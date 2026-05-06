// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Observation

// MARK: - Routes (replaces QML stack)

/// Top-level navigation. The desktop's `Main.qml` uses a Qt StackView with
/// push/pop/replace. SwiftUI on tvOS is happier with a single switched view —
/// we replicate the desktop's "replace" semantics by setting `route`.
///
/// See [`docs/ui/swift-ui-plan.md`](../../docs/ui/swift-ui-plan.md) §6.
enum AppRoute: Hashable {
    case hostList
    case manualHost
    case registration(Host)
    case consolePin(hostId: String)
    case settings
    case stream
    /// Wake-on-LAN waiting room, parameterised by the host MAC the user
    /// was trying to reach so the view can observe its discovery state
    /// and auto-promote to streaming once it comes online.
    case autoConnect(hostId: String)
}

// MARK: - Modals

/// Modal overlays that float on top of any route. Equivalent to the desktop's
/// in-place `Dialog` instances in `Main.qml`.
enum ChiakiModal: Equatable {
    case confirm(ConfirmDialogModel)
    case remind(RemindDialogModel)
    case info(title: String, message: String)
    case errorToast(title: String, message: String)
}

/// `.sheet(item:)`-driven modals over the host list. Per
/// `docs/ui/redesign-v2-report.md §C3`: presenting these as real sheets
/// gives the user the system scrim + dim of the underlying content +
/// Menu-button dismissal that route-replacement can't offer.
enum SheetItem: Identifiable, Equatable {
    case manualHost
    case registration(Host)
    case consolePin(hostId: String)

    var id: String {
        switch self {
        case .manualHost:               return "manual"
        case .registration(let host):   return "reg-\(host.id)"
        case .consolePin(let hostId):   return "pin-\(hostId)"
        }
    }
}

struct ConfirmDialogModel: Equatable {
    let title: String
    let message: String
    let onConfirm: ConfirmAction
    let onReject: ConfirmAction?

    static func == (lhs: ConfirmDialogModel, rhs: ConfirmDialogModel) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

struct RemindDialogModel: Equatable {
    let title: String
    let message: String
    let onYes: ConfirmAction
    let onNo: ConfirmAction
    let onLater: ConfirmAction

    static func == (lhs: RemindDialogModel, rhs: RemindDialogModel) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

/// A type-erased action so we can stash closures inside Equatable models
/// without breaking SwiftUI diffing.
struct ConfirmAction {
    let perform: () -> Void
    static let noop = ConfirmAction(perform: {})
}

// MARK: - App State

@MainActor
@Observable
final class AppState {

    // Navigation
    var route: AppRoute = .hostList
    var modal: ChiakiModal? = nil
    var sheet: SheetItem? = nil

    /// In-stream management overlay. Lifted to `AppState` so multiple input
    /// sources can request it: a long-press of the gamepad's Guide / PS
    /// button via `ControllerService.onHomeLongPress`, or a hold of the Siri
    /// Remote Menu button via `StreamInputCapture.onLongPress`. `StreamView`
    /// reads/writes this value as the binding for `StreamMenuOverlay`.
    var streamMenuOpen: Bool = false

    // Discovery toggle (mirrors Chiaki.discoveryEnabled). Drives DiscoveryService
    // start/stop via `didSet`.
    var discoveryEnabled: Bool = true {
        didSet {
            guard !isHydrating, oldValue != discoveryEnabled else { return }
            if discoveryEnabled {
                discoveryService.start()
            } else {
                discoveryService.stop()
            }
        }
    }

    /// Live host list. Phase 1: backed by DiscoveryService. Future steps will
    /// merge in registered hosts that aren't currently discoverable (e.g.
    /// powered-off PS5s show as offline-but-known).
    var hosts: [Host] = []

    var settings: AppSettings {
        didSet {
            guard !isHydrating, oldValue != settings else { return }
            SettingsStore.save(settings)
        }
    }

    var registeredHosts: [RegisteredHost] {
        didSet {
            guard !isHydrating, oldValue != registeredHosts else { return }
            RegisteredHostStore.save(registeredHosts)
        }
    }

    /// Bridge driver. Owned by AppState so its lifecycle = app lifecycle.
    let discoveryService: DiscoveryService

    /// Registration driver — exposed so views can observe progress.
    let registrationService: RegistrationService

    /// MFi/DualSense controller fanout.
    let controllerService: ControllerService

    /// Active streaming session driver.
    let streamSession: StreamSession

    /// `true` while we're loading initial state from disk — disables the
    /// auto-save sinks so we don't immediately rewrite what we just read.
    private var isHydrating = true

    init(discoveryService: DiscoveryService? = nil,
         registrationService: RegistrationService? = nil) {
        self.settings = SettingsStore.load()
        self.registeredHosts = RegisteredHostStore.load()
        self.discoveryService = discoveryService ?? DiscoveryService()
        self.registrationService = registrationService ?? RegistrationService()
        let controllers = ControllerService()
        self.controllerService = controllers
        self.streamSession = StreamSession(controllerService: controllers)
        self.isHydrating = false

        // Long-press of the gamepad's Guide / PS button is the second entry
        // point to the in-stream management overlay (the first is the Siri
        // Remote Menu hold). Both routes funnel through `streamMenuOpen`.
        controllers.onHomeLongPress = { [weak self] in
            self?.streamMenuOpen = true
        }

        // Observation-based mirroring replaces the Combine `.sink`s the legacy
        // ObservableObject AppState used. The recursive `withObservationTracking`
        // pattern reads the tracked property *and re-arms itself* whenever it
        // changes — no Task / AsyncStream plumbing needed.
        observeDiscoveryHosts()
        observeRegistrationState()
    }

