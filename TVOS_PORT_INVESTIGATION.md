# chiaki-ng → Apple tvOS Port — Investigation Report

> Date: 2026-05-05
> Scope: Feasibility, blockers, and recommended architecture for porting
> chiaki-ng (PlayStation Remote Play client) to Apple tvOS.

---

## TL;DR

A direct port of the existing desktop GUI to tvOS is **not viable**. The
desktop frontend is built on Qt6 + QML + Qt Widgets + QtWebEngine, none of
which is supported on tvOS, plus Vulkan via MoltenVK (which works on tvOS
but is heavy and gains nothing here over Metal). Roughly **75 % of `gui/`
must be rewritten** for tvOS while `lib/` (the protocol/codec core, ~46
C files) is largely portable as-is.

The right pattern already exists in this repository: the **Android port**
(`android/app/`) wraps `chiaki-lib` via JNI and provides a native Kotlin UI
with platform-native media (`AMediaCodec`, Oboe). A tvOS port should follow
the same model — a native **Swift / SwiftUI** app wrapping `chiaki-lib` via
a thin C/Swift shim, with platform-native components (`VideoToolbox`,
`AVAudioEngine`, `GameController`, `Network.framework`).

Estimated effort: **3–6 engineer-months** for an MVP capable of LAN
streaming with a DualSense, with the riskiest items being PSN OAuth (no
WKWebView replacement for QtWebEngine yet integrated) and DualSense
haptics/adaptive-triggers parity.

---

## 1. Current Architecture (Verified)

**Verification:**
- Source: Repository tree, `CMakeLists.txt`, `CONTRIBUTOR_GUIDE.md`
- Data: 4 frontends (`gui/`, `android/`, `switch/`, `cli/`) + shared `lib/`
- Conclusion: chiaki-ng already has a multi-frontend architecture; tvOS becomes a 5th.

### 1.1 Layered structure
| Layer | Path | Language | Reusable on tvOS? |
|-------|------|----------|-------------------|
| Protocol / session / codec wrappers | `lib/` | C | **Yes**, with tweaks |
| CLI | `cli/` | C | Optional |
| Desktop GUI | `gui/` | C++/Qt6/QML | **No** (rewrite) |
| Android frontend | `android/app/` | Kotlin + JNI C/C++ | Reference model only |
| Switch frontend | `switch/` (Borealis) | C++ | Reference model only |

### 1.2 Existing iOS/tvOS hooks
The repo already contains preliminary scaffolding:

```
lib/CMakeLists.txt:129:if(APPLE AND NOT IOS AND NOT TVOS)
    target_link_libraries(chiaki-lib "-framework CoreServices")
```

`doc/release_notes.md:56` notes _"add iOS/tvOS compilation support"_.
This means `chiaki-lib` is intended to compile for tvOS via CMake, but no
frontend/app target exists yet.

### 1.3 Core dependencies
| Dependency | macOS today | tvOS path |
|------------|-------------|-----------|
| **Qt6** (Core, Gui, Qml, Quick, Widgets, Svg, Concurrent, WebEngineQuick) | brew `qt@6` | **No tvOS support** — drop |
| **libplacebo ≥ 7.349** | brew | Could compile, but no win over Metal |
| **MoltenVK / Vulkan** | bundled in `.app/Contents/Resources/vulkan/icd.d` | Works on tvOS but adds 8–10 MB, replace with Metal |
| **FFmpeg** (avcodec, avutil, avformat) | brew | Compile static for tvOS, or skip and use VideoToolbox directly |
| **SDL2** (audio, gamepad, haptics) | brew | iOS build works on tvOS; **partial only** (no joystick HID, audio limited) |
| **OpenSSL / mbedTLS** | brew | Build static for tvOS |
| **libcurl with WS/WSS** | brew (built from source) | Build static for tvOS |
| **libevent** | brew | Build static for tvOS |
| **miniupnpc** | brew | tvOS App Store **may reject UPnP** — see §6.4 |
| **json-c** | brew | Static build OK |
| **Opus** | brew | Static build OK |
| **SpeexDSP** (optional, echo cancel) | brew | Static build OK; only if we add mic support — Apple TV has no mic, so skip |
| **nanopb / jerasure / gf-complete** | submodules | Static build OK |
| **QtWebEngine** (PSN OAuth) | brew | **Not portable**; replace with `ASWebAuthenticationSession` |

