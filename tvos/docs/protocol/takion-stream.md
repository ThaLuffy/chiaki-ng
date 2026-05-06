# Takion Stream Channel

> Owner: upstream chiaki-ng `lib/`. This page summarizes with citations.

## Source files

- [`../../lib/src/takion.c`](../../lib/src/takion.c) — UDP recv loop, packet types, sequencing
- [`../../lib/src/gkcrypt.c`](../../lib/src/gkcrypt.c) — AES-CTR + 4-byte truncated GMAC, key refresh every 45 KB
- [`../../lib/src/videoreceiver.c`](../../lib/src/videoreceiver.c) — frame assembly, FEC integration, NAL output
- [`../../lib/src/audioreceiver.c`](../../lib/src/audioreceiver.c) — audio packet reassembly
- [`../../lib/src/feedbacksender.c`](../../lib/src/feedbacksender.c) — controller state + history sender
- [`../../lib/src/fec.c`](../../lib/src/fec.c) — Reed–Solomon encode/decode via Jerasure

## Wire summary

After Big/Bang completes, both sides have GKCrypt keys (`gkcrypt_local`, `gkcrypt_remote`). All UDP packets on the stream channel are wrapped:

```
[type byte | sequence | key_pos | encrypted_payload | gmac_tag(4 bytes)]
```

- **type byte**: video (`0`), audio (`1`), control (`2`), feedback (`3`), congestion (`4`), heartbeat (`3` w/ specific payload), etc. Exact set in [`../../lib/include/chiaki/takion.h`](../../lib/include/chiaki/takion.h).
- **GMAC** covers the **entire packet buffer including the type byte** — sibling project's hard-learned bug, captured in their [`../../../ps-remote-play/docs/protocol/encryption.md`](../../../ps-remote-play/docs/protocol/encryption.md).
- **AES-CTR** covers AV packets only; CONTROL packets are GMAC-authenticated but plaintext payload.

We don't re-implement any of that — chiaki-lib's `gkcrypt.c` owns the dance. The bridge sees only the post-decrypt callbacks.

## Video packet layout (once decrypted)

The PS5 sends NAL units fragmented across multiple UDP packets, with a Takion AV header carrying:

- frame index (12 bits or so)
- packet index within frame
- packet count for frame
- whether this is the first NAL or a continuation
- HEVC slice type hints
- (optional) HDR10 metadata SEI piggyback

`videoreceiver.c` reassembles, runs FEC if any packets are missing, and emits complete NAL units via the `ChiakiVideoSampleCallback`. That's the surface our Swift bridge sees.

## Audio packet layout

Smaller. Each packet is one Opus frame (240 or 480 samples). `audioreceiver.c` emits via the audio sink callback after Opus decode in `opusdecoder.c`.

## Controller (outbound)

`feedbacksender.c` packetizes two flavors:

- **Feedback State** (every 10 ms or on change) — sticks, motion, triggers, touchpad continuous state
- **Feedback History** (event-driven) — button down / up, touchpad finger events

Both are sent immediately, never batched. Hard rule #5 in [`../../AGENTS.md`](../../AGENTS.md).

## FEC

Reed–Solomon erasure code via Jerasure. Configurable redundancy ratio (set in the Big launch spec). The PS5 sends `k` data packets + `m` parity packets per frame group; if up to `m` packets are lost, FEC reconstructs them.

If FEC fails (more than `m` lost), `videoreceiver.c` flags the frame as corrupt and chiaki-lib sends a CORRUPTFRAME control message asking the PS5 to issue an IDR. Without that signal, the stream stalls on the next P-slice referencing the missing frame.

## What the tvOS-side bridge handles

Nothing on the per-packet path beyond:

1. Receive a callback from chiaki-lib's video receiver (a fully reassembled NAL unit).
2. Receive a callback from chiaki-lib's audio receiver (a decoded PCM frame).
3. Send controller state via `chiaki_session_set_controller_state` (one call per `GCController` value-changed event).

That's it. The encryption, sequencing, FEC, and reassembly all stay in C.

## What the tvOS-side bridge does **not** handle

- Decrypting packets (chiaki-lib).
- Verifying GMAC (chiaki-lib).
- Reassembling NAL units (chiaki-lib).
- Detecting frame_index gaps and signaling CORRUPTFRAME (chiaki-lib).
- Re-keying GKCrypt every 45 KB (chiaki-lib).

If any of those starts behaving unexpectedly, the fix is in `lib/`, not in `tvos/`.
