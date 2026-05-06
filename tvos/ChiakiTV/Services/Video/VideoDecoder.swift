// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo
import ChiakiBridgeC

/// Hardware-accelerated VideoToolbox decoder fed by the chiaki video sample
/// bridge. The chiaki side (`lib/src/videoreceiver.c`) already handles
/// FEC reassembly, frame reordering, and reference-frame invalidation,
/// so this decoder is intentionally minimal:
///
///   - Annex-B → AVCC walking is delegated to `chiaki_tv_walk_annex_b` in
///     `ChiakiBridgeC` so the per-frame `Data` allocation Swift would
///     otherwise do is eliminated. See
///     `docs/optimization/native-alternatives-latency-first.md` Phase A.2.
///   - Extract VPS/SPS/PPS on the first NAL of each kind; rebuild the
///     `CMFormatDescription` + `VTDecompressionSession` on parameter-set change.
///   - Synchronously decode each access unit; output `CVPixelBuffer` to a
///     caller-supplied delegate.
///
/// References:
///   - `docs/architecture/video-pipeline.md`
///   - `gui/src/qmlbackend.cpp:videotoolbox` (desktop reference for the
///     decoder selection on macOS)
final class VideoDecoder: @unchecked Sendable {

    enum Codec {
        case h264
        case h265
        case h265HDR

        fileprivate var bridgeValue: chiaki_tv_video_codec_t {
            switch self {
            case .h264:    return CHIAKI_TV_VIDEO_CODEC_H264
            case .h265:    return CHIAKI_TV_VIDEO_CODEC_H265
            case .h265HDR: return CHIAKI_TV_VIDEO_CODEC_H265_HDR
            }
        }
    }

    // MARK: - Public

    /// Fires from the decode queue with each decoded `CVPixelBuffer`. The
    /// renderer should consume immediately (single-slot, drop-newest).
    var onPixelBuffer: ((CVPixelBuffer) -> Void)?

    /// Fires when a new `CMFormatDescription` is built (first prime, or
    /// after a parameter-set swap). Owner uses this to drive
    /// `AVDisplayManager.preferredDisplayCriteria` for HDR / refresh-rate.
    var onFormatDescriptionReady: ((CMFormatDescription) -> Void)?

    init() {}

    deinit {
        invalidateSession()
    }

