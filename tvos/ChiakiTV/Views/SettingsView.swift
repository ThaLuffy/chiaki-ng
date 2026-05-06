// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import GameController

/// Settings screen rebuilt against SwiftUI primitives per
/// [`docs/ui/redesign-v2-report.md §C2`](../../docs/ui/redesign-v2-report.md).
///
/// **What changed from v1:**
/// - Rail items are tvOS `.buttonStyle(.card)` Buttons. No more
///   `chiakiFocusRing` overlap or hand-rolled scale animations — the
///   focus engine handles parallax, lift, and the system-default halo.
/// - Tab bodies use `Form` + `Section` + `LabeledContent` instead of
///   the custom `SettingsForm` / `SettingsRow`. Spacing, separators,
///   and section headers come from the system.
/// - Controls are `Picker(.segmented)`, `Slider`, `Toggle` — every
///   one inherits `.tint(amber500)` from `applyChiakiTheme()`, with
///   correct focus chrome and Dynamic Type for free.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: SettingsTab = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["CHIAKITV_INITIAL_SETTINGS_TAB"],
           let tab = SettingsTab(rawValue: raw) {
            return tab
        }
        #endif
        return .stream
    }()

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: Theme.space8) {
                rail
                detailContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            // No horizontal padding here — NavigationStack already
            // applies its own ~80pt safe-area inset on tvOS for its
            // toolbar / titlebar chrome. Adding screenInset on top would
            // double the visible margin (and was the source of the
            // Home-vs-Settings inconsistency the user flagged: Home
            // ignores safe area, Settings respects it, so the same 80pt
            // padding token rendered as ~80pt on Home but ~165pt on
            // Settings).
            .padding(.top, Theme.space6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { appState.showHostList() }
                }
            }
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.label, systemImage: tab.icon)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .font(.system(.body, design: .default).weight(.medium))
                        .foregroundStyle(selectedTab == tab ? Theme.amber500 : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.space3)
                        .padding(.horizontal, Theme.space4)
                }
                .buttonStyle(.card)
            }
            Spacer()
        }
        .frame(width: 300, alignment: .top)
        .focusSection()
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .stream:     StreamTab()
        case .network:    NetworkTab()
        case .controller: ControllerDiagnosticTab()
        case .consoles:   ConsolesTab()
        case .app:        AppTab()
        }
    }
}

// MARK: - Tab descriptor

enum SettingsTab: String, CaseIterable, Identifiable {
    case stream, network, controller, consoles, app

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stream:     return "Stream"
        case .network:    return "Network"
        case .controller: return "Controller"
        case .consoles:   return "Consoles"
        case .app:        return "App"
        }
    }

    var icon: String {
        switch self {
        case .stream:     return "tv"
        case .network:    return "antenna.radiowaves.left.and.right"
        case .controller: return "gamecontroller"
        case .consoles:   return "list.bullet.rectangle.portrait"
        case .app:        return "slider.horizontal.3"
        }
    }
}

// MARK: - Stream tab

