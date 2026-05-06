# Glossary

| Term | Meaning |
|---|---|
| **chiaki-lib** | The C protocol library at [`../../../lib/`](../../../lib/). Reused wholesale by this port. |
| **chiaki-ng** | Upstream project (this repo) maintained at https://streetpea.github.io/chiaki-ng/. |
| **ChiakiTV** | This port — the tvOS frontend that lives in [`../../`](../../). |
| **ChiakiBridgeC** | The thin Swift ↔ chiaki-lib glue layer at [`../../ChiakiBridgeC/`](../../ChiakiBridgeC/). |
| **Takion** | The PS5's custom UDP-based streaming protocol (SCTP-style framing). v12 on PS5. Implemented by `lib/src/takion.c`. |
| **RPCrypt** | The control-channel cipher (AES-128-CFB128 with HMAC-derived IV per packet). Implemented by `lib/src/rpcrypt.c`. |
| **GKCrypt** | The streaming-channel cipher (AES-128-CTR + 4-byte truncated GMAC). Re-keyed every 45 KB. Implemented by `lib/src/gkcrypt.c`. |
| **GMAC** | Galois Message Authentication Code. Used here authenticate-only with a 4-byte truncated tag. Covers the entire packet buffer including the type byte. |
| **Big / Bang** | The two ECDH protobuf messages exchanged inside the control channel (Big = client → PS5, Bang = PS5 → client). |
| **FEC** | Reed–Solomon erasure coding. PS5 transmits parity packets so the client can reconstruct lost UDP packets without retransmission. Implemented in `lib/src/fec.c` via `third-party/jerasure/`. |
| **Feedback State / Feedback History** | The two controller-input wire formats. State is continuous (sticks, motion). History is discrete events (buttons, touchpad). |
| **DualSense** | Sony's PS5 controller. Adaptive triggers, haptic feedback, motion sensors, touchpad. The only controller ChiakiTV supports. |
| **HEVC / H.265** | The video codec the PS5 uses for v12 Remote Play. Hardware-decoded by VideoToolbox on A15. |
| **VideoToolbox** | Apple's hardware-accelerated video coding framework. Provides `VTDecompressionSession`. |
| **CommonCrypto** | Apple's hardware-accelerated AES (and other primitives). C API. |
| **GameController** | Apple's input framework. Provides `GCController`, `GCExtendedGamepad`, `GCDualSenseGamepad`. |
| **Account ID** | The 8-byte PSN account ID needed by registration (`lib/src/regist.c`). **Prefilled in this port** rather than retrieved via OAuth. |
| **Prefilled** | This port's term for "the user types it in once, copied from a desktop chiaki-ng install." Shorthand for "no PSN OAuth flow." |
| **NAL** | Network Abstraction Layer (HEVC). Atomic encoded-video unit; the PS5 fragments NALs across UDP packets and we reassemble them via `lib/src/videoreceiver.c`. |
| **VPS / SPS / PPS** | HEVC parameter sets — Video / Sequence / Picture. Sent **out-of-band** by the PS5 in the STREAMINFO control message, *not* inline in IDR frames. The decoder must be primed with these before the first frame. |
| **Annex-B** | HEVC bitstream framing with `00 00 00 01` start codes. The PS5 emits Annex-B; VideoToolbox wants AVCC. Convert in place. |
| **AVCC** | HEVC bitstream framing with 4-byte big-endian length prefixes per NAL. VideoToolbox's required input format. |
| **`CVPixelBuffer`** | Apple's pixel buffer type. IOSurface-backed when produced by VideoToolbox. Zero-copy hand-off to Metal via `CVMetalTextureCache`. |
| **`CAMetalLayer`** | Core Animation layer that owns the swap chain on Apple platforms. We render decoded frames into its drawables. |
| **`CAMetalDisplayLink`** | tvOS 17+ tick source matched to the layer's refresh rate. Replaces `CADisplayLink` for our case. |
| **`AudioUnit`** | CoreAudio's render-callback-based audio I/O surface. Lower-overhead than `AVAudioEngine`. |
| **MFi** | Made-for-iPhone/iPad/Apple TV — Apple's controller certification program. DualSense isn't MFi but is supported via the same `GCExtendedGamepad` profile. |
| **STREAMINFO** | The PS5 control message announcing video / audio / FEC parameters at session start. `lib/src/ctrl.c` parses it. |
| **CORRUPTFRAME** | Client-to-PS5 control message saying "frame N–M was unrecoverable, please send IDR." See `lib/src/videoreceiver.c:160-203`. |
| **IDR** | Instantaneous Decoder Refresh. A self-contained HEVC keyframe — required after a CORRUPTFRAME or session start. |
| **PLC** | Packet Loss Concealment. The Opus jitter buffer's strategy for synthesizing audio for missing packets. |
| **STUN / TURN** | Internet-side NAT traversal protocols. Used by chiaki-ng's `lib/src/remote/holepunch.c`. **Out of scope** for this port. |
| **RUDP** | The reliable-UDP wrapper chiaki-ng uses for remote-over-internet sessions. Out of scope; LAN-only. |
| **Phase 0 / 1 / 2** | This port's implementation phases. See [`../phases.md`](../phases.md). |
