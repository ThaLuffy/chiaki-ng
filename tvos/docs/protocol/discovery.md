# Discovery

> Owner: upstream chiaki-ng `lib/`. This page summarizes with citations.

## Source files

- [`../../lib/src/discovery.c`](../../lib/src/discovery.c) — packet format, broadcast send, response parse
- [`../../lib/src/discoveryservice.c`](../../lib/src/discoveryservice.c) — periodic broadcast loop, host bookkeeping
- [`../../lib/include/chiaki/discovery.h`](../../lib/include/chiaki/discovery.h) — port + protocol-version constants

## Wire summary

- Send: UDP datagram from any source port to **`255.255.255.255:9302`** (PS5).
- Payload: `SRCH * HTTP/1.1\ndevice-discovery-protocol-version:00030010\n\n` (PS5 protocol version is `00030010`; PS4 uses `00020020` and port `:987`, both out of scope).
- Receive: PS5 unicasts an HTTP-style response with fields `host-id`, `host-name`, `host-type`, `running-app-titleid`, `system-version`, `device-discovery-protocol-version`, etc.

## Socket setup gotcha (chiaki-lib)

chiaki-lib calls `setsockopt(SOL_SOCKET, SO_BROADCAST, 1)` at [`../../lib/src/discovery.c:213`](../../lib/src/discovery.c) before sending the broadcast. That syscall is what tvOS *might* gate behind the multicast entitlement — but in practice on tvOS 17 it works on a personal-team-signed build. See [`../platform/tvos-constraints.md#multicast--broadcast`](../platform/tvos-constraints.md).

## tvOS-side wrapper plan (Phase 1)

`PSSwiftPlay/Services/Discovery/DiscoveryService.swift` (port name TBD; sibling project uses `DiscoveryService`) wraps `chiaki_discovery_service_*` via the bridge:

- `chiaki_discovery_service_init`
- `chiaki_discovery_service_start`
- a discovery callback that fires on each `ChiakiDiscoveryHost` change
- `chiaki_discovery_service_fini` on teardown

The callback flows up through `ChiakiBridgeC` → Swift `@MainActor` → `@Published var hosts: [Host]` on the view model. Discovery is *not* a hot-path; it's fine to allocate when a new host appears.

## Manual host entry path

For LAN setups that filter UDP broadcast (rare on home Wi-Fi, common in office / cafe networks), the user types an IP into the host-list view. We instantiate a synthetic `ChiakiDiscoveryHost` with just the IP populated and proceed to registration. This mirrors the desktop's `gui/src/qml/ManualHostDialog.qml`.
