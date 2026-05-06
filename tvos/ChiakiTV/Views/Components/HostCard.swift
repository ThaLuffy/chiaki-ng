// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Hero card representing a single PS5. Replaces `HostTile` per
/// [`docs/ui/redesign-plan.md §4.1`](../../../docs/ui/redesign-plan.md).
///
/// **Layout** (1180 × 460 pt, three columns, all the same height):
///
/// 1. **Console portrait** (380 pt) — large `playstation.logo` glyph backed
///    by a soft radial that takes the host's rim color (amber/ready,
///    blue/standby, rose/unreachable).
/// 2. **Identity stack** (flex) — 72-pt nickname, state chip, then a
///    label-on-the-left / mono-value-on-the-right metadata table.
/// 3. **Action stack** (240 pt) — full-bleed CONNECT button up top,
///    Wake / Edit / Forget glyph row below.
///
/// **Focus behaviour:** the card itself is a `focusSection()` — the focus
/// engine moves into it as a unit, then routes between the four
/// inline buttons (`connect / wake / edit / forget`). The card's *rim*
/// brightens when any of its descendants is focused.
struct HostCard: View {
    let host: Host
    var onConnect:    () -> Void = {}
    var onWake:       () -> Void = {}
    var onUpdatePin:  () -> Void = {}
    var onForget:     () -> Void = {}

    /// Inline-action focus key. The card's `@FocusState` reads this so the
    /// rim treatment knows *which* descendant is focused (not just whether).
    private enum Action: Hashable { case connect, wake, edit, forget }

    @FocusState private var focused: Action?
    private var cardFocused: Bool { focused != nil }

    var body: some View {
        HStack(spacing: 0) {
            consolePortrait
                .frame(width: Theme.hostCardConsoleWidth)

            identityStack
                .frame(maxWidth: .infinity)

            actionStack
                .frame(width: Theme.hostCardActionWidth)
        }
        .frame(width: Theme.hostCardWidth, height: Theme.hostCardHeight)
        .background(cardBackground)
        .overlay(rimBorder)
        .shadow(color: rimColor.opacity(cardFocused ? 0.45 : 0.18),
                radius: cardFocused ? 40 : 22, x: 0, y: 0)
        .focusSection()
        .animation(Theme.focusSpring, value: cardFocused)
    }

    // MARK: - Console portrait

    private var consolePortrait: some View {
        ZStack {
            // Soft state-tinted glow behind the icon.
            RadialGradient(
                colors: [rimColor.opacity(host.state == .ready ? 0.28 : 0.10),
                         Color.clear],
                center: .center,
                startRadius: 40,
                endRadius: 240
            )

            Image(systemName: host.state == .ready ? "playstation.logo"
                                                   : "moon.zzz.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .foregroundStyle(host.state == .ready ? Theme.psBlue
                                                      : Theme.mist500)
        }
    }

    // MARK: - Identity stack

    private var identityStack: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text(host.nickname)
                    .font(Theme.font(.displayLarge))
                    .foregroundStyle(Theme.white50)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                stateChip
            }

            VStack(alignment: .leading, spacing: 6) {
                identityRow("ADDRESS",
                            host.ipAddress.isEmpty ? "—" : host.ipAddress)
                identityRow("ID",
                            host.mac.isEmpty ? "—" : host.mac)
                identityRow("ORIGIN",
                            discoveryTag.uppercased())
            }
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateChip: some View {
        let (label, color): (String, Color) = {
            switch host.state {
            case .ready:   return ("READY",        Theme.green500)
            case .standby: return ("STANDBY",      Theme.psBlue)
            case .unknown: return ("UNREACHABLE",  Theme.rose500)
            }
        }()

        return HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.6), radius: 6)

            Text(label)
                .font(Theme.font(.monoSmall))
                .foregroundStyle(color)
                .tracking(1.2)
        }
    }

    private func identityRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.mist500)
                .tracking(1.4)
                .frame(width: 84, alignment: .leading)

            Text(value)
                .font(Theme.font(.monoMed))
                .foregroundStyle(Theme.mist300)
                .lineLimit(1)
        }
    }

    // MARK: - Action stack

    private var actionStack: some View {
        VStack(alignment: .center, spacing: 18) {
            primaryConnectButton

            secondaryActionRow
                .opacity(cardFocused ? 1.0 : 0.55)
                .animation(.easeOut(duration: 0.18), value: cardFocused)
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }

    private var primaryConnectButton: some View {
        let isFocused = (focused == .connect)
        return Button(action: onConnect) {
            HStack(spacing: 10) {
                Text("CONNECT")
                    .font(Theme.font(.titleMed).weight(.bold))
                    .tracking(1.2)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
            }
            .foregroundStyle(Theme.ink900)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Theme.amber400, Theme.amber500],
                        startPoint: .topLeading,
                        endPoint:   .bottomTrailing
                    ))
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .focused($focused, equals: .connect)
        .chiakiFocusRing(isFocused, cornerRadius: 20)
    }

    private var secondaryActionRow: some View {
        HStack(spacing: 8) {
            // "Wake" only makes sense for a registered, currently-standby host.
            if host.registered && host.state == .standby {
                inlineGlyph(.wake, glyph: "moon.stars.fill",   title: "Wake",
                            action: onWake)
            }

            // "Edit" (re-register / set new PIN) only for already-paired hosts.
            if host.registered {
                inlineGlyph(.edit, glyph: "key.horizontal.fill", title: "Edit",
                            action: onUpdatePin)
            }

            inlineGlyph(.forget, glyph: "trash.fill",
                        title: host.discovered ? "Hide" : "Forget",
                        action: onForget)
        }
    }

    private func inlineGlyph(_ key: Action, glyph: String, title: String,
                             action: @escaping () -> Void) -> some View {
        let isFocused = (focused == key)
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(Theme.font(.bodySmall))
            }
            .foregroundStyle(isFocused ? Theme.white50 : Theme.mist500)
            .frame(width: 64, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFocused ? Theme.amber500.opacity(0.18)
                                    : Color.clear)
            )
            .scaleEffect(isFocused ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .focused($focused, equals: key)
        .chiakiFocusRing(isFocused, cornerRadius: 12)
    }

    // MARK: - Visual helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.hostCardCorner, style: .continuous)
            .fill(Theme.ink800)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.hostCardCorner,
                                 style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.35))
            )
    }

    private var rimBorder: some View {
        RoundedRectangle(cornerRadius: Theme.hostCardCorner, style: .continuous)
            .stroke(rimColor.opacity(cardFocused ? 1.0 : 0.45),
                    lineWidth: cardFocused ? 2 : 1)
    }

    /// State-driven rim color. The "alive" cue from the plan: warm amber for
    /// `ready`, cool ps-blue for `standby`, rose for `unreachable`.
    private var rimColor: Color {
        switch host.state {
        case .ready:   return Theme.amber500
        case .standby: return Theme.psBlue
        case .unknown: return Theme.rose500
        }
    }

    private var discoveryTag: String {
        if host.manual && host.discovered { return "manual + discovered" }
        if host.manual                     { return "manual" }
        if host.discovered                 { return "discovered" }
        return "automatic"
    }
}

#Preview {
    VStack(spacing: 30) {
        HostCard(host: .previewReady)
        HostCard(host: .previewStandby)
        HostCard(host: .previewManual)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .chiakiBackground()
}
