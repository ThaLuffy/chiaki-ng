# ChiakiTV Documentation

> Complete technical documentation for AI agents and developers working on the chiaki-ng tvOS port. Start at [`../AGENTS.md`](../AGENTS.md) for the navigation map; this index is a flat backup.

## Documentation Map

### Cross-cutting
- [Decisions](decisions.md) — ADR log
- [Phases](phases.md) — implementation status

### Protocol (summarized from upstream chiaki-ng `lib/`)
- [Protocol Overview](protocol/overview.md) — connection lifecycle, port assignments, protocol stack
- [Discovery](protocol/discovery.md) — UDP broadcast on `:9302`
- [Registration](protocol/registration.md) — pairing with prefilled account ID + PIN
- [Takion Control](protocol/takion-control.md) — INIT/COOKIE handshake, RPCrypt
- [Takion Stream](protocol/takion-stream.md) — AV streaming, GKCrypt framing

### Platform
- [Apple TV Hardware](platform/apple-tv-hardware.md) — A15 Bionic capabilities, tvOS specifics
- [tvOS Frameworks](platform/tvos-frameworks.md) — VideoToolbox, Metal, GameController, AudioUnit
- [tvOS Constraints](platform/tvos-constraints.md) — sandbox, multicast, no-mic, suspend behavior

### Architecture
- [System Architecture](architecture/system-architecture.md) — module structure, threading, data flow
- [Video Pipeline](architecture/video-pipeline.md) — chiaki-lib NAL → VideoToolbox → Metal
- [Audio Pipeline](architecture/audio-pipeline.md) — chiaki-lib Opus → AudioUnit
- [Bridge Layer](architecture/bridge-layer.md) — Swift ↔ C glue design

### Optimization
- [Latency Strategy](optimization/latency-strategy.md) — sub-16 ms budget, where the bridge cost lives
- [Network Optimization](optimization/network-optimization.md) — socket config, Wi-Fi 6, ECN/DSCP

### Reference
- [Upstream Mapping](reference/upstream-mapping.md) — chiaki-ng `lib/` files ↔ tvOS-side modules
- [Build Dependencies](reference/build-deps.md) — cross-compiling OpenSSL / libcurl / opus / etc. for tvOS arm64
- [Known Issues](reference/known-issues.md) — quirks, workarounds
- [Testing Strategy](reference/testing-strategy.md) — SPM unit, hardware-only integration
- [Glossary](reference/glossary.md) — terms and abbreviations

### Reports
- [`reports/`](reports/) — per-test-run reports (mandatory protocol; see [`../CLAUDE.md`](../CLAUDE.md))
