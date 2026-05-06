# Known Issues

Quirks, workarounds, and edge cases. Append to this file as you hit them — that's how the next session learns from this one.

## Phase 0

Nothing yet — the scaffold builds clean.

## Phase 1

### Wi-Fi burst loss → FEC failure storm (run5, 2026-05-06)

**Symptom**: 1080p60 H.265 @ 15 Mbps streaming session stutters constantly. Per-frame loss up to 66% (`5+0 / 12+3` units received), FEC fails ≈once per second, IDR resync storm. Senkusha RTT 2.944 ms — the path is fine, the *receive* side is dropping bursts.

**Root causes** (two contributors, both fixed):

1. **`SO_RCVBUF` was set to 100 KiB** (`TAKION_A_RWND = 0x19000` at upstream `lib/src/takion.c:41`). At 15 Mbps that's ~50 ms of headroom; under any userspace preemption ≥50 ms the kernel UDP buffer overflows and packets are dropped before chiaki-lib ever sees them.
2. **Receive thread inherited default QoS class.** On Apple platforms the takion thread runs alongside the renderer/audio threads. Default `QOS_CLASS_DEFAULT` lets the scheduler preempt it under load, lengthening the gap between `recv()` calls and triggering #1.

**Fix** (deviates from "wrap, don't patch" hard rule — this is a true platform-specific upstream bug, change is small and self-contained):

- `lib/src/takion.c`: introduce `TAKION_SO_RCVBUF = 4 MiB`, decoupled from the protocol-level `TAKION_A_RWND` advertisement. Use it at the two `SO_RCVBUF` setsockopt sites. The protocol-level a_rwnd announcement is unchanged so flow-control semantics are preserved.
- `lib/src/takion.c`: at the start of `takion_thread_func`, on `__APPLE__` only, call `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)`. Matches the QoS class AVAudioEngine uses internally.

**Should be upstreamed.** Both changes benefit any chiaki-ng client on Apple platforms (and arguably elsewhere — the 100 KiB buffer is conservative for any modern host). Track on next sync from upstream so the patches don't get clobbered.

**Reference**: see [`../reports/2026-05-06-11-05-run5.md`](../reports/2026-05-06-11-05-run5.md) for the full diagnosis.

**Important caveat — these patches did NOT fix the run-5 stutter.** Run 6 (post-fix retest) showed the same 5–18% per-window loss pattern. The Ethernet-tether discriminator immediately afterward returned **0% loss**, confirming the dominant cause was Wi-Fi airtime burst loss between the simulator host and the PS5, not anything in the receive pipeline. The patches are correct upgrades (and necessary headroom in case the host *is* slow), but they were never on the critical path for this incident. See "Wi-Fi path is the limiting factor" below.

### Dev simulator is on a contended Wi-Fi path (run6, 2026-05-06)

**Symptom**: same 5–18% per-window loss as run 5, even with the run-5 receive-pipeline patches in place. Ethernet-tethering the dev Mac → **0% packet loss** at the same bitrate. The loss only appears when the simulator host's Wi-Fi link is in the path.

**Root cause**: this specific dev room has a lot of 2.4/5 GHz interference. The Mac shares airtime with everything else on the desk; a sustained 15 Mbps downlink to the PS5 wipes packet bursts even though Senkusha's single-MTU pings sail through.

**Implication for development testing**: when iterating on the simulator, prefer Ethernet-tether the Mac for like-for-like comparison against eventual Apple TV hardware. Wi-Fi runs from the simulator in this room are not a fair benchmark and should not drive code-side decisions on their own.

**Implication for production (Apple TV 4K in the living room)**: not yet measured. The expectation is that the deployment environment (Apple TV 4K dedicated to streaming, less radio contention than a developer's desk) will behave noticeably better than this dev path. Validate when hardware is in place; don't pre-emptively bake "wired-only" assumptions into user-facing docs.

**Reference**: [`../reports/2026-05-06-12-13-run6.md`](../reports/2026-05-06-12-13-run6.md).

## Anticipated for Phase 1

These are issues the sibling [`../../../ps-remote-play/`](../../../ps-remote-play/) project hit during its hardware integration. If we hit them too, document them here with links to the actual fix. If we *don't* hit them, that's also worth a note (suggests the chiaki-lib path handles them and our re-implementation didn't).

### Audio ring buffer must be ≥ 80 ms

Sibling: 20 ms (2 Opus frames) ring overflowed because chiaki-ng's `OpusJitterBuffer` drains 3+ frames in one tight loop after prefill. Fix: 80 ms ring. See [`../../../ps-remote-play/docs/reference/known-issues.md#audio-ring-buffer-must-be-80-ms-not-20-ms`](../../../ps-remote-play/docs/reference/known-issues.md).

We're going to be running the same `OpusJitterBuffer` (it lives in chiaki-ng `lib/`), so this is likely to bite us identically.

### STREAMINFO video header must prime the decoder before the first frame

PS5 sends VPS / SPS / PPS **out-of-band** in the `STREAMINFO` control message's `ResolutionPayload.video_header`, not inline in IDR frames. Without priming `VTDecompressionSession` from those parameter sets, every frame returns `vps=-1 sps=-1 pps=-1` and the session is never created.

Plan: the bridge surfaces a `set_video_header(_:)` method that the Phase 1 `VideoDecoder` calls before the first `VTDecompressionSessionDecodeFrame`.

### Siri Remote latches as the input controller

`GCController.controllers` returns the Siri Remote first if it was paired before the DualSense. Plan: prefer `extendedGamepad`-profile controllers in `startMonitoring` AND swap on connect.

### B-button-exits-to-Home

DualSense PS button + Xbox Guide bounce out of the app by default. Fix: `GCEventViewController.controllerUserInteractionEnabled = false` on the streaming view controller.

### Discovery broadcast may need the multicast entitlement

UDP broadcast on tvOS is in a gray zone. On personal-team-signed builds in tvOS 17 it works. If a future tvOS release closes this, we add `com.apple.developer.networking.multicast` to entitlements and request approval. Keep an eye on [`../platform/tvos-constraints.md#multicast--broadcast`](../platform/tvos-constraints.md).

### `NWConnection` is too lossy for the streaming UDP path

Sibling project found this. We sidestep it entirely because chiaki-lib uses BSD sockets directly via `lib/src/sock.h`. Don't try to "modernize" that.

## Process

When you find a real issue:

1. Document the symptom (what you saw, with timestamps and counts).
2. Document the root cause (file:line in our code or in `lib/`).
3. Document the fix (what changed, with a link to the commit).
4. Cross-reference from the relevant doc (e.g. an audio bug also gets noted in [`../architecture/audio-pipeline.md`](../architecture/audio-pipeline.md)).
