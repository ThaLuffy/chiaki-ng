# Decisions

ADR-style log of non-obvious choices for the chiaki-ng tvOS port. Each entry lists the decision, the alternatives considered, and the *why*. Update this file when revisiting a decision; never silently overwrite — append a "superseded by …" line and add a new entry.

## Reuse upstream chiaki-ng `lib/` instead of rewriting the protocol core

**Decision:** the tvOS port reuses [`../../lib/`](../../lib/) (the chiaki-ng C protocol library) wholesale. The Swift app drives it via a thin C bridge in [`../ChiakiBridgeC/`](../ChiakiBridgeC/). No protocol code is re-implemented in Swift.

**Considered:**
- Rewriting the protocol layer in Swift (the path the sibling [`../../../ps-remote-play/`](../../../ps-remote-play/) project took).
- Forking `lib/` into `tvos/lib/` to apply tvOS-specific patches.
- Generating Swift bindings automatically from `lib/include/chiaki/*.h` via `swift-bridge` or `bindgen`.

**Why:**
- `lib/` is *the* upstream reference. It's tested, deployed across desktop / Android / Switch / Steam Deck, and updated whenever Sony's firmware shifts. Reusing it means we get firmware updates, bug fixes, and protocol corrections "for free" by tracking upstream.
- The sibling ps-remote-play project demonstrated the cost of re-implementing in Swift: 116 unit tests, ~5,000 lines of Swift+C, and still hunting Chiaki-ng deviations after several months of work. That project explicitly cites "always read Chiaki-ng first" as Hard Rule #5 — at which point reusing `lib/` directly is the obvious next step.
- The thin-bridge model is exactly what `../../android/app/` does. Android wraps `chiaki-lib` via JNI + a small adapter layer (`chiaki-jni.c`, `video-decoder.c`, `audio-output.cpp`). We do the same with Swift + `ChiakiBridgeC`.
- Patching `lib/` would split it from upstream; that path leads to silent protocol drift and makes upstream PRs harder.

**Trade-off accepted:** we inherit `lib/`'s C surface and its dependency footprint (OpenSSL, libcurl, libevent, json-c, miniupnpc, opus, jerasure, nanopb). Cross-compiling that for tvOS arm64 is non-trivial but a one-time cost — see [`reference/build-deps.md`](reference/build-deps.md).

## Swift + C split (not pure Swift, not pure C)

**Decision:** Application, UI, networking sockets that talk to AppleAPIs, and media decode/render in Swift; protocol parsing, AES crypto, GMAC, FEC, Opus, Takion in [`../../lib/`](../../lib/) (C, upstream). A small bridge in [`../ChiakiBridgeC/`](../ChiakiBridgeC/) routes callbacks Swift can't take directly.

**Considered:**
- Pure Swift end to end (would have meant re-implementing the protocol — see above).
- Pure C with a thin Swift launcher (would have surrendered SwiftUI + GameController integration; the desktop's QML setup proves this isn't the right shape).

**Why:**
- The hot path (UDP receive → GMAC verify → AES-CTR decrypt → FEC decode → handoff to VideoToolbox) needs **zero allocations**. Upstream `lib/` already runs allocation-free on this path; keeping it in C preserves that.
- Apple frameworks (VideoToolbox, Metal, AudioUnit, GameController) have C-callable APIs but the most ergonomic surface is Swift — and SwiftUI + Combine on tvOS is genuinely the right fit for the menu/host-list UI.

**Confirmed:** consistent with the [`../../android/`](../../android/) port's split (Kotlin + JNI + chiaki-lib).

## Scope — LAN-only, no PSN OAuth, no App Store

**Decision:** ChiakiTV is a personal-use port. It targets Stephano's living room only. Out of scope:

- PSN OAuth (used by `gui/src/qml/PSNLoginDialog.qml` to retrieve an account ID).
- Remote Play over the Internet (RUDP / STUN / hole-punch — `lib/src/remote/holepunch.c`).
- App Store distribution (TestFlight / direct device install only).
- PS4 / older Apple TVs.
- Microphone + voice chat (Apple TV has no built-in microphone).

