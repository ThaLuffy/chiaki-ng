// SPDX-License-Identifier: AGPL-3.0-only
//
// Design tokens for ChiakiTV.
//
// Philosophy after redesign-v2: lean on SwiftUI's semantic system whenever
// possible. Brand color tokens stay (they carry meaning the system can't
// infer); raw point sizes go (they break Dynamic Type); hardcoded layout
// dimensions go (they fight content-driven sizing). The `applyTheme()`
// modifier wires `.accentColor` once at the root so every system control
// (Toggle, Picker(.segmented), Slider, .buttonStyle(.card)) inherits the
// brand amber automatically.
//
// See docs/ui/redesign-v2-report.md for rationale and implementation order.

import SwiftUI

enum Theme {

    // MARK: - Brand color tokens
    //
    // These carry meaning the system can't infer:
    // - Amber is the action accent (primary button, focus emphasis).
    // - PS Blue is reserved for PlayStation-context cues only.
    // - Rose is destructive, Green is success — distinct from system
    //   .red / .green which adapt to user vibrancy settings unpredictably.
    // - Ink is the cinema-room base; neutral semantic colors for text
    //   come from `Color.primary` / `.secondary`.

    /// Deep ink — the app background base.
    static let ink900 = Color(red: 0.031, green: 0.063, blue: 0.102)   // #08101A
    /// Elevated panels — host card, list rows. Used as a fill *under*
    /// `.regularMaterial` for elevated surfaces.
    static let ink800 = Color(red: 0.059, green: 0.102, blue: 0.165)   // #0F1A2A
    /// Hover/focus background fill on quiet surfaces.
    static let ink700 = Color(red: 0.106, green: 0.161, blue: 0.251)   // #1B2940
    /// Borders, dividers.
    static let ink600 = Color(red: 0.165, green: 0.227, blue: 0.333)   // #2A3A55

    /// Primary action — `CONNECT` button, focus emphasis.
    static let amber500 = Color(red: 0.961, green: 0.620, blue: 0.043) // #F59E0B
    /// Primary action hover/focus inner highlight.
    static let amber400 = Color(red: 0.984, green: 0.749, blue: 0.141) // #FBBF24
    /// 35% amber bloom — soft outer glow.
    static let amberGlow = Color(red: 0.961, green: 0.620, blue: 0.043).opacity(0.35)

    /// PlayStation-context only — console-ready state, system imagery.
    static let psBlue = Color(red: 0.145, green: 0.388, blue: 0.922)   // #2563EB

    /// Destructive (Hide / Forget confirm, error toasts).
    static let rose500 = Color(red: 0.957, green: 0.247, blue: 0.369)  // #F43F5E
    /// Ready / success state.
    static let green500 = Color(red: 0.063, green: 0.725, blue: 0.506) // #10B981

    // MARK: - Legacy aliases
    //
    // Some pre-redesign components still read these. They'll retire as the
    // remaining migrations land, but in the meantime keeping the aliases
    // means a chrome change here propagates everywhere.

    static let accent           = amber500
    static let background       = ink900
    static let surface          = ink800
    static let streamMenuSurface = Color(red: 0.169, green: 0.169, blue: 0.169)
    static let primaryText      = Color.primary
    static let secondaryText    = Color.secondary
    static let tertiaryText     = Color.secondary.opacity(0.7)
    static let errorRed         = rose500

    /// Semantic stand-in tokens for components that pre-date the dynamic-type
    /// migration. New code should reach for `Color.primary` / `.secondary`
    /// directly.
    static let mist300 = Color.primary           // primary body on dark
    static let mist500 = Color.secondary         // secondary
    static let white50 = Color.white             // emphasised on dark surfaces

    // MARK: - Spacing — pre-redesign components still in use
    //
    // These power the in-stream HUD and a few legacy chrome surfaces. Don't
    // add new tokens of this shape; new code should rely on adaptive
    // spacing or content-driven layout.

    static let toolbarHeight:          CGFloat = 80
    static let dialogTopMargin:        CGFloat = 20
    static let dialogColumnSpacing:    CGFloat = 20
    static let dialogRowSpacing:       CGFloat = 20
    static let dialogFieldWidth:       CGFloat = 400

    static let smallIconSize:          CGFloat = 28
    static let largeIconSize:          CGFloat = 50

    static let toastBottomMargin:      CGFloat = 30
    static let toastInsetH:            CGFloat = 20
    static let toastInsetV:            CGFloat = 10

