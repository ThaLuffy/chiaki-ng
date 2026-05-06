# Latency Strategy

Target: **< 16 ms added latency** vs. desktop chiaki-ng on the same LAN, at 4K60 HDR.

## Latency budget (rough, per pipeline stage)

| Stage | Typical | Hard cap | Notes |
|---|---|---|---|
| LAN one-way (Wi-Fi 6) | 2 ms | 5 ms | jitter is the killer; mean is fine |
| chiaki-lib UDP recv → decrypt → FEC → NAL emit | 0.5 ms | 1 ms | C path, allocation-free; same as desktop |
| Bridge: NAL → `videoDispatchQueue` → `VTDecompressionSessionDecodeFrame` | 0.1 ms | 0.5 ms | one `dispatch_async`, no copy |
| VideoToolbox HEVC HW decode (4K60) | 1–2 ms | 4 ms | A15 Bionic, RealTime hint set |
| Output handler → atomic store into `pendingPixelBuffer` | < 0.1 ms | 0.1 ms | single-slot, lock-free |
| `CAMetalDisplayLink` tick + Metal encode + present | 0.5 ms | 1 ms | YUV→RGB shader, no compute |
| Compositor + scan-out | 8.3 ms (60 Hz) | 16.7 ms | one frame |
| **Total added** | **~12 ms** | **< 28 ms** | |

The goal is **not** "lower than physically possible" — it's **lower than desktop chiaki-ng**, which has Qt event loop hops, libplacebo Vulkan submission overhead, and MoltenVK translation cost.

## Where the budget is spent and why

### `OutputPoolRequestedMinimumBufferCount = 2`

`VTDecompressionSession`'s default output pool is sized for 3 simultaneous in-flight buffers. For our renderer (single-slot drop-newest), the third slot is pure latency — it just queues a buffer that will never be presented before the next one arrives. We pin it to 2.

### `CAMetalLayer.maximumDrawableCount = 2`

Same idea, drawable side. Default 3 = up to ~16 ms of compositor-side queue depth. With 2, the compositor holds at most one frame ahead of scan-out.

### `VTDecompressionSessionDecodeFrame` synchronous

We call it with `flags = []` (synchronous) on a dedicated `userInteractive` queue. The output handler runs *before* `DecodeFrame` returns. Why synchronous? Because async decode would fan out work across an internal queue we don't control, with unbounded buffering in between.

### No pre-decoder backpressure

Hard-learned lesson from the sibling [`../../../ps-remote-play/`](../../../ps-remote-play/): adding an `InFlightCounter` + IDR-detection drop layer in front of the decoder masks upstream issues and introduces an accounting drift class of bugs. The renderer's single-slot `pendingPixelBuffer` is the natural drop-newest boundary.

If the decoder genuinely can't keep up at full quality, the right move is to ask the PS5 to lower the bitrate via the control channel — not silently drop frames client-side.

### Receive loop on a dedicated GCD queue

The streaming UDP recv loop (chiaki-lib's) runs on its own thread inside `lib/`. Our bridge dispatches **only** to dedicated `userInteractive` GCD queues (`videoDispatchQueue`, `audioDispatchQueue`). Never to `Task` priority pools — those are shared with arbitrary work and introduce pool-contention latency under load. Sibling project rediscovered this the hard way and documented it: [`../../../ps-remote-play/docs/decisions.md#recv-loop-on-dedicated-gcd-queue-not-swift-task`](../../../ps-remote-play/docs/decisions.md).

## What we *don't* do

- **No frame mixing / frame interpolation.** Desktop chiaki-ng has frame-mixer settings under libplacebo. The default is now off (per [`../../doc/release_notes.md`](../../doc/release_notes.md)) and we don't ship the option at all.
- **No deinterlacing.** PS5 source is progressive HEVC.
- **No tone-mapping by default.** HDR10 → display-as-HDR10. The TV does the work.
- **No upscaling.** PS5 emits the resolution we ask for in the launch spec; we render 1:1 (or letterbox if the user enabled stretch/zoom modes — Phase 2).

Each of these is a latency line item we deliberately don't pay.

## Hardware findings (to be filled in Phase 1)

The sibling project's hardware-test findings for the same target hardware are at [`../../../ps-remote-play/docs/optimization/latency-strategy.md#phase-e-hardware-findings-2026-05-04`](../../../ps-remote-play/docs/optimization/latency-strategy.md). When we run the first hardware test of ChiakiTV, capture our equivalent findings here.
