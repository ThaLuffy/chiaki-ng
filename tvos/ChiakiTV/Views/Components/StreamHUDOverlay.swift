// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Full-width, edge-to-edge translucent telemetry bar pinned to the absolute
/// top of the viewport. Sits over live video like the system playback HUD on
/// tvOS — the bar is a thin status strip, not a hugging pill.
///
/// Design choices and rationale (research-backed):
///   - **Edge-to-edge, top-flush.** Apple's tvOS HIG and the system playback
///     HUD both use full-bleed bars at the top edge for transient overlay
///     status. A floating pill in the centre fights for attention with game
///     UI (clocks, maps, scoreboards); a thin top strip stays peripheral.
///   - **`.ultraThinMaterial` over a dark dimmer.** The system material gives
///     the live blur effect (so the bar reads on bright AND dark scenes)
///     without baking in a fixed colour. The added `.black.opacity(0.35)`
///     dimmer below it pushes the contrast up so white text stays legible
///     even when the bar overlays a bright frame. PS5 streams use 4:2:0
///     chroma subsampling — luma-weighted designs survive the encode round
///     trip; saturated colours bleed.
///   - **64pt tall.** Matches tvOS tab-bar conventions (HIG: 68pt selected,
///     46pt+padding from top edge). A bar in this band reads as "system
///     chrome", not "in-game UI".
///   - **1pt hairline bottom border.** Definition against high-motion video
///     so the eye finds the bar's edge instantly. Same trick AVPlayerVC's
///     control bar uses.
///   - **Two-region layout.** Left = identity + uptime (the slow-changing
///     "session header"). Right = live metrics (the fast-changing "live
///     vitals"). Mirrors Moonlight, GeForce Now, OpenNOW, and the Apple TV
///     playback HUD itself.
///   - **Monospaced digits + colour thresholds.** Numbers update at 1 Hz;
///     `.monospacedDigit()` prevents horizontal jitter as digit widths
///     change. Green/yellow/red is the same convention every cloud-gaming
///     HUD uses for at-a-glance health.
///
/// Drives off `appState.streamSession`'s @Observable telemetry — no extra
/// timer; the 1 Hz pump in `StreamSession.startStatsPump` is the single
/// source of truth. Uptime ticks every second via a local timer so the
/// readout doesn't freeze on a bridge stall.
struct StreamHUDOverlay: View {

    /// Host nickname rendered in the left identity block.
    let connectedTo: String
    /// Wall-clock at which the bridge transitioned to `.connected`. The bar
    /// derives uptime from `Date().timeIntervalSince(connectedAt)` so the
    /// readout survives stats-pump pauses and view rebuilds.
    let connectedAt: Date?

    /// Live measured throughput. `StreamSession.measuredBitrateMbps`.
    let bitrateMbps: Double
    /// Configured target throughput — only used for the bitrate health
    /// colour decision. A stream measuring well under target is a stronger
    /// signal than any absolute number.
    let targetMbps: Double
    /// Packet loss as a percentage in [0, 100].
    let packetLossPct: Double
    /// Senkusha-measured RTT in ms. Static after the handshake.
    let latencyMs: Int
    /// Audio queue fill in milliseconds.
    let audioBufferMs: Int
    /// Cumulative dropped frames since session start.
    let droppedFrames: Int
    /// Cumulative FEC repairs since session start.
    let fecRepairs: Int

