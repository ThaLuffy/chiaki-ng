# ChiakiTV — Redesign Analysis Report

**Author:** post-redesign critical review, 2026-05-06.
**Scope:** every captured frame in [`redesign-final/`](redesign-final/), the
source files that render those frames, and the design tokens in
[`Theme.swift`](../../ChiakiTV/Theme/Theme.swift).
**Method:** for each frame, I read the rendering source, applied four SwiftUI
skills (`swiftui-patterns`, `swiftui-layout-components`, `swiftui-animation`,
`focus-engine`) plus the `frontend-design` aesthetic skill, and recorded what
I found. The analysis is per-frame *and* cross-cutting — many bugs trace to
the same root causes in `Theme.swift`.

---

## Part 1 — Foundation (`Theme.swift`)

### F1.1 — `chiakiFocusRing` is structurally wrong

```swift
extension View {
    func chiakiFocusRing(_ isFocused: Bool, cornerRadius: CGFloat) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isFocused ? Theme.amber500 : Color.clear,
                        lineWidth: Theme.focusRingWidth)        // 3 pt
        )
        .shadow(color: isFocused ? Theme.amberGlow : .clear,
                radius: Theme.focusRingBlur, x: 0, y: 0)         // 24 pt
    }
}
```

**Problem 1 — the stroke lives on `.overlay`, not `.background` or
`.compositingGroup`.** SwiftUI's `.overlay(stroke)` draws the stroke
*centered* on the rounded-rect's border. With `lineWidth: 3` on a button
whose corner radius is 16, the stroke straddles the bounds with 1.5pt
*outside* the layout frame. That outside half is what overlaps neighbour
content.

**Problem 2 — `.shadow(radius: 24)` extends the visual bounds by ~24pt in
every direction.** Combined with the stroke overshoot, a focused button's
*painted* footprint is roughly 26pt larger than its layout frame on each
side. tvOS's native `.buttonStyle(.card)` solves this by drawing the focus
chrome *inside* the focus replicant view, not overlapping siblings.

**Problem 3 — there's no `.scaleEffect` coordination.** Components that use
`chiakiFocusRing` *also* apply `.scaleEffect(1.05)` themselves (HostCard,
ChiakiSheetPrimaryButton, etc.). That double-scaling is what makes focused
buttons "pop" beyond the form's column boundaries — the layout reserves
space for the button at scale 1.0, but the focused button paints at scale
1.05.

**Skill citation — `focus-engine`:**
> "Reaching for `UIFocusGuide` before trying `focusSection()` on macOS or
> tvOS, or better layout grouping in SwiftUI" — and earlier in the same
> doc, *"Use a semantic Button when possible"*. The card focus chrome is
> a tvOS HIG primitive (`.buttonStyle(.card)`), not something to roll
> from scratch with overlay strokes.

**Severity:** **Critical.** This is the single biggest source of visual bugs
in the redesign. It causes the overlap on Frame 09 (Manual Host), the
"CONNECT looks disabled" effect on Frame 03 (Hide focused), the dialog-
overlapping-host-card effect on Frame 12.

### F1.2 — Token system mixes raw hex with custom semantics

The new ink/amber/mist/rose/green tokens are *all* raw `Color(red:green:blue:)`.
They do not adapt to dark/light mode, accessibility contrast settings, or
Increase Contrast. tvOS only ships in dark mode by default, so light/dark
isn't a regression *today* — but the tokens completely sidestep SwiftUI's
semantic color system (`Color.primary`, `.secondary`, `Color.accentColor`,
`Material.thin`, etc.).

**Skill citation — `swiftui-patterns` HIG Alignment:**
> "Use semantic colors (`Color.primary`, `.secondary`,
> `Color(uiColor: .systemBackground)`) for automatic light/dark mode."

The current token system also can't hook the standard accent color
infrastructure. SwiftUI's `Toggle` reads `.accentColor` for its on-state.
We're applying `.tint(Theme.amber500)` in some places but not others —
hence Frame 04's Vertical Sync toggle looks like a stock SwiftUI yellow
blob instead of an integrated component.

**Severity:** Medium-High. Drives the "looks like stock SwiftUI dark mode"
critique.

### F1.3 — Type ramp uses raw `.system(size:)` calls

```swift
case .titleMed: return .system(size: 28, weight: .medium, design: .default)
```

These hard-coded point sizes do not respond to Dynamic Type. tvOS supports
larger system text via Accessibility settings; a user with low vision
gets exactly 28pt regardless. The skill guidance is explicit:

**Skill citation — `swiftui-patterns` HIG Alignment:**
> "Use system font styles (`.title`, `.headline`, `.body`, `.caption`) for
> Dynamic Type support."

The whole reason I added `Theme.font(role:)` was as a "seam where Inter and
JetBrains Mono swap in." That seam is fine *if* the role names map to
HIG semantic roles (`.title2`, `.callout`, etc.) so accessibility scaling
flows through. As written, every ramp entry is a fixed pixel size — a
production sin on Apple platforms.

