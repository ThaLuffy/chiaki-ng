# ChiakiTV — Redesign v2 (Implementation Plan)

**Author:** companion to [`analysis-report.md`](analysis-report.md), 2026-05-06.
**Goal:** translate the analysis's problems into concrete component-level
changes the implementation can execute against, ordered by dependency.

This plan inverts the v1 mistake: instead of rolling custom chrome and
tokens, we *use SwiftUI's primitives* and theme them where the system
allows it. The result will look less generic-AI and more grounded —
because the system controls have correct focus chrome, accessibility,
and Dynamic Type built in, leaving us free to spend our design budget
on the *content* rather than fighting the framework.

---

## Part 1 — Foundation overhaul

### F1 — Replace `chiakiFocusRing` with `.buttonStyle(.card)`

**Delete** the `chiakiFocusRing` extension entirely.
**Use** `.buttonStyle(.card)` on tvOS as the canonical focus chrome.
**Where the brand needs amber emphasis** (the primary CONNECT button,
the primary sheet action), wrap with a custom `ButtonStyle` that
*composes with* `.card` rather than replacing it — using
`configuration.isPressed` and `@FocusState` to add an amber tint inside
the system-provided focus replicant.

```swift
// Replaces chiakiFocusRing usage everywhere except the primary
// brand-amber buttons (CONNECT, sheet primary action).
.buttonStyle(.card)

// For primary brand-amber buttons:
struct ChiakiPrimaryCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(amberGradient)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
    }
}
```

`.buttonStyle(.card)` gives us, for free:
- Focus halo with correct geometry (stays inside layout bounds).
- Parallax on focus.
- Press scale.
- VoiceOver label propagation.

This single swap fixes Frames 03, 09, 12 visual bugs and reduces the
custom code surface dramatically.

### F2 — Use semantic colors and accent color

Add `Theme.applyTheme()` view modifier that sets `.accentColor(.amber500)`
on the root. SwiftUI's `Toggle`, `Picker(.segmented)`, `Slider`, and
`.buttonStyle(.card)` all read `\.accentColor` — applying it once at the
root makes every system control match without per-call-site `.tint(...)`.

Replace raw color usages where SwiftUI has a semantic equivalent:
- `Theme.mist300` for primary text → `Color.primary`
- `Theme.mist500` for secondary text → `Color.secondary`
- `Theme.ink800` for elevated panels → `.regularMaterial` over the chiakiBackground
- `Theme.ink900` for app background → kept (chiakiBackground does the work)

The amber/rose/green/psBlue brand tokens *stay* — those carry meaning
that the system can't infer.

### F3 — Replace fixed pt sizes with HIG semantic font roles

Rebuild `Theme.FontRole` to map onto Apple's text styles, not raw points:

```swift
enum FontRole {
    case display      // .system(.largeTitle, design: .default).bold() — host nickname
    case heading      // .title2 — sheet titles, screen titles
    case sectionTitle // .title3 — sheet section dividers
    case body         // .body — settings row labels (default 17pt, scales with Dynamic Type)
    case bodyEmph     // .body.weight(.medium)
    case footnote     // .footnote — hint sub-text, captions
    case mono         // .body.monospaced() — IP, MAC values
    case monoCaption  // .footnote.monospaced() — label-side caps
}
```

Now `Theme.font(.body)` returns `.body` which is a *semantic font* that
scales with Dynamic Type. The italic hints currently set in
`bodySmall.italic` (18pt italic) become `.footnote.italic()` which
respects the user's accessibility text size.

We keep the `Theme.font(role:)` *seam* so we can still bundle Inter
later — but the seam returns semantic fonts today, not raw points.

### F4 — Remove hard-coded card / form dimensions

Delete:
- `Theme.hostCardWidth`, `hostCardHeight`, `hostCardConsoleWidth`,
  `hostCardActionWidth`
- `Theme.modalMaxWidth` (replaced by `.presentationSizing` or just
  `.frame(maxWidth: 720)` for the sheet content)
- `Theme.settingsRailWidth`, `settingsRowHeight`, `settingsRailItemHeight`