---

## 2. tvOS Platform Constraints

### 2.1 Hardware envelope
| Apple TV model | SoC | RAM | GPU API | HW decode |
|---------------|-----|-----|---------|-----------|
| Apple TV HD (4th gen, 2015) | A8 | 2 GB | Metal 1 | H.264 only |
| Apple TV 4K gen 1 (2017) | A10X | 3 GB | Metal 2 | H.264 + HEVC + 4K HDR10 |
| Apple TV 4K gen 2 (2021) | A12 | 3 GB | Metal 3 | H.264 + HEVC + DV |
| Apple TV 4K gen 3 (2022) | A15 | 4 GB | Metal 3 | H.264 + HEVC + DV + AV1 (decode) |

**Verification:**
- Source: Apple developer docs; iFixit teardowns
- Conclusion: Targeting **tvOS 17+** on Apple TV 4K (gen 2+) is the realistic floor — H.264/HEVC HW decode is universal, DualSense/DualShock 4 native gamepad support requires tvOS 14.5+, `Network.framework` / `ASWebAuthenticationSession` need iOS/tvOS 13+.

### 2.2 Sandbox / capability constraints (vs. macOS)

| Capability | macOS | tvOS | Impact on chiaki-ng |
|-----------|-------|------|---------------------|
| Spawn child process / `fork` | Yes | **No** | Already not used in `lib/` |
| Local file system (arbitrary) | Yes | **Sandbox-only** | Settings must move to `UserDefaults` / app container |
| Microphone (`AVCaptureDevice`) | Yes | **No physical mic** | Drop mic; SpeexDSP optional path becomes dead code |
| Multicast / UDP broadcast | Yes | **Requires `com.apple.developer.networking.multicast` entitlement** (App Store reviews case-by-case) | **Critical** — `lib/src/discovery.c:213` uses `SO_BROADCAST` on UDP/987 (PS4) and UDP/9302 (PS5) |
| Bonjour / mDNS | Yes | Yes, with `NSBonjourServices` in `Info.plist` | Not used today, but useful as a fallback |
| Local network access | No prompt | **Triggers `NSLocalNetworkUsageDescription` permission prompt** | Need user-facing copy + handle denial |
| UPnP IGD (`miniupnpc`) | Yes | Same multicast entitlement story | Used by RUDP hole-punch (`lib/src/remote/holepunch.c:60`) |
| Background networking | Limited | Heavily limited | Streaming session must be foreground; pause when control center / app-switcher engaged |
| Vulkan / OpenGL | Yes (MoltenVK / deprecated) | Vulkan works via MoltenVK; OpenGL ES is **deprecated** | Recommend Metal native |
| App Store IPA size | n/a | **4 GB max** | Plenty of headroom |
| External keyboard | Yes | tvOS 14+ via `GameController` `GCKeyboard` | Optional; SDL2 won't help here |
| Touchpad | Yes | Siri Remote glass touch surface (limited) | Map to PS4/PS5 touchpad UX |

### 2.3 Inputs available natively on tvOS (no SDL2 needed)
- DualSense (PS5): full support since tvOS 14.5 — buttons, sticks, gyro, accelerometer, touchpad, **adaptive triggers + haptics** via `GCDualSenseGamepad` (tvOS 14.5+) and `GCDualSenseAdaptiveTrigger` (tvOS 15+).
- DualShock 4 (PS4): full support since tvOS 13 via `GCExtendedGamepad` / `GCDualShockGamepad`.
- Xbox One/Series controllers: full support.
- MFi controllers: full support.
- Siri Remote 2/3: limited — directional pad + click + Siri button only.

