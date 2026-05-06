# AGENTS.md — ChiakiTV (chiaki-ng tvOS port)

> **You are here.** This file is the entry point for any LLM agent (Claude, Cursor, etc.) working on the tvOS port. Read this first, then jump into the linked docs as needed. Do **not** reconstruct context from memory or assumptions — everything you need is in [`docs/`](./docs/).

## What this project is

ChiakiTV is a tvOS port of [`chiaki-ng`](../) (an open-source PlayStation Remote Play client). It is purpose-built for **Apple TV 4K 3rd gen (A15 Bionic)** to stream **PS5** Remote Play over **the local network only**. Personal-use, single-user, single-LAN — no PSN OAuth, no remote-over-internet hole-punching, no App Store distribution.

The implementation reuses the upstream chiaki-ng C protocol library wholesale and replaces only the platform-specific frontend:

- **Swift / SwiftUI** owns the app: UI, MVVM, view models, settings UI, GameController integration. Source: [`ChiakiTV/`](./ChiakiTV/).
- **chiaki-ng `lib/`** (existing, upstream) owns the protocol hot path: discovery, registration, RPCrypt, Takion, GKCrypt, Reed–Solomon FEC, Opus codec, controller serialization, RUDP, takion sequencing. Source: [`../lib/`](../lib/) — **do not vendor this; build it in place via the existing CMakeLists**.
- **ChiakiBridgeC** is a thin C shim Swift can't call directly (mostly C-callback-to-Swift-closure adapters). Source: [`ChiakiBridgeC/`](./ChiakiBridgeC/).
- **Apple frameworks** own the platform-native pieces: `VideoToolbox` for HEVC decode, `Metal` for render, `AudioUnit` for output, `GameController` for DualSense, `Network.framework` for socket I/O.

Why this scope and these picks: see [`docs/decisions.md`](./docs/decisions.md).

## Status at a glance

