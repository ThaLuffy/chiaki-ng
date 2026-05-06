# System Architecture

## Three-layer split

```
┌─────────────────────────────────────────────────────────┐
│ ChiakiTV (SwiftUI / UIKit, Swift 5.9)                   │
│   App / Views / ViewModels / Models                     │
│   Services (Swift wrappers around the bridge)           │
│   Utilities (logging, ring buffer, atomic counters)     │
└─────────────────────────────────────────────────────────┘
                          │ Swift ↔ C
┌─────────────────────────────────────────────────────────┐
│ ChiakiBridgeC (thin C glue Swift can't call directly)   │
│   Callback adapters (log / session events / video / …)  │
│   ChiakiLog → OSLog routing                             │
│   No protocol logic here                                │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│ chiaki-ng lib/ (../../lib/, C, upstream — REUSED)       │
│   session, ctrl, takion, regist, holepunch, opus*,      │
│   gkcrypt, rpcrypt, fec, controller, …                  │
└─────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────┐
│ tvOS / Apple frameworks                                 │
│   Metal · MetalKit · VideoToolbox · CoreVideo           │
│   AVFAudio · AudioUnit · AVAudioSession                 │
│   GameController · Network                              │
└─────────────────────────────────────────────────────────┘
```

The middle layer is intentionally tiny. It's not a re-implementation, it's not a feature layer — it's just the wrappers Swift can't take directly (C function-pointer typedefs that capture state, raw-buffer callbacks, etc.). See [`bridge-layer.md`](bridge-layer.md).

## Threading model (planned for Phase 1)

| Thread / Queue | Owner | What runs there |
|---|---|---|
| `MainActor` | Swift | UI, view models, app state |
| chiaki-lib internal threads | C | session, ctrl recv, takion recv, video receiver, audio receiver |
| `videoDispatchQueue` (tvOS-side, `userInteractive`) | Swift | feeding NAL units into `VTDecompressionSession`; the C callback dispatches onto this queue |
| `audioDispatchQueue` (tvOS-side, `userInteractive`) | Swift | feeding decoded PCM into `AudioUnit` ring buffer |
| Audio render callback | CoreAudio | pulling PCM samples for the next audio buffer (no allocations, lock-free read from the ring buffer) |
| Video output callback | VideoToolbox | receiving `CVPixelBuffer`; lock-free write into the renderer's single-slot `pendingPixelBuffer` |
| `CAMetalDisplayLink` | Metal | per-frame: read newest `pendingPixelBuffer`, encode to `MTLTexture`, present via `CAMetalLayer` |

Hard rule: the per-packet / per-frame path between chiaki-lib's receive thread and the renderer / audio sink **never returns to `MainActor`**. The Swift bridge has to be lock-free at that depth.

## Data flow — video

```
PS5 → UDP packet → chiaki-lib (../../lib/src/takion.c)
                 → GMAC verify (gkcrypt.c)
                 → AES-CTR decrypt (gkcrypt.c)
                 → FEC reassemble (videoreceiver.c, fec.c)
                 → NAL unit available
                                │
                                ▼ via ChiakiBridgeC video sample callback
                 dispatch_async on videoDispatchQueue
                                │
                                ▼
                 VTDecompressionSessionDecodeFrame (synchronous, output handler runs before return)
                                │
                                ▼ output handler
                 atomic store of CVPixelBuffer into MetalRenderer.pendingPixelBuffer
                                │
                                ▼ next CAMetalDisplayLink tick
                 read newest pendingPixelBuffer → MTLTexture → CAMetalLayer present
```

## Data flow — audio

```
PS5 → UDP packet → chiaki-lib (../../lib/src/takion.c)
                 → GMAC + decrypt (gkcrypt.c)
                 → audio receiver dispatch (audioreceiver.c)
                 → opus decoder (opusdecoder.c)
                 → 48 kHz stereo S16 PCM frame
                                │
                                ▼ via ChiakiBridgeC audio sink callback
                 lock-free write to ring buffer (Utilities/RingBuffer.swift)
                                │
                                ▼ AudioUnit render callback (CoreAudio thread)
                 lock-free read from ring buffer → render buffer
```

## Data flow — controller

```
DualSense → GameController.framework value-changed handler (Swift)
                                │
                                ▼ ImmediatelyOnChange
                 chiaki-lib API call via bridge (chiaki_session_set_controller_state)
                                │
                                ▼ chiaki-lib feedback sender thread
                 packetize → encrypt (gkcrypt) → send to PS5
```

Hard rule #5: the input → packet → wire path never debounces, batches, or coalesces.

## Module boundaries

- **App** — entry point, scene, AppState. Knows about navigation.
- **Views** — SwiftUI. Dumb. Reads view models, dispatches user intent.
- **ViewModels** — observable state for views. `@MainActor`.
- **Models** — Codable data types (Host, RegisteredHost, settings). No behavior.
- **Services** — the Swift face of each subsystem. Each service wraps one piece of chiaki-lib via the bridge.
  - `Discovery/DiscoveryService.swift` (Phase 1) — wraps `chiaki_discovery_service_*`
  - `Session/SessionManager.swift` (Phase 1) — wraps `chiaki_session_*`
  - `Video/VideoDecoder.swift` (Phase 1) — owns the `VTDecompressionSession`
  - `Video/MetalRenderer.swift` (Phase 1) — owns the `CAMetalLayer`
  - `Audio/AudioPlayer.swift` (Phase 1) — owns the `AudioUnit`
  - `Controller/ControllerManager.swift` (Phase 1) — owns `GCController` / `GCDualSenseGamepad`
  - `Settings/SettingsStore.swift` (Phase 1) — `Codable` + `FileManager`
- **Utilities** — `RingBuffer`, `AtomicCounter`, `ChiakiLogger`. No domain knowledge.
- **Extensions** — Foundation/SwiftUI extensions only.

## Where the desktop reference lives

The desktop GUI at [`../../gui/`](../../gui/) drives the same `lib/` we drive. When the orchestration shape is unclear (e.g. the ordering of registration → session-start → controller-connect events), the reference is:

- [`../../gui/src/streamsession.cpp`](../../gui/src/streamsession.cpp) — orchestration, ~2700 lines
- [`../../gui/src/qmlbackend.cpp`](../../gui/src/qmlbackend.cpp) — settings ↔ session bridge
- [`../../gui/src/qmlbackend.cpp:831`](../../gui/src/qmlbackend.cpp) — VideoToolbox decoder selection on macOS

Strip Qt + SDL2 from those, keep the chiaki-lib API calls, and you have the tvOS service implementation.