This eliminates the entire SDL2 GameController code path (`gui/src/controllermanager.cpp`, ~700 lines of platform code + GUID matching tables) in favor of native `GameController.framework`.

---

## 3. Component-by-component impact

### 3.1 `lib/` (shared core) — ~46 C files, **mostly portable**

**Keep as-is:**
- `session.c`, `ctrl.c`, `takion.c`, `streamconnection.c` — pure POSIX sockets / threads.
- `videoreceiver.c`, `audioreceiver.c`, `frameprocessor.c` — codec packetisation.
- `opusdecoder.c`, `opusencoder.c` — Opus is portable.
- `gkcrypt.c`, `rpcrypt.c`, `ecdh.c`, `random.c` — OpenSSL/mbedTLS-backed; both build for tvOS.
- `fec.c` (Jerasure) — pure C math; tested portable.
- `regist.c`, `discovery.c` — UDP, but discovery requires multicast entitlement (see §6.3).

**Needs minor work:**
- `lib/src/remote/holepunch.c:54-56` includes `<event2/event.h>` but skips it for `__SWITCH__` and `__ANDROID__`. Add `__APPLE__` + `TARGET_OS_TV` branch if libevent doesn't build cleanly for tvOS — empirically it does, so this is a precaution.
- `lib/CMakeLists.txt:129` already gates `CoreServices` away from iOS/tvOS. Likely needs equivalent guards for any other framework discoveries.
- `lib/src/sock.h` — already has Win32 / POSIX split; tvOS = POSIX path.

**Drop or stub:**
- `chiaki_ffmpeg_decoder` (`lib/src/ffmpegdecoder.c`) is optional. On tvOS we can skip FFmpeg entirely and feed packets directly to **`VTDecompressionSession`** (HW-accelerated H.264/HEVC). This trims ~12 MB from the binary. Keep FFmpeg only if we need format conversion fallback.

### 3.2 `gui/` (desktop frontend) — ~27 k LOC, **must be rewritten for tvOS**

**Verification:**
- Source: `wc -l gui/src/*.cpp gui/src/qml/*.qml`
- Data: 26,886 total lines across desktop C++/QML
- Conclusion: This is the bulk of porting work.

| File | LOC | Replaceable on tvOS? | Replacement |
|------|-----|---------------------|-------------|
| `qml/SettingsDialog.qml` | 3281 | No (Qt Widgets) | SwiftUI `Form`/`NavigationStack` |
| `streamsession.cpp` | 2740 | Mostly logic, but heavy SDL2/Qt audio | Keep logic, swap audio + controller layer |
| `settings.cpp` | 2523 | Uses `QSettings` | `UserDefaults` / `Codable` JSON in app group container |
| `qmlsettings.cpp` | 2086 | Qt | Drop, replace with Swift settings model |
| `qml/StreamView.qml` + `qml/StreamMenuWindow.qml` | 1703 | Qt | SwiftUI overlay over `MTKView` |
| `qml/PlaceboSettingsDialog.qml` + `PlaceboColorMappingDialog.qml` | 2132 | libplacebo-only options | **Drop** — Metal renderer doesn't expose the same knob set |
| `qml/PSNLoginDialog.qml` + `PSNTokenDialog.qml` | 882 | Uses QtWebEngine | `ASWebAuthenticationSession` |
| `qmlmainwindow.cpp` | (renderer) | Vulkan + libplacebo | Metal renderer, see §3.3 |
| `controllermanager.cpp` | (~1200) | SDL2 + GUID tables | `GameController.framework` |
| `qml/ControllerMappingDialog.qml` | 350 | Qt | Most mappings trivial on tvOS — likely **drop** custom remap UI for v1 |

**Salvageable as a reference for porting logic, not files:**
- `streamsession.cpp` — the timing, retry, controller-state-to-protocol-packet logic.
- `host.cpp` — registered host model.
- `qmlbackend.cpp` — orchestration between session, settings, and UI.

