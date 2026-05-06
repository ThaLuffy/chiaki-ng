# Phases

What's built, what's pending, what's deferred. **As-of dates** are load-bearing — when in doubt about whether a phase is current, re-verify against the running code and tests before quoting status.

## Phase 0 — Scaffolding (in progress)

The minimum that has to exist before anything real can be written: directory layout, build system, doc scaffold, stub Swift app, stub C bridge.

| Component | Status | Source of truth |
|---|---|---|
| Directory tree (`tvos/{ChiakiTV,ChiakiBridgeC,Tests,Vendors,docs}`) | ✅ done | top of [`../README.md`](../README.md) |
| AGENTS.md / CLAUDE.md / README.md | ✅ done | [`../AGENTS.md`](../AGENTS.md), [`../CLAUDE.md`](../CLAUDE.md), [`../README.md`](../README.md) |
| `project.yml` (XcodeGen) — produces `ChiakiTV.xcodeproj` | ✅ done | [`../project.yml`](../project.yml) |
| `Package.swift` (SPM) — for headless C-bridge tests | ✅ done | [`../Package.swift`](../Package.swift) |
| `Info.plist` + `ChiakiTV.entitlements` | ✅ done | [`../ChiakiTV/Info.plist`](../ChiakiTV/Info.plist), [`../ChiakiTV/ChiakiTV.entitlements`](../ChiakiTV/ChiakiTV.entitlements) |
| Stub Swift app (entry point + 4 view stubs + AppState + Host model + logger) | ✅ done | [`../ChiakiTV/`](../ChiakiTV/) |
| Stub C bridge (`module.modulemap` + version smoke-test function) | ✅ done | [`../ChiakiBridgeC/`](../ChiakiBridgeC/) |
| `swift build` succeeds | ✅ verified 2026-05-05 | n/a |
| `swift test` runs the C bridge smoke test | ✅ verified 2026-05-05 (1 test) | [`../Tests/ChiakiBridgeCTests/ChiakiBridgeCTests.swift`](../Tests/ChiakiBridgeCTests/ChiakiBridgeCTests.swift) |
| `xcodegen generate` produces a clean `ChiakiTV.xcodeproj` | 🟡 **pending validation** — run as the closing step of Phase 0 |
| Phase 0 docs (decisions, phases, platform stubs, architecture stubs) | 🟡 **in progress** |

Phase 0 success criteria: `swift test` green AND `xcodegen generate` produces a buildable Xcode project. Both are below the Phase 1 starting line, so neither claims to do anything real yet.

## Phase 1 — LAN streaming MVP (pending)

Take the chiaki-ng `lib/` upstream, get it onto the Apple TV, drive a single PS5 over the LAN with a single DualSense.

Major workstreams (rough order):

