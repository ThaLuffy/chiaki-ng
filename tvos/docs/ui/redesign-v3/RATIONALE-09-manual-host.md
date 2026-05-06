# Rationale — Frame 09 (Manual Host sheet)

Capture: [`09-manual-host.png`](./09-manual-host.png)
Source: [`ManualHostDialog.swift`](../../../tvos/ChiakiTV/Views/Components/ManualHostDialog.swift)
Shared design system: [`README.md`](./README.md)

---

## What this screen does

User wants to add a PS5 by IP/hostname (discovery didn't find it).
Two inputs: address (free-text) and an optional link to an
already-registered host. Modal over the host list.

## Per-screen design choices

### 1. Sheet, not full-screen replacement

Presented via `.fullScreenCover(item: $appState.sheet)` over the
HostListView with a black 60%-opacity scrim. Dismiss via Cancel /
Add or the Menu button. The user keeps spatial context — they
came from the host list, they return to it.

> A modal's primary purpose is to focus attention. The scrim's
> role is to dim, not to remove, the underlying context — so the
> user knows dismissing returns them to where they were.
>
> — [Material Design 3 — *Dialogs*](https://m3.material.io/components/dialogs/guidelines)

### 2. Top bar = SheetChrome (Cancel / title / Add)

`SheetChrome` row is a fixed visual band at the top of the modal.
Cancel left (neutral grey bordered), Title centered (`.title2`
semibold), Add right (amber borderedProminent, disabled when
`canAdd == false`).

Cancel is **never the default focus** because Add is the natural
next-step affordance — but Cancel is *prominent* (same control
size as Add) so the safe-exit is always reachable in one
directional swipe.

### 3. Address as a real `TextField` in the Form

`TextField("e.g. 192.168.1.42", text: $host)` inside a `Form { Section { ... } }`.
On tvOS 17+, this triggers the system on-screen keyboard
modally — same pattern as Settings → Wi-Fi Network password entry.

The placeholder *example* is more useful than a generic "Enter IP":

> Use placeholder text to demonstrate the expected format, not
> just to repeat the label. "e.g. 192.168.1.42" tells the user
> "this field expects an IPv4 address" in two characters of
> microcopy.
>
> — [Concept7 — *5 UX best practices for user-friendly labels*](https://concept7.nl/en/articles/forms-101-5-ux-best-practices-for-user-friendly-labels-in-forms)

### 4. Linked-console as a default-style Picker (drill-in)

`Picker("Linked console", selection: $registeredHostId) { ... }` —
no `.pickerStyle` modifier. Renders as `[Linked console] [current]
>` row. Drill-in is right because the option count varies (0 to N
registered hosts) and we can't predict labels at design time.

### 5. Two sections, distinct concerns

- **Hostname or IP** — the new address
- **Linked console** — optional pairing to existing registration

Splitting prevents the user from interpreting the two as a single
form-fill. Picking a registered host is *optional* — the section
break makes that visually obvious.

### 6. Footer per section, not per field

Each section's footer answers "why would I touch this?" — not
"how do I enter an IP?". The latter is the placeholder's job.

> Field-level help should answer the *why*, not the *how*. The
> *how* belongs in placeholder text or input format constraints.
>
> — [DesignStudio UI/UX — *12 Form UI/UX Design Best Practices*](https://www.designstudiouiux.com/blog/form-ux-design-best-practices/)

### 7. Add button disabled until valid

`canAdd: !host.trimmingCharacters(in: .whitespaces).isEmpty` —
prevents adding an empty manual host. Disabled-state styling comes
free with `.borderedProminent .disabled(!canAdd)`.

> Disable the primary action button rather than allowing the
> form to be submitted in an invalid state and showing an error
> after — the disabled affordance is its own validation.
>
> — [Salim Ansari — *Best practices for form design*](https://uxdesign.cc/best-practices-for-form-design-ff5de6ca8e5f)

## Sources

- [Material Design 3 — *Dialogs*](https://m3.material.io/components/dialogs/guidelines)
- [Concept7 — *5 UX best practices for user-friendly labels in forms*](https://concept7.nl/en/articles/forms-101-5-ux-best-practices-for-user-friendly-labels-in-forms)
- [DesignStudio UI/UX — *12 Form UI/UX Design Best Practices*](https://www.designstudiouiux.com/blog/form-ux-design-best-practices/)
- [Salim Ansari — *Best practices for form design*](https://uxdesign.cc/best-practices-for-form-design-ff5de6ca8e5f)
- [Apple HIG — *Layout*](https://developer.apple.com/design/human-interface-guidelines/layout)
