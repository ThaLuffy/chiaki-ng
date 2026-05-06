// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Wake-on-LAN waiting room. Mirrors
/// [`gui/src/qml/AutoConnectView.qml`](../../../gui/src/qml/AutoConnectView.qml):
///
/// - Full-bleed black background.
/// - Centered "Waiting for console..." label, opacity 0 → 1 over 250 ms once
///   the `allowClose` flag flips at t = 1500 ms.
/// - 70 × 70 spinner pinned slightly below center.
/// - Helper label below the spinner: "Press <Circle/B> to cancel connection".
///
/// Lifecycle:
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

    /// Hard ceiling on how long we sit on this screen before giving up.
    /// PS5 wake-from-standby is typically 5–15 s; 30 s gives generous headroom
    /// without leaving the user staring at a frozen spinner forever.
    private let failTimeout: Duration = .seconds(30)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                Text("Waiting for console…")
                    .font(.system(size: Theme.dialogTitleFontSize, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .opacity(allowClose ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: Theme.streamLoadFade),
                               value: allowClose)

                ChiakiSpinner()

                Text("Press B / Circle to cancel")
                    .font(.system(size: Theme.dialogHeaderFontSize))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.top, 10)
            }
        }
        // `.focusable()` gives the focus engine a target inside this view.
        // Without it, B/Circle/Menu presses escape the responder chain and
        // tvOS interprets them as "exit the app." With it, the press lands
        // here and `.onExitCommand` fires reliably.
        .focusable()
        .task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            allowClose = true
        }
        .task(id: hostId) {
            // Observe discovery state for our target host. As soon as it
            // shows up as `.ready` and we still have a registered record
            // for it, promote to streaming.
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
            // Timed out — fall back to host list so the user isn't stuck.
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
