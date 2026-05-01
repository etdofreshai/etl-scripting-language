# Self-Improvement Roadmap

This document defines the practical path from ETL's current headless-ready
state to a self-improving language loop: a compiler that can evaluate and
improve itself through deterministic, headless-verified cycles.

It complements the phase ladder in `docs/ROADMAP.md` (sequencing) and the
design philosophy in `docs/DESIGN.md` (long-term vision). This document is
about *how the language self-evaluates today and what each next step unlocks*.

## What the language can self-evaluate today

The `make headless-ready` gate proves the current self-evaluation surface:

| Capability | Gate target | What is checked |
|---|---|---|
| Compiler-0 correctness | `make check` | Tests, smoke suite, runtime tests |
| Compiler-1 pipeline | `make selfhost` | Lex/parse/sema/emit stages pass |
| Backend plan scaffolds | `make backend-plan` | ASM scaffold compiles |
| Shared backend subset | `make backend-subset` | C, ASM, WAT agree on small corpus |
| WAT/WASM smoke | `make backend-wasm` | WAT text validates, optionally runs |
| Deterministic stdout | `make headless-selfeval` | Exit codes, golden files, repeatability |
| Trace artifacts | `make selfeval-trace` | CSV artifact content + SHA-256 |
| Software framebuffer | `make graphics-software` | PPM output, pixel values, hash |
| SDL3 graphics | `make graphics-headless` | Skip-safe; runs when SDL3 present |

Self-eval programs (`examples/selfeval/`) currently exercise:
- Tick counters (`tick_counter.etl`) — stdout-only state progression.
- State cycles (`state_cycle.etl`) — multi-state simulation with deterministic output.
- Trace artifacts (`trace_artifact.etl`) — CSV tick/state pairs written to disk alongside stdout.

The language can evaluate its own compiler pipeline (compiler-0 builds
compiler-1, compiler-1 produces output) and verify that the output is
deterministic. It cannot yet evaluate graphical programs through the
self-hosted compiler, nor can it modify its own source and re-verify.

## Self-evaluation mechanisms

### Console logs

Every self-eval program prints structured state via `etl_print_i32` to stdout.
The harness captures stdout and compares it against golden `.expected` files.
Console logs are the primary contract for numeric/state verification.

Use console logs for:
- Verifying integer arithmetic and control flow.
- Tracking tick-by-tick state transitions.
- Detecting non-determinism (run twice, diff output).

### Trace artifacts

Programs that need persistent state records write CSV artifacts under
`build/selfeval/`. The current format is:

```
tick,state
0,0
1,3
2,7
...
```

The harness checks artifact existence, content against a golden, and SHA-256
byte-for-byte repeatability. Trace artifacts and console logs contain the same
tick/state values but serve different purposes: stdout is ephemeral and
human-readable in CI logs; the artifact is persistent and hash-comparable.

Use trace artifacts for:
- Programs that need offline state inspection after the run.
- Detecting byte-level regressions across commits.
- Providing input to future visualization or analysis tools.

### Ticks and states

Self-eval programs model simulation as a sequence of ticks. Each tick advances
a deterministic state. The current convention is:

- Programs print `(tick, state)` pairs, one per line.
- The golden file documents what each line represents.
- Trace artifacts use the same values in CSV form.

This convention will extend naturally to graphical programs: each tick renders
one frame, producing a PPM screenshot alongside the tick/state log.

### Screenshots and PPM artifacts

The software framebuffer (`runtime/etl_graphics_software.c`) renders to binary
PPM files under `build/graphics/`. Each PPM has a SHA-256 sidecar for exact
byte comparison.

The verification chain for graphical self-eval:

```
tick N → state S(N) → stdout + CSV → render(S(N)) → framebuffer F(N) → PPM + sha256
```

Use PPM artifacts for:
- Detecting pixel-level rendering regressions.
- Verifying that the software and SDL3 backends produce identical output.
- Providing deterministic visual output on headless CI.

