// SPDX-License-Identifier: AGPL-3.0-only
//
// ChiakiTV — tvOS port of chiaki-ng. Personal-use, LAN-only.
// See ../AGENTS.md for the full architecture and ../CLAUDE.md for working rules.

import SwiftUI

@main
struct ChiakiTVApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    ChiakiLogBridge.install()
                    appState.bootstrapDiscovery()
                    #if DEBUG
                    applyDebugLaunchRoute()
                    #endif
                }
        }
    }

    #if DEBUG
    /// Honors the env var `CHIAKITV_INITIAL_ROUTE` (set via
    /// `xcrun simctl launch --setenv CHIAKITV_INITIAL_ROUTE=...`) so the
    /// capture script can deterministically open each frame for screenshots.
    /// Values: settings, manualHost, consolePin, registration, confirm.
    private func applyDebugLaunchRoute() {
        let env = ProcessInfo.processInfo.environment
        guard let route = env["CHIAKITV_INITIAL_ROUTE"], !route.isEmpty else { return }

        let seed: Host = appState.hosts.first ?? Host(
            id: "preview",
            nickname: "PS5-860",
            ipAddress: "192.168.2.26"
        )

        switch route {
        case "settings":
            appState.showSettings()
        case "manualHost":
            appState.showManualHost()
        case "consolePin":
            appState.showConsolePin(hostId: seed.id)
        case "registration":
            appState.showRegistration(for: seed)
        case "confirm":
            appState.showConfirm(
                title: "Hide host?",
                message: "This will remove \(seed.nickname) from the list.",
                onConfirm: {}, onReject: {}
            )
        case "remind":
            appState.showRemind(
                title: "Wake up console?",
                message: "The console is asleep. Send a Wake-on-LAN packet?",
                onYes: {}, onNo: {}, onLater: {}
            )
        default:
            break
        }
    }
    #endif
}
