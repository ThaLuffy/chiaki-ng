// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Hero card for one PS5 on the LAN. v3 redesign — see
/// [`docs/ui/redesign-v3/01-host-card.md`](../../../docs/ui/redesign-v3/01-host-card.md)
/// for design rationale + citations.
///
/// **Layout** (single-axis vertical hierarchy, all left-aligned):
///
/// ```
/// ┌──────────────────────────────────────────────────────────┐
/// │  PS5-860                                                 │
/// │  ● READY                                                 │
/// │                                                          │
/// │  Address     192.168.2.26                                │
/// │  MAC         78:C8:81:D7:10:99                           │
/// │  Origin      Discovered                                  │
/// │                                                          │
/// │  ┌──────────────┐   ┌──────┐   ┌──────┐                  │
/// │  │  CONNECT  →  │   │ Wake │   │ Hide │                  │
/// │  └──────────────┘   └──────┘   └──────┘                  │
/// └──────────────────────────────────────────────────────────┘
/// ```
///
/// - Single column, left-aligned. Body content is never centered (see
///   [Pimp My Type — *Avoid centered text*](https://pimpmytype.com/avoid-centered-text/)
///   and [UX Movement — *Why You Should Never Center Align Paragraph
///   Text*](https://uxmovement.com/content/why-you-should-never-center-align-paragraph-text/)).
/// - Hierarchy via type scale + spacing only — no decorative dividers.
///   Title (largeTitle) → state chip (caption mono) → metadata table
///   (body) → primary action.
/// - All padding on the 8pt grid: `space4` (16pt) interior gutter,
///   `space5` (24pt) between groups, `space7` (48pt) outer.
struct HostCard: View {
    let host: Host
    var onConnect:    () -> Void = {}
    var onWake:       () -> Void = {}
    var onUpdatePin:  () -> Void = {}
    var onForget:     () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var focused: Action?
    private enum Action: Hashable { case connect, wake, edit, forget }
    private var cardFocused: Bool { focused != nil }

