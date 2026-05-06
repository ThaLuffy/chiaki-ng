// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Metal
import MetalKit
import CoreVideo
import os.lock

/// Renders `CVPixelBuffer`s (NV12 or P010 video-range) as an MTKView.
/// Single-slot drop-newest hand-off between the decoder thread (writer)
/// and the MTKView display callback (reader).
///
/// Pipeline:
///   - Bind the CVPixelBuffer's two planes via `CVMetalTextureCache` →
///     two `MTLTexture`s (Y, CbCr).
///   - Render a fullscreen triangle strip with `fs_nv12` (see
///     `VideoShaders.metal`).
///   - Present at the next vsync via the MTKView's draw callback.
///
/// References:
///   - `docs/architecture/video-pipeline.md`
///   - Sibling: `../../ps-remote-play/PSSwiftPlay/Services/Streaming/MetalRenderer.swift`
final class MetalRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?

    /// Single-slot drop-newest. The decoder thread writes; the MTKView
    /// callback reads. CVPixelBuffer isn't Sendable so we wrap in @unchecked.
    private struct Slot: @unchecked Sendable { var buffer: CVPixelBuffer? }
    private let pending = OSAllocatedUnfairLock<Slot>(initialState: .init(buffer: nil))

    /// Snapshot of the last format successfully rendered — used for diagnostics.
    private(set) var lastWidth: Int = 0
    private(set) var lastHeight: Int = 0

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
        try? buildPipeline()
    }

    /// Push a freshly-decoded pixel buffer for the next draw. Drop-newest:
    /// if a previous buffer hasn't been drawn yet, it's discarded.
    func present(_ pixelBuffer: CVPixelBuffer) {
        let snap = Slot(buffer: pixelBuffer)
        pending.withLock { $0 = snap }
    }

    func attach(to view: MTKView) {
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = self
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
        guard let pipelineState = pipelineState,
              let textureCache = textureCache,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        lastWidth = width
        lastHeight = height

        // Bind plane 0 (Y) and plane 1 (CbCr).
        guard let yTex = makePlaneTexture(pixelBuffer: pixelBuffer,
                                          plane: 0,
                                          format: .r8Unorm,
                                          textureCache: textureCache),
              let uvTex = makePlaneTexture(pixelBuffer: pixelBuffer,
                                           plane: 1,
                                           format: .rg8Unorm,
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

    private func buildPipeline() throws {
        guard let library = try? device.makeDefaultLibrary(bundle: .main),
              let vs = library.makeFunction(name: "vs_quad"),
              let fs = library.makeFunction(name: "fs_nv12") else {
            chiakiLog("MetalRenderer: shader functions not found in default library",
                      category: .video, type: .error)
            return
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = fs
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            chiakiLog("MetalRenderer: makeRenderPipelineState failed: \(error)",
                      category: .video, type: .error)
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
}
