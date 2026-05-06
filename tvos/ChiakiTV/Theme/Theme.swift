// SPDX-License-Identifier: AGPL-3.0-only
//
// Design tokens for ChiakiTV. The values here are the source of truth for
// color, type, spacing, and motion across the app — Apple's HIG defaults are
// avoided so the app reads as itself, not as a stock SwiftUI sample.
//
// Companion docs:
//   - docs/ui/redesign-plan.md   the why behind every token below.
//   - docs/ui/original-gui-spec.md   the upstream desktop spec we *no longer*
//     mirror 1:1 — kept for historical mapping only.

import SwiftUI

enum Theme {

    // MARK: - Color tokens (ink + amber)
    //
    // Two families. INK is the dark base — every surface, every background.
    // AMBER is the primary action accent — focus halos, primary buttons,
    // confirm-state highlights. PS_BLUE is reserved for PlayStation-context
    // cues only (the console-ready glyph, the system imagery hook). Status
    // colors (rose, green) are for destructive / success states.

    /// Deep ink — the app background base.
    static let ink900 = Color(red: 0.031, green: 0.063, blue: 0.102)   // #08101A
    /// Elevated panels — host card, settings rows.
    static let ink800 = Color(red: 0.059, green: 0.102, blue: 0.165)   // #0F1A2A
    /// Hover/focus background fill.
    static let ink700 = Color(red: 0.106, green: 0.161, blue: 0.251)   // #1B2940
    /// Borders, dividers, deselected segmented-control fill.
    static let ink600 = Color(red: 0.165, green: 0.227, blue: 0.333)   // #2A3A55

    /// Secondary text, scan-line indicators.
    static let mist500 = Color(red: 0.580, green: 0.639, blue: 0.722)  // #94A3B8
    /// Primary body text on dark.
    static let mist300 = Color(red: 0.796, green: 0.835, blue: 0.882)  // #CBD5E1
    /// Emphasised primary text, focus halo highlights.
    static let white50 = Color(red: 0.973, green: 0.980, blue: 0.988)  // #F8FAFC

    /// Primary action — `CONNECT` button fill, focus rings.
    static let amber500 = Color(red: 0.961, green: 0.620, blue: 0.043) // #F59E0B
    /// Primary action hover/focus inner highlight.
    static let amber400 = Color(red: 0.984, green: 0.749, blue: 0.141) // #FBBF24
    /// 35% amber bloom — focus halo shadow.
    static let amberGlow = Color(red: 0.961, green: 0.620, blue: 0.043).opacity(0.35)

    /// PlayStation-context only — console-ready state, system imagery.
    static let psBlue = Color(red: 0.145, green: 0.388, blue: 0.922)   // #2563EB

    /// Destructive action (Hide/Forget confirm, error toasts).
    static let rose500 = Color(red: 0.957, green: 0.247, blue: 0.369)  // #F43F5E
    /// Ready / success state.
    static let green500 = Color(red: 0.063, green: 0.725, blue: 0.506) // #10B981

    // MARK: - Legacy aliases (still in use; will retire as components migrate)
    //
    // Today every component reads `Theme.accent` for its focus ring + primary
    // highlight. Repointing the alias is how Step 1 of the redesign flips the
    // entire app from cool-blue chrome to amber chrome in one commit. The
    // alias stays so we don't have to chase 30+ call sites in the same change.

    /// Primary action / focus accent. Was `#00a7ff` (cool blue, mirrored from
    /// the Qt Material Dark theme). Now amber per docs/ui/redesign-plan.md §3.
    static let accent = amber500

    /// App background base. Was `#303030`. Now ink-900.
    static let background = ink900

    /// Elevated surface (toolbars, dialog bg). Was `#424242`. Now ink-800.
    static let surface = ink800

    /// In-stream menu bar background. Distinct from `surface` only because the
    /// stream HUD already shipped its own visual language; preserve it.
    static let streamMenuSurface = Color(red: 0.169, green: 0.169, blue: 0.169)

    static let primaryText   = mist300
    static let secondaryText = mist300.opacity(0.7)
    static let tertiaryText  = mist300.opacity(0.45)

    /// Packet-loss + dropped-frame counters in the stream HUD.
    static let errorRed = rose500

