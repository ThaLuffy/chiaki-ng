// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Hardware-accelerated VideoToolbox decoder fed by the chiaki video sample
/// bridge. The chiaki side (`lib/src/videoreceiver.c`) already handles
/// FEC reassembly, frame reordering, and reference-frame invalidation,
/// so this decoder is intentionally minimal:
///
///   - Walk Annex-B start codes → AVCC length-prefix in place.
///   - Extract VPS/SPS/PPS on the first NAL of each kind; rebuild the
///     `CMFormatDescription` + `VTDecompressionSession` on parameter-set change.
///   - Synchronously decode each access unit; output `CVPixelBuffer` to a
///     caller-supplied delegate.
///
/// References:
///   - `docs/architecture/video-pipeline.md`
///   - `gui/src/qmlbackend.cpp:videotoolbox` (desktop reference for the
///     decoder selection on macOS)
///   - Sibling: `../../ps-remote-play/PSSwiftPlay/Services/Streaming/VideoDecoder.swift`
final class VideoDecoder: @unchecked Sendable {

    enum Codec {
        case h264
        case h265
        case h265HDR
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

    /// Submit a NAL-unit buffer (Annex-B framing) for decode. Runs the work
    /// on the decoder queue so the chiaki video receiver thread isn't blocked
    /// by VT.
    func submit(_ buffer: UnsafeBufferPointer<UInt8>, codec: Codec) {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return }
        // Copy into a Swift Data — chiaki releases the buffer when the
        // callback returns. The decoder runs synchronously inside this same
        // call (chiaki's contract), so allocation is per-frame; future
        // optimization is to switch to a malloc'd ring + zero-copy walk.
        let data = Data(bytes: base, count: buffer.count)
        decoderQueue.async { [weak self] in
            self?.decodeData(data, codec: codec)
        }
    }

