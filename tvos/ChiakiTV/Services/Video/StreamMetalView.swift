// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import AVKit
import AVFoundation
import CoreMedia
import QuartzCore
#if os(tvOS)
import UIKit
#endif

/// SwiftUI host for a raw `CAMetalLayer`-backed UIView, driven by a
/// `MetalRenderer` whose internal `CAMetalDisplayLink` calls back at vsync.
///
/// Drives `UIWindow.avDisplayManager.preferredDisplayCriteria` whenever a
/// fresh `CMFormatDescription` arrives from the decoder. tvOS uses that
/// hint to renegotiate the HDMI link to the right refresh rate + dynamic
/// range (HDR10 PQ for `kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ`-
/// tagged streams, SDR otherwise).
///
/// See `docs/optimization/native-alternatives-latency-first.md` Phase A.6.
struct StreamMetalView: UIViewRepresentable {

    let renderer: MetalRenderer
    /// Latest format description from the decoder. Drives display-criteria.
    let formatDescription: CMFormatDescription?
    /// Target refresh rate in Hz (typically 60).
    let refreshRate: Float

    func makeUIView(context: Context) -> ChiakiMetalView {
        let view = ChiakiMetalView()
        view.backgroundColor = .black
        renderer.attach(to: view.metalLayer)
        return view
    }

    func updateUIView(_ uiView: ChiakiMetalView, context: Context) {
        applyDisplayCriteria(for: uiView)
    }

    static func dismantleUIView(_ uiView: ChiakiMetalView, coordinator: ()) {
        // Clear the criteria so a future SDR app on the same Apple TV
        // doesn't get pinned to HDR. tvOS would eventually clear this
        // on its own, but explicit reset is cheap insurance.
        #if os(tvOS)
        uiView.window?.avDisplayManager.preferredDisplayCriteria = nil
        #endif
    }

    private func applyDisplayCriteria(for view: ChiakiMetalView) {
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

/// UIView whose backing layer is a `CAMetalLayer`. Lets us host Metal
/// content directly without the `MTKView` abstraction.
final class ChiakiMetalView: UIView {

    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the drawable resolution matched to the view's pixel size so
        // the GPU never scales up/down on present.
        let scale = window?.screen.nativeScale ?? UIScreen.main.nativeScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width:  bounds.width * scale,
            height: bounds.height * scale
        )
    }
}
