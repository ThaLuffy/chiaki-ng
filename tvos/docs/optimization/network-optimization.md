# Network Optimization

Most of the streaming-side network work is *already done by chiaki-lib*. This page captures what tvOS-specific levers we have and which we deliberately don't pull.

## What chiaki-lib already does

- POSIX UDP socket via [`../../lib/src/sock.h`](../../lib/src/sock.h) and [`../../lib/src/takion.c`](../../lib/src/takion.c).
- Per-packet sequencing, loss detection, FEC reconstruction.
- Congestion signal from the PS5 ([`../../lib/src/congestioncontrol.c`](../../lib/src/congestioncontrol.c)) — chiaki-lib forwards congestion ACKs back to the console; we don't override.

## Levers we pull on the tvOS side

### `SO_RCVBUF = 4 MB`

Default kernel UDP recv buffer on tvOS is small (typically 256 KB). Under bursty loss, that's not enough — the kernel drops packets at the socket layer before chiaki-lib gets a chance to run FEC.

**Plan**: in Phase 1, set `SO_RCVBUF` to 4 MB on chiaki-lib's stream socket. Sibling project does this and saw it close their largest packet-loss class. Detail: [`../../../ps-remote-play/docs/optimization/network-optimization.md`](../../../ps-remote-play/docs/optimization/network-optimization.md).

There's no chiaki-lib API to set this from the outside; we'll either patch upstream or expose a setter via the bridge.

### `IP_TOS / IPV6_TCLASS = 0x01` (ECN-Capable Transport, ECT(1))

Marks our packets as ECN-capable so a Wi-Fi 6 router with ECN-aware queues can flag (rather than drop) packets when its queue is filling. PS5 doesn't act on this — the PS5 → us direction is what matters anyway — but it's a nearly-free signal to the network on the *send* path (controller input + ACKs).

**Plan**: Phase 1 sets this on the streaming socket.

### Wi-Fi 6 vs. Ethernet

- **Ethernet** (Wi-Fi+Ethernet Apple TV model): preferred. Removes radio contention entirely. ~0.1 ms LAN latency.
- **Wi-Fi 6**: ~2 ms median, occasional bursts to 10–20 ms. Usable but the PS5 should also be on Wi-Fi 6 (or Ethernet) for the path to be consistent.

We don't surface "use Ethernet" advice in the UI — it's a personal-use port; the user knows their network.

## Levers we deliberately don't pull

- **Network.framework's `NWConnection`**: high-level, but the sibling project found it lossy at the streaming UDP scale and migrated to a BSD socket. chiaki-lib already uses BSD sockets — we don't need to rebuild this.
- **QUIC**: tvOS supports it via `NWConnection`. PS5 doesn't speak it on the streaming path.
- **MultipathTCP / MPTCP**: irrelevant for UDP streaming.
- **Custom congestion algorithm**: chiaki-lib has one. Replacing it would mean re-implementing congestion control in Swift, which is exactly the kind of "rewrite the protocol layer" we're avoiding.

## Discovery network behavior

Discovery uses `255.255.255.255:9302` UDP broadcast. On home Wi-Fi this works without any tvOS-specific setup. On segmented LANs (VLAN-isolated guest network, enterprise Wi-Fi with broadcast filtering), the broadcast is dropped and the manual host entry path is the only option.

We don't try to route around broadcast filtering with mDNS / Bonjour — it'd require the multicast entitlement and Apple review for a feature with marginal benefit on personal home networks.