1. ~~**Cross-compile chiaki-ng `lib/` and dependencies for tvOS arm64.**~~ ✅ done 2026-05-05. Driven by [`../scripts/build-deps-tvos.sh`](../scripts/build-deps-tvos.sh). Outputs land in `Vendors/prefix/{appletvos,appletvsimulator}/lib/` (arm64, both slices). `OTHER_LDFLAGS` in [`../project.yml`](../project.yml) statically links: `libchiaki, libjerasure, libgf_complete, libprotobuf-nanopb, libcurl, libopus, libjson-c, libevent*, libminiupnpc, libcrypto`. Smoke-test: `testChiakiLibIsLinked` in [`../Tests/ChiakiTVTests/ModelCodableTests.swift`](../Tests/ChiakiTVTests/ModelCodableTests.swift) calls `chiaki_log_level_char` from upstream and verifies the round-trip.
2. ~~**C bridge**: typed wrappers for the chiaki-ng callbacks Swift can't take directly (log, session events, video sample, audio sink, controller state).~~ ✅ done 2026-05-05. Headers: [`chiaki_bridge_log.h`](../ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_log.h), [`chiaki_bridge_regist.h`](../ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_regist.h), [`chiaki_bridge_session.h`](../ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_session.h). Swift drivers: [`ChiakiLogBridge`](../ChiakiTV/Services/Logging/ChiakiLogBridge.swift), [`RegistrationService`](../ChiakiTV/Services/Registration/RegistrationService.swift), [`StreamSession`](../ChiakiTV/Services/Session/StreamSession.swift), [`ControllerService`](../ChiakiTV/Services/Controller/ControllerService.swift). See [`architecture/bridge-layer.md`](architecture/bridge-layer.md).
3. ~~**Discovery service**: drive `chiaki_discovery_service_*` from `lib/src/discoveryservice.c`, surface results to a Swift `@Published` host list.~~ ✅ done 2026-05-05 (simulator). Bridge: [`../ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_discovery.h`](../ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_discovery.h) wraps `ChiakiDiscoveryService` with a stack-allocated POD snapshot per callback (the upstream `const char *` fields die with the chiaki state mutex). Swift driver: [`../ChiakiTV/Services/Discovery/DiscoveryService.swift`](../ChiakiTV/Services/Discovery/DiscoveryService.swift) hops to MainActor and publishes `[Host]`. UDP broadcast on `:9302` (PS5) and `:987` (PS4 ping for compat) works without the multicast entitlement — verified on the simulator with a real PS5 on the dev LAN. Test target: [`../Tests/ChiakiTVTests/DiscoveryServiceTests.swift`](../Tests/ChiakiTVTests/DiscoveryServiceTests.swift) (10 tests). Hardware re-verify still required for Apple TV 4K 3rd gen sign-off.
4. ~~**Settings service**: persist registered hosts + the prefilled PSN account ID in JSON inside the app container.~~ ✅ done 2026-05-05. PSN account ID default ships as `"TyiIo99CmXI="` (8-byte account); registered hosts persist to `Application Support/ChiakiTV/registered_hosts.json` via [`RegisteredHostStore`](../ChiakiTV/Services/Settings/RegisteredHostStore.swift).
5. ~~**Manual host entry path**: IP address text field (tvOS keyboard) → instantiate a registered-host record → register / connect.~~ ✅ done 2026-05-05. [`ManualHostDialog`](../ChiakiTV/Views/Components/ManualHostDialog.swift) appends a manual `Host` to `AppState.hosts` and (if the user picked an existing registered console) updates that console's `lastIpAddress` so the connect path resolves it correctly.
6. ~~**Registration**: drive `chiaki_regist_start` from `lib/src/regist.c` with the prefilled account ID + an 8-digit PIN.~~ ✅ done 2026-05-05. [`RegistrationService`](../ChiakiTV/Services/Registration/RegistrationService.swift) wraps the C bridge; on success persists a `RegisteredHost` and refreshes `AppState.registeredHosts`. Hardware verify required: user-side action is putting PS5 into Link Device mode + entering the displayed PIN in `RegistrationView`.
7. ~~**Session bring-up**: drive `chiaki_session_start` from `lib/src/session.c`.~~ ✅ done 2026-05-05. [`StreamSession`](../ChiakiTV/Services/Session/StreamSession.swift) wires connect_info from a `RegisteredHost`, hooks the bridge callbacks to `VideoDecoder` + `AudioPlayer` + `ControllerService`, and surfaces session state via `@Published`. Hardware verify required.
8. ~~**Video pipeline**: NAL units flow out of `lib/src/videoreceiver.c` via the bridge; the Swift side feeds them into a `VTDecompressionSession` and renders the output `CVPixelBuffer` via Metal.~~ ✅ done 2026-05-05. Drop FFmpeg + libplacebo entirely. [`VideoDecoder`](../ChiakiTV/Services/Video/VideoDecoder.swift) walks Annex-B → AVCC and feeds VT; [`MetalRenderer`](../ChiakiTV/Services/Video/MetalRenderer.swift) renders NV12 (or P010 video-range for HDR) via [`VideoShaders.metal`](../ChiakiTV/Services/Video/VideoShaders.metal). See [`architecture/video-pipeline.md`](architecture/video-pipeline.md). Hardware verify required.
9. ~~**Audio pipeline**: PCM samples flow out of `lib/src/opusdecoder.c` via the bridge; the Swift side feeds them into AVAudioEngine.~~ ✅ done 2026-05-05. [`AudioPlayer`](../ChiakiTV/Services/Audio/AudioPlayer.swift) configures an `AVAudioEngine` + `AVAudioPlayerNode` from the audio header callback and schedules per-frame int16 PCM buffers. See [`architecture/audio-pipeline.md`](architecture/audio-pipeline.md). Hardware verify required.
10. ~~**Controller pipeline**: `GameController.framework` `GCExtendedGamepad` → `chiaki_controller_state_*` mutations sent immediately on every value change via the bridge.~~ ✅ done 2026-05-05. [`ControllerService`](../ChiakiTV/Services/Controller/ControllerService.swift) maps the GC values to chiaki's button bitmask + analog state and pushes through `chiaki_tv_session_set_controller_state` on every value change. Hardware verify required.
11. **End-to-end hardware verification** (pending — user action required): stream live, end to end, on Apple TV 4K 3rd gen against a physical PS5. The simulator can drive the same code paths against a real LAN PS5 too — first verify there with `simctl install booted` + `simctl launch booted`, then validate on real hardware before declaring Phase 1 done.

