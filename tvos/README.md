# ChiakiTV

A tvOS port of [chiaki-ng](../) — PlayStation 5 Remote Play on **Apple TV 4K 3rd gen**, optimized for **local-network play** with a sub-16 ms added-latency target.

```
    ┌──────────────────────────────┐         ┌─────────────────────┐
    │  ChiakiTV (Swift, tvOS)      │         │                     │
    │  SwiftUI · MVVM · Services   │  Wi-Fi  │      PlayStation 5  │
    │       │                      │ ◄─────► │                     │
    │  ChiakiBridgeC (Swift ↔ C)   │   LAN   │   Takion v12        │
    │       │                      │         │                     │
    │  chiaki-lib (../lib/, C)     │         │                     │
    │  Takion · AES · GMAC · FEC   │         │                     │
    └──────────────────────────────┘         └─────────────────────┘
```

This port reuses the protocol library from chiaki-ng (`../lib/`) wholesale and replaces the desktop Qt GUI with a native Swift/SwiftUI app for tvOS. Personal use, single LAN, single PS5, single DualSense.

## Where to look

This README is intentionally short. Everything technical lives in the in-tree documentation scaffold:

- **Start here:** [`AGENTS.md`](./AGENTS.md) — the navigation hub. Documentation map, hard rules, glossary.
- **Specific topic?** Each protocol layer / platform constraint / architectural module has its own doc under [`docs/`](./docs/).
- **Why was X chosen over Y?** [`docs/decisions.md`](./docs/decisions.md).
- **What's built / what's next?** [`docs/phases.md`](./docs/phases.md).
- **Why a separate port instead of patching the desktop GUI?** [`../TVOS_PORT_INVESTIGATION.md`](../TVOS_PORT_INVESTIGATION.md).

## Requirements

| Component | Requirement |
|---|---|
| Apple TV | Apple TV 4K 3rd gen (2022, A15 Bionic) |
| tvOS | 17.0+ |
| PlayStation | PS5 (any model, recent firmware) |
| Network | Same LAN as PS5; Wi-Fi 6 or Gigabit Ethernet recommended |
| Controller | DualSense (standard or Edge) |
| PSN account ID | **Prefilled in settings** — get it from the desktop chiaki-ng with `chiaki-ng list` once you've registered there |

## Quick start

```bash
brew install xcodegen           # one-time
cd tvos
xcodegen generate               # produces ChiakiTV.xcodeproj from project.yml
open ChiakiTV.xcodeproj         # Xcode 15+, build the ChiakiTV target
```

Headless C-bridge + Swift services tests:

```bash
cd tvos
swift test
```

## Scope

**In scope (LAN-only personal use):**

- LAN discovery (UDP broadcast on `:9302`)
- Manual host entry (IP) for networks where broadcast is filtered
- One-time registration with prefilled PSN account ID
- 4K60 HDR HEVC streaming via VideoToolbox + Metal
- Stereo Opus audio via AudioUnit
- DualSense input via GameController.framework

**Out of scope (explicitly dropped, not deferred):**

- PSN OAuth flow (account ID is prefilled — get it from the desktop chiaki-ng)
- Remote Play over the Internet (RUDP / STUN / hole-punching)
- PS4 / PS4 Pro support
- Apple TV HD / older 4K models
- Microphone / voice chat (Apple TV has no mic)
- App Store distribution
- Multi-user / multi-host management beyond a small LAN list

For the why behind each, see [`docs/decisions.md`](./docs/decisions.md).

## Conventions

This README is the only doc written primarily for a human. Everything else is structured for an LLM agent (Claude, Cursor) to navigate and update — see [`AGENTS.md`](./AGENTS.md) and [`CLAUDE.md`](./CLAUDE.md). When in doubt, follow the link from the relevant entity doc rather than duplicating content here.

## License

This port is part of the chiaki-ng project and inherits its **AGPLv3** license — see [`../COPYING`](../COPYING) and [`../LICENSES/`](../LICENSES/).

## Acknowledgments

ChiakiTV is a frontend over the existing [chiaki-ng](https://streetpea.github.io/chiaki-ng/) protocol library. All protocol-level reverse engineering credit belongs to the chiaki and chiaki-ng communities.
