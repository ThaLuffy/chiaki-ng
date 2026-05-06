# ChiakiTV — v2 Redesign Frame Audit (2026-05-06, final)

Captures live alongside this file — 1920×1080 tvOS framebuffer exports from
the Apple TV 4K (3rd gen) simulator on the latest Debug build.
Routes were navigated via the `#if DEBUG` launch-arg path
(`CHIAKITV_INITIAL_ROUTE`, `CHIAKITV_INITIAL_SETTINGS_TAB`).

---

## Verdict per frame

| # | Frame | File | Status | Notes |
|---|-------|------|:---:|---|
| 01 | Home (host visible) | `01-home.png` | ✅ | Connect / labels / halo all clean. Card now uses `PhaseAnimator` between `.dim` and `.bright` phases on a 1.4s period for a subtle breathing rim glow on ready hosts (gated on `accessibilityReduceMotion`). |
| 04 | Settings — Stream | `04-settings-stream.png` | ✅ | `NavigationStack` with native title + Done toolbar action. Rail at 280pt — "Controller" no longer wraps. Form + Section + Picker(.segmented) per spec. |
| 05 | Settings — Network | `05-settings-network.png` | ✅ | Same chrome. Audio + Connection-diagnostics sections. |
| 06 | Settings — Controller | `06-settings-controller.png` | ✅ | Per-cluster section grouping, HOME-button warning chip. |
| 07 | Settings — Consoles | `07-settings-consoles.png` | ✅ | `ContentUnavailableView` empty state. |
| 08 | Settings — App | `08-settings-app.png` | ✅ | Segmented option labels fit ("Sleep", "Both"). |
| 09 | Manual Host sheet | `09-manual-host.png` | ✅ | Real modal: black scrim + `.regularMaterial` rounded panel + `SheetChrome` top bar (Cancel / title / Add). Inline `TextField`. |
| 10 | Console PIN sheet | `10-console-pin.png` | ✅ | Same modal pattern. 4 digit reels, system focus chrome. |
| 11 | Register sheet | `11-register.png` | ✅ | Same modal pattern. Console section (Host / Console / PSN ID) on single lines. 8 PIN reels. |
| 12 | Confirm dialog | `12-confirm.png` | ✅ | Native `.alert(...)` over the host list. |

---

## What landed across all v2 passes

**Foundation (steps F1–F4):**
- `chiakiFocusRing` deprecated then deleted
- `applyChiakiTheme()` sets `.tint(amber500)` at root
- `Theme.font` rebuilt around semantic styles
- Most hardcoded layout dimensions retired

**Component rework (steps C1–C6):**
- `HostCard` uses `.buttonStyle(.borderedProminent)` for Connect, `.buttonStyle(.bordered)` for Wake/Edit/Forget. Identity rows widened + `lineLimit(1)` + `layoutPriority(1)`. Inline `actionStack` uses `.fixedSize` so the identity column expands to fill. **Steady-state ready pulse via `PhaseAnimator`** (step 8) — `.dim` ↔ `.bright` rim shadow on a 1.4s smooth spring, reduce-motion gated.
- `SettingsView` rebuilt around `NavigationStack` (custom `HStack(rail, content)` lives inside it for tvOS, since `List(selection:)` isn't available on tvOS). Done button replaces back chevron. `Form + Section + LabeledContent + Picker(.segmented/.menu)`.
- Three sheets (`ManualHostDialog`, `ConsolePinDialog`, `RegistrationView`) now present via `.fullScreenCover(item:)` over the host list with a black scrim, a `.regularMaterial` rounded panel, and a `SheetChrome` top bar (Cancel / centered title / Confirm). Step 6 of v2 — both visual and presentation layer.
- `ChiakiDigitPicker` rebuilt around `.focusable()` + `Environment(\.isFocused)` — system focus chrome, no `chiakiFocusRing`. (Note: `.pickerStyle(.wheel)` is unavailable on tvOS, so the reel itself stays hand-drawn — but the focus chrome is system-native.)
- `ConfirmDialog` already replaced with native `.alert(...)`.

**Cleanup (step 10):**
Deleted as orphan/unused after the migration:
- `ChiakiToolbar.swift`, `ChiakiButton.swift`, `ChiakiSheet.swift`, `ChiakiDialogChrome.swift`
- `ChiakiSegmented.swift`, `ChiakiSlider.swift` (earlier pass)
- `HostTile.swift`, `ConfirmDialog.swift`, `RemindDialog.swift` (earlier pass)
- `chiakiFocusRing` extension on `View` removed from `Theme.swift`
- `ConfirmDialogModel` / `RemindDialogModel` value types kept in `AppState.swift` (driven by native `.alert`)

**New plumbing:**
- `SheetItem` enum on `AppState` — `.manualHost`, `.registration(Host)`, `.consolePin(hostId:)`. Driven by `appState.sheet: SheetItem?`. The corresponding `AppRoute` cases are now no-ops that fall back to the host list.
- `SheetChrome` view — symmetric Cancel / centered title / Confirm header used by all three sheets. Cancel uses `.tint(.secondary)` so it stays neutral against the amber-tinted root.

---

## Padding / margin verification (computer-use zoomed)

Live-zoomed against the simulator window:

- **Top safe area**: `NavigationStack` and `.fullScreenCover` content respect tvOS overscan-safe insets — Done button and Cancel pills sit ~80pt below the screen edge, well within tvOS HIG's 60pt minimum.
- **Settings rail**: 280pt wide; "Controller" fits on one line; rail items have ~10pt vertical and 14pt horizontal interior padding via `.buttonStyle(.card)`.
- **Form sections**: system-default `Form { Section { ... } }` rhythm (no manual padding hacks). Section headers track at the top, footer text has its own line-spacing baseline.
- **Sheet panels**: 1100×760pt fixed inside an 80pt-margin black scrim. Centered. Panel uses `.regularMaterial` over `.continuous` 28pt corner radius — depth without garishness.
- **Card identity rows**: caption column 130pt, mono value column expands; `.layoutPriority(1)` keeps the caption from compressing under HStack pressure.

---

## Pending / out of scope

- **Visual identity for the PS5 portrait**: the v2 plan called for a hand-drawn silhouette via `Canvas` / `Shape`. Current implementation uses the `playstation.logo` SF Symbol with a state-tinted radial. Functionally fine, visually unique-enough for personal use; can be a follow-up.
- **HostCard `.buttonStyle(.card)` over the whole card**: the v2 plan suggested wrapping the card body in a single `.card` Button with secondary actions in a `.contextMenu`. The current implementation keeps Connect / Wake / Edit / Forget as visible inline buttons because tvOS personal-use users prefer affordance-on-screen over hidden menus.

---

## Capture method note

`osascript`-driven keyboard forwarding into the simulator wouldn't reach the
focus engine reliably, so navigation was driven by a `#if DEBUG`-only launch-arg
path added to `ChiakiTVApp.swift` + `SettingsView.swift`. The code is gated by
`#if DEBUG` so it has zero release-build cost and is useful for future audits —
keep it.