**Severity:** Medium. Won't be visible in the simulator at default
settings; will regress hard the moment a real user enables Larger Text.

### F1.4 — Layout tokens picked by intuition, not measurement

```swift
static let hostCardWidth:  CGFloat = 1180
static let hostCardHeight: CGFloat = 460
static let hostCardConsoleWidth: CGFloat = 380
static let hostCardActionWidth:  CGFloat = 240
```

1920 - 1180 = 740pt of dead horizontal space distributed evenly as
auto-margins around the card. That's why Frame 01 has so much air.
The 460pt height is similarly arbitrary — there's no content that
fills it; the moon glyph sits at 200pt with 130pt of vertical air
above and below.

The `settingsRailWidth: 220` + content area at remainder leaves the
labels-column starting at ~256pt and the controls right-edge at the
1920pt boundary, with the middle ~600pt empty. That's the empty middle
visible across Frames 04/05/06/07/08.

**Skill citation — `swiftui-layout-components`:**
> "Hard-coding `spacing:` on stacks and grids by default — omit to get
> platform-adaptive spacing; only specify for intentional tight (0–4pt)
> or wide gaps."

The same principle applies to widths: explicit point dimensions are
brittle. The card should have a `maxWidth` (so it can grow when the
viewport is wider) and a content-driven height (so it shrinks when the
content needs less). All four hardcoded `hostCard*` values fight the
layout system instead of cooperating with it.

**Severity:** Medium. Drives the "sparse / void" critique on Frames 01–08.

---

## Part 2 — Per-frame analysis

### Frame 00 — Home, empty state

**Source:** [`HostListView.swift`](../../ChiakiTV/Views/HostListView.swift)
`emptyState` computed view.

**What I see:**
- Wordmark + status line top-left
- 80pt gamepad SF Symbol mid-screen at 25% opacity
- "Let's find your PS5." in `Theme.font(.displayMed)` (56pt)
- Two-line body in `bodyLarge` (24pt), max width 760pt

**Problems:**
1. **The gamepad glyph is decorative chrome at content scale.** It's an
   SF Symbol at 80pt sized as if it were content, but its function is
   purely decorative. At 80pt it competes for visual weight with the
   56pt headline below it, even though it carries zero information.
2. **`LogoPulse` was originally placed here with an `opacity` cycle to
   convey "alive."** The current empty state nests a *separate*
   `LogoPulse` view inside the `emptyState` view at frame 280×280, but
   LogoPulse internally fills its parent with `gamecontroller.fill` —
   the actual rendered glyph is much smaller than 280×280 because the
   Image is `.scaledToFit()` and the parent VStack is centred. The
   spacing math is off.
3. **The hint text is centred but the column is 760pt wide on a 1920pt
   canvas.** That leaves ~580pt of margin on each side. The text feels
   like a footnote, not the actionable "next step" the empty state
   should convey.
4. **No animation in stills means no "discovery active" cue.** A user
   landing on this screen has no way to know whether discovery is
   working. The amber pulse dot in the toolbar is 6pt — invisible at
   3m. There needs to be a *prominent* live indicator here.

**Skill citation — `swiftui-patterns` HIG Alignment:**
> "Use `ContentUnavailableView` for empty and error states."

`ContentUnavailableView` is the iOS 17+ canonical empty-state primitive. It
ships with Dynamic Type support, sane default spacing, an icon-headline-
description hierarchy, and a customisable action button slot. The empty
state I built is a hand-rolled version of `ContentUnavailableView`
without its accessibility benefits.

**Severity:** Medium.

---

### Frame 01 — Home, populated, toolbar focused

**Source:** [`HostListView.swift`](../../ChiakiTV/Views/HostListView.swift),
[`HostCard.swift`](../../ChiakiTV/Views/Components/HostCard.swift).

**What I see:**
- Toolbar: wordmark + status line on left; Add Manual Host pill
  (focused, white halo) + small gear glyph on right
- Hero card centred, ~1180×460pt, with three columns:
  - Console portrait area with moon-Z SF Symbol at ~200pt
  - Identity stack: 72pt nickname + STANDBY chip + ADDRESS/ID/ORIGIN rows
  - Action stack: CONNECT button + Hide secondary

**Problems:**
1. **The "console portrait" is `Image(systemName: "moon.zzz.fill")`.** The
   redesign plan §4.1 committed to a "real PS5 portrait illustration"
   with rim-lighting. The plan acknowledged this was a step-2 asset
   responsibility I was supposed to ship. I never did. The most
   distinctive element of the hero card is a stock SF Symbol any iOS
   bedtime app uses.
2. **The card is sized 1180×460pt — too tall for its content.** Vertical
   air: console portrait 200pt + ~100pt empty in the column, identity
   stack ~280pt of text + ~80pt empty bottom, action stack 88pt button
   + ~40pt secondary + ~250pt empty bottom. The card visually
   "rattles" because the columns are aligned to top and bottom with
   nothing centring the void.