**Why:**
- Each out-of-scope item is a substantial engineering surface that exists for product/market reasons rather than personal-use reasons. PSN OAuth alone implies hosting `WKWebView` content, persisting cookies, handling Sony auth-flow changes — none of which improves a living-room PS5-on-the-same-LAN experience.
- The original port investigation (`../TVOS_PORT_INVESTIGATION.md` §6) flagged AGPLv3 vs. App Store as an open question. Avoiding the App Store side-steps that entirely.

**Trade-off accepted:** ChiakiTV cannot be used to play remotely from another house, won't be on the App Store, and has no voice chat. All three are by design.

## Prefill PSN account ID, no OAuth

**Decision:** the PSN account ID required by the registration protocol (`lib/src/regist.c`, the 8-byte field encoded into the inner-payload AES-CFB128 block) is **prefilled** in ChiakiTV settings rather than retrieved via PSN OAuth.

**How to get the account ID for prefill:** run desktop chiaki-ng on macOS / Linux / Windows, register with the PS5 there once, then read the registered host's `account_id` from the desktop's settings (`~/Library/Preferences/com.chiaki.Chiaki.plist` on macOS) and copy it into ChiakiTV's settings.

**Considered:**
- Implementing the full OAuth flow with `ASWebAuthenticationSession` (the original investigation §3.5).
- Using the desktop-style web flow in a tvOS browser — but tvOS has no `WKWebView` for general browsing.

**Why:**
- The OAuth flow exists to bootstrap the account ID. Once you have it, you don't need OAuth again — the registration protocol consumes the 8-byte ID, not the OAuth token.
- A personal-use, single-user, single-LAN port has zero value-add from automating the bootstrap. Stephano types the ID once.
- Removes the entire `ASWebAuthenticationSession` + cookie-store + redirect-URI integration from the project.

**Trade-off accepted:** users who want to use ChiakiTV as their first chiaki-ng install have to acquire the account ID from somewhere. They can use a desktop chiaki-ng install or the standalone `psn-account-id.py` / `.go` scripts (`../../scripts/`).

## Apple TV 4K 3rd gen only (A15 Bionic), tvOS 17+

**Decision:** Target tvOS 17+ on Apple TV 4K 3rd gen (2022, A15 Bionic). Older Apple TV models are not supported.

**Considered:** broadening to Apple TV 4K 1st/2nd gen (A10X / A12), or tvOS 16.

**Why:**
- A15's HEVC decoder handles 4K60 HDR with headroom. A10X tops out around 1080p60 HEVC and struggles with 4K HDR HDCP gates.
- DualSense haptic and adaptive-trigger APIs landed in `GameController.framework` on tvOS 14.5+; many of the supporting APIs (`GCDualSenseAdaptiveTrigger`, `GCHapticEngine`) stabilized in tvOS 17.
- This is a personal-use project on Stephano's specific hardware — broader compatibility is a non-goal that costs build matrix complexity.

**Confirmed:** matches the sibling [`../../../ps-remote-play/`](../../../ps-remote-play/) project's hardware target.

## PS5 only

**Decision:** PS5 (Takion v12) only. PS4 / PS4 Pro out of scope.

**Considered:** dual-stack v9 + v12.

**Why:**
- v9 vs. v12 differ in AV packet header layout, codec (H.264 vs. HEVC), and a handful of control-plane shapes. `lib/` already supports both, but the tvOS app would need both code paths through video / audio pipeline configuration.
- Apple TV 4K's A15 is fastest at HEVC. The PS4 path would be tax on every change for a console that streams sub-1080p H.264.
- Same as ps-remote-play: one console, one client, one symmetric configuration.

## PS5 Remote Play caps at 1080p — defaults target 1080p60 HDR, not 4K60 HDR

**Decision:** the streaming defaults target **1080p60 HEVC HDR**, not 4K. The `.res2160p` enum case stays in `VideoResolution` for users who want to experiment, but the shipped default is `.res1080p`.

**When:** 2026-05-07, after [run7](reports/2026-05-07-01-30-run7.md).

