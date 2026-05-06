// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import GameController

/// Settings screen with a vertical rail navigator per
/// [`docs/ui/redesign-plan.md §4.2 + §5.2`](../../docs/ui/redesign-plan.md).
///
/// Five tabs (re-named + re-ordered from the original General / Video /
/// Audio / Consoles / Controller — content unchanged in this step; row
/// rework lives in §4.4 / Step 4):
///
/// 1. **Stream** — resolution, FPS, bitrate, codec, render preset.
///    *Was "Video & Stream".*
/// 2. **Network** — buffer, volume, weak-wifi + packet-loss thresholds.
///    *Was "Audio". Renamed because half the rows are network diagnostics.*
/// 3. **Controller** — DualSense / MFi diagnostic surface.
/// 4. **Consoles** — registered host list + "Register New Console" CTA.
/// 5. **App** — disconnect/suspend behavior, streamer mode, verbose logs,
///    PSN account ID. *Was "General". Renamed; "General" is meaningless.*
///
/// The rail anchors left at 220pt; tab content fills the remaining 1700pt
/// (resolves audit issue S1 — the centered narrow form).
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: SettingsTab = .stream

    var body: some View {
        ChiakiDialogChrome(
            title: "Settings",
            subtitle: "* Defaults marked with (Default)",
            onBack: { appState.showHostList() }
        ) {
            EmptyView()
        } content: {
            HStack(spacing: 0) {
                rail
                contentArea
            }
        }
    }

    // MARK: - Vertical rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsRailButton(tab: tab,
                                   isSelected: selectedTab == tab) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                }
            }
            Spacer()
        }
        .frame(width: Theme.settingsRailWidth, alignment: .topLeading)
        .padding(.top, 32)
        .padding(.horizontal, 12)
        .focusSection()
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        Group {
            switch selectedTab {
            case .stream:     VideoStreamTab()
            case .network:    AudioTab()
            case .controller: ControllerDiagnosticTab()
            case .consoles:   ConsolesTab()
            case .app:        GeneralTab()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 24)
        .padding(.horizontal, 24)
        .focusSection()
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

    /// SF Symbol for the rail icon — kept in the same family as the
    /// previous TabView icons so muscle memory carries over.
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

// MARK: - Rail button

private struct SettingsRailButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Active-state amber bar on the left edge.
                Rectangle()
                    .fill(isSelected ? Theme.amber500 : Color.clear)
                    .frame(width: 4)

                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 28)

                Text(tab.label)
                    .font(Theme.font(.titleMed))

                Spacer(minLength: 0)
            }
            .foregroundStyle(textColor)
            .frame(height: Theme.settingsRailItemHeight)
            .padding(.trailing, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFocused ? Theme.ink700
                                    : (isSelected ? Theme.ink800.opacity(0.6)
                                                  : Color.clear))
            )
            .scaleEffect(isFocused ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .chiakiFocusRing(isFocused, cornerRadius: 12)
        .animation(Theme.focusSpring, value: isFocused)
    }

    private var textColor: Color {
        if isFocused { return Theme.white50 }
        if isSelected { return Theme.amber500 }
        return Theme.mist500
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Environment(AppState.self) private var appState

    @State private var psnPromptShown = false
    @State private var psnDraft: String = ""

    var body: some View {
        @Bindable var appState = appState
        SettingsForm {
            SettingsRow(label: "Action On Disconnect:") {
                Picker("", selection: $appState.settings.actionOnDisconnect) {
                    ForEach(DisconnectAction.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            SettingsRow(label: "Action On Suspend:") {
                Picker("", selection: $appState.settings.actionOnSuspend) {
                    ForEach(SuspendAction.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            SettingsRow(label: "Audio + Video:") {
                Picker("", selection: $appState.settings.audioVideoMode) {
                    ForEach(AudioVideoMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            SettingsRow(label: "PSN Account-ID (12-char base64):") {
                psnAccountIdButton
            }

            SettingsRow(label: "Streamer Mode:") {
                Toggle("", isOn: $appState.settings.streamerMode)
                    .labelsHidden()
                    .frame(width: Theme.dialogFieldWidth, alignment: .leading)
            }

            SettingsRow(label: "Verbose Logs:") {
                Toggle("", isOn: $appState.settings.verboseLogs)
                    .labelsHidden()
                    .frame(width: Theme.dialogFieldWidth, alignment: .leading)
            }

            SettingsRow(label: "Show Stream Stats:") {
                Toggle("", isOn: $appState.settings.showStreamStats)
                    .labelsHidden()
                    .frame(width: Theme.dialogFieldWidth, alignment: .leading)
            }
        }
    }

    /// PSN account ID is a base64 string. tvOS's plain `TextField` doesn't
    /// participate cleanly in the focus engine when wrapped in a custom row
    /// (see `RegistrationView` for the same pattern). A focusable `Button`
    /// that pops a system `.alert` with the real `TextField` is the
    /// reliable tvOS path.
    private var psnAccountIdButton: some View {
        @Bindable var appState = appState
        return Button {
            psnDraft = appState.settings.psnAccountId
            psnPromptShown = true
        } label: {
            HStack {
                Text(appState.settings.psnAccountId.isEmpty
                     ? "AAAAAAAAAAAAAAAA=="
                     : appState.settings.psnAccountId)
                    .font(.system(size: Theme.baseFontSize))
                    .foregroundStyle(appState.settings.psnAccountId.isEmpty
                                     ? Theme.tertiaryText
                                     : Theme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(width: Theme.dialogFieldWidth)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .fill(Theme.surface)
            )
        }
        .buttonStyle(.plain)
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

// MARK: - Video & Stream

private struct VideoStreamTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsForm {
            SettingsRow(label: "Resolution:") {
                Picker("", selection: $appState.settings.resolution) {
                    ForEach(VideoResolution.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            SettingsRow(label: "FPS:") {
                Picker("", selection: $appState.settings.fps) {
                    ForEach(VideoFPS.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            SettingsRow(label: "Bitrate (kbps):") {
                stepperRow(value: $appState.settings.bitrateKbps,
                           range: 2_000...50_000, step: 500,
                           display: "\(appState.settings.bitrateKbps)")
            }

            SettingsRow(label: "Codec:") {
                Picker("", selection: $appState.settings.codec) {
                    ForEach(VideoCodec.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            SettingsRow(label: "Render Preset:") {
                Picker("", selection: $appState.settings.renderPreset) {
                    ForEach(RenderPreset.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            SettingsRow(label: "Vertical Sync:") {
                Toggle("", isOn: $appState.settings.verticalSync)
                    .labelsHidden()
                    .frame(width: Theme.dialogFieldWidth, alignment: .leading)
            }
        }
    }
}

// MARK: - Audio

private struct AudioTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsForm {
            SettingsRow(label: "Audio Buffer (ms):") {
                stepperRow(value: $appState.settings.audioBufferMs,
                           range: 10...500, step: 10,
                           display: "\(appState.settings.audioBufferMs)")
            }

            SettingsRow(label: "Audio Volume:") {
                stepperRow(value: $appState.settings.audioVolume,
                           range: 0...100, step: 5,
                           display: "\(appState.settings.audioVolume)")
            }

            SettingsRow(label: "Weak Wifi Notification (% packet loss):") {
                stepperRow(value: $appState.settings.weakWifiThresholdPct,
                           range: 0...100, step: 1,
                           display: "\(appState.settings.weakWifiThresholdPct)")
            }

            SettingsRow(label: "Packet Loss Reported Max:") {
                stepperRow(value: $appState.settings.packetLossReportedMax,
                           range: 0...100, step: 1,
                           display: "\(appState.settings.packetLossReportedMax)")
            }
        }
    }
}

// MARK: - Stepper helper

private func stepperRow(value: Binding<Int>, range: ClosedRange<Int>,
                        step: Int, display: String) -> some View {
    ChiakiStepper(value: value, range: range, step: step)
        .frame(width: Theme.dialogFieldWidth, alignment: .leading)
}

// MARK: - Consoles

private struct ConsolesTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.dialogRowSpacing) {
            Text("Registered Consoles")
                .font(.system(size: Theme.dialogTitleFontSize, weight: .bold))
                .foregroundStyle(Theme.primaryText)

            if appState.registeredHosts.isEmpty {
                Text("No consoles registered yet.")
                    .font(.system(size: Theme.baseFontSize))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(appState.registeredHosts) { host in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(host.nickname)
                                .foregroundStyle(Theme.primaryText)
                            Text(host.mac)
                                .font(.system(size: Theme.dialogHeaderFontSize))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        Spacer()
                        ChiakiButton(title: "Delete", systemImage: "trash") {
                            appState.registeredHosts.removeAll { $0.id == host.id }
                        }
                    }
                    .padding(.vertical, 8)
                    Divider().background(Theme.tertiaryText)
                }
            }

            Spacer().frame(height: 20)

            ChiakiButton(title: "Register New Console",
                         systemImage: "plus.circle.fill") {
                appState.showRegistration(for: Host(
                    id: UUID().uuidString,
                    nickname: "New PS5",
                    ipAddress: ""
                ))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Form helpers

private struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.dialogRowSpacing) {
                content()
            }
            .padding(40)
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.dialogColumnSpacing) {
            Text(label)
                .font(.system(size: Theme.baseFontSize))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 360, alignment: .trailing)
            trailing()
            Spacer()
        }
    }
}

// MARK: - Controller Diagnostic
//
// Live-poll snapshot of every connected GCController. Shows the vendor name,
// the concrete profile class (GCExtendedGamepad / GCDualSenseGamepad /
// GCXboxGamepad), whether the Home button is exposed, and a button list with
// per-button press feedback. Used to verify that Info.plist profile changes
// surfaced new buttons (Home, Touchpad, Share) without round-tripping through
// Console.app to read chiakiLog output.
private struct ControllerDiagnosticTab: View {
    @State private var snapshot = ControllerSnapshot()
    @State private var pollTask: Task<Void, Never>? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Controller Diagnostic")
                    .font(.system(size: Theme.dialogTitleFontSize, weight: .bold))
                    .foregroundStyle(Theme.primaryText)

                Text("Live snapshot of every connected GCController. Press a button to verify mapping; the dot lights green when the framework reports it pressed.")
                    .font(.system(size: Theme.dialogHeaderFontSize))
                    .foregroundStyle(Theme.tertiaryText)

                if snapshot.controllers.isEmpty {
                    Text("No controllers connected.")
                        .font(.system(size: Theme.baseFontSize))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 12)
                } else {
                    ForEach(0..<snapshot.controllers.count, id: \.self) { idx in
                        controllerCard(snapshot.controllers[idx])
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    @ViewBuilder
    private func controllerCard(_ c: ControllerSnapshot.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.vendorName)
                .font(.system(size: Theme.dialogTitleFontSize, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Profile: \(c.profileClass)")
                .font(.system(size: Theme.dialogHeaderFontSize))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 8) {
                Circle()
                    .fill(c.hasHome ? Color.green : Theme.errorRed)
                    .frame(width: 14, height: 14)
                Text(c.hasHome ? "Home button exposed" : "Home button NOT exposed")
                    .font(.system(size: Theme.baseFontSize))
                    .foregroundStyle(Theme.primaryText)
            }
            Divider().background(Theme.tertiaryText).padding(.vertical, 4)
            Text("Buttons (\(c.buttons.count))")
                .font(.system(size: Theme.dialogHeaderFontSize, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
            ForEach(0..<c.buttons.count, id: \.self) { i in
                let b = c.buttons[i]
                HStack(spacing: 10) {
                    Circle()
                        .fill(b.pressed ? Color.green : Color.white.opacity(0.18))
                        .frame(width: 12, height: 12)
                    Text(b.name)
                        .font(.system(size: Theme.baseFontSize))
                        .foregroundStyle(b.pressed ? Theme.primaryText : Theme.secondaryText)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
}

#Preview {
    SettingsView()
        .environment(AppState.preview())
}
