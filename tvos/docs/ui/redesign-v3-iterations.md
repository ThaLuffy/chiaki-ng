# v3 Redesign — Post-Audit Iteration Log

After the [skill-grounded audit](./redesign-v3-skill-audit/AUDIT.md)
landed, an extended iteration phase tightened spacing, fixed focus
routing, replaced a hijacking picker with a custom slider, and rebuilt
the controller diagnostic against an online-researched pattern.

This document is the running record of those iterations. Each section
maps to one or more commits on `tvos-port` with the SwiftUI skill rule
that drove the decision.

## Theme tokens

- **`Theme.screenInset`** introduced as the single source of truth for
  the screen-edge inset (= `space8` = 80pt). Used by HostListView
  toolbar + heroZone, SettingsView outer HStack, and the
  `.fullScreenCover` scrim padding. Skill: *swiftui-patterns* — "extract
  repeated styling so call sites stay declarative."

## Home (`HostListView` + `HostCard`)

- **Toolbar margins** — top inset bumped to 80pt + horizontal to 80pt
  for symmetric spacing. Skill: *swiftui-layout-components* — omit
  `spacing:` for adaptive defaults OR specify intentional values.
- **Settings gear** — landed on `.buttonStyle(.bordered) +
  .controlSize(.large) + .tint(.secondary)` after several wrong turns
  (`.borderless`, `.plain`). Renders as a fixed-size pill matching
  Add Manual Host's height; tint changes on focus, no auto-stretching
  chrome.
- **Card focus routing** — toolbar has `.focusSection()` (toolbar↔card
  navigation), HostCard has its own `.focusSection()` (card is a
  Down-target from the toolbar), `actionRow` HStack has its own
  `.focusSection()` (Connect↔Hide Left/Right). Skill: *focus-engine* —
  "Use `focusSection()` to guide directional movement across groups of
  focusable descendants in uneven layouts."
- **PulseShadow** — restored to high-amplitude breathing glow
  (`.dim` 0.14 / `.bright` 0.55 when focused) per user preference; the
  toned-down version overshot.
- **Hero zone top inset** — bumped to `space8 + space5` (104pt) so the
  card has visible breathing room from the toolbar.
- **`ignoresSafeArea()`** on the outer ZStack so my `screenInset`
  padding is the only inset (no hidden tvOS overscan stack).

## Settings (`SettingsView`)

- **Margin parity with Home** — dropped the manual
  `.padding(.horizontal, screenInset)` because `NavigationStack`
  already applies its own ~80pt safe-area inset on tvOS. Adding
  `screenInset` on top double-inset Settings to ~165pt.
- **Rail-↔-detail HStack spacing** bumped to `space8` (80pt) so the
  visual gap reads as the same design-system unit as the screen-edge
  inset.
- **`SettingsRow<Value>` component** — fixed 280pt label column +
  flexible value column + 80pt `minHeight`. Replaces the inconsistent
  `LabeledContent`/bare `Picker(title:)`/`Toggle(title:)` mix with one
  uniform row geometry. The same `segmentedRow` helper now wraps
  `SettingsRow + Picker(.segmented)` so segmented rows inherit the
  same column geometry. Skill: *LearnUI guide-line principle* —
  "Aligning items along an invisible guide line creates a visual
  relationship between them."
- **`valueInset: CGFloat = 0`** parameter on `SettingsRow` — slider /
  drill-in / button rows pass `valueInset: 2` so their value column
  doesn't kiss the row's rounded background. Segmented rows keep 0
  (they fill edge-to-edge by design).
- **Row corner radius** — explicit `RoundedRectangle(cornerRadius: 14)`
  via `.listRowBackground` so corners are tighter than the system Form
  default ~16pt.

## TVSlider (new component)