Replace with content-driven layout:
- HostCard uses `.frame(maxWidth: 1280)` and content-driven height
  (the columns size to their content).
- Sheets use `.frame(maxWidth: 720)` with vertical padding driven by
  `Section` content.
- Settings rail uses `.fixedSize(horizontal: true, vertical: false)`
  on each rail row's HStack so the rail self-sizes to its widest label.

---

## Part 2 — Component rework

### C1 — `HostCard` (Frame 01–03)

**Replace the moon SF Symbol with a custom-drawn PS5 silhouette.** Use
SwiftUI `Canvas` or layered `Shape` primitives — the PS5's recognisable
form is two slightly-curved white panels with a black middle. A 30-line
`Shape` rendering captures the silhouette without needing a vendor asset.
Apply state-tinted glow behind it.

**Wrap the whole card as a `.buttonStyle(.card)` Button** so the focus
treatment is system-native. Inside the card, the secondary action row
(Wake / Edit / Forget) becomes a *focusable child* via the focus engine's
nested `Button`s — but each is also `.buttonStyle(.card)` so it gets
correct focus chrome.

**Card layout:**
- Use `.frame(maxWidth: 1280)` (responsive on 4K canvases).
- Three columns sized by content (`.fixedSize(horizontal: true,
  vertical: false)` on the action stack so it doesn't sprawl).
- Console portrait column ~360pt wide, identity stack flexing,
  action stack at content width.
- Card height grows from the tallest column's intrinsic height.

**Steady-state alive cue:** add a `PhaseAnimator` cycling between
`.dim` and `.bright` phases on a 1.4s period when `host.state == .ready`.
Gate on `accessibilityReduceMotion`. This is the redesign-plan's
0.5Hz pulse the v1 didn't ship.

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

var rimGlow: some View {
    Color.clear
        .background(rimColor.opacity(rimOpacity))
        .blur(radius: 60)
}

@ViewBuilder
private var animatedRim: some View {
    if host.state == .ready && !reduceMotion {
        PhaseAnimator([RimPhase.dim, .bright]) { phase in
            rimGlow.opacity(phase == .bright ? 0.18 : 0.08)
        } animation: { _ in .smooth(duration: 1.4) }
    } else {
        rimGlow.opacity(host.state == .ready ? 0.14 : 0.06)
    }
}
```

### C2 — `SettingsView` (Frames 04–08)

**Replace the custom HStack(rail, content) with a real `NavigationSplitView`** —
tvOS supports it natively as of iOS 16, with proper focus management
between sidebar and detail. The rail becomes a `List` with `Section`s,
the detail uses `Form`.

```swift
NavigationSplitView {
    List(selection: $selection) {
        ForEach(SettingsTab.allCases) { tab in
            Label(tab.label, systemImage: tab.icon)
                .tag(tab)
        }
    }
} detail: {
    switch selection {
    case .stream:    StreamForm()
    case .network:   NetworkForm()
    // ...
    }
}
```

This gets us, for free:
- Correct focus chrome on rail items (no custom `chiakiFocusRing`).
- Proper sidebar selection state.
- Adaptive sidebar width.
- iOS 26+ scroll edge effects.

**Each tab body uses `Form` + `Section`:**

```swift
Form {
    Section {
        LabeledContent("Resolution") {
            Picker("", selection: $resolution) {
                ForEach(VideoResolution.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        LabeledContent("Refresh rate") {
            Picker("", selection: $fps) {
                ForEach(VideoFPS.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    } footer: {
        Text("Higher refresh rates require a 4K HDR TV and Apple TV 4K.")
    }
    Section {
        LabeledContent("Bitrate") {
            VStack(alignment: .trailing, spacing: 4) {
                Slider(value: $bitrate, in: 2_000...50_000, step: 500)
                Text("\(bitrate / 1000) Mbps")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    } footer: {
        Text("Hard ceiling. The PS5 will adapt downward on a weak link.")
    }
}
.formStyle(.grouped)
```

`Form` + `Section` gives us:
- Section grouping with proper visual rhythm.
- Footer text for hints (correctly typed at `.footnote` with secondary
  color).
- Native `LabeledContent` row chrome.
- `Picker(.segmented)` with system focus chrome.

**Delete `ChiakiSegmented`, `ChiakiSlider`, `SettingsRow`,
`SettingsForm` entirely.**

### C3 — Sheets (`ChiakiSheet`, Frames 09, 11)

**Move from "AppState route → fullscreen replacement" to
`.sheet(item:)` over the host list.** This is the F5 / X5 architectural
fix. AppState gets:

```swift
enum SheetItem: Identifiable {
    case manualHost
    case registration(Host)
    case consolePin(hostId: String)

    var id: String { ... }
}

@Observable
final class AppState {
    var sheet: SheetItem? = nil
}
```

```swift
HostListView()
    .sheet(item: $appState.sheet) { item in
        switch item {
        case .manualHost: ManualHostSheet()
        case .registration(let host): RegistrationSheet(host: host)
        case .consolePin(let id): ConsolePinSheet(hostId: id)
        }
    }
```

`.sheet(item:)` gives:
- Native scrim + dismissal.
- Swipe-down-to-dismiss.
- `\.dismiss` environment value the sheet can call.
- Correct focus restoration when the sheet closes.
- iOS 26+ `.presentationSizing` for sizing control.

The sheets become regular SwiftUI views with `Form` content:

```swift
struct ManualHostSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section { ... }
            }
            .navigationTitle("Add Manual Console")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { ...; dismiss() }
                        .disabled(!canAdd)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationSizing(.fitted)
    }
}
```

Native sheet + Form + toolbar primary/cancellation actions = correct
focus chrome, correct dismissal, native tvOS conventions, no custom
focus halos.

**Delete `ChiakiSheet`, `ChiakiSheetPrimaryButton`, `ChiakiSheetSecondaryButton`.**

### C4 — `ChiakiDigitPicker` (Frame 11)

The custom digit-reel picker has the right *idea* — tvOS keyboard for
8-digit numeric input is bad UX. But the implementation is too wide,
the static-when-unfocused state is confusing, and the focus chrome
is the same chiakiFocusRing problem.

**Rebuild as a single composite `Picker(.wheel)` per column** wrapped
in an HStack. SwiftUI's `Picker(.wheel)` is the canonical reel UI —
focus, scroll, and selection are all handled natively. Each wheel
binds to a single digit (0…9) and the parent re-assembles the string.

```swift
struct DigitPicker: View {
    @Binding var value: String
    let length: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<length, id: \.self) { col in
                Picker("", selection: digitBinding(at: col)) {
                    ForEach(0..<10, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(width: 80, height: 180)
            }
        }
    }

    private func digitBinding(at col: Int) -> Binding<Int> {
        // Same as v1 — read/write specific column from the assembled string.
    }
}
```

`Picker(.wheel)` on tvOS is a focusable column that scrolls vertically.
Focus chrome, accessibility, and behavior are all native.

### C5 — `ConfirmDialog` (Frame 12)

**Replace with native SwiftUI `.alert(...)` modifier.** SwiftUI 17+'s
alert is correctly tvOS-native: scrim, title, message, primary/cancel
buttons with proper focus.

```swift
.alert("Hide host?", isPresented: $showConfirm) {
    Button("Confirm", role: .destructive) { onConfirm() }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This will remove \(host.nickname) from the list.")
}
```

This eliminates the custom `ConfirmDialog` entirely and fixes the scrim
opacity, dialog overlap, and focus chrome bugs in one swap.

The `ConfirmDialogModel` + `AppState.showConfirm` API can stay (so call
sites don't change) — internally, AppState's confirm state drives the
boolean for `.alert(isPresented:)`.

### C6 — `ErrorToastView` (not in captures but verified)

Replace with native `.alert` for errors that need acknowledgement, or
SwiftUI's iOS 17+ `.contentTransition(...)` overlay pattern for
auto-dismissing toasts. The current implementation works; just point it
at the new tokens.

---

## Part 3 — Per-frame after-state spec

Each frame's expected post-implementation appearance:

### Frame 00 (Empty state)
- Use `ContentUnavailableView`:
  ```swift
  ContentUnavailableView {
      Label("Looking for your PS5", systemImage: "gamecontroller")
  } description: {
      Text("Make sure your PS5 is on the same Wi-Fi as the Apple TV " +
           "and Remote Play is enabled in System → Remote Play.")
  } actions: {
      Button("Add manually") { appState.sheet = .manualHost }
          .buttonStyle(.borderedProminent)
  }
  ```
- Native HIG empty state with Dynamic Type, semantic colors, the system
  icon-headline-description-action layout, and built-in animation.

### Frame 01 (Home, populated, toolbar focused)
- Toolbar: wordmark in `.title.weight(.bold)`, status sub-line in
  `.footnote` secondary. Settings gear in a `.buttonStyle(.card)`
  Button so it has visible chrome.
- Hero card uses `.buttonStyle(.card)` and wraps the entire card as
  a single Button whose action is "connect." The inline secondary
  actions (Wake / Edit / Forget) live in a separate row *below* the
  card or behind a `.contextMenu` on the card.

### Frame 02 (CONNECT focused)
- The card itself focuses with the system's card focus chrome. The
  CONNECT amber gradient is the card's *content*, not its focus state.
  Focus is communicated by the system parallax + scale, not by an
  amber halo overlay.

### Frame 03 (Hide focused)
- Hide is a separate `.buttonStyle(.card)` Button below the hero card.
  Focusing it does not affect the visual state of CONNECT (since they're
  siblings, not children of a single focusable). Eliminates the
  "disabled-CONNECT" bug.

### Frame 04 (Stream tab)
- `Form` with sections:
  - Section "Picture": Resolution (segmented), Refresh rate (segmented),
    Codec (segmented). Footer: "Higher refresh rates need a 4K HDR TV."
  - Section "Quality": Render preset (segmented). Footer: "Higher
    quality costs ~1–2 ms of decode latency."
  - Section "Bandwidth": Bitrate (slider with mono-digit readout).
    Footer: "Hard ceiling. PS5 adapts down on weak links."
  - Section "Compatibility": Vertical sync (toggle). Footer: "Reduces
    tearing. Adds ~16 ms of latency."

### Frame 05 (Network tab)
- `Form` with sections:
  - Section "Audio": Audio buffer (slider), Volume (slider with mute
    toggle). Footer: "Higher buffer = smoother audio, more lag."
  - Section "Connection diagnostics": Weak Wi-Fi threshold (slider),
    Reported loss ceiling (slider). Footer explains the diagnostic
    role.

### Frame 06 (Controller tab)
- `List` of `Section` per cluster (Face buttons / D-pad / Shoulders /
  Left stick / Right stick / System). Each row shows label + green
  dot (using `.contentTransition(.symbolEffect)` for the dot's
  state change).
- Header section above the list: vendor name, profile chip, HOME
  status as a prominent `LabeledContent` row using `.foregroundStyle(.red)`
  for "not exposed" — full row, full width, unmissable.

### Frame 07 (Consoles tab)
- `Form` with a single `Section` containing the registered consoles
  list and a `Section` footer with a `Button("Register New Console")`.
- Each registered console is a row with `.swipeActions` for delete
  on tvOS (which becomes a long-press menu).

### Frame 08 (App tab)
- `Form` with the same row chrome as Frames 04–05. Trailing colons
  removed. Picker(.menu) usages converted to `Picker(.segmented)`
  where the option count is small. Toggles use `Toggle` directly.
- PSN Account-ID gets a `LabeledContent("PSN Account-ID")` showing
  the value as `.font(.body.monospaced())` followed by a "Change…"
  Button that opens an alert with TextField (or a proper
  TextEditor sheet, which is a step further but probably overkill).

### Frame 09 (Manual Host sheet)
- `.sheet(item:)`-presented `NavigationStack { Form { ... } }` with
  `.toolbar` for Cancel/Add. Address row is a *real* TextField
  (no Button-→-alert two-step). Linked console row is a
  `Picker(.menu)`.

### Frame 11 (Register sheet)
- `.sheet(item:)`-presented `NavigationStack { Form { ... } }` with
  `.toolbar` for Cancel/Register. Sections:
  - Section "Console" (read-only): Host (`LabeledContent`),
    Console (`LabeledContent`), PSN Account-ID (`LabeledContent` +
    note pointing at Settings → App).
  - Section "PIN": `DigitPicker` (the new wheel-based one),
    full width.
  - Section footer: "Find this on your PS5: Settings → System →
    Remote Play → Link Device."
  - Status section (only when `state != .idle`): live status with
    progress / success / failure icon.

### Frame 12 (Confirm dialog)
- `.alert(...)` — no custom view. tvOS draws the alert with the
  system's modal chrome.

---

## Part 4 — Implementation order

Each step is a self-contained commit. Tests + build green at each.

1. **Foundation (F1–F4):** Theme.swift sweep — delete `chiakiFocusRing`,
   point `Theme.font` at semantic font roles, drop hardcoded layout
   tokens, add `Theme.applyTheme` that sets `.accentColor`.
2. **Replace ConfirmDialog with `.alert`:** smallest visible bug fix,
   single-file change, validates the "use system primitives" thesis.
3. **Replace ChiakiSegmented + ChiakiSlider with `Picker(.segmented)` +
   `Slider`:** rewrite Stream/Network tab content. Delete the two
   custom components.
4. **Migrate App + Consoles tabs to the new SettingsRow pattern:**
   resolves the half-finished-redesign critique.
5. **Replace SettingsView's HStack with NavigationSplitView + Form +
   Section:** big visual change, but native focus + adaptive layout.
6. **Replace ChiakiSheet with `.sheet(item:)`-driven sheets:**
   biggest architectural change. AppState gets a `sheet: SheetItem?`
   property; the three sheet views become standalone with native
   `.toolbar` confirm/cancel.
7. **Replace ChiakiDigitPicker columns with `Picker(.wheel)`:**
   single-component swap; integrates cleanly with the new
   RegistrationSheet.
8. **HostCard rework — `.buttonStyle(.card)` + content-driven sizing
   + custom PS5 silhouette:** big visual win. Drop hardcoded
   dimensions, add the steady-state ready pulse via PhaseAnimator
   (gated on Reduce Motion).
9. **Empty state → `ContentUnavailableView`.**
10. **Delete `chiakiFocusRing`, `HostTile.swift`, custom ChiakiSheet*
    components, custom Settings* helpers — every now-unused file.**

After each commit, capture a fresh screenshot and verify the frame
matches the spec in Part 3. Re-run the test suite.

---

## What stays vs. what goes

**Stays:**
- `Theme.swift` color tokens (ink, amber, mist, rose, green, psBlue) —
  these carry brand meaning the system can't infer.
- `Theme.font` API as a font seam (still useful when we eventually
  bundle Inter, even though the role values become semantic font styles).
- `Theme.chiakiBackground()` view modifier — the gradient mesh is
  fine, just needs to be visible (slight opacity bump on the radial
  anchors).
- `HostCard`, `RegistrationView`, `ManualHostDialog`, etc. as **views**
  — but their internals get rewritten to use system primitives.
- `ConfirmDialogModel` + `AppState.showConfirm` API — internally driven
  by `.alert(isPresented:)`.

**Goes:**
- `Theme.chiakiFocusRing` (the root cause).
- `ChiakiSegmented`, `ChiakiSlider`, `ChiakiSheet`,
  `ChiakiSheetPrimaryButton`, `ChiakiSheetSecondaryButton`,
  `ChiakiDigitPicker` — replaced by system primitives.
- `Theme.hostCardWidth/Height/...`, `modalMaxWidth`,
  `settingsRailWidth` — replaced by content-driven sizing.
- `SettingsForm`, `SettingsRow` — replaced by `Form` + `Section` +
  `LabeledContent`.

Net: ~700 lines of custom chrome deleted, ~250 lines of system-
primitive integration added. The app does *less hand-rolled work*
and looks *more native*, which is exactly what tvOS users expect.

---

**Next:** implement.
