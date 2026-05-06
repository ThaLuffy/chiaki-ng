// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import GameController

/// Settings screen — slimmed projection of
/// [`gui/src/qml/SettingsDialog.qml`](../../../gui/src/qml/SettingsDialog.qml).
///
/// Four tabs (down from the desktop's nine — see [`docs/ui/swift-ui-plan.md`](../../docs/ui/swift-ui-plan.md) §1):
///   1. **General** — disconnect/suspend behavior + PSN Account-ID prefill.
///   2. **Video & Stream** — resolution, FPS, bitrate, codec, render preset.
///   3. **Audio** — buffer + volume + WiFi notification thresholds.
///   4. **Consoles** — registered hosts list + "Register New Console" CTA.
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ChiakiDialogChrome(
            title: "Settings",
            subtitle: "* Defaults marked with (Default)",
            onBack: { appState.showHostList() }
        ) {
            // No primary action button on the Settings screen — desktop's
            // SettingsDialog has `buttonVisible: false`.
            EmptyView()
        } content: {
            TabView {
                GeneralTab()
                    .tabItem { Label("General", systemImage: "slider.horizontal.3") }

                VideoStreamTab()
                    .tabItem { Label("Video & Stream", systemImage: "tv") }

                AudioTab()
                    .tabItem { Label("Audio", systemImage: "speaker.wave.2.fill") }

                ConsolesTab()
                    .tabItem { Label("Consoles", systemImage: "gamecontroller.fill") }

                ControllerDiagnosticTab()
                    .tabItem { Label("Controller", systemImage: "dot.radiowaves.left.and.right") }
            }
        }
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
