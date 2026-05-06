# Rationale — Frame 07 (Settings → Consoles)

Capture: [`07-settings-consoles.png`](./07-settings-consoles.png)
Source: `ConsolesTab` in [`SettingsView.swift`](../../../tvos/ChiakiTV/Views/SettingsView.swift)
Shared design system: [`README.md`](./README.md)

---

## What this screen does

Manage paired PS5s — list registered consoles, allow removal, and
present the entry point to register a new one. On a fresh install
(no consoles), show an empty state.

## Per-screen design choices

### 1. ContentUnavailableView for the empty state

Instead of a blank list with only a "Register" button, the empty
state uses `ContentUnavailableView`:

```swift
ContentUnavailableView(
    "No registered consoles",
    systemImage: "gamecontroller",
    description: Text("Pair a PS5 to use Remote Play without re-entering a PIN every time.")
)
```

This gives the user **context**, **guidance**, and **visual
appeal** in one component — Mobbin's three required ingredients of
a good empty state:

> A well-designed empty state should include: Context (clearly
> explains why the screen is empty), Guidance (offers actionable
> next steps to resolve state), Visual appeal (includes engaging
> visuals or illustrations).
>
> — [Mobbin — *Empty State UI Design: Best practices*](https://mobbin.com/glossary/empty-state)

The action ("Register a new console" button) sits in its own
adjacent section so the empty-state explanation isn't crowded by a
focusable affordance.

### 2. Action button as a Form row, not a CTA

`Button { ... } label: { Label("Register a new console", systemImage: "plus.circle.fill") }`
inside a `Form { Section { ... } }`. Same row chrome as every
Settings row → focus chrome consistent with the rest of the screen.
On press it sets `appState.sheet = .registration(...)`.

> For settings-screen affordances, prefer the same row chrome the
> user has already learned — don't introduce a new button style for
> a single action.
>
> — [Toptal — *How to Improve App Settings UX*](https://www.toptal.com/designers/ux/settings-ux)

### 3. Populated list (when registered hosts exist)

Each registered console becomes a `LabeledContent` row:
`[Nickname]    [MAC]    [Forget icon button]`. Forget action gates
on a `Confirm dialog` (Frame 12) — the destructive-action confirm.

### 4. ContentUnavailableView's built-in benefits

- Consistent with iOS / macOS empty-state visuals
- Auto-localised
- Auto-accessible (VoiceOver reads label + description)
- No custom styling required

> Another benefit is that the content unavailable view automatically
> translates into the languages your app supports.
>
> — [Antoine van der Lee — *ContentUnavailableView: Handling Empty States in SwiftUI*](https://www.avanderlee.com/swiftui/contentunavailableview-handling-empty-states/)

### 5. The empty state is *expected*, not an error

Users open this tab with no registered consoles all the time —
it's the natural starting state. The copy reflects that:
"No registered consoles. Pair a PS5 to use Remote Play without
re-entering a PIN every time." — informative, not apologetic.

> Differentiate "expected empty" (first-run, just-cleared,
> filtered-to-nothing) from "unexpected empty" (error, 404).
> Expected-empty copy should be inviting; error-empty copy should
> be diagnostic.
>
> — [Mobbin — *Empty State UI Design*](https://mobbin.com/glossary/empty-state)

## Sources

- [Mobbin — *Empty State UI Design: Best practices, Design variants & Examples*](https://mobbin.com/glossary/empty-state)
- [Antoine van der Lee — *ContentUnavailableView: Handling Empty States in SwiftUI*](https://www.avanderlee.com/swiftui/contentunavailableview-handling-empty-states/)
- [Medium / Gaurav Parmar — *Mastering ContentUnavailableView in SwiftUI*](https://medium.com/@gauravios/mastering-contentunavailableview-in-swiftui-the-new-elegant-empty-state-ui-dfa291d52372)
- [Toptal — *How to Improve App Settings UX*](https://www.toptal.com/designers/ux/settings-ux)
