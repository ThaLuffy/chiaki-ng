// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// "Add Manual Console" push-style dialog. Mirrors
/// [`gui/src/qml/ManualHostDialog.qml`](../../../../gui/src/qml/ManualHostDialog.qml):
///
/// Two-row form: `Host:` text field + `Registered Consoles:` picker. The
/// trailing **Add** button enables only when the host is non-empty AND a
/// console has been picked.
///
/// Phase 0: persists nowhere — `onAdd` simply hands the values back to the
/// caller. Phase 1 wires this to `Chiaki.addManualHost(consoleIndex, host)`.
struct ManualHostDialog: View {
    @Environment(AppState.self) private var appState

    @State private var host: String = ""
    @State private var registeredHostId: String = ""

    /// The host text field is replaced with a focusable Button + system alert
    /// pattern — same fix as RegistrationView's PIN row, since plain
    /// `TextField` on tvOS doesn't reliably register with the focus engine.
    @State private var hostPromptShown = false
    @State private var hostDraft: String = ""

    private var registeredHosts: [RegisteredHost] { appState.registeredHosts }

    /// Allow `Add` either when a registered console is picked AND a host is
    /// entered, or when "Register on first connection" is the selection AND a
    /// host is entered (matches the desktop's behavior).
    private var canAdd: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ChiakiDialogChrome(
            title: "Add Manual Console",
            onBack: { appState.showHostList() }
        ) {
            ChiakiButton(title: "Add", systemImage: "plus.circle.fill") {
                addManualHost()
                appState.showHostList()
            }
            .disabled(!canAdd)
            .opacity(canAdd ? 1.0 : 0.4)
        } content: {
            VStack(alignment: .leading, spacing: Theme.dialogRowSpacing) {

                HStack(spacing: Theme.dialogColumnSpacing) {
                    Text("Host:")
                        .font(.system(size: Theme.baseFontSize))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 220, alignment: .trailing)

                    hostButton
                }

                HStack(spacing: Theme.dialogColumnSpacing) {
                    Text("Registered Console:")
                        .font(.system(size: Theme.baseFontSize))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 220, alignment: .trailing)

                    Picker("Registered Console", selection: $registeredHostId) {
                        Text("Register on first connection").tag("")
                        ForEach(registeredHosts) { rh in
                            Text(rh.nickname).tag(rh.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: Theme.dialogFieldWidth)
                }
            }
        }
    }

    // MARK: - Subviews

    /// Focusable Button + system alert. tvOS-friendly text input.
    private var hostButton: some View {
        Button {
            hostDraft = host
            hostPromptShown = true
        } label: {
            HStack {
                Text(host.isEmpty ? "hostname or IP address" : host)
                    .font(.system(size: Theme.baseFontSize))
                    .foregroundStyle(host.isEmpty
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
        .alert("Host", isPresented: $hostPromptShown) {
            TextField("hostname or IP address", text: $hostDraft)
            Button("OK") {
                host = hostDraft.trimmingCharacters(in: .whitespaces)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Actions

    private func addManualHost() {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // If the user picked a registered console, sync that console's
        // lastIpAddress to the new IP so the connect lookup will find it.
        if !registeredHostId.isEmpty,
           let idx = appState.registeredHosts.firstIndex(where: { $0.id == registeredHostId }) {
            appState.registeredHosts[idx].lastIpAddress = trimmed
        }

        // Stable id for manual entries — use the IP itself.
        let manualHost = Host(
            id: trimmed,
            nickname: registeredHostId.isEmpty ? "Manual host (\(trimmed))" :
                appState.registeredHosts.first(where: { $0.id == registeredHostId })?.nickname ?? trimmed,
            ipAddress: trimmed,
            mac: appState.registeredHosts.first(where: { $0.id == registeredHostId })?.mac ?? "",
            ps5: true,
            registered: !registeredHostId.isEmpty,
            manual: true,
            discovered: false,
            state: .unknown
        )

        // Replace any pre-existing manual host with the same IP.
        if let idx = appState.hosts.firstIndex(where: { $0.id == manualHost.id }) {
            appState.hosts[idx] = manualHost
        } else {
            appState.hosts.append(manualHost)
        }
    }
}

#Preview {
    ManualHostDialog()
        .environment(AppState.preview())
}
