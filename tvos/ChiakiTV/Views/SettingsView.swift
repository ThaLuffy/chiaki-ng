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

// MARK: - Stream tab (was Video & Stream)
//
// Cycling enums become ChiakiSegmented; the bitrate stepper becomes a slider.

private struct VideoStreamTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsForm {
            SettingsRow(label: "Resolution") {
                ChiakiSegmented(
                    selection: $appState.settings.resolution,
                    options: VideoResolution.allCases,
                    label: { $0.label }
                )
            }

            SettingsRow(label: "Refresh rate") {
                ChiakiSegmented(
                    selection: $appState.settings.fps,
                    options: VideoFPS.allCases,
                    label: { $0.label }
                )
            }

            SettingsRow(label: "Codec") {
                ChiakiSegmented(
                    selection: $appState.settings.codec,
                    options: VideoCodec.allCases,
                    label: { $0.label }
                )
            }

            SettingsRow(label: "Render preset",
                        hint: "Higher quality costs ~1–2 ms of decode latency.") {
                ChiakiSegmented(
                    selection: $appState.settings.renderPreset,
                    options: RenderPreset.allCases,
                    label: { $0.label }
                )
            }

            SettingsRow(label: "Bitrate",
                        hint: "Hard ceiling. The PS5 will adapt downward on a weak link.") {
                ChiakiSlider(
                    value: $appState.settings.bitrateKbps,
                    range: 2_000...50_000, step: 500,
                    format: { "\($0 / 1000) Mbps" }
                )
            }

            SettingsRow(label: "Vertical sync",
                        hint: "Reduces tearing. Adds ~16 ms of latency.") {
                Toggle("", isOn: $appState.settings.verticalSync)
                    .labelsHidden()
                    .tint(Theme.amber500)
            }
        }
    }
}

// MARK: - Network tab (was Audio)
//
// Audio buffer + audio volume are kept here because the Network tab is
// "things that affect the streaming pipeline" — buffer size *is* a network
// vs. latency tradeoff. Volume stays adjacent to buffer for ergonomic
// reasons. The two diagnostic thresholds (weak-wifi, packet-loss-reported)
// finally have a coherent home.

private struct AudioTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsForm {
            SettingsRow(label: "Audio buffer",
                        hint: "Higher = smoother audio, more lag-to-mouth.") {
                ChiakiSlider(
                    value: $appState.settings.audioBufferMs,
                    range: 20...500, step: 10,
                    format: { "\($0) ms" }
                )
            }

            SettingsRow(label: "Volume") {
                ChiakiSlider(
                    value: $appState.settings.audioVolume,
                    range: 0...100, step: 5,
                    format: { "\($0)%" }
                )
            }

            SettingsRow(label: "Weak Wi-Fi threshold",
                        hint: "Show a warning when sustained packet loss exceeds this percentage.") {
                ChiakiSlider(
                    value: $appState.settings.weakWifiThresholdPct,
                    range: 1...20, step: 1,
                    format: { "\($0)%" }
                )
            }

            SettingsRow(label: "Reported loss ceiling",
                        hint: "Cap reported packet loss in stream stats. Diagnostic.") {
                ChiakiSlider(
                    value: $appState.settings.packetLossReportedMax,
                    range: 1...20, step: 1,
                    format: { "\($0)%" }
                )
            }
        }
    }
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
//
// The redesigned form (per docs/ui/redesign-plan.md §4.4) drops the centred-
// narrow column layout in favour of full-bleed rows with a left-anchored
// label and a right-anchored control. Optional `hint` adds a third line of
// italic mist-500 sub-text under the label for non-obvious tradeoffs.

private struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(label: String, hint: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.hint = hint
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(Theme.font(.titleMed))
                    .foregroundStyle(Theme.mist300)
                if let hint {
                    Text(hint)
                        .font(Theme.font(.bodySmall))
                        .foregroundStyle(Theme.mist500)
                        .italic()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
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
            VStack(alignment: .leading, spacing: 24) {
                if snapshot.controllers.isEmpty {
                    emptyState
                } else {
                    ForEach(0..<snapshot.controllers.count, id: \.self) { idx in
                        controllerCard(snapshot.controllers[idx])
                    }
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(Theme.mist500)
            Text("No controllers connected.")
                .font(Theme.font(.titleMed))
                .foregroundStyle(Theme.mist300)
            Text("Pair a DualSense or MFi controller in tvOS Settings → Remotes & Devices.")
                .font(Theme.font(.bodyMed))
                .foregroundStyle(Theme.mist500)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    @ViewBuilder
    private func controllerCard(_ c: ControllerSnapshot.Entry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header — vendor name big, profile + home-status as adjacent chips.
            VStack(alignment: .leading, spacing: 8) {
                Text(c.vendorName)
                    .font(Theme.font(.displaySmall))
                    .foregroundStyle(Theme.white50)
                HStack(spacing: 10) {
                    statusChip(label: c.profileClass,
                               color: Theme.psBlue, glyph: "rectangle.connected.to.line.below")
                    statusChip(label: c.hasHome ? "HOME EXPOSED" : "HOME NOT EXPOSED",
                               color: c.hasHome ? Theme.green500 : Theme.rose500,
                               glyph: c.hasHome ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                }
            }

            // Button cluster grid.
            buttonClusters(for: c)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.ink800)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.ink600, lineWidth: 1)
        )
    }

    /// Renders the button list grouped by physical cluster. Resolves audit
    /// issue Co1 (alphabetical sort scattered logically-grouped inputs).
    private func buttonClusters(for c: ControllerSnapshot.Entry) -> some View {
        let groups = ControllerSnapshot.cluster(buttons: c.buttons)
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title.uppercased())
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.mist500)
                        .tracking(1.4)

                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 6)
                    ], alignment: .leading, spacing: 6) {
                        ForEach(0..<group.buttons.count, id: \.self) { i in
                            buttonRow(group.buttons[i])
                        }
                    }
                }
            }
        }
    }

    private func buttonRow(_ b: ControllerSnapshot.Button) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(b.pressed ? Theme.green500 : Theme.ink600)
                .frame(width: 10, height: 10)
                .shadow(color: b.pressed ? Theme.green500.opacity(0.6) : .clear,
                        radius: 5)
            Text(b.name)
                .font(Theme.font(.bodyMed))
                .foregroundStyle(b.pressed ? Theme.white50 : Theme.mist500)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func statusChip(label: String, color: Color, glyph: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(Theme.font(.monoSmall))
                .tracking(1.0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(color.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(color.opacity(0.5), lineWidth: 1)
        )
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

    /// A logically-grouped subset of inputs. Used by the redesigned
    /// diagnostic to render thumb cluster / d-pad / etc as separate groups
    /// instead of one alphabetical wall of text.
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

    /// Bucket the alphabetical button list by physical cluster. Anything
    /// that doesn't match a known cluster lands in "Other" so the grouping
    /// stays loss-less even when GameController surfaces a vendor-specific
    /// input we didn't anticipate.
    static func cluster(buttons: [Button]) -> [Group] {
        // Match against substrings of GCController's input identifiers
        // (GCInputButtonA / GCInputDirectionPadUp / etc), which are
        // mostly stable across MFi profiles.
        let buckets: [(title: String, contains: [String])] = [
            ("Face buttons",  ["Button A", "Button B", "Button X", "Button Y"]),
            ("D-pad",         ["Direction Pad"]),
            ("Shoulders",     ["Left Shoulder", "Right Shoulder",
                               "Left Trigger",  "Right Trigger"]),
            ("Left stick",    ["Left Thumbstick"]),
            ("Right stick",   ["Right Thumbstick"]),
            ("System",        ["Button Menu", "Button Options", "Button Home",
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

        // Anything left over.
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
