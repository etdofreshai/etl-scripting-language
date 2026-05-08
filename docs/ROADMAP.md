# ETL Roadmap

Synthesized from a three-agent council (Claude / Codex / GLM). The full
council transcripts are not committed; this is the consolidated plan.

The four-command success criterion: when these all pass, ETL has
crossed from bootstrap experiment into a real minimal scripting
language.

```sh
make check
make selfhost
make visual
make examples
```

## Status

| Phase | Status   | Landing commit |
| ----- | -------- | -------------- |
| 0     | done     | 88d0c4d        |
| 1a    | done     | a891678        |
| 1b    | done     | faa384e        |
| 1c    | done     | 1727eeb        |
| 2a    | done     | da79da0        |
| 2b    | done     | db7dfdd        |
| 3a    | done     | b28668d        |
| 3b    | done     | 18ef0df        |
| 3c    | done     | 3b47fa0        |
| 4a    | done     | d8f76aa        |
| 4b    | done     | 625c740        |
| 5     | done (selfhost-bootstrap fixed point; 33-fixture c1 equiv corpus; VM-in-ETL shipped; 16 four-backend shared fixtures; full ASM/WAT subsets) | see make selfhost-bootstrap |
| 6     | done (6a graphics shims; 6b headless visual; 6c scripted input; 6e Conway's Life golden; 6d audio stub deferred) | see make visual |
| 7     | not started (calculator, breakout, snake, asteroids, pong, CLI polish) | -            |
| 8     | not started | -            |
| 9     | not started | -            |

## Standing decisions

- Self-hosting is the critical path. Compiler-0 (Python) freezes once
  compiler-1 (in ETL) reaches a fixed point.
- Backend order: C → WASM. Native ASM and mobile are deferred.
  Multi-backend architecture documented in `docs/backend-plan.md`.
  Scaffolds in `compiler1/backend_defs.etl`, `compiler1/emit_asm.etl`,
  `compiler1/emit_wasm.etl`, and `compiler1/emit_bytecode.etl`.
- Runtime ETL uses the same compiler frontend and semantic model as AOT ETL.
  The first runtime target is portable bytecode interpreted by an ETL VM;
  native JIT is a later optimization over that path.
- Graphics/audio/input/gamepad framework: **SDL3**. Final.
- Headless visual testing: **SDL3 software renderer +
  `SDL_RenderReadPixels` → PNG**. No llvmpipe, no offscreen Vulkan.
- Block syntax: `end`-terminated. Braces are not source syntax.
- `if`/`while` conditions are strictly `bool`. No implicit truthiness.
- Pointers in v0 are opaque FFI handles only. Full `ptr T`/`&`/`*`
  arrives only when compiler-1 actually needs heap structures.
- Strings in v0 are `i8[N]` static literals + length convention. No
  string struct until needed.
- Structs land *before* self-hosting (Phase 3). Parallel-array compilers
  are not maintainable.
- Self-host equality gate: **behavior-equivalence + normalized C diff**,
  not byte-for-byte (too brittle early).
- Bundled bitmap font (Cozette/Spleen). No system fonts.
- Fake clock + scripted input + seeded RNG are mandatory in the runtime
  for headless determinism. Every example ships with input goldens from
  day one.
- Scripted input is deterministic text event replay only: one event per
  non-comment line as `tick code down`, where `tick` is a non-negative frame
  index, `code` is a non-negative key/button code, and `down` is `1` for press
  or `0` for release. The runtime reads from explicit files or byte buffers and
  never polls live devices on test paths.
- WASM does not start until the C path has shipped at least one
  graphical example.

## Phase ladder

| #  | Phase                                                                 | Gate                                                | Waves  |
| -- | --------------------------------------------------------------------- | --------------------------------------------------- | ------ |
| 0  | End-block migration + cleanup (kill `{}` lexer path; migrate examples) | `make check`                                        | 1–2    |
| 1  | `*` `/` `%`, comparisons, `bool`, unary `-`, `and`/`or`/`not`         | `make check` + fizzbuzz golden                      | 3–4    |
| 2  | `if`/`else`/`elif`/`while`, assignment, return-checking               | `make check` + `fib(10) == 55` golden               | 3–5    |
| 3  | Fixed-size arrays, structs, string literals, `sizeof`                 | linkedlist / token-array smoke                      | 4–6    |
| 4  | `extern fn` + minimal C runtime (alloc, file I/O, panic, log)         | `make smoke-runtime`                                | 3–5    |
| 5  | **Compiler-1 in ETL**                                                 | `make selfhost` (c0→c1, c1→c2, behavior-equiv corpus)| 10–16  |

> **Phase 5 status: COMPLETE.** `make selfhost-bootstrap` is green: three-stage
> fixed point achieved (sha256(c1_self.c)==sha256(c2_self.c)==sha256(c3_self.c)).
> Compiler-0 is frozen as the historical bootstrap reference.
> 33-fixture c0/C vs c1/C equivalence corpus passes. VM-in-ETL (M2) shipped:
> `compiler1/vm.etl` implements the full ETL VM with dispatch, stack, local slots,
> branches, call frames, and M1 opaque-type bridges. 16 four-backend shared fixtures
> (C/VM/ASM/WAT) plus 2 three-backend fixtures pass.
> See `docs/support-matrix.md` for the full works/experimental/unsupported matrix.
| 6  | SDL3 shim + headless screenshot harness + Conway's Life               | `make visual` (Life golden matches)                 | 6–8    |
| 7  | App ladder: calculator → breakout → snake → asteroids → pong → CLI    | `make examples`                                     | 18–24  |
| 8  | C-backend hardening + Linux/macOS/Windows CI matrix                   | matrix green                                        | 4–6    |
| 9  | WASM via `emit_wat.etl` + Canvas2D shim + Playwright screenshots      | `make wasm-examples` (Life + breakout)              | 8–12   |

**Total estimate:** ~60–88 autopilot waves. Critical path to
self-hosting is Phases 0–5 (~24–38 waves); everything after that
parallelizes.

## Phase 5 sub-tasks

- 5a: scaffold (DONE)
- 5b: lexer in ETL (DONE at a74d1e9)
- 5c: parser in ETL (DONE at a74d1e9)
- 5d: sema in ETL (DONE at ba0b94b)
- 5e: C emitter in ETL (smoke DONE; void + return-valued extern calls DONE; multi-function/user-call emission with `i32` parameters DONE at 6ab989e; narrow i32 array indexing DONE at fa722e8; narrow i32 variable-index array smoke DONE at 6df84e6; narrow local integer struct field smoke DONE at 902b736; narrow local byte string array smoke DONE at ed3d8de; narrow local byte string variable-index smoke DONE; narrow local byte array indexed assignment smoke DONE at bd10575; narrow user-defined byte-array parameter smoke DONE; narrow local struct array field smoke DONE at 6c54423; narrow byte string extern C pointer param smoke DONE at 8d72ca2; narrow by-value struct parameter smoke DONE at ec342d7)
- 5f: c0→c1 builds c1; c1 compiles fixture corpus; behavior-equivalent diff (DONE; 33-fixture corpus passes; selfhost-bootstrap fixed point achieved)
- 5g: c1→c2 fixed-point; freeze c0 (DONE; selfhost-bootstrap green; c0 frozen)

See `docs/fixed-point-plan.md` for the detailed fixed-point milestone
definition, prerequisites, worker chunks, and verification gates.
See `docs/c1-corpus-expansion-plan.md` for the ordered fixture catalog
and acceptance criteria driving the 5f emitter expansion.
See `docs/language-goal-roadmap.md` for the readiness ladder from the current
bootstrap state to a usable AOT language with an embedded runtime ETL VM.

## Risks pinned to the wall

1. **Scope creep during Phase 5.** Freeze the grammar at the start of
   compiler-1. Any feature proposal during Phase 5 is deferred to
   post-fixed-point.
2. **Pixel-test flakiness from non-determinism.** Fake clock, scripted
   input, seeded RNG, and a bundled bitmap font are non-negotiable.
3. **Structs vs parallel arrays in compiler-1.** Don't let
   "minimalism" push parallel arrays into the self-hosted compiler.
   Structs first; the cost is paid once, the benefit lasts forever.

## Workflow

This roadmap is executed by Claude (overseer) delegating sequential
tasks to subagents via the local ai-sessions server, in a fixed
provider rotation:

```
codex → codex → glm → codex → codex → glm → codex → codex → claude
```

Each task is one or more autopilot waves; each wave commits and pushes
on green. The overseer reviews diffs between tasks, advances the phase
ladder, and adjusts scope as gaps surface.

## L5 Mission Status (as of M7-release)

Milestones M0–M6 are sealed. M7 (Release) is in progress (F7.1 gates green; F7.2 docs sweep in progress; F7.3 clean-checkout and F7.4 tag pending).

| L5 Milestone | Status | Gate |
|---|---|---|
| M0 Foundation | sealed | `make check` + pre-mission gates green |
| M1 Language surface (ptr/str/dynarr/etlval) | sealed | c1/C + c1/VM, valgrind clean |
| M2 VM-in-ETL (`compiler1/vm.etl`) | sealed | `make vm-equivalence` (21 fixtures); triple equiv (20 fixtures) |
| M3 CLI samples | sealed | `make examples-cli` (4 cases) |
| M4 SDL3 live | sealed | `make visual` (Life golden + SDL3 bouncing-rect) |
| M5 Backend validation | sealed | `make backend-subset` (16+2); `make backend-asm`; `make backend-wasm` |
| M6 Multi-platform | sealed | `make release-check` (x86_64, aarch64/qemu, macOS, WASM/WASI, Node.js) |
| M7 Release | in progress | F7.1 done; F7.2–F7.4 pending |

### Remaining future work (post-M7)

- Wave 6d: deterministic audio runtime stub (deferred from M4).
- Phase 7 app ladder: calculator, breakout, snake, asteroids, pong, CLI polish.
- Phase 8: C-backend hardening + Windows CI.
- Phase 9: WASM/Canvas2D shim + Playwright screenshots.
- True headless Chrome (deferred; Node.js WebAssembly API provided instead).
- Native machine-code JIT (deferred until VM semantics and tests stable).
- Larger standard library, package manager, install instructions.
- Versioned language spec + backward-compatibility policy.
