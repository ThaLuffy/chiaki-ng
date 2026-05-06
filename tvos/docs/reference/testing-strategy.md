# Testing Strategy

## Layers

### Unit (SPM, headless)

`swift test` from `tvos/`. Runs on the dev machine without a tvOS simulator.

| What it covers (Phase 1) | Where |
|---|---|
| C bridge symbols are reachable from Swift | [`../../Tests/ChiakiBridgeCTests/`](../../Tests/ChiakiBridgeCTests/) |
| Codable round-trips for `Host`, `RegisteredHost`, settings | [`../../Tests/ChiakiTVTests/`](../../Tests/ChiakiTVTests/) |
| Controller-state mapping (`GCDualSenseGamepad` → `chiaki_controller_state_t`) | (Phase 1) |
| Ring buffer correctness | (Phase 1, Utilities/) |

The C bridge tests don't exercise chiaki-lib's protocol logic — that's owned upstream and tested in [`../../../test/`](../../../test/). We test only the bridge surface.

### Integration (Xcode, simulator)

`xcodebuild` against the Apple TV simulator. Covers:

- The Swift app boots without crashing.
- Views render (snapshot tests, optional).
- AppState transitions work end-to-end.

The simulator can't drive VideoToolbox HW decode + GameController + a real PS5, so nothing past "the app boots" is testable here.

### Hardware (manual)

The only path that exercises the full pipeline. Requires:

- Apple TV 4K 3rd gen
- PS5
- Same LAN
- DualSense controller

Manual checklist (Phase 1, will become a script):

1. Sideload via Xcode → Apple TV.
2. Set the prefilled account ID + register against the PS5.
3. Connect — verify video pixel arrival within 5 s of starting the session.
4. Verify audio plays without underrun for 60 s.
5. Verify DualSense button → on-screen action latency feels native (subjective).
6. Drive the test for 5 minutes; check for stalls / IDR storms / audio overflows.
7. Capture `Console.app` log filter `subsystem=org.streetpea.chiakitv`, save to `tvos/logs.txt`, and **write the four-section report** at `tvos/docs/reports/YYYY-MM-DD-HH-MM-runN.md` per [`../../CLAUDE.md`](../../CLAUDE.md#test-run-report-first-protocol--mandatory).

## What we don't test

- **Protocol correctness in isolation.** chiaki-lib already has a unit-test suite at [`../../../test/`](../../../test/). We don't duplicate it. If we re-implement any part of the protocol path on the tvOS side, that becomes test surface — but the whole point of the port is to *not* re-implement.
- **Performance microbenchmarks of the decode path.** VideoToolbox's reported decode time is sufficient evidence; we don't need a sub-millisecond stopwatch.
- **Cross-device compatibility.** Single device target.

## Pre-flight checks

Before declaring any change done:

```bash
cd tvos
swift test                           # bridge + Swift unit tests
xcodegen generate                    # confirm project regenerates clean
xcodebuild -scheme ChiakiTV \
    -destination "generic/platform=tvOS" \
    -configuration Debug build       # confirm Xcode build still works
```

If a streaming-relevant change is in scope: add the hardware run as the gating step. Don't claim a streaming feature works until it has been driven against a real PS5.
