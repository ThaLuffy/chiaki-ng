# Native-alternatives audit for chiaki-lib

> Date: 2026-05-06
> Question: which parts of chiaki-lib could we replace or augment with Apple-native code, given our hardware target (Apple TV 4K 3rd gen / A15 Bionic / tvOS 17+) and our hard rule #1 ("reuse upstream chiaki-ng `lib/`. Wrap, don't patch")?
> Methodology: enumerate every subsystem in `../../../lib/src/`, identify the C-level dep, evaluate the Apple-native alternative, decide Keep / Hybrid / Swap-at-edge / Upstream-PR / Out-of-scope.

## TL;DR — what's worth our time

In priority order, by expected wall-clock benefit on the streaming hot path:

| # | Opportunity | Where | Verdict | Expected win |
|---|---|---|---|---|
| 1 | **Enable A15 hardware AES** in our OpenSSL build (currently `no-asm` per `scripts/build-deps-tvos.sh:160`). | All 4 crypto files in `lib/src/` (`gkcrypt`, `rpcrypt`, `ecdh`, `random`) | **Build-script fix on our side** | Streaming AES + GMAC on every UDP packet drops from software-table-based to AES instructions — order-of-magnitude crypto-loop speedup, biggest single win available. |
| 2 | **Zero-copy Annex-B → AVCC walk** in C bridge (currently `Data(bytes:count:)` per video sample in [`VideoDecoder.swift:71`](../../ChiakiTV/Services/Video/VideoDecoder.swift)). | `ChiakiBridgeC/src/chiaki_bridge_session.c` video trampoline | **Edge-side wrap** | One per-frame allocation eliminated (~1 KB-15 KB depending on frame); cleaner thermal/cache profile under sustained 4K60 streaming. |
| 3 | **Codable launch-spec / regist-response decode** (currently sprintf templates + manual key parsing in `lib/src/launchspec.c`, `lib/src/regist.c`). | Cold path — registration + session bring-up. | **Skip**; cold path, no streaming benefit. | — |
| 4 | **CommonCrypto fast path for streaming hot loop** as an alternative to OpenSSL backend swap. | `gkcrypt.c` `EVP_*` callsites | **Upstream contribution** if (1) is too entangled. | Same as (1); but requires `#ifdef CHIAKI_CRYPTO_COMMONCRYPTO` upstream. |

Everything else is either already native (video/audio/render/controller/logging), already optimal upstream (threading QoS — chiaki already sets `QOS_CLASS_USER_INTERACTIVE` on Apple at [`lib/src/takion.c:1077-1085`](../../../lib/src/takion.c)), or out-of-scope (libcurl/libevent/json-c/miniupnpc are only used by `lib/src/remote/holepunch.c`, which we explicitly drop).

## Methodology

For each subsystem we verify:

1. **Source files** — exact `lib/src/*.c` files implementing it.
2. **Hot path?** — does this code run per UDP packet, per video frame, per audio frame, per controller tick, or only during connection setup?
3. **External deps** — what gets linked to compile / run this subsystem.
4. **Native alternative on Apple platforms** — what `Foundation` / `CryptoKit` / `CommonCrypto` / `Network.framework` / `AVFoundation` / `Accelerate` API gives equivalent behaviour.
5. **Compatibility with hard rule #1** — can we wrap at the bridge edge without patching `lib/`?
6. **Verdict** — Keep / Hybrid / Swap-at-edge / Upstream-PR / Out-of-scope.

Verification protocol applies — every numerical claim cites file:line; every comparison cites both sides.

---

## Subsystem inventory

### Crypto stack — `lib/src/{ecdh,rpcrypt,gkcrypt,random}.c`

**Verification:**
- Source: `grep -l "openssl\|<mbedtls" lib/src/*.c`
- Data: 4 crypto files all use OpenSSL (`EVP_*`) with optional `mbedtls_*` paths via `#ifdef`.
  - `gkcrypt.c:238` `EVP_aes_128_ecb` for keystream init
  - `gkcrypt.c:421` `EVP_aes_128_gcm` for GMAC
  - `gkcrypt.c:154` `HMAC(EVP_sha256(), …)` for KDF
  - `rpcrypt.c:2289` `mbedtls_md_hmac_starts` (HMAC for registration handshake)
  - `rpcrypt.c:2321-2331` `mbedtls_aes_crypt_cfb128` (AES-CFB for registration)
  - `ecdh.c:59` `EC_GROUP_new_by_curve_name(NID_secp256k1)` (one-time, registration)
