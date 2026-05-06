// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import GameController
import ChiakiBridgeC

/// Bridges `GameController.framework` events to the chiaki session bridge.
/// On every analog or button change, builds a `chiaki_tv_controller_state_t`
/// and pushes it through immediately — no batching (see Hard Rule #5).
///
/// References:
///   - `lib/include/chiaki/controller.h` for the upstream state shape
///   - Sibling: `../../ps-remote-play/PSSwiftPlay/Services/...` (controller mapping)
@MainActor
@Observable
final class ControllerService {

    /// Published list of friendly product names for any connected controllers.
    private(set) var connected: [String] = []

    /// Owner-set sink for controller state changes. Called on every value
    /// change. Closure runs on the main actor (GCController callbacks fire on
    /// the main queue by default).
    @ObservationIgnored var onState: ((chiaki_tv_controller_state_t) -> Void)?

    /// Fires when the gamepad's PS / Xbox Guide button has been held past
    /// `homeLongPressThreshold` seconds. Caller is expected to open the
    /// in-stream management overlay. Short presses still pass through to
    /// the PS5 as `CHIAKI_TV_BTN_PS`; long presses are intercepted locally
    /// (PS5 sees a brief tap, then a release at the threshold).
    @ObservationIgnored var onHomeLongPress: (() -> Void)?

    /// Hold duration that promotes a Guide-button press to a long-press.
    /// 0.6 s mirrors `StreamInputCapture.longPressThreshold` so both entry
    /// points to the overlay feel identical. The same threshold is reused
    /// for the buttonOptions long-press → PS remap (tvOS hides the real PS /
    /// Guide button, so users need a software route to it).
    private static let homeLongPressThreshold: TimeInterval = 0.6
    private static let optionsLongPressThreshold: TimeInterval = 0.6

