# Compiler-0 Freeze Plan

This document tracks the path from the current state to declaring
compiler-0 (the Python bootstrap) frozen.

## Definition

Compiler-0 is **frozen** when:

1. `make selfhost-selfcompile` passes — c1 reads its own concatenated
   source from stdin, emits valid C, and that C compiles cleanly into
   a c2 binary.
2. `make selfhost-bootstrap` passes — c2 emits c1 source to identical
   bytes as c1, and c3 emits identical bytes to c2. Three-stage hash
   agreement is the fixed-point criterion.
3. The c0 path is no longer required for ongoing compiler development.
4. `docs/DESIGN.md` and `docs/ROADMAP.md` declare c0 maintenance-only.

## Current state (as of this commit)

| Stage | Status | Evidence |
|-------|--------|----------|
| c0 builds c1 (skeleton) | GREEN | scripts/c1_smoke.sh |
| c0 builds real c1 (concatenated with driver.etl) | GREEN | scripts/c1_selfcompile_smoke.sh stage 1 |
| c1 reads its own source from stdin | GREEN | driver.etl — proven by selfcompile probe |
| c1 lex on c1 source | GREEN | selfcompile probe passes lex phase |
| c1 parse on c1 source | GREEN | selfcompile probe passes parse phase |
| c1 sema on c1 source | GREEN | selfcompile probe passes sema phase |
| **c1 emit_c on c1 source** | **BLOCKED at rc=14** | `build/fixedpoint/selfcompile-status.md` |
| c0 -> c1 -> c2 -> c3 chain | NOT STARTED | bootstrap probe gates on selfcompile |

## The single remaining blocker

`compiler1/emit_c.etl` does not yet emit C for every AST shape used in
c1's own source. The driver returns rc=14 from `emit_c()` when fed the
concatenated c1 source. The exact AST shape that triggers the failure
is not reported by emit_c itself; the next chunk of work needs to:

1. Add diagnostic output to `compiler1/emit_c.etl` so it identifies
   which AST node kind it could not handle (e.g. write the failing
   node kind to stderr before returning -1).
2. Pick the smallest c1 fixture that exhibits the same shape.
3. Extend emit_c to handle that shape.
4. Re-run `make selfhost-selfcompile`; observe whether it advances or
   surfaces the next shape.

## Decomposition (from `docs/fixed-point-plan.md`)

The underlying decomposition is already in place. The remaining
chunks are roughly:

- **5f-MULTIFN** — broader multi-function coverage. Basic i32
  multi-fn already lands; remaining gaps are in struct/array/buffer
  composition.
- **5f-PARAMS** — param emission beyond the current scalar/byte-array
  set, especially extern typed params and struct returns.
- **5f-TYPES** — typed locals beyond the current set.
- **5f-ARRAYS** — broader array shapes used by c1 itself.
- **5f-STRUCTS** — broader struct emission, including struct-typed
  return values.
- **5f-STRINGS** — string literal coverage at c1 scale.
- **5f-BUFFERS** — already landed.
- **5f-SELFCOMPILE** — the smoke probe is landed; advances as gaps
  close.

Each chunk is small: pick the next AST shape that emit_c rejects, add
a c1 corpus fixture covering it (so c0 and c1 must both emit
equivalent C), extend emit_c, watch the corpus stay green, and watch
selfhost-selfcompile advance.

## Once selfhost-selfcompile passes

`make selfhost-bootstrap` will then run the three-stage chain. If
hashes agree across c1/c2/c3, the compiler is at fixed point.

After that:

1. Update `docs/DESIGN.md` bootstrap-strategy section to declare c0
   frozen.
2. Update `docs/ROADMAP.md` Phase 5 status to "done".
3. Move `compiler0/` out of the active build path (still preserved as
   historical reference); future development happens in compiler1/.

## Why this is a long-tail effort

c1 itself uses every AST shape it emits, plus a few it does not
itself emit. Every gap surfaces only when emit_c hits it on c1
source. The work is fundamentally incremental — there is no single
edit that completes it. Estimated 18–28 narrow waves per
`docs/fixed-point-plan.md`.

## Why c0 is not yet frozen in this revision

The supervisor goal that drove the recent commits (the runtime VM
path, host bridge, CLI/visual examples, support matrix, bootstrap
probe, etc.) was scoped to make the rest of the goal-state language
visible and testable. The c1 emit_c expansion is the documented
multi-week effort that gates actual c0 freeze.
