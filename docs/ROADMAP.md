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
| 5     | in progress (extern calls + 26-fixture c1 equiv corpus with multi-function/i32 parameter/recursive calls/Tier 2 typed bool+i8 locals/local fixed i32 array sum and loop fixtures/local i8 array fixture + 18-case backend subset + narrow i32 array indexing smoke + narrow i32 variable-index array smoke + narrow local integer struct field smoke + narrow local byte string array smoke + narrow local byte string variable-index smoke + narrow local byte array indexed assignment smoke + narrow user-defined byte-array parameter smoke + narrow scalar bool/i8/byte parameter smoke + narrow local struct array field smoke + narrow byte string extern C pointer param smoke + narrow C extern scalar bool/i8/byte parameter emission smoke + WAT i32 array indexing smoke + WAT byte/i8 array indexed assignment/read smoke + WAT byte/i8 string literal array init smoke + WAT local i32 struct field store/load smoke + WAT local struct array field store/load smoke + WAT elif chain smoke + WAT i32 helper/user function call smoke + WAT i32 extern import/call smoke + WAT byte/i8 array helper parameter indexed read/write smoke + WAT scalar bool/i8/byte helper parameter smoke + ASM i32 array indexing smoke + ASM byte/i8 array indexed assignment/read smoke + ASM byte/i8 string literal array init smoke + ASM local i32 struct field store/load smoke + ASM local struct array field store/load smoke + ASM elif chain smoke + ASM i32 helper/user function call smoke + ASM i32 extern call smoke + ASM extern scalar bool/i8/byte parameter smoke + ASM byte/i8 array helper parameter indexed read/write smoke + ASM scalar bool/i8/byte helper parameter smoke) | -        |
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
> support, multi-function/user-call emission with `i32` parameters across
> C/WAT/ASM, a
> 26-fixture c1 equiv corpus including Tier 2 typed bool/i8 locals plus local
> fixed i32 array sum, loop, and i8 array fixtures, and an 18-case shared
> C/ASM/WAT backend subset.
> `make selfhost` runs the full compiler-1 pipeline; `make headless-ready` is
> the integration gate.
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
- 5f: c0→c1 builds c1; c1 compiles fixture corpus; behavior-equivalent diff (in progress; 26 c1 corpus fixtures now pass including multi-function, `i32` parameter, recursive calls, Tier 2 typed bool/i8 locals, local fixed i32 array summation returning 100, local fixed i32 array loop indexing returning 49, and local i8 array indexing returning 72; variable-index i32 arrays, byte array indexed assignment, user-defined byte-array params, scalar bool/i8/byte params (C and WAT), struct array field read/write, by-value struct params, byte string variable-index reads, byte string extern C pointer params, multi-buffer byte strings, and C/ASM extern scalar bool/i8/byte parameter emission now proven; extern typed params beyond scalar bool/i8/byte, struct returns, and remaining struct/string corpus fixtures remain)
- 5g: c1→c2 fixed-point; freeze c0

See `docs/fixed-point-plan.md` for the detailed fixed-point milestone
definition, prerequisites, worker chunks, and verification gates.
See `docs/c1-corpus-expansion-plan.md` for the ordered fixture catalog
and acceptance criteria driving the 5f emitter expansion.

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
