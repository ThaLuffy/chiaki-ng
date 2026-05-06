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
                    // Funnel chiaki-lib log lines through OSLog. Idempotent
                    // — safe to call from `.onAppear` even if the WindowGroup
                    // re-emits this scene.
                    ChiakiLogBridge.install()
                    appState.bootstrapDiscovery()
                }
        }
    }
}
