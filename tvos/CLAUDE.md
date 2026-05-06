# CLAUDE.md — ChiakiTV (chiaki-ng tvOS port) Claude instructions

## Knowledge base — use the in-tree documentation scaffold

**[`AGENTS.md`](./AGENTS.md) is the canonical knowledge base for this port.** Read it at the start of every session before doing anything else, then navigate into the relevant docs under [`docs/`](./docs/).

When you learn something durable about this port — a constraint that wasn't in the docs, a fix's root cause, an upstream API that changed, an Apple-framework quirk — **update the relevant doc in the same edit pass.** The doc scaffold is the long-term memory; do not defer the update.

### Do not write to `~/.claude/.../memory/` for this project

Claude's auto-memory system is intentionally **not used** for the chiaki-ng tvOS port. The persistence layer is in-tree, version-controllable documentation. That means:

- **Do not create** new memory files at `~/.claude/projects/-Users-thaluffy-Development-Personal-chiaki-ng/memory/` for tvOS-port content.
- The `memory/` directory at the user-level is fine for **cross-project user preferences** (something Stephano prefers across all his repos), **but project-specific knowledge belongs in [`docs/`](./docs/).**
- If you discover that something belongs in the docs but no doc exists for it, create the doc and link it from [`AGENTS.md`](./AGENTS.md). Keep the scaffold's structure — protocol docs under [`docs/protocol/`](./docs/protocol/), platform docs under [`docs/platform/`](./docs/platform/), architecture under [`docs/architecture/`](./docs/architecture/), reference under [`docs/reference/`](./docs/reference/), cross-cutting at [`docs/`](./docs/) root.

## Hard rules — non-negotiable