3. **Toolbar's gear is 34pt SF Symbol on an 80×64 hit area.** The gear
   is barely visible against the dark background; no fill, no
   container. Compared to the Add Manual Host pill which has a
   container, the gear feels like it doesn't belong on the toolbar.
   Audit issue H8 explicitly called this out and the redesign didn't
   fix it.
4. **The toolbar is 80pt tall but has no visible top edge.** It's just
   text floating above an invisible boundary. The original design had
   `Theme.surface.opacity(0.6)` background; the redesign removed it
   without replacement. The toolbar now reads as "stuff that happens
   to be at the top" rather than as a navigation chrome.
5. **The wordmark "ChiakiTV" is set in `titleLarge.weight(.semibold)`
   (36pt semibold).** That's the same weight/size as a settings tab
   title — there's no hierarchy distinguishing the *app name* from a
   *tab name*. Branding should be visually heavier.

**Skill citation — `swiftui-layout-components`:**
> "Hard-coding frame dimensions for sheets — use `.presentationSizing`
> instead." Same principle applies to cards: don't hardcode 1180×460;
> use `maxWidth`/`maxHeight` and let content drive height.

**Skill citation — `swiftui-patterns`:**
> "Stable view tree" and "view composition: extract subviews". The
> 220-line HostCard struct has its console portrait, identity stack, and
> action stack all inside one struct. Three separate views with their
> own focus state would be cleaner.

**Severity:** High. This is the steady-state screen 99% of users see.

---

### Frame 02 — Home, CONNECT focused

**Source:** Same as Frame 01.

**What I see:**
- Same as Frame 01 plus the amber halo + bloom around CONNECT
- Card's blue rim brightens slightly

**Problems:**
1. **The amber halo extends past the card's right edge.** The CONNECT
   button is 200×88pt at the right side of the card. With
   `chiakiFocusRing` adding a 24pt blur, the halo paints up to ~24pt
   beyond the card's content. You can see the halo crossing the card's
   own ink-600 border in the screenshot.
2. **The card border / rim color change is too subtle.** Going from
   `psBlue.opacity(0.45)` to `psBlue.opacity(1.0)` at lineWidth 1→2 is
   a small delta visually. At 3m viewing distance the focus state is
   ambiguous; the user might think they need to press another button to
   "really" focus the card.
3. **The amber bloom inside the card portrait doesn't fire on focus.**
   The redesign-plan §4.1 said: *"When the host is `ready`: the card
   has a subtle amber rim-light pulsing at 0.5 Hz (8% opacity
   oscillating to 14%) — barely perceptible, communicates 'alive.'"*
   I implemented a one-shot bloom on `.onAppear`, not a sustained pulse
   on the ready state. The "alive" cue is missing in the steady state.

**Skill citation — `swiftui-animation`:**
> "Use `.animation(_:value:)` for simple value-bound changes."

The bloom uses `.onAppear { bloomActive = true; ...sleep; bloomActive = false }`
which is correct, but the *steady-state* alive pulse should use
`PhaseAnimator` with `.idle/.bright` phases on a 0.5Hz cycle, gated on
`host.state == .ready`. The current implementation has neither.

**Severity:** Medium-High.

---

### Frame 03 — Home, Hide focused

**Source:** Same as Frame 01.

**What I see:**
- Same as Frame 02 except the focus moved to the Hide secondary button
- The CONNECT button has darkened — visually muted to ~70% of its prior
  brightness

**Problems:**
1. **Critical: CONNECT looks disabled.** When focus leaves CONNECT, the
   button removes its `chiakiFocusRing` halo. Combined with the adjacent
   bright Hide-focus halo, the eye contrast-adapts and the *unfocused*
   amber CONNECT now reads as recessive. The user's most-frequent
   action visually demotes to "unavailable" any time focus is on a
   sibling.
2. **The Hide button focus halo pulls focus *out* of the action
   stack visually.** The Hide button is small (~64pt wide) but its 24pt
   shadow + 3pt stroke + 1.06× scale makes its painted footprint about
   90pt — wider than the column it lives in (the action stack column is
   240pt with internal padding, leaving a content area of ~190pt; the
   inflated Hide button at 90×80pt with the bloom takes up nearly half
   that content area).
3. **The Hide icon is a 20pt trash glyph at 64×60pt frame.** That's a
   reasonable target size on tvOS. But the focus state's amber tint on
   the icon plus the amber halo plus the ink-700 fill makes the button
   read as *yellow* when focused — visually identical to the CONNECT
   button. They're now indistinguishable by color.

**Skill citation — `focus-engine`:**
> "Custom controls opt into focus only when they are truly interactive."
> And: "Reach for built-in focusable patterns first."

