# Rationale — Frame 04 (Settings → Stream)

Capture: [`04-settings-stream.png`](./04-settings-stream.png)
Source: `StreamTab` in [`SettingsView.swift`](../../../tvos/ChiakiTV/Views/SettingsView.swift)
Shared design system: [`README.md`](./README.md)

---

## What this screen does

Picture / Quality / Compatibility tradeoffs for the live video stream:
resolution, refresh rate, codec, render preset, bitrate, vertical sync.

## Per-screen design choices

### 1. Segmented pickers for ≤ 4-option enums

Resolution (4 options), Refresh rate (2), Codec (2), Render preset (2)
all use `segmentedRow(...)` — the helper that wraps `Picker` in
`LabeledContent` so the label stays visible alongside the segmented
control. Material 3 caps segmented buttons at 5 options per group,
matching what we use:

> Segmented buttons should hold no more than 5 items. For more
> options, use a different selection control like a list, dropdown,
> or tabs.
>
> — [Material Design 3 — *Segmented buttons*](https://m3.material.io/components/segmented-buttons/guidelines)

### 2. Drill-in for many-option Bitrate

Bitrate has 97 valid values (`stride(from: 2_000, through: 50_000, by: 500)`).
Segmented would force the user to scroll through pills with the D-pad.
The default `Picker(title:)` style on tvOS Form renders as a chevron
drill-in row — single Select press opens a wheel-style popover that
respects D-pad up/down. Right control for the data shape.

### 3. Single Toggle row at the bottom

`Toggle("Vertical sync", isOn:)` — one binary preference, no need for
a wrapper. Sits in its own `Section` so the footer ("Reduces tearing.
Adds ~16 ms of latency.") attaches to the right control.

### 4. Footer hints, not inline help

Each `Section { ... } footer: { Text(...) }` gives a one-line
explanation under the section. Inline tooltips are wrong for tvOS
(no hover) and wrong for accessibility (hidden from VoiceOver).
Section footer keeps the explanation discoverable + announced.

> Footers serve three purposes: clarification, regulation, and
> next-step guidance. Use them where the input choice has
> consequences the user can't infer from the label alone.
>
> — [DesignStudio UI/UX — *12 Form UI/UX Best Practices*](https://www.designstudiouiux.com/blog/form-ux-design-best-practices/)

### 5. Quality/Bandwidth merged into one section

In v2 these were two adjacent sections with one row each — visual
hiccup of "tiny section / tiny section / bigger section". v3
combines them since the footer ("Higher quality costs ~1–2 ms…
Bitrate is a hard ceiling…") covers both rows. Reduces vertical
fragmentation.

> Group related fields together so users can scan with fewer
> stops. A multi-section page with one field per section breaks
> the eye's natural grouping.
>
> — [Salim Ansari — *Best practices for form design*](https://uxdesign.cc/best-practices-for-form-design-ff5de6ca8e5f)

## Sources

- [Material Design 3 — *Segmented buttons*](https://m3.material.io/components/segmented-buttons/guidelines)
- [DesignStudio UI/UX — *12 Form UI/UX Design Best Practices*](https://www.designstudiouiux.com/blog/form-ux-design-best-practices/)
- [Salim Ansari — *Best practices for form design*](https://uxdesign.cc/best-practices-for-form-design-ff5de6ca8e5f)
- [Apple HIG — *Layout*](https://developer.apple.com/design/human-interface-guidelines/layout)
- [LearnUI — *3 Pro Tips on Alignment*](https://www.learnui.design/blog/3-pro-tips-on-alignment.html)
