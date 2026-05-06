// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Metal
import MetalKit
import CoreVideo
import os.lock
import QuartzCore

/// Renders `CVPixelBuffer`s (NV12 SDR or P010 HDR10) as an MTKView.
/// Single-slot drop-newest hand-off between the decoder thread (writer)
/// and the MTKView display callback (reader).
///
/// Pipeline:
///   - Bind the CVPixelBuffer's two planes via `CVMetalTextureCache` →
///     two `MTLTexture`s (Y, CbCr). Plane format is 8-bit for NV12, 16-bit
///     for P010 — the decoder hands us the right pixel format based on
///     the negotiated codec.
///   - Render a fullscreen triangle strip with `fs_nv12` (SDR) or
///     `fs_p010_hdr` (HDR10) — see `VideoShaders.metal`.
///   - Present at the next vsync via the MTKView's draw callback.
///
/// Mode negotiation:
///   The decoder calls `prepare(forCodec:)` *before* the first frame so
///   the MTKView's `colorPixelFormat` and the layer's `colorspace` are
///   set correctly. Switching colorspace mid-stream would briefly drop
///   to SDR while the layer reconfigures, so we lock the choice for the
///   life of a session.
///
/// References:
///   - `docs/architecture/video-pipeline.md`
final class MetalRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var sdrPipelineState: MTLRenderPipelineState?
    private var hdrPipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private weak var attachedView: MTKView?

    /// Single-slot drop-newest. The decoder thread writes; the MTKView
    /// callback reads. CVPixelBuffer isn't Sendable so we wrap in @unchecked.
    private struct Slot: @unchecked Sendable { var buffer: CVPixelBuffer? }
    private let pending = OSAllocatedUnfairLock<Slot>(initialState: .init(buffer: nil))

    /// Snapshot of the last format successfully rendered — used for diagnostics.
    private(set) var lastWidth: Int = 0
    private(set) var lastHeight: Int = 0

    /// Whether the next session is HDR. Locked at `prepare(forHDR:)` time
    /// and applied to the attached MTKView. Both the renderer and the
    /// SwiftUI layer (`StreamMetalView`) read it.
    private(set) var hdrEnabled: Bool = false

    override init() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device — required for tvOS port")
        }
        guard let queue = dev.makeCommandQueue() else {
            fatalError("Could not create Metal command queue")
        }
        self.device = dev
        self.commandQueue = queue
        super.init()
        try? buildTextureCache()
        try? buildPipelines()
    }

    /// Push a freshly-decoded pixel buffer for the next draw. Drop-newest:
    /// if a previous buffer hasn't been drawn yet, it's discarded.
    func present(_ pixelBuffer: CVPixelBuffer) {
        let snap = Slot(buffer: pixelBuffer)
        pending.withLock { $0 = snap }
    }

    func attach(to view: MTKView) {
        view.device = device
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = self
        attachedView = view
        applyHDRConfig(to: view)
    }

    /// Lock the renderer into SDR or HDR mode for the upcoming session.
    /// Must be called *before* the first `present`. The decoder calls this
    /// from the session bring-up path once the codec is known.
    func prepare(forHDR hdr: Bool) {
        if hdrEnabled == hdr { return }
        hdrEnabled = hdr
        if let view = attachedView {
            applyHDRConfig(to: view)
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // CAMetalLayer drives drawable allocation; nothing to do.
    }

    func draw(in view: MTKView) {
        let snap = pending.withLock { $0 }
        guard let pixelBuffer = snap.buffer else { return }
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        guard let textureCache = textureCache,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        let pipelineState = hdrEnabled ? hdrPipelineState : sdrPipelineState
        guard let pipelineState = pipelineState else { return }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        lastWidth = width
        lastHeight = height

        // Plane format depends on whether the source is NV12 (8-bit) or
        // P010 (16-bit). Querying the buffer is cheaper than threading
        // codec state through the renderer and lets the renderer recover
        // gracefully if something hands it the "wrong" buffer for its mode.
        let isP010 = Self.isP010(pixelBuffer)
        let yFormat: MTLPixelFormat = isP010 ? .r16Unorm : .r8Unorm
        let uvFormat: MTLPixelFormat = isP010 ? .rg16Unorm : .rg8Unorm

        guard let yTex = makePlaneTexture(pixelBuffer: pixelBuffer,
                                          plane: 0,
                                          format: yFormat,
                                          textureCache: textureCache),
              let uvTex = makePlaneTexture(pixelBuffer: pixelBuffer,
                                           plane: 1,
                                           format: uvFormat,
                                           textureCache: textureCache) else {
            encoder.endEncoding()
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(yTex, index: 0)
        encoder.setFragmentTexture(uvTex, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        // Flush stale CV cache entries periodically.
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    // MARK: - Private setup

    private func buildTextureCache() throws {
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(
            kCFAllocatorDefault, nil, device, nil, &cache
        )
        guard status == kCVReturnSuccess, let c = cache else {
            chiakiLog("MetalRenderer: CVMetalTextureCacheCreate failed (\(status))",
                      category: .video, type: .error)
            return
        }
        self.textureCache = c
    }

    private func buildPipelines() throws {
        guard let library = try? device.makeDefaultLibrary(bundle: .main),
              let vs = library.makeFunction(name: "vs_quad"),
              let fsSdr = library.makeFunction(name: "fs_nv12"),
              let fsHdr = library.makeFunction(name: "fs_p010_hdr") else {
            chiakiLog("MetalRenderer: shader functions not found in default library",
                      category: .video, type: .error)
            return
        }

        let sdrDesc = MTLRenderPipelineDescriptor()
        sdrDesc.vertexFunction = vs
        sdrDesc.fragmentFunction = fsSdr
        sdrDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        let hdrDesc = MTLRenderPipelineDescriptor()
        hdrDesc.vertexFunction = vs
        hdrDesc.fragmentFunction = fsHdr
        hdrDesc.colorAttachments[0].pixelFormat = .bgr10a2Unorm

        do {
            sdrPipelineState = try device.makeRenderPipelineState(descriptor: sdrDesc)
            hdrPipelineState = try device.makeRenderPipelineState(descriptor: hdrDesc)
        } catch {
            chiakiLog("MetalRenderer: makeRenderPipelineState failed: \(error)",
                      category: .video, type: .error)
        }
    }

    /// Configure the MTKView's drawable format + colorspace for the current
    /// HDR mode. Idempotent — safe to call before/after attach.
    ///
    /// On tvOS, HDR delivery is gated by (a) the layer's colorspace
    /// (`itur_2100_PQ` makes the compositor treat outgoing 10-bit values as
    /// PQ-encoded) and (b) `AVDisplayManager.preferredDisplayCriteria` set
    /// in `StreamMetalView`. There is no `wantsExtendedDynamicRangeContent`
    /// flag here — that's iOS/macOS only — and a 10-bit drawable is enough
    /// for the Apple TV's HDMI link.
    private func applyHDRConfig(to view: MTKView) {
        if hdrEnabled {
            view.colorPixelFormat = .bgr10a2Unorm
            if let layer = view.layer as? CAMetalLayer {
                layer.pixelFormat = .bgr10a2Unorm
                layer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)
            }
        } else {
            view.colorPixelFormat = .bgra8Unorm
            if let layer = view.layer as? CAMetalLayer {
                layer.pixelFormat = .bgra8Unorm
                layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            }
        }
    }

    private func makePlaneTexture(
        pixelBuffer: CVPixelBuffer,
        plane: Int,
        format: MTLPixelFormat,
        textureCache: CVMetalTextureCache
    ) -> MTLTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            format,
            width,
            height,
            plane,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cv = cvTexture else {
            return nil
        }
        return CVMetalTextureGetTexture(cv)
    }

    private static func isP010(_ buffer: CVPixelBuffer) -> Bool {
        let fmt = CVPixelBufferGetPixelFormatType(buffer)
        return fmt == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            || fmt == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
    }
}