The right primitive for this row is `.buttonStyle(.card)` which provides
the system's focus chrome: a subtle scale + lift, with the button's
*own background* darkening neighbours via the focused-replicant
overlay. The custom amber halo competes with that built-in
treatment.

**Severity:** Critical (UX) — the disabled-CONNECT effect is the kind of
thing that gets bug reports.

---

### Frame 04 — Settings → Stream

**Source:** [`SettingsView.swift`](../../ChiakiTV/Views/SettingsView.swift)
`VideoStreamTab` + [`ChiakiSegmented.swift`](../../ChiakiTV/Views/Components/ChiakiSegmented.swift)
+ [`ChiakiSlider.swift`](../../ChiakiTV/Views/Components/ChiakiSlider.swift).

**What I see:**
- Vertical rail on left (220pt): Stream selected (amber bar), Network/
  Controller/Consoles/App below in mist-500
- Right pane: 6 rows of label + control
- Resolution: 4-segment (720p / 1080p / 1440p / 2160p (4K)) — second
  selected
- Refresh rate: 2-segment (30 fps / 60 fps) — second selected
- Codec: 2-segment (H.265 (Default) / H.265 HDR) — first selected
- Render preset: 2-segment (Fast (Bilinear) / High Quality (Lanczos))
  — second selected
- Bitrate: amber slider, "15 Mbps" readout right
- Vertical sync: amber Toggle on the right edge

**Problems:**
1. **Rail-to-content gap is 480pt of empty space.** Rail width = 220pt;
   content padding-leading = 24pt + label "Resolution" at maybe 200pt
   = column ends at ~444pt. The control sits at the right edge,
   ~1670pt. The middle ~1200pt is empty. The plan committed to "use
   the canvas" (§4.4) — instead the form just stretches the same
   centred-narrow shape across more pixels.
2. **The Vertical sync Toggle is a vanilla SwiftUI `Toggle`** — applied
   `.tint(amber500)` but the on-state still uses Apple's pill-shape with
   the sliding circle. It looks like a transplant from a generic iOS
   app, not a designed component. Compare with the segmented controls
   above it: those use bespoke `RoundedRectangle.fill(amber500)` cells.
   The Toggle reads as a different design system.
3. **The Bitrate slider has 110pt minimum readout width on the right.**
   "15 Mbps" is 6 chars + space — "100 Mbps" would be 8 chars. The
   readout's `.frame(minWidth: 110, alignment: .trailing)` works but
   makes the slider end at ~1450pt, leaving ~120pt of unused space
   between slider end and readout. Could either extend the slider or
   tighten the readout.
4. **"Render preset" hint says "Higher quality costs ~1–2 ms of decode
   latency."** The hint is in `bodySmall.italic` (18pt italic) at
   mist-500. At 3m on tvOS that's barely legible. tvOS HIG recommends
   minimum 24pt for body text. This entire row of italic hints is
   below the readability floor.
5. **Each segmented control at ~280pt right-aligned has a different
   total width** (Codec is 220pt, Render preset is 320pt). Visual
   alignment along the right edge fails because each control is sized
   to its content. The eye expects either all-equal widths (like
   right-aligned right-edge) or all-fluid (single shared track).
6. **No `Form` / `Section` structure.** The skill says: *"Use `Form` for
   structured input screens (not custom stacks)."* My implementation
   uses a hand-rolled VStack of HStacks. That bypasses Form's built-in
   row spacing, separator handling, focus management, and Dynamic
   Type adaptation.

**Skill citation — `swiftui-layout-components`:**
> "Form used for structured input screens (not custom stacks)."

**Skill citation — `swiftui-layout-components`:**
> ".pickerStyle(.segmented)" — SwiftUI ships a tvOS-native segmented
> picker style. I rolled my own `ChiakiSegmented<T>` instead. The
> system picker has correct focus chrome, accessibility labels, and
> Dynamic Type. Mine has none of those.

**Severity:** High. This is the screen most users will edit settings on.

---

### Frame 05 — Settings → Network

**Source:** Same as Frame 04, plus `AudioTab` (ironically named — the
content moved to Network nominally but the Swift struct is still
`AudioTab`).

**What I see:**
- Same rail; Network selected (white halo, focus chrome)
- 4 rows: Audio buffer (80 ms slider) / Volume (100% slider) / Weak
  Wi-Fi threshold (5% slider) / Reported loss ceiling (3% slider)

**Problems:**
1. **Same problems as Frame 04** — empty middle, rail-to-content gap,
   undersized italic hints, custom controls instead of system ones.
2. **The Volume slider is 100% — but the slider's filled portion goes
   only 70% of the track length**, suggesting the track itself is being
   clipped. Inspecting `ChiakiSlider`: the track uses `GeometryReader`
   inside a 28pt-tall frame with `.padding(.horizontal, 16)` on the
   parent. The slider's geometry is reading the inner width *after*
   padding, so 100% maps to track-end, but the readout right of it
   adds extra space — probably correct behavior but visually surprising.