- **Phase 0 — Scaffolding (in progress).** Project skeleton, build files (XcodeGen `project.yml` + SPM `Package.swift`), AGENTS/README/CLAUDE/docs scaffold, stubbed Swift app + C bridge so `xcodegen generate` and `swift build` succeed without source code yet to do real work. Detail: [`docs/phases.md#phase-0--scaffolding`](./docs/phases.md#phase-0--scaffolding).
- **Phase 1 — Bridge + LAN streaming MVP (pending).** Cross-compile chiaki-ng `lib/` and its dependencies for tvOS, write the Swift ↔ C bridge, do `VTDecompressionSession`-based video render, `AudioUnit` audio out, single DualSense via `GameController.framework`, manual host entry only. Detail: [`docs/phases.md#phase-1--lan-streaming-mvp`](./docs/phases.md#phase-1--lan-streaming-mvp).
- **Phase 2 — DualSense haptics + adaptive triggers + 4K HDR (deferred).**
- **Out of scope (not deferred — explicitly dropped):** PSN OAuth, RUDP/STUN hole-punch, multicast/mDNS discovery beyond UDP broadcast, microphone/echo-cancel (Apple TV has no mic), App Store distribution, Sideload-without-cert. See [`docs/decisions.md#scope--lan-only-no-psn-oauth-no-app-store`](./docs/decisions.md#scope--lan-only-no-psn-oauth-no-app-store).

## Hard rules — non-negotiable

These are the rules every change is audited against.

1. **Reuse upstream chiaki-ng `lib/` whenever the protocol is involved.** The C protocol layer at [`../lib/src/`](../lib/src/) is the source of truth for *every* protocol value, packet shape, sequence number, key derivation, FEC layout, and timing constant. If a tvOS-specific need conflicts with the upstream layout, the answer is to wrap, not patch — patching `lib/` is a regression unless it's also valuable upstream and contributed there. Always cite the upstream file:line in commit messages and doc updates (e.g. `lib/src/takion.c:942`).
2. **Zero allocations on the streaming hot path** (UDP receive → GMAC verify → AES-CTR decrypt → FEC decode → `VTDecompressionSession` handoff). The chiaki-ng C path is already zero-alloc; the Swift bridge layer must not introduce `Data` / `Array` allocations on that path. Use `UnsafeMutableBufferPointer` views over caller-owned buffers.
3. **Hardware acceleration only** for AES (CommonCrypto, already used by chiaki-ng via OpenSSL on this platform), HEVC (VideoToolbox), and rendering (Metal). No software-decode fallback paths — the target hardware doesn't need them and they hide regressions.
4. **Zero-copy video** all the way from `CVPixelBuffer` (IOSurface-backed) → `CVMetalTextureCache` → `MTLTexture`. No CPU-side pixel manipulation.
5. **Send controller input immediately** on value change. Never batch, never coalesce, never debounce. Latency dominates correctness here.
6. **LAN-only / PS5-only / Apple-TV-3rd-gen-only.** If you find yourself adding a code path for Apple TV HD, PS4, or remote-play-over-internet, stop — it's out of scope. See [`docs/decisions.md#scope--lan-only-no-psn-oauth-no-app-store`](./docs/decisions.md#scope--lan-only-no-psn-oauth-no-app-store).
7. **Read upstream chiaki-ng before changing protocol-adjacent code.** The upstream lives in this same repo at [`../lib/src/`](../lib/src/) and [`../gui/src/`](../gui/src/) — both are reference implementations for what we replace. The desktop GUI also uses VideoToolbox via FFmpeg on macOS ([`../gui/src/qmlbackend.cpp:831`](../gui/src/qmlbackend.cpp)) and that path's choices are usually the right starting point.
8. **Lock-free where possible** on the data path. Ring buffers and atomic counters; if you reach for a mutex outside init/teardown, the design is wrong.

## Documentation map

### Cross-cutting

| Doc | When to read |
|---|---|
| [`docs/decisions.md`](./docs/decisions.md) | The *why* behind every non-obvious choice (Swift+chiaki-lib, LAN-only, PS5-only, Apple-TV-3rd-gen-only, prefilled accountID, build system, …) |
| [`docs/phases.md`](./docs/phases.md) | What's built, what's pending hardware verification, what's deferred |

### Protocol — [`docs/protocol/`](./docs/protocol/)

> All protocol facts are owned by upstream chiaki-ng `lib/`. The docs in this directory exist only to **summarize the upstream behavior with file:line citations** so an agent doesn't have to re-derive it. When the upstream shifts (e.g. a firmware update breaks the registration shape), update the upstream first, then re-cite here.

| Doc | Covers |
|---|---|
| [`overview.md`](./docs/protocol/overview.md) | Connection lifecycle, port assignments (`9302` discovery, `9295` registration/session, `9296` control, `9297` stream), protocol stack |
| [`discovery.md`](./docs/protocol/discovery.md) | UDP broadcast discovery on `:9302`, response parsing — citing `lib/src/discovery.c` |
| [`registration.md`](./docs/protocol/registration.md) | One-time pairing — citing `lib/src/regist.c` |
| [`takion-control.md`](./docs/protocol/takion-control.md) | INIT/COOKIE handshake, control channel — citing `lib/src/takion.c` and `lib/src/ctrl.c` |
| [`takion-stream.md`](./docs/protocol/takion-stream.md) | AV streaming, GKCrypt framing — citing `lib/src/takion.c` and `lib/src/gkcrypt.c` |

### Platform — [`docs/platform/`](./docs/platform/)

| Doc | Covers |
|---|---|
| [`apple-tv-hardware.md`](./docs/platform/apple-tv-hardware.md) | A15 Bionic capabilities: HEVC decode rates, Metal feature set, audio routing |
| [`tvos-frameworks.md`](./docs/platform/tvos-frameworks.md) | VideoToolbox, Metal, GameController, AudioUnit — what we use and how |
| [`tvos-constraints.md`](./docs/platform/tvos-constraints.md) | Sandbox, multicast entitlement (irrelevant for personal LAN dev builds), no-mic, suspend behavior |

### Architecture — [`docs/architecture/`](./docs/architecture/)

| Doc | Covers |
|---|---|
| [`system-architecture.md`](./docs/architecture/system-architecture.md) | Module boundaries (Swift app ↔ ChiakiBridgeC ↔ chiaki-lib), threading model, data flow |
| [`video-pipeline.md`](./docs/architecture/video-pipeline.md) | Network receive (in chiaki-lib) → callback → VTDecompressionSession → CVPixelBuffer → MTLTexture |
| [`audio-pipeline.md`](./docs/architecture/audio-pipeline.md) | Opus decode in chiaki-lib → PCM callback → AudioUnit ring buffer |
| [`bridge-layer.md`](./docs/architecture/bridge-layer.md) | The Swift ↔ C bridge: how callbacks are routed without per-frame allocations |

### Optimization — [`docs/optimization/`](./docs/optimization/)

| Doc | Covers |
|---|---|
| [`latency-strategy.md`](./docs/optimization/latency-strategy.md) | Latency budget, where the bridge cost is, why we don't add buffering |
| [`network-optimization.md`](./docs/optimization/network-optimization.md) | Socket buffer sizing, Wi-Fi 6 tuning, ECN/DSCP marking |

### Reference — [`docs/reference/`](./docs/reference/)

| Doc | Covers |
|---|---|
| [`upstream-mapping.md`](./docs/reference/upstream-mapping.md) | What upstream chiaki-ng files map to what tvOS-side modules. Read this before implementing any service. |
| [`build-deps.md`](./docs/reference/build-deps.md) | How OpenSSL, libcurl, libevent, json-c, miniupnpc, opus, jerasure, nanopb are cross-compiled for tvOS arm64 |
| [`known-issues.md`](./docs/reference/known-issues.md) | Quirks, workarounds, anything that surprised us |
| [`testing-strategy.md`](./docs/reference/testing-strategy.md) | Unit / integration / hardware-only test layering |
| [`glossary.md`](./docs/reference/glossary.md) | Terms and abbreviations |

## Repository structure

This `tvos/` directory sits inside the chiaki-ng repo alongside the existing `android/`, `switch/`, `gui/`, and `cli/` frontends. The shared `lib/` C protocol library is reused as-is.

```
chiaki-ng/                         (repo root — upstream chiaki-ng)
├── lib/                           (shared C protocol library — reused as-is)
├── gui/                           (existing desktop Qt frontend — reference only)
├── android/                       (existing Android JNI frontend — reference architecture)
├── switch/                        (existing Switch frontend — reference only)
├── cli/                           (existing CLI tools)
└── tvos/                          (← THIS PORT)
    ├── AGENTS.md                  (this file)
    ├── CLAUDE.md                  (Claude-specific instructions)
    ├── README.md                  (short human-facing intro)
    ├── docs/                      (knowledge base — see Documentation map above)
    │   ├── decisions.md           (ADR log)
    │   ├── phases.md              (implementation status)
    │   ├── protocol/              (upstream chiaki-ng protocol summaries with citations)
    │   ├── platform/              (Apple TV / tvOS specifics)
    │   ├── architecture/          (module / pipeline design)
    │   ├── optimization/          (perf strategies)
    │   ├── reference/             (upstream mapping, build deps, known issues, etc.)
    │   └── reports/               (per-test-run reports — see CLAUDE.md)
    ├── ChiakiTV/                  (tvOS app, Swift)
    │   ├── App/                   (entry point, AppState)
    │   ├── Views/                 (SwiftUI views + components)
    │   ├── ViewModels/            (MVVM)
    │   ├── Models/                (data models)
    │   ├── Services/              (discovery, session, video, audio, controller, settings)
    │   ├── Utilities/             (RingBuffer, AtomicCounter, ChiakiLogger)
    │   ├── Extensions/            (Swift extensions)
    │   ├── Resources/             (icons, etc.)
    │   ├── Assets.xcassets        (Apple TV icon stack)
    │   ├── Info.plist
    │   └── ChiakiTV.entitlements
    ├── ChiakiBridgeC/             (thin C shim Swift can't call directly)
    │   ├── include/ChiakiBridgeC/ (public headers + module.modulemap)
    │   └── src/                   (.c implementation)
    ├── Tests/                     (SPM unit + integration)
    │   ├── ChiakiBridgeCTests/    (C bridge, callable from Swift)
    │   └── ChiakiTVTests/         (Swift services)
    ├── Vendors/                   (prebuilt static deps for tvOS arm64 — populated in Phase 1)
    ├── project.yml                (XcodeGen — produces ChiakiTV.xcodeproj)
    ├── Package.swift              (SPM — for headless bridge tests)
    └── ChiakiTV.xcodeproj         (generated; do not edit by hand)
```

## How to work in this repo as an agent

1. **Start with this file**, then jump into the doc(s) most relevant to the task. Do not reconstruct context from past sessions or memory.
2. **Use `tvos/docs/` as your authoritative knowledge base.** There is **no** `~/.claude/.../memory/` for the tvOS port — see [`CLAUDE.md`](./CLAUDE.md) and [`docs/decisions.md#auto-memory-is-not-used-docs-is-the-persistence-layer`](./docs/decisions.md#auto-memory-is-not-used-docs-is-the-persistence-layer).
3. **If you learn something durable** (a new constraint, a fix's root cause, an upstream that changed): **update the relevant doc in the same edit pass.** Don't defer — the doc scaffold is the persistence layer.
4. **DRY — cross-reference instead of duplicating.** If two docs would say the same thing, one of them links to the other. Hard rules live here in AGENTS.md and are referenced from CLAUDE.md and the entity docs.
5. **Verify against upstream chiaki-ng `lib/` before changing anything protocol-adjacent.** The upstream is co-located in this repo — read [`../lib/src/<file>.c`](../lib/src/) and cite line numbers when documenting decisions. Hard rule #1.
6. **Don't guess for the user.** When implementation choices have credible alternatives, surface them as decision points rather than burying them as "Phase 2+ upgrades" — see [`CLAUDE.md`](./CLAUDE.md).

## Build & run

### Full app (XcodeGen + Xcode)

```bash
brew install xcodegen           # one-time
cd tvos
xcodegen generate               # generates ChiakiTV.xcodeproj from project.yml
open ChiakiTV.xcodeproj         # Xcode 15+
# Build target: ChiakiTV (Apple TV)
# Requires: Apple TV 4K 3rd gen device
```

### Bridge / Swift services only (SPM, headless)

```bash
cd tvos
swift test
```

> **Note**: `swift test` runs only the headless tests. The full streaming pipeline cannot run in a simulator — VideoToolbox HW decode, GameController, and the actual PS5 require real hardware.

Build-system files: [`project.yml`](./project.yml) (XcodeGen spec), [`Package.swift`](./Package.swift) (SPM manifest), [`ChiakiTV/Info.plist`](./ChiakiTV/Info.plist), [`ChiakiTV/ChiakiTV.entitlements`](./ChiakiTV/ChiakiTV.entitlements).

## Code conventions

- **Swift**: modern async/await, `@MainActor` on view models, SwiftUI for all UI. Swift 5.9 syntax — strict concurrency is **not** enabled (see [`docs/decisions.md`](./docs/decisions.md)).
- **C bridge**: `snake_case`, `chiaki_tv_` prefix on all public symbols, caller-allocated buffers on the hot path. See [`docs/architecture/bridge-layer.md`](./docs/architecture/bridge-layer.md).
- **Naming**: file matches its primary type (`VideoDecoder.swift` → `class VideoDecoder`).
- **Error handling**: Swift `throws` for recoverable, `fatalError` for programmer errors. C bridge returns `int` (0 = success) and writes errors via the chiaki-ng log callback.
- **Logging**: `ChiakiLogger` (Swift) wraps the chiaki-ng `ChiakiLog` callback so all log lines (Swift and C) flow through one PSLog pipeline with categories (`network`, `video`, `audio`, `controller`, `session`).

## Protocol stack at a glance

> Owned by upstream chiaki-ng `lib/`. We do not re-implement this; we drive it.

```
Discovery (UDP :9302 PS5 / :987 PS4)         lib/src/discovery.c
  → Registration (HTTP :9295)                lib/src/regist.c
  → Session bring-up                         lib/src/session.c
  → Control (TCP, RPCrypt + INIT/COOKIE)     lib/src/ctrl.c, lib/src/takion.c
  → Stream (UDP, GKCrypt AES-CTR + GMAC)     lib/src/takion.c, lib/src/gkcrypt.c
  → Video receiver                            lib/src/videoreceiver.c
  → Audio receiver (Opus)                     lib/src/audioreceiver.c, lib/src/opusdecoder.c
  → Controller sender                         lib/src/feedbacksender.c, lib/src/controller.c
  → FEC                                       lib/src/fec.c
```

Full lifecycle and packet flow: [`docs/protocol/overview.md`](./docs/protocol/overview.md).

## Glossary

| Term | Meaning |
|---|---|
| **chiaki-lib** | The C protocol library at `../lib/`. Reused wholesale by this port. |
| **Takion** | The PS5's custom UDP-based streaming protocol. Implemented by `lib/src/takion.c`. |
| **RPCrypt** | The control-channel cipher (AES-128-CFB128). Implemented by `lib/src/rpcrypt.c`. |
| **GKCrypt** | The streaming-channel cipher (AES-128-CTR + truncated 4-byte GMAC). Implemented by `lib/src/gkcrypt.c`. |
| **FEC** | Reed–Solomon erasure coding (Jerasure). Implemented in `lib/src/fec.c` via `third-party/jerasure/`. |
| **DualSense** | Sony's PS5 controller. Adaptive triggers, haptic feedback, motion sensors, touchpad. The only controller ChiakiTV supports. |
| **HEVC / H.265** | The video codec the PS5 uses. Hardware-decoded by VideoToolbox on A15. |
| **VideoToolbox** | Apple's hardware-accelerated video coding framework. |
| **GameController** | Apple's controller framework. Native DualSense + DualShock 4 + Xbox support since tvOS 14.5. |
| **Account ID** | The 8-byte PSN account ID needed by the registration protocol. **Prefilled in this port** rather than retrieved via OAuth — see [`docs/decisions.md#prefill-account-id-no-oauth`](./docs/decisions.md#prefill-account-id-no-oauth). |
| **Bridge** | The Swift ↔ C glue layer. Lives in `ChiakiBridgeC/` and is the only place Swift talks to chiaki-lib. |