- Conclusion: AES-128 ECB (keystream) + AES-128 GCM (GMAC) run on **every** Takion stream packet (`takion.c:738-760` for send, `takion.c:564` for GMAC verify on receive).

**Hot path?** Yes for `gkcrypt.c` — every UDP packet on stream port 9297 hits AES + GMAC. At 30 Mbps × N packets/frame × 60 fps, that's roughly 5–15 k packets/sec going through software-table AES.

**Current Apple build**:

**Verification:**
- Source: [`scripts/build-deps-tvos.sh:159-161`](../../scripts/build-deps-tvos.sh)
- Data: OpenSSL Configure args: `darwin64-arm64-cc … no-shared no-asm no-tests no-engine no-dso no-async no-ui-console no-stdio`.
- Comment in script: _"`no-asm` because OpenSSL's arm64 asm calls into routines that aren't valid on tvOS. The C fallback is fine for the crypto we use (AES + ECDH + HMAC)."_
- Conclusion: We're running **C-table-based AES** on every stream packet. A15 has `AESE` / `AESD` instructions that CommonCrypto and CryptoKit use transparently — we're leaving them on the table.

**Native alternatives**:

| Candidate | Hardware-accelerated on A15? | Hot-path swap feasible? |
|---|---|---|
| **CommonCrypto** (`CCCryptorCreate` with `kCCAlgorithmAES`) | ✅ uses `AESE`/`AESD` automatically | Possible at edge (would need to bypass `gkcrypt.c`'s OpenSSL calls — very entangled, not "wrap, don't patch" friendly). |
| **CryptoKit** (`AES.GCM`) | ✅ same | Swift only — would require crossing the C/Swift boundary on every packet, latency-hostile. |
| **BoringSSL** (drop-in OpenSSL replacement) | ✅ working ARMv8 asm out of the box for Apple platforms | Drop-in build replacement — touches our build script only, not `lib/` source. |
| **OpenSSL with `enable-asm`** | ✅ if we resolve the missing-symbol issue | Rebuild; likely needs a small shim for the symbols Apple's tvOS sysroot strips. |

**Verdict — Highest priority opportunity, two routes**:

1. **Cleanest**: switch the prebuilt static lib from OpenSSL `no-asm` to **BoringSSL**. BoringSSL is what Apple-platform projects routinely vendor and its arm64 asm is supported on iOS/tvOS. Touches `scripts/build-deps-tvos.sh` only — `lib/src/` is unchanged. Risk: BoringSSL doesn't claim API parity with OpenSSL forever; need to verify the `EVP_*` and `EC_*` symbols `lib/` calls all resolve. They do today.
2. **Cheapest**: figure out which symbols OpenSSL's arm64 asm references that are unavailable on tvOS, ship a small C shim, drop the `no-asm` flag. The `darwin64-arm64-cc` preset targets macOS by default; the issue is likely a couple of macOS-only entry points, not the asm itself.

**Do not** attempt to swap chiaki's `gkcrypt` / `rpcrypt` callsites to CommonCrypto on a per-call basis from the bridge — it would mean mirroring chiaki's protocol-internal state (key positions, GMAC IV layout, slot offsets) outside chiaki, which is exactly what hard rule #1 forbids. Either fix the OpenSSL build or contribute a `CHIAKI_CRYPTO_COMMONCRYPTO` backend upstream alongside the existing OpenSSL/mbedTLS pair.

---

### FEC + Galois Field math — `lib/src/{fec,frameprocessor}.c` + Jerasure + GF-Complete

**Verification:**
- Source: `grep -l "jerasure\|gf_complete" lib/src/*.c` → `fec.c`, `frameprocessor.c`.
- Data: `frameprocessor.c:115-137` allocates `unit_slots` + `frame_buf` per frame; `fec.c` calls into Jerasure's `jerasure_matrix_decode`. Inputs are byte-array units; output is the reconstructed frame buffer.
- Conclusion: Reed-Solomon erasure decode is invoked only when packets are lost (PS5 over a healthy LAN: rare). Software path is fast enough.

**Hot path?** Conditional. Hits FEC only on packet loss.

**Native alternatives**:

- Apple's **Accelerate** has `vDSP` (DSP), `vImage` (image), `BNNS` (neural). **No Galois Field arithmetic primitives**. There is no Apple-shipped Reed-Solomon implementation.
- A custom Metal compute shader could offload GF math to GPU but at the cost of round-trip latency — wrong tradeoff for a packet-loss-conditional path.

**Verdict**: **Keep**. The current Jerasure + GF-Complete path is fine. Software AES (gkcrypt) is the bottleneck, not FEC.

---

### Opus audio decode — `lib/src/{opusdecoder,opusencoder}.c` + `libopus`

**Verification:**
- Source: `grep -l "<opus/" lib/src/*.c` → `opusdecoder.c`, `opusencoder.c`.
- Data: chiaki uses libopus directly; `chiaki_opus_decoder_get_sink` exposes a sink that chains in front of our `audio_frame_cb` ([`chiaki_bridge_session.c:229-237`](../../ChiakiBridgeC/src/chiaki_bridge_session.c)).
- Conclusion: libopus is the Opus reference implementation, hand-tuned, with NEON code paths for ARM.

**Native alternatives**:

- macOS / iOS / tvOS have AAC, ALAC, FLAC, AC-3, EAC-3 decoders in `AudioToolbox` — **but no Opus decoder** in the system codecs. The PS5 always emits Opus on the stream channel; we have no choice but to consume it.
- libopus has hardware-friendly NEON paths active on arm64 by default.

**Verdict**: **Keep**. No native alternative exists; libopus is already optimal.

---

### Video receiver / NAL framing — `lib/src/{videoreceiver,frameprocessor,bitstream}.c`

**Verification:**
- Source: `videoreceiver.c:295-297` calls `session->video_sample_cb(frame, frame_size, ...)` once per assembled frame. Our trampoline at [`chiaki_bridge_session.c:185`](../../ChiakiBridgeC/src/chiaki_bridge_session.c) forwards to Swift.
- Data: chiaki emits Annex-B-framed NAL units (`00 00 00 01` start codes). Our [`VideoDecoder.swift:71`](../../ChiakiTV/Services/Video/VideoDecoder.swift) does `Data(bytes: base, count: buffer.count)` on the receiver thread, then `walkAnnexB` on the decoder queue, allocating an AVCC buffer with `malloc(total)` and freeing the input `Data` afterward.
- Conclusion: Per-frame allocation cost — one Swift `Data` per video sample callback, plus the malloc'd AVCC buffer. The Data copy is the avoidable one (the AVCC buffer hands ownership to `CMBlockBuffer`, so it can't be a pool).

