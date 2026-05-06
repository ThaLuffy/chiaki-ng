// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import UIKit
import GameController

/// SwiftUI host that drains every gamepad press from the tvOS focus engine
/// while a stream is active. Gamepad input flows only through
/// `GameController.framework` callbacks (i.e. `ControllerService`) and from
/// there straight to chiaki/PS5.
///
/// Siri Remote handling has two modes, controlled by `overlayShown`:
///   - **Closed** (default): only the Menu press is observed. A short tap
///     fires `onShortTap` (the stream-level "back/dismiss" action); a hold
///     past `longPressThreshold` fires `onLongPress` (open the management
///     overlay). All other Siri Remote presses are swallowed so they don't
///     drive the focus engine while playing.
///   - **Open**: D-pad and Select presses are forwarded to `super`, letting
///     the focus engine navigate the overlay's buttons. Menu still toggles
///     short-tap / long-press the same way.
struct StreamInputCapture<Content: View>: UIViewControllerRepresentable {

    let onShortTap: () -> Void
    let onLongPress: () -> Void
    let overlayShown: Bool
    @ViewBuilder let content: () -> Content

    func makeUIViewController(context: Context) -> StreamInputCaptureController<Content> {
        let host = UIHostingController(rootView: content())
        let vc = StreamInputCaptureController(host: host)
        vc.controllerUserInteractionEnabled = false  // gamepad always drains
        vc.onShortTap = onShortTap
        vc.onLongPress = onLongPress
        vc.overlayShown = overlayShown
        return vc
    }

    func updateUIViewController(_ vc: StreamInputCaptureController<Content>, context: Context) {
        vc.onShortTap = onShortTap
        vc.onLongPress = onLongPress
        vc.overlayShown = overlayShown
        vc.host.rootView = content()
    }
}

/// Drains controller input via `GCEventViewController` and intercepts Siri
/// Remote `UIPress` events. Gamepad GameController events still fire
/// through `ControllerService` independently — they bypass UIPress entirely.
final class StreamInputCaptureController<Content: View>: GCEventViewController {

    /// Hold duration that promotes a Menu press from short-tap to long-press.
    /// Picked to be longer than a deliberate tap (~150 ms), shorter than the
    /// system Siri-Remote long-hold gestures (>~1.5 s) the user wants to leave
    /// untouched (sleep menu, etc.).
    private static var longPressThreshold: TimeInterval { 0.6 }

    var onShortTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    var overlayShown: Bool = false
    let host: UIHostingController<Content>

    private var menuPressTimer: Timer?
    private var menuLongPressFired = false

    init(host: UIHostingController<Content>) {
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    deinit {
        menuPressTimer?.invalidate()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passthrough: Set<UIPress> = []
        for press in presses {
            switch press.type {
            case .menu:
                startMenuTimer()
            case .upArrow, .downArrow, .leftArrow, .rightArrow, .select:
                if overlayShown { passthrough.insert(press) }
            default:
                // play/pause and others — drop on the floor while streaming.
                break
            }
        }
        if !passthrough.isEmpty {
            super.pressesBegan(passthrough, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passthrough: Set<UIPress> = []
        for press in presses {
            switch press.type {
            case .menu:
                finishMenuTimer()
            case .upArrow, .downArrow, .leftArrow, .rightArrow, .select:
                if overlayShown { passthrough.insert(press) }
            default:
                break
            }
        }
        if !passthrough.isEmpty {
            super.pressesEnded(passthrough, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        cancelMenuTimer()
        if overlayShown {
            super.pressesCancelled(presses, with: event)
        }
    }

    // MARK: - Menu press tap-vs-hold detection

    private func startMenuTimer() {
        menuPressTimer?.invalidate()
        menuLongPressFired = false
        menuPressTimer = Timer.scheduledTimer(
            withTimeInterval: Self.longPressThreshold, repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.menuLongPressFired = true
            self.onLongPress?()
        }
    }

    private func finishMenuTimer() {
        menuPressTimer?.invalidate()
        menuPressTimer = nil
        if !menuLongPressFired {
            onShortTap?()
        }
    }

    private func cancelMenuTimer() {
        menuPressTimer?.invalidate()
        menuPressTimer = nil
        menuLongPressFired = false
    }
}
