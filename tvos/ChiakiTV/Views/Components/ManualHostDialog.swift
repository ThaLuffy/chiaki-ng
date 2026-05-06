// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// "Add Manual Console" sheet — `.sheet(item:)` over the host list with a
/// `SheetChrome` top bar and a `Form` body. Address row is an inline
/// `TextField` (tvOS 17+ supports this in `Form`).
struct ManualHostDialog: View {
    @Environment(AppState.self) private var appState

    @State private var host: String = ""
    @State private var registeredHostId: String = ""

    private var registeredHosts: [RegisteredHost] { appState.registeredHosts }

    private var canAdd: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetChrome(
                title: "Add Manual Console",
                cancel: ("Cancel", { appState.dismissSheet() }),
                confirm: ("Add", isEnabled: canAdd, {
                    addManualHost()
                    appState.dismissSheet()
                })
            )

            Form {
                Section {
                    TextField("e.g. 192.168.1.42", text: $host)
                } header: {
                    Text("Hostname or IP")
                } footer: {
                    Text("Useful when discovery doesn't find your PS5 — different VLAN, hard-wired, etc.")
                }

                Section {
                    Picker("Linked console", selection: $registeredHostId) {
                        Text("Register on first connection").tag("")
                        ForEach(registeredHosts) { rh in
                            Text(rh.nickname).tag(rh.id)
                        }
                    }
                } footer: {
                    Text("Pair on first connection, or attach this address to a host you've already registered.")
                }
            }
            .formStyle(.grouped)
        }
    }

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