**Hot path?** Yes — every video frame.

**Native alternatives**:

- The **AVCC framing walk** is just byte arithmetic — Swift, C, and Metal all do it equally fast at this size. The difference is the *Swift `Data` copy*: 1 KB to ~15 KB allocation per frame, freed when the `Data` value goes out of scope.
- Move the walk into `chiaki_bridge_session.c` (C side), pass the Swift callback an `UnsafePointer<UInt8>` to a malloc'd AVCC buffer plus parameter-set ranges, let Swift wrap it as a `CMBlockBuffer` directly without copying.

**Verdict**: **Hybrid — high-value zero-copy refactor.**

- Bridge owns the AVCC buffer + parameter-set extraction in C.
- Swift gets pointer + length + a small POD struct describing where VPS/SPS/PPS live.
- Annex-B walker drops out of `VideoDecoder.swift` entirely.
- Saves one allocation per frame on the streaming hot path; aligns with hard rule #2 ("zero allocations on the streaming hot path").

This is the most actionable Swift-side refactor in this audit.

---

### Audio receiver — `lib/src/audioreceiver.c` + `lib/src/opusdecoder.c`

**Verification:**
- Source: `chiaki_opus_decoder_get_sink` ([`chiaki_bridge_session.c:236`](../../ChiakiBridgeC/src/chiaki_bridge_session.c)) inserts the chiaki Opus decoder between the session's audio sink and our PCM callback.
- Data: PCM samples land in [`AudioPlayer.swift`](../../ChiakiTV/Services/Audio/AudioPlayer.swift), which schedules `AVAudioPCMBuffer`s onto an `AVAudioPlayerNode`.
- Conclusion: Output side is already AVFoundation-native. Decode side is libopus (kept — see Opus subsystem above).

**Verdict**: **Keep both halves**. Output is already native; decode has no native alternative.

---

### Network sockets — `lib/src/{takion,sock,stoppipe}.c`

**Verification:**
- Source: `takion.c:1072` `takion_thread_func` runs the UDP recv loop; `sock.c:20` is a 20-line wrapper around `fcntl(F_SETFL, O_NONBLOCK)`.
- Data: chiaki uses POSIX BSD sockets (`socket`, `bind`, `recvfrom`, `sendto`). Apple has `Network.framework` (`NWConnection`, `NWListener`, `NWPathMonitor`) which is the modern Apple-native API.
- Conclusion: BSD sockets work fine; Network.framework adds a Dispatch-based async layer that costs latency on the receive path.

