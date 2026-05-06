// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// The main host list. Mirrors [`gui/src/qml/MainView.qml`](../../../gui/src/qml/MainView.qml):
///
/// - 80-px top toolbar with [`×` quit] (left), [`+ Add Manual Host`,
///   `⚙ Settings`] (right). The desktop's PSN/Steam buttons are
///   intentionally omitted (see [`docs/ui/swift-ui-plan.md`](../../docs/ui/swift-ui-plan.md) §1).
/// - Vertical list of `HostTile` rows, 180 px each.
/// - Bottom-left: round discovery toggle (Phase 1 will bind to the bridge).
/// - Bottom-right: version label.
/// - Centered watermark: `LogoPulse`.
struct HostListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            LogoPulse()

            VStack(spacing: 0) {
                topToolbar
                hostList
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

    // MARK: - Host list

    private var hostList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(appState.hosts) { host in
                    HostTile(host: host,
                             onConnect: { connect(to: host) },
                             onDelete: { delete(host) },
                             onWakeUp: { wakeUp(host) },
                             onUpdatePin: { appState.showConsolePin(hostId: host.id) })
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