    /// Synchronous decode — runs the walk + VT decode on the calling thread.
    /// The chiaki video sample callback runs on chiaki's video receiver
    /// thread which is already isolated from MainActor; calling VT
    /// synchronously there avoids a per-frame queue hop.
    func submitSynchronously(_ buffer: UnsafeBufferPointer<UInt8>, codec: Codec) -> Bool {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return false }
        return decodeBuffer(base: base, count: buffer.count, codec: codec)
    }

    // MARK: - Private

    private var session: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?
    private var currentCodec: Codec = .h265

    private var cachedVPS: [UInt8]?
    private var cachedSPS: [UInt8]?
    private var cachedPPS: [UInt8]?

    /// Returns true if the frame produced output. Errors are logged but not
    /// propagated — chiaki retries on its own when needed.
    @discardableResult
    private func decodeBuffer(base: UnsafePointer<UInt8>, count: Int, codec: Codec) -> Bool {
        currentCodec = codec

        // C-side walker writes AVCC framing into a fresh malloc'd buffer
        // and gives us pointers into the caller's input buffer for any
        // VPS/SPS/PPS NALs found. No per-frame Swift `Data` allocation.
        var walked = chiaki_tv_avcc_walk_t()
        let ok = chiaki_tv_walk_annex_b(base, count, codec.bridgeValue, &walked)
        guard ok else { return false }

        // Free the AVCC buffer on early-return paths. After we hand it to
        // CMBlockBuffer with kCFAllocatorMalloc, set this to nil to skip the
        // free (CoreMedia owns it then).
        var avccOwned: UnsafeMutablePointer<UInt8>? = walked.avcc_buf
        defer {
            if let p = avccOwned { free(p) }
        }

        // Detect parameter-set changes and rebuild session if needed.
        // Parameter-set NALs come either out-of-band (no slice — pre-warm
        // path from `lib/src/videoreceiver.c:140-141`) or inline with an IDR.
        if let parameterSetsChanged = updateCachedParameterSets(walked: walked, codec: codec),
           parameterSetsChanged,
           let sps = cachedSPS, let pps = cachedPPS {
            do {
                try refreshFormatDescription(vps: cachedVPS, sps: sps, pps: pps, codec: codec)
            } catch {
                chiakiLog("VideoDecoder: refreshFormatDescription failed: \(error)",
                          category: .video, type: .error)
                return false
            }
        }

        guard let session = session,
              let formatDesc = formatDescription else {
            return false
        }

        guard walked.has_slice else { return false }
        guard let avccBuffer = walked.avcc_buf, walked.avcc_size > 0 else { return false }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: avccBuffer,
            blockLength: walked.avcc_size,
            blockAllocator: kCFAllocatorMalloc,   // CoreMedia takes ownership + free's
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: walked.avcc_size,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let block = blockBuffer else { return false }
        // Ownership transferred to the block buffer; clear so the defer
        // doesn't double-free.
        avccOwned = nil

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        )
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sample = sampleBuffer else { return false }

        // DisplayImmediately tells VideoToolbox to bypass its internal
        // reorder-for-display buffering — the PS5 stream is already in
        // presentation order, so any reordering VT does is pure latency.
        // See `docs/optimization/native-alternatives-latency-first.md` Phase A.3.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            let key = Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
            let value = Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            CFDictionarySetValue(dict, key, value)
        }

        var produced: CVPixelBuffer?
        var info = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [],
            infoFlagsOut: &info
        ) { decodeStatus, _, imageBuffer, _, _ in
            if decodeStatus == noErr, let buf = imageBuffer {
                produced = buf
            }
        }

        if status != noErr {
            chiakiLog("VideoDecoder: VTDecompressionSessionDecodeFrame status=\(status)",
                      category: .video, type: .error)
            return false
        }
        if let pixel = produced {
            onPixelBuffer?(pixel)
            return true
        }
        return false
    }

    /// Returns nil if the buffer carried no parameter sets at all (so no
    /// change-detection comparison was possible). Returns true/false to
    /// indicate whether the cached parameter sets changed.
    private func updateCachedParameterSets(
        walked: chiaki_tv_avcc_walk_t,
        codec: Codec
    ) -> Bool? {
        let vps = walked.vps_ptr.map { Array(UnsafeBufferPointer(start: $0, count: walked.vps_len)) }
        let sps = walked.sps_ptr.map { Array(UnsafeBufferPointer(start: $0, count: walked.sps_len)) }
        let pps = walked.pps_ptr.map { Array(UnsafeBufferPointer(start: $0, count: walked.pps_len)) }

        // No parameter sets at all → caller can't make a session decision
        // from this submission alone (we may still have a cached session
        // from an earlier prime).
        if sps == nil && pps == nil && vps == nil { return nil }

        let needHDRVPS = (codec == .h265 || codec == .h265HDR)
        var changed = false

        if needHDRVPS, let v = vps, v != cachedVPS {
            cachedVPS = v
            changed = true
        }
        if let s = sps, s != cachedSPS {
            cachedSPS = s
            changed = true
        }
        if let p = pps, p != cachedPPS {
            cachedPPS = p
            changed = true
        }
        return changed
    }

    private func refreshFormatDescription(
        vps: [UInt8]?, sps: [UInt8], pps: [UInt8], codec: Codec
    ) throws {
        invalidateSession()

        let formatDesc = try buildFormatDescription(vps: vps, sps: sps, pps: pps, codec: codec)
        formatDescription = formatDesc
        try buildDecompressionSession(formatDesc: formatDesc, codec: codec)

        chiakiLog("VideoDecoder: rebuilt session (codec=\(codec) vps=\(vps?.count ?? 0)B sps=\(sps.count)B pps=\(pps.count)B)",
                  category: .video, type: .info)
        onFormatDescriptionReady?(formatDesc)
    }

    private func buildFormatDescription(
        vps: [UInt8]?, sps: [UInt8], pps: [UInt8], codec: Codec
    ) throws -> CMFormatDescription {
        var formatDesc: CMFormatDescription?
        let status: OSStatus
        if codec == .h265 || codec == .h265HDR {
            guard let vps = vps else {
                throw VideoDecoderError.invalidParameterSets
            }
            // For HDR10 we tag the format description with BT.2020 / SMPTE
            // 2084 (PQ) / BT.2020-NCL so VideoToolbox decodes into a properly
            // colorspace-tagged CVPixelBuffer and AVDisplayManager can match
            // an AVDisplayCriteria from this same description.
            let extensions: CFDictionary? = (codec == .h265HDR)
                ? Self.hdr10ExtensionsDictionary()
                : nil
            status = vps.withUnsafeBufferPointer { vpsBuf in
                sps.withUnsafeBufferPointer { spsBuf in
                    pps.withUnsafeBufferPointer { ppsBuf in
                        let pointers: [UnsafePointer<UInt8>] = [vpsBuf.baseAddress!, spsBuf.baseAddress!, ppsBuf.baseAddress!]
                        let sizes: [Int] = [vps.count, sps.count, pps.count]
                        return pointers.withUnsafeBufferPointer { ptrBuf in
                            sizes.withUnsafeBufferPointer { sizeBuf in
                                CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                                    allocator: kCFAllocatorDefault,
                                    parameterSetCount: 3,
                                    parameterSetPointers: ptrBuf.baseAddress!,
                                    parameterSetSizes: sizeBuf.baseAddress!,
                                    nalUnitHeaderLength: 4,
                                    extensions: extensions,
                                    formatDescriptionOut: &formatDesc
                                )
                            }
                        }
                    }
                }
            }
        } else {
            status = sps.withUnsafeBufferPointer { spsBuf in
                pps.withUnsafeBufferPointer { ppsBuf in
                    let pointers: [UnsafePointer<UInt8>] = [spsBuf.baseAddress!, ppsBuf.baseAddress!]
                    let sizes: [Int] = [sps.count, pps.count]
                    return pointers.withUnsafeBufferPointer { ptrBuf in
                        sizes.withUnsafeBufferPointer { sizeBuf in
                            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                                allocator: kCFAllocatorDefault,
                                parameterSetCount: 2,
                                parameterSetPointers: ptrBuf.baseAddress!,
                                parameterSetSizes: sizeBuf.baseAddress!,
                                nalUnitHeaderLength: 4,
                                formatDescriptionOut: &formatDesc
                            )
                        }
                    }
                }
            }
        }
        guard status == noErr, let desc = formatDesc else {
            throw VideoDecoderError.formatFailed(status)
        }
        return desc
    }

    /// HDR10 colorimetry extensions for `CMVideoFormatDescriptionCreate*`.
    /// The PS5 emits HDR streams in BT.2020 + SMPTE-2084 PQ + BT.2020-NCL
    /// matrix — this is the only HDR mode the protocol negotiates (see
    /// `lib/src/launchspec.c:81` `dynamicRange:HDR`). Tagging the format
    /// description here propagates to the decoded `CVImageBuffer` so the
    /// renderer can pick the right colorspace and `AVDisplayManager` can
    /// derive `AVDisplayCriteria(refreshRate:formatDescription:)` correctly.
    private static func hdr10ExtensionsDictionary() -> CFDictionary {
        let colorAttachments: [CFString: Any] = [
            kCVImageBufferColorPrimariesKey:    kCVImageBufferColorPrimaries_ITU_R_2020,
            kCVImageBufferTransferFunctionKey:  kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
            kCVImageBufferYCbCrMatrixKey:       kCVImageBufferYCbCrMatrix_ITU_R_2020,
        ]
        return colorAttachments as CFDictionary
    }

    private func buildDecompressionSession(
        formatDesc: CMFormatDescription, codec: Codec
    ) throws {
        let pixelFormat: OSType = codec == .h265HDR
            ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

        let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: Int(dims.width),
            kCVPixelBufferHeightKey as String: Int(dims.height),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        let spec: [String: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true,
        ]

        var sess: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: spec as CFDictionary,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &sess
        )
        guard status == noErr, let s = sess else {
            throw VideoDecoderError.sessionFailed(status)
        }
        VTSessionSetProperty(s, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(
            s,
            key: kVTDecompressionPropertyKey_OutputPoolRequestedMinimumBufferCount,
            value: 2 as CFNumber
        )
        session = s
    }

    private func invalidateSession() {
        if let s = session {
            VTDecompressionSessionInvalidate(s)
            session = nil
        }
        formatDescription = nil
    }
}

// MARK: - Errors

enum VideoDecoderError: Error, LocalizedError {
    case invalidParameterSets
    case formatFailed(OSStatus)
    case sessionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidParameterSets: return "Missing VPS/SPS/PPS for codec"
        case .formatFailed(let s):  return "CMFormatDescription create failed: \(s)"
        case .sessionFailed(let s): return "VTDecompressionSessionCreate failed: \(s)"
        }
    }
}