Phase 1 success criteria: 4K HEVC video + stereo Opus audio + DualSense control via the desktop chiaki-ng's same `lib/` API surface, on real hardware, without rebasic protocol fixes.

## Phase 2 — Polish

- ~~**HDR10 metadata propagation** (`AVDisplayCriteria(refreshRate:formatDescription:)`).~~ ✅ implemented 2026-05-06.
  - `VideoDecoder.buildFormatDescription` tags HEVC `CMFormatDescription` with BT.2020 / SMPTE-2084 PQ / BT.2020-NCL extensions when codec is `.h265HDR` ([`VideoDecoder.swift:266`](../ChiakiTV/Services/Video/VideoDecoder.swift)).
  - `MetalRenderer.applyHDRConfig` switches the `MTKView` drawable to `.bgr10a2Unorm` and the layer colorspace to `CGColorSpace.itur_2100_PQ` for HDR sessions ([`MetalRenderer.swift`](../ChiakiTV/Services/Video/MetalRenderer.swift)). 16-bit plane textures (`r16Unorm` / `rg16Unorm`) feed the new `fs_p010_hdr` BT.2020 fragment shader ([`VideoShaders.metal`](../ChiakiTV/Services/Video/VideoShaders.metal)).
  - `StreamMetalView.applyDisplayCriteria` calls `UIWindow.avDisplayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate:formatDescription:)` (tvOS 17+) so tvOS renegotiates the HDMI link to HDR + correct refresh rate ([`StreamMetalView.swift`](../ChiakiTV/Services/Video/StreamMetalView.swift)). Hardware verify required.
- ~~**4K60 default profile.**~~ ✅ implemented 2026-05-06. `AppSettings` defaults flipped to `.res2160p` / `.fps60` / `.h265hdr` / `30000 kbps` ([`AppSettings.swift`](../ChiakiTV/Models/AppSettings.swift)). chiaki-lib's preset table caps at 1080p (`lib/src/session.c:92-122`); we set width/height/fps directly on `ChiakiConnectVideoProfile` and rely on `video_profile_auto_downgrade=true` if the PS5 rejects 4K60. Hardware verify required.
- DualSense haptics + adaptive triggers via `GCDualSenseGamepad` (deferred).
- LAN discovery surfaced in the host list (currently manual-host-entry only) (deferred).
- In-stream menu overlay (long-press of the PS button to open) — already wired in Phase 1 (`appState.streamMenuOpen` + `StreamMenuOverlay`).
- ~~**Latency-first native-alternatives Phase A** (six tvOS-side optimizations).~~ ✅ implemented 2026-05-07. See [`optimization/native-alternatives-latency-first.md`](optimization/native-alternatives-latency-first.md) for per-item file:line citations and verdicts. Summary:
  - OpenSSL `libcrypto.a` rebuilt with ARMv8 AES asm (`_aes_v8_*` symbols verified).
  - Annex-B → AVCC walk relocated into [`ChiakiBridgeC/src/chiaki_bridge_video.c`](../ChiakiBridgeC/src/chiaki_bridge_video.c) — eliminates per-frame `Data` allocation on the streaming hot path.
  - `kCMSampleAttachmentKey_DisplayImmediately` set on every sample buffer.
  - Pre-warm path confirmed (parameter-set delivery builds VT session before any slice arrives) and AVCC malloc skipped on parameter-set-only deliveries.
  - `audioBufferMs` default lowered from 80 to 30.
  - Renderer migrated to raw `CAMetalLayer` + `CAMetalDisplayLink` (tvOS 17+) for `targetPresentationTimestamp`-aligned presents. Hardware verify required.