    // MARK: - Spacing — current implementation
    //
    // Tokens sized for the in-flight HostTile / SettingsView etc. They stay
    // valid until those components migrate to the redesigned Host Card and
    // settings rail. New layout tokens for the redesign live below.

    static let toolbarHeight:          CGFloat = 80
    static let dialogTopMargin:        CGFloat = 20
    static let dialogColumnSpacing:    CGFloat = 20
    static let dialogRowSpacing:       CGFloat = 20
    static let dialogFieldWidth:       CGFloat = 400

    static let hostTileHeight:         CGFloat = 180
    static let hostTileLeftMargin:     CGFloat = 30
    static let hostTileRightMargin:    CGFloat = 10
    static let hostTileVerticalMargin: CGFloat = 10
    static let hostTileSubitemSpacing: CGFloat = 50
    static let consoleIconWidth:       CGFloat = 150

    static let smallIconSize:          CGFloat = 28
    static let largeIconSize:          CGFloat = 50

    static let toastBottomMargin:      CGFloat = 30
    static let toastInsetH:            CGFloat = 20
    static let toastInsetV:            CGFloat = 10

    // MARK: - Spacing — redesign (forthcoming components)

    /// Hero Host Card outer dimensions (single-console steady state).
    static let hostCardWidth:          CGFloat = 1180
    static let hostCardHeight:         CGFloat = 460
    static let hostCardCorner:         CGFloat = 32
    static let hostCardConsoleWidth:   CGFloat = 380
    static let hostCardActionWidth:    CGFloat = 240

    /// Settings vertical rail.
    static let settingsRailWidth:      CGFloat = 220
    static let settingsRowHeight:      CGFloat = 64
    static let settingsRailItemHeight: CGFloat = 80

    /// Modal sheet (replaces the back-chevron-toolbar full-screen forms).
    static let modalMaxWidth:          CGFloat = 880
    static let modalCorner:            CGFloat = 24
    static let modalContentPadding:    CGFloat = 40

    /// Focus ring geometry.
    static let focusRingWidth:         CGFloat = 3
    static let focusRingBlur:          CGFloat = 24

    // MARK: - Typography — current implementation

    static let baseFontSize:                CGFloat = 20
    static let dialogTitleFontSize:         CGFloat = 26
    static let dialogHeaderFontSize:        CGFloat = 14
    static let toolbarOkFontSize:           CGFloat = 25
    static let errorTitleFontSize:          CGFloat = 24
    static let errorTextFontSize:           CGFloat = 20
    static let bigCloseFontSize:            CGFloat = 60     // "×" close button
    static let streamMenuCloseFontSize:     CGFloat = 50
    static let streamHudBitrateFontSize:    CGFloat = 28
    static let streamHudCounterFontSize:    CGFloat = 18
    static let streamHudLabelFontSize:      CGFloat = 15

    // MARK: - Typography — redesign ramp
    //
    // Three roles, distinct sizes per HIG 10-foot legibility. The display
    // role uses tight tracking; body keeps default tracking; mono is reserved
    // for tabular numeric values (IP, MAC, bitrate, latency). At Step 1 we
    // resolve to system fonts; the `Theme.font(...)` API below is the seam
    // where Inter Display + Inter + JetBrains Mono swap in (Step 2) without
    // touching call sites.

    enum FontRole {
        case displayXL    //  96pt — hero hero (e.g. "PS5-860" on the Host Card if we ever go larger)
        case displayLarge //  72pt — host nickname on the Host Card
        case displayMed   //  56pt — screen titles
        case displaySmall //  44pt — section headers in modals
        case titleLarge   //  36pt — settings tab titles
        case titleMed     //  28pt — settings row label, button text
        case bodyLarge    //  24pt — primary read-content
        case bodyMed      //  22pt — settings row values
        case bodySmall    //  18pt — secondary captions
        case caption      //  14pt — meta labels (e.g. "ID:", "Address:")
        case monoLarge    //  28pt — bitrate/latency display readouts
        case monoMed      //  22pt — IP, MAC, version-like values
        case monoSmall    //  16pt — chip text (READY / STANDBY)
    }