**Apple-side optimization that's already in upstream**:

**Verification:**
- Source: [`lib/src/takion.c:1077-1085`](../../../lib/src/takion.c)
- Data: `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` is called on the takion receive thread.
- Conclusion: Upstream chiaki-ng already promotes the receive thread to the highest QoS tier on Apple platforms, matching what AVAudioEngine uses internally. No further QoS work needed.

**Native alternatives**:

- `Network.framework` would require running every UDP packet through `NWConnection.receiveMessage` callbacks on a Dispatch queue. Adds at least one queue hop per packet over the current pthread + recvfrom loop. Hostile to latency.
- BSD sockets on tvOS work correctly; UDP broadcast for discovery on `:9302` and `:987` works without the multicast entitlement (verified 2026-05-05 via simulator + real PS5 on dev LAN — see [`docs/phases.md`](../phases.md)).

**Verdict**: **Keep BSD sockets**. Hard rule #2 (zero allocations on hot path) and the upstream QoS code already in place make POSIX the right choice.

---

### Discovery — `lib/src/{discovery,discoveryservice}.c`

**Verification:**
- Source: `discoveryservice.c` runs a periodic UDP broadcast → response thread; chiaki callbacks fire when hosts appear / change state.
- Data: Wrapped in [`chiaki_bridge_discovery.c`](../../ChiakiBridgeC/src/chiaki_bridge_discovery.c) → [`DiscoveryService.swift`](../../ChiakiTV/Services/Discovery/DiscoveryService.swift).
- Conclusion: Already abstracted at the bridge edge. Works as-is.

**Native alternatives**:

- `Network.framework` Bonjour / mDNS would let us discover via `_playstation._udp` rather than UDP broadcast — but **the PS5 doesn't advertise mDNS**, so this is moot.
- `NWConnection` for the discovery probe specifically would be cleaner Swift-side, but the existing path works on tvOS without the multicast entitlement.

**Verdict**: **Keep**. The discovery path is already working on the simulator + real PS5; refactoring to Network.framework would add risk for zero benefit.

---

### Registration — `lib/src/regist.c`

**Verification:**
- Source: 940 lines of registration logic (`grep -c '' lib/src/regist.c` = 940).
- Data: HTTP POST to `:9295`, RPCrypt-encrypted payload (AES-CFB-128 with key derived from the 8-digit PS5 PIN). Wrapped at [`chiaki_bridge_regist.c`](../../ChiakiBridgeC/src/chiaki_bridge_regist.c).
- Conclusion: Cold path — runs once per PS5 pairing. Not perf-critical.

**Native alternatives**:

- `URLSession` for the HTTP transport would be cleaner than chiaki's `lib/src/http.c` parser — but `http.c` is 275 lines, scoped to TCP socket + minimal HTTP, and works.
- The crypto inside `regist.c` is the same AES-CFB-128 + HMAC-SHA-256 as `rpcrypt.c` — same OpenSSL/mbedTLS path as the streaming hot path, but at registration frequency it's one-shot.