- ~~**Latency-first native-alternatives Phase B** (upstream-contributable patches).~~ ✅ implemented 2026-05-07. Carried in this branch on the `tvos-port` line; each is structured to be upstream-PR-ready.
  - **`EVP_CIPHER_CTX` reuse in `gkcrypt.c`**: per-instance contexts allocated once at `chiaki_gkcrypt_init`, freed at `chiaki_gkcrypt_fini`, reused across every encrypt + GMAC call. Eliminates per-packet malloc on the streaming hot path. Files: [`lib/include/chiaki/gkcrypt.h`](../../lib/include/chiaki/gkcrypt.h), [`lib/src/gkcrypt.c`](../../lib/src/gkcrypt.c).
  - **`TAKION_REORDER_QUEUE_SIZE_EXP` configurability**: new field on `ChiakiConnectInfo` (default 0 = preserve historical behaviour); threaded through `ChiakiTakionConnectInfo` and `ChiakiTakion` to the call site at [`takion.c:1095`](../../lib/src/takion.c). Bridge-level field on `chiaki_tv_session_config_t` ([`ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_session.h`](../ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_session.h)); `StreamSession.connect(...)` sets `2` (4 entries) for our wired-LAN target.
  - **`FEEDBACK_STATE_TIMEOUT_MIN_MS` reduction**: withdrawn after audit correction — the constant is declared but never enforced ([`feedbacksender.c:8` + `:314 // TODO`](../../lib/src/feedbacksender.c)); chiaki sends feedback packets sub-millisecond after a controller-state change. There is no input-latency floor to remove.

## Out of scope (explicitly dropped — not deferred)

| Item | Why it's out of scope |
|---|---|
| PSN OAuth for account-ID retrieval | Prefilled instead — see [`decisions.md#prefill-psn-account-id-no-oauth`](decisions.md#prefill-psn-account-id-no-oauth) |
| Remote Play over Internet (RUDP / hole-punch) | LAN-only personal use — see [`decisions.md#scope--lan-only-no-psn-oauth-no-app-store`](decisions.md#scope--lan-only-no-psn-oauth-no-app-store) |
| Microphone / voice chat | Apple TV has no built-in mic; DualSense mic isn't surfaced via tvOS APIs |
| App Store distribution | Personal use; AGPLv3 vs. App Store TOS adds friction with no payoff for personal use |
| PS4 / PS4 Pro support | Single PS5 target, mirroring `../../../ps-remote-play/` |
| Apple TV HD / 4K gen 1 / 4K gen 2 | A15 only — see [`decisions.md#apple-tv-4k-3rd-gen-only-a15-bionic-tvos-17`](decisions.md#apple-tv-4k-3rd-gen-only-a15-bionic-tvos-17) |
| Multi-user / multi-account / Family Sharing | Single user |
| libplacebo / FSR / FSRCNNX upscalers | Replaced by Metal native — see [`architecture/video-pipeline.md`](architecture/video-pipeline.md) |
| QtWebEngine / WebKit content | Not needed once OAuth is dropped |
| FFmpeg | Replaced by direct VideoToolbox decode — desktop's `videotoolbox` codepath in [`../../gui/src/qmlbackend.cpp:831`](../../gui/src/qmlbackend.cpp) is the reference |

## Test status

As of 2026-05-06:
- **1 SPM test** (`testBridgeVersionStringIsReachable` — Phase 0 smoke test).
- **41 Xcode tests** across `ChiakiTVTests`. Coverage: codable round-trip (7), persistence (10), discovery (10), Phase 1 services (13 — PSN account-id decode, registered-host lookup, discovered/registered reconciliation, bridge constants), `chiaki-lib` link smoke (1). The earlier `DebugHUDStateTests` (5) were retired when the in-app debug HUD was replaced by the in-stream `StreamHUDOverlay` top bar.
- End-to-end streaming cannot be fully tested in a simulator; Phase 1 sign-off requires real Apple TV 4K 3rd gen + real PS5 on the same LAN. Discovery has been smoke-verified on the simulator against a real PS5 on the dev LAN — the simulator picked up host `PS5-860` at standby state via UDP broadcast, exercising every layer of the discovery bridge end-to-end.

The simulator *can* drive registration + streaming against a real LAN PS5; that's the cheapest first verification. The flow:
1. PS5 → Settings → System → Remote Play → Link Device. Note the 8-digit PIN displayed.
2. In ChiakiTV simulator → tap the discovered PS5 → enter the PIN.
3. After registration succeeds, the host appears as paired; tap again to stream.

## External dependencies / blockers

- **Apple multicast entitlement** (`com.apple.developer.networking.multicast`) — not currently blocking. UDP broadcast for discovery works on tvOS without it for personal-use builds; if Apple closes that hole, we'll add the entitlement and request approval (relevant only if we ever pursue App Store distribution, which is out of scope).
- **Hardware testing** requires Apple TV 4K 3rd gen + PS5 on same LAN. Dev machine simulator can build / SPM-test but cannot exercise the streaming pipeline end-to-end.
- **Cross-compiled chiaki-ng deps** (Phase 1) — need a working build of OpenSSL + libcurl + libevent + json-c + miniupnpc + opus + jerasure + nanopb for tvOS arm64. There's no homebrew tap that ships these for tvOS; we own the build script.
