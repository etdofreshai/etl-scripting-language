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
| 5     | in progress (extern calls + 18-case backend subset active) | -        |
| 6     | not started | -            |
| 7     | not started | -            |
| 8     | not started | -            |
| 9     | not started | -            |

## Standing decisions

- Self-hosting is the critical path. Compiler-0 (Python) freezes once
  compiler-1 (in ETL) reaches a fixed point.
- Backend order: C → WASM. Native ASM and mobile are deferred.
  Multi-backend architecture documented in `docs/backend-plan.md`.
  Scaffolds in `compiler1/backend_defs.etl`, `compiler1/emit_asm.etl`,
  `compiler1/emit_wasm.etl`.
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

> **Phase 5 status: IN PROGRESS.** `compiler1/` now has lexer, parser,
> semantic validation, C emission with void and return-valued extern call
> support, and an 18-case shared C/ASM/WAT backend subset. `make selfhost`
> runs the full compiler-1 pipeline; `make headless-ready` is the
> integration gate.
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
- 5e: C emitter in ETL (smoke DONE; void + return-valued extern calls DONE)
- 5f: c0→c1 builds c1; c1 compiles fixture corpus; behavior-equivalent diff (next)
- 5g: c1→c2 fixed-point; freeze c0

See `docs/fixed-point-plan.md` for the detailed fixed-point milestone
definition, prerequisites, worker chunks, and verification gates.

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