**Why:**
- PS5 Remote Play does not stream 4K. The PS5 accepts the launch spec at the protocol level (BANG fires) and then its `Nagare` / `AvCap` video pipeline fails with `InitResult:-6`, terminating the stream connection (run7 logs).
- Upstream chiaki-ng's UI caps at 1080p ([`gui/src/settings.cpp:454`](../../gui/src/settings.cpp), [`lib/src/session.c:92-122`](../../lib/src/session.c)) for exactly this reason — they never let users try 4K because the protocol rejects it.
- `video_profile_auto_downgrade=true` in [`ctrl.c:1442-1461`](../../lib/src/ctrl.c) only handles **PS4** server types (server_type 0/1) — there is no `server_type == 2 && height > 1080` downgrade branch. We can't lean on it.
- HDR (BT.2020 / SMPTE-2084 PQ) at 1080p60 *is* supported by PS5 Remote Play and is exactly what the Phase 2 HDR pipeline (HDR10 colorimetry on `CMFormatDescription`, BT.2020 PQ Metal render path, `AVDisplayCriteria(refreshRate:formatDescription:)`) was built for.

**Bitrate is a cap, not a target:** the `bitrate` field on `ChiakiConnectVideoProfile` becomes `bwKbpsSent` in the launch spec ([`lib/src/launchspec.c:24`](../../lib/src/launchspec.c)) — it tells the PS5 "I (the client) can absorb up to this much bandwidth." The PS5 then chooses the actual encoded bitrate up to the cap based on scene complexity, codec, and HDR overhead. So:
- A higher cap on a wired GbE link is essentially free — the PS5 won't waste bits if it doesn't need them.
- HDR's PQ encoding wants ~30–50% more bits than equivalent SDR for the same perceived quality.
- Upstream's 15 Mbps preset is sized for SDR over Wi-Fi. Our 30 000 kbps default leaves the encoder headroom for 1080p60 HDR on a wired LAN where we have it.

Do not "match upstream's 15 Mbps" mechanically — that's the SDR-1080p preset.

**How to apply:** if a future audit suggests bumping resolution back to 2160p, point them at run7 and the `ctrl.c:1442-1461` analysis. If the future audit suggests dropping bitrate to 15 000, point them at the cap-vs-target paragraph above.

## Build system: XcodeGen (`project.yml`) + SPM (`Package.swift`)

**Decision:** XcodeGen produces `ChiakiTV.xcodeproj` from `project.yml` for the full app. SPM's `Package.swift` exists separately so the C bridge can be unit-tested headlessly with `swift test`.

**Considered:**
- Pure Xcode (commit the .xcodeproj). Rejected — UUIDs churn, dirty diffs.
- Pure SPM. Rejected — SPM cannot produce a tvOS app target with entitlements.
- CMake (the path the rest of chiaki-ng uses). Rejected — less ergonomic for SwiftUI + entitlements + asset catalogs than Xcode-native; and we want to keep the Apple-side build separate from the cross-platform CMake build.

