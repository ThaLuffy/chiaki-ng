// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Metal
import MetalKit
import CoreVideo
import os.lock
import QuartzCore
import UIKit

/// Renders `CVPixelBuffer`s (NV12 SDR or P010 HDR10) to a `CAMetalLayer`.
/// Single-slot drop-newest hand-off between the decoder thread (writer)
/// and the `CAMetalDisplayLink` callback (reader).
///
/// Why a raw `CAMetalLayer` + `CAMetalDisplayLink` instead of `MTKView`:
/// MTKView wraps `CADisplayLink` and only gives us a tick — we then have to
/// call `nextDrawable()` ourselves, which blocks waiting on the compositor
/// when the drawable pool is exhausted. `CAMetalDisplayLink` (tvOS 17+)
/// hands the delegate a drawable that's already been allocated for the
/// next vsync, plus `targetPresentationTimestamp`. That tightens vsync
/// alignment and keeps the renderer off the path of compositor stalls.
/// See `docs/optimization/native-alternatives-latency-first.md` Phase A.6.
///
/// Pipeline:
///   - Bind the CVPixelBuffer's two planes via `CVMetalTextureCache` →
///     two `MTLTexture`s (Y, CbCr). 8-bit for NV12, 16-bit for P010.
///   - Render a fullscreen triangle strip with `fs_nv12` (SDR) or
///     `fs_p010_hdr` (HDR10) — see `VideoShaders.metal`.
///   - Present at the next vsync via the layer's drawable.
///
/// Mode negotiation:
///   The decoder calls `prepare(forHDR:)` *before* the first frame so
///   the layer's `pixelFormat` and `colorspace` are set correctly.
final class MetalRenderer: NSObject {

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var sdrPipelineState: MTLRenderPipelineState?
    private var hdrPipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?

    // The CAMetalLayer the renderer draws into. Set by `attach(to:)`.
    private weak var attachedLayer: CAMetalLayer?
    private var displayLink: AnyObject? // CAMetalDisplayLink (tvOS 17+); type-erased to avoid availability noise.

    /// Single-slot drop-newest. The decoder thread writes; the display-link
    /// callback reads. CVPixelBuffer isn't Sendable so we wrap in @unchecked.
    private struct Slot: @unchecked Sendable { var buffer: CVPixelBuffer? }
    private let pending = OSAllocatedUnfairLock<Slot>(initialState: .init(buffer: nil))

    /// Snapshot of the last format successfully rendered — used for diagnostics.
    private(set) var lastWidth: Int = 0
    private(set) var lastHeight: Int = 0

    /// Whether the next session is HDR. Locked at `prepare(forHDR:)` time.
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

    /// Attach the renderer to a CAMetalLayer. Configures the layer for
    /// SDR / HDR output and starts a `CAMetalDisplayLink` driving presents
    /// at the layer's vsync.
    func attach(to layer: CAMetalLayer) {
        layer.device = device
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 2  // see latency-strategy.md
        attachedLayer = layer
        applyHDRConfig(to: layer)
        startDisplayLink(for: layer)
    }

    /// Tear down the display link and detach. Idempotent.
    func detach() {
        stopDisplayLink()
        attachedLayer = nil
    }

    /// Lock the renderer into SDR or HDR mode for the upcoming session.
    /// Must be called *before* the first `present`.
    func prepare(forHDR hdr: Bool) {
        if hdrEnabled == hdr { return }
        hdrEnabled = hdr
        if let layer = attachedLayer {
            applyHDRConfig(to: layer)
        }
    }

    // MARK: - Display-link plumbing

    private func startDisplayLink(for layer: CAMetalLayer) {
        stopDisplayLink()
        if #available(tvOS 17.0, *) {
            let link = CAMetalDisplayLink(metalLayer: layer)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            link.delegate = self
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    private func stopDisplayLink() {
        if #available(tvOS 17.0, *), let link = displayLink as? CAMetalDisplayLink {
            link.invalidate()
        }
        displayLink = nil
    }

    /// Render the currently-pending pixel buffer into `drawable` and
    /// schedule it for `targetPresentationTimestamp`. Called from the
    /// display-link delegate at vsync cadence.
    fileprivate func drawIntoDrawable(_ drawable: CAMetalDrawable,
                                      targetPresentationTimestamp: CFTimeInterval)
    {
        let snap = pending.withLock { $0 }
        guard let pixelBuffer = snap.buffer else { return }
        guard let textureCache = textureCache,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let pipelineState = hdrEnabled ? hdrPipelineState : sdrPipelineState
        guard let pipelineState = pipelineState else { return }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        lastWidth = width
        lastHeight = height

        let isP010 = Self.isP010(pixelBuffer)
        let yFormat: MTLPixelFormat = isP010 ? .r16Unorm : .r8Unorm
        let uvFormat: MTLPixelFormat = isP010 ? .rg16Unorm : .rg8Unorm

        guard let yTex = makePlaneTexture(pixelBuffer: pixelBuffer, plane: 0,
                                          format: yFormat, textureCache: textureCache),
              let uvTex = makePlaneTexture(pixelBuffer: pixelBuffer, plane: 1,
                                           format: uvFormat, textureCache: textureCache) else {
            encoder.endEncoding()
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(yTex, index: 0)
        encoder.setFragmentTexture(uvTex, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        // Schedule for the predicted vsync rather than ASAP — the display
        // link gave us this drawable specifically for this timestamp.
        commandBuffer.present(drawable, atTime: targetPresentationTimestamp)
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

    /// Configure the layer's pixel format + colorspace for the current HDR
    /// mode. Idempotent — safe to call before/after attach.
    ///
    /// On tvOS, HDR delivery is gated by (a) the layer's colorspace
    /// (`itur_2100_PQ` makes the compositor treat outgoing 10-bit values as
    /// PQ-encoded) and (b) `AVDisplayManager.preferredDisplayCriteria` set
    /// in `StreamMetalView`. There is no `wantsExtendedDynamicRangeContent`
    /// flag here — that's iOS/macOS only — and a 10-bit drawable is enough
    /// for the Apple TV's HDMI link.
    private func applyHDRConfig(to layer: CAMetalLayer) {
        if hdrEnabled {
            layer.pixelFormat = .bgr10a2Unorm
            layer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)
        } else {
            layer.pixelFormat = .bgra8Unorm
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
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

// MARK: - CAMetalDisplayLinkDelegate (tvOS 17+)

@available(tvOS 17.0, *)
extension MetalRenderer: CAMetalDisplayLinkDelegate {
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        drawIntoDrawable(update.drawable,
                         targetPresentationTimestamp: update.targetPresentationTimestamp)
    }
}
