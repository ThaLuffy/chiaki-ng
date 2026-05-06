// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Wake-on-LAN waiting room. Reskinned per
/// [`docs/ui/redesign-plan.md`](../../docs/ui/redesign-plan.md):
/// atmospheric ink background, centered modal-style card with the
/// destination host's nickname + IP, and an amber spinner so the
/// "alive" cue matches the rest of the redesign.
///
/// Lifecycle (unchanged from prior implementation):
///   1. `HostListView.connect(to:)` sends the WoL packet then routes here
///      with the target host's MAC.
///   2. We watch `appState.hosts` for that MAC. As soon as DiscoveryService
///      reports the host transitioning out of `.standby` (i.e. `.ready`) and
///      we have a `RegisteredHost` entry, we promote to `connectStream(...)`.
///   3. If the watch times out (`failTimeout`), we bail back to the host
///      list — usually means the WoL packet didn't take or the PS5 isn't
///      on the same LAN.
///   4. The user can cancel at any time after 1.5 s by pressing B / Circle
///      on a gamepad or Menu on the Siri Remote.
struct AutoConnectView: View {
    let hostId: String

    @Environment(AppState.self) private var appState

    @State private var allowClose = false

    private let failTimeout: Duration = .seconds(30)

    private var targetHost: RegisteredHost? {
        appState.registeredHosts.first(where: { $0.id == hostId })
    }

    var body: some View {
        ZStack {
            VStack(spacing: 36) {
                ChiakiSpinner()
                    .frame(width: 110, height: 110)

                VStack(spacing: 8) {
                    Text("Waking PS5")
                        .font(Theme.font(.displaySmall))
                        .foregroundStyle(Theme.white50)

                    if let host = targetHost {
                        Text(host.nickname)
                            .font(Theme.font(.titleMed))
                            .foregroundStyle(Theme.amber500)
                        Text(host.lastIpAddress)
                            .font(Theme.font(.monoMed))
                            .foregroundStyle(Theme.mist500)
                    } else {
                        Text("Waiting for the console to report ready…")
                            .font(Theme.font(.bodyMed))
                            .foregroundStyle(Theme.mist500)
                    }
                }
                .opacity(allowClose ? 1.0 : 0.0)
                .animation(.easeInOut(duration: Theme.streamLoadFade),
                           value: allowClose)

                Text("Press Menu or Circle to cancel")
                    .font(Theme.font(.bodySmall))
                    .foregroundStyle(Theme.mist500)
                    .opacity(allowClose ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: Theme.streamLoadFade)
                                .delay(0.15),
                               value: allowClose)
            }
            .padding(48)
            .frame(maxWidth: 720)
            .background(
                RoundedRectangle(cornerRadius: Theme.modalCorner,
                                 style: .continuous)
                    .fill(Theme.ink800)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.modalCorner,
                                 style: .continuous)
                    .stroke(Theme.amber500.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Theme.amberGlow, radius: 60, x: 0, y: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .chiakiBackground()
        .focusable()
        .task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            allowClose = true
        }
        .task(id: hostId) {
            let deadline = ContinuousClock.now.advanced(by: failTimeout)
            while ContinuousClock.now < deadline {
                if let host = appState.hosts.first(where: { $0.id == hostId }),
                   host.state == .ready,
                   let registered = appState.registeredHost(for: host) {
                    appState.connectStream(host: host, registered: registered)
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
            }
            if !Task.isCancelled {
                appState.showHostList()
            }
        }
        .onExitCommand {
            appState.showHostList()
        }
    }
}

#Preview {
    AutoConnectView(hostId: "AA:BB:CC:DD:EE:FF")
        .environment(AppState.preview())
}