**Why:** dual-build keeps app development fast (Xcode + Previews) and keeps CI / pre-commit hooks fast (SPM-only test runner doesn't need a tvOS simulator).

**Confirmed:** matches the sibling [`../../../ps-remote-play/`](../../../ps-remote-play/) project's build setup.

## `tvos/` lives inside the chiaki-ng repo (not a separate repo)

**Decision:** ChiakiTV ships as a `tvos/` subdirectory of the main chiaki-ng repository, alongside `android/`, `switch/`, `gui/`, `cli/`, and `lib/`.

**Considered:** a separate `chiaki-tv` repository that pins chiaki-ng as a submodule.

**Why:**
- The other frontends are in-tree (`android/`, `switch/`). Symmetry argues for tvOS doing the same.
- Co-located source means upstream protocol changes and tvOS frontend changes can land in one commit when they're related.
- Reusing `lib/` works without any submodule machinery — the bridge just compiles it via the existing CMake or via a static archive built once and dropped in `Vendors/`.

**Trade-off accepted:** the chiaki-ng repo grows another frontend. That's already the model.

## Auto-memory at `~/.claude/.../memory/` is not used; `docs/` is the persistence layer

**Decision:** All durable knowledge about this port lives in version-controlled docs under `tvos/docs/`. Claude's auto-memory system is intentionally not used for tvOS-port content.

**When:** 2026-05-05 (project start).

**Why:**
- Memory is per-machine and per-Claude-install. Docs are version-controlled, reviewable, and survive across machines and sessions.
- A 52-day-old memory entry is indistinguishable from authoritative until it's wrong; in-tree docs get reviewed in commits.
- Pattern proven by the sibling [`../../../ps-remote-play/`](../../../ps-remote-play/): AGENTS.md as entry, `docs/` as the long-term store, CLAUDE.md as project-specific instruction.

**How to apply:** see [`../CLAUDE.md`](../CLAUDE.md) and [`../AGENTS.md`](../AGENTS.md). The user-level memory directory is fine for cross-project preferences but project-specific knowledge belongs in `docs/`.

## Stay on Swift 5 syntax — do not enable strict concurrency

**Decision:** Keep `SWIFT_VERSION = 5.9` and do not set `SWIFT_STRICT_CONCURRENCY = complete`.

**Why:** identical reasoning to the sibling ps-remote-play project — strict concurrency pushes toward actor isolation, which adds queue hops and `Sendable`-driven copies on every cross-domain call. The streaming hot path requires zero allocations and lock-free where possible. Use `final class … : @unchecked Sendable` plus explicit locks where shared mutable state crosses concurrency boundaries.

**Trade-off accepted:** when Apple eventually defaults `SWIFT_VERSION` to 6.0, this codebase will need a migration pass. Bounded cost — keep fixing Swift-6-error-in-waiting warnings as they appear during normal work.

## libchiaki dependencies — static link, prebuilt for tvOS arm64 (Phase 1 plan)

**Decision (planned):** OpenSSL, libcurl, libevent, json-c, miniupnpc, opus, jerasure, nanopb are built once for tvOS arm64 (device + simulator), checked into [`../Vendors/`](../Vendors/), and linked statically into `ChiakiTV.app`.

**Status:** **Phase 1 work — not yet implemented.** The Phase 0 scaffold doesn't link against any of these yet; `ChiakiBridgeC` is a stub.

**Considered:**
- Dynamic linking. Rejected — App Store would require static anyway, and bundling .dylibs into a tvOS .app adds a `LD_RUNPATH_SEARCH_PATHS` foot-gun.
- CocoaPods / SPM-managed deps. Rejected — none of these C libraries have official SPM / CocoaPods packaging for tvOS.
- A single XCFramework that bundles `chiaki-lib` + all its deps. **Strong candidate** for Phase 1; we'll decide between "static archives in Vendors/" and "single XCFramework" once we've cross-compiled OpenSSL once.

**Why:** Static + prebuilt avoids running `./configure` / `cmake` inside the Xcode build. The build script will live in [`../scripts/build-deps-tvos.sh`](../scripts/build-deps-tvos.sh) (Phase 1) and produce the contents of `Vendors/`.

## Cross-controller button-cluster mapping

**Decision:** map the GameController.framework button cluster to the PS5 button cluster by **physical position**, not by Apple's typed-accessor names. The full mapping:

| GameController input            | DualSense   | Xbox Series  | → PS5 button             |
| ------------------------------- | ----------- | ------------ | ------------------------ |
| `pad.buttonMenu`                | Options (R) | Menu (R)     | `CHIAKI_TV_BTN_OPTIONS`  |
| `pad.buttonOptions` (short tap) | Create (L)  | View (L)     | `CHIAKI_TV_BTN_SHARE`    |
| `pad.buttonOptions` (≥0.6 s hold)| Create (L) | View (L)     | `CHIAKI_TV_BTN_PS` (replaces SHARE while held) |
| `pad.buttonHome`                | PS          | Xbox / Guide | `CHIAKI_TV_BTN_PS` (only on Apple devices that surface the button — tvOS does not) |
| `"Button Touchpad"`             | Touchpad    | —            | `CHIAKI_TV_BTN_TOUCHPAD` |
| `GCInputButtonShare` (fallback) | Create *    | Share        | `CHIAKI_TV_BTN_TOUCHPAD` *only when no real touchpad exists* |

* On DualSense the same Create button surfaces under both `buttonOptions` *and* `GCInputButtonShare`. The `hasTouchpad` guard in `makeState` ensures the Share-fallback path is ignored on DualSense, so Create only fires once (as `SHARE`).

**When:** 2026-05-06.

**Why:**
- Apple's typed-accessor names (`buttonMenu`, `buttonOptions`) read in the opposite order to physical layout on DualSense (`Options` is the right button, `Create` is the left). Trust position over name — that's what users feel under their thumbs.
- PS5 games gate map / inventory / objective UI on a Touchpad press (Spider-Man, GoW Ragnarök, Horizon, etc.). Xbox controllers lack a touchpad, so Xbox Series's third "Share" button (between View and Menu) is remapped to it. The Xbox Series Share button physically sits on the right side of the cluster — the closest ergonomic substitute to the DualSense's right-touchpad-half.
- The Guide / PS button cannot be claimed on tvOS (system reserves it — see [`platform/tvos-constraints.md`](platform/tvos-constraints.md)). To give users a software route to the PS button anyway, holding `buttonOptions` past 0.6 s flips that button's mapping from `SHARE` to `PS` for as long as it's held. Pattern mirrors the existing Home long-press handler. Side-effect: a brief SHARE pulse fires before the long-press latches — acceptable, matches the symmetric Home behaviour.
- The earlier code mapped both `buttonMenu` and `buttonOptions` to `CHIAKI_TV_BTN_OPTIONS`, leaving `CHIAKI_TV_BTN_SHARE` unreachable from any controller. The position-based mapping fixes that.

**How to apply:** mapping lives in `ControllerService.makeState`; long-press detection lives in `handleOptionsPressChange`, set up alongside the Home handler in `wireExtendedGamepad`. The Share/Touchpad fallback requires the `GCXboxGamepad` profile to be exposed, which requires `GCSupportedGameControllers` absent / permissive in [`../ChiakiTV/Info.plist`](../ChiakiTV/Info.plist) (set 2026-05-06). Verify with the in-app diagnostic at **Settings → Controller**: pressing the View / Create button should light up `Button Options`, pressing Menu / Options should light up `Button Menu`, and on Xbox pressing Share should light up `Button Share`. The long-press → PS path doesn't show in the diagnostic (it's a synthesised software state), but the PS5 reaction is the test.