    /// Honor the initial `discoveryEnabled` state by starting the bridge if
    /// the user/persisted setting said so. Called from `ChiakiTVApp` on
    /// launch. Idempotent.
    func bootstrapDiscovery() {
        if discoveryEnabled {
            discoveryService.start()
        }
    }

    /// Find a registered host that matches the given discovered/manual `host`
    /// — by MAC if available, otherwise by IP. Returns `nil` if the host
    /// hasn't been paired yet.
    func registeredHost(for host: Host) -> RegisteredHost? {
        if !host.mac.isEmpty,
           let r = registeredHosts.first(where: { $0.mac.caseInsensitiveCompare(host.mac) == .orderedSame }) {
            return r
        }
        if !host.ipAddress.isEmpty,
           let r = registeredHosts.first(where: { $0.lastIpAddress == host.ipAddress }) {
            return r
        }
        return nil
    }

    /// Open a streaming session against the given registered host, then
    /// route to the stream view.
    func connectStream(host: Host, registered: RegisteredHost) {
        streamSession.connect(registered: registered, host: host, settings: settings)
        showStream()
    }

    // MARK: - Bridge → AppState mirroring (Observation-driven)

    private func observeDiscoveryHosts() {
        withObservationTracking {
            // Read both inputs inside the tracking block so the observer
            // re-fires when EITHER the discovered list or the registered
            // list changes — otherwise pairing a host wouldn't refresh the
            // stamped `registered` flag (or its dependent inline actions)
            // until the next discovery cycle.
            let snapshot = discoveryService.hosts
            let regs = registeredHosts
            let merged = snapshot.map { host -> Host in
                guard !host.registered, Self.matchesRegistered(host: host, in: regs) else {
                    return host
                }
                var stamped = host
                stamped.registered = true
                return stamped
            }
            if hosts != merged { hosts = merged }
        } onChange: { [weak self] in
            // `onChange` is called *before* the property finalizes; hop to the
            // next main-actor tick before reading the new value and re-arming.
            Task { @MainActor in self?.observeDiscoveryHosts() }
        }
    }

    static func matchesRegistered(host: Host, in regs: [RegisteredHost]) -> Bool {
        if !host.mac.isEmpty,
           regs.contains(where: { $0.mac.caseInsensitiveCompare(host.mac) == .orderedSame }) {
            return true
        }
        if !host.ipAddress.isEmpty,
           regs.contains(where: { $0.lastIpAddress == host.ipAddress }) {
            return true
        }
        return false
    }

    private func observeRegistrationState() {
        withObservationTracking {
            if case .succeeded = registrationService.state {
                let stored = RegisteredHostStore.load()
                if registeredHosts != stored { registeredHosts = stored }
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeRegistrationState() }
        }
    }

    // MARK: - Preview / test seam

    /// AppState that doesn't drive the C bridge — for SwiftUI previews and
    /// unit tests. Seeds mock hosts so views have something to render.
    @MainActor
    static func preview(
        hosts: [Host] = Host.previewSet,
        settings: AppSettings = AppSettings(),
        registered: [RegisteredHost] = []
    ) -> AppState {
        let s = AppState(discoveryService: DiscoveryService())
        s.discoveryEnabled = false
        s.hosts = hosts
        s.settings = settings
        s.registeredHosts = registered
        return s
    }

    // MARK: - Navigation API (matches Main.qml's surface)

    func showHostList() {
        sheet = nil
        setRoute(.hostList, label: "showHostList")
    }
    func showManualHost()       { sheet = .manualHost }
    func showRegistration(for host: Host) { sheet = .registration(host) }
    func showConsolePin(hostId: String)   { sheet = .consolePin(hostId: hostId) }
    func dismissSheet()         { sheet = nil }

    func showSettings()         { setRoute(.settings,    label: "showSettings") }
    func showStream()           { setRoute(.stream,      label: "showStream") }
    func showAutoConnect(hostId: String) {
        setRoute(.autoConnect(hostId: hostId), label: "showAutoConnect(\(hostId))")
    }

    func showConfirm(title: String, message: String,
                     onConfirm: @escaping () -> Void,
                     onReject: (() -> Void)? = nil) {
        setModal(.confirm(.init(title: title, message: message,
                                onConfirm: ConfirmAction(perform: onConfirm),
                                onReject: onReject.map { ConfirmAction(perform: $0) })),
                 label: "showConfirm(\(title))")
    }

    func showRemind(title: String, message: String,
                    onYes: @escaping () -> Void,
                    onNo: @escaping () -> Void,
                    onLater: @escaping () -> Void) {
        setModal(.remind(.init(title: title, message: message,
                               onYes: ConfirmAction(perform: onYes),
                               onNo: ConfirmAction(perform: onNo),
                               onLater: ConfirmAction(perform: onLater))),
                 label: "showRemind(\(title))")
    }

    func showInfo(title: String, message: String) {
        setModal(.info(title: title, message: message), label: "showInfo(\(title))")
    }

    func showError(title: String, message: String) {
        setModal(.errorToast(title: title, message: message),
                 label: "showError(\(title))")
    }

    func dismissModal() {
        setModal(nil, label: "dismissModal")
    }

    // MARK: - Navigation primitives

    private func setRoute(_ next: AppRoute, label _: String) {
        route = next
    }

    private func setModal(_ next: ChiakiModal?, label _: String) {
        modal = next
    }
}