private struct StreamTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                segmentedRow("Resolution", selection: $appState.settings.resolution,
                             options: VideoResolution.allCases) { $0.label }
                segmentedRow("Refresh rate", selection: $appState.settings.fps,
                             options: VideoFPS.allCases) { $0.label }
                segmentedRow("Codec", selection: $appState.settings.codec,
                             options: VideoCodec.allCases) { $0.label }
            } header: {
                Text("Picture")
            } footer: {
                Text("Higher refresh rates require a 4K HDR TV connected to the Apple TV.")
            }

            Section {
                segmentedRow("Render preset", selection: $appState.settings.renderPreset,
                             options: RenderPreset.allCases) { $0.label }

                SettingsRow("Bitrate", valueInset: 2) {
                    TVSlider(value: $appState.settings.bitrateKbps,
                             range: 2_000...50_000, step: 500,
                             format: { "\($0 / 1_000) Mbps" })
                }
            } header: {
                Text("Quality")
            } footer: {
                Text("Higher quality costs ~1–2 ms of decode latency. Bitrate is a hard ceiling — the PS5 adapts down on a weak link.")
            }

            Section {
                segmentedRow("Vertical sync",
                             selection: $appState.settings.verticalSync,
                             options: [false, true]) { $0 ? "On" : "Off" }
            } footer: {
                Text("Reduces tearing. Adds ~16 ms of latency.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Reusable segmented-row helper now built on top of `SettingsRow` so
/// every segmented row inherits the same fixed label-column width and
/// minimum row height as toggles, sliders, and drill-in pickers.
@ViewBuilder
fileprivate func segmentedRow<T: Hashable, S: RandomAccessCollection>(
    _ label: String,
    selection: Binding<T>,
    options: S,
    text: @escaping (T) -> String
) -> some View where S.Element == T, S: Sendable {
    SettingsRow(label) {
        Picker("", selection: selection) {
            ForEach(Array(options), id: \.self) { item in
                Text(text(item)).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Network tab

private struct NetworkTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                SettingsRow("Audio buffer", valueInset: 2) {
                    TVSlider(value: $appState.settings.audioBufferMs,
                             range: 20...500, step: 10,
                             format: { "\($0) ms" })
                }
                SettingsRow("Volume", valueInset: 2) {
                    TVSlider(value: $appState.settings.audioVolume,
                             range: 0...100, step: 5,
                             format: { "\($0)%" })
                }
            } header: {
                Text("Audio")
            } footer: {
                Text("A higher buffer means smoother audio at the cost of mouth-to-ear latency.")
            }

            Section {
                SettingsRow("Weak Wi-Fi threshold", valueInset: 2) {
                    TVSlider(value: $appState.settings.weakWifiThresholdPct,
                             range: 1...20, step: 1,
                             format: { "\($0)%" })
                }
                SettingsRow("Reported loss ceiling", valueInset: 2) {
                    TVSlider(value: $appState.settings.packetLossReportedMax,
                             range: 1...20, step: 1,
                             format: { "\($0)%" })
                }
            } header: {
                Text("Connection diagnostics")
            } footer: {
                Text("Show a Wi-Fi warning when sustained packet loss exceeds the threshold. The ceiling caps reported loss in the in-stream stats overlay.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - App tab (was General)

private struct AppTab: View {
    @Environment(AppState.self) private var appState
    @State private var psnPromptShown = false
    @State private var psnDraft: String = ""

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                segmentedRow("Action on disconnect",
                             selection: $appState.settings.actionOnDisconnect,
                             options: DisconnectAction.allCases) { $0.label }
                segmentedRow("Action on suspend",
                             selection: $appState.settings.actionOnSuspend,
                             options: SuspendAction.allCases) { $0.label }
                segmentedRow("Audio + Video",
                             selection: $appState.settings.audioVideoMode,
                             options: AudioVideoMode.allCases) { $0.label }
            } header: {
                Text("Behavior")
            }

            Section {
                SettingsRow("PSN Account-ID", valueInset: 2) {
                    Button {
                        psnDraft = appState.settings.psnAccountId
                        psnPromptShown = true
                    } label: {
                        Text(appState.settings.psnAccountId.isEmpty
                             ? "Not set"
                             : appState.settings.psnAccountId)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                Text("12-character base64 string. The PS5 ties registrations to this account.")
            }

            Section {
                segmentedRow("Streamer Mode",
                             selection: $appState.settings.streamerMode,
                             options: [false, true]) { $0 ? "On" : "Off" }
                segmentedRow("Verbose Logs",
                             selection: $appState.settings.verboseLogs,
                             options: [false, true]) { $0 ? "On" : "Off" }
                segmentedRow("Show Stream Stats",
                             selection: $appState.settings.showStreamStats,
                             options: [false, true]) { $0 ? "On" : "Off" }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Streamer Mode hides identifying details from the stream HUD. Verbose Logs writes detailed diagnostics to Console.")
            }
        }
        .formStyle(.grouped)
        .alert("PSN Account ID", isPresented: $psnPromptShown) {
            TextField("AAAAAAAAAAAAAAAA==", text: $psnDraft)
            Button("OK") {
                appState.settings.psnAccountId = psnDraft
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("12-character base64 string (decodes to 8 bytes).")
        }
    }
}

// MARK: - Consoles tab

private struct ConsolesTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                if appState.registeredHosts.isEmpty {
                    // Empty-state row inside the same Form chrome as the
                    // populated state — keeps the visual rhythm matching
                    // every other Settings tab. Centered alignment +
                    // generous padding distinguishes it as a "callout"
                    // rather than a clickable row.
                    VStack(spacing: Theme.space3) {
                        Text("No registered consoles")
                            .font(.system(.body).weight(.semibold))
                        Text("Pair a PS5 to use Remote Play without re-entering a PIN every time.")
                            .font(.system(.footnote))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Theme.space6)
                    .padding(.horizontal, Theme.space6)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                } else {
                    ForEach(appState.registeredHosts) { host in
                        SettingsRow(host.nickname, valueInset: 2) {
                            HStack(spacing: Theme.space5) {
                                Text(host.mac)
                                    .font(Theme.font(.mono))
                                    .foregroundStyle(.secondary)
                                Button {
                                    appState.registeredHosts.removeAll {
                                        $0.id == host.id
                                    }
                                } label: {
                                    Label("Forget", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.bordered)
                                .tint(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Registered consoles")
            }

            Section {
                Button {
                    appState.showRegistration(for: Host(
                        id: UUID().uuidString,
                        nickname: "New PS5",
                        ipAddress: ""
                    ))
                } label: {
                    Label("Register a new console",
                          systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Controller diagnostic tab

private struct ControllerDiagnosticTab: View {
    @State private var snapshot = ControllerSnapshot()
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var diagnosticActive = false
    /// Per-button "first observed pressed at" timestamp. Cleared when
    /// the button is released. Drives the hold-2s exit.
    @State private var pressStarts: [String: Date] = [:]
    /// Latest hold duration for any currently-pressed button — used to
    /// drive a small progress indicator showing how close the user is
    /// to triggering the exit. Updated each poll tick.
    @State private var maxHoldDuration: TimeInterval = 0

    /// How long to hold any button before exiting diagnostic mode.
    private let exitHoldThreshold: TimeInterval = 2.0

    var body: some View {
        Group {
            if snapshot.controllers.isEmpty {
                ContentUnavailableView {
                    Label("No controllers connected", systemImage: "gamecontroller")
                } description: {
                    Text("Pair a DualSense or MFi controller in tvOS Settings → Remotes & Devices.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                idleView
            }
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
        // Diagnostic mode is a full-screen takeover so the SettingsView
        // rail and the NavigationStack title don't overlap the
        // controller diagram. The cover dismisses when the hold-2s
        // exit fires (`diagnosticActive = false`).
        .fullScreenCover(isPresented: $diagnosticActive) {
            diagnosticGrid
                .background(Theme.ink900.ignoresSafeArea())
                .applyChiakiTheme()
        }
    }

    // MARK: - Idle view (controllers connected, diagnostic not started)

    private var idleView: some View {
        Form {
            ForEach(0..<snapshot.controllers.count, id: \.self) { idx in
                let c = snapshot.controllers[idx]
                Section {
                    SettingsRow("Profile", valueInset: 2) {
                        Text(c.profileClass)
                            .font(Theme.font(.mono))
                            .foregroundStyle(.secondary)
                    }
                    SettingsRow("Home button", valueInset: 2) {
                        if c.hasHome {
                            Label("Exposed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.green500)
                        } else {
                            Label("Not exposed", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.rose500)
                        }
                    }
                } header: {
                    Text(c.vendorName)
                } footer: {
                    if !c.hasHome {
                        Text("Long-press the Options button (Create on DualSense, View on Xbox) past 0.6 s to reach the PS5's PS button while streaming.")
                    }
                }
            }

            Section {
                Button {
                    diagnosticActive = true
                } label: {
                    Label("Start button diagnostic", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Captures the D-pad while active so your inputs don't navigate away from this screen. Press Menu / B to exit.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Diagnostic grid (active mode — no focusable elements)
    //
    // While `diagnosticActive` is true, the screen has zero focusable
    // children — that's what stops the D-pad from moving focus, scrolling,
    // or dismissing. The only escape is the Menu/B button, captured via
    // `onExitCommand`. Per Apple HIG: tvOS apps may capture Menu in
    // contexts where it's the natural exit affordance for a sub-mode.

    /// Spatial controller diagram. Per online research on controller
    /// diagnostic UIs (GamePadViewer, Steam Input Test, Adobe UX guide),
    /// the dominant pattern is a silhouette that mirrors the physical
    /// layout — D-pad bottom-left, sticks middle, face buttons
    /// bottom-right, shoulders top. Recognition over recall.
    ///
    /// All clusters fit inside one viewport (no scroll). No focusable
    /// elements — D-pad presses don't move SwiftUI focus or scroll.
    private var diagnosticGrid: some View {
        let c = snapshot.controllers[0]
        let exitProgress = min(1.0, maxHoldDuration / exitHoldThreshold)

        return VStack(spacing: Theme.space6) {
            // Shoulders / triggers (top of the controller)
            HStack(alignment: .top, spacing: Theme.space7) {
                shoulderColumn(buttons: c.buttons,
                               trigger: "Left Trigger",
                               shoulder: "Left Shoulder",
                               triggerLabel: "L2", shoulderLabel: "L1")
                Spacer(minLength: Theme.space7)
                shoulderColumn(buttons: c.buttons,
                               trigger: "Right Trigger",
                               shoulder: "Right Shoulder",
                               triggerLabel: "R2", shoulderLabel: "R1")
            }
            .padding(.horizontal, Theme.screenInset)

            // Main controls row: D-pad / Sticks / Face buttons
            HStack(alignment: .top, spacing: Theme.space7) {
                dpadCluster(buttons: c.buttons)
                Spacer()
                stickCluster(buttons: c.buttons)
                Spacer()
                faceButtonCluster(buttons: c.buttons)
            }
            .padding(.horizontal, Theme.screenInset)

            // System buttons row (Menu / Options / Home / Share /
            // Touchpad — only the ones the controller actually exposes)
            HStack(spacing: Theme.space4) {
                ForEach(systemButtons(in: c.buttons), id: \.name) { b in
                    pillIndicator(label: shortName(b.name), pressed: b.pressed)
                }
            }

            Spacer(minLength: 0)

            exitHint(progress: exitProgress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, Theme.space6)
        // No .onExitCommand — it would let the Menu / B button exit
        // instantly, defeating the purpose. Exit is hold-any-button-2s.
    }

    // MARK: - Cluster subviews (per swiftui-patterns view-composition rule)

    /// L1/L2 or R1/R2 stack (one shoulder + one trigger).
    private func shoulderColumn(buttons: [ControllerSnapshot.Button],
                                trigger: String, shoulder: String,
                                triggerLabel: String,
                                shoulderLabel: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.space3) {
            shoulderBar(label: triggerLabel, pressed: pressed(trigger, in: buttons))
            shoulderBar(label: shoulderLabel, pressed: pressed(shoulder, in: buttons))
        }
    }

    private func shoulderBar(label: String, pressed isPressed: Bool) -> some View {
        Text(label)
            .font(.system(.body).weight(.semibold))
            .foregroundStyle(isPressed ? Theme.ink900 : .primary)
            .frame(width: 200, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPressed ? Theme.green500 : Color.white.opacity(0.08))
            )
            .animation(.easeOut(duration: 0.10), value: isPressed)
    }

    /// D-pad cross. Up, then [Left, Right], then Down.
    private func dpadCluster(buttons: [ControllerSnapshot.Button]) -> some View {
        VStack(spacing: Theme.space3) {
            clusterCaption("D-PAD")
            VStack(spacing: Theme.space2) {
                dpadKey("↑", pressed: pressed("Direction Pad Up", in: buttons))
                HStack(spacing: Theme.space2) {
                    dpadKey("←", pressed: pressed("Direction Pad Left", in: buttons))
                    Color.clear.frame(width: 56, height: 56)
                    dpadKey("→", pressed: pressed("Direction Pad Right", in: buttons))
                }
                dpadKey("↓", pressed: pressed("Direction Pad Down", in: buttons))
            }
        }
    }

    private func dpadKey(_ glyph: String, pressed isPressed: Bool) -> some View {
        Text(glyph)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(isPressed ? Theme.ink900 : .primary)
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isPressed ? Theme.green500 : Color.white.opacity(0.08))
            )
            .animation(.easeOut(duration: 0.10), value: isPressed)
    }

    /// Two analog stick indicators with click-button states.
    private func stickCluster(buttons: [ControllerSnapshot.Button]) -> some View {
        VStack(spacing: Theme.space3) {
            clusterCaption("STICKS")
            HStack(spacing: Theme.space5) {
                stickIndicator(label: "L",
                               clickPressed: pressed("Left Thumbstick Button", in: buttons))
                stickIndicator(label: "R",
                               clickPressed: pressed("Right Thumbstick Button", in: buttons))
            }
        }
    }

    private func stickIndicator(label: String, clickPressed: Bool) -> some View {
        ZStack {
            Circle()
                .fill(clickPressed ? Theme.green500 : Color.white.opacity(0.08))
                .frame(width: 88, height: 88)
            Text(label)
                .font(.system(.title3).weight(.semibold))
                .foregroundStyle(clickPressed ? Theme.ink900 : .primary)
        }
        .animation(.easeOut(duration: 0.10), value: clickPressed)
    }

    /// Face-button diamond — Y top, X left, B right, A bottom.
    private func faceButtonCluster(buttons: [ControllerSnapshot.Button]) -> some View {
        VStack(spacing: Theme.space3) {
            clusterCaption("FACE BUTTONS")
            VStack(spacing: Theme.space2) {
                faceKey("Y", pressed: pressed("Button Y", in: buttons))
                HStack(spacing: Theme.space2) {
                    faceKey("X", pressed: pressed("Button X", in: buttons))
                    Color.clear.frame(width: 56, height: 56)
                    faceKey("B", pressed: pressed("Button B", in: buttons))
                }
                faceKey("A", pressed: pressed("Button A", in: buttons))
            }
        }
    }

    private func faceKey(_ glyph: String, pressed isPressed: Bool) -> some View {
        Text(glyph)
            .font(.system(size: 26, weight: .heavy))
            .foregroundStyle(isPressed ? Theme.ink900 : .primary)
            .frame(width: 56, height: 56)
            .background(
                Circle()
                    .fill(isPressed ? Theme.green500 : Color.white.opacity(0.08))
            )
            .animation(.easeOut(duration: 0.10), value: isPressed)
    }

    /// System buttons (Menu / Options / Home / Share / Touchpad) as
    /// rounded pills. Only renders the ones this controller exposes.
    private func systemButtons(in buttons: [ControllerSnapshot.Button])
        -> [ControllerSnapshot.Button]
    {
        let preferred = ["Button Share", "Button Options",
                         "Button Menu", "Button Home", "Touchpad"]
        var result: [ControllerSnapshot.Button] = []
        for name in preferred {
            if let b = buttons.first(where: { $0.name == name }) {
                result.append(b)
            }
        }
        return result
    }

    private func pillIndicator(label: String, pressed isPressed: Bool) -> some View {
        Text(label)
            .font(.system(.footnote).weight(.semibold))
            .foregroundStyle(isPressed ? Theme.ink900 : .secondary)
            .padding(.horizontal, Theme.space4)
            .padding(.vertical, Theme.space2)
            .background(
                Capsule().fill(isPressed
                               ? Theme.green500
                               : Color.white.opacity(0.06))
            )
            .animation(.easeOut(duration: 0.10), value: isPressed)
    }

    private func clusterCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2).weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }

    /// Shorten the GameController button name to its display form
    /// ("Button Menu" → "Menu", etc.).
    private func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: "Button ", with: "")
    }

    private func pressed(_ buttonName: String,
                         in buttons: [ControllerSnapshot.Button]) -> Bool {
        buttons.first(where: { $0.name == buttonName })?.pressed ?? false
    }

    /// Footer with the exit instruction + a thin progress bar that
    /// fills as the user holds a button toward the 2-second threshold.
    @ViewBuilder
    private func exitHint(progress: Double) -> some View {
        VStack(spacing: Theme.space2) {
            Text(progress > 0
                 ? "Keep holding to exit…"
                 : "Hold any button for 2 seconds to exit diagnostic")
                .font(.system(.footnote))
                .foregroundStyle(.secondary)

            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(progress >= 1.0 ? Theme.green500 : Theme.amber500)
                .frame(width: 320)
                .opacity(progress > 0 ? 1.0 : 0.0)
        }
        .padding(.bottom, Theme.space5)
        .animation(.easeOut(duration: 0.12), value: progress)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                let newSnap = ControllerSnapshot.capture()
                snapshot = newSnap

                if diagnosticActive {
                    updateHoldExit(snapshot: newSnap)
                } else if !pressStarts.isEmpty || maxHoldDuration > 0 {
                    pressStarts.removeAll()
                    maxHoldDuration = 0
                }

                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Track per-button hold duration; fire the exit when any button has
    /// been held continuously for `exitHoldThreshold`.
    @MainActor
    private func updateHoldExit(snapshot: ControllerSnapshot) {
        let now = Date()
        var longest: TimeInterval = 0
        var shouldExit = false

        for c in snapshot.controllers {
            for btn in c.buttons {
                if btn.pressed {
                    if pressStarts[btn.name] == nil {
                        pressStarts[btn.name] = now
                    }
                    if let start = pressStarts[btn.name] {
                        let held = now.timeIntervalSince(start)
                        longest = max(longest, held)
                        if held >= exitHoldThreshold {
                            shouldExit = true
                        }
                    }
                } else {
                    pressStarts.removeValue(forKey: btn.name)
                }
            }
        }

        maxHoldDuration = longest

        if shouldExit {
            diagnosticActive = false
            pressStarts.removeAll()
            maxHoldDuration = 0
        }
    }
}

// MARK: - Controller snapshot

private struct ControllerSnapshot {
    var controllers: [Entry] = []

    struct Entry {
        let vendorName: String
        let profileClass: String
        let hasHome: Bool
        let buttons: [Button]
    }

    struct Button {
        let name: String
        let pressed: Bool
    }

    struct Group: Identifiable {
        let id = UUID()
        let title: String
        let buttons: [Button]
    }

    static func capture() -> ControllerSnapshot {
        let entries = GCController.controllers().map { c -> Entry in
            let profile = c.physicalInputProfile
            let sortedKeys = profile.buttons.keys.sorted()
            let buttons = sortedKeys.map { key in
                Button(name: key, pressed: profile.buttons[key]?.isPressed ?? false)
            }
            let hasHome = profile.buttons[GCInputButtonHome] != nil
            let profileClass = String(describing: type(of: c.extendedGamepad ?? profile))
            return Entry(
                vendorName: c.vendorName ?? "Unknown",
                profileClass: profileClass,
                hasHome: hasHome,
                buttons: buttons
            )
        }
        return ControllerSnapshot(controllers: entries)
    }

    static func cluster(buttons: [Button]) -> [Group] {
        let buckets: [(title: String, contains: [String])] = [
            ("Face buttons", ["Button A", "Button B", "Button X", "Button Y"]),
            ("D-pad",        ["Direction Pad"]),
            ("Shoulders",    ["Left Shoulder", "Right Shoulder",
                              "Left Trigger",  "Right Trigger"]),
            ("Left stick",   ["Left Thumbstick"]),
            ("Right stick",  ["Right Thumbstick"]),
            ("System",       ["Button Menu", "Button Options", "Button Home",
                              "Button Share", "Touchpad"])
        ]

        var assigned = Set<String>()
        var groups: [Group] = []
        for bucket in buckets {
            let matches = buttons.filter { btn in
                bucket.contains.contains { btn.name.contains($0) }
            }
            if !matches.isEmpty {
                groups.append(Group(title: bucket.title, buttons: matches))
                matches.forEach { assigned.insert($0.name) }
            }
        }

        let leftovers = buttons.filter { !assigned.contains($0.name) }
        if !leftovers.isEmpty {
            groups.append(Group(title: "Other", buttons: leftovers))
        }
        return groups
    }
}

#Preview {
    SettingsView()
        .environment(AppState.preview())
}