## No upstream contributions — fork-only, never propose PRs back to streetpea/chiaki-ng

**Decision:** any patches we make to upstream files (notably `lib/`) live exclusively on this fork (`ThaLuffy/chiaki-ng`). We do not plan, prepare, or propose pull requests back to `streetpea/chiaki-ng`. Claude must not suggest upstreaming anything, ever — not even as a "follow-up" or "consider it".

**When:** 2026-05-06.

**Why:**
- This is a personal-use port for one living room. The maintenance overhead of an upstream PR (review cycles, style alignment, justifying changes for the broader chiaki-ng audience) outweighs the benefit when the only consumer is this fork.
- The fork-and-rebase workflow handles drift just fine: when upstream `lib/src/takion.c` or others move, we rebase our patches on the new upstream. No coordination required.
- Hard rule #1 in [`../CLAUDE.md`](../CLAUDE.md) ("wrap, don't patch") still applies in spirit — patches to `lib/` should remain rare, scoped, and well-commented — but the destination of those patches is *our fork's branch*, not an upstream PR.

**How to apply:** when patching `lib/` (or any other directory we listed under "do not touch") becomes genuinely necessary, commit the patch on a tvos-port-adjacent branch in `origin` (the fork). Do not draft a PR description for upstream, do not suggest cherry-picking onto an `upstream-*` branch, do not say "worth upstreaming." Just land it on the fork.
