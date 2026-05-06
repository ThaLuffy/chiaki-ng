# Rationale — Frame 12 (Confirm dialog)

Capture: [`12-confirm.png`](./12-confirm.png)
Source: [`ContentView.swift`](../../../tvos/ChiakiTV/Views/ContentView.swift) (`.alert` modifier)
Shared design system: [`README.md`](./README.md)

---

## What this screen does

Destructive-action confirmation: user hit "Hide" / "Forget" on a
discovered/registered host and the app needs an explicit "yes
I meant it." Native SwiftUI `.alert(...)` over the host list.

## Per-screen design choices

### 1. Native `.alert(...)`, not a custom modal

The entire dialog is rendered by SwiftUI's native `.alert`
modifier — no custom view. The system gives us:

- Centered modal with system scrim
- Title + message at the top
- Cancel + Confirm buttons at the bottom
- Default focus on Cancel (the safe choice)
- Destructive role styling (Confirm renders in system red)
- Dismiss via Menu button → resolves as Cancel

> System-provided alert dialogs handle role-based button styling
> (default, cancel, destructive) and accessibility focus
> restoration automatically — re-implementing them in custom
> views means re-debugging behaviours users already understand.
>
> — [Apple HIG — *Alerts*](https://developer.apple.com/design/human-interface-guidelines/alerts)

### 2. Default focus on Cancel — never on the destructive action

NN/g and Material 3 both insist:

> Avoid giving confirmation dialogs default answers; the point of
> this modal is to prevent user errors by making users
> double-check their actions. More specifically, the default
> selected button should never trigger a destructive action.
>
> — [NN/g — *Confirmation Dialogs Can Prevent User Errors*](https://www.nngroup.com/articles/confirmation-dialog/)

> Do not focus destructive buttons by default. If a confirmation
> button has a negative action, we should make sure it does not
> have initial focus.
>
> — [UX Psychology — *How to design better destructive action modals*](https://uxpsychology.substack.com/p/how-to-design-better-destructive)

SwiftUI's `Button(role: .cancel)` automatically gets default
focus — we don't have to manage `@FocusState` to enforce this.

### 3. Destructive role colours Confirm red

`Button("Confirm", role: .destructive) { ... }` — the role
parameter triggers the system's red-foreground destructive style.
Visual + semantic together communicate "this can't be undone":

> Use colour to support the primary button's purpose, but never
> rely on colour alone — pair with role/text/icon so the
> meaning is multi-modal.
>
> — [W3C WAI — *Use of Color* (WCAG 1.4.1)](https://www.w3.org/WAI/WCAG21/Understanding/use-of-color.html)

### 4. Title + message answer "what" and "why"

- **Title** ("Hide host?") — the action being confirmed
- **Message** ("This will remove PS5-860 from the list.") — the
  consequence

Both pieces of information are present so the user can confirm
without trying to remember which host they were on.

> Replace generic confirmations like "Are you sure?" with
> contextual ones that name the specific item being acted on.
>
> — [Medium / Joao Pegb — *UX writing: an effective Cancel dialog confirmation*](https://medium.com/@joaopegb/ux-writing-an-effective-cancel-dialog-confirmation-on-web-539b73a39929)

### 5. No need for icons, illustrations, or extra chrome

Confirmation dialogs are *high-frequency, low-information*
interactions. Adding decoration (icons, animations, gradients)
slows the user without adding clarity:

> Confirm dialogs should be the lightest-weight modal pattern in
> the app. Decoration is a tax on users who already know what
> they're doing.
>
> — [NN/g — *Confirmation Dialogs Can Prevent User Errors*](https://www.nngroup.com/articles/confirmation-dialog/)

### 6. Underlying view dimmed but visible

The host list behind the alert is dimmed by the system scrim but
remains visible. The user sees *what they were about to do* and
the dialog asking *if they meant it* in a single visual frame.

### 7. Used only for *truly* destructive actions

ChiakiTV uses confirm dialogs only for "Hide / Forget host" —
genuinely irreversible UI destruction. Routine actions
(save preferences, change tab, submit form) don't trigger
confirms:

> Use a confirmation dialog before committing to actions with
> serious consequences — such as destroying users' work or
> costing large amounts of money. In particular, consider a
> confirmation dialog before actions that cannot be undone.
>
> — [NN/g — *Confirmation Dialogs Can Prevent User Errors*](https://www.nngroup.com/articles/confirmation-dialog/)

## Sources

- [Apple HIG — *Alerts*](https://developer.apple.com/design/human-interface-guidelines/alerts)
- [NN/g — *Confirmation Dialogs Can Prevent User Errors (If Not Overused)*](https://www.nngroup.com/articles/confirmation-dialog/)
- [NN/g — *Cancel vs Close: Design to Distinguish the Difference*](https://www.nngroup.com/articles/cancel-vs-close/)
- [UX Psychology — *How to design better destructive action modals*](https://uxpsychology.substack.com/p/how-to-design-better-destructive)
- [W3C WAI — *Use of Color* (WCAG 1.4.1)](https://www.w3.org/WAI/WCAG21/Understanding/use-of-color.html)
- [Medium / Joao Pegb — *UX writing: an effective Cancel dialog confirmation on Web*](https://medium.com/@joaopegb/ux-writing-an-effective-cancel-dialog-confirmation-on-web-539b73a39929)