    // MARK: - Typography — semantic font roles
    //
    // Each role maps to a SwiftUI semantic font style. Semantic fonts scale
    // with Dynamic Type automatically — the user's accessibility text-size
    // setting flows through every label.
    //
    // Why the indirection (`Theme.font(role:)`) when the body could just call
    // `.font(.title2)` directly? Two reasons:
    //
    // 1. The role names map to *intent* (display, sectionTitle, hint), not
    //    to system-font names. We can swap the underlying mapping in one
    //    place without touching call sites.
    // 2. We can layer brand styling (Inter Display, JetBrains Mono) at this
    //    seam in a future commit without changing role values.

    enum FontRole {
        // New semantic roles (use these in new code).
        case display       // Hero — host nickname on the Host Card
        case heading       // Sheet titles, screen titles
        case sectionTitle  // Tab section dividers
        case body          // Default body text
        case bodyEmph      // Emphasised body
        case footnote      // Hints, captions
        case mono          // Tabular numerics (IP, MAC, bitrate readouts)
        case monoCaption   // Caption-side labels (HOST / ID / ADDRESS)

        // Legacy roles (in-flight components; retire as their owners
        // migrate to system primitives in v2 implementation steps).
        case displayXL, displayLarge, displayMed, displaySmall
        case titleLarge, titleMed
        case bodyLarge, bodyMed, bodySmall
        case caption
        case monoLarge, monoMed, monoSmall
    }

    /// Resolves a FontRole to a SwiftUI Font. Semantic styles only — every
    /// returned Font scales with the user's Dynamic Type setting.
    static func font(_ role: FontRole) -> Font {
        switch role {
        // New roles
        case .display:      return .system(.largeTitle, design: .default).bold()
        case .heading:      return .system(.title2,     design: .default).weight(.semibold)
        case .sectionTitle: return .system(.title3,     design: .default).weight(.semibold)
        case .body:         return .system(.body,       design: .default)
        case .bodyEmph:     return .system(.body,       design: .default).weight(.medium)
        case .footnote:     return .system(.footnote,   design: .default)
        case .mono:         return .system(.body,       design: .monospaced)
        case .monoCaption:  return .system(.footnote,   design: .monospaced).weight(.semibold)

        // Legacy mappings — collapse to semantic styles where possible.
        case .displayXL:    return .system(.largeTitle, design: .default).weight(.heavy)
        case .displayLarge: return .system(.largeTitle, design: .default).bold()
        case .displayMed:   return .system(.title,      design: .default).weight(.semibold)
        case .displaySmall: return .system(.title2,     design: .default).weight(.semibold)
        case .titleLarge:   return .system(.title2,     design: .default).weight(.semibold)
        case .titleMed:     return .system(.title3,     design: .default).weight(.medium)
        case .bodyLarge:    return .system(.body,       design: .default)
        case .bodyMed:      return .system(.body,       design: .default)
        case .bodySmall:    return .system(.callout,    design: .default)
        case .caption:      return .system(.footnote,   design: .default).weight(.medium)
        case .monoLarge:    return .system(.title3,     design: .monospaced)
        case .monoMed:      return .system(.body,       design: .monospaced)
        case .monoSmall:    return .system(.footnote,   design: .monospaced).weight(.medium)
        }
    }

    // MARK: - Legacy layout dimensions (delete with their owners)

    static let hostCardWidth:          CGFloat = 1180
    static let hostCardHeight:         CGFloat = 460
    static let hostCardConsoleWidth:   CGFloat = 380
    static let hostCardActionWidth:    CGFloat = 240

    static let settingsRailWidth:      CGFloat = 220
    static let settingsRowHeight:      CGFloat = 64
    static let settingsRailItemHeight: CGFloat = 80

    static let modalMaxWidth:          CGFloat = 880
    static let modalContentPadding:    CGFloat = 40

    static let focusRingWidth:         CGFloat = 3
    static let focusRingBlur:          CGFloat = 24

    static let baseFontSize:           CGFloat = 20
    static let dialogTitleFontSize:    CGFloat = 26
    static let dialogHeaderFontSize:   CGFloat = 14
    static let toolbarOkFontSize:      CGFloat = 25
    static let errorTitleFontSize:     CGFloat = 24
    static let errorTextFontSize:      CGFloat = 20
    static let bigCloseFontSize:       CGFloat = 60
    static let streamMenuCloseFontSize: CGFloat = 50
    static let streamHudBitrateFontSize: CGFloat = 28
    static let streamHudCounterFontSize: CGFloat = 18
    static let streamHudLabelFontSize: CGFloat = 15

