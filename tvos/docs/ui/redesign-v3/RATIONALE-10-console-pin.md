# Rationale — Frame 10 (Console PIN sheet)

Capture: [`10-console-pin.png`](./10-console-pin.png)
Source: [`ConsolePinDialog.swift`](../../../tvos/ChiakiTV/Views/Components/ConsolePinDialog.swift)
Shared design system: [`README.md`](./README.md)

---

## What this screen does

Set the 4-digit Remote Play PIN for an already-registered PS5
(separate from the 8-digit pairing PIN at first registration).
Modal over the host list.

## Per-screen design choices

### 1. PIN reels instead of TextField

tvOS's on-screen keyboard for a 4-digit numeric PIN is the
worst-case interaction model: Siri Remote → keyboard sheet →
tap each digit → confirm. ~10 input events for 4 characters.

`ChiakiDigitPicker` turns this into a row of focusable digit
columns: Left/Right walks columns, Up/Down cycles 0–9. Four
events for four digits.

> Match the input control to the data shape. For numeric PINs,
> a column-of-digits picker is far faster than a generic
> alphanumeric keyboard.
>
> — [Apple HIG — *Designing for tvOS*](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos)

### 2. Reels are centered horizontally inside the Form section

The 4 reels live inside `Section { HStack { Spacer(); reels;
Spacer() } }` — the spacers keep the reels visually centered
in the section. The reels themselves are short content that
benefits from horizontal centering (the *titles* and *body*
prohibition against centering doesn't apply to short
visually-impactful elements like a digit row).

> Center alignment should be reserved for short content like
> titles, headlines, and call-to-action buttons.
>
> — [UXPin — *Alignment in Design: A Complete Guide* (2026)](https://www.uxpin.com/studio/blog/alignment-in-design-making-text-and-visuals-more-appealing/)

### 3. Footer below reels = "where do I find this?"

`"Find this on your PS5: Settings → System → Remote Play."` —
answers the question every user has: "what PIN are you asking
for?" The breadcrumb path mirrors the PS5's own menu structure
so the user can navigate.

### 4. SheetChrome reused from other sheets

Same Cancel / title / Set PIN top bar as Frames 09 and 11. The
user sees the same chrome pattern on every modal — they don't
have to re-learn dismissal.

> Reuse modal chrome across screens — the user's mental model of
> "left = cancel, right = confirm" should hold across every
> modal in the app.
>
> — [Apple HIG — *Layout*](https://developer.apple.com/design/human-interface-guidelines/layout)

### 5. Set PIN disabled while pin == "0000"

The default state is `0000` (placeholder). Set PIN button is
disabled until the user changes at least one digit AND the PIN
passes validation (`pin != "0000" && pin.allSatisfy(\.isNumber)`).
This prevents accidentally registering "0000" as the PIN.

### 6. System focus chrome on each reel

Each `DigitReel` uses `.focusable(true)` and reads `\.isFocused`
from the environment — the system applies its own focus halo
(slight elevation + glow). No custom focus ring.

> Take advantage of system-provided focus indicators on tvOS.
> They're optimised for living-room viewing distances and adapt
> to user accessibility preferences.
>
> — [Apple HIG — *Focus and Selection*](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)

## Sources

- [Apple HIG — *Designing for tvOS*](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos)
- [Apple HIG — *Focus and Selection*](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)
- [Apple HIG — *Layout*](https://developer.apple.com/design/human-interface-guidelines/layout)
- [UXPin — *Alignment in Design: A Complete Guide* (2026)](https://www.uxpin.com/studio/blog/alignment-in-design-making-text-and-visuals-more-appealing/)
- [Material Design 3 — *Dialogs*](https://m3.material.io/components/dialogs/guidelines)
