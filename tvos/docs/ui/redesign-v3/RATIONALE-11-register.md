# Rationale — Frame 11 (Register sheet)

Capture: [`11-register.png`](./11-register.png)
Source: [`RegistrationView.swift`](../../../tvos/ChiakiTV/Views/RegistrationView.swift)
Shared design system: [`README.md`](./README.md)

---

## What this screen does

First-time pairing of a discovered PS5: confirm the read-only
identity (host / console / PSN account), enter the 8-digit
Remote Play PIN, hit Register. Modal over the host list.

## Per-screen design choices

### 1. Two distinct sections — *Console* (read-only) and *Remote Play PIN* (input)

The user doesn't *configure* Host or Console — they *confirm*
them. Putting these in their own section above the PIN section
visually communicates "this is for context, you're verifying you're
about to pair the right device."

> Surface read-only context separately from input fields.
> Mixing them creates visual confusion about which rows are
> editable.
>
> — [LogRocket — *Setting the stage: Designing settings screen UI*](https://blog.logrocket.com/ux-design/designing-settings-screen-ui/)

### 2. PSN Account-ID shows error state inline when missing

If the user hasn't set their PSN ID in Settings → App, the row
shows "Set this in Settings → App" in `Theme.rose500`. The
Register button then validates `accountOK = !appState.settings.psnAccountId.isEmpty`
and stays disabled.

This is **inline validation** with clear remediation — the user
sees both "what's wrong" and "where to fix it" without leaving
the modal:

> Inline error states should answer two questions at once: "what's
> wrong?" and "what do I do about it?". Don't show a red label
> without a path forward.
>
> — [DesignStudio UI/UX — *12 Form UI/UX Design Best Practices*](https://www.designstudiouiux.com/blog/form-ux-design-best-practices/)

### 3. PIN reels span 8 digits → wider sheet

Frame 11 is the *widest* sheet in the app because of the 8-digit
PIN row (8 × 96pt + 7 × 12pt gaps = ~852pt). The shared modal cap
(`maxWidth: 1180`) accommodates this with ~160pt margin.

### 4. Status row appears only when relevant

A fourth `Section` with `Label(statusMessage, systemImage: glyph)`
appears only when `registrationService.state` is not `.idle` —
i.e. the user has hit Register and is waiting / succeeded /
failed. No empty placeholder when nothing is happening.

> Don't reserve space for state that hasn't occurred yet. A
> conditional `if let` is cleaner than a perma-rendered "Waiting…"
> with empty content.
>
> — [Reform — *7 Visual Hierarchy Tips for Better Form Design*](https://www.reform.app/blog/7-visual-hierarchy-tips-for-better-form-design)

### 5. Status colour tracks success/failure semantics

- `.succeeded` → `Theme.green500` + checkmark
- `.failed` → `Theme.rose500` + warning triangle
- `.running` → `.secondary` + circular arrow

Three states, three glyphs, three colours — matches Material 3's
semantic-state colour palette.

### 6. Auto-dismiss on success

`.onChange(of: appState.registrationService.state)` watches for
`.succeeded` and after 600ms dismisses the sheet. The user sees
the success state briefly, then returns to a host list with the
new console paired — no manual "Done" press needed.

> When an action's success is the natural next-state, dismiss
> the modal automatically with a short confirmation glance
> (~500–800ms). Forcing the user to press a button after success
> adds friction with no information value.
>
> — [Material Design 3 — *Dialogs*](https://m3.material.io/components/dialogs/guidelines)

### 7. Register button shows progress in its label

Default label: "Register". While `isRunning`: "Registering…". The
button itself is the progress indicator — no separate spinner
needed. This pattern is canonical iOS / macOS form submission UX.

## Sources

- [LogRocket — *Setting the stage: Designing settings screen UI*](https://blog.logrocket.com/ux-design/designing-settings-screen-ui/)
- [DesignStudio UI/UX — *12 Form UI/UX Design Best Practices*](https://www.designstudiouiux.com/blog/form-ux-design-best-practices/)
- [Reform — *7 Visual Hierarchy Tips for Better Form Design*](https://www.reform.app/blog/7-visual-hierarchy-tips-for-better-form-design)
- [Material Design 3 — *Dialogs*](https://m3.material.io/components/dialogs/guidelines)
- [Apple HIG — *Designing for tvOS*](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos)