3. **The Audio buffer slider is at ~24% — value 80, range 20–500.** The
   `(80-20)/(500-20) = 60/480 = 12.5%` math says it should be at 12.5%,
   but it visually sits closer to 20%. Either my range is off or the
   slider rendering math has a bug.

**Severity:** Medium-High.

---

### Frame 06 — Settings → Controller

**Source:** [`SettingsView.swift`](../../ChiakiTV/Views/SettingsView.swift)
`ControllerDiagnosticTab` + private `ControllerSnapshot`.

**What I see:**
- Rail: Controller selected (white halo)
- Card titled "Gamepad" in `displaySmall` (44pt semibold)
- Two status chips: blue "GCEXTENDEDGAMEPAD" + rose "⚠ HOME NOT EXPOSED"
- Six cluster sections with adaptive grid:
  - FACE BUTTONS: A/B/X/Y in 4 columns
  - D-PAD: 4 columns
  - SHOULDERS: 4 columns
  - LEFT STICK: 5 truncated thumbstick labels
  - RIGHT STICK: 5 truncated thumbstick labels
  - SYSTEM: Button Menu

**Problems:**
1. **"Right Thumbstick…" truncates 5 times in a row.** The
   `LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320))])`
   with `Text(b.name).lineLimit(1)` on labels of 22+ chars (e.g.
   "Right Thumbstick Direction Down") doesn't fit. The truncation is
   uniform — every single right-stick label cuts at the same offset
   and shows ellipsis. Visually awful.
2. **Cluster headers are caption-track-loose-mist-500**, but the headers
   "FACE BUTTONS" / "D-PAD" / etc are *information-bearing* — they
   should be at least 18pt, ideally 22pt, not 14pt small caps. At 3m
   they're unreadable.
3. **The button-row dot is 10×10pt.** Combined with the `b.pressed ?
   green : ink600` color logic it's a nearly-invisible indicator. tvOS
   guidance for status indicators is min 16pt dot.
4. **The card body is `padding(28)` on a card that's already padded by
   the rail's content area.** Net: the cluster grid starts at ~290pt
   from the left edge. Lots of margin for no reason.
