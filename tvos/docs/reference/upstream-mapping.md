# Upstream Mapping

Where does each upstream chiaki-ng `lib/` file fit in the tvOS-port world? This map is the answer to "I need to do X — which `lib/` file owns X, and which tvOS-side service drives it?"

Read this before implementing any service in [`../../ChiakiTV/Services/`](../../ChiakiTV/Services/).

## Discovery

| Upstream | tvOS service (Phase 1) |
|---|---|
| [`../../../lib/src/discovery.c`](../../../lib/src/discovery.c) | `Services/Discovery/DiscoveryService.swift` |
| [`../../../lib/src/discoveryservice.c`](../../../lib/src/discoveryservice.c) | (same) |
| [`../../../lib/include/chiaki/discovery.h`](../../../lib/include/chiaki/discovery.h) | imported via the bridge |

## Registration

| Upstream | tvOS service (Phase 1) |
|---|---|
| [`../../../lib/src/regist.c`](../../../lib/src/regist.c) | `Services/Session/RegistrationService.swift` |
| [`../../../lib/src/rpcrypt.c`](../../../lib/src/rpcrypt.c) | reused as-is by chiaki-lib internally |
| [`../../../lib/include/chiaki/regist.h`](../../../lib/include/chiaki/regist.h) | imported via the bridge |

## Session lifecycle

| Upstream | tvOS service (Phase 1) |
|---|---|
| [`../../../lib/src/session.c`](../../../lib/src/session.c) | `Services/Session/SessionManager.swift` |
| [`../../../lib/src/streamconnection.c`](../../../lib/src/streamconnection.c) | (same) |
| [`../../../lib/src/ctrl.c`](../../../lib/src/ctrl.c) | `Services/Session/SessionManager.swift` (events + errors only) |
| [`../../../lib/src/takion.c`](../../../lib/src/takion.c) | runs internally; no Swift-side touchpoints |
| [`../../../lib/src/gkcrypt.c`](../../../lib/src/gkcrypt.c) | (same — internal) |

## Video

| Upstream | tvOS service (Phase 1) |
|---|---|
| [`../../../lib/src/videoreceiver.c`](../../../lib/src/videoreceiver.c) | upstream emits NAL units → bridge → `Services/Video/VideoDecoder.swift` |
| [`../../../lib/src/frameprocessor.c`](../../../lib/src/frameprocessor.c) | upstream-internal |
| [`../../../lib/src/fec.c`](../../../lib/src/fec.c) | upstream-internal |
| [`../../../lib/src/bitstream.c`](../../../lib/src/bitstream.c) | upstream-internal (HEVC ref-frame invalidation) |
| [`../../../lib/src/ffmpegdecoder.c`](../../../lib/src/ffmpegdecoder.c) | **NOT USED** — tvOS bypasses FFmpeg, feeds NAL units straight into VideoToolbox. Compile-flag-disabled in our build. |

`Services/Video/VideoDecoder.swift` (Phase 1) owns the `VTDecompressionSession`. `Services/Video/MetalRenderer.swift` (Phase 1) owns the `CAMetalLayer` and the YUV→RGB shader.

## Audio

| Upstream | tvOS service (Phase 1) |
|---|---|
| [`../../../lib/src/audioreceiver.c`](../../../lib/src/audioreceiver.c) | upstream emits decoded PCM → bridge → `Services/Audio/AudioPlayer.swift` |
| [`../../../lib/src/opusdecoder.c`](../../../lib/src/opusdecoder.c) | upstream-internal |
| [`../../../lib/src/audiosender.c`](../../../lib/src/audiosender.c) | sends silence packets — no mic on Apple TV |
| [`../../../lib/src/opusencoder.c`](../../../lib/src/opusencoder.c) | unused (no mic) |

## Controller

| Upstream | tvOS service (Phase 1) |
|---|---|
| [`../../../lib/src/controller.c`](../../../lib/src/controller.c) | upstream-internal state machine |
| [`../../../lib/src/feedbacksender.c`](../../../lib/src/feedbacksender.c) | upstream-internal — receives controller-state updates from us |
| [`../../../lib/src/feedback.c`](../../../lib/src/feedback.c) | upstream-internal |
| [`../../../lib/include/chiaki/controller.h`](../../../lib/include/chiaki/controller.h) | imported via the bridge — defines `ChiakiControllerState` |

`Services/Controller/ControllerManager.swift` (Phase 1) owns `GCController` discovery + `GCDualSenseGamepad` value-changed callbacks → bridge → `chiaki_session_set_controller_state`.

## Settings / persistence

| Desktop | tvOS service (Phase 1) |
|---|---|
| [`../../../gui/src/settings.cpp`](../../../gui/src/settings.cpp) (`QSettings`) | `Services/Settings/SettingsStore.swift` (Codable + `FileManager.urls(for:.applicationSupportDirectory)`) |
| [`../../../gui/src/host.cpp`](../../../gui/src/host.cpp) (`RegisteredHost`) | `Models/RegisteredHost.swift` (Codable) |

We don't share `QSettings` format; we use JSON. The user copies in the account ID once and otherwise the file is opaque.

## What is *not* mapped

- libplacebo / Vulkan / MoltenVK: not used.
- FFmpeg: not used.
- SDL2 (audio + gamepad): not used; replaced by AudioUnit + GameController.
- QtWebEngine (PSN OAuth): not used; account ID prefilled.
- miniupnpc / libevent (RUDP / hole-punch): not used; LAN-only.
- Speex DSP: not used; no mic.
- setsu / steamdeck_native: not used; not Steam Deck.

The `tvos/Vendors/` directory in Phase 1 will hold static archives for the deps that *are* used (OpenSSL, libcurl, libevent for some chiaki-lib pieces, json-c, opus, jerasure, nanopb), or we'll find a way to cut more of those too. Detail: [`build-deps.md`](build-deps.md).
