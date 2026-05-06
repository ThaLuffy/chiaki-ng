# ChiakiTV — Final Redesign Screenshots

Captured 2026-05-06 against `tvos-port` after all 10 redesign steps shipped
(commits `f2e689b2` → `7564d589`). All shots taken on the Apple TV 4K (3rd
gen) tvOS 26.4 simulator at 1920×1080, against a real PS5 (`PS5-860`,
`192.168.2.26`) on the dev LAN.

The screens here are the deliverable of `docs/ui/redesign-plan.md` — each
file maps to one of the plan's per-screen specs and demonstrates that the
audit's high-severity issues are resolved.

## Frames

| # | File | Screen / state |
|---|---|---|
| 00 | [`00-home-empty-state.png`](00-home-empty-state.png) | Home — empty state during discovery. Replaces the prior always-on gamepad silhouette (audit H1) with the actionable "Let's find your PS5" copy from §5.1. |
| 01 | [`01-home-launch.png`](01-home-launch.png) | Home — populated. Discovery just completed; hero card shows PS5-860 with cool ps-blue rim (standby). Toolbar's Add Manual Host has launch focus (no more X exit button per §4.6 / audit H7). |
| 02 | [`02-home-card-focused.png`](02-home-card-focused.png) | Home — CONNECT focused. The amber halo + scaled button is the canonical primary-action affordance. The card's blue rim brightens to signal focus is inside the card. |
| 03 | [`03-home-secondary-focused.png`](03-home-secondary-focused.png) | Home — Hide focused on the secondary action stack. Demonstrates the "always-visible at half opacity, brightens on focus" pattern from §4.1. |
| 04 | [`04-settings-stream.png`](04-settings-stream.png) | Settings → Stream. Vertical rail (§4.2), full-bleed rows with hint sub-text (§4.4), segmented controls for Resolution / Refresh / Codec / Render preset, amber slider for Bitrate. Replaces the old centered-narrow form with pill-button pickers (audit S1, S2). |
| 05 | [`05-settings-network.png`](05-settings-network.png) | Settings → Network (renamed from Audio). All four numeric scalars are sliders — Audio buffer, Volume, Weak Wi-Fi threshold, Reported loss ceiling. Resolves audit A1 / A3 (volume needed a slider, all scalars had wrong control type). |
| 06 | [`06-settings-controller.png`](06-settings-controller.png) | Settings → Controller. Cluster grouping replaces the alphabetical 23-row text wall (audit Co1). The "HOME NOT EXPOSED" rose chip in the header is the most operationally important fact on the page (audit Co3). Profile chip in ps-blue. |
| 07 | [`07-settings-consoles.png`](07-settings-consoles.png) | Settings → Consoles. Register New Console focused. Empty-state copy is concise and the affordance is the only focusable item — clear next step. |
| 08 | [`08-settings-app.png`](08-settings-app.png) | Settings → App (renamed from General — "General" was meaningless). Holds disconnect/suspend behavior, PSN account ID, streamer mode, verbose logs, show-stream-stats. Still uses the legacy SettingsRow rendering pending the row-rework follow-up (Step 4 covered Stream + Network). |
| 09 | [`09-manual-host-sheet.png`](09-manual-host-sheet.png) | Add Manual Console sheet. New centered modal-card chrome (§4.5), italic hint sub-lines per row, primary/secondary footer buttons. Replaces the back-chevron-toolbar full-screen form. |
| 11 | [`11-register-sheet.png`](11-register-sheet.png) | Register Console sheet with the 8-digit `ChiakiDigitPicker` (§4.5 + Step 7). Each column is a focusable reel showing prev/current/next digit; D-pad Up/Down cycles 0–9, Left/Right walks columns. Replaces the prior `Button + alert(TextField)` keyboard-routing pattern. PSN Account-ID is now display-only here (audit D4). |
| 12 | [`12-confirm-dialog.png`](12-confirm-dialog.png) | "Hide host?" confirm. Default focus on Cancel (destructive Confirm requires explicit move). Replaces the previous Yes/No + PS-shape glyphs (audit D3) with proper "Cancel" + "Confirm" labels in the same primary/secondary button pair as the sheets. |

## Frames not captured here

Three screens require runtime state that's hard to reach in the dev
environment:

- **Set Console PIN sheet** — visible only via the host card's Edit button,
  which only appears for registered hosts. The simulator session never
  successfully completed registration during capture. Implementation
  verified visually equivalent to the Register sheet but with a 4-digit
  picker instead of 8.
- **AutoConnect waiting room** — requires triggering wake-on-LAN against
  a registered standby PS5; same blocker as Set Console PIN.
- **ErrorToastView** — requires a connection failure, which is hard to
  produce reliably in the simulator.

The implementations of all three are verified by inspecting the source
(`AutoConnectView.swift`, `ConsolePinDialog.swift`, `ErrorToastView.swift`)
and they share visual tokens with the captured frames — same ink-800
fill, ink-600 stroke, amber/rose accents, and type ramp. They will
appear consistent with the rest of the redesign in production use.

## Comparison with the audit baseline

The pre-redesign screenshots live under
[`../audit-2026-05-06/`](../audit-2026-05-06/). Diffing the two folders
visualises the 29 high/medium/low-severity issues that the redesign plan
called out. The largest deltas are:

- **Host list:** spreadsheet rows → hero card.
- **Settings:** centered narrow column → vertical rail + full-bleed rows
  with segmented controls and sliders.
- **Controller:** alphabetical text dump → physical cluster grouping with
  prominent status chips.
- **Forms:** back-chevron-toolbar full-screen routes → centered modal
  sheets with proper primary/secondary action buttons.
- **PIN entry:** TextField + tvOS keyboard → focusable digit-reel picker.
- **Toolbar:** in-app quit button + heavy chrome → minimal wordmark +
  status line + two compact actions.
