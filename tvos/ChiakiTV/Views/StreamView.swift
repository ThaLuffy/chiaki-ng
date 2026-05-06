// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Full-bleed canvas hosting the live VideoToolbox + Metal pipeline.
///
/// Mirrors [`gui/src/qml/StreamView.qml`](../../../gui/src/qml/StreamView.qml)
/// but stripped of Qt-specific concerns. Pulls the renderer from
/// `AppState.streamSession` so the Metal layer survives view rebuilds.
///
/// State machine:
///   - `.idle` / `.connecting`: black + loading spinner overlay
///   - `.loginPinRequired`: routes to PIN entry (handled in router)
///   - `.connected`: pure Metal output, optional in-stream menu overlay
///   - `.disconnected` / `.failed`: bounce back to host list
///
/// Siri Remote handling while streaming:
///   - **Tap Menu**: if overlay open → close it. If overlay closed → exit
///     the stream.
///   - **Hold Menu** past `StreamInputCapture.longPressThreshold`: open the
///     `StreamMenuOverlay`. This is the "stream management" handle the
///     user reaches for without leaving the stream.
struct StreamView: View {
    @Environment(AppState.self) private var appState

    @State private var stretch = false
    @State private var volume: Int = 80

    var body: some View {
        @Bindable var appStateBinding = appState
        // `StreamInputCapture` wraps the body in a `GCEventViewController`
        // with `controllerUserInteractionEnabled = false`, so DualSense/Xbox
        // input bypasses the tvOS focus engine entirely and only reaches
        // chiaki via `ControllerService`. Siri Remote presses are mediated
        // here — short Menu tap dismisses, long Menu hold opens the overlay.
        // The same overlay also opens when `ControllerService.onHomeLongPress`
        // flips `appState.streamMenuOpen` (gamepad Guide / PS hold).
        StreamInputCapture(
            onShortTap: handleShortTap,
            onLongPress: { appState.streamMenuOpen = true },
            overlayShown: appState.streamMenuOpen
        ) {
            streamBody(menuBinding: $appStateBinding.streamMenuOpen)
        }
        .ignoresSafeArea()
        .task(id: appState.streamSession.state) {
            if case .disconnected = appState.streamSession.state {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                appState.showHostList()
            }
            // `.failed` keeps the overlay until the user backs out manually.
        }
    }

    @ViewBuilder
    private func streamBody(menuBinding: Binding<Bool>) -> some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            // Live video — always-mounted so the Metal layer stays alive.
            // `formatDescription` propagates through to AVDisplayManager so
            // the Apple TV negotiates an HDR + correct-refresh HDMI link.
            StreamMetalView(
                renderer: appState.streamSession.renderer,
                formatDescription: appState.streamSession.formatDescription,
                refreshRate: Float(appState.settings.fps.rawValue)
            )
            .ignoresSafeArea()

            switch appState.streamSession.state {
            case .idle, .connecting:
                loadingOverlay(message: "Connecting…")
                    .transition(.opacity)
            case .connected:
                if appState.streamMenuOpen {
                    StreamMenuOverlay(
                        isPresented: menuBinding,
                        stretch: $stretch,
                        volume: $volume,
                        connectedTo: hostLabel,
                        onDisconnect: exitStream
                    )
                }
            case .loginPinRequired(let retry):
                pinPrompt(retry: retry)
            case .disconnected, .failed:
                disconnectedOverlay
                    .transition(.opacity)
            }

            // Edge-to-edge top bar telemetry. Lives outside the state switch
            // so it can ride through transient `.connecting` states without
            // flicker; gated to actually-streaming + user opted in via
            // Settings.
            if case .connected = appState.streamSession.state,
               appState.settings.showStreamStats {
                StreamHUDOverlay(
                    connectedTo:   hostLabel,
                    connectedAt:   appState.streamSession.connectedAt,
                    bitrateMbps:   appState.streamSession.measuredBitrateMbps,
                    targetMbps:    Double(appState.settings.bitrateKbps) / 1000.0,
                    packetLossPct: appState.streamSession.packetLossPct,
                    latencyMs:     appState.streamSession.latencyMs,
                    audioBufferMs: appState.streamSession.audioBufferMs,
                    droppedFrames: appState.streamSession.framesLost,
                    fecRepairs:    appState.streamSession.framesRecovered
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25),
                           value: appState.streamSession.state)
            }
        }
    }

    private func handleShortTap() {
        if appState.streamMenuOpen {
            appState.streamMenuOpen = false
        } else {
            exitStream()
        }
    }

    private func exitStream() {
        appState.streamMenuOpen = false
        appState.streamSession.disconnect()
        appState.showHostList()
    }

    private var hostLabel: String {
        if let h = appState.hosts.first(where: { $0.state == .ready }) {
            return h.nickname
        }
        return "PS5"
    }

    private func loadingOverlay(message: String) -> some View {
        VStack(spacing: 30) {
            ChiakiSpinner()
            Text(message)
                .font(.system(size: Theme.baseFontSize))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(40)
    }

    private var disconnectedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 60))
                .foregroundStyle(Theme.errorRed)
            Text(disconnectedMessage)
                .font(.system(size: Theme.baseFontSize))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
            Text("Returning to host list…")
                .font(.system(size: Theme.dialogHeaderFontSize))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(40)
        .frame(maxWidth: 800)
        .background(Theme.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius))
    }

    private var disconnectedMessage: String {
        switch appState.streamSession.state {
        case .failed(let msg): return msg
        case .disconnected:    return "Stream ended"
        default:               return ""
        }
    }

    private func pinPrompt(retry: Bool) -> some View {
        VStack(spacing: 16) {
            Text(retry ? "PIN incorrect — try again." : "Enter the on-screen PIN")
                .font(.system(size: Theme.baseFontSize))
                .foregroundStyle(retry ? Theme.errorRed : Theme.primaryText)
            // For Phase 1 minimum the PIN flow surfaces in the registration
            // path; an in-stream PIN entry view can be added in Phase 2 if
            // the auto-regist path actually requires it on the user's setup.
            Text("Login PIN entry not wired into the in-stream UI yet.")
                .font(.system(size: Theme.dialogHeaderFontSize))
                .foregroundStyle(Theme.tertiaryText)
        }
        .padding(40)
        .background(Theme.surface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius))
    }
}

#Preview {
    StreamView()
        .environment(AppState.preview())
}
