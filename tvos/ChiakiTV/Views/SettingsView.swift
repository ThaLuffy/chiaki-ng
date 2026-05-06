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
            HStack(alignment: .top, spacing: Theme.space6) {
                rail
                detailContent
                    .frame(maxWidth: 1200, alignment: .topLeading)
            }
            .padding(.horizontal, Theme.space7)
            .padding(.top, Theme.space4)
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
        VStack(alignment: .leading, spacing: Theme.space2) {
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

                Picker("Bitrate", selection: $appState.settings.bitrateKbps) {
                    ForEach(Array(stride(from: 2_000, through: 50_000, by: 500)), id: \.self) { v in
                        Text("\(v / 1000) Mbps").tag(v)
                    }
                }
            } header: {
                Text("Quality")
            } footer: {
                Text("Higher quality costs ~1–2 ms of decode latency. Bitrate is a hard ceiling — the PS5 adapts down on a weak link.")
            }

            Section {
                Toggle("Vertical sync", isOn: $appState.settings.verticalSync)
            } footer: {
                Text("Reduces tearing. Adds ~16 ms of latency.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Reusable segmented-row helper. tvOS hides `Picker.title` when
/// `.pickerStyle(.segmented)` is applied, so we wrap the picker in a
/// `LabeledContent` to keep the label visible. Using a single helper
/// instead of inline call-sites makes every segmented row identically
/// shaped — a precondition for visual rhythm in a `Form`.
@ViewBuilder
fileprivate func segmentedRow<T: Hashable, S: RandomAccessCollection>(
    _ label: String,
    selection: Binding<T>,
    options: S,
    text: @escaping (T) -> String
) -> some View where S.Element == T, S: Sendable {
    LabeledContent(label) {
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
                Picker("Audio buffer", selection: $appState.settings.audioBufferMs) {
                    ForEach(Array(stride(from: 20, through: 500, by: 10)), id: \.self) { v in
                        Text("\(v) ms").tag(v)
                    }
                }

                Picker("Volume", selection: $appState.settings.audioVolume) {
                    ForEach(Array(stride(from: 0, through: 100, by: 5)), id: \.self) { v in
                        Text("\(v)%").tag(v)
                    }
                }
            } header: {
                Text("Audio")
            } footer: {
                Text("A higher buffer means smoother audio at the cost of mouth-to-ear latency.")
            }

            Section {
                Picker("Weak Wi-Fi threshold",
                       selection: $appState.settings.weakWifiThresholdPct) {
                    ForEach(1...20, id: \.self) { v in
                        Text("\(v)%").tag(v)
                    }
                }

                Picker("Reported loss ceiling",
                       selection: $appState.settings.packetLossReportedMax) {
                    ForEach(1...20, id: \.self) { v in
                        Text("\(v)%").tag(v)
                    }
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
                Button {
                    psnDraft = appState.settings.psnAccountId
                    psnPromptShown = true
                } label: {
                    HStack {
                        Text("PSN Account-ID")
                        Spacer()
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
                Toggle("Streamer Mode", isOn: $appState.settings.streamerMode)
                Toggle("Verbose Logs", isOn: $appState.settings.verboseLogs)
                Toggle("Show Stream Stats", isOn: $appState.settings.showStreamStats)
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
            if appState.registeredHosts.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No registered consoles",
                        systemImage: "gamecontroller",
                        description: Text("Pair a PS5 to use Remote Play without re-entering a PIN every time.")
                    )
                }
            } else {
                Section {
                    ForEach(appState.registeredHosts) { host in
                        LabeledContent(host.nickname) {
                            HStack(spacing: 16) {
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
                                .buttonStyle(.card)
                            }
                        }
                    }
                } header: {
                    Text("Registered consoles")
                }
            }

            Section {
                Button {
                    appState.showRegistration(for: Host(
                        id: UUID().uuidString,
                        nickname: "New PS5",
                        ipAddress: ""
                    ))
                } label: {
                    Label("Register a new console", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.card)
            }
        }
        .formStyle(.grouped)

    }
}

// MARK: - Controller diagnostic tab

private struct ControllerDiagnosticTab: View {
    @State private var snapshot = ControllerSnapshot()
    @State private var pollTask: Task<Void, Never>? = nil

    var body: some View {
        Form {
            if snapshot.controllers.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No controllers connected",
                        systemImage: "gamecontroller",
                        description: Text("Pair a DualSense or MFi controller in tvOS Settings → Remotes & Devices.")
                    )
                }
            } else {
                ForEach(0..<snapshot.controllers.count, id: \.self) { idx in
                    controllerSections(snapshot.controllers[idx])
                }
            }
        }
        .formStyle(.grouped)

        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    @ViewBuilder
    private func controllerSections(_ c: ControllerSnapshot.Entry) -> some View {
        Section {
            LabeledContent("Profile") {
                Text(c.profileClass)
                    .font(Theme.font(.mono))
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Home button") {
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

        let groups = ControllerSnapshot.cluster(buttons: c.buttons)
        ForEach(groups) { group in
            Section {
                ForEach(0..<group.buttons.count, id: \.self) { i in
                    let b = group.buttons[i]
                    LabeledContent(b.name) {
                        Image(systemName: b.pressed
                              ? "circle.fill" : "circle")
                            .foregroundStyle(b.pressed
                                             ? Theme.green500
                                             : .secondary)
                    }
                }
            } header: {
                Text(group.title)
            }
        }
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
