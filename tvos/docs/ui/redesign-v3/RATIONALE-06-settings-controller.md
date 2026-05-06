# Rationale — Frame 06 (Settings → Controller)

Capture: [`06-settings-controller.png`](./06-settings-controller.png)
Source: `ControllerDiagnosticTab` in [`SettingsView.swift`](../../../tvos/ChiakiTV/Views/SettingsView.swift)
Shared design system: [`README.md`](./README.md)

---

## What this screen does

Live diagnostic of the connected MFi/DualSense controller: vendor
name, profile class, Home-button availability, plus a per-button
"is pressed?" indicator polled at 80ms. This is *not* a preferences
screen — it's an instrument panel.

## Per-screen design choices

### 1. Sectioned by button cluster, not alphabetically

Buttons are grouped by physical cluster on the controller:
GAMEPAD / FACE BUTTONS / D-PAD / SHOULDERS / LEFT STICK / RIGHT STICK
/ SYSTEM. This matches the user's mental model of the device
("test the right shoulder") rather than naming convention.

> Group settings by the user's mental model of the underlying
> system, not by the engineering taxonomy. For diagnostic screens
> in particular, mirror the physical layout of the device.
>
> — [Toptal — *How to Improve App Settings UX*](https://www.toptal.com/designers/ux/settings-ux)

### 2. "Home button" status uses semantic colour + warning glyph

If the controller exposes the Home button (DualSense Edge, etc.)
the row shows a green checkmark + "Exposed". If not (most controllers
on tvOS), it shows a rose triangle + "Not exposed", with a footer
explaining the long-press-Options workaround.

This uses **colour + icon + word together** so the status is
unambiguous regardless of colour-blindness or VoiceOver:

> Never communicate state with colour alone. Pair with an icon and
> a label so the meaning is multi-modal.
>
> — [W3C WAI — *Use of color* (WCAG 1.4.1)](https://www.w3.org/WAI/WCAG21/Understanding/use-of-color.html)

### 3. Per-button rows use a circle indicator

Each button row shows `[Button name] ............ ○` where ○ fills
green when pressed. The indicator is the same size and position on
every row — diagnostic signal at a glance.

> For real-time monitoring UIs, keep the change-indicator location
> stable across rows. The eye learns where to look in 1–2 seconds
> if the layout is consistent.
>
> — [Penpot — *Typography hierarchy: How to improve readability*](https://penpot.app/blog/typography-hierarchy-how-to-improve-readability/)

### 4. ContentUnavailableView when no controller present

If `GCController.controllers()` is empty, the tab shows a
`ContentUnavailableView("No controllers connected", systemImage:
"gamecontroller", description: ...)` with the pairing instruction.

iOS 17's `ContentUnavailableView` is the canonical empty-state
container — it handles localisation, accessibility, and visual
polish without re-implementation:

> ContentUnavailableView is perfect for times your app relies on
> user information that hasn't been provided yet. Apple introduced
> this beautifully crafted system component designed to simplify
> empty-states, "no data" screens, error states, search-no-results,
> and placeholder views.
>
> — [Medium / Gaurav Parmar — *Mastering ContentUnavailableView in SwiftUI*](https://medium.com/@gauravios/mastering-contentunavailableview-in-swiftui-the-new-elegant-empty-state-ui-dfa291d52372)

### 5. 80ms poll loop, not 16ms

Polling at 80ms (≈12 Hz) instead of every frame keeps the tab
responsive enough for human button-press perception (people can't
distinguish gaps shorter than ~50ms) while keeping the polling task
off the streaming hot path.

## Sources

- [W3C WAI — *Use of Color* (WCAG 1.4.1)](https://www.w3.org/WAI/WCAG21/Understanding/use-of-color.html)
- [Toptal — *How to Improve App Settings UX*](https://www.toptal.com/designers/ux/settings-ux)
- [Medium / Gaurav Parmar — *Mastering ContentUnavailableView in SwiftUI*](https://medium.com/@gauravios/mastering-contentunavailableview-in-swiftui-the-new-elegant-empty-state-ui-dfa291d52372)
- [Penpot — *Typography hierarchy: How to improve readability*](https://penpot.app/blog/typography-hierarchy-how-to-improve-readability/)
