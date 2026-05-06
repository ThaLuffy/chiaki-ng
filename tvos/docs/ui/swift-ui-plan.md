# Swift UI Implementation Plan

> Plan for replacing the desktop chiaki-ng QML UI ([`original-gui-spec.md`](./original-gui-spec.md)) with native SwiftUI on tvOS. Scope-driven by [`../decisions.md#scope--lan-only-no-psn-oauth-no-app-store`](../decisions.md#scope--lan-only-no-psn-oauth-no-app-store) and [`../decisions.md#prefill-psn-account-id-no-oauth`](../decisions.md#prefill-psn-account-id-no-oauth).
>
> Hard rule: every UI piece in this plan is justified against the spec doc, has a Phase tag (Phase 0 / 1 / 2), and either matches the desktop visually or has a documented reason to deviate.

---

## 1. Scope cuts (what does NOT come to tvOS)

These are intentionally dropped for the personal-use, LAN-only port. Do not implement.

| Desktop screen | Why dropped |
|---|---|
| **PSNLoginDialog**, **PSNTokenDialog** | No PSN OAuth (account ID is prefilled). |
| **PsnView** | LAN only — no remote-over-internet host list. |
| **SteamShortcutDialog** | Steam-specific, irrelevant on tvOS. |
| **PlaceboSettingsDialog** + **PlaceboColorMappingDialog** | We use Metal native, not libplacebo. ~2,100 LOC of QML do not need a Swift counterpart. |
| **DisplaySettingsDialog** | The desktop's mid-stream display tuner is a libplacebo subset; the tvOS Stream HUD will only expose Volume + Mute + Disconnect. |
| **ProfileDialog** | Single-user personal device — no profile system. |
| **ControllerMappingDialog** | DualSense is the only controller; tvOS surfaces it natively. v2 might add a lightweight remap. |
| **Settings → Keys tab** | tvOS streaming view is controller-only; no keyboard remap. |
| **Settings → Controllers tab** | See above. |
| **Settings → Remote tab** | PSN auth — out of scope. |
| **Settings → Profile tab** | See above. |
| **Settings → General → Steam Deck options** | Not Steam Deck. |
| **MainView toolbar buttons**: "Create Steam Shortcut", "Refresh PSN Hosts" | Out of scope. |
| **MainView "PageDown = Refresh PSN"**, **F1 = Steam Shortcut** | Out of scope. |
| **Manual host "Streamer Mode" privacy hide** | LAN only personal device — no streaming-on-camera privacy concern. (Include the toggle if cheap.) |

---

## 2. What we keep

Phase tags: **P0** = ship now (matching scaffolding); **P1** = ship with the bridge / streaming MVP; **P2** = polish.

| Desktop original | tvOS equivalent | Phase |
|---|---|---|
| Material Dark theme + `#00a7ff` accent | `Theme.swift` constants + global modifier | **P0** |
| Stack-view replace transition (200 ms opacity) | SwiftUI `.transition(.opacity)` + `.animation(.easeInOut(duration: 0.2))` | **P0** |
| Main.qml — global navigation shell | `ChiakiNavigation` enum in `AppState` + switch in `ContentView` | **P0** |
| MainView.qml — host list | `HostListView` | **P0** (mocked data) → **P1** (live discovery) |
| DialogView.qml — push dialog with toolbar | `ChiakiDialogChrome` SwiftUI container | **P0** |
| ManualHostDialog.qml | `ManualHostDialog` | **P0** (UI) → **P1** (calls `Chiaki.addManualHost`) |
| ConsolePinDialog.qml | `ConsolePinDialog` | **P0** UI → **P1** (calls `Chiaki.setConsolePin`) |
| RegistDialog.qml | `RegistDialog` (slimmed: no PS4<7 / Online-ID, no PSN Login button — only PS5 with Account ID + PIN) | **P0** UI → **P1** wiring |
| ConfirmDialog.qml | `ConfirmDialog` (alert-style modal) | **P0** |
| RemindDialog.qml | `RemindDialog` (3-button modal) | **P0** (only as fallback shape; the only "remind" prompts in scope are not PSN-related) |
| AutoConnectView.qml | `AutoConnectView` | **P1** (post-WoL wait) |
| SettingsDialog.qml — General/Video/Stream/Audio/Consoles tabs only | `SettingsView` with `TabView`, four tabs: General, Video/Stream (combined), Audio, Consoles | **P0** UI → **P1** values |
| SettingsDialog → Add Account ID field | Net new for tvOS; lives in **General** tab (no OAuth) | **P0** |
| StreamView.qml | `StreamView` placeholder (full-bleed black) | **P0** UI → **P1** Metal video |
| StreamMenuWindow.qml | `StreamMenuOverlay` (bottom slide-up) — slimmed: Disconnect, Volume, Stretch, Default Preset | **P0** UI → **P1** wiring |
| Error toast | `ErrorToastView` modifier, 2-second auto-dismiss | **P0** |
| Logo pulse animation | `LogoPulse` 1 s opacity loop | **P0** |
| Loading spinner | `ChiakiSpinner` based on SwiftUI `ProgressView` | **P0** |
| Bottom-left discovery toggle | Round button bound to `discoveryEnabled` | **P0** UI → **P1** wiring |
| Version label bottom-right | `Bundle.main` version string | **P0** |

---

## 3. tvOS-specific deviations (with justification)

### 3.1 No `Window` instances; one root scene

QML's `Main.qml` uses three separate `Window`s for "separate stream settings" (Vulkan path) and the in-stream menu, plus `transientParent` shenanigans. **tvOS apps are single-scene**. We render the stream menu as a SwiftUI overlay on `ZStack` instead of a separate window. No functional loss.

### 3.2 Focus engine — SwiftUI `@FocusState`, not focus chain

Qt's `firstInFocusChain` / `lastInFocusChain` translate poorly to SwiftUI. tvOS already has a focus engine that handles directional navigation. We use:

- `@FocusState` enums for screens with multiple focusable controls.
- `.focusable()` and `.focusSection()` to define groups.
- `.prefersDefaultFocus(_:in:)` for initial-focus hints.

The desktop's "no wrap-around at chain edges" behavior **becomes the tvOS default** — focus simply doesn't move when you press past the edge of a section. Visually identical UX.

### 3.3 No on-screen keyboard hand-rolling

Qt's `controls/TextField.qml` calls `Qt.inputMethod.show()`. SwiftUI's `TextField` on tvOS automatically pops the system keyboard on focus + activation. No equivalent code needed.

### 3.4 No long-press / right-click mouse paths

The desktop has `MouseArea` enabling click-to-cancel on `AutoConnectView` and double-click-to-fullscreen toggle. tvOS doesn't have a mouse — replace with the controller B-button (`onExitCommand` in SwiftUI / `GCEventViewController` for the streaming view).

### 3.5 SVG controller glyphs

The desktop generates `image://svg/button-(ps|deck)#name` via a Qt image provider that picks PS or Steam Deck artwork at runtime. On tvOS:

- Reuse the original PNG/SVG glyphs from [`../../../gui/res/icons/`](../../../gui/res/icons/) by copying into `ChiakiTV/Assets.xcassets`. **P1**.
- For **P0**, use SF Symbols stand-ins (`circle.fill`, `xmark`, `triangle.fill`, `square.fill`) so the scaffold is shippable without copying assets.

### 3.6 Settings tab merging

The desktop has 9 tabs. After scope cuts we have 4. tvOS `TabView` with the `.page` style (or the new `.tabViewStyle(.sidebarAdaptable)` on tvOS 18+) handles this naturally. We **do not** ship the desktop's L1/R1 inset tab-icon hint — `TabView`'s native tvOS focus already shows tab bumper hints.

### 3.7 No `WebEngineView` ever

QtWebEngine is the only thing that uses Chromium. None of our screens need it.

### 3.8 Frame-mixer / placebo settings → missing from tvOS

These are libplacebo-specific. Since we're on Metal, the equivalent settings simply don't exist. The "Render Preset" combo in the desktop's Stream HUD becomes 2 options in tvOS: "Default" and "High Quality" (= bilinear vs. Lanczos via MetalPerformanceShaders).

---

## 4. Concrete file plan

```
ChiakiTV/
├── App/
│   ├── ChiakiTVApp.swift           (entry point — already exists, P0 keep)
│   └── AppState.swift              (extended in P0 to include navigation enum + theme tokens)
├── Theme/
│   └── Theme.swift                 (NEW — Material Dark palette + spacing constants)
├── Models/
│   ├── Host.swift                  (extend: ps5: Bool, registered: Bool, manual: Bool, app, titleId)
│   ├── RegisteredHost.swift        (NEW — Codable with regist_key/rp_key/mac/nickname)
│   └── AppSettings.swift           (NEW — Codable settings model)
├── Views/
│   ├── ContentView.swift           (REWRITE in P0 to match Main.qml structure)
│   ├── HostListView.swift          (REWRITE — NEW for P0, replaces existing stub)
│   ├── RegistrationView.swift      (REWRITE — RegistDialog-shaped)
│   ├── StreamView.swift            (REWRITE — full-bleed black + StreamMenuOverlay)
│   ├── SettingsView.swift          (REWRITE — TabView)
│   ├── AutoConnectView.swift       (NEW — wake-on-LAN waiting view, P1 wired)
│   └── Components/
│       ├── ChiakiDialogChrome.swift   (NEW — DialogView.qml shell)
│       ├── ChiakiToolbar.swift        (NEW — 80px top toolbar with back/forward buttons)
│       ├── ChiakiButton.swift         (NEW — flat, focused-accent button matching controls/Button.qml)
│       ├── HostTile.swift             (NEW — 180px host list delegate)
│       ├── ConfirmDialog.swift        (NEW — modal Yes/No)
│       ├── RemindDialog.swift         (NEW — modal Yes/No/Later)
│       ├── ManualHostDialog.swift     (NEW)
│       ├── ConsolePinDialog.swift     (NEW)
│       ├── ErrorToastView.swift       (NEW — 2-s auto-dismiss bottom-center pill)
│       ├── LogoPulse.swift            (NEW — opacity loop watermark)
│       ├── StreamMenuOverlay.swift    (NEW — bottom slide-up HUD)
│       └── ChiakiSpinner.swift        (NEW — wraps ProgressView with our 70×70 sizing)
└── Utilities/
    └── ChiakiLogger.swift          (already exists)
```

`Tests/ChiakiTVTests/` gets new model-roundtrip tests in P0 (Codable for `Host`, `RegisteredHost`, `AppSettings`).

---

## 5. Color + spacing tokens (Theme.swift)

**Verified against the spec.** Every value below maps directly to a desktop value cited in [`original-gui-spec.md`](./original-gui-spec.md).

```swift
enum Theme {
    // MARK: Palette (Material Dark)
    static let accent = Color(red: 0.0,  green: 0.655, blue: 1.0)   // #00a7ff
    static let background  = Color(red: 0.188, green: 0.188, blue: 0.188)  // #303030
    static let surface     = Color(red: 0.259, green: 0.259, blue: 0.259)  // #424242
    static let streamMenuSurface = Color(red: 0.169, green: 0.169, blue: 0.169) // #2b2b2b
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.7)
    static let errorRed = Color(red: 0.937, green: 0.604, blue: 0.604) // #ef9a9a
    
    // MARK: Spacing (px values mapped 1:1 from desktop)
    static let toolbarHeight: CGFloat = 80
    static let dialogContentTopMargin: CGFloat = 20
    static let dialogColumnSpacing: CGFloat = 20
    static let dialogRowSpacing: CGFloat = 20
    static let dialogFieldWidth: CGFloat = 400
    static let hostTileHeight: CGFloat = 180
    static let hostTileLeftMargin: CGFloat = 30
    static let hostTileSubitemSpacing: CGFloat = 50
    static let consoleIconWidth: CGFloat = 150
    static let smallIconSize: CGFloat = 28
    static let largeIconSize: CGFloat = 50
    
    // MARK: Type
    static let baseFontSize: CGFloat = 20
    static let dialogTitleFontSize: CGFloat = 26
    static let dialogHeaderFontSize: CGFloat = 14
    static let toolbarOkFontSize: CGFloat = 25
    static let errorTitleFontSize: CGFloat = 24
    static let bigCloseFontSize: CGFloat = 60   // "×" close button
    static let streamMenuCloseFontSize: CGFloat = 50
    static let streamHudBitrateFontSize: CGFloat = 28
    static let streamHudCounterFontSize: CGFloat = 18
    
    // MARK: Animation
    static let stackTransitionDuration: Double = 0.2
    static let toastFadeDuration: Double = 0.5
    static let streamLoadFade: Double = 0.25
    static let streamMenuSlide: Double = 0.25
    static let logoPulseDuration: Double = 1.0
    
    // MARK: Radii
    static let smallRadius: CGFloat = 4
    static let mediumRadius: CGFloat = 8
}
```

---

## 6. Navigation model

The desktop uses `StackView.push/pop/replace`. SwiftUI on tvOS gives us a few options:

### Decision: single-route enum in `AppState`, switch in `ContentView`

```swift
enum AppRoute: Hashable {
    case hostList
    case registration(host: String, ps5: Bool)
    case manualHost
    case consolePin(hostIndex: Int)
    case settings
    case stream
    case autoConnect
}

@MainActor final class AppState: ObservableObject {
    @Published var route: AppRoute = .hostList
    @Published var modal: ChiakiModal? = nil   // ConfirmDialog / RemindDialog / Toast
    // …
}
```

`ContentView` switches on `appState.route` with `.transition(.opacity)` for the 200 ms cross-fade. `ChiakiModal` is presented via `.fullScreenCover` or a custom `ZStack` overlay (the desktop modals are **always** centered overlays that don't pause the underlying view, so a `ZStack` is closer to the original behavior than `.fullScreenCover`).

**Why not `NavigationStack`**: tvOS `NavigationStack` is great for hierarchical lists but the desktop's transition shape is replace, not push, and dialogs are overlay-based not stack-based. A custom enum keeps the implementation honest to the original.

---

## 7. SettingsView mapping

Desktop has 9 tabs; we ship **4**:

### Tab "General"
| Desktop control | tvOS equivalent | Phase |
|---|---|---|
| Action On Disconnect | `Picker` | P0 |
| Action On Suspend | `Picker` | P0 |
| Audio/Video toggle | `Picker` (Audio + Video / Audio only / Video only / Disabled) | P0 |
| Stream Menu Combo | `Picker` (button combo) | P1 — depends on actual GameController bindings |
| **PSN Account ID** *(net new)* | `TextField` (12-char base64) | **P0** |
| Streamer Mode | `Toggle` | P0 |
| Verbose Logs | `Toggle` | P0 |
| Show Stream Stats | `Toggle` | P0 |

### Tab "Video & Stream"
*(combine desktop's Video + Stream tabs — they're conceptually the same picture quality settings)*

| Control | Type | Phase |
|---|---|---|
| Settings Profile | `Picker` (Local PS5 / Local PS4 — but we drop PS4) | drop combo, hardcoded "Local PS5" |
| Resolution | `Picker` (720p / 1080p / 1440p / 2160p HDR) | P0 UI |
| FPS | `Picker` (30 / 60) | P0 UI |
| Bitrate | `Slider` | P0 UI |
| Codec | `Picker` (H265 / H265 HDR) (drop H264, A15 doesn't need it) | P0 UI |
| Render Preset | `Picker` (Default / High Quality) (cut: HQ+Spatial / FSRCNNX — libplacebo only) | P0 UI |
| Vertical Sync | `Toggle` | P0 UI |
| Window Type / Stretch / Zoom | live in StreamMenuOverlay, not here | — |

### Tab "Audio"
| Control | Type | Phase |
|---|---|---|
| Audio Buffer Size | `Slider` | P0 UI (default 80 ms per [`../architecture/audio-pipeline.md`](../architecture/audio-pipeline.md)) |
| Audio Volume | `Slider` 0–100 | P0 UI |
| Weak Wifi Notification | `Slider` (0–100% packet loss threshold) | P0 UI |
| Packet Loss Reported Max | `Slider` | P0 UI |

(Drop Output / Input device pickers — Apple TV has one output, no mic.)

### Tab "Consoles"
| Section | Type | Phase |
|---|---|---|
| **Registered consoles list** | `List` of registered hosts with **Delete** swipe | P0 UI → P1 wired |
| **Hidden consoles list** | `List` with Unhide button | P0 UI → P1 wired |
| **Register New Console** button | navigates to `.registration` route | P0 |

---

## 8. Phase 0 deliverable shape

After Phase 0 ends:

- `xcodegen generate && xcodebuild` builds clean (already true today).
- `swift test` green (already true today; we'll add Codable round-trip tests).
- Visually: the simulator boots into a `HostListView` rendering **mocked** hosts (so we have something to look at without the bridge wired). All buttons navigate; all dialogs open + dismiss; all settings tabs render. Nothing real talks to a PS5 yet — that's Phase 1.
- The visual style is **matching the desktop** for everything we keep. A user looking at the desktop and the tvOS app side-by-side should immediately recognize them as the same family.

Phase 1 (separate work, deferred to after the bridge lands) wires every UI binding to the Chiaki bridge, replaces SF Symbol stand-ins with the original SVG glyphs, and adds the Metal video view to `StreamView`.

---

## 9. Open decisions for the user (post-implementation)

These are **not** blockers for Phase 0 but should be revisited before Phase 1:

1. **Tab style on the Settings screen.** tvOS 18+ has `.tabViewStyle(.sidebarAdaptable)` which gives a native left-sidebar nav similar to a desktop tab bar. tvOS 17 only has `.page` (which adds dot indicators that look out of place for settings) and the default top bar (which loses on widescreen). I'll default to **default top tab bar** (cleanest). If you prefer the sidebar, set deployment target to tvOS 18.
2. **SettingsView placement of the PSN Account ID field.** Currently slated for the General tab. Alternative: a dedicated "Account" section first (single field). I went with General because it's the desktop's habitual landing tab. Tell me if you want it isolated.
3. **In-stream menu's "Disconnect" placement.** Desktop puts it as the leftmost icon in StreamMenuWindow. SwiftUI on tvOS makes the leftmost focusable element the default-focused one, which is desirable here so the user can quickly disconnect with B-button-then-A. Keeping desktop layout.
4. **Background watermark.** Desktop pulses the chiaki-ng logo at low opacity behind the host list. We'll ship the same with an SF Symbol fallback (`gamecontroller.fill` placeholder) until we copy the SVG asset across. **Action:** in P1 copy `gui/res/icons/chiaking-logo-white.svg` into `Assets.xcassets`.

I'll surface (1)/(2)/(3) for confirmation if you'd rather not have the defaults.

---

## 10. Implementation order (Phase 0)

1. `Theme/Theme.swift` — palette + spacing tokens.
2. `App/AppState.swift` — extend with `route: AppRoute` + `modal: ChiakiModal?`.
3. `Models/{Host,RegisteredHost,AppSettings}.swift` — Codable types + mock factories.
4. `Views/Components/{ChiakiButton, ChiakiDialogChrome, ChiakiToolbar, ChiakiSpinner, LogoPulse}.swift`
5. `Views/Components/{ConfirmDialog, RemindDialog, ManualHostDialog, ConsolePinDialog, ErrorToastView}.swift`
6. `Views/HostListView.swift` (replaces stub) + `HostTile.swift`
7. `Views/RegistrationView.swift`
8. `Views/SettingsView.swift` (TabView + 4 tab content views)
9. `Views/StreamView.swift` (full-bleed black + StreamMenuOverlay)
10. `Views/AutoConnectView.swift`
11. `Views/ContentView.swift` (rewrite to switch on `AppState.route`)
12. `Tests/ChiakiTVTests/` — Codable roundtrip tests for the three model types.
13. `xcodegen generate && xcodebuild ... build` and `swift test` to confirm green.

This order is **dependency-driven** — each file only references things written before it. We can implement and validate in chunks.

---

End of plan. Implementation starts in [`../phases.md#phase-0--scaffolding`](../phases.md) and lands across the file plan in §4.