    private enum PulsePhase: CaseIterable { case dim, bright }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space6) {
            consoleAccent

            VStack(alignment: .leading, spacing: Theme.space6) {
                header
                metadata
                actionRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.space7)
        .frame(maxWidth: 1280, alignment: .leading)
        .background(cardBackground)
        .overlay(rimBorder)
        .modifier(PulseShadow(active: host.state == .ready && !reduceMotion,
                              cardFocused: cardFocused,
                              rimColor: rimColor))
        // No `.focusSection()` — per `swiftui-skills:focus-engine`,
        // sections are only needed when default directional movement
        // *skips* the intended group. Action row buttons are evenly
        // adjacent so default routing reaches them. Wrapping the card
        // in a section was making Right-from-Connect jump up to the
        // toolbar instead of right to Hide, because the section's
        // boundary preferred a sibling section over an internal button.
        .defaultFocus($focused, .connect)
        .animation(.smooth(duration: 0.28), value: cardFocused)
    }

    // MARK: - Console accent — small visual anchor on the left
    //
    // Per Layout Scene's 2026 card guide, a card benefits from a single
    // visual anchor that *complements* the text hierarchy rather than
    // competing with it. The PS logo is small (88×88pt vs the previous
    // 380pt column) and sits inside the same baseline grid as the title.

    private var consoleAccent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(rimColor.opacity(0.16))
                .frame(width: 88, height: 88)
            Image(systemName: host.state == .ready ? "playstation.logo"
                                                   : "moon.zzz.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(host.state == .ready ? Theme.psBlue
                                                      : .secondary)
        }
    }

    // MARK: - Header — title + state chip
    //
    // Title and state form the "scannable in 200ms" zone (Layout Scene,
    // *Mastering Card UI Design Patterns 2026*). Title is the largest
    // type on screen; state chip is right under it, semantic-color coded.

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            Text(host.nickname)
                .font(.system(.largeTitle, design: .default).weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            stateChip
        }
    }

    private var stateChip: some View {
        let (label, color): (String, Color) = {
            switch host.state {
            case .ready:   return ("READY",       Theme.green500)
            case .standby: return ("STANDBY",     Theme.psBlue)
            case .unknown: return ("UNREACHABLE", Theme.rose500)
            }
        }()

        return HStack(spacing: Theme.space2) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.6), radius: 6)
            Text(label)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(color)
                .tracking(1.0)
        }
    }

    // MARK: - Metadata — uniform Address/MAC/Origin table
    //
    // Two-column key/value table. Label column is fixed-width so values
    // align on a single vertical edge — required for visual rhythm in
    // multi-row tables (LearnUI, *3 Pro Tips on Alignment*). Values are
    // monospaced so digits stack cleanly.

    private var metadata: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            metadataRow(label: "Address",
                        value: host.ipAddress.isEmpty ? "—" : host.ipAddress)
            metadataRow(label: "MAC",
                        value: host.mac.isEmpty ? "—" : host.mac)
            metadataRow(label: "Origin",
                        value: discoveryTag)
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space5) {
            Text(label)
                .font(.system(.body, design: .default).weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)

            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Action row — primary CONNECT + secondary actions

    private var actionRow: some View {
        HStack(spacing: Theme.space4) {
            Button(action: onConnect) {
                Label("Connect", systemImage: "play.fill")
                    .font(.system(.body, design: .default).weight(.semibold))
                    .padding(.horizontal, Theme.space2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .focused($focused, equals: .connect)

            if host.registered && host.state == .standby {
                secondaryButton(.wake, title: "Wake",
                                glyph: "moon.stars.fill", action: onWake)
            }
            if host.registered {
                secondaryButton(.edit, title: "Re-pair",
                                glyph: "key.horizontal.fill", action: onUpdatePin)
            }
            secondaryButton(.forget, title: host.discovered ? "Hide" : "Forget",
                            glyph: "trash.fill", action: onForget)
        }
        .padding(.top, Theme.space2)
        // Group the action row's focusables so directional movement
        // stays inside it. Without this, Right from Connect was being
        // routed up-right to the toolbar's focusSection (which the
        // engine treated as a more legitimate destination than a loose
        // sibling Button at the same level).
        // Per `swiftui-skills:focus-engine`: 'Use focusSection() to
        // guide directional movement across groups of focusable
        // descendants in uneven layouts.'
        .focusSection()
    }

    private func secondaryButton(_ key: Action, title: String, glyph: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: glyph)
                .font(.system(.body, design: .default))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.secondary)
        .focused($focused, equals: key)
    }

    // MARK: - Visual chrome

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.hostCardCorner, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: Theme.hostCardCorner,
                                 style: .continuous)
                    .fill(Theme.ink800.opacity(0.65))
            )
    }

    private var rimBorder: some View {
        RoundedRectangle(cornerRadius: Theme.hostCardCorner, style: .continuous)
            .stroke(rimColor.opacity(cardFocused ? 1.0 : 0.35),
                    lineWidth: cardFocused ? 2 : 1)
    }

    private var rimColor: Color {
        switch host.state {
        case .ready:   return Theme.amber500
        case .standby: return Theme.psBlue
        case .unknown: return Theme.rose500
        }
    }

    private var discoveryTag: String {
        if host.manual && host.discovered { return "Manual + Discovered" }
        if host.manual                     { return "Manual" }
        if host.discovered                 { return "Discovered" }
        return "Automatic"
    }
}

/// Pulse-shadow modifier — drives the breathing rim glow on ready hosts.
/// Higher amplitude than v3.1 so the card visibly *breathes* — the user
/// preferred this over the toned-down version. The button focus halos
/// inside the card are system-rendered and don't interact with this
/// shadow (it's drawn outside the card's frame).
private struct PulseShadow: ViewModifier {
    let active: Bool
    let cardFocused: Bool
    let rimColor: Color

    func body(content: Content) -> some View {
        if active {
            PhaseAnimator([HostCard_PulsePhase.dim, .bright]) { phase in
                content
                    .shadow(color: rimColor.opacity(opacity(for: phase)),
                            radius: cardFocused ? 40 : 28, x: 0, y: 0)
            } animation: { _ in .smooth(duration: 1.4) }
        } else {
            content
                .shadow(color: rimColor.opacity(cardFocused ? 0.45 : 0.18),
                        radius: cardFocused ? 40 : 22, x: 0, y: 0)
        }
    }

    private func opacity(for phase: HostCard_PulsePhase) -> Double {
        if cardFocused { return phase == .bright ? 0.55 : 0.40 }
        return phase == .bright ? 0.28 : 0.14
    }
}

private enum HostCard_PulsePhase: CaseIterable { case dim, bright }

#Preview {
    VStack(spacing: 24) {
        HostCard(host: .previewReady)
        HostCard(host: .previewStandby)
        HostCard(host: .previewManual)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(80)
    .background(Color.black)
}
