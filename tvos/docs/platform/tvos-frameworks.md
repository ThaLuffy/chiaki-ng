# tvOS Frameworks

What we use from Apple's SDK and how. Phase 1 will fill these in with concrete API call traces; Phase 0 captures the picks.

## VideoToolbox

- **What**: HW HEVC / H.264 decode.
- **Why this and not FFmpeg**: see [`../architecture/video-pipeline.md`](../architecture/video-pipeline.md).
- **Key APIs**: `VTDecompressionSessionCreate`, `VTDecompressionSessionDecodeFrame`, `kVTDecompressionPropertyKey_RealTime`, `kVTDecompressionPropertyKey_OutputPoolRequestedMinimumBufferCount`.
- **Output**: `CVPixelBuffer`, IOSurface-backed, NV12 (8-bit) or P010 (10-bit HDR).

## Metal / MetalKit / CoreVideo

- **What**: GPU upload + render of decoded `CVPixelBuffer`.
- **Why this and not Vulkan/MoltenVK**: native, no MoltenVK overhead, no validation layer to ship, and we don't need libplacebo's feature set.
- **Key APIs**: `CAMetalLayer`, `CAMetalDisplayLink` (tvOS 17+), `CVMetalTextureCache`, `MTLDevice`, `MTLRenderPipelineState`, custom YUV→RGB shader.
- **Drawable count**: `maximumDrawableCount = 2`. See [`../optimization/latency-strategy.md`](../optimization/latency-strategy.md).

## GameController

- **What**: DualSense / DualShock 4 input, haptics, adaptive triggers.
- **Why this and not SDL2**: native; SDL2's tvOS port is partial (audio works, controller works less well, joystick HID layer doesn't surface DualSense haptics the way `GCDualSenseGamepad` does).
- **Key APIs**: `GCController.controllers`, `GCDualSenseGamepad`, `GCDualSenseAdaptiveTrigger`, `GCHapticEngine`.
- **Quirk to remember**: Siri Remote latches as `microGamepad` first if it connected before the DualSense. Always prefer `extendedGamepad`-profile controllers in `startMonitoring` and swap on connect — captured by the sibling project at [`../../../ps-remote-play/docs/platform/tvos-frameworks.md#gamecontroller-on-tvos`](../../../ps-remote-play/docs/platform/tvos-frameworks.md).
- **B-button-to-home suppression**: set `GCEventViewController.controllerUserInteractionEnabled = false` on the streaming view controller so DualSense PS-button + Xbox Guide don't bounce out of the app.

## AudioUnit / CoreAudio

- **What**: low-latency audio output sink.
- **Why this and not AVAudioEngine**: no graph, no internal queueing — just a render callback. Lowest possible round-trip.
- **Key APIs**: `AudioComponentInstanceNew(kAudioUnitSubType_RemoteIO)`, `kAudioUnitProperty_StreamFormat`, `kAudioUnitProperty_SetRenderCallback`.
- **Format**: 48 kHz, S16 little-endian, stereo (matches the PS5's Opus output).

## Network.framework

- **What**: discovery (UDP broadcast), control TCP, optional but probably *not* the streaming UDP path.
- **Why partially**: Network.framework is great for orchestration but the sibling project found it too lossy at the streaming UDP path's scale. They moved that path to a BSD socket (`UDPStreamingSocket`) with `SO_RCVBUF = 4 MB` and `O_NONBLOCK` recv-drain — see [`../../../ps-remote-play/docs/optimization/network-optimization.md`](../../../ps-remote-play/docs/optimization/network-optimization.md). For the chiaki-ng port we sidestep this entirely: chiaki-lib's `lib/src/takion.c` and `lib/src/sock.h` already use `socket()` / `recv()` directly — we don't need to plug Network.framework into the streaming hot path.
- **Where Network.framework still helps**: discovery service (Phase 1) and any TCP control we need from Swift directly.

## CryptoKit

- **What**: nothing on the streaming hot path. chiaki-lib uses OpenSSL (or mbedTLS, depending on build flag) for AES, GMAC, ECDH.
- **Why mention it**: tvOS apps often default to CryptoKit. We don't, because the protocol layer has its own crypto and re-implementing it on the Swift side would duplicate hot-path code that's already in C.

## AVFoundation / AVKit

- **What**: minor — `AVDisplayCriteria` for HDR mode negotiation with the TV. Not for media playback.
- **Why this and not just Metal**: setting `UIWindow.avDisplayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate:formatDescription:)` is the only way to tell the Apple TV "ask the TV to switch to 60 Hz HDR" — without it the OS leaves the display in the user's home-screen mode and our HDR pixels get tone-mapped client-side.

## CoreHaptics

- **What**: per-controller haptics in `GCHapticEngine`. The DualSense engine is exposed as a `GCHapticEngine` instance via `GCDualSenseGamepad`.
- **What we don't do**: don't try to play haptic patterns on the Apple TV itself — it's a streaming box, not a haptic device.

## Accelerate

- **What**: vector-math primitives if we ever need them on the Swift side. Currently unused; listed in `project.yml` linked frameworks for future use.

## What we don't link

- **AVFoundation media playback** (`AVPlayer`): we own the decoder; no `AVAssetReader`, no `AVPlayerLayer`.
- **GLKit / OpenGL ES**: deprecated by Apple. Metal everywhere.
- **MultipeerConnectivity / Bonjour**: discovery uses UDP broadcast (chiaki-lib path). If multicast/mDNS becomes interesting, see the multicast-entitlement note in [`tvos-constraints.md`](tvos-constraints.md).
