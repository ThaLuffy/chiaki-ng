# Apple TV Hardware

## Target: Apple TV 4K (3rd gen, 2022)

| Spec | Value |
|---|---|
| SoC | A15 Bionic (5-core CPU, 5-core GPU, 16-core Neural Engine) |
| RAM | 4 GB (Wi-Fi+Ethernet model); 3 GB (Wi-Fi-only model) |
| GPU | Apple A15 GPU, Metal 3 feature set |
| HEVC HW decode | 4K60 8-bit + 10-bit, HDR10, Dolby Vision |
| Network | Wi-Fi 6 (802.11ax), Gigabit Ethernet (Wi-Fi+Ethernet model) |
| Display out | HDMI 2.1, up to 4K60 HDR |

This port targets the Wi-Fi+Ethernet model for the Ethernet path; Wi-Fi 6 on the Wi-Fi-only model is fine too.

## Why not older Apple TVs

| Model | Why excluded |
|---|---|
| Apple TV HD (4th gen, 2015, A8) | 2 GB RAM, no HEVC decode, capped at 1080p |
| Apple TV 4K gen 1 (2017, A10X) | 3 GB RAM, struggles with 4K HDR HDCP gates, older HEVC HW decoder |
| Apple TV 4K gen 2 (2021, A12) | 3 GB RAM, fine for 4K HDR but lacks several Metal 3 / GameController-haptics niceties |

Sticking to A15 keeps the test surface to one device. See [`../decisions.md#apple-tv-4k-3rd-gen-only-a15-bionic-tvos-17`](../decisions.md#apple-tv-4k-3rd-gen-only-a15-bionic-tvos-17).

## Network stack

- **Wi-Fi 6 (802.11ax)**: 1.2 Gbps theoretical; in practice ~600–800 Mbps over the air. PS5 4K60 HEVC peaks around 30 Mbps, so the network is never the bottleneck on a healthy LAN.
- **Ethernet**: 1 Gbps. Preferred for the lowest jitter; adds zero variance from radio contention.
- The streaming socket should request 4 MB `SO_RCVBUF` (sibling project ships this — see [`../optimization/network-optimization.md`](../optimization/network-optimization.md)).

## Audio

- HDMI 2.1 supports up to 7.1 LPCM and Dolby Atmos passthrough. We don't passthrough — Opus is the source format and we decode locally.
- AudioUnit at 48 kHz S16 stereo is the sink.

## Controller

- DualSense pairs over Bluetooth via `GameController.framework` since tvOS 14.5.
- Haptics + adaptive triggers via `GCDualSenseGamepad` (tvOS 14.5+) and `GCDualSenseAdaptiveTrigger` (tvOS 15+).
- Siri Remote 2/3 also pairs but only exposes a `microGamepad` profile — useful for menu navigation while Bluetooth-pairing the DualSense, not for actual gameplay.

## Power / suspend

- Apple TV doesn't sleep the way an iPhone does. The screensaver kicks in after ~10 min of no input but the app stays running.
- The PS button on the tvOS remote bounces back to the home screen — when streaming, intercept this via `GCEventViewController.controllerUserInteractionEnabled = false` so DualSense PS-button presses are passed through to the stream instead of triggering tvOS home.

## Why this matters for the latency budget

A15's HEVC decoder reports ~1–2 ms wall-clock for a 4K60 frame; Metal present at 60 Hz adds at most ~16 ms (one frame); the DAC adds ~10 ms. Our latency budget is dominated by network jitter and decoder pipeline depth, not raw silicon speed. The hardware has a lot of headroom — the design has to spend it carefully.

See [`../optimization/latency-strategy.md`](../optimization/latency-strategy.md) for the per-stage budget.
