// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import MetalKit
import AVKit
import AVFoundation
import CoreMedia
#if os(tvOS)
import UIKit
#endif

/// SwiftUI host for an `MTKView` driven by a `MetalRenderer`. The renderer
/// pulls from its single-slot pending buffer on each vsync; the view is
/// a passive presentation surface.
///
/// Drives `UIWindow.avDisplayManager.preferredDisplayCriteria` whenever a
/// fresh `CMFormatDescription` arrives from the decoder. tvOS uses that
/// hint to renegotiate the HDMI link to the right refresh rate + dynamic
/// range (HDR10 PQ for `kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ`-
/// tagged streams, SDR otherwise).
struct StreamMetalView: UIViewRepresentable {

    let renderer: MetalRenderer
    /// Latest format description from the decoder. Drives display-criteria.
    let formatDescription: CMFormatDescription?
    /// Target refresh rate in Hz (typically 60).
    let refreshRate: Float

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor = .black
        renderer.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        applyDisplayCriteria(for: uiView)
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: ()) {
        // Clear the criteria so a future SDR app on the same Apple TV
        // doesn't get pinned to HDR. tvOS would eventually clear this
        // on its own, but explicit reset is cheap insurance.
        #if os(tvOS)
        uiView.window?.avDisplayManager.preferredDisplayCriteria = nil
        #endif
    }

    private func applyDisplayCriteria(for view: MTKView) {
        #if os(tvOS)
        guard let window = view.window else { return }
        guard let formatDescription = formatDescription else {
            window.avDisplayManager.preferredDisplayCriteria = nil
            return
        }
        if #available(tvOS 17.0, *) {
            let criteria = AVDisplayCriteria(
                refreshRate: refreshRate,
                formatDescription: formatDescription
            )
            window.avDisplayManager.preferredDisplayCriteria = criteria
        }
        #endif
    }
}
