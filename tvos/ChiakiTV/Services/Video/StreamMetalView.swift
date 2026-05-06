// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import MetalKit

/// SwiftUI host for an `MTKView` driven by a `MetalRenderer`. The renderer
/// pulls from its single-slot pending buffer on each vsync; the view is
/// a passive presentation surface.
struct StreamMetalView: UIViewRepresentable {

    let renderer: MetalRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor = .black
        renderer.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // No-op — the renderer owns the draw loop.
    }
}