    static let hostTileHeight:         CGFloat = 180
    static let hostTileLeftMargin:     CGFloat = 30
    static let hostTileRightMargin:    CGFloat = 10
    static let hostTileVerticalMargin: CGFloat = 10
    static let hostTileSubitemSpacing: CGFloat = 50
    static let consoleIconWidth:       CGFloat = 150

    // MARK: - Animation
    //
    // Semantic animation presets. tvOS focus state changes use the
    // built-in `.smooth` / `.snappy` springs — these constants exist for
    // explicit `withAnimation` calls only.

    static let stackTransitionDuration: Double = 0.20
    static let toastFadeDuration:       Double = 0.50
    static let streamLoadFade:          Double = 0.25
    static let streamMenuSlide:         Double = 0.25
    static let logoPulseDuration:       Double = 1.00

    /// Default focus-state spring. Use `.smooth(duration: 0.28)` for
    /// new code; the alias is retained for in-flight components.
    static let focusSpring: Animation = .smooth(duration: 0.28)

    static let routeTransitionDuration: Double = 0.32

    // MARK: - Radii

    static let smallRadius:  CGFloat = 4
    static let mediumRadius: CGFloat = 8
    static let cardRadius:   CGFloat = 16
    static let modalCorner:  CGFloat = 24
    static let hostCardCorner: CGFloat = 28

    // MARK: - v3 Design Tokens (8pt grid)
    //
    // The redesign-v3 token set. All new code uses these. Names follow the
    // spec convention recommended by `cieden.com/book/sub-atomic/spacing`
    // (`space1..space7`) — semantic-first, never raw pixels at call site.
    //
    // | token   | px | use                                                   |
    // | ------- | -- | ----------------------------------------------------- |
    // | space1  |  4 | inline icon ↔ label gap, half-step                    |
    // | space2  |  8 | base unit — paragraph baseline                        |
    // | space3  | 12 | row internal padding (between label and value)        |
    // | space4  | 16 | card internal gutter, control-row vertical padding    |
    // | space5  | 24 | section-internal vertical rhythm                      |
    // | space6  | 32 | between sections, between major UI groups             |
    // | space7  | 48 | hero zone padding, between unrelated screen regions   |
    // | space8  | 80 | reserved (no current call sites — overscan-safe       |
    // |         |    | inset removed per user preference; modern TVs don't   |
    // |         |    | need it)                                              |

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32
    static let space7: CGFloat = 48
    static let space8: CGFloat = 80
}

// MARK: - View modifiers

extension View {
    /// Apply ChiakiTV's atmospheric background — a deep ink base with soft
    /// off-canvas radial accents. Static; no per-frame cost.
    func chiakiBackground() -> some View {
        self.background(
            ZStack {
                Theme.ink900

                RadialGradient(
                    colors: [Theme.psBlue.opacity(0.22), Color.clear],
                    center: UnitPoint(x: -0.05, y: -0.10),
                    startRadius: 60,
                    endRadius: 1400
                )

                RadialGradient(
                    colors: [Theme.amber500.opacity(0.14), Color.clear],
                    center: UnitPoint(x: 1.10, y: 1.15),
                    startRadius: 80,
                    endRadius: 1500
                )

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

    /// Apply the app's tint at the root. Sets `.accentColor(.amber500)` so
    /// every descendant `Toggle`, `Picker`, `Slider`, and
    /// `.buttonStyle(.card)` inherits the brand color without per-call-site
    /// `.tint(...)`.
    func applyChiakiTheme() -> some View {
        self
            .tint(Theme.amber500)
            .preferredColorScheme(.dark)
    }
}

// MARK: - Custom button styles

/// Primary brand button — amber gradient fill, ink-on-amber type, system-
/// native focus chrome via `.focusable()` semantics. Use for the single
/// primary action on a screen (CONNECT on Host Card; primary toolbar
/// button on a sheet). For everything else, `.buttonStyle(.card)` is the
/// canonical tvOS focus chrome.
struct ChiakiPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.bodyEmph).weight(.bold))
            .foregroundStyle(Theme.ink900)
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Theme.amber400, Theme.amber500],
                        startPoint: .topLeading,
                        endPoint:   .bottomTrailing
                    ))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ChiakiPrimaryButtonStyle {
    /// `.buttonStyle(.chiakiPrimary)` — the brand amber primary CTA.
    static var chiakiPrimary: ChiakiPrimaryButtonStyle { ChiakiPrimaryButtonStyle() }
}