### Backend equivalence

The shared backend subset (`make backend-subset`) runs a small corpus through
all three compiler-1 backends. C and ASM produce native executables; WAT is
text-validated and optionally executed.

Backend equivalence is checked by:
- Exit codes (all backends return the same integer).
- WAT text validation (structural correctness).
- Optional WASM runtime execution when tools are available.

Backend equivalence is the foundation for trusting that the self-hosted
compiler can target multiple platforms without behavioral divergence.

## Phase order: current state to self-hosting

### Phase 5 (in progress): Compiler-1 in ETL

**Current state**: lex, parse, sema, and C emitter smokes are landed. The
compiler-1 pipeline compiles via compiler-0 and produces C output for a
growing subset.

**Self-eval relevance**: Once compiler-1 can compile the full v0 corpus with
behavior-equivalence to compiler-0, it becomes the first self-improvement
loop candidate. Compiler-0 builds compiler-1; compiler-1 can be modified to
improve its own output, and the self-eval harness verifies correctness.

**Remaining sub-tasks**:
- 5f: c0→c1 builds c1; c1 compiles fixture corpus; behavior-equivalent diff.
- 5g: c1→c2 fixed-point; freeze c0.

### Phase 6 (not started): Graphics and visual testing

**Gate**: `make visual` (Conway's Life golden matches).

**Self-eval relevance**: Graphics programs extend the tick/state model to
include rendered frames. Each tick produces both a console log and a PPM
screenshot. The self-eval harness verifies visual output deterministically
without a display.

**What this unlocks**: Visual regression testing for all future graphical
programs and games. The software framebuffer provides the portable floor;
SDL3 adds hardware-accelerated verification when available.

### Phase 7 (not started): Application ladder

**Gate**: `make examples` (calculator through pong).

**Self-eval relevance**: Real applications stress-test the language, runtime,
and graphics pipeline. Each example ships with scripted input, golden output,
and (for graphical examples) screenshot goldens.

**What this unlocks**: Confidence that the language can express non-trivial
programs before committing to self-hosted compiler improvements.

### Phase 8 (not started): Cross-platform hardening

**Gate**: Linux/macOS/Windows CI matrix green.

**Self-eval relevance**: The self-improvement loop must be portable. If
compiler-1 can only build on one platform, it cannot safely modify itself
on others. Cross-platform CI ensures that improvements verified on one
platform hold on all platforms.

### Phase 9 (not started): WASM backend

**Gate**: `make wasm-examples` (Life + breakout in browser).

**Self-eval relevance**: WASM is the long-term portable target. Once the
WASM backend can run the self-eval corpus, the language can self-improve
across native and web runtimes.

**Standing decision**: WASM does not start until the C path has shipped at
least one graphical example (Phase 6).

## The self-improvement loop

The eventual self-improvement loop has four stages:

### Stage 1: Evaluate

The harness runs the current compiler against the self-eval corpus and
records:
- Compilation success/failure.
- Backend output (C, ASM, WAT text).
- Runtime output (stdout, exit codes).
- Artifacts (traces, PPM screenshots, hashes).

All results are deterministic and repeatable.

### Stage 2: Compare

The harness compares new results against golden baselines:
- stdout diff against `.expected` files.
- Trace artifact diff against `.artifact` goldens.
- PPM SHA-256 comparison.
- Backend equivalence check across C/ASM/WAT.

A regression is any change in output that is not an intentional golden update.

### Stage 3: Modify

A human or AFK worker modifies the compiler, runtime, or self-eval programs.
Modifications must be:
- Small (one concern per commit).
- Isolated (no cross-cutting changes to unrelated systems).
- Compatibility-preserving (existing goldens must still pass, or be
  intentionally updated with documented justification).

### Stage 4: Re-verify

The harness re-runs after modification. If all gates pass, the modification
is accepted. If any gate fails, the modification is rejected or the goldens
are updated with explicit justification.

This cycle repeats. The language improves itself through verified,
deterministic increments.

## AFK worker chunk contract

Future AFK worker chunks must follow these rules:

### Size and scope

- One concern per chunk. A chunk is either documentation, a single new
  self-eval program, a backend improvement, or a compiler fix — not a mix.
- Chunks must pass `make headless-ready` before committing.
- Chunks must not modify compiler-0 unless fixing a bug that breaks an
  existing test.

### Isolation

- Chunks must not modify files owned by in-progress work in other chunks.
  Check `docs/ROADMAP.md` for ownership notes (e.g., `emit_c.etl` is owned
  by Phase 5).
- Chunks must not add new keywords or types without updating
  `docs/platform-vocabulary.md` simultaneously.
- Chunks must not change the self-eval contract in `docs/selfeval.md`
  without coordinating with the supervisor.

### Compatibility preservation

- Existing golden files must not change unless the chunk intentionally
  updates them with documented justification.
- New self-eval programs must follow the existing MANIFEST and `.expected`
  conventions.
- New backends must be skip-safe (detect missing tools, print SKIP, exit 0).
- The software framebuffer must never acquire a dependency beyond the C
  standard library.

### Documentation

- Each chunk that adds a new gate, artifact type, or backend must update
  this document and `docs/platform-vocabulary.md`.
- Each chunk that changes the `make headless-ready` surface must update
  `docs/selfeval.md`.
- Each chunk that advances a phase must update `docs/ROADMAP.md`.

## Non-goals

This roadmap explicitly does not cover:

- **Automated code generation by the language itself.** ETL does not write
  its own code yet. The self-improvement loop is currently human/AFK-driven.
- **Machine learning or neural components.** Self-improvement means verified
  deterministic improvement cycles, not learned optimization.
- **Hot reloading or live patching.** The loop is compile-verify-commit,
  not runtime mutation.
- **Performance optimization as a self-eval metric.** The current metrics
  are correctness, determinism, and backend equivalence — not speed.
- **Self-hosting before Phase 5g.** The language cannot modify its own
  compiler until compiler-1 reaches fixed point.
- **Floating-point, closures, exceptions, generics, or GC.** These are
  deferred per standing decisions in `docs/ROADMAP.md`.
- **Mobile or console targets.** These are Phase 8+ concerns.
- **IR layer.** AST currently feeds directly to emitters. An IR layer
  should be extracted only when at least two non-C backends need shared
  lowering logic (per `docs/backend-plan.md`).

## Unsupported areas

The following are intentionally unsupported in the current self-eval surface:

| Area | Status | Reason |
|---|---|---|
| Floating-point self-eval | Not supported | No floating-point types in v0 |
| String-output self-eval | Partial | String literals exist but self-eval checks integer stdout |
| Multi-file programs | Not supported | No module system (`use` is reserved, unused) |
| Interactive input self-eval | Not supported | Scripted input exists but is not yet wired into self-eval |
| PNG output | Not supported | PPM only; PNG requires external library |
| WASM binary emission | Not supported | WAT text only; binary emission is future work |
| Parallel test execution | Not supported | Tests run sequentially for determinism |
| Benchmarking | Not supported | Self-eval measures correctness, not performance |

## Key files

| File | Role |
|---|---|
| `docs/selfeval.md` | Self-eval contract and harness usage |
| `docs/backend-plan.md` | Multi-backend architecture and delegation chunks |
| `docs/graphics.md` | Headless graphics API and artifact contract |
| `docs/platform-vocabulary.md` | Compatibility tiers and worker guidance |
| `docs/ROADMAP.md` | Phase ladder and standing decisions |
| `docs/DESIGN.md` | Long-term language design philosophy |
| `Makefile` | Gate targets (`headless-ready`, `selfeval-all`, etc.) |
| `examples/selfeval/MANIFEST` | Self-eval program registry |
