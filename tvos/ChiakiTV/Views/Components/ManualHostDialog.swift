// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// "Add Manual Console" sheet. Reskin of the prior full-screen form per
/// [`docs/ui/redesign-plan.md §5.8`](../../../docs/ui/redesign-plan.md).
/// Two rows: hostname/IP (focusable button → tvOS keyboard alert) and a
/// console picker (Register on first connection / pick a registered host).
struct ManualHostDialog: View {
    @Environment(AppState.self) private var appState

    @State private var host: String = ""
    @State private var registeredHostId: String = ""

    @State private var hostPromptShown = false
    @State private var hostDraft: String = ""

    private var registeredHosts: [RegisteredHost] { appState.registeredHosts }

    private var canAdd: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ChiakiSheet(
            title: "Add Manual Console",
            subtitle: "Type a hostname or IP address. Useful when discovery " +
                      "doesn't find your PS5 — different VLAN, hard-wired, etc.",
            onBack: { appState.showHostList() },
            content: {
                VStack(alignment: .leading, spacing: 22) {
                    fieldRow(label: "Address",
                             hint: "Hostname or IP, e.g. 192.168.1.42") {
                        hostButton
                    }

                    fieldRow(label: "Linked console",
                             hint: "Pair on first connection, or attach this " +
                                   "address to a host you've already registered.") {
                        consolePicker
                    }
                }
            },
            footer: {
                ChiakiSheetSecondaryButton(title: "Cancel",
                                           systemImage: "xmark") {
                    appState.showHostList()
                }
                ChiakiSheetPrimaryButton(title: "Add",
                                         systemImage: "plus.circle.fill",
                                         isEnabled: canAdd) {
                    addManualHost()
                    appState.showHostList()
                }
            }
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private func fieldRow<Trailing: View>(label: String, hint: String,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.font(.titleMed))
                .foregroundStyle(Theme.mist300)

            trailing()

            Text(hint)
                .font(Theme.font(.bodySmall))
                .foregroundStyle(Theme.mist500)
                .italic()
        }
    }

    /// Focusable button + system-alert TextField pattern. tvOS-friendly
    /// text input where a digit-picker isn't appropriate (free text).
    private var hostButton: some View {
        Button {
            hostDraft = host.isEmpty ? "192.168." : host
            hostPromptShown = true
        } label: {
            HStack {
                Text(host.isEmpty ? "Tap to enter address" : host)
                    .font(Theme.font(.monoMed))
                    .foregroundStyle(host.isEmpty ? Theme.mist500 : Theme.white50)
                Spacer()
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.mist500)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.ink800.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.ink600, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .alert("Address", isPresented: $hostPromptShown) {
            TextField("hostname or IP address", text: $hostDraft)
            Button("OK") {
                host = hostDraft.trimmingCharacters(in: .whitespaces)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var consolePicker: some View {
        Picker("Linked console", selection: $registeredHostId) {
            Text("Register on first connection").tag("")
            ForEach(registeredHosts) { rh in
                Text(rh.nickname).tag(rh.id)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.ink800.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.ink600, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func addManualHost() {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if !registeredHostId.isEmpty,
           let idx = appState.registeredHosts.firstIndex(where: { $0.id == registeredHostId }) {
            appState.registeredHosts[idx].lastIpAddress = trimmed
        }

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