    /// Resolves a `FontRole` to a SwiftUI `Font`. System fonts today; will
    /// switch to bundled Inter / JetBrains Mono in the type-asset commit.
    static func font(_ role: FontRole) -> Font {
        switch role {
        case .displayXL:    return .system(size: 96, weight: .bold,    design: .default).leading(.tight)
        case .displayLarge: return .system(size: 72, weight: .bold,    design: .default).leading(.tight)
        case .displayMed:   return .system(size: 56, weight: .semibold, design: .default).leading(.tight)
        case .displaySmall: return .system(size: 44, weight: .semibold, design: .default).leading(.tight)
        case .titleLarge:   return .system(size: 36, weight: .semibold, design: .default)
        case .titleMed:     return .system(size: 28, weight: .medium,  design: .default)
        case .bodyLarge:    return .system(size: 24, weight: .regular, design: .default)
        case .bodyMed:      return .system(size: 22, weight: .regular, design: .default)
        case .bodySmall:    return .system(size: 18, weight: .regular, design: .default)
        case .caption:      return .system(size: 14, weight: .medium,  design: .default).smallCaps()
        case .monoLarge:    return .system(size: 28, weight: .medium,  design: .monospaced)
        case .monoMed:      return .system(size: 22, weight: .regular, design: .monospaced)
        case .monoSmall:    return .system(size: 16, weight: .medium,  design: .monospaced).smallCaps()
        }
    }

    // MARK: - Animation (seconds)

    static let stackTransitionDuration: Double = 0.20
    static let toastFadeDuration:       Double = 0.50
    static let streamLoadFade:          Double = 0.25
    static let streamMenuSlide:         Double = 0.25
    static let logoPulseDuration:       Double = 1.00

    /// Focus enter/exit spring — the canonical motion for any focusable
    /// surface that scales/translates on focus.
    static let focusSpring: Animation = .interpolatingSpring(
        mass: 0.7, stiffness: 280, damping: 18, initialVelocity: 0
    )

    /// Card route transition — the host card scales up to 1.20× while the
    /// destination view crossfades over it. 320ms total.
    static let routeTransitionDuration: Double = 0.32

    // MARK: - Radii

    static let smallRadius:  CGFloat = 4
    static let mediumRadius: CGFloat = 8
    /// New: rounded-rect for elevated cards (settings rows, segment cells).
    static let cardRadius:   CGFloat = 16
}

// MARK: - Background

extension View {
    /// Atmospheric ink-base background with a soft cool/warm radial mesh.
    /// One off-canvas blue anchor (top-left), one off-canvas amber anchor
    /// (bottom-right), creating a quiet diagonal pull from the home screen's
    /// header toward the Host Card's primary action. Static — no per-frame
    /// cost. See docs/ui/redesign-plan.md §3 "Background".
    func chiakiBackground() -> some View {
        self.background(
            ZStack {
                // Base ink fill.
                Theme.ink900

                // Cool blue anchor, top-left, off-canvas. Soft and wide.
                RadialGradient(
                    colors: [Theme.psBlue.opacity(0.18), Color.clear],
                    center: UnitPoint(x: -0.05, y: -0.10),
                    startRadius: 60,
                    endRadius: 1400
                )

                // Warm amber anchor, bottom-right, off-canvas. Even softer.
                RadialGradient(
                    colors: [Theme.amber500.opacity(0.10), Color.clear],
                    center: UnitPoint(x: 1.10, y: 1.15),
                    startRadius: 80,
                    endRadius: 1500
                )

                // Subtle vignette to keep the corners reading as "deep".
                RadialGradient(
                    colors: [Color.clear, Theme.ink900.opacity(0.6)],
                    center: .center,
                    startRadius: 700,
                    endRadius: 1300
                )
            }
            .ignoresSafeArea()
        )
    }
}

// MARK: - Focus ring helper

extension View {
    /// Apply the canonical amber focus ring to any rounded-rect surface.
    /// Caller decides the corner radius and supplies the `isFocused` flag.
    func chiakiFocusRing(_ isFocused: Bool, cornerRadius: CGFloat) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isFocused ? Theme.amber500 : Color.clear,
                        lineWidth: Theme.focusRingWidth)
        )
        .shadow(color: isFocused ? Theme.amberGlow : .clear,
                radius: Theme.focusRingBlur, x: 0, y: 0)
    }
}