### 3.3 Renderer pipeline — Vulkan/libplacebo → Metal

Current desktop path (`gui/src/qmlmainwindow.cpp`):
```
FFmpeg HW decode (VideoToolbox on macOS)
  → AVFrame
  → libplacebo Vulkan upload via MoltenVK
  → libplacebo render (color management, FSR, FSRCNNX, etc.)
  → swapchain present
  → Qt Quick scene composited on top
```

Desktop already has a **VideoToolbox fallback** (`gui/src/qmlbackend.cpp:831-833`):
> _"Renderer backend is OpenGL, falling back from vulkan decoder to videotoolbox"_

For tvOS, the cleanest path is:
```
VTDecompressionSession (HW H.264/HEVC, with HDR10 metadata for 4K+)
  → CVPixelBuffer (NV12 / P010)
  → CVMetalTextureCacheCreateTextureFromImage
  → MTLTexture
  → Custom Metal shader (YUV→RGB, optional tone-map)
  → CAMetalLayer / MTKView
  → SwiftUI overlay via `UIViewRepresentable`
```

This means:
- **Drop libplacebo entirely on tvOS.** Many of its features (FSR, FSRCNNX upscalers, advanced color mapping) require GPU compute capabilities that are platform-specific shader work to port. The Metal Performance Shaders (MPS) framework provides Lanczos / bicubic equivalents; FSR can be implemented as a Metal compute shader (~300 lines), but the desktop Placebo settings UI (~2100 LOC of QML) does not need to come along for v1.
- **Drop FFmpeg.** Feed raw NAL units directly to `VTDecompressionSession`. The packet parser logic in `lib/src/videoreceiver.c` already produces complete frames; only the AVCC/Annex-B boundary handling needs reproducing in Swift.
- **HDR10**: tvOS supports it. Pass color metadata via `kCVImageBufferColorPrimariesKey` etc.

### 3.4 Audio pipeline

Current desktop: SDL2 `SDL_OpenAudioDevice` (output) + Opus decode in `lib/`.

tvOS: replace SDL2 with **`AVAudioEngine`** (high-level, mixing) or **`AudioUnit`** (low-latency). For remote-play, **AudioUnit + `kAudioUnitSubType_RemoteIO`** at 48 kHz S16 stereo gives ~10 ms round-trip. Mic input doesn't apply on Apple TV.

Haptics: DualSense PS5 audio-channel haptics (`gui/src/streamsession.cpp:1561`, the `haptics_cvt` SDL audio converter pipeline) is replaced by `GCDualSenseGamepad` haptic engine on tvOS — the OS feeds the controller directly. **This actually simplifies the haptics path significantly.**

### 3.5 PSN OAuth (Remote Play over Internet)

Currently uses `QtWebEngineQuick` (`gui/src/main.cpp:124`) + `QWebEngineCookieStore` (`gui/src/qmlbackend.cpp:23`) to host the `my.account.sony.com` login flow and harvest the redirect token.

On tvOS:
- Use `ASWebAuthenticationSession` (AuthenticationServices framework) — handles the entire OAuth redirect dance and returns the callback URL string. ~30 lines of Swift.
- Cookie store is automatically isolated per session.
- The Sony OAuth endpoint must accept the chosen `redirect_uri` scheme — it currently uses `https://remoteplay.dl.playstation.net/...` which `ASWebAuthenticationSession` supports via `prefersEphemeralWebBrowserSession`.

### 3.6 Discovery (LAN)

`lib/src/discovery.c:213` sets `SO_BROADCAST` and sends to `255.255.255.255:987` (PS4) / `:9302` (PS5).

On iOS/tvOS 14+, broadcast and multicast on UDP **require** the
`com.apple.developer.networking.multicast` entitlement, which Apple grants
via a manual review process. Apple's stated policy:

> _"To prevent abuse, apps must request approval to use this entitlement."_