`tvOS has no native `Slider`, and the alternative — a `Picker` with 50+
stride values — hijacks the entire screen. Built `TVSlider`: a
focusable horizontal track with D-pad Left/Right step, Up/Down 10×
big-step, accessibility adjustable action.

Replaced drill-in pickers everywhere ranged numeric input was needed:
Bitrate (97 stride values), Audio buffer (49), Volume (21), Weak Wi-Fi
threshold (20), Reported loss ceiling (20).

Skills cited:
- *layout-components* — Common Mistake: "Using `.pickerStyle(.segmented)`
  for large option sets — use menu or inline styles." Generalised: don't
  use a screen-hijacking control for a 50-option range.
- *focus-engine* — "Use `.focusable(_:interactions:)` on custom SwiftUI
  views that should participate in keyboard or directional focus."

## Off/On segmented for binary settings

Vertical sync, Streamer Mode, Verbose Logs, Show Stream Stats — all
switched from `Toggle` to `segmentedRow(...)` with `[false, true]` →
`Off / On`. Reasoning: tvOS `Toggle` inside a custom HStack drops the
switch UI and renders as just text; the user wanted the same visual
geometry as Refresh rate's segmented control.

## Sheets (`SheetChrome` + `ConsolePinDialog` etc.)

- `SheetChrome` row spacings tokenised to `space6` (32pt button gap),
  `space7` (48pt outer horizontal), `space5` (24pt vertical).
- Cancel button `.tint(.secondary)` so it stays neutral grey against
  the amber-tinted root.
- `.fullScreenCover(item:)` over the host list with explicit panel
  frame — tvOS `.sheet` doesn't size `Form` content correctly.

## Controller diagnostic (`ControllerDiagnosticTab`)

Total redesign after the original drill-in list was called out as
broken:

1. **Online research** turned up one dominant pattern across
   GamePadViewer, Steam Input Test, Adobe UX guide, and the Gamepad
   Scan 2025 review: a **silhouette mirroring the physical button
   layout**. Recognition over recall.
2. **Two-mode UI**:
   - **Idle**: Form with controller info (vendor, profile class, Home-
     button exposure status) + 'Start button diagnostic'
     `.borderedProminent` CTA + footer explaining the diagnostic-mode
     behaviour.
   - **Active** (`.fullScreenCover`): spatial diagram with all clusters
     visible above the fold —
     - Top: shoulder + trigger pill bars (L1/L2 left, R1/R2 right)
     - Middle: D-pad cross (left), stick indicators with click-button
       state (centre), face-button diamond Y/X/B/A (right)
     - Bottom: system buttons (Share / Options / Menu / Home /
       Touchpad) as rounded pills — only the ones the controller
       exposes render
3. **Hold-any-button-2s exit** — `.onExitCommand` removed (it was
   making B/Menu/Options exit instantly, blocking diagnosis of those
   exact buttons). Polling loop tracks per-button hold duration. If
   any button is held for ≥ 2.0s, `diagnosticActive = false`.
4. **Linear progress bar** below the footer hint fills as the user
   holds a button toward the threshold. Hint text swaps from "Hold
   any button for 2 seconds…" → "Keep holding to exit…".

Sources: [GamePadViewer](https://gamepadviewer.com/) ·
[Adobe UXpert](https://theblog.adobe.com/game-ui-how-to-prototype-test-designs) ·
[Microsoft GDK touch-control guide](https://learn.microsoft.com/en-us/gaming/gdk/docs/features/common/game-streaming/building-touch-layouts/game-streaming-tak-designers-guide) ·
[Gamepad Scan 2025 review](https://gamepadscan.com/best-free-game-pad-tester-tools/).

## Consoles tab

- Both empty and populated states render inside the same `Form {
  Section { ... } header: Text("Registered consoles") }` chrome (was
  diverging from other Settings tabs).
- Empty state: a single row with bold "No registered consoles" title
  and secondary footnote description, **centered horizontally** with
  `space6` (32pt) vertical + horizontal padding — distinguishes it as
  a callout rather than a clickable row.
- "Register a new console" `.borderedProminent` CTA stays in its own
  Section below.
- Dropped the redundant section footer that repeated the empty-state
  copy.

## Workflow rule the user added

[Memory file](../../.claude/projects/-Users-thaluffy-Development-Personal-chiaki-ng/memory/feedback_swiftui_skill_required.md) —
no UI change happens without first consulting the relevant SwiftUI
skill reference. The hard-won lesson: I had been iterating reactively
on the Settings gear button style (`.borderless` → `.plain` →
`.bordered`) by guessing from screenshots; each iteration produced a
worse result. The fix is to ground every decision in a cited skill
rule before touching code.
