// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// The main host list, redesigned around the hero `HostCard` per
/// [`docs/ui/redesign-plan.md §5.1`](../../docs/ui/redesign-plan.md).
///
/// Layout:
///
/// - Top toolbar (kept from prior design pending Step 10): `×` quit,
///   `+ Add Manual Host`, `⚙ Settings`. Visually muted in the redesign so it
///   doesn't compete with the hero.
/// - Hero zone: one or more `HostCard`s vertically stacked when populated,
///   centered in the canvas. Empty state falls back to `LogoPulse` plus a
///   helpful caption (the "let's find your PS5" hint from the plan §5.1).
/// - Bottom-left: discovery toggle (round wifi pill, kept).
/// - Bottom-right: version label.
struct HostListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topToolbar
                heroZone
            }

            bottomBar
        }
        .chiakiBackground()
    }

    // MARK: - Top toolbar

    private var topToolbar: some View {
        HStack(spacing: 0) {
            Button {
                appState.showConfirm(
                    title: "Quit ChiakiTV?",
                    message: "Are you sure you want to quit?",
                    onConfirm: { exit(0) }
                )
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: Theme.bigCloseFontSize, weight: .light))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 100, height: Theme.toolbarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            ChiakiButton(title: "Add Manual Host", systemImage: "plus.circle.fill") {
                appState.showManualHost()
            }
            .padding(.horizontal, 6)

            Button {
                appState.showSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: Theme.largeIconSize - 8))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 100, height: Theme.toolbarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: Theme.toolbarHeight)
        .background(Theme.surface.opacity(0.6))
    }

    // MARK: - Hero zone

    @ViewBuilder
    private var heroZone: some View {
        if appState.hosts.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(appState.hosts) { host in
                        HostCard(
                            host: host,
                            onConnect:    { connect(to: host) },
                            onWake:       { wakeUp(host) },
                            onUpdatePin:  { appState.showConsolePin(hostId: host.id) },
                            onForget:     { delete(host) }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Make the hero zone a focus region. Without this, D-pad Down
            // from the toolbar's left-edge buttons (X, gear) jumps directly
            // to the bottom-bar's left-edge wifi pill — the focus engine's
            // spatial-alignment rule prefers vertical X-alignment over
            // proximity. With `focusSection()`, the engine has to enter
            // this zone first, landing on the Connect button.
            .focusSection()
        }
    }

    /// Empty-state guidance — replaces the always-on gamepad silhouette of
    /// the prior design. Surfaces actionable next steps the user can take.
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            LogoPulse()
                .frame(width: 280, height: 280)

            VStack(spacing: 10) {
                Text("Let's find your PS5.")
                    .font(Theme.font(.displayMed))
                    .foregroundStyle(Theme.mist300)

                Text("Make sure your PS5 is on the same Wi-Fi as the Apple TV " +
                     "and Remote Play is enabled in System → Remote Play.")
                    .font(Theme.font(.bodyLarge))
                    .foregroundStyle(Theme.mist500)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 760)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 80)
    }

    // MARK: - Bottom bar (discovery toggle + version)

    private var bottomBar: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                Button {
                    appState.discoveryEnabled.toggle()
                } label: {
                    Image(systemName: appState.discoveryEnabled
                          ? "wifi" : "wifi.slash")
                        .font(.system(size: Theme.largeIconSize - 12))
                        .foregroundStyle(Theme.primaryText)
                        .padding(20)
                        .background(
                            Circle().fill(appState.discoveryEnabled
                                          ? Theme.accent
                                          : Theme.surface)
                        )
                }
                .buttonStyle(.plain)
                .padding(20)

                Spacer()

                Text(versionLabel)
                    .font(.system(size: Theme.dialogHeaderFontSize))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(20)
            }
        }
    }

    private var versionLabel: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "ChiakiTV \(v)"
    }

    // MARK: - Actions (Phase 1 wires to chiaki-lib)

    private func connect(to host: Host) {
        if let registered = appState.registeredHost(for: host) {
            if host.state == .standby {
                // Standby PS5 — wake it up first then route through auto-connect.
                _ = appState.discoveryService.sendWakeup(
                    hostIp: host.ipAddress,
                    registKeyHex: registered.wakeCredentialHex
                )
                appState.showAutoConnect(hostId: registered.id)
            } else {
                appState.connectStream(host: host, registered: registered)
            }
        } else {
            appState.showRegistration(for: host)
        }
    }

    private func delete(_ host: Host) {
        appState.showConfirm(
            title: host.discovered ? "Hide host?" : "Delete host?",
            message: "This will remove \(host.nickname) from the list.",
            onConfirm: {
                appState.hosts.removeAll { $0.id == host.id }
            }
        )
    }

    private func wakeUp(_ host: Host) {
        guard let registered = appState.registeredHost(for: host) else { return }
        _ = appState.discoveryService.sendWakeup(
            hostIp: host.ipAddress,
            registKeyHex: registered.wakeCredentialHex
        )
        appState.showAutoConnect(hostId: registered.id)
    }
}

#Preview {
    HostListView()
        .environment(AppState.preview())
}