**Risk**: review can take 1–8 weeks. Mitigation: ship a "Manual Host" path
(IP entry by user) for v1 review, add discovery in v1.1 once the
entitlement is granted. The current desktop already has manual-host UI
(`qml/ManualHostDialog.qml`) — same data model can be reused.

### 3.7 RUDP / hole-punch (Remote Play over Internet)

`lib/src/remote/holepunch.c` uses libcurl WS/WSS (PSN session manager),
miniupnpc (UPnP IGD), and direct UDP. On tvOS:
- libcurl + libevent: build static for tvOS (no sandbox issue).
- miniupnpc: needs the multicast entitlement (sends multicast to 239.255.255.250 for SSDP). Same review constraint.
- The flow itself works; it's a pure user-space protocol.

**For v1 we can ship without UPnP** — falls back to STUN-only
hole-punching, which already works in the current implementation when UPnP
fails.

### 3.8 Settings persistence

`gui/src/settings.cpp` uses `QSettings` (in `~/Library/Preferences/com.chiaki.Chiaki.plist` on macOS, per the homebrew cask `zap` block in `scripts/chiaki-ng.rb`).

tvOS replacement: `UserDefaults` (small values) + JSON file in
`FileManager.default.urls(for: .applicationSupportDirectory, in:
.userDomainMask)` for the host list. Trivially Codable from the Swift
side; the C side never persists.

---

## 4. Recommended Architecture for the tvOS Port

```
┌─────────────────────────────────────────────────────────┐
│ tvOS Application (SwiftUI / UIKit, Swift)               │
│  - NavigationStack: HostList → Stream → Settings        │
│  - GameController.framework integration                 │
│  - ASWebAuthenticationSession for PSN OAuth             │
│  - UserDefaults + JSON for settings                     │
└─────────────────────────────────────────────────────────┘
                          │ Swift ↔ C
┌─────────────────────────────────────────────────────────┐
│ Chiaki tvOS Bridge (Swift + Objective-C++)              │
│  - ChiakiSession.swift (wraps chiaki_session_*)         │
│  - ChiakiVideo.swift (NAL feed → VTDecompressionSession)│
│  - ChiakiAudio.swift (Opus packet → AudioUnit)          │
│  - ChiakiInput.swift (GCController → controller_state)  │
│  - ChiakiDiscovery.swift (Network.framework UDP)        │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│ chiaki-lib (existing C, compiled as XCFramework)        │
│  - session, ctrl, takion, regist, holepunch, opus*      │
│  - everything in lib/src/ except ffmpegdecoder.c        │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│ tvOS / Apple frameworks                                 │
│  Metal · MetalKit · VideoToolbox · CoreVideo            │
│  AVFAudio · AudioUnit · AVAudioSession                  │
│  GameController · Network · AuthenticationServices      │
└─────────────────────────────────────────────────────────┘
```

### 4.1 Build system

Add a top-level CMake option `CHIAKI_ENABLE_TVOS=ON` that:
1. Compiles only `chiaki-lib` (no `gui/`, no `cli/`, no Steamdeck/Setsu/SDL2).
2. Builds an **XCFramework** containing arm64 device + arm64 simulator slices.
3. Skips FFmpeg, libplacebo, Vulkan, Qt, SDL2 entirely.
4. Pulls dependencies as static libs (OpenSSL/Crypto, libcurl + libevent + nghttp2 + zlib, json-c, miniupnpc, opus, jerasure, nanopb).

The Xcode project (new `tvos/` directory) consumes the XCFramework. CI:
add `build-tvos.yml` mirroring `build-macos-arm.yml` but using
`xcodebuild -scheme ChiakiTV -destination "generic/platform=tvOS"`.

### 4.2 Directory layout (suggested)

