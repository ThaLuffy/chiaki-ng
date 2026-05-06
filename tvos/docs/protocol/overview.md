# Protocol Overview

> All protocol facts are owned by upstream chiaki-ng `lib/`. This page is a navigation aid with file:line citations into the upstream source. When the upstream shifts, update the upstream first, then re-cite here.

## Connection lifecycle

```
1. Discovery
   UDP broadcast to 255.255.255.255:9302 (PS5) or :987 (PS4 — out of scope)
   Source: ../../lib/src/discovery.c, ../../lib/src/discoveryservice.c
   PS5 responds with a small HTTP-flavored payload (host_id, system_version,
   running_app_titleid, etc.) → ChiakiDiscoveryHost.

2. Wake-on-LAN (if PS5 is in standby)
   PS5-specific text-based wake protocol (NOT a magic-packet WoL).
   Source: ../../lib/src/discovery.c (wake helper)

3. Registration (one-time per console + account)
   POST to https://<host>:9295/sie/ps5/rp/sess/rp
   Inner payload AES-CFB128 encrypted using key derived from PIN + 8-byte
   account ID via the `ps5_keys_0` / `ps5_keys_1` lookup tables.
   Source: ../../lib/src/regist.c
   Returns regist_key (RP key + RP regist key) — persisted by the client
   for all future sessions with this console + account.

4. Session bring-up
   HTTP request to :9295 with RP-Auth / RP-Did / RP-OSType / RP-Bitrate
   headers. PS5 responds with the Session-ID we'll use for Takion.
   Source: ../../lib/src/session.c

5. Control channel (TCP, port negotiated by session bring-up)
   RPCrypt: AES-128-CFB128 with per-counter HMAC IV, separate send/recv counters.
   Inside the RPCrypt-decrypted stream, Takion-style framing:
     INIT → COOKIE_REQ → COOKIE_ACK handshake.
     Then ECDH Big (client → PS5) / Bang (PS5 → client) protobuf messages.
   Source: ../../lib/src/ctrl.c, ../../lib/src/takion.c, ../../lib/src/rpcrypt.c

6. Stream channel (UDP, port negotiated by Big/Bang)
   GKCrypt: AES-128-CTR + truncated 4-byte GMAC. Re-keyed every 45,000 bytes.
   Source: ../../lib/src/takion.c, ../../lib/src/gkcrypt.c

7. AV streaming
   Video receiver: ../../lib/src/videoreceiver.c (HEVC NAL reassembly + FEC)
   Audio receiver: ../../lib/src/audioreceiver.c → opusdecoder.c (Opus → PCM)
   Controller sender: ../../lib/src/feedbacksender.c (state + history)
   FEC: ../../lib/src/fec.c (Jerasure-backed Reed–Solomon)
```

## Port assignments (PS5)

| Port | Purpose | Notes |
|---|---|---|
| `:9302` (UDP) | Discovery | PS5; `:987` for PS4 (out of scope) |
| `:9295` (HTTPS) | Registration + session bring-up | TLS (chiaki-lib uses libcurl) |
| Negotiated (TCP) | Control channel | RPCrypt + Takion framing |
| Negotiated (UDP) | Stream channel | GKCrypt + Takion framing |

The control TCP and stream UDP ports come out of session bring-up, not hard-coded.

## Why we don't re-document this in tvos/docs/protocol/

Because the source of truth is upstream and copying it here just creates a drift surface. The doc files in this directory exist to:

- summarize the upstream behavior with file:line citations, so an agent doesn't have to re-derive it
- highlight tvOS-specific orchestration concerns (e.g. how the bridge feeds chiaki-lib's video receiver into VideoToolbox)
- record gotchas that bit us during the port

For the actual byte layouts, key derivation, FEC matrix shapes, and packet shapes — read [`../../lib/src/`](../../lib/src/) directly. Cite line numbers when documenting.

## Reference: the sibling project's protocol docs

The sibling [`../../../ps-remote-play/docs/protocol/`](../../../ps-remote-play/docs/protocol/) contains a much deeper protocol manual derived independently. It's a useful sanity check when chiaki-lib's behavior surprises us, but it's not authoritative — chiaki-lib is.
