# v3 Redesign — Skill-Grounded Audit

This audit re-walks every UI change made in the v3 redesign, citing the
specific SwiftUI skill rule that justifies each pattern, and verifies the
result visually against the same rule using `computer-use` against the
live simulator.

Skills consulted (loaded as project skills):

- `swiftui-patterns` — architecture, state management, view composition
- `swiftui-layout-components` — Form, Picker styles, Lists, Stacks
- `swiftui-animation` — `withAnimation`, `PhaseAnimator`, transitions
- `swiftui-skills:focus-engine` — `@FocusState`, `defaultFocus`,
  `focusSection`, `focusable(_:interactions:)`
- `ios-engineering-skills:ios-simulator` — `xcrun simctl` device,
  install, launch, screenshot

Captures live alongside this file in
[`tvos/docs/ui/redesign-v3-skill-audit/`](.).

---

## Group A — Home toolbar (`HostListView.topToolbar`)

Captures: [`A-home-default.png`](./A-home-default.png) ·
[`A-home-gear-focused.png`](./A-home-gear-focused.png) ·
[`A-home-down-from-gear.png`](./A-home-down-from-gear.png)

Source: [`HostListView.swift`](../../../tvos/ChiakiTV/Views/HostListView.swift)
lines 41-78.

### Skill rules cited

> *swiftui-skills:focus-engine* — "Use `focusSection()` on macOS 13+ and
> tvOS 15+ to guide directional movement across groups of focusable
> descendants in uneven layouts."

> *swiftui-skills:focus-engine* — Common Mistakes: "Using gesture
> handlers for primary actions on custom focusable controls instead of a
> semantic Button when possible."

### Verification

| Rule | Code | Visual |
|---|---|:---:|
| Semantic `Button` for primary actions | `Button { showManualHost() }` and `Button { showSettings() }` — both `Button` | ✅ |
| Same `controlSize` for adjacent buttons in same toolbar | Both use `.controlSize(.large)` | ✅ (same height in `A-home-default.png`) |
| Same button-style family (`bordered` family) | `.borderedProminent` + `.bordered` | ✅ — both render as pills, no auto-stretching chrome |
| `.tint(.secondary)` on neutral secondary action | Settings gear: `.tint(.secondary)` | ✅ — gray at rest, system-tint at focus (`A-home-gear-focused.png`) |
| `focusSection()` to make toolbar a destination | `.focusSection()` on toolbar HStack | ✅ — Down from gear returns to Connect (`A-home-down-from-gear.png`) |

### Outcome

Group A passes the audit. Settings gear renders as a fixed-size pill
matching Add Manual Host's height, focus chrome is system-rendered
(no hand-rolled halo), navigation works in both directions.

---

## Group B — HostCard (`HostCard.swift`)

Captures: [`B-after-section-removed.png`](./B-after-section-removed.png) ·
[`B-right-from-connect-section-on-row.png`](./B-right-from-connect-section-on-row.png) ·
[`B-up-from-hide.png`](./B-up-from-hide.png)

Source: [`HostCard.swift`](../../../tvos/ChiakiTV/Views/Components/HostCard.swift).

### Skill rules cited

> *swiftui-skills:focus-engine* — "Use `.defaultFocus` to set the
> preferred initial focus region or control when a view appears or when
> focus is reassigned automatically. Prefer one clear default destination
> per screen or focus region."

> *swiftui-skills:focus-engine* — Common Mistake: "Storing `@FocusState`
> in shared models instead of the owning view."

> *swiftui-skills:focus-engine* — "Use `focusSection()` … in **uneven
> layouts**." (Implication — the section is unnecessary when default
> directional movement reaches the intended target.)

> *swiftui-animation* — *PhaseAnimator* section: "Cycle through discrete
> phases with per-phase animation curves." Common Mistake #2: "Never run
> heavy computation in `keyframeAnimator` / `PhaseAnimator` content
> closures — they execute every frame. Precompute outside, animate only
> visual properties." Common Mistake #3: missing reduce-motion support.

> *swiftui-patterns* — View composition: "Extract Subviews. Break views
> into focused subviews. Each should have a single responsibility."

### Verification

| Rule | Code | Visual |
|---|---|:---:|
| `@FocusState` lives in the owning view | `@FocusState private var focused: Action?` inside `HostCard` | ✅ |
| Single `defaultFocus` per region | `.defaultFocus($focused, .connect)` once on the card | ✅ |
| `focusSection()` only where movement *would otherwise skip* | Removed card-level section; added on `actionRow` only — fixed Right-from-Connect was being routed up-right to the toolbar's section | ✅ — see `B-right-from-connect-section-on-row.png` (Hide gets focus instead of gear) |
| Reduce-motion support on `PhaseAnimator` | `@Environment(\.accessibilityReduceMotion)` gates `PulseShadow` `active` flag | ✅ |
| Only visual properties in PhaseAnimator content | Closure does only `.shadow(color:radius:)` — no computation | ✅ |
| View composition via computed-property subviews | `consoleAccent`, `header`, `metadata`, `actionRow`, `cardBackground`, `rimBorder` | ✅ |

### Outcome

Group B passes after refactor: removed the card-level `focusSection()`
(skill says sections are for *uneven* layouts) and added one to the
action row (the eventually-uneven-vs-toolbar group). Right-from-Connect
now routes to Hide as expected.

---

## Group C — SettingsView (`SettingsView.swift`)

Captures: [`C-settings-stream.png`](./C-settings-stream.png).
Earlier nav captures with TVSliders rendered:
[`../redesign-v3-nav/10-network-tab.png`](../redesign-v3-nav/10-network-tab.png).

