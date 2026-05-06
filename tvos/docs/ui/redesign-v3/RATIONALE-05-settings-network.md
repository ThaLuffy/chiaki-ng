# Rationale — Frame 05 (Settings → Network)

Capture: [`05-settings-network.png`](./05-settings-network.png)
Source: `NetworkTab` in [`SettingsView.swift`](../../../tvos/ChiakiTV/Views/SettingsView.swift)
Shared design system: [`README.md`](./README.md)

---

## What this screen does

Audio buffering and Wi-Fi connection-quality knobs: audio buffer
length, output volume, weak-Wi-Fi packet-loss threshold, reported-loss
ceiling. All four are large-range numeric values.

## Per-screen design choices

### 1. All four pickers are drill-in

Audio buffer (49 values), Volume (21), Weak Wi-Fi threshold (20),
Reported loss ceiling (20) — each too large for segmented. They use
the default `Picker(title:)` style which renders as
`[Label]    [current value] >` — a single drill-in row.

> When option count exceeds 5, prefer a list, dropdown, or
> drill-in over a segmented control. The segmented control's value
> proposition is *visible all-at-once choice*; that breaks down when
> the user has to scroll across pills.
>
> — [Material Design 3 — *Segmented buttons*](https://m3.material.io/components/segmented-buttons/guidelines)

### 2. Two sections by *purpose*, not by data type

- "Audio" — buffer + volume (output processing)
- "Connection diagnostics" — weak-Wi-Fi threshold + loss ceiling
  (signal-quality reporting)

Section grouping reflects the *user's mental model* — "what am I
adjusting?" — not the underlying data type. Toptal's settings UX
guide flags this as a primary failure mode of bad settings screens:

> The most common mistake: grouping settings by what the engineer
> implemented, not by what the user wants to do. Group by user task,
> not by class hierarchy.
>
> — [Toptal — *How to Improve App Settings UX*](https://www.toptal.com/designers/ux/settings-ux)

### 3. Footer text answers "what does this do?"

Each footer provides the consequence in plain language:
- "A higher buffer means smoother audio at the cost of mouth-to-ear
  latency."
- "Show a Wi-Fi warning when sustained packet loss exceeds the
  threshold. The ceiling caps reported loss in the in-stream stats
  overlay."

> Provide explanatory text under fields when the consequence is
> non-obvious from the label alone — particularly for technical
> values like timing thresholds or quality knobs.
>
> — [Salim Ansari — *Best practices for form design*](https://uxdesign.cc/best-practices-for-form-design-ff5de6ca8e5f)

### 4. Identical row chrome across all four

Every row goes through `Picker(title, selection:)` with the default
style. SwiftUI's `Form` renders them with identical:
- left-aligned label
- right-aligned current value
- chevron disclosure indicator
- same row height
- same focus halo

This is the LearnUI "guide line" principle in action — the four rows
form a single vertical bar of label-value pairs.

## Sources

- [Material Design 3 — *Segmented buttons*](https://m3.material.io/components/segmented-buttons/guidelines)
- [Toptal — *How to Improve App Settings UX*](https://www.toptal.com/designers/ux/settings-ux)
- [Salim Ansari — *Best practices for form design*](https://uxdesign.cc/best-practices-for-form-design-ff5de6ca8e5f)
- [LearnUI — *3 Pro Tips on Alignment*](https://www.learnui.design/blog/3-pro-tips-on-alignment.html)
- [LogRocket — *Setting the stage: Designing settings screen UI*](https://blog.logrocket.com/ux-design/designing-settings-screen-ui/)