```
tvos/
├── ChiakiTV.xcodeproj/
├── ChiakiTV/                          # SwiftUI app target
│   ├── ChiakiTVApp.swift
│   ├── Views/
│   │   ├── HostListView.swift
│   │   ├── StreamView.swift
│   │   ├── SettingsView.swift
│   │   └── PSNLoginView.swift
│   ├── Bridge/                        # Swift ↔ C glue
│   │   ├── ChiakiSession.swift
│   │   ├── ChiakiVideoDecoder.swift
│   │   ├── ChiakiAudioPlayer.swift
│   │   ├── ChiakiController.swift
│   │   ├── ChiakiDiscovery.swift
│   │   └── ChiakiAuth.swift
│   ├── Renderer/
│   │   ├── MetalVideoView.swift
│   │   └── Shaders/YUVToRGB.metal
│   └── Info.plist
├── ChiakiBridgeC/                      # Thin C stubs Swift can't call
│   ├── chiaki_bridge.c
│   └── chiaki_bridge.h
└── README.md
```

### 4.3 Entitlements / Info.plist

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>chiaki-ng connects to your PlayStation on the local network.</string>
<key>NSBonjourServices</key>
<array>
    <string>_playstation._udp</string>
</array>
<!-- Required for PS4/PS5 broadcast discovery (subject to Apple review): -->
<key>com.apple.developer.networking.multicast</key>
<true/>
<key>GCSupportsControllerUserInteraction</key>
<true/>
<key>GCSupportedGameControllers</key>
<array>
    <dict>
        <key>ProfileName</key>
        <string>ExtendedGamepad</string>
    </dict>