5. **The two status chips are pill-shaped with ink-600 stroke.** They
   work. But the "HOME NOT EXPOSED" rose chip is *the* most operationally
   important fact on the page (the audit's Co3) and it's visually
   smaller and more recessed than the gamepad title above it. The
   information hierarchy is wrong — the warning should be the focal
   point.
6. **No live press animation** — the "dot lights green when pressed"
   behavior works (the snapshot polls every 80ms via Task) but the
   transition is a hard switch with no spring.

**Skill citation — `swiftui-layout-components`:**
> "Use `LazyVGrid` ... with `.adaptive` columns for layouts that scale
> across device sizes." I'm using adaptive correctly. But the column
> minimum (220pt) is too small for the longest label. Either bump
> `minimum:` or shorten labels (DPad / LStick / RStick instead of
> "Direction Pad" / "Left Thumbstick").

**Severity:** High (visual sloppiness — truncation pattern is the most
visible defect across all frames).

---

### Frame 07 — Settings → Consoles

**Source:** Same `SettingsView.swift` `ConsolesTab`.

**What I see:**
- Rail: Consoles selected
- "Registered Consoles" header, "No consoles registered yet."
- "+ Register New Console" button (focused, white halo)

**Problems:**
1. **The header "Registered Consoles" uses `Theme.dialogTitleFontSize`
   (26pt bold) — pre-redesign typography.** None of the new type ramp
   `Theme.font(.titleLarge)` etc. is used here. The tab body skipped
   the typography migration.
2. **"No consoles registered yet." in `Theme.baseFontSize` (20pt) is
   the empty state for the most important list in the app.** No icon,
   no actionable hint, no link to the host list. Bare and uninviting.
3. **The "Register New Console" `ChiakiButton` (the legacy chrome from
   pre-redesign) has a 1pt border and a 28pt circle plus icon at the
   left.** It looks like a different component from the
   `ChiakiSheetPrimaryButton` used elsewhere (which has amber gradient
   fill).
4. **No way to delete or rename a registered console from this list
   when populated** — the original implementation had a Delete button
   per row, my reskin didn't migrate that.
5. **`ChiakiButton` is the legacy unmigrated component.** It still uses
   `Theme.accent` (which now resolves to amber) but its chrome is the
   old style. Mixing old `ChiakiButton` and new `ChiakiSheetPrimaryButton`
   in the same screen is visually inconsistent.

**Severity:** Medium (the user touches this rarely).

---

### Frame 08 — Settings → App

**Source:** Same `SettingsView.swift` `GeneralTab`.

**What I see:**
- Rail: App selected (white halo)
- 7 rows in pre-redesign `SettingsRow` chrome:
  Action On Disconnect: / Action On Suspend: / Audio + Video: / PSN
  Account-ID (12-char base64): / Streamer Mode: / Verbose Logs: / Show
  Stream Stats:
- Each row has a label-with-trailing-colon on the left and a
  `Picker(.menu)` or `Toggle("")` on the right
- PSN Account-ID has a translucent text field

**Problems:**
1. **The entire tab is unmigrated.** This is the most damaging frame in
   the set. The rail, the card chrome, the rest of the app all read as
   "redesigned" — this tab shouts "leftover."
2. **Trailing colons (`Action On Disconnect:`)** are pre-redesign
   convention. The new `SettingsRow` (used in Frames 04/05) drops them.
   Inconsistent grammar — *"Resolution"* (no colon) vs *"Action On
   Disconnect:"* (colon) right next to each other in the same Settings
   navigator.
3. **`Picker(.menu)` opens a system menu with raw row content.** It
   does not match the segmented control style used elsewhere. Compare
   the Codec segmented in Frame 04 to the Audio + Video Picker(.menu)
   here — same role (cycle a value), two completely different
   interactions.
4. **The PSN Account-ID `TextField` row is rendered with translucent
   background that's unaffected by the `Theme.surface` rename.** It
   looks like a deactivated text field. tvOS-friendly text input —
   per the existing alert pattern — works elsewhere but this row is
   a raw `TextField` that doesn't even raise the keyboard reliably.
5. **Show Stream Stats: On is a Toggle in the legacy unmigrated
   chrome** — black ink-700 pill, `Theme.accent` underlying state.
   Different from the Frame 04 amber Toggle.

**Severity:** Critical for the "is the redesign finished" question.

---

### Frame 09 — Add Manual Console sheet

**Source:** [`ManualHostDialog.swift`](../../ChiakiTV/Views/Components/ManualHostDialog.swift)
+ [`ChiakiSheet.swift`](../../ChiakiTV/Views/Components/ChiakiSheet.swift).

**What I see:**
- Modal sheet centred on the canvas
- Title "Add Manual Console" + 2-line subtitle
- "Address" label
- Big focusable field "Tap to enter address" (focused, white halo
  extending past the row's bounds)
- Hint text "Hostname or IP, e.g. 192.168.x.x" (partially obscured by
  the focus halo's bottom edge)
- "Linked console" label + "Register on first connection" pill
- Hint "Pair on first connection, or attach this address to a host
  you've already registered."
- × Cancel + ⊘ Add (disabled)

**Problems:**
1. **Critical: the focus halo on the Address field overlaps the row's
   own label "Address" above and the hint "Hostname or IP, e.g.
   192.168.x.x" below.** Look at the screenshot: the "Address" label
   is partially eaten by the halo's top extent, and the hint text
   directly below is bisected by the bottom extent. This is the
   `chiakiFocusRing` shadow problem from F1.1 in action.
2. **`fieldRow` in `ManualHostDialog` uses
   `VStack(alignment: .leading, spacing: 6) { label / control / hint }`
   with no extra padding to account for the focus chrome's overshoot.**
   The intention is "label is associated with control which has hint
   below." The execution has zero clearance for focus chrome.
3. **The "Tap to enter address" focused field is a `Button` inside the
   sheet**, but pressing it opens a *system alert with a TextField*.
   That's a two-step interaction — focus → activate → modal alert →
   focus inside alert → type → submit → back to sheet. The redesign-plan
   §5.8 said: *"Pre-populate the IP address field with the most recently-
   discovered local network prefix (192.168.1.) so the user has 4
   keystrokes to type, not 12."* I implemented that pre-fill but the
   keyboard sheet UX is still painful on tvOS.
4. **The "Linked console" Picker uses `.pickerStyle(.menu)`** which on
   tvOS opens a system menu. Inside a sheet this stacks two modal
   layers on top of each other.
5. **The "Add" button shows `.opacity(0.35)` when disabled** — a
   muddy olive-amber color. Not clearly disabled; could be confused
   with "loading" or "low priority."
6. **Cancel and Add together are 380pt wide, right-aligned in the
   action bar — leaves ~520pt of empty space on the left.** The action
   bar should either be centred or have Cancel left-aligned with Add
   right-aligned.

**Skill citation — `swiftui-navigation`:**
> The standard pattern for sheet text input is to put a real `TextField`
> *inside the sheet* with `@FocusState`. Bouncing to a system alert is a
> tvOS workaround for an old SwiftUI tvOS limitation that's been
> addressed in iOS 17+ (the alert TextField pattern came from iOS 14
> compatibility). Modern tvOS handles in-sheet TextField correctly.

**Severity:** Critical.

---

### Frame 11 — Register Console sheet

**Source:** [`RegistrationView.swift`](../../ChiakiTV/Views/RegistrationView.swift)
+ [`ChiakiDigitPicker.swift`](../../ChiakiTV/Views/Components/ChiakiDigitPicker.swift).

**What I see:**
- Sheet titled "Register Console" with subtitle
- Summary: HOST / CONSOLE / PSN ACCOUNT-ID rows in caption-label + mono-value
- "REMOTE PLAY PIN" caption
- 8-column digit picker showing 9/0/1 reels (faded prev/next, bright
  current "0")
- Hint text below the picker
- × Cancel (focused) + ⊙ Register (disabled)

**Problems:**
1. **The digit reels are 110×240pt each — too wide for 8 columns.** Eight
   reels × 110pt + 7 gaps × 12pt = 964pt. Plus picker padding (16pt
   each side) = 996pt. Plus modal content padding (40pt each side) =
   1076pt. The modal is `Theme.modalMaxWidth: 880pt`. The digit reel
   row should overflow horizontally — but doesn't because of layout
   safety. Looking at the screenshot, the reels appear to be at maybe
   80pt each instead of the spec'd 110pt. The `.frame(width: 110)`
   I set on `DigitReel` is being shrunk by SwiftUI's compression
   behavior. The visual result: cramped, smaller-than-designed reels.
2. **The reels render *static* in this frame because focus is on
   Cancel.** Without seeing what a focused reel looks like — its
   `chiakiFocusRing` halo + 1.06× scale — the picker reads as
   decorative chrome, not interactive.
3. **The "9/0/1" cycle in every column is identical** because the
   binding starts at "00000000" so every position reads as 0 with prev=9
   and next=1. Visually this creates a wallpaper-like pattern that
   makes the columns hard to distinguish. A user might think the
   reels are visual noise, not 8 separate inputs.
4. **The hint sub-text "Find this on your PS5: Settings → System →
   Remote Play → Link Device." is in `bodySmall.italic`** — same
   undersized italic as Frame 04. Below readability floor.
5. **The summary header rows use a fixed `frame(width: 180,
   alignment: .leading)` for the label.** Look at the rendered output:
   "PSN ACCOUNT-ID" has 14 characters fitting in 180pt of caption-track-
   loose 14pt small-caps — works. "HOST" at 4 chars uses only 30% of
   that 180pt slot; "CONSOLE" uses 60%. The visual rhythm is
   inconsistent — better to size labels to content with a min-width.
6. **The "Register" disabled button at 35% opacity is the same muddy
   olive-amber as the Manual Host's disabled Add.**

**Skill citation — `swiftui-patterns`:**
> "Sheets own their actions and call `dismiss()` internally."

This sheet calls `appState.showHostList()` — that's because we're not
using SwiftUI's actual `.sheet()` modifier; we're using AppState's
custom routing. The sheet doesn't know it's a sheet. That's why the
sheet doesn't get the `\.dismiss` environment value, can't be swiped
down, and the focus management has the issues you've seen.

**Severity:** High.

---

### Frame 12 — Confirm dialog

**Source:** [`ConfirmDialog.swift`](../../ChiakiTV/Views/Components/ConfirmDialog.swift).

**What I see:**
- Dimming scrim over the host list (host card is still readable
  through it — STANDBY chip and ID rows are visible)
- Centred dialog box with title "Hide host?" + subtitle "This will
  remove PS5-860 from the list."
- Cancel (focused, white halo) + Confirm pair

**Problems:**
1. **The 45% opacity black scrim is too transparent to dim the
   underlying screen.** The host card behind the dialog is still
   readable — the eye competes between dialog content and background
   content. Standard alert scrims are 60–75% opacity black or use
   `.thinMaterial` with `.saturation(0.5)`.
2. **The dialog overlaps the host card's right edge in the frame.**
   The dialog at `maxWidth: 640pt` is centred on the canvas, the
   card is also centred at 1180pt — they overlap by ~270pt of width.
   The dialog visually sits *on top of* the card, with the card
   bleeding through the scrim's gaps. This breaks the modal mental
   model.
3. **Cancel focus halo bleeds past the dialog's right edge** —
   another `chiakiFocusRing` overshoot. The Cancel button is at
   approximately the dialog's center; its 24pt shadow extends to
   about 90pt past the button on each side.
4. **The dialog padding is `padding(36)`** which gives the title
   adequate breathing room, but the action bar at the bottom is
   `padding(.top, 4)` — too tight. The title-message-buttons spacing
   is uneven (20pt-8pt-4pt cascading).
5. **No animation on dialog appear/dismiss.** The dialog snap-shows
   when triggered. tvOS expects a scale-from-0.9 + fade-in transition
   (200–250ms) to convey "I am a modal."

**Skill citation — `swiftui-animation`:**
> "Use `.transition()` on insertion/removal" — and pair it with an
> animation modifier wrapped around the boolean state change. The
> dialog's `if isPresented` should have `.transition(.scale(0.9)
> .combined(with: .opacity))` and the toggle should use
> `withAnimation(.smooth(duration: 0.22)) { ... }`.

**Severity:** High.

---

## Part 3 — Cross-cutting issues

### X1 — Custom focus chrome instead of `.buttonStyle(.card)`

Every `Button` in the app applies `.buttonStyle(.plain)` then layers
custom `chiakiFocusRing`. The `.buttonStyle(.card)` available on tvOS
provides:
- A correctly-clipped focus halo that stays inside the layout frame
- Proper parallax on focus (the button visually lifts, content shifts
  to convey 3D depth)
- Built-in scale + shadow that doesn't bleed past sibling content
- Accessibility chrome (VoiceOver focus treatment)
- Works correctly with `focusSection()` and `.defaultFocus()`

I bypassed all of this in the name of "matching the brand color" with
amber. The skills are clear: rolling custom focus chrome is a path with
many landmines. We've hit several.

### X2 — Hand-rolled segmented control + slider + toggle

`Picker(.segmented)`, `Slider`, and `Toggle` are SwiftUI primitives. They
all have native tvOS focus chrome. I rolled custom replacements for all
three (`ChiakiSegmented`, `ChiakiSlider`, didn't roll `Toggle` but
applied `.tint`) so they'd "match the design system." The native
controls would have:
- Correct focus chrome with no overshoot
- Proper Dynamic Type adaptation
- Correct accessibility labels
- Familiar tvOS interaction patterns

### X3 — Custom `Form` replacement that's worse than `Form`

`SettingsForm` is a `ScrollView { VStack { content } }`. SwiftUI's `Form`
gives:
- Adaptive section spacing
- Built-in row separators
- Focus management between rows
- `Section` headers and footers
- iOS 26+ `scrollEdgeEffectStyle` integration

We have none of these.

### X4 — No accessibility / Dynamic Type plumbing anywhere

No `.accessibilityLabel`, no `.dynamicTypeSize`, no Reduce Motion
gating on animations, no `.accessibilityHint` on focusable buttons.
Every text size is fixed. The redesign assumes the simulator's default
state and breaks at every accessibility boundary.

### X5 — Routing-as-modal instead of `.sheet(item:)`

`AppState` uses a custom `Route` enum and replaces the entire root
view's content based on the current route. That's *navigation*, not
*presentation*. Three of the routes (Manual Host, Console PIN,
Registration) are conceptually modal — they should layer over the host
list, not replace it. The visual workaround (`ChiakiSheet` with a
fake scrim) gets us part of the way but breaks dismissal, focus
restoration, and the swipe-to-dismiss gesture that tvOS users expect.

### X6 — No use of SwiftUI Previews for design iteration

Every component file has a `#Preview` block that I never opened in
Xcode during the redesign. SwiftUI's `#Preview` is *the* design feedback
loop on Apple platforms — it's where you catch focus chrome overshoot,
type-ramp inconsistencies, and adaptive-spacing bugs at design time.
I built blind, screenshotted in the running app, and iterated by ship-
and-fix. That process is the upstream cause of most of the bugs in
this report.

### X7 — Hard-coded everything

- Frame widths (1180, 220, 880, 760)
- Frame heights (460, 80, 88, 64, 240)
- Spacings (24, 18, 12, 6)
- Font sizes (96, 72, 56, 44, 36, 28, 22, 18, 16, 14)
- Animation durations (320, 250, 220, 180, 150, 80)

None come from measurement, HIG, or content. All come from
"this number feels right." The skills are explicit: omit
spacing/sizing where possible, use semantic font sizes for Dynamic
Type, let layout flow from content.

### X8 — `frontend-design` skill misuse

I invoked `frontend-design` for the redesign plan. That skill is web-
oriented (its examples use HTML/CSS, React, Motion library). Its
"distinctive maximalism vs refined minimalism" framing produced an
aspirational *aesthetic* plan but didn't translate to SwiftUI's
geometric reality. The right skill set for this project was
`swiftui-patterns + swiftui-layout-components + swiftui-animation +
focus-engine`. I had access to all of them; I used only one (focus-
engine), passively, as context.

---

## Summary

The redesign has the right *intent* — a hero card, a vertical rail, a
segmented control where it makes sense, a sheet for short forms. It is
better than the audit baseline.

The redesign has the wrong *execution* — every interactive element is
hand-rolled chrome on top of `.buttonStyle(.plain)`, with focus
geometry that bleeds past layout bounds, type ramp that sidesteps
Dynamic Type, and form layout that fights the canvas. The single
biggest root cause is `chiakiFocusRing` (F1.1) — fix that and roughly
half the visible bugs go away.

The single biggest *strategic* error was building blind without
SwiftUI Previews and without invoking the layout / patterns / animation
skills. With the skills loaded, the redesign would have shipped with
`Form`, `Picker(.segmented)`, `Slider`, `.buttonStyle(.card)`, and
`Color.accentColor` from the start — and the visible defects in
Frames 03, 09, 12 would never have happened.

---

**Next deliverable:** the redesign report, which translates the
problems above into concrete component-level fixes, ordered by
dependency and severity. Then implementation.