The full list with rationale lives in [`AGENTS.md`](./AGENTS.md#hard-rules--non-negotiable). Summary, ordered by how easy each is to violate by accident:

1. **Reuse upstream chiaki-ng `lib/`.** Never re-implement protocol values, key derivation, or packet shapes — they live in `../lib/src/`. Wrap, don't patch.
2. **Zero allocations on the streaming hot path.** No `Data` / `Array` allocations in the bridge layer between UDP receive and `VTDecompressionSession` handoff.
3. **Hardware acceleration only** — no software-decode fallbacks.
4. **Zero-copy video** — `CVPixelBuffer` (IOSurface) → `CVMetalTextureCache` → `MTLTexture`.
5. **Send controller input immediately** on value change. Never batch.
6. **LAN-only / PS5-only / Apple-TV-3rd-gen-only.** No PSN OAuth, no remote-play-over-internet, no PS4, no older Apple TVs.
7. **Read upstream chiaki-ng before changing protocol-adjacent code.** The reference is co-located in this repo at `../lib/src/` and `../gui/src/`. Cite line numbers when documenting decisions.
8. **Lock-free where possible** on the data path.

Audit every change against these.

## Working preferences for this project

These were inherited from the sibling project [`../../ps-remote-play/CLAUDE.md`](../../ps-remote-play/CLAUDE.md) and codified here for this port. They apply specifically to how you collaborate with Stephano on the chiaki-ng tvOS port.

### Test-run report-first protocol — MANDATORY

**After every test run that produces a `logs.txt`, you MUST first produce a written report at [`docs/reports/`](./docs/reports/) before doing anything else** — no code changes, no extra grep, no proposing fixes, nothing. The report is the gate.

The report must contain four sections, in order:

1. **What is going wrong** — the concrete observed symptom in *this specific* log, with citations to log lines and counts. Numbers, not narrative.
2. **Why it is going wrong** — the proximate cause inside our code, with file:line citations to the code path that produced it. If you cannot point to a specific line, the section reads "unknown — investigation required."
3. **How chiaki-ng handles it** — the corresponding code path in chiaki-ng, with file:line citations from `../lib/src/` (or `../gui/src/`). Quote the relevant snippet.
4. **How we differ from chiaki-ng** — the concrete delta, line by line. Not "we should be like chiaki-ng"; the *actual* difference between our line N and their line M.

Only after all four sections are written and saved do you propose a fix. Each fix proposal is its own next step that the user approves explicitly.

**Why:** prior sessions on the sibling ps-remote-play project wasted multiple test runs on speculative fixes that didn't move the needle, because Claude was pattern-matching from earlier summaries instead of doing the chiaki-ng comparison rigorously per run. The report enforces the comparison; the user reviews the report before any code is touched.

**How to apply:** report file is `docs/reports/YYYY-MM-DD-HH-MM-runN.md` (e.g., `2026-05-05-10-18-run5.md`). Cap each report at ~400 words; if the comparison genuinely needs more, split into a referenced sub-doc. Reports accumulate as a permanent record of "fix attempt → result" pairs.

For this tvOS port specifically, the chiaki-ng comparison is **especially load-bearing** because we explicitly reuse `lib/` rather than re-implementing it. If our behavior diverges from chiaki-ng, either (a) the bridge is wrong, (b) the platform path (VideoToolbox / AudioUnit / GameController) is wrong, or (c) we patched `lib/` and shouldn't have. The report makes the (a/b/c) split obvious.

### Capture project state in-tree before changes

For multi-session technical projects, project context lives **inside the repo**, not in Claude's memory or scratch files. When wrapping up planning for a multi-step technical project, the *first* implementation step is updating the relevant doc in this scaffold.

**Why:** durability across sessions and machines. A 52-day-old memory entry is indistinguishable from authoritative until it's wrong. Docs get reviewed in commits and travel with the code.

### Surface credible alternatives, don't bury them

When researching available tools/libraries/protocol approaches for a task, present credible alternatives — especially newer or community-preferred ones — as **decision points** rather than as background notes or "Phase 2+ upgrades."

**How to apply:** during verification phases, list each credible alternative with concrete trade-offs (latency, complexity, maturity). Use AskUserQuestion to let Stephano pick rather than defaulting silently to the established/safe option.

### Verification protocol applies here

The global verification protocol from `~/.claude/CLAUDE.md` (Source → Data → Calculation → Conclusion) applies to every factual claim about this project — protocol values, latency numbers, test counts, file paths, comparisons against chiaki-ng. When in doubt, **show the source and the data, then the conclusion.** Don't just assert.

This matters extra in this codebase because protocol values are silent failures: wrong offsets pass kilobytes of data before garbage video manifests. Document the source (e.g., `chiaki-ng lib/src/takion.c:942` or `Apple VideoToolbox docs §X`) every time.

## Code-level guidance specific to this project

The deeper layer of code guidance — Swift conventions, C conventions, naming, error handling, logging, build commands — lives in [`AGENTS.md#code-conventions`](./AGENTS.md#code-conventions) and [`docs/architecture/bridge-layer.md`](./docs/architecture/bridge-layer.md). Don't duplicate it here.

A few session-level reminders that don't fit cleanly in either of those:

- **The build has two front doors.** XcodeGen + Xcode for the full tvOS app, SPM (`swift test`) for headless bridge tests. CI / pre-commit should default to SPM; only fall back to xcodebuild when something genuinely needs the simulator.
- **chiaki-lib's API is finite and load-bearing.** [`../lib/include/chiaki/`](../lib/include/chiaki/) is the public surface. Treat it as immutable from the tvOS-port side — header changes belong upstream, not in this directory. The Swift side bridges through these via [`ChiakiBridgeC/`](./ChiakiBridgeC/).
- **Phase 1 (LAN streaming MVP) is currently the bottleneck.** No simulator can drive the full stack against a real PS5. Don't claim a streaming feature works until it has been driven against hardware. See [`docs/phases.md#phase-1--lan-streaming-mvp`](./docs/phases.md#phase-1--lan-streaming-mvp).
- **The desktop GUI in `../gui/` is a working reference** for everything we replace. When the upstream protocol output looks unexpected, run the desktop build and capture its log for comparison — the `videotoolbox` decoder fallback path on macOS exercises the same `lib/` API surface we're calling. See [`../gui/src/qmlbackend.cpp:831`](../gui/src/qmlbackend.cpp).
- **Don't touch `../lib/`, `../gui/`, `../android/`, `../switch/`, `../cli/`, `../scripts/` from a tvOS-port task.** Those are upstream. If a real bug there blocks the port, file an issue / PR upstream and document the workaround at [`docs/reference/known-issues.md`](./docs/reference/known-issues.md). The only files outside `tvos/` we own are `TVOS_PORT_INVESTIGATION.md` (the original investigation; do not delete) and a future `tvos/CMakeLists.txt`-or-equivalent integration point if and when we wire the lib build into XcodeGen.

## Personal-use scope reminder

This is a personal-use port for Stephano's living room. The success criteria are:

- One Apple TV 4K 3rd gen. One PS5. One DualSense. One LAN.
- 4K60 HDR streaming with sub-16 ms added latency vs. desktop chiaki-ng.

It is **not**:

- A community project. Don't add forums, issue trackers, telemetry, crash reporting, analytics, locale support, accessibility tooling beyond what tvOS provides for free, or anything else that's load-bearing only at scale.
- A productized App Store app. Don't add IAP scaffolding, App Store Connect metadata, paid-app guards, App Tracking Transparency prompts, etc.
- A reverse-engineering project. The protocol is already RE'd by upstream chiaki-ng. Use it.

When you're tempted to add scope, the answer is almost always "no — file it under [`docs/decisions.md`](./docs/decisions.md) as 'considered and dropped' instead."