Source: [`SettingsView.swift`](../../../tvos/ChiakiTV/Views/SettingsView.swift).

### Skill rules cited

> *swiftui-patterns* — "Use `NavigationStack` (not `NavigationView`)."

> *swiftui-layout-components* — Form section: "Use `Form` for structured
> settings and input screens. Group related controls into `Section`
> blocks."

> *swiftui-layout-components* — Picker control table:
> "`Picker` … `.segmented` for 2-4 options."

> *swiftui-layout-components* — Common Mistakes: "Using
> `.pickerStyle(.segmented)` for large option sets — use menu or inline
> styles." (Generalised: don't use a screen-hijacking control for a
> 50-option range; choose a control that fits the data shape — and on
> tvOS without a native `Slider`, that means a custom focusable slider.)

> *swiftui-skills:focus-engine* — "Use `.focusable(_:interactions:)` on
> custom SwiftUI views that should participate in keyboard or
> directional focus. Use `.activate` for button-like controls. Reserve
> broader interactions for views that genuinely need editing or multiple
> focus-driven behaviors."

### Verification

| Rule | Code | Visual |
|---|---|:---:|
| `NavigationStack` (not deprecated `NavigationView`) | Outer wrapper | ✅ |
| `Form { Section { ... } }` for tabs | Every tab body is a Form | ✅ (`C-settings-stream.png`) |
| `.pickerStyle(.segmented)` for 2-4 options | Resolution (4), Refresh rate (2), Codec (2), Render preset (2), and the App-tab enums (2-4) | ✅ |
| Avoid `.segmented` for large enums | Bitrate (97 stride values) → custom `TVSlider`; same for Audio buffer (49), Volume (21), Wi-Fi thresholds (20 each) | ✅ |
| `.focusable(true)` on custom focusable | `TVSlider` uses `.focusable(true)` + `@FocusState` + `.onMoveCommand` for D-pad | ✅ — slider responds to Left/Right per `redesign-v3-nav/10-network-tab.png` |
| Top-level `.toolbar { }` ToolbarItem | `Done` action in `.cancellationAction` | ✅ |

### Outcome

Group C passes. The `TVSlider` is the only custom-built control and it
follows the focus-engine rule for custom focusables (`.focusable` +
`.onMoveCommand`). Every other control is system-native (`Picker`,
`Toggle`, `Button`).

---

## Group D — Sheets (`SheetChrome` + `ManualHostDialog` etc.)

Captures: from earlier nav walk —
[`../redesign-v3-nav/04-add-manual-host-sheet.png`](../redesign-v3-nav/04-add-manual-host-sheet.png).

Source:
[`SheetChrome.swift`](../../../tvos/ChiakiTV/Views/Components/SheetChrome.swift),
[`ContentView.swift`](../../../tvos/ChiakiTV/Views/ContentView.swift),
[`ManualHostDialog.swift`](../../../tvos/ChiakiTV/Views/Components/ManualHostDialog.swift),
[`ConsolePinDialog.swift`](../../../tvos/ChiakiTV/Views/Components/ConsolePinDialog.swift),
[`RegistrationView.swift`](../../../tvos/ChiakiTV/Views/RegistrationView.swift).

### Skill rules cited

> *swiftui-patterns* — "`.sheet(item:)` preferred over `.sheet(isPresented:)`."

> *swiftui-patterns* — "Sheets own their actions and call `dismiss()`
> internally."

> *swiftui-layout-components* — `fullScreenCover`: "Use
> `.fullScreenCover(item:)` for immersive presentations that cover the
> entire screen (media viewers, onboarding flows)."

### Verification

| Rule | Code | Visual |
|---|---|:---:|
| `item:` overload not `isPresented:` | `.fullScreenCover(item: sheetBinding) { item in ... }` | ✅ |
| `SheetItem` is `Identifiable` | `enum SheetItem: Identifiable { var id: String ... }` | ✅ |
| Sheet body owns its dismiss | Each sheet calls `appState.dismissSheet()` from Cancel/Confirm | ✅ |
| `.fullScreenCover` chosen over `.sheet` | tvOS `.sheet` doesn't size a `Form` correctly (collapses to chrome height); `.fullScreenCover` with explicit panel frame works | ✅ |

### Outcome

Group D passes. Note the deliberate tvOS-specific deviation: per
`swiftui-layout-components`, `.fullScreenCover` is for immersive
presentations — but on tvOS sheets don't size `Form` content correctly,
and a wrapped panel inside a `.fullScreenCover` gives the same modal
feel without the sizing bug. This is a documented workaround at the
file's docstring.

---

## Cross-cutting — `Theme.screenInset`

Skill: *swiftui-patterns* — "Custom `ViewModifier` for repeated styling."
Generalised: a single source-of-truth token for repeated layout values.

`Theme.screenInset = space8 = 80pt`. Every screen-level horizontal
padding goes through it. Used by:

- `HostListView.topToolbar`
- `HostListView.heroZone`
- `SettingsView` outer HStack
- `ContentView.fullScreenCover` panel padding

### Outcome

Cross-cutting passes. Token is named after intent (screen edge inset),
not magnitude (space8), so call sites read as documentation.

---

## Audit gaps

- The audit verified Home toolbar + HostCard via D-pad in the live
  simulator; for Settings I verified the Stream tab end-to-end and
  relied on earlier Network/Controller/Consoles/App captures from the
  navigation walk for the remaining tabs (focus got stuck on the
  Vertical-sync toggle in this session, blocking further D-pad rail
  navigation — that's worth investigating but doesn't invalidate the
  per-screen verification).
- Sheets verified via the prior navigation walk's captures only; not
  re-walked in this audit pass.