    // NotificationCenter observers + scratch state — not observable. Keep them
    // out of `@Observable` tracking so `deinit` (nonisolated) can read them.
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var current: chiaki_tv_controller_state_t = chiaki_tv_controller_state_t()
    @ObservationIgnored private var homeLongPressTimer: Timer?
    @ObservationIgnored private var homeSuppressed: Bool = false
    @ObservationIgnored private var optionsLongPressTimer: Timer?
    /// `true` once a buttonOptions hold has crossed the threshold — `makeState`
    /// then sends `CHIAKI_TV_BTN_PS` instead of the normal `CHIAKI_TV_BTN_SHARE`
    /// for as long as the button is physically held. Cleared on release.
    @ObservationIgnored private var optionsLongPressActive: Bool = false

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let ctrl = note.object as? GCController else { return }
            Task { @MainActor in self?.attach(ctrl) }
        })
        observers.append(center.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let ctrl = note.object as? GCController else { return }
            Task { @MainActor in self?.detach(ctrl) }
        })

        // Pick up controllers already connected at launch time.
        for ctrl in GCController.controllers() {
            attach(ctrl)
        }
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Wiring

    private func attach(_ controller: GCController) {
        let name = controller.vendorName ?? "Unknown Controller"
        if !connected.contains(name) { connected.append(name) }
        chiakiLog("ControllerService: attached '\(name)'", category: .controller, type: .info)

        // Diagnostic — confirms whether the Guide/Home button is exposed at all
        // and which physicalInputProfile key holds it on this controller.
        let buttonKeys = controller.physicalInputProfile.buttons.keys.sorted().joined(separator: ", ")
        chiakiLog("ControllerService: buttons=[\(buttonKeys)] hasHome=\(controller.physicalInputProfile.buttons[GCInputButtonHome] != nil)",
                  category: .controller, type: .debug)

        // Order matters: release the Home button from system gestures BEFORE
        // wiring handlers, so the first physical press after attach is already
        // owned by us instead of the OS.
        if let pad = controller.extendedGamepad {
            disableSystemGestures(on: pad, controller: controller)
            wireExtendedGamepad(pad, controller: controller)
        }
    }

    /// Take the PS / Xbox / Home button away from tvOS so a press doesn't
    /// raise the system overlay during streaming. With this set, the press
    /// is delivered ONLY through `GameController.framework`, which our
    /// mapping forwards as `CHIAKI_TV_BTN_PS`. `controllerUserInteractionEnabled`
    /// alone isn't enough — the home gesture is system-level and bypasses
    /// the focus-engine drain unless we explicitly opt out here.
    ///
    /// Set on BOTH the typed accessor and the physicalInputProfile entry —
    /// some controllers/tvOS versions only honor the change on one path.
    private func disableSystemGestures(on pad: GCExtendedGamepad, controller: GCController) {
        pad.buttonHome?.preferredSystemGestureState = .disabled
        controller.physicalInputProfile.buttons[GCInputButtonHome]?.preferredSystemGestureState = .disabled
    }

    private func detach(_ controller: GCController) {
        let name = controller.vendorName ?? "Unknown Controller"
        connected.removeAll { $0 == name }
        chiakiLog("ControllerService: detached '\(name)'", category: .controller, type: .info)

        // If no controllers remain, push an idle state so chiaki releases held buttons.
        if GCController.controllers().isEmpty {
            current = chiaki_tv_controller_state_t()
            onState?(current)
        }
    }

    private func wireExtendedGamepad(_ pad: GCExtendedGamepad, controller: GCController) {
        pad.valueChangedHandler = { [weak self] pad, _ in
            guard let self = self else { return }
            self.current = self.makeState(from: pad)
            self.onState?(self.current)
        }
        // The Guide / Home button doesn't fire `valueChangedHandler` on its
        // own — Apple treats it specially. Register `pressedChangedHandler`
        // on BOTH the typed accessor and the underlying physicalInputProfile
        // entry: across tvOS versions and vendors (Xbox vs DualSense), one
        // path occasionally delivers events when the other doesn't. They
        // back the same input object so a real press fires once net via
        // GameController's de-duplication of identical handler invocations.
        let homeHandler: GCControllerButtonValueChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleHomePressChange(pressed: pressed, pad: pad)
            }
        }
        pad.buttonHome?.pressedChangedHandler = homeHandler
        controller.physicalInputProfile.buttons[GCInputButtonHome]?.pressedChangedHandler = homeHandler

        if pad.buttonHome == nil && controller.physicalInputProfile.buttons[GCInputButtonHome] == nil {
            chiakiLog("ControllerService: WARNING Home button not exposed — Guide press will not reach PS5",
                      category: .controller, type: .error)
        } else {
            chiakiLog("ControllerService: Home press handler installed", category: .controller, type: .info)
        }

        // buttonOptions long-press → PS button. tvOS doesn't surface the real
        // PS / Guide button, so the secondary cluster button (DualSense Create
        // / Xbox View) doubles as the user-invocable PS press: short tap goes
        // through as SHARE, hold past `optionsLongPressThreshold` flips to PS.
        // Same handler-on-both-paths defence as the Home button — cheap to set,
        // immune to vendor-profile differences.
        let optionsHandler: GCControllerButtonValueChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleOptionsPressChange(pressed: pressed, pad: pad)
            }
        }
        pad.buttonOptions?.pressedChangedHandler = optionsHandler

        // Push an initial state so chiaki sees a clean baseline.
        self.current = self.makeState(from: pad)
        self.onState?(self.current)
    }

    /// Tap-vs-hold detection for the Guide / Home button. The press is
    /// forwarded to the PS5 immediately; if the user keeps holding past
    /// `homeLongPressThreshold`, we send a release to the PS5 and fire
    /// `onHomeLongPress` so the StreamView can open the overlay.
    private func handleHomePressChange(pressed: Bool, pad: GCExtendedGamepad) {
        chiakiLog("ControllerService: Home pressed=\(pressed)", category: .controller, type: .debug)
        homeLongPressTimer?.invalidate()
        homeLongPressTimer = nil

        if pressed {
            homeSuppressed = false
            current = makeState(from: pad)
            onState?(current)
            homeLongPressTimer = Timer.scheduledTimer(
                withTimeInterval: Self.homeLongPressThreshold, repeats: false
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    // Promote: send a release to the PS5 (so it doesn't see
                    // a stuck PS button), then signal the overlay open.
                    self.homeSuppressed = true
                    self.current = self.makeState(from: pad)
                    self.onState?(self.current)
                    self.onHomeLongPress?()
                }
            }
        } else {
            homeSuppressed = false
            current = makeState(from: pad)
            onState?(current)
        }
    }

    /// Tap-vs-hold detection for `buttonOptions` (DualSense Create / Xbox
    /// View). Short tap delivers a normal `CHIAKI_TV_BTN_SHARE` press+release.
    /// Holding past `optionsLongPressThreshold` flips the in-flight SHARE off
    /// and pins `CHIAKI_TV_BTN_PS` on for as long as the button is physically
    /// held — so the user can reach the PS5 system menu even though tvOS
    /// hides the real Guide button.
    private func handleOptionsPressChange(pressed: Bool, pad: GCExtendedGamepad) {
        chiakiLog("ControllerService: Options pressed=\(pressed)", category: .controller, type: .debug)
        optionsLongPressTimer?.invalidate()
        optionsLongPressTimer = nil

        if pressed {
            optionsLongPressActive = false
            current = makeState(from: pad)
            onState?(current)
            optionsLongPressTimer = Timer.scheduledTimer(
                withTimeInterval: Self.optionsLongPressThreshold, repeats: false
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    // Promote: stop sending SHARE, start sending PS. The PS5
                    // sees a brief SHARE pulse for the threshold duration —
                    // acceptable side-effect, mirrors the Home long-press path.
                    self.optionsLongPressActive = true
                    self.current = self.makeState(from: pad)
                    self.onState?(self.current)
                }
            }
        } else {
            optionsLongPressActive = false
            current = makeState(from: pad)
            onState?(current)
        }
    }

    // MARK: - Mapping

    /// Map `GCExtendedGamepad` to chiaki's button bitmask + analog state.
    /// Mapping order mirrors the desktop controller mapping (gui/src/controllermanager.cpp).
    private func makeState(from pad: GCExtendedGamepad) -> chiaki_tv_controller_state_t {
        var s = chiaki_tv_controller_state_t()
        var buttons: UInt32 = 0

        if pad.buttonA.isPressed { buttons |= UInt32(CHIAKI_TV_BTN_CROSS) }
        if pad.buttonB.isPressed { buttons |= UInt32(CHIAKI_TV_BTN_CIRCLE) }
        if pad.buttonX.isPressed { buttons |= UInt32(CHIAKI_TV_BTN_SQUARE) }
        if pad.buttonY.isPressed { buttons |= UInt32(CHIAKI_TV_BTN_TRIANGLE) }
        if pad.dpad.left.isPressed  { buttons |= UInt32(CHIAKI_TV_BTN_DPAD_LEFT) }
        if pad.dpad.right.isPressed { buttons |= UInt32(CHIAKI_TV_BTN_DPAD_RIGHT) }
        if pad.dpad.up.isPressed    { buttons |= UInt32(CHIAKI_TV_BTN_DPAD_UP) }
        if pad.dpad.down.isPressed  { buttons |= UInt32(CHIAKI_TV_BTN_DPAD_DOWN) }
        if pad.leftShoulder.isPressed  { buttons |= UInt32(CHIAKI_TV_BTN_L1) }
        if pad.rightShoulder.isPressed { buttons |= UInt32(CHIAKI_TV_BTN_R1) }
        if pad.leftThumbstickButton?.isPressed == true  { buttons |= UInt32(CHIAKI_TV_BTN_L3) }
        if pad.rightThumbstickButton?.isPressed == true { buttons |= UInt32(CHIAKI_TV_BTN_R3) }
        // GCExtendedGamepad's two non-system buttons map to the PS5 cluster's
        // two non-PS buttons by ergonomic position:
        //   - `buttonMenu` is the right-side / "start / hamburger" button on
        //     both controllers (DualSense Options, Xbox Menu) → PS5 OPTIONS.
        //   - `buttonOptions` is the left-side / "secondary" button (DualSense
        //     Create, Xbox View) → PS5 SHARE on a short tap, but flips to PS5
        //     PS once `optionsLongPressActive` latches (~0.6 s hold). tvOS
        //     hides the real Guide button, so this is the only path to PS.
        // Apple's framework gives the typed accessors confusingly-inverted
        // names; trust physical position over property name.
        if pad.buttonMenu.isPressed { buttons |= UInt32(CHIAKI_TV_BTN_OPTIONS) }
        if optionsLongPressActive {
            buttons |= UInt32(CHIAKI_TV_BTN_PS)
        } else if pad.buttonOptions?.isPressed == true {
            buttons |= UInt32(CHIAKI_TV_BTN_SHARE)
        }
        if !homeSuppressed, pad.buttonHome?.isPressed == true {
            buttons |= UInt32(CHIAKI_TV_BTN_PS)
        }

        // PS5 Touchpad press: prefer a real touchpad if exposed (DualSense's
        // GCInputDualShockTouchpadButton, surfaced as "Button Touchpad").
        // Xbox controllers lack a touchpad entirely — many PS5 games gate
        // map / inventory / mission UI on a Touchpad press, so fall back to
        // remapping the Share button (`GCInputButtonShare`) onto Touchpad.
        // The Xbox Series Share button sits on the right side of the cluster
        // — the closest ergonomic substitute. DualSense users keep their
        // dedicated touchpad and Share/Create stays free for a future SHARE
        // mapping; the `hasTouchpad` guard prevents double-firing on them.
        let profile = pad.controller?.physicalInputProfile
        let hasTouchpad     = profile?.buttons["Button Touchpad"] != nil
        let touchpadPressed = profile?.buttons["Button Touchpad"]?.isPressed == true
        let sharePressed    = profile?.buttons[GCInputButtonShare]?.isPressed == true
        if touchpadPressed || (!hasTouchpad && sharePressed) {
            buttons |= UInt32(CHIAKI_TV_BTN_TOUCHPAD)
        }

        s.buttons = buttons
        s.l2_state = analogToTrigger(pad.leftTrigger.value)
        s.r2_state = analogToTrigger(pad.rightTrigger.value)
        let lx = analogToStick(pad.leftThumbstick.xAxis.value)
        let ly = analogToStick(pad.leftThumbstick.yAxis.value, invertY: true)
        let rx = analogToStick(pad.rightThumbstick.xAxis.value)
        let ry = analogToStick(pad.rightThumbstick.yAxis.value, invertY: true)
        s.left_x = lx
        s.left_y = ly
        s.right_x = rx
        s.right_y = ry
        return s
    }

    @inline(__always)
    private func analogToTrigger(_ v: Float) -> UInt8 {
        let clamped = max(0, min(1, v))
        return UInt8(clamped * 255)
    }

    @inline(__always)
    private func analogToStick(_ v: Float, invertY: Bool = false) -> Int16 {
        // GameController: -1.0 ... 1.0. chiaki stick: Int16 -32767 ... 32767.
        // Y is inverted (GC up = +1, chiaki up = -32767) — invert when invertY.
        let raw = invertY ? -v : v
        let clamped = max(-1, min(1, raw))
        return Int16(clamped * 32767)
    }
}