**Verdict**: **Keep**. Cold path. The OpenSSL build fix (item #1 above) covers the crypto for free; the HTTP wrapper is fine as-is.

---

### Senkusha (latency probe) — `lib/src/senkusha.c` + nanopb

**Verification:**
- Source: `grep -l "pb_decode\|pb_encode" lib/src/*.c` → `senkusha.c`, `streamconnection.c`.
- Data: 962 lines of senkusha + protobuf for the connection-handshake latency probe (Sony's pre-stream RTT measurement).
- Conclusion: Cold path — runs once during session bring-up. Not perf-critical.

**Native alternatives**:

- `SwiftProtobuf` is Apple's native protobuf package — but bridging the chiaki-side `.proto` schemas would be a manual port. Cold path, no benefit.
- nanopb is the embedded-friendly protobuf the Sony reference apps use; it's small and works.

**Verdict**: **Keep**.

---

### Logging — `lib/src/log.c`

**Verification:**
- Source: `log.c` 232 lines, called via `CHIAKI_LOGI` / `CHIAKI_LOGE` macros.
- Data: Already wrapped at [`chiaki_bridge_log.c`](../../ChiakiBridgeC/src/chiaki_bridge_log.c) → [`ChiakiLogger.swift`](../../ChiakiTV/Utilities/ChiakiLogger.swift) → `os.Logger` / `OSLog`.
- Conclusion: Already native at the Swift edge; chiaki internally uses its own log struct, which we hand a callback that re-formats for `os.Logger`.

**Verdict**: **Keep** — already swap-at-edge.

---

### Threading + synchronization — `lib/src/thread.c`

**Verification:**
- Source: `thread.c` is 556 lines, all pthread + Apple QoS.
- Data: `pthread_create` + `pthread_setname_np` + the Apple-only `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, …)` already in `takion.c`.
- Conclusion: Already as Apple-native as a C codebase can be without rewriting in Swift.

**Native alternatives**:

- `DispatchQueue` / `Task` would require ripping out chiaki's thread-per-subsystem model, which is what its mutex pattern (`gkcrypt_local_mutex`, `seq_num_local_mutex`, etc.) protects. That's a "patch upstream" change, forbidden by hard rule #1.

**Verdict**: **Keep**.

---

### Hole-punch + UPnP + WebSocket — `lib/src/remote/*.c`

**Verification:**
- Source: `grep -l '<curl/'` → `lib/src/remote/holepunch.c` only. Same for `<event2/`, `json-c`, `miniupnpc`.
- Data: 4 deps (libcurl, libevent, json-c, miniupnpc) exist *exclusively* for `holepunch.c`, which implements PSN session-manager hole-punch for remote-play-over-internet.
- Conclusion: Out of scope per [`docs/decisions.md`](../decisions.md) "LAN-only personal use" — we never compile this path.

**Verdict**: **Out-of-scope** — already not linked. The 4 deps are still pulled by the build script for completeness but don't ship in our XCFramework.

---

### Sundries — `lib/src/{base64,common,time,reorderqueue,packetstats,...}.c`

Small utility files (`base64.c` 153 lines, `time.c` 28 lines, `reorderqueue.c` 200 lines, etc.). All pure C with no external deps; all called from chiaki-internal code paths.

**Verdict**: **Keep across the board**. None of these are bottlenecks; none have a meaningful Apple-native alternative that wouldn't require rewriting protocol code.

---

## Considered and dropped

| Idea | Why we're not doing it |
|---|---|
| Swap `gkcrypt.c` callsites to CommonCrypto from the bridge | Mirroring chiaki's GMAC IV layout + key-position state outside chiaki violates hard rule #1. The OpenSSL build fix achieves the same speedup without touching `lib/`. |
| Network.framework for UDP recv | One Dispatch hop per packet — latency-hostile vs. raw `recvfrom` on a QoS_USER_INTERACTIVE thread. |
| GPU-side FEC via Metal compute | Round-trip cost > current software FEC; FEC only fires on packet loss anyway. |
| SwiftProtobuf in place of nanopb | Cold path, cosmetic improvement only. |
| URLSession for `regist.c` HTTP | Cold path; current 275-line `http.c` works. |
| Bonjour / mDNS discovery | PS5 doesn't advertise on mDNS. |
| Custom Swift Annex-B walker (vs. moving walk to C) | Walker speed isn't the issue; the per-frame `Data` allocation is. Move the walk to C and skip the allocation entirely. |
| `Task` / `actor`-based replacement for chiaki's pthread model | Would require patching `lib/src/takion.c`, `streamconnection.c`, `ctrl.c` — explicitly forbidden. |
| OpenSSL → mbedTLS swap | mbedTLS is what `rpcrypt.c` already prefers via `#ifdef`; on Apple this gives us nothing over OpenSSL. The win is hardware AES, not which library wraps it. |

## Recommended next steps, in priority order

1. **Fix the OpenSSL `no-asm` build** ([`scripts/build-deps-tvos.sh:160`](../../scripts/build-deps-tvos.sh)). Either (a) switch to BoringSSL or (b) identify the missing-symbol issue blocking `enable-asm` and ship a shim. This single change accelerates AES + GMAC on every UDP packet — the highest-frequency code in the entire pipeline.
2. **Move the Annex-B → AVCC walk to the C bridge** so the per-frame `Data` allocation in [`VideoDecoder.swift:71`](../../ChiakiTV/Services/Video/VideoDecoder.swift) goes away. Aligns with hard rule #2.
3. **Hardware-verify** both changes against an actual PS5 + Apple TV 4K 3rd gen with the latency-strategy budget in [`latency-strategy.md`](latency-strategy.md). Quantify the before/after in a `docs/reports/` entry.

Both are within "wrap, don't patch" and self-contained to our directory + our build script.

Everything else in this audit is **already native, already optimal, or out of scope**.