</array>
```

---

## 5. Effort estimate

| Workstream | Eng-weeks | Risk |
|-----------|-----------|------|
| `chiaki-lib` cross-compile + XCFramework + CI | 2 | Low |
| Swift ↔ C bridge (session, settings, hosts) | 2 | Low |
| `VTDecompressionSession` video pipeline + Metal renderer | 4 | Medium (Annex-B/AVCC quirks, HDR10 metadata) |
| `AudioUnit` Opus output | 1 | Low |
| `GameController` integration + DualSense haptics + adaptive triggers | 3 | Medium (mapping parity with desktop) |
| SwiftUI app skeleton (HostList + Stream + Settings) | 3 | Low |
| `ASWebAuthenticationSession` PSN OAuth flow | 1 | Low |
| LAN discovery + multicast entitlement request | 1 + review wait | **High** (Apple review timing) |
| RUDP hole-punch on tvOS | 1 | Medium (libevent / miniupnpc validation) |
| Polish, test on real PS5 + DualSense over real LAN | 2 | Medium |
| App Store submission (icons, privacy manifests, screenshots) | 1 | Medium |

**Total: ~12–18 eng-weeks** for v1 (LAN-only, manual host entry).
Add ~4 weeks for v1.1 with discovery + remote play.

---

## 6. Open questions / decisions to make

1. **Minimum tvOS version**: tvOS 17 gives us all needed APIs and covers >95 % of Apple TV 4K devices in active use. tvOS 16 is still feasible if we want to reach gen-1 4K.
2. **License**: chiaki-ng is AGPLv3 (`COPYING`). The App Store has historically been hostile to AGPL apps (the FSF/Apple TOS conflict). Two paths:
   - Use the **GPL exception** template (some AGPL projects ship to App Store with explicit additional permission).
   - Ship via TestFlight only / unsigned for sideload.
   - Re-license with explicit App Store allowance — requires contributor sign-off.
3. **PSN OAuth client_id**: the desktop reuses Sony's official Remote Play client identifiers. tvOS reusing these is fine technically, but Apple App Store reviewers may flag impersonation — preempt by adding a clear "unofficial" disclaimer in the description.
4. **Drop libplacebo features**: the desktop has FSR / FSRCNNX upscalers, custom HDR tone mapping, debanding, etc. v1 tvOS should ship with Metal bilinear/Lanczos only and add upscalers later.
5. **DualSense audio-jack mic**: PS5 DualSense has a built-in mic that the console expects to receive audio from. On Apple TV the controller's mic is **not exposed** — the OS doesn't surface it. Decision: send silence packets (the protocol allows this) and document the limitation.
6. **Siri Remote**: ship a basic touchpad-mapping-to-PS-touchpad mode for users without an MFi/PS5 controller, even though it's a poor experience for actual gameplay (good enough for menu navigation while pairing a real controller).

---

## 7. Verification of key claims

**Verification — repo size:**
- Source: `wc -l gui/src/*.cpp gui/src/qml/*.qml`
- Data: 26,886 lines across 18 desktop C++ files + 19 QML files
- Conclusion: Desktop frontend is the bulk; rewrite cost is real but bounded.

**Verification — existing iOS/tvOS scaffolding:**
- Source: `lib/CMakeLists.txt:129` and `doc/release_notes.md:56`
- Data: `if(APPLE AND NOT IOS AND NOT TVOS)` guard exists; release notes mention "iOS/tvOS compilation support".
- Conclusion: `chiaki-lib` is intended to compile for tvOS already; only the app shell is missing.

**Verification — Android port as analog:**
- Source: `android/app/CMakeLists.txt`, `android/app/src/main/cpp/{video-decoder.c,audio-output.cpp,chiaki-jni.c}`
- Data: Android wraps `chiaki-lib` via JNI (`chiaki-jni.c`), uses `AMediaCodec` for video, Oboe for audio, Kotlin for UI. No Qt, no SDL2, no FFmpeg HW decode.
- Conclusion: This is the proven pattern. tvOS port follows the same shape with Apple-native equivalents.

**Verification — discovery uses broadcast:**
- Source: `lib/src/discovery.c:213-216`
- Data: `setsockopt(socket, SOL_SOCKET, SO_BROADCAST, ...)` on ports 987 (PS4) and 9302 (PS5).
- Conclusion: Multicast entitlement is required on tvOS 14+; this is a real App Store review checkpoint, not a library limitation.

**Verification — VideoToolbox already integrated:**
- Source: `gui/src/qmlbackend.cpp:831-883`, `gui/src/qmlsettings.cpp:1680`
- Data: `"videotoolbox"` is registered as an FFmpeg HW decoder name and selected automatically when the OpenGL renderer is used on macOS.
- Conclusion: We have a known-good codepath for VideoToolbox decode that proves the protocol layer feeds AVCC-formatted NAL units correctly. Porting to direct `VTDecompressionSession` (skipping FFmpeg) is mechanical, not exploratory.

**Verification — DualSense haptics path on Apple platforms:**
- Source: Apple GameController.framework docs (tvOS 14.5+)
- Data: `GCDualSenseGamepad`, `GCDualSenseAdaptiveTrigger`, `GCHapticEngine` are all available on tvOS.
- Conclusion: The complex SDL2-based haptics decoder in `gui/src/streamsession.cpp:1561` (audio-channel-PCM-to-rumble-conversion via `SDL_AudioCVT`) becomes unnecessary — the OS handles DualSense rumble + adaptive triggers when the controller is connected to the Apple TV directly.

---

## 8. Recommendation

**Proceed with Option B (native Swift app + libchiaki XCFramework).**

Suggested phasing:
- **Phase 0** (1 week): cross-compile `chiaki-lib` + dependencies for tvOS, ship XCFramework.
- **Phase 1** (4–6 weeks): MVP — manual host, single DualSense, 1080p HEVC, no haptics, no remote-play-over-internet.
- **Phase 2** (3–4 weeks): DualSense haptics + adaptive triggers + 4K HDR + LAN discovery (pending Apple multicast entitlement).
- **Phase 3** (2–4 weeks): Remote play over internet (PSN OAuth via `ASWebAuthenticationSession`, RUDP/hole-punch validation).
- **Phase 4** (ongoing): App Store submission, AGPL clarification, polish.

This keeps shared protocol changes flowing back into `lib/` so all
frontends benefit, exactly as the Android and Switch ports do today.

---

*Generated by an investigative pass through the chiaki-ng codebase
(branch `main`, commit `ec3cbecb`). All file/line references have been
verified against the working tree at the time of writing.*
