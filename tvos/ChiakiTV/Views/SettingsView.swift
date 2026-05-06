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
        if appState.registeredHosts.isEmpty {
            // SwiftUI's canonical empty-state pattern: ContentUnavailableView
            // with an `actions:` block. When the list is empty, we drop the
            // Form chrome entirely so the empty state can center properly
            // (Form rows force leading text alignment and break the
            // ContentUnavailableView's centered layout).
            ContentUnavailableView {
                Label("No registered consoles", systemImage: "gamecontroller")
            } description: {
                Text("Pair a PS5 to use Remote Play without re-entering a PIN every time.")
            } actions: {
                Button {
                    appState.showRegistration(for: Host(
                        id: UUID().uuidString,
                        nickname: "New PS5",
                        ipAddress: ""
                    ))
                } label: {
                    Label("Register a new console", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
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
}

// MARK: - Controller diagnostic tab

private struct ControllerDiagnosticTab: View {
    @State private var snapshot = ControllerSnapshot()
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var diagnosticActive = false

    var body: some View {
        Group {
            if snapshot.controllers.isEmpty {
                ContentUnavailableView {
                    Label("No controllers connected", systemImage: "gamecontroller")
                } description: {
                    Text("Pair a DualSense or MFi controller in tvOS Settings → Remotes & Devices.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diagnosticActive {
                diagnosticGrid
            } else {
                idleView
            }
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
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

    private var diagnosticGrid: some View {
        let c = snapshot.controllers[0]
        let columns = [
            GridItem(.flexible(), spacing: Theme.space5),
            GridItem(.flexible(), spacing: Theme.space5)
        ]

        return VStack(spacing: Theme.space6) {
            diagnosticHeader(for: c)

            LazyVGrid(columns: columns,
                      alignment: .leading,
                      spacing: Theme.space5) {
                ForEach(c.buttons, id: \.name) { b in
                    HStack {
                        Image(systemName: b.pressed
                              ? "circle.fill" : "circle")
                            .foregroundStyle(b.pressed
                                             ? Theme.green500
                                             : .secondary)
                        Text(b.name)
                            .font(.system(.body, design: .default))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.space2)
                    .padding(.horizontal, Theme.space4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(b.pressed ? 0.10 : 0.04))
                    )
                }
            }
            .padding(.horizontal, Theme.screenInset)

            Spacer(minLength: 0)

            Text("Press Menu / B to exit diagnostic")
                .font(.system(.footnote))
                .foregroundStyle(.secondary)
                .padding(.bottom, Theme.space5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, Theme.space6)
        .onExitCommand { diagnosticActive = false }
    }

    private func diagnosticHeader(for c: ControllerSnapshot.Entry) -> some View {
        VStack(spacing: Theme.space2) {
            Text(c.vendorName)
                .font(.system(.title2).weight(.semibold))
            Text(c.profileClass)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                snapshot = ControllerSnapshot.capture()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
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
