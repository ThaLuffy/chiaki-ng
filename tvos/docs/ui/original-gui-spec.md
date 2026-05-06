# Original chiaki-ng GUI — Pixel-Perfect Spec

> Cataloging every screen, dialog, control, color, and dimension of the desktop QML GUI ([`../../../gui/src/qml/`](../../../gui/src/qml/)) so the tvOS port can reproduce visual + behavioral parity where appropriate. **Source of truth for every claim is a file:line citation into the QML.**
>
> 11,002 lines of QML across 22 files. This doc is the full spec; the implementation plan at [`swift-ui-plan.md`](./swift-ui-plan.md) decides what we keep, drop, or rework for tvOS.

---

## 1. Global theme

**Source:** [`gui/src/qml/qtquickcontrols2.conf`](../../../gui/src/qml/qtquickcontrols2.conf)

| Token | Value | Purpose |
|---|---|---|
| Style | `Material` | Qt's Material theme |
| Theme | `Dark` | dark mode |
| **Accent** | `#00a7ff` | brand sky-blue, the only chromatic color used for buttons / focus highlights / spinners |
| Default font pixel size | `20` | base text size |

**Material palette under "Dark" (Qt's defaults, not overridden):**

| Role | Hex | Usage |
|---|---|---|
| Background | `#303030` (dark gray) | window / pane background |
| Surface | `#424242` | elevated surfaces (toolbars, dialogs) |
| Foreground (primary text) | `#FFFFFF` | most labels |
| Foreground (secondary) | `~#B3FFFFFF` (70% alpha) | placeholders, helper text |
| Error / loss color | `#ef9a9a` | packet-loss + dropped-frame counters in stream HUD |
| Stream-menu surface | `#2b2b2b` | the in-stream menu bar background ([`StreamMenuWindow.qml:84`](../../../gui/src/qml/StreamMenuWindow.qml)) |

**Border radii:**
- `Material.SmallScale` (~4 px) — most flat buttons, settings rows.
- `Material.MediumScale` (~8 px) — modal dialogs.

**Animations:**
- Stack-view replace: opacity 0.01 → 1.0 over **200 ms** ([`Main.qml:264-280`](../../../gui/src/qml/Main.qml)).
- Error toast opacity: 0 → 0.8 with **500 ms** `NumberAnimation` ([`Main.qml:430`](../../../gui/src/qml/Main.qml)).
- Loading-view opacity: **250 ms** ([`StreamView.qml:122`](../../../gui/src/qml/StreamView.qml)).
- Stream-menu slide: **250 ms** vertical translation ([`StreamMenuWindow.qml:55-57`](../../../gui/src/qml/StreamMenuWindow.qml)).
- Logo idle pulse: opacity 0.05 → 0.20 over **1000 ms** with `Easing.OutCubic`, looping ([`MainView.qml:427-435`](../../../gui/src/qml/MainView.qml)).

---

## 2. Custom controls (gui/src/qml/controls/)

The desktop wraps Qt's Material controls with **focus-chain helpers**: every wrapper exposes `firstInFocusChain` / `lastInFocusChain` so up/down at the chain edges are a no-op rather than wrap-around.

### 2.1 `controls/Button.qml`

- Wraps `Button`. When focused, `Material.background = Material.accent` (highlights in `#00a7ff`).
- Up arrow → `nextItemInFocusChain(false)`; Down arrow → `nextItemInFocusChain()`.
- Return → triggers `clicked()` only when `visualFocus` is true.
- On destruction while focused, forwards focus to the next item.

### 2.2 `controls/CheckBox.qml`

- Same focus-chain helpers as Button.
- Return → `toggle() + toggled()`.

### 2.3 `controls/ComboBox.qml`

- `implicitContentWidthPolicy: ComboBox.WidestText` (sizes to widest entry).
- Return → if popup open, accept and close; else open popup.
- Up/Down arrows ignored while popup is visible (so the popup handles its own item navigation).

### 2.4 `controls/RadioButton.qml`

- Same as CheckBox.

### 2.5 `controls/Slider.qml`

- Up/Down navigate between focus chain items (does **not** modify value).
- Value is changed by Left/Right arrow keys (Qt default behavior, no override).

### 2.6 `controls/TextField.qml`

- Starts in `readOnly = true`.
- Return → enters edit mode, calls `Qt.inputMethod.show()` (on-screen keyboard for controller users).
- Escape → exits edit mode, fires `editingFinished()`.
- Up/Down → focus chain navigation (only when read-only).
- MouseArea backs `readOnly` mode → click puts the field in edit mode.

These all imply the same focus-chain pattern we'll need on tvOS via SwiftUI's `@FocusState` chain.

---

## 3. Top-level shell — `Main.qml`

**Source:** [`gui/src/qml/Main.qml`](../../../gui/src/qml/Main.qml) (639 lines)

### 3.1 Structure

```
Item (root)
├─ Pane (anchors.fill: parent, visible only when no video)
├─ StackView (anchors.fill: parent, font.pixelSize: 20)
│  └─ initialItem: MainView
│     [stack push/replace targets:
│      MainView, StreamView, AutoConnectView, PsnView,
│      ManualHostDialog, SettingsDialog, DisplaySettingsDialog,
│      PlaceboSettingsDialog, PlaceboColorMappingDialog,
│      ProfileDialog, ConsolePinDialog, SteamShortcutDialog,
│      PSNTokenDialog, RegistDialog, ControllerMappingDialog]
├─ Rectangle placeboSettingsRect    1200 × 650, anchored top, opacity 0–0.8
├─ Rectangle displaySettingsRect    1200 × 500, anchored top
├─ Rectangle colorMappingSettingsRect 1200 × 600, anchored top
├─ Window separateDisplaySettingsWindow      [framelessHint, transient]
├─ Window separatePlaceboSettingsWindow
├─ Window separateColorMappingSettingsWindow
├─ Rectangle (error toast)          bottom-center, 30px bottomMargin
│   ├─ Label (errorTitleLabel)      bold, 24px
│   └─ Label (errorTextLabel)       20px
│   bg: Material.accent, radius 8, opacity 0 → 0.8
├─ Dialog infoDialog                centered modal, MediumScale rounded
│   └─ Label + OK button (50px leftPadding, accent bg) with cross icon
├─ ConfirmDialog                    (separate file)
└─ RemindDialog                     (separate file)
```

### 3.2 Global functions (the navigation API)

| Function | Action |
|---|---|
| `showMainView()` | pop or replace stack to MainView |
| `showStreamView()` | replace stack with StreamView |
| `showPsnView()` | replace stack with PsnView (immediate, no animation) |
| `showManualHostDialog()` | push ManualHostDialog |
| `showRegistDialog(host, ps5)` | push RegistDialog with props |
| `showSettingsDialog()` | push SettingsDialog |
| `showConfirmDialog(title, text, cb, rejectCb=null)` | open in-place modal |
| `showInfoDialog(title, text)` | open in-place modal |
| `showRemindDialog(title, text, remotePlay, cb)` | open RemindDialog (3 buttons) |
| `showConsolePinDialog(consoleIndex)` | push ConsolePinDialog |
| `grabInput(item)` / `releaseInput()` | take/restore controller input ownership |
| `controllerButton(name)` | returns `image://svg/button-(ps|deck)#name` for prompts |

### 3.3 Behavior on Chiaki signals

| Signal | Reaction ([`Main.qml:522-563`](../../../gui/src/qml/Main.qml)) |
|---|---|
| `onSessionChanged` (truthy) | switch to StreamView |
| `onShowPsnView` | switch to PsnView |
| `onPsnCredsExpired` | clear PSN tokens, push PSNTokenDialog |
| `onError(title, text)` | populate + start `errorHideTimer` (2 s, ramped opacity) |
| `onRegistDialogRequested(host, ps5, duid)` | push RegistDialog or, if a `duid` exists, ask via ConfirmDialog whether to use automatic registration |
| `onWakeupStartInitiated` | replace with AutoConnectView |

---

## 4. Main host list — `MainView.qml`

**Source:** [`gui/src/qml/MainView.qml`](../../../gui/src/qml/MainView.qml) (437 lines)

### 4.1 Layout

```
Pane (padding: 0)
├─ ToolBar (top-anchored, height 80, leftMargin 10 / rightMargin 10)
│   └─ RowLayout
│       ├─ Button "×"            [100w, flat, 60px font, NoFocus, Qt.quit()]
│       ├─ Spacer (FillWidth)
│       ├─ Button "Create Steam Shortcut" [350w, flat, NoFocus, L3 icon right]    *Steam-only, hidden on tvOS*
│       ├─ Button "Refresh PSN Hosts"     [400w, flat, R1 icon, NoFocus]          *PSN-only, hidden on tvOS*
│       ├─ Button (placeholder)           [400w, hidden when PSN auth absent]
│       ├─ Button "Add Manual Host"       [300w, flat, R3 icon left, NoFocus]
│       └─ Button (settings gear)         [100w, settings-20px.svg @ 50×50, NoFocus]
│
├─ ListView hostsView
│   anchors: top=ToolBar.bottom, l/r=parent, bottom=parent.bottom-50
│   keyNavigationWraps: true · clip: true · model: Chiaki.hosts
│   delegate: ItemDelegate
│       width = parent.width
│       height = 180  (when visible; 0 otherwise)
│       highlighted: ListView.isCurrentItem
│       RowLayout (fill, leftMargin 30, rightMargin 10, top/bottom 10, spacing 50)
│           ├─ Image (PS console)         150 × fill height
│           │   src: image://svg/console-ps{4|5}#light_{on|standby}
│           ├─ Label  (left-aligned)
│           │   line 1: name
│           │   line 2: "Address: <ip or 'hidden'>"
│           │   line 3: "ID: <mac> (registered/unregistered)"
│           │   line 4: discovery/manual/automatic/PSN tag
│           ├─ Label  (left-aligned)
│           │   "State: ready|standby"
│           │   "App: <name>"
│           │   "Title ID: <id>"
│           ├─ Spacer (FillWidth)
│           └─ ColumnLayout (fillHeight, spacing 0)
│               ├─ Button "Delete"/"Hide"       [flat, 20pad, focusPolicy:NoFocus,
│               │                                 leftPadding 50 when highlighted,
│               │                                 ▢ box icon visible when highlighted]
│               ├─ Button "Wake Up"             [pyramid icon, when registered + offline]
│               └─ Button "Update Console Pin"  [L1 icon, when registered]
│
├─ RoundButton (discovery toggle)
│   anchors: bottom-left, margin 20
│   icon: discover-(off-)24px.svg @ 50 × 50, padding 20
│   bg: Material.accent
│   checkable, bound to Chiaki.discoveryEnabled
│
├─ Label (version)               bottom-right, margin 20
└─ Image  (chiaking-logo-white.svg)
    centered, sized to min(W,H)/2
    opacity 0.05 → 0.20 looping pulse, 1 s, OutCubic
```

### 4.2 Delegate height + spacing

Each tile = **180 px high**, **30 px left** + **10 px right** + **10 px top/bottom** internal margins, **50 px between sub-items**. Console icon is **150 px wide**. Right-side action buttons stack vertically with **0 spacing**, each ~`text + 20 pad` tall.

### 4.3 Key bindings on the host list

| Key | Action |
|---|---|
| **Up / Down** | move list selection (skipping invisible delegates) |
| **Return** | `connectToHost()` on current item |
| **Yes (Cross/A)** | `wakeUpHost()` on current item |
| **No (Circle/B)** | `deleteHost()` (with confirm) — only if manual or unregistered |
| **Menu** | open SettingsDialog |
| **PageUp** | open ConsolePinDialog for current item |
| **PageDown** | refresh PSN token (if available) |
| **F1** | open SteamShortcutDialog |
| **F2** | open ManualHostDialog |
| **Escape** | confirm Quit |

### 4.4 Buttons appearing only when delegate is highlighted

The action buttons (Delete/Hide, Wake Up, Update Pin) gain a `leftPadding: 50` and reveal an inline 28×28 controller-button SVG (Box, Triangle, L1) on the left edge — only when the delegate is the focused/highlighted one ([`MainView.qml:316-388`](../../../gui/src/qml/MainView.qml)). Resting state hides the icons, no padding.

---

## 5. DialogView (toolbar shell for push-style dialogs)

**Source:** [`gui/src/qml/DialogView.qml`](../../../gui/src/qml/DialogView.qml) (131 lines)

The base for ManualHostDialog, ConsolePinDialog, RegistDialog, ProfileDialog, SettingsDialog, DisplaySettingsDialog, etc.

### 5.1 Structure

```
Item (dialog root)
├─ ToolBar (top-anchored, height 80, leftMargin 10 / rightMargin 10)
│   ├─ Button "❮"           [100w, flat, NoFocus, calls reject() + close()]
│   ├─ Spacer (FillWidth)
│   └─ Button "OK/Add/..."   [flat, padding 30, font 25,
│                              NoFocus, options.svg @ 50×50,
│                              text bound to dialog.buttonText,
│                              enabled bound to dialog.buttonEnabled,
│                              visible bound to dialog.buttonVisible]
│   ├─ Label titleLabel       centered, bold, 26px
│   └─ Label headerLabel      anchored to title.right, bold, 14px (used by SettingsDialog
│                              for the "* Defaults in () to right of value" subtitle)
└─ Item contentItem          fills below toolbar; concrete dialog populates this
```

### 5.2 Key bindings

| Key | Action |
|---|---|
| **Escape** | close() (rejects + pops stack) |
| **Menu** | trigger OK button if enabled |
| `StackView.onActivated` | restore focus to last-active control or next-in-chain |

---

## 6. ManualHostDialog

**Source:** [`gui/src/qml/ManualHostDialog.qml`](../../../gui/src/qml/ManualHostDialog.qml) (78 lines)

```
DialogView { title: "Add Manual Console", buttonText: "Add" }
└─ GridLayout (columns: 2, rowSpacing 20, columnSpacing 20, topMargin 20)
   ├─ Label "Host:"                    [right-aligned]
   ├─ TextField hostField               [400w, firstInFocusChain]
   ├─ Label "Registered Consoles:"      [right-aligned]
   └─ ComboBox consoleCombo             [400w, lastInFocusChain]
       model: list of registered hosts + "Register on first Connection"
```

`buttonEnabled = hostField.text.trim() && consoleCombo.currentIndex != "Select an Option"`.
`onAccepted = Chiaki.addManualHost(consoleIndex, host); close()`.

---

## 7. ConsolePinDialog

**Source:** [`gui/src/qml/ConsolePinDialog.qml`](../../../gui/src/qml/ConsolePinDialog.qml) (42 lines)

```
DialogView { title: "Set console pin", buttonText: "Set" }
└─ GridLayout (columns: 2, rowSpacing 10, columnSpacing 20, topMargin 20)
   ├─ Label "Remote Play PIN (4 digits):"
   └─ TextField pin     [400w, validator: /[0-9]{4}/]
```

Validator regex `[0-9]{4}` enforces 4 digits exactly.

---

## 8. RegistDialog

**Source:** [`gui/src/qml/RegistDialog.qml`](../../../gui/src/qml/RegistDialog.qml) (264 lines)

```
DialogView { title: "Register Console", buttonText: "Register" }
└─ GridLayout (columns: 2, rowSpacing 10, columnSpacing 20, topMargin 20)
   ├─ Label "Host:"                  → TextField hostField              [400w, firstInFocusChain]
   ├─ Label "PSN Online-ID:"          → TextField onlineId               [400w, visible if PS4<7]
   ├─ Label "PSN Account-ID:"         → TextField accountId              [adjusted width to fit
   │                                                                       inline buttons]
   │   inline:                          C.Button loginButton   "PSN Login"      [topPad 18, botPad 18, hidden if accountId already set]
   │                                    C.Button lookupButton  "Public Lookup"  [same, opens PSNLoginDialog]
   ├─ Label "Remote Play PIN:"        → TextField pin                    [400w, validator /[0-9]{8}/]
   ├─ Label "Console Pin [Optional]"  → TextField cpin                   [400w, validator empty or /[0-9]{4}/]
   ├─ Label "Console:"                → ColumnLayout
   │                                       RadioButton "PS4 Firmware < 7.0"
   │                                       RadioButton "PS4 Firmware >= 7.0, < 8.0"
   │                                       RadioButton "PS4 Firmware >= 8.0"           [checked when !ps5]
   │                                       RadioButton "PS5"                            [checked when ps5, lastInFocusChain]
   └─ embedded log Dialog "Register Console"
       Flickable (600 × 400)
       Label logArea (wrap, scroll on Up/Down)
       initially Cancel button → on completion swaps to Close button
```

`buttonEnabled` requires: host trimmed + valid pin + valid cpin + (online id if PS4<7 *or* account id otherwise) all populated.

The log dialog opens after pressing "Register" and shows live progress of the registration.

---

## 9. ConfirmDialog

**Source:** [`gui/src/qml/ConfirmDialog.qml`](../../../gui/src/qml/ConfirmDialog.qml) (104 lines)

Centered modal `Dialog`, `MediumScale` rounded.

```
Dialog (Overlay.overlay parent, modal)
├─ header (centered, bold, no background)
└─ ColumnLayout (spacing 20)
    ├─ Label  (text passed in, with Esc=reject + Return=accept)
    └─ RowLayout (centered, spacing 20)
        ├─ Button "Yes"  [flat, leftPadding 50, accent bg, cross icon left]
        └─ Button "No"   [flat, leftPadding 50, accent bg, moon icon left]
```

`onAccepted` calls user-supplied `callback`; `onRejected` calls optional `rejectCallback`.

---

## 10. RemindDialog

**Source:** [`gui/src/qml/RemindDialog.qml`](../../../gui/src/qml/RemindDialog.qml) (135 lines)

Same pattern as ConfirmDialog plus a third button:

```
RowLayout
├─ Button "Yes"           [cross icon]
├─ Button "No"            [moon (circle) icon]
└─ Button "Remind Me Later" [pyramid (triangle) icon]
```

Selecting "No" sets `Chiaki.settings.remotePlayAsk = false` (or `addSteamShortcutAsk = false`) so the user isn't pestered again.

---

## 11. AutoConnectView

**Source:** [`gui/src/qml/AutoConnectView.qml`](../../../gui/src/qml/AutoConnectView.qml) (104 lines)

Full-bleed black `Rectangle` shown while waking a console / waiting for it to come online.

```
Rectangle (color: black, fills parent)
├─ Label  infoLabel                centered, "Waiting for console..."
│         opacity 0 → 1 over 250 ms once allowClose flag flips at t=1500ms
├─ BusyIndicator spinner             70 × 70, anchored to bottom-half center
└─ Label closeMessageLabel           below spinner (margin 30)
          "Press <Circle/B> to cancel connection" (or "escape or right-click")
```

Pressing Escape, right-click, or Cancel cancels the connection (with a 2-second `failTimer` confirming + bouncing back to MainView).

---

## 12. ProfileDialog

**Source:** [`gui/src/qml/ProfileDialog.qml`](../../../gui/src/qml/ProfileDialog.qml) (87 lines)

Profile manager (multi-user "profiles" within a single chiaki-ng install).

```
DialogView { dynamic title }
└─ GridLayout
   ├─ Label "User Profile:"          → ComboBox profileComboBox
   ├─ Label "New Profile Name"       → TextField profileName        [visible only when "create new profile"]
   └─ Label "Delete selected profile"→ CheckBox deleteBox            [visible if non-default & non-current]
```

The button text dynamically becomes "Create Profile" / "Delete Profile" / "Switch Profile" based on the combo state.

---

## 13. SettingsDialog (the big one)

**Source:** [`gui/src/qml/SettingsDialog.qml`](../../../gui/src/qml/SettingsDialog.qml) (3281 lines)

```
DialogView { title: "Settings", header: "* Defaults in () to right of value or marked with (Default)", buttonVisible: false }
└─ Item
   ├─ TabBar bar  [top, focusPolicy NoFocus on each tab; PageUp/PageDown changes tab]
   │   Tabs: General · Video · Stream · Audio/Wifi · Consoles · Keys · Controllers · Remote · [Profile (modal subdialog)]
   │   Each tab shows L1 / R1 icons on the inactive edges hinting controller bumper navigation
   └─ Flickables (one per tab) hosting the settings rows
```

### 13.1 Tab content (all rows = `[Label aligned-right] | [Control 400w (or as noted)]`)

#### Tab 0 — **General**

| Label | Control |
|---|---|
| Action On Disconnect: | ComboBox |
| Action On Suspend: | ComboBox |
| Steam Deck Haptics: | CheckBox **(Linux/Steam Deck only)** |
| Steam Deck Vertical: | CheckBox **(SD only)** |
| Audio/Video: | ComboBox (audio+video / audio-only / video-only / disabled) |
| Log Directory: | Label + open/clear buttons |
| Streamer Mode (privacy): | CheckBox |
| Verbose Logs: | CheckBox |
| Stream Menu Combo: | ComboBox (button combo to open in-stream menu) |
| Disconnect Action: | ComboBox |
| (more privacy / log toggles) | mixed |

Plus a top-row "Disconnect Now" action button (`disconnectAction`).

#### Tab 1 — **Video**

| Label | Control |
|---|---|
| Hardware Decoder: | ComboBox (videotoolbox / dxva2 / vaapi / vulkan…) |
| Window Type: | ComboBox (Normal / Stretch / Zoom) |
| Toggle Fullscreen on Double-click: | CheckBox |
| Vertical Sync: | CheckBox |
| Render Preset: | ComboBox (Default / High Quality / HQ+Spatial / HQ+Adv Spatial / Custom) |
| Frame Mixer: | ComboBox |
| Bitrate slider (when Custom): | Slider |
| Renderer Backend: | ComboBox (Vulkan / OpenGL) |
| Direct Stream: | CheckBox + label |
| Throttle / Pace timing: | Slider |

#### Tab 2 — **Stream**

| Label | Control |
|---|---|
| Settings for: | ComboBox (Local PS5 / Local PS4 / Remote PS5 / Remote PS4) |
| Resolution: | ComboBox (360 / 540 / 720 / 1080p / Auto) |
| FPS: | ComboBox (30 / 60) |
| Bitrate: | Slider (kbps) |
| Audio bitrate: | Slider |
| Codec: | ComboBox (H264 / H265 (Default) / H265 HDR) |

The "Settings for" combo lets users tune PS4 vs PS5 + Local vs Remote profiles independently.

#### Tab 3 — **Audio/Wifi**

| Label | Control |
|---|---|
| Output Device: | ComboBox |
| Input Device (mic): | ComboBox |
| Audio Buffer Size: | Slider |
| Audio Volume: | Slider |
| Start Mic Unmuted: | CheckBox |
| Speech Processing (Speex): | CheckBox |
| Noise To Suppress: | Slider |
| Echo To Suppress: | Slider |
| Weak Wifi Notification: | Slider |
| Packet Loss Reported Max: | Slider |
| WiFi Networks (display only): | list |
| Show "Stream Stats" overlay: | CheckBox |

#### Tab 4 — **Consoles**

Two sub-sections:

- **Registered consoles**: list with delete button.
- **Hidden consoles**: list with unhide button.
- "Register New" button at top → opens RegistDialog with the selected target.

#### Tab 5 — **Keys**

Reset all keys + per-action key remap rows (keyboard key mapping for every PS button).

#### Tab 6 — **Controllers**

Controller mapping change button → opens ControllerMappingDialog. Per-controller GUID + custom mapping override.

#### Tab 7 — **Remote**

PSN OAuth login + token state + hole-punch options:
- "Open PSN Login" button
- "Reset PSN Tokens" button
- Hole punch guessing CheckBox
- Port guess count Slider
- Port guess socket Slider

#### Tab 8 — **Profile** (visually a tab, mechanically a separate dialog)

Push to ProfileDialog.

### 13.2 Tab navigation

- **PageUp / PageDown** (or **L1 / R1** on a controller) cycle tabs ([`SettingsDialog.qml:138-144`](../../../gui/src/qml/SettingsDialog.qml)).
- **Up / Down** scroll the active Flickable when not at edges; otherwise propagate to the focus chain.
- Tab icons (L1/R1 SVGs) appear inset to the active tab's neighbors as visual hints.

---

## 14. DisplaySettingsDialog

**Source:** [`gui/src/qml/DisplaySettingsDialog.qml`](../../../gui/src/qml/DisplaySettingsDialog.qml) (193 lines)

The mid-stream display-tuning popover (1200 × 500). Subset of Video tab applied while the stream is live (window type, render preset, bitrate, throttle, vsync, etc.).

---

## 15. PlaceboSettingsDialog + PlaceboColorMappingDialog

**Source:**
- [`gui/src/qml/PlaceboSettingsDialog.qml`](../../../gui/src/qml/PlaceboSettingsDialog.qml) (1192 lines)
- [`gui/src/qml/PlaceboColorMappingDialog.qml`](../../../gui/src/qml/PlaceboColorMappingDialog.qml) (940 lines)

Custom libplacebo renderer tuning: FSR / FSRCNNX upscalers, deband settings, peak detection, color mapping curves, etc. Hugely featureful, ~2,100 LOC of QML in the two dialogs combined.

---

## 16. PSNLoginDialog + PSNTokenDialog

**Source:** [`gui/src/qml/PSNLoginDialog.qml`](../../../gui/src/qml/PSNLoginDialog.qml) (455 lines), [`gui/src/qml/PSNTokenDialog.qml`](../../../gui/src/qml/PSNTokenDialog.qml) (427 lines).

OAuth flow via embedded `WebEngineView` from QtWebEngine. Login window, token capture, refresh, account-id extraction.

---

## 17. PsnView

**Source:** [`gui/src/qml/PsnView.qml`](../../../gui/src/qml/PsnView.qml) (246 lines)

Specialized host list for PSN-discovered consoles (over-internet sessions). Visual style identical to MainView's list with a different filter on `Chiaki.hosts`.

---

## 18. SteamShortcutDialog

**Source:** [`gui/src/qml/SteamShortcutDialog.qml`](../../../gui/src/qml/SteamShortcutDialog.qml) (194 lines)

Linux/macOS/Windows-specific: drops a non-Steam game into Steam's library with the chiaki-ng artwork + controller layout.

---

## 19. ControllerMappingDialog

**Source:** [`gui/src/qml/ControllerMappingDialog.qml`](../../../gui/src/qml/ControllerMappingDialog.qml) (350 lines)

Visual gamepad mapper: shows a controller diagram, lets the user click a button on screen → press the corresponding physical button → save mapping (per-GUID, persisted to settings).

---

## 20. StreamView

**Source:** [`gui/src/qml/StreamView.qml`](../../../gui/src/qml/StreamView.qml) (1268 lines)

The active streaming canvas. Most of the area is the libplacebo-rendered video (handled in C++ at the QWindow level, not QML). The QML overlays:

```
Item (view)
├─ Rectangle loadingView  (full, black, opacity 1.0 while sessionLoading)
│   ├─ BusyIndicator spinner (70×70, vertical-center'd to bottom half)
│   ├─ Label "Press <combo> to open stream menu" + dpad-touch hint
│   ├─ Label audioVideoDisabledTitleLabel (when AV disabled in settings)
│   ├─ Label audioVideoDisabledTextLabel
│   ├─ Label errorTitleLabel  (24px, when sessionError)
│   └─ Label errorTextLabel   (20px)
├─ StreamStats overlay      (small floating panel: bitrate, packet loss, dropped frames)
│   anchored top-right; visible when settings.showStreamStats && session.connected
└─ StreamMenuWindow        (sliding bottom bar; described separately)
```

`fadeIn 250ms`, `keepVideo` flag flips on `StackView.onActivating` so the Vulkan swapchain isn't torn down when transitioning.

---

## 21. StreamMenuWindow (the in-stream HUD)

**Source:** [`gui/src/qml/StreamMenuWindow.qml`](../../../gui/src/qml/StreamMenuWindow.qml) (435 lines)

A separate `Window` (Tool / FramelessWindowHint / NonModal) that slides up from the bottom (`y` animated, 250 ms duration). Only opens on demand (user-configured controller combo, or Ctrl+O).

```
FocusScope (fills window)
├─ Rectangle  background  #2b2b2b
├─ RowLayout  bottom-anchored, leftMargin 30, bottomMargin 40, spacing 0
│   ├─ ToolButton closeButton  "×"            50px font, padding 10
│   ├─ ToolSeparator
│   ├─ Slider volumeSlider      vertical, 0–128 mapped to 0–100%, height 100, label below
│   ├─ ToolSeparator
│   ├─ ToolButton muteButton    "Mic"           checkable
│   ├─ ToolButton zoomButton    "Zoom"          checkable
│   ├─ Slider zoomFactor        vertical -1 to 4, height 100; visible only when Zoom on
│   ├─ ToolSeparator
│   ├─ ToolButton stretchButton "Stretch"
│   ├─ ToolButton defaultButton "Default"        videoPreset radio
│   ├─ ToolSeparator
│   ├─ ToolButton highQualityButton                "High Quality"
│   ├─ ToolButton highQualitySpatialButton        "HQ + Spatial"
│   ├─ ToolButton highQualityAdvancedSpatialButton "HQ + Adv Spatial"
│   ├─ ToolSeparator
│   ├─ ToolButton customButton                    "Custom"
│   ├─ ToolButton displaySettingsButton           "Display"  (gear icon)
│   └─ ToolButton placeboSettingsButton           "Placebo"  (gear, visible if Custom preset)
└─ Right side
    ├─ Label "Mbps"            18px, with bitrate value to its left in 28px bold accent
    └─ Label consoleNameLabel   "Connected to <host>" / "Connecting to <host>"
        Below it:
            "<%>%" packet loss   color #ef9a9a, 18px bold
            "<n> dropped frames" color #ef9a9a, 18px bold
```

Slide animation: `Behavior on y { NumberAnimation { duration: 250 } }` → window slides from below the visible area to its docked position when toggled.

---

## 22. Iconography

The desktop ships a fairly large icon set in [`gui/res/icons/`](../../../gui/res/icons/) and provides controller glyph SVGs via the `image://svg/button-(ps|deck)#name` provider:

| Glyph name | Meaning |
|---|---|
| `cross` | PS Cross / Xbox A |
| `moon` | PS Circle / Xbox B |
| `box` | PS Square / Xbox X |
| `pyramid` | PS Triangle / Xbox Y |
| `l1` / `l2` / `l3` | PS L1 / L2 / L3 |
| `r1` / `r2` / `r3` | PS R1 / R2 / R3 |
| `options` | PS Options |
| `settings-20px` | gear |
| `discover-24px`, `discover-off-24px` | discovery toggle |
| `chiaking-logo-white.svg` | the watermark on MainView |

For the tvOS port we have access to all of these via the chiaki-ng resource files; see [`swift-ui-plan.md`](./swift-ui-plan.md) for which ones we actually bring across.

---

## 23. Summary of distinctive visual / interaction patterns

This list is the "feel" we want to keep on tvOS:

1. **Material Dark + `#00a7ff` accent** on focused items.
2. **Focus-chain navigation** — every control declares `firstInFocusChain` / `lastInFocusChain` so up/down at the edge of a chain is a no-op (vs. wrap-around).
3. **Inline controller-button glyphs** appearing only when a delegate is highlighted (Box on Delete, Triangle on Wake Up, L1 on Update Pin, etc.).
4. **Logo idle pulse** (1 s, ~5% → 20% opacity) as a subtle "alive" cue on the host list.
5. **Toolbar height = 80 px** everywhere it appears (DialogView, MainView).
6. **Dialog content area = 400 px** wide for fields, **20 px row spacing**, **20 px column spacing**, **20 px top margin**.
7. **180 px tile height** for the host list, **150 px** console icon, **30 px** internal left margin, **50 px** between sub-elements.
8. **Stream menu** = bottom-anchored slide-up bar with **250 ms** vertical animation.
9. **Stream HUD stats** = right-aligned, "Mbps" with **28 px bold accent value**, error counters in `#ef9a9a` 18 px bold.
10. **Toast errors** = bottom-center pill (radius 8, accent bg, opacity 0.8 with 500 ms fade) auto-hiding after 2 s.

---

This catalog covers what we *might* port. The next document, [`swift-ui-plan.md`](./swift-ui-plan.md), is where we decide what we *will* port for the tvOS LAN-only personal-use scope.
