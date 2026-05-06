# Takion Control Channel

> Owner: upstream chiaki-ng `lib/`. This page summarizes with citations.

## Source files

- [`../../lib/src/takion.c`](../../lib/src/takion.c) — INIT/COOKIE handshake, sequence numbering, packet framing
- [`../../lib/src/ctrl.c`](../../lib/src/ctrl.c) — control-channel orchestration, GENERIC chunks, ECDH big/bang exchange
- [`../../lib/src/rpcrypt.c`](../../lib/src/rpcrypt.c) — RPCrypt cipher wrapping the control TCP stream
- [`../../lib/src/streamconnection.c`](../../lib/src/streamconnection.c) — orchestrates the whole session including bringing up the GKCrypt-encrypted stream channel after Big/Bang

## What flows here

The control channel rides on top of TCP between the client and the PS5 (port negotiated by session bring-up). Inside the TCP stream:

```
Outer wrap: RPCrypt (AES-128-CFB128 with HMAC-derived IV per packet,
                     separate 32-bit send/recv counters).
Inner: Takion-style framing — INIT, COOKIE_REQ, COOKIE_ACK,
       DATA_ACK, DATA, DATA_FRAGMENT, CONTROL chunks, etc.
       (SCTP-style framing layered on TCP.)
```

The DATA chunks carry **TakionMessage** protobuf payloads (definitions in [`../../lib/protobuf/`](../../lib/protobuf/)). The two big ones for handshake:

- **Big** (client → PS5): ECDH ephemeral pubkey, encrypted launch spec, etc.
- **Bang** (PS5 → client): ECDH ephemeral pubkey, GKCrypt seed, accepted negotiation parameters.

After Bang, both sides derive GKCrypt keys (see [`../../lib/src/gkcrypt.c`](../../lib/src/gkcrypt.c)) and the stream UDP channel comes up.

## Heartbeats — there are two

Critical gotcha (rediscovered by the sibling project, see [`../../../ps-remote-play/docs/protocol/takion.md#heartbeats--there-are-two-and-you-need-both`](../../../ps-remote-play/docs/protocol/takion.md)):

1. **Takion-level heartbeat** — client-driven, every 1000 ms, channel 1 PayloadType=3 over the stream UDP. chiaki-lib's `lib/src/takion.c` runs this internally; we don't have to drive it ourselves but we must not interfere with the timing.
2. **TCP control HEARTBEAT_REQ / HEARTBEAT_REP** — initiated by the PS5 over the control TCP. chiaki-lib responds inside `ctrl.c`.

If we somehow squelch one of these (e.g. by parking chiaki-lib's worker thread), the PS5 fires `DISCONNECT reason="heartbeat failure"` after ~5 s. The bridge layer must not block these threads.

## tvOS-side wrapper plan (Phase 1)

There is **no** tvOS-side wrapper for the control channel — chiaki-lib owns the entire control-channel state machine. The bridge surfaces only:

- A session-event callback (connecting / connected / disconnected / regist-event-style codes).
- Errors translated from `ChiakiQuitReason` into Swift `enum`.

The Swift side never sees individual control packets. If a control-flow bug surfaces, it's debugged in `lib/src/ctrl.c` upstream, not in `tvos/`.

## When this matters in tvOS-land

The control channel comes up before the streaming UDP. While that handshake is in flight, the UI shows a spinner. The `ChiakiSession` event callbacks are the source of truth for whether to flip the UI from "Connecting…" to "Streaming."
