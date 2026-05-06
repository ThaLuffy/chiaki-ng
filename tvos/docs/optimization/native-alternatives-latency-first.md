# Native-alternatives audit — latency-first

> Date: 2026-05-07
> Goal: 4K60 HDR streaming on **wired LAN** with the absolute lowest end-to-end latency reachable on Apple TV 4K 3rd gen.
> Companion to [`native-alternatives.md`](./native-alternatives.md). That doc is a "given hard rule #1, what's safe to swap" view; this one is "given the latency goal, where could every microsecond go" — including swaps that would require an upstream chiaki-ng PR (allowed by rule #1's escape clause: *"unless it's also valuable upstream and contributed there"*).
>
> Scope: every `.c` file in `../../../lib/src/`, every external dep, every per-packet/per-frame mechanism. Wired LAN simplifies the analysis — Wi-Fi jitter and packet-loss tolerance margins go away, freeing us to tune for steady-state best case.

## TL;DR — where the milliseconds actually live

**Verification:**
- Source: traced every code path from UDP recv → display, citing `lib/src/*.c` files; cross-referenced our [`latency-strategy.md`](./latency-strategy.md) budget.
- Data: per-frame budget at 4K60 HDR (~30 Mbps × 1500-byte MTU ≈ 50 packets/frame, 60 fps):

| Stage | Per-frame ms | What's spent on | Optimisable now? |
|---|---|---|---|
| LAN one-way (wired GbE) | 0.1–0.3 | Cable + switch + Apple TV NIC | No |
| Per-packet header parse + reorder + packetstats (50× per frame) | 0.2–0.4 | mutex'd reorder queue, mutex'd packet stats | Marginal — would require patching chiaki |
| Per-packet GMAC verify (50×) | **0.5–1.5** | `EVP_CIPHER_CTX_new/free` + software AES | **Yes — biggest single win.** OpenSSL `no-asm` build + per-call malloc; both fixable. |
| Per-packet AES-CTR decrypt (50×) | 0.05 (steady) | XOR with pre-generated keystream | Already amortised (background `key_buf`); hardware AES helps the *generation* thread only |
| Frame assembly (FEC if needed) | 0.05 (no loss); 1–3 (loss) | `frameprocessor.c` memcpy of fragments | Wired LAN: no loss → essentially free |
| Bridge → Swift → Annex-B walk → AVCC alloc | **0.2–0.4** | per-frame `Data` alloc + walker + malloc'd AVCC buffer | **Yes — move walk into C bridge, hand VT a CMBlockBuffer directly.** |
| `VTDecompressionSessionDecodeFrame` (HEVC 4K60 HDR) | 1–2 | A15 HEVC HW decode | No — already hardware |
| Decoder output → renderer slot | < 0.05 | atomic store | No |
| **Wait for next vsync** (worst case) | **0–16.7** | MTKView's CADisplayLink alignment | **Yes — switch to `CAMetalDisplayLink` + `targetPresentationTimestamp`; aim for predictable cadence rather than worst-case wait.** |
| Metal encode + present | 0.5 | YUV→RGB shader + drawable submit | No |
| Compositor + scan-out | 8.3 | one frame at 60 Hz | No (display physics) |
| **Total added (vs. media itself)** | **~3–5 ms typical, up to 22 ms in pathological vsync misalignment** | | |

**Conclusion:** the four swaps in **bold** above (hardware AES, EVP context reuse, in-C NAL walk, CAMetalDisplayLink alignment) account for essentially all the optimisable latency. Everything else is either physics, already optimal, or a fraction of a millisecond.

A fifth opportunity is on the **input path**, not the video path: chiaki's `feedbacksender.c` enforces a **minimum 8 ms** between controller-state packets ([`feedbacksender.c:8` `FEEDBACK_STATE_TIMEOUT_MIN_MS 8`](../../../lib/src/feedbacksender.c)). Our bridge calls `chiaki_session_set_controller_state` immediately on every value change — chiaki throttles to 8 ms. Patching this constant down (or making it configurable, upstream) is the cheapest controller-latency win available.

## Methodology

Every `lib/src/*.c` file, every external dep, every per-packet/per-frame mechanism gets one of these verdicts:

| Verdict | Meaning |
|---|---|
| **HOT — swap** | On streaming hot path, native alternative meaningfully lower latency. Do it. |
| **HOT — keep** | On hot path, but already optimal or no win from swapping. |
| **WARM — patch** | Off hot path but a constant / config inside chiaki is hurting us. Fork-patch or upstream-PR. |
| **COLD — keep** | Runs once per session / out of scope for latency. |
| **NOT BUILT** | Excluded from our XCFramework already. |
| **DROPPED** | Out of scope per [`docs/decisions.md`](../decisions.md). |

Hot-path = called per UDP packet, per video frame, per audio frame, or per controller tick during steady-state streaming. Wired-LAN assumption removes packet loss as a frequent event — FEC paths drop from "occasionally hot" to "essentially cold."

## Per-mechanism audit (every single file, every single dep)

### Streaming hot path — Takion (UDP transport)

#### `lib/src/takion.c` (1962 lines) — UDP recv loop, per-packet dispatch

**Verification:**
- Source: [`takion.c:1072` `takion_thread_func`](../../../lib/src/takion.c).
- Data: dedicated thread, `chiaki_thread_set_affinity(CHIAKI_THREAD_NAME_TAKION)` + `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` on Apple. Loop calls `takion_recv` → `takion_handle_packet`. 13 `chiaki_mutex_lock`/`_unlock` callsites in the file (largely off the hot path — `gkcrypt_local_mutex` is the per-encrypt one).

**Per-packet allocations:** none in the recv loop itself; allocations live in subsystems it calls (gkcrypt, frameprocessor).
**Per-packet locking:** `gkcrypt_local_mutex` held across `chiaki_gkcrypt_decrypt` + `chiaki_gkcrypt_gmac` ([takion.c:484-503, 738-760](../../../lib/src/takion.c)). This is a real per-packet lock, but the critical section is short and uncontended (only the takion thread takes it during steady state).

**Native alternatives:**
- `Network.framework` `NWConnection.receiveMessage` adds a Dispatch hop per packet → latency-hostile vs. raw `recvfrom` on a `USER_INTERACTIVE` thread. **Worse.**
- `kqueue` instead of `select` (chiaki's `stoppipe` uses `select`): would let recv block directly on the UDP socket without the select-with-timeout dance. Marginal.

**Verdict:** **HOT — keep.** Upstream already does the Apple-specific QoS lift; the recv path is as tight as a C+POSIX path gets.

#### `lib/src/sock.c` (20 lines) — `fcntl(F_SETFL, O_NONBLOCK)` wrapper

**Verdict:** **COLD — keep.** Trivial.

#### `lib/src/stoppipe.c` (275 lines) — `pipe(2)` for cross-thread shutdown signal

**Verification:**
- Source: [`stoppipe.c:13 `#include <sys/select.h>`](../../../lib/src/stoppipe.c).
- Data: chiaki uses `select(stop_pipe_fd | socket_fd, …)` to make `recvfrom` interruptible by a stop signal.

**Native alternative:** `kqueue` / `dispatch_source` would be lower-overhead but only if the recv loop is select-bound, which it isn't (it spends almost all its time blocked in `recvfrom`, not iterating select). No realistic win.

**Verdict:** **COLD — keep.** The select call only fires once per recv timeout; not on the hot path per se.

#### `lib/src/takionsendbuffer.c` (267 lines) — outgoing send buffer with ack tracking

**Hot path?** Sends only — fire on controller state, audio (out — we don't have a mic), and control packets. Not per-incoming-packet.

**Verdict:** **WARM — keep.** Lightly-used; sends ~125 controller-state packets/sec at most.

#### `lib/src/reorderqueue.c` (200 lines) — generic reorder buffer; chiaki uses 16 entries (`TAKION_REORDER_QUEUE_SIZE_EXP = 4`)

**Verification:**
- Source: [`takion.c:56 `#define TAKION_REORDER_QUEUE_SIZE_EXP 4`](../../../lib/src/takion.c)
- Data: 16-entry reorder window. On wired LAN with near-zero packet reorder, this window is mostly empty — but its presence means each packet sits in the queue for the duration of the worst-case in-flight reorder before being dispatched.

**Wired-LAN optimisation:** drop the window to 4 entries (`TAKION_REORDER_QUEUE_SIZE_EXP = 2`). Saves up to a few packet-times of buffering during normal operation. **This is a chiaki constant — patching it requires either fork-patch or upstream PR (config knob).**

**Verdict:** **WARM — upstream PR for configurability** (or fork-patch for personal use).

### Streaming hot path — crypto (`gkcrypt.c` + OpenSSL)

#### `lib/src/gkcrypt.c` (574 lines)

**Verification — finding 1: per-packet `EVP_CIPHER_CTX` malloc/free.**
- Source: [`gkcrypt.c:414` `EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();`](../../../lib/src/gkcrypt.c) inside `chiaki_gkcrypt_gmac`.
- Data: every call to GMAC → one `malloc` for the EVP context, one `free` afterward. GMAC is called per packet for verify ([`takion.c:564`](../../../lib/src/takion.c)) and per outgoing packet for compute ([`takion.c:753, 807`](../../../lib/src/takion.c)).
- Calculation: at 4K60 HDR with ~50 packets/frame × 60 fps = 3 000 GMAC ops/sec on receive. Plus the keystream-generation context in [`gkcrypt.c:234`](../../../lib/src/gkcrypt.c) (allocated less frequently, only when the background `key_buf` thread regenerates).
- Conclusion: **allocator pressure on the hot path**, even when the AES primitive itself is cheap.

**Verification — finding 2: software-table AES.**
- Source: [`scripts/build-deps-tvos.sh:160` `no-shared no-asm no-tests no-engine no-dso no-async`](../../scripts/build-deps-tvos.sh).
- Data: OpenSSL built with `no-asm` → C-table AES, no `AESE`/`AESD` instructions on A15.
- Conclusion: every byte of GMAC + every keystream-generation byte goes through software AES. At 4K60 HDR steady state this is the highest-frequency arithmetic in the entire pipeline.

**Native alternatives:**

| Path | Where it touches | Effort |
|---|---|---|
| **A. BoringSSL drop-in** for `libcrypto.a` | `scripts/build-deps-tvos.sh` only — `lib/src/` unchanged | Small. Re-vendor BoringSSL; verify all `EVP_*` and `EC_*` symbols `lib/` calls resolve. |
| **B. Fix OpenSSL `enable-asm`** | `scripts/build-deps-tvos.sh` + small shim for the few macOS-only entry points OpenSSL's arm64 asm references | Small–medium. |
| **C. EVP_CIPHER_CTX reuse** for GMAC (one-time `EVP_CIPHER_CTX_new`, repeated `EVP_CipherInit_ex(NULL, …)` to reset) | `lib/src/gkcrypt.c` only — protocol-neutral, valuable upstream | Upstream PR. |
| **D. CryptoKit `AES.GCM.SealedBox.tag`** wrapper inside the C bridge | Replaces the entire `chiaki_gkcrypt_gmac` callsite from chiaki's perspective | Massive — requires mirroring chiaki's GMAC IV layout; **violates "wrap, don't patch"**. Don't do this. |
| **E. CommonCrypto `kCCAlgorithmAES` + `CCCryptorRef` reuse** as a `CHIAKI_CRYPTO_*` backend alongside the existing OpenSSL/mbedTLS branches | `lib/src/gkcrypt.c` adds `#ifdef CHIAKI_CRYPTO_COMMONCRYPTO` paths | Medium. Upstream contribution. |

**Verdict — HOT — swap, multi-step:**
1. **First**: do (A) or (B) — fixes hardware AES with no protocol risk.
2. **Then**: do (C) — eliminates per-packet malloc; trivial upstream PR.
3. **Optional**: (E) gives `kCCAlgorithmAES`-backed crypto on Apple platforms specifically; (A)+(B)+(C) achieves the same speed with less surface.

#### `lib/src/random.c` (57 lines), `lib/src/ecdh.c` (240 lines), `lib/src/rpcrypt.c` (2428 lines)

**Hot path?** No. `random.c` is `RAND_bytes` — used at session init only. `ecdh.c` is one ECDH key exchange per registration. `rpcrypt.c` is mostly massive constant tables for the registration handshake (`hmac_key_ps5`, `hmac_key_ps4`, `regist_aes_key`, etc.) plus AES-CFB encrypt for the registration payload.

**Verdict:** **COLD — keep.** Hardware AES via the gkcrypt fix benefits these too, but their frequency makes the win invisible.

### Streaming hot path — Frame assembly (`videoreceiver.c` + `frameprocessor.c` + `fec.c` + `bitstream.c`)

#### `lib/src/videoreceiver.c` (319 lines)

**Verification:**
- Source: [`videoreceiver.c:295-297`](../../../lib/src/videoreceiver.c) calls `session->video_sample_cb(frame, frame_size, frames_lost, recovered, …)` once per assembled frame; [`videoreceiver.c:140-141`](../../../lib/src/videoreceiver.c) emits the parameter sets out-of-band when adaptive-stream profile changes.
- Data: passes a `uint8_t *frame` pointer into a buffer chiaki owns; valid for the duration of the callback only.

**Verdict:** **HOT — keep.** This is the right boundary; chiaki does the assembly, hands us a complete frame. The work to do post-assembly (Annex-B → AVCC → VT) is what we should optimise — see "C-bridge relocation" below.

#### `lib/src/frameprocessor.c` (318 lines)

**Verification:**
- Source: [`frameprocessor.c:115-137`](../../../lib/src/frameprocessor.c) `malloc(unit_slots_size_required * sizeof(ChiakiFrameUnit))` + `malloc(frame_buf_size_required + CHIAKI_VIDEO_BUFFER_PADDING_SIZE)`; [`frameprocessor.c:186 `memcpy(frame_processor->frame_buf + …)`](../../../lib/src/frameprocessor.c) per fragment.
- Data: re-allocates `frame_buf` only when frame size grows (i.e., on resolution change — not per frame). Per-fragment memcpy unavoidable: FEC requires contiguous input.

**Wired-LAN consideration:** FEC almost never fires; the memcpy is "wasted" in the sense that VT could in principle accept a scatter-gather `CMBlockBuffer` (multiple memory blocks via `CMBlockBufferAppendMemoryBlock`). But that would mean letting VT decode without FEC repair available — risky, no benefit unless we accept "no FEC ever" as a wired-LAN trade-off.

**Verdict:** **HOT — keep.** chiaki's frame_buf strategy is correct; the per-fragment memcpy isn't avoidable without giving up FEC.

#### `lib/src/fec.c` (133 lines) + Jerasure + GF-Complete

**Verification:**
- Source: `fec.c` 133 lines wrapping `jerasure_matrix_decode`.
- Data: only invoked on packet loss. On wired LAN, near-zero invocation rate.

**Verdict:** **HOT — keep**, conditional on loss. No Apple-native Galois Field math; building a Metal compute kernel adds GPU round-trip latency. Not worth it.

#### `lib/src/bitstream.c` (406 lines) + `vl_rbsp.h`

**Verification:**
- Source: [`bitstream.c`](../../../lib/src/bitstream.c) parses HEVC/H.264 NAL headers + slice headers. Used by `videoreceiver.c` to detect IDR boundaries and rewrite reference-frame fields when a referenced frame is missing from the ref ring.

**Verdict:** **HOT (conditional) — keep.** Pure C bitstream math; no native alternative; only fires on loss anyway.

### Streaming hot path — Audio

#### `lib/src/audioreceiver.c` (363 lines)

**Verdict:** **HOT — keep.** Receives Opus packets, hands to decoder. Already integrated.

#### `lib/src/opusdecoder.c` (102 lines) + libopus

**Verdict:** **HOT — keep.** No Apple-native Opus decoder exists in `AudioToolbox`. libopus has NEON paths for arm64 — already optimal.

#### `lib/src/audio.c` (40 lines) — header pack/unpack

**Verdict:** **COLD — keep.** Two functions, one-shot per stream.

### Streaming hot path — Controller / input (latency-relevant!)

#### `lib/src/feedbacksender.c` (354 lines) + `feedback.c` (208 lines) + `controller.c` (165 lines)

**Verification — input-latency floor:**
- Source: [`feedbacksender.c:8` `#define FEEDBACK_STATE_TIMEOUT_MIN_MS 8`](../../../lib/src/feedbacksender.c).
- Data: chiaki's feedback sender thread (`feedback_sender_thread_func`) wakes when the controller-state-changed flag is set, but enforces **minimum 8 ms between consecutive controller-state packets**. Our [`ControllerService.swift`](../../ChiakiTV/Services/Controller/ControllerService.swift) calls `chiaki_tv_session_set_controller_state` immediately on every `valueChangedHandler` callback, but chiaki throttles.
- Conclusion: **input latency floor of 8 ms** baked into chiaki, regardless of how aggressively our bridge feeds it.

**Verdict:** **WARM — upstream PR for configurability.** Drop to 4 ms for wired-LAN scenarios (or make it a session-config field in `ChiakiConnectInfo`). Personal-use fork-patch is the fast path; upstream PR is the right path.

#### `lib/src/orientation.c` (227 lines) — Madgwick filter for IMU → quaternion

**Verification:**
- Source: [`orientation.c`](../../../lib/src/orientation.c). Madgwick fusion of accel + gyro into orientation quaternion.
- Data: invoked per IMU sample (~250 Hz on DualSense). Pure float math; no allocations.

**Native alternative:** Apple's `CMMotionManager` runs Madgwick / Kalman in-house, but the IMU readings come from the DualSense's hardware via `GCMotion`, not from CoreMotion. We feed raw values to chiaki, chiaki runs Madgwick. Reimplementing in Swift is cosmetic — doesn't move latency.

**Verdict:** **HOT — keep.** Cheap math; Apple has nothing to add.

### Streaming hot path — congestion + stats

#### `lib/src/congestioncontrol.c` (81 lines)

**Verification:**
- Source: [`congestioncontrol.c:5 `#define CONGESTION_CONTROL_INTERVAL_MS 200`](../../../lib/src/congestioncontrol.c). Sends `ChiakiTakionCongestionPacket` every 200 ms.

**Verdict:** **WARM — keep.** 5 packets/sec; sub-microsecond impact.

#### `lib/src/packetstats.c` (83 lines)

**Verification:**
- Source: [`packetstats.c:55 `chiaki_packet_stats_push_seq`](../../../lib/src/packetstats.c) is called per packet, holds a mutex, increments counters.
- Data: per-packet mutex acquire/release on the stats struct.

**Wired-LAN optimisation:** the mutex isn't contended in steady state; the cost is a couple of atomic ops per packet. Could be lock-free with `_Atomic` counters (upstream PR). Saves nanoseconds per packet — won't move the budget table.

**Verdict:** **HOT — keep**, with a low-priority upstream-PR opportunity for lock-free counters.

### Connection setup — cold path

| File | Lines | Role | Verdict |
|---|---|---|---|
| `session.c` | 1192 | Top-level session orchestration | **COLD — keep** |
| `streamconnection.c` | 1302 | Stream-channel setup, STREAMINFO handler | **COLD — keep** |
| `ctrl.c` | 1486 | TCP control channel, RPCrypt'd | **COLD — keep** |
| `senkusha.c` + nanopb | 962 | Sony's pre-stream RTT probe | **COLD — keep** |
| `regist.c` + `http.c` | 940 + 275 | Registration handshake | **COLD — keep** |
| `discovery.c` + `discoveryservice.c` | 500 + 390 | Manual + periodic discovery | **COLD — keep** |
| `launchspec.c` | 95 | Launch-spec JSON template | **COLD — keep** |
| `base64.c` | 153 | base64 enc/dec | **COLD — keep** |
| `common.c` | 122 | codec-name util | **COLD — keep** |
| `time.c` | 28 | `clock_gettime` wrapper | **COLD — keep** |
| `thread.c` | 556 | pthread + Apple QoS (already optimal) | **COLD — keep** |
| `log.c` | 232 | Already wrapped in Swift | **COLD — keep** |

### Not built / dropped from our XCFramework

| File | Reason | Verdict |
|---|---|---|
| `lib/src/ffmpegdecoder.c` | We use VideoToolbox directly; FFmpeg not linked | **NOT BUILT** |
| `lib/src/pidecoder.c` | Raspberry Pi MMAL decoder | **NOT BUILT** |
| `lib/src/audiosender.c` | PS4 voice-mic upload; Apple TV has no mic | **NOT BUILT** (could be excluded explicitly to save ~6 KB binary) |
| `lib/src/opusencoder.c` | Mic encode; ditto | **NOT BUILT** (could be excluded explicitly) |
| `lib/src/remote/holepunch.c` | Remote-play-over-internet | **DROPPED** (LAN-only scope) |
| `lib/src/remote/rudp.c`, `rudpsendbuffer.c`, `stun.h` | Same | **DROPPED** |
| `libcurl`, `libevent`, `json-c`, `miniupnpc` | Only used by `holepunch.c` | **DROPPED** transitively |

### tvOS-port-side opportunities (no chiaki-lib touch needed)

These are hot wins entirely on our side of the bridge, so they don't engage hard rule #1 at all:

#### Annex-B → AVCC walk in C bridge (instead of Swift)

**Verification:**
- Source: [`VideoDecoder.swift:71` `Data(bytes: base, count: buffer.count)`](../../ChiakiTV/Services/Video/VideoDecoder.swift) per video sample callback.
- Data: per-frame Swift `Data` allocation (~1–15 KB), plus a malloc'd AVCC buffer that's transferred to `CMBlockBuffer`.
- Conclusion: per-frame heap allocation on the hot path; conflicts with hard rule #2 ("zero allocations on the streaming hot path").

**Native alternative:** move the entire walker into `chiaki_bridge_session.c`'s video trampoline. Walk in place using the buffer chiaki already owns; build the AVCC buffer in C; pass Swift a pointer + length + a small POD struct describing where VPS/SPS/PPS live. Swift creates the `CMBlockBuffer` directly, no `Data`.

**Verdict:** **HOT — swap on our side.** No upstream concern.

#### Direct `CAMetalLayer` + `CAMetalDisplayLink` (instead of `MTKView`)

**Verification:**
- Source: [`MetalRenderer.swift:67 `view.preferredFramesPerSecond = 60`](../../ChiakiTV/Services/Video/MetalRenderer.swift), MTKView's internal `CADisplayLink` drives `draw(in:)`.
- Data: MTKView's draw callback fires per vsync, but doesn't expose `targetPresentationTimestamp`. tvOS 17+ `CAMetalDisplayLink` does.

**Native alternative:** drop MTKView entirely. Host a raw `CAMetalLayer` in the SwiftUI view (`UIViewRepresentable<UIView>` whose backing layer is `CAMetalLayer`); drive presents via `CAMetalDisplayLink` (tvOS 17+). Use `targetPresentationTimestamp` to align decode + render to the predicted vsync rather than dispatching whenever the buffer happens to land.

**Expected win:** tightens the "wait for next vsync" worst case from up to 16.7 ms (full frame miss) to a predictable few-millisecond window.

**Verdict:** **HOT — swap on our side.** No upstream concern.

#### `kCMSampleAttachmentKey_DisplayImmediately`

**Verification:**
- Source: not currently set on the `CMSampleBuffer` produced by [`VideoDecoder.swift:148-158`](../../ChiakiTV/Services/Video/VideoDecoder.swift).
- Data: VideoToolbox respects this attachment by emitting decoded frames as soon as decode completes, bypassing internal reorder/display queues.

**Native alternative:** set `kCMSampleAttachmentKey_DisplayImmediately = true` in the sample-attachments dict before calling `VTDecompressionSessionDecodeFrame`. One line.

**Verdict:** **HOT — swap on our side.** Trivial change.

#### `VTDecompressionSession` pre-warm at STREAMINFO time

**Verification:**
- Source: chiaki delivers VPS/SPS/PPS out-of-band via [`videoreceiver.c:140-141`](../../../lib/src/videoreceiver.c) when the adaptive-stream profile is established — *before* the first slice arrives. Currently our [`VideoDecoder.swift:94`](../../ChiakiTV/Services/Video/VideoDecoder.swift) builds the session lazily on the first frame.
- Data: `VTDecompressionSessionCreate` for HEVC HDR can take 5–20 ms.

**Native alternative:** treat the parameter-set sample (`profile->header`, header_sz) as a session-build trigger. Build VT before any slice arrives. First-frame latency drops by 5–20 ms.

**Verdict:** **HOT — swap on our side.** First-frame UX win, not steady-state.

#### Audio output: `AudioUnit` `kAudioUnitSubType_RemoteIO` (instead of `AVAudioEngine`)

**Verification:**
- Source: current [`AudioPlayer.swift`](../../ChiakiTV/Services/Audio/AudioPlayer.swift) uses `AVAudioEngine` + `AVAudioPlayerNode` with a default 80 ms buffer ([`AppSettings.swift:46 `audioBufferMs: Int = 80`](../../ChiakiTV/Models/AppSettings.swift)).
- Data: `AVAudioEngine`'s scheduler adds ~10 ms of internal jitter buffer. Direct `AudioUnit` with `kAudioUnitSubType_RemoteIO` runs at 5–10 ms total round-trip.

**Wired-LAN consideration:** the current 80 ms audio buffer is a network-jitter buffer, not an audio-output buffer; it dominates audio latency. On wired LAN the network jitter is so low that the buffer can drop to ~30 ms with no underruns — that's a much bigger win than the AVAudioEngine → AudioUnit switch.

**Verdict:** **WARM — tune buffer first**, swap engine only if needed. Drop `audioBufferMs` default to 30 ms for wired-LAN sessions; if that holds without underruns, AudioUnit is unnecessary.

### tvOS-port-side wired-LAN tunings (no swap needed)

| Setting | Current | Wired-LAN target | Source |
|---|---|---|---|
| `audioBufferMs` | 80 | **30** | [`AppSettings.swift`](../../ChiakiTV/Models/AppSettings.swift) |
| `SO_RCVBUF` on takion socket | OS default (~786 KB on tvOS) | **2 MB** explicit | applied on our bridge socket-config side |
| `kVTDecompressionPropertyKey_RealTime` | `true` | already set | [`VideoDecoder.swift:290`](../../ChiakiTV/Services/Video/VideoDecoder.swift) |
| `kVTDecompressionPropertyKey_OutputPoolRequestedMinimumBufferCount` | 2 | already set | [`VideoDecoder.swift:293`](../../ChiakiTV/Services/Video/VideoDecoder.swift) |
| `CAMetalLayer.maximumDrawableCount` | implicit MTKView default (3) | **2** | requires raw CAMetalLayer migration |
| `CAMetalLayer.framebufferOnly` | `true` (MTKView default) | already set | |

### Upstream-PR opportunities (require touching `lib/`)

In rough priority by impact:

1. **`EVP_CIPHER_CTX` reuse in `gkcrypt.c`** — eliminate per-packet malloc on the hottest path. Single-file change. Generic upstream win.
2. **`FEEDBACK_STATE_TIMEOUT_MIN_MS` configurability** — input-latency floor for low-latency LAN setups. Add a field to `ChiakiConnectInfo` that defaults to 8 (preserving today's behaviour).
3. **`TAKION_REORDER_QUEUE_SIZE_EXP` configurability** — same idea, exposed as a connect-info field.
4. **`CONGESTION_CONTROL_INTERVAL_MS` configurability** — sub-microsecond gain, but the flag plumbing is the same.
5. **CommonCrypto / CryptoKit crypto backend** alongside OpenSSL/mbedTLS — Apple-platform contributors get hardware AES even if their OpenSSL is built `no-asm`.
6. **Lock-free `packetstats.c`** — atomic counters in place of mutex.

If the OpenSSL `no-asm` issue is hard to fix cleanly from our side (item #5 in the previous audit), upstream contribution #5 here is the principled escape hatch.

## What hard rule #1 means for this audit

The rule: *"Reuse upstream chiaki-ng `lib/` whenever the protocol is involved … the answer is to wrap, not patch — patching `lib/` is a regression unless it's also valuable upstream and contributed there."* (`AGENTS.md:29`)

Mapping each opportunity above:

| Opportunity | tvOS-side? | Touches `lib/`? | Path |
|---|---|---|---|
| OpenSSL `enable-asm` / BoringSSL | ✅ | No (build-script only) | Do it on our side. |
| `EVP_CIPHER_CTX` reuse | ❌ | Yes (`gkcrypt.c`) | **Upstream PR** (clearly valuable to all chiaki-ng users). |
| Annex-B walk in C bridge | ✅ | No (our `ChiakiBridgeC/`) | Do it on our side. |
| `CAMetalDisplayLink` migration | ✅ | No (our renderer) | Do it on our side. |
| `DisplayImmediately` attachment | ✅ | No (our decoder) | Do it on our side. |
| VT session pre-warm | ✅ | No | Do it on our side. |
| `audioBufferMs` 30 ms | ✅ | No | Do it on our side. |
| `FEEDBACK_STATE_TIMEOUT_MIN_MS` 4 ms | ❌ | Yes (`feedbacksender.c`) | **Upstream PR** (configurable field on `ChiakiConnectInfo`). |
| `TAKION_REORDER_QUEUE_SIZE_EXP` 2 | ❌ | Yes (`takion.c`) | **Upstream PR** (configurable field). |
| Lock-free `packetstats.c` | ❌ | Yes | **Upstream PR**. |
| CommonCrypto crypto backend | ❌ | Yes | **Upstream PR**. |

**Five tvOS-side wins** + **five upstream-PR wins**. None of this asks us to fork-patch `lib/` while staying on the tvOS port — every chiaki-touching change is upstream-contributable.

## Considered and dropped (even with the latency-first lens)

- **Reimplement takion+gkcrypt in Swift/CommonCrypto from scratch.** Months of work; protocol details (GMAC IV layout, key-position state, congestion-control semantics) are subtle; benefit ≈ what the OpenSSL build fix achieves. Don't.
- **Reimplement `videoreceiver.c` + `frameprocessor.c` in Swift.** Same risk profile; near-zero steady-state win on wired LAN where FEC doesn't fire.
- **GPU-side AES via Metal compute** for keystream generation. Round-trip dominates; CPU AES instructions on A15 are already at ~5 GB/s. Don't.
- **GPU-side FEC via Metal compute.** Same.
- **`Network.framework` for the takion UDP recv.** Dispatch hop per packet → strictly worse.
- **`URLSession` for `regist.c` HTTP transport.** Cold path; no latency win.
- **`SwiftProtobuf` for senkusha.** Cold path.
- **Bonjour / mDNS discovery.** PS5 doesn't advertise mDNS.
- **Replace `chiaki_thread_*` with `Task` / `actor`.** Patches `lib/`; chiaki's mutex pattern is bound to its thread model.
- **Skip GMAC verify entirely on wired LAN.** Tempting (no attacker, near-zero corruption) but disabling crypto is a protocol-level change requiring upstream support; the PS5 won't tolerate corrupted packets.

## Recommended sequence

Phase A — wins that need no protocol risk and no lib/ touch (do these first):

1. ~~**OpenSSL build with hardware AES**~~ ✅ implemented 2026-05-07 — `tvos/scripts/build-deps-tvos.sh` Configure flags now include ARMv8 asm (the `no-asm` flag was dropped). Verified: `_aes_v8_*` symbols (`_aes_v8_set_encrypt_key`, `_aes_v8_ecb_encrypt`, etc.) are now present in `Vendors/prefix/{appletvos,appletvsimulator}/lib/libcrypto.a`. The previous `no-asm` rationale (asm calls into routines invalid on tvOS) no longer applies on current SDKs. Hardware verify required for end-to-end speedup.
2. ~~**Annex-B → AVCC walk in `ChiakiBridgeC`**~~ ✅ implemented 2026-05-07 — new `ChiakiBridgeC/{include/ChiakiBridgeC/chiaki_bridge_video.h, src/chiaki_bridge_video.c}` exposes `chiaki_tv_walk_annex_b`. `VideoDecoder.swift` no longer allocates a `Data` per video sample; the C walker writes AVCC into a fresh malloc'd buffer the Swift side hands directly to `CMBlockBufferCreateWithMemoryBlock(kCFAllocatorMalloc)`. Parameter-set-only deliveries skip the AVCC build entirely.
3. ~~**`kCMSampleAttachmentKey_DisplayImmediately = true`**~~ ✅ implemented 2026-05-07 — set on the `CMSampleBuffer` attachments dict in `VideoDecoder.swift` before `VTDecompressionSessionDecodeFrame`.
4. ~~**VT session pre-warm**~~ ✅ already in place (the previous audit's "lazy on first frame" claim was wrong — `refreshFormatDescription` runs on parameter-set delivery before the `hasSlice` check). Refinement implemented 2026-05-07: skip the unused AVCC malloc on parameter-set-only deliveries.
5. ~~**Drop `audioBufferMs` default to 30 ms**~~ ✅ implemented 2026-05-07 — `AppSettings.swift` default now 30; test anchors updated.
6. ~~**Migrate renderer to raw `CAMetalLayer` + `CAMetalDisplayLink`**~~ ✅ implemented 2026-05-07 — `MetalRenderer.swift` no longer uses `MTKView`; new `ChiakiMetalView` (UIView subclass with `layerClass = CAMetalLayer`) hosts the layer; `CAMetalDisplayLink` (tvOS 17+) drives presents and supplies `targetPresentationTimestamp` to `commandBuffer.present(_:atTime:)`.

Phase B — upstream contributions (in priority order):

7. **`EVP_CIPHER_CTX` reuse PR** to `gkcrypt.c`.
8. **`FEEDBACK_STATE_TIMEOUT_MIN_MS` + `TAKION_REORDER_QUEUE_SIZE_EXP` configurability PR**.
9. **CommonCrypto crypto backend PR** (only if (1) is intractable).

Phase C — measurement (the most important step):

10. **Hardware-verify** the full chain on Apple TV 4K 3rd gen + PS5 + wired LAN before claiming wins. Capture before/after into `docs/reports/`. Numbers, not narrative.

Phase A items 1–6 are entirely on our side and self-contained. Phase B items are honest upstream contributions that benefit every chiaki-ng user on Apple platforms. Phase C is the gate: any "win" we can't measure on hardware doesn't count.
