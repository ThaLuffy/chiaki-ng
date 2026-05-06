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
        .ignoresSafeArea()
    }

    // MARK: - Top toolbar
    //
    // The X "exit app" button is intentionally absent — tvOS apps exit via
    // the system TV button, not via in-app affordances (HIG, see audit
    // issue H7). The wordmark + scan-line live on the left; secondary
    // actions (Add Manual Host, Settings) live on the right.

    private var topToolbar: some View {
        HStack(spacing: Theme.space6) {
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text("ChiakiTV")
                    .font(Theme.font(.titleLarge).weight(.semibold))
                    .foregroundStyle(Theme.white50)
                    .tracking(0.5)

                discoveryStatusLine
            }

            Spacer()

            Button {
                appState.showManualHost()
            } label: {
                Label("Add Manual Host", systemImage: "plus.circle.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                appState.showSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 72, height: 72)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Theme.space8)
        .padding(.top, Theme.space8)
        .frame(height: Theme.toolbarHeight + Theme.space8)
        .focusSection()
    }

    /// Tiny inline indicator next to the wordmark — replaces the bottom-bar
    /// wifi pill's role as "discovery active" telltale.
    private var discoveryStatusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.discoveryEnabled ? Theme.amber500 : Theme.mist500)
                .frame(width: 6, height: 6)

            Text(appState.discoveryEnabled
                 ? "Listening for consoles on this network"
                 : "Discovery paused")
                .font(Theme.font(.bodySmall))
                .foregroundStyle(Theme.mist500)
        }
    }

    // MARK: - Hero zone

    @ViewBuilder
    private var heroZone: some View {
        if appState.hosts.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: Theme.space5) {
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
                .padding(.horizontal, Theme.space7)
                .padding(.top, Theme.space8)
                .padding(.bottom, Theme.space5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Note: previously wrapped in `.focusSection()` to corral focus
            // away from a now-removed bottom-bar wifi pill. Removing that
            // section unblocked Up-from-Connect → toolbar navigation.
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

    // MARK: - Bottom bar
    //
    // The previous bottom bar had a focusable "discovery toggle" wifi pill at
    // the left edge. It pulled launch focus away from the hero CONNECT
    // button (the focus engine prefers vertical x-alignment over proximity).
    // The discovery indicator now lives in the toolbar status line; the
    // toggle is dropped because pausing discovery is a near-zero-frequency
    // action. The version label is preserved as a low-emphasis bottom-right
    // anchor.

    private var bottomBar: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(versionLabel)
                    .font(Theme.font(.bodySmall))
                    .foregroundStyle(Theme.mist500.opacity(0.6))
                    .padding(.trailing, 32)
                    .padding(.bottom, 24)
            }
        }
        .allowsHitTesting(false)  // keep it out of the focus tree entirely
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