    /// Local 1 Hz tick so the uptime readout keeps moving even if the bridge
    /// stats pump stalls. Cheaper than another `Task` — `TimelineView` would
    /// also work, but `.timer` is one fewer concept to maintain.
    @State private var now: Date = Date()
    private let uptimeTimer = Timer.publish(every: 1.0, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            leftBlock
            Spacer(minLength: 24)
            rightBlock
        }
        .padding(.horizontal, 60)         // tvOS title-safe inset
        .padding(.top, 12)                // breathing room from screen edge
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.35))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
        .ignoresSafeArea(edges: [.top, .horizontal])
        .onReceive(uptimeTimer) { now = $0 }
    }

    // MARK: - Left identity block

    private var leftBlock: some View {
        HStack(spacing: 12) {
            // Pulsing connection dot — live indicator, mirrors AVPlayer's
            // record/live badge convention.
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.green.opacity(0.35), lineWidth: 4)
                        .blur(radius: 2)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(connectedTo.isEmpty ? "Streaming" : connectedTo)
                    .font(.system(size: Theme.streamHudCounterFontSize,
                                  weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(uptimeText)
                    .font(.system(size: Theme.streamHudLabelFontSize,
                                  weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .fixedSize()
    }

    // MARK: - Right metrics block

    private var rightBlock: some View {
        HStack(spacing: 28) {
            cell(label: "BITRATE",
                 value: String(format: "%.1f", bitrateMbps),
                 unit:  "Mbps",
                 color: bitrateColor)
            cell(label: "PKT LOSS",
                 value: String(format: "%.1f", packetLossPct),
                 unit:  "%",
                 color: packetLossColor)
            cell(label: "LATENCY",
                 value: latencyMs > 0 ? "\(latencyMs)" : "—",
                 unit:  latencyMs > 0 ? "ms" : nil,
                 color: latencyColor)
            cell(label: "AUDIO",
                 value: "\(audioBufferMs)",
                 unit:  "ms",
                 color: audioBufferColor)
            cell(label: "DROPPED",
                 value: "\(droppedFrames)",
                 unit:  nil,
                 color: droppedColor)
            cell(label: "FEC",
                 value: "\(fecRepairs)",
                 unit:  nil,
                 color: Theme.primaryText)
        }
        .fixedSize()
    }

    // MARK: - Cell

    @ViewBuilder
    private func cell(label: String, value: String, unit: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: Theme.streamHudLabelFontSize, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .tracking(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: Theme.streamHudCounterFontSize,
                                  weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                if let unit {
                    Text(unit)
                        .font(.system(size: Theme.streamHudLabelFontSize,
                                      weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    // MARK: - Uptime formatting

    /// `H:MM:SS` once we cross an hour, `MM:SS` below that. Sub-minute
    /// sessions still render as `0:NN` so the readout is always two-segment
    /// — keeps the layout from shifting at the one-minute mark.
    private var uptimeText: String {
        guard let connectedAt else { return "0:00" }
        let elapsed = max(0, Int(now.timeIntervalSince(connectedAt)))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Health thresholds

    private var bitrateColor: Color {
        guard targetMbps > 0 else { return Theme.primaryText }
        let ratio = bitrateMbps / targetMbps
        if ratio >= 0.80 { return .green }
        if ratio >= 0.50 { return .yellow }
        return Theme.errorRed
    }

    private var packetLossColor: Color {
        if packetLossPct < 0.5 { return .green }
        if packetLossPct < 2.0 { return .yellow }
        return Theme.errorRed
    }

    private var latencyColor: Color {
        // LAN one-shot RTT ought to be <5 ms on healthy gigabit. 5–20 ms is
        // wifi/general LAN; >20 ms suggests congestion or a bad path.
        if latencyMs == 0          { return Theme.tertiaryText }  // pre-handshake
        if latencyMs < 5           { return .green }
        if latencyMs < 20          { return .yellow }
        return Theme.errorRed
    }

    private var audioBufferColor: Color {
        if audioBufferMs >= 30 && audioBufferMs <= 150 { return .green }
        if audioBufferMs >= 10 && audioBufferMs <= 300 { return .yellow }
        return Theme.errorRed
    }

    private var droppedColor: Color {
        if droppedFrames == 0   { return .green }
        if droppedFrames <= 30  { return .yellow }
        return Theme.errorRed
    }
}

#Preview("Healthy stream") {
    ZStack(alignment: .top) {
        // Stand-in for the live video underneath.
        LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        StreamHUDOverlay(
            connectedTo: "Living Room PS5",
            connectedAt: Date().addingTimeInterval(-185),
            bitrateMbps: 14.7,
            targetMbps: 15.0,
            packetLossPct: 0.3,
            latencyMs: 3,
            audioBufferMs: 64,
            droppedFrames: 0,
            fecRepairs: 12
        )
    }
}

#Preview("Degraded stream") {
    ZStack(alignment: .top) {
        Color.gray.opacity(0.6).ignoresSafeArea()
        StreamHUDOverlay(
            connectedTo: "Living Room PS5",
            connectedAt: Date().addingTimeInterval(-3725),
            bitrateMbps: 6.2,
            targetMbps: 15.0,
            packetLossPct: 4.8,
            latencyMs: 38,
            audioBufferMs: 220,
            droppedFrames: 142,
            fecRepairs: 88
        )
    }
}
