# Audio Pipeline

## End-to-end path

```
PS5 ─UDP─► chiaki-lib (../../lib/src/{takion,audioreceiver,opusdecoder}.c)
              │  GMAC + AES-CTR + Opus decode
              ▼  PCM frames: 48 kHz, S16, stereo
       ChiakiBridgeC audio sink callback (Phase 1)
              │
              ▼
       audioDispatchQueue (userInteractive)
              │  lock-free push into SPSC ring buffer
              ▼
       Utilities/RingBuffer.swift (depth ≥ 80 ms)
              │
              ▼  AudioUnit render callback (CoreAudio HAL thread)
       lock-free pop → output buffer → DAC → speakers
```

## Why AudioUnit instead of SDL2 / AVAudioEngine

- **SDL2** (`gui/src/streamsession.cpp:1175`): not officially supported on tvOS; the iOS port works but ties us to a third-party C library for what is fundamentally one ring buffer + one render callback. Net subtraction.
- **AVAudioEngine**: idiomatic Swift, but adds an unbounded queue between the source and the DAC and surfaces resampling / format conversion as graph nodes. Both work against the latency target. We bypass AVAudioEngine and talk directly to `AudioUnit` (`kAudioUnitSubType_RemoteIO`).
- **AudioUnit**: a ~10 ms round-trip render callback that wants a pre-filled output buffer. Lowest-overhead surface available, exactly the right shape for "drain a ring buffer into a render callback."

## Ring-buffer depth — 80 ms minimum

The sibling [`../../../ps-remote-play/`](../../../ps-remote-play/) project found through hardware testing that a 20 ms ring (2 frames at 10 ms Opus) overflows: chiaki-lib's `OpusJitterBuffer` drains 3+ frames in one tight loop after prefill. An 80 ms depth absorbed the burst.

Our ring buffer depth: **80 ms** (default). Reduce only after hardware-confirming a different bursting profile. See [`../../../ps-remote-play/docs/reference/known-issues.md#audio-ring-buffer-must-be-80-ms-not-20-ms`](../../../ps-remote-play/docs/reference/known-issues.md).

## Format negotiation

chiaki-lib emits PCM at the format announced in `ChiakiAudioHeader` (set by `STREAMINFO` from the PS5). For PS5 v12 this is always:

- 48,000 Hz
- S16 little-endian
- 2 channels (stereo)
- 240 samples per Opus frame (= 5 ms) or 480 (= 10 ms) depending on negotiation

The `AudioUnit` is configured to match. No resampling on the playback path.

## No microphone / no echo cancellation

Apple TV has no built-in microphone, and the DualSense's mic isn't surfaced via tvOS APIs. We send silence packets on the mic channel (chiaki-lib accepts this via `chiaki_audiosender_*`).

This means the Speex DSP echo-cancel and noise-suppress code in [`../../gui/src/streamsession.cpp:263-267`](../../gui/src/streamsession.cpp) is dead code on tvOS. We don't compile it.

## DualSense audio-channel haptics — handled by tvOS, not by us

The PS5 sends DualSense haptics as a separate audio stream (`gui/src/streamsession.cpp:1561` runs an `SDL_AudioCVT` to resample 3 kHz → 48 kHz and pipes it through a separate audio device). On tvOS, the DualSense is connected directly to the Apple TV via Bluetooth, and the OS routes haptics + adaptive triggers through `GameController.framework` (`GCDualSenseGamepad.haptics`, `GCDualSenseAdaptiveTrigger`). The audio-channel haptics path doesn't apply here.

That gives us a sizeable simplification vs. the desktop: no haptics audio device, no `SDL_AudioCVT`, no Speex, no echo cancellation, no microphone setup. Just one ring buffer + one AudioUnit.

## What goes wrong here

- **Underrun stutter**: ring depth too small, or audio queue starves between Opus frames.
- **Drift**: source clock (PS5) and sink clock (Apple TV DAC) aren't locked. Don't try to resample to fix it — the right move is to drop a frame at ring overflow and pad with PLC at ring underflow. Chiaki-ng's PLC is built into `OpusJitterBuffer` (which we'll port via the bridge in Phase 1).
- **AudioUnit configuration mismatch**: if the format we configure doesn't match what the PS5 sends, the render callback gets garbage. Always pull the format from `ChiakiAudioHeader`, not from defaults.

Document anything you hit in [`../reference/known-issues.md`](../reference/known-issues.md).
