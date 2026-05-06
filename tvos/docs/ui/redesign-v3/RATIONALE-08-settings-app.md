# Rationale — Frame 08 (Settings → App)

Capture: [`08-settings-app.png`](./08-settings-app.png)
Source: `AppTab` in [`SettingsView.swift`](../../../tvos/ChiakiTV/Views/SettingsView.swift)
Shared design system: [`README.md`](./README.md)

---

## What this screen does

App-level preferences and identity: behaviour on disconnect/suspend,
audio-vs-video output mode, PSN Account-ID, and three diagnostic
toggles (Streamer Mode, Verbose Logs, Show Stream Stats).

## Per-screen design choices

### 1. Three sections, each with a distinct concern

- **Behaviour** — segmented pickers for short-option enums
- **Account** — PSN Account-ID button
- **Diagnostics** — three toggles

Each section's purpose is named in its header. The user can scan
section headers and decide whether the answer they need is here
without reading every row:

> Section headers act as the user's eye-skim landmark. Use them
> liberally; don't merge unrelated fields under a single header
> just to reduce vertical space.
>
> — [Toptal — *How to Improve App Settings UX*](https://www.toptal.com/designers/ux/settings-ux)

### 2. Option labels shortened to fit segmented controls

In v2, "Action on disconnect" had options "Ask / Disconnect / Put PS5
in Sleep Mode" and "Audio + Video" had "Audio and Video Enabled" — both
too long for segmented control widths and forcing tail-truncation. v3:

- DisconnectAction: "Ask / Disconnect / **Sleep**" (was "Put PS5 in Sleep Mode")
- AudioVideoMode: "**Both** / Audio only / Video only / Disabled"
  (was "Audio and Video Enabled")

> Segmented button labels should fit the cell width without
> wrapping. If they don't, switch to a different control or
> shorten the label — never let the cell truncate.
>
> — [Material Design 3 — *Segmented buttons*](https://m3.material.io/components/segmented-buttons/guidelines)

### 3. PSN Account-ID is a Button → alert(TextField)

Pure inline `TextField` in a Form row would force-trigger the tvOS
on-screen keyboard, which on Apple TV is a slow remote-driven grid.
A Button-row that opens an alert with TextField gives the same data
entry but keeps the *settings list* free of keyboard-summoning rows.

The button row visually mirrors the other rows ("PSN Account-ID"
left-aligned label, monospaced value right-aligned) and uses the
default Form-row focus chrome.

### 4. "Not set" placeholder, not "—"

When the field is empty, the value shows "Not set" instead of the
em-dash placeholder. UX writing principle: state the meaning, not the
ASCII placeholder. The user shouldn't have to interpret what `—` means.

> Microcopy should be self-explanatory at a glance. Replace
> placeholder symbols (—, *, ?) with English words wherever the
> meaning isn't obvious.
>
> — [Concept7 — *5 UX best practices for user-friendly labels*](https://concept7.nl/en/articles/forms-101-5-ux-best-practices-for-user-friendly-labels-in-forms)

### 5. Toggles separate from button rows

Diagnostics (three toggles) live in their own section, away from the
PSN Account-ID button. This prevents "toggle fatigue" — running rows
of toggles between heterogeneous control types reads as cluttered.

### 6. Footer for the toggle group, not per-toggle

One footer below all three toggles explains the cluster ("Streamer
Mode hides identifying details from the stream HUD. Verbose Logs
writes detailed diagnostics to Console."). Per-toggle hints would
fragment the visual rhythm — section-level hint preserves it.

## Sources

- [Toptal — *How to Improve App Settings UX*](https://www.toptal.com/designers/ux/settings-ux)
- [Material Design 3 — *Segmented buttons*](https://m3.material.io/components/segmented-buttons/guidelines)
- [Concept7 — *5 UX best practices for user-friendly labels in forms*](https://concept7.nl/en/articles/forms-101-5-ux-best-practices-for-user-friendly-labels-in-forms)
- [DesignStudio UI/UX — *12 Form UI/UX Design Best Practices*](https://www.designstudiouiux.com/blog/form-ux-design-best-practices/)