    /// Synchronous variant — runs the entire walk + decode on the calling
    /// thread. The chiaki video sample callback runs on chiaki's video
    /// receiver thread which is already isolated from MainActor; calling
    /// VT synchronously there avoids the per-frame queue hop. Use this for
    /// the hot path; use `submit` for ad-hoc Swift code paths.
    func submitSynchronously(_ buffer: UnsafeBufferPointer<UInt8>, codec: Codec) -> Bool {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return false }
        let data = Data(bytes: base, count: buffer.count)
        return decodeData(data, codec: codec)
    }

    // MARK: - Private

    private let decoderQueue = DispatchQueue(
        label: "org.streetpea.chiakitv.video.decoder",
        qos: .userInteractive
    )

    private var session: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?
    private var currentCodec: Codec = .h265

    private var cachedVPS: Data?
    private var cachedSPS: Data?
    private var cachedPPS: Data?

    /// Returns true if the frame produced output. Errors are logged but not
    /// propagated — chiaki retries on its own when needed.
    @discardableResult
    private func decodeData(_ data: Data, codec: Codec) -> Bool {
        currentCodec = codec
        // `var` (not `let`) is load-bearing here: the `defer` below reads
        // `walked.avccBuffer` to free it on early returns, and we clear that
        // field after handing ownership to a CMBlockBuffer. Swift `defer`
        // sees mutations to the captured `var` but NOT mutations made to a
        // separate copy of the struct — see report 2026-05-05-17-47-run1.md.
        var walked = walkAnnexB(data, codec: codec)
        defer {
            if let buf = walked.avccBuffer { free(buf) }
        }

        // Rebuild session on parameter-set change (or first sight).
        if walked.parameterSetsChanged, let sps = walked.sps, let pps = walked.pps {
            do {
                try refreshFormatDescription(vps: walked.vps, sps: sps, pps: pps, codec: codec)
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

        guard walked.hasSlice else { return false }
        guard let avccBuffer = walked.avccBuffer, walked.avccSize > 0 else { return false }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: avccBuffer,
            blockLength: walked.avccSize,
            blockAllocator: kCFAllocatorMalloc,   // CoreMedia takes ownership + free's
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: walked.avccSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let block = blockBuffer else { return false }
        // Ownership transferred to the block buffer; clear so the defer
        // doesn't double-free. Mutating `walked` directly (not a copy) is
        // what the deferred read above will see.
        walked.avccBuffer = nil

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

    private func refreshFormatDescription(
        vps: Data?, sps: Data, pps: Data, codec: Codec
    ) throws {
        if cachedVPS == vps, cachedSPS == sps, cachedPPS == pps, session != nil {
            return  // no-op
        }
        cachedVPS = vps
        cachedSPS = sps
        cachedPPS = pps

        invalidateSession()

        let formatDesc = try buildFormatDescription(vps: vps, sps: sps, pps: pps, codec: codec)
        formatDescription = formatDesc
        try buildDecompressionSession(formatDesc: formatDesc, codec: codec)

        chiakiLog("VideoDecoder: rebuilt session (codec=\(codec) vps=\(vps?.count ?? 0)B sps=\(sps.count)B pps=\(pps.count)B)",
                  category: .video, type: .info)
        onFormatDescriptionReady?(formatDesc)
    }

    private func buildFormatDescription(
        vps: Data?, sps: Data, pps: Data, codec: Codec
    ) throws -> CMFormatDescription {
        var formatDesc: CMFormatDescription?
        let status: OSStatus
        if codec == .h265 || codec == .h265HDR {
            guard let vps = vps else {
                throw VideoDecoderError.invalidParameterSets
            }
            let sets: [Data] = [vps, sps, pps]
            // For HDR10 we tag the format description with BT.2020 / SMPTE
            // 2084 (PQ) / BT.2020-NCL so VideoToolbox decodes into a properly
            // colorspace-tagged CVPixelBuffer and AVDisplayManager can match
            // an AVDisplayCriteria from this same description.
            let extensions: CFDictionary? = (codec == .h265HDR)
                ? Self.hdr10ExtensionsDictionary()
                : nil
            status = sets.withContiguousUnsafeBuffers { buffers in
                let pointers = buffers.map { $0.baseAddress! }
                let sizes = buffers.map { $0.count }
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
        } else {
            let sets: [Data] = [sps, pps]
            status = sets.withContiguousUnsafeBuffers { buffers in
                let pointers = buffers.map { $0.baseAddress! }
                let sizes = buffers.map { $0.count }
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

    // MARK: - Annex-B walker

    private struct AnnexBWalk {
        var avccBuffer: UnsafeMutableRawPointer?
        var avccSize: Int
        var vps: Data?
        var sps: Data?
        var pps: Data?
        var hasSlice: Bool
        var parameterSetsChanged: Bool
    }

    private func walkAnnexB(_ data: Data, codec: Codec) -> AnnexBWalk {
        var result = AnnexBWalk(
            avccBuffer: nil, avccSize: 0,
            vps: nil, sps: nil, pps: nil,
            hasSlice: false, parameterSetsChanged: false
        )

        return data.withUnsafeBytes { rawBuf -> AnnexBWalk in
            guard let base = rawBuf.baseAddress else { return result }
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let n = rawBuf.count

            // Pass 1 — find start codes.
            var starts: [(prefixLen: Int, nalStart: Int)] = []
            starts.reserveCapacity(8)
            var i = 0
            while i + 2 < n {
                if bytes[i] == 0 && bytes[i + 1] == 0 {
                    if bytes[i + 2] == 0x01 {
                        starts.append((3, i + 3))
                        i += 3
                        continue
                    } else if bytes[i + 2] == 0 && i + 3 < n && bytes[i + 3] == 0x01 {
                        starts.append((4, i + 4))
                        i += 4
                        continue
                    }
                }
                i += 1
            }

            // Pass 2 — classify and total AVCC size.
            var ranges: [(start: Int, len: Int)] = []
            ranges.reserveCapacity(starts.count)
            var total = 0
            for k in 0..<starts.count {
                let nalStart = starts[k].nalStart
                let nalEnd = (k + 1 < starts.count) ? (starts[k + 1].nalStart - starts[k + 1].prefixLen) : n
                guard nalEnd > nalStart, nalEnd <= n else { continue }
                let len = nalEnd - nalStart
                ranges.append((nalStart, len))
                total += 4 + len

                let header = bytes[nalStart]
                if codec == .h265 || codec == .h265HDR {
                    let nalType = (header >> 1) & 0x3F
                    switch nalType {
                    case 32: result.vps = Data(bytes: bytes + nalStart, count: len)
                    case 33: result.sps = Data(bytes: bytes + nalStart, count: len)
                    case 34: result.pps = Data(bytes: bytes + nalStart, count: len)
                    case 16...23: result.hasSlice = true   // IDR / BLA / CRA
                    case 0...9:   result.hasSlice = true   // trail / TSA / STSA
                    default: break
                    }
                } else {
                    let nalType = header & 0x1F
                    switch nalType {
                    case 7: result.sps = Data(bytes: bytes + nalStart, count: len)
                    case 8: result.pps = Data(bytes: bytes + nalStart, count: len)
                    case 5, 1: result.hasSlice = true
                    default: break
                    }
                }
            }

            // Did parameter sets change vs cache?
            if let sps = result.sps, let pps = result.pps {
                let vpsChanged = (codec == .h265 || codec == .h265HDR) && (result.vps != cachedVPS)
                result.parameterSetsChanged = vpsChanged
                    || sps != cachedSPS
                    || pps != cachedPPS
            }

            // Pass 3 — single malloc for AVCC buffer, write length-prefixed NALs.
            guard total > 0 else { return result }
            let buf = malloc(total)!.assumingMemoryBound(to: UInt8.self)
            var off = 0
            for nal in ranges {
                let len = UInt32(nal.len)
                buf[off    ] = UInt8((len >> 24) & 0xFF)
                buf[off + 1] = UInt8((len >> 16) & 0xFF)
                buf[off + 2] = UInt8((len >>  8) & 0xFF)
                buf[off + 3] = UInt8( len        & 0xFF)
                off += 4
                memcpy(buf + off, bytes + nal.start, nal.len)
                off += nal.len
            }
            result.avccBuffer = UnsafeMutableRawPointer(buf)
            result.avccSize = total
            return result
        }
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

// MARK: - Helper for parameter-set marshaling

private extension Array where Element == Data {
    func withContiguousUnsafeBuffers<R>(
        _ body: ([UnsafeBufferPointer<UInt8>]) -> R
    ) -> R {
        func recurse(index: Int, accumulated: [UnsafeBufferPointer<UInt8>]) -> R {
            if index == count { return body(accumulated) }
            return self[index].withUnsafeBytes { rawPtr in
                let typed = rawPtr.bindMemory(to: UInt8.self)
                var next = accumulated
                next.append(typed)
                return recurse(index: index + 1, accumulated: next)
            }
        }
        return recurse(index: 0, accumulated: [])
    }
}
