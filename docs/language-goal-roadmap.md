# ETL Language Goal Roadmap

This document defines the path from ETL's current bootstrap state to the goal
state: a small, portable language that supports ahead-of-time compilation for
normal programs and an embedded runtime compiler/VM for dynamic ETL modules.

It complements:

- `docs/ROADMAP.md` for the historical phase ladder.
- `docs/fixed-point-plan.md` for compiler-1 fixed-point work.
- `docs/runtime-vm-plan.md` for the runtime bytecode/VM path.
- `docs/backend-plan.md` for multi-backend architecture.

## Goal State

ETL should become:

- **Portable**: normal ETL programs compile ahead of time through C on the
  widest practical set of platforms.
- **Small**: few language concepts, few keywords, explicit types, regular
  grammar, and no hidden dynamic semantics.
- **Self-hosted**: the ETL compiler is written in ETL and can build a stable
  next compiler generation.
- **Runtime-capable**: an AOT-compiled ETL program can embed the ETL compiler
  frontend and run runtime-provided ETL source through the same parser, semantic
  checks, and typed representation.
- **VM-first for dynamic code**: runtime ETL compiles to portable bytecode for
  the ETL VM. Native JIT can come later as an optimization, not as the first
  runtime execution target.

## Current Baseline

As of this roadmap:

- `make check` passes.
- `make selfhost` passes.
- `scripts/c1_equiv_smoke.sh` passes the current c1 equivalence corpus.
- `make backend-vm` passes a narrow stack-bytecode smoke.
- The C backend is the serious AOT path.
- ASM and WAT/WASM have smoke subsets.
- The VM path exists only for integer expression return bytecode.

The language is usable for small controlled programs and compiler/runtime
experiments. It is not ready yet for general application development.

## Readiness Levels

### Level 0: Bootstrap Lab

ETL can compile small programs and support compiler development.

Required gates:

```sh
make check
make selfhost
make backend-vm
```

Status: in progress, mostly achieved for the current subset.

### Level 1: Self-Hosted AOT Language

ETL can build its own compiler through a stable fixed point. Compiler-0 becomes
a frozen historical bootstrap/reference implementation.

Required capabilities:

- compiler-1 can compile its own source without crashing.
- c0 -> c1 -> c2 -> c3 bootstrap chain succeeds.
- Generated compiler outputs are behavior-equivalent and normalized-output
  stable enough to compare.
- Current compiler-1 corpus is promoted, documented, and green.
- Remaining compiler-1 limitations are explicit and tested as unsupported.

Required gates:

```sh
make selfhost
make selfhost-bootstrap
scripts/c1_equiv_smoke.sh
```

Primary docs:

- `docs/fixed-point-plan.md`
- `docs/c1-corpus-expansion-plan.md`

### Level 2: Practical AOT CLI Language

ETL is usable for small real command-line tools.

Required capabilities:

- Stable `etl` CLI for compile/run/check flows.
- Clear diagnostics with file, line, column, and a short error reason.
- Stable v0 syntax and compatibility aliases.
- Minimal standard runtime for:
  - stdout/stderr
  - stdin
  - file read/write
  - allocation/free
  - panic/error exit
- Examples that are built and tested in CI.
- A published "what works / what does not" support matrix.

Required gates:

```sh
make check
make selfhost
make examples-cli
```

Exit criteria:

- A new user can write and compile a small ETL CLI program without touching
  compiler internals.
- Unsupported features fail with diagnostics, not compiler crashes.

### Level 3: Embedded Runtime ETL

A normal AOT ETL program can load runtime ETL source, compile it with the same
frontend, and execute it in the VM.

Required capabilities:

- Bytecode emitter supports:
  - integer and boolean expressions
  - locals
  - assignment
  - `if` / `elif` / `else`
  - `while`
  - function calls
  - fixed-size arrays needed by common scripts
- VM supports:
  - stack values
  - local slots
  - branches
  - call frames
  - bounded memory/stack limits
  - deterministic error codes
- Host bridge supports:
  - compile module from source buffer
  - run `main` or a named function
  - inspect return code/result
  - allowlisted imports only

Required gates:

```sh
make backend-vm
scripts/c1_vm_expr_smoke.sh
scripts/c1_vm_control_flow_smoke.sh
scripts/c1_vm_function_smoke.sh
scripts/c1_runtime_compile_smoke.sh
```

Exit criteria:

- AOT ETL host program can compile and run a small runtime ETL module.
- Runtime ETL uses the same syntax and type rules as AOT ETL.
- VM limitations are documented as host/runtime limits, not language dialect
  differences.

### Level 4: Application Runtime

ETL can build deterministic interactive or graphical applications with tested
runtime APIs.

Required capabilities:

- Deterministic clock/input/random APIs.
- Software graphics backend.
- SDL3 backend when installed.
- Example apps with golden tests.
- Runtime APIs stable enough for examples to rely on.

Required gates:

```sh
make headless-ready
make visual
make examples
```

Exit criteria:

- CLI and graphical examples are built and checked by automated gates.
- Headless deterministic tests catch output and rendering regressions.

### Level 5: Multi-Platform Distribution

ETL can be distributed as a practical toolchain.

Required capabilities:

- Linux/macOS/Windows CI matrix.
- Release artifacts.
- Install instructions.
- Versioned language spec.
- Backward compatibility policy.
- Platform support matrix for C, VM, WASM, and optional ASM/JIT paths.

Required gates:

```sh
make release-check
```

Exit criteria:

- Users can install ETL, compile examples, and run documented workflows on
  supported platforms.

## Workstreams

### A. Compiler-1 Fixed Point

Purpose: make ETL self-hosted.

Immediate tasks:

- Finish remaining c1 corpus/backend parity gaps.
- Add or refresh docs after each promoted fixture.
- Add bootstrap chain smoke.
- Freeze compiler-0 after c1 fixed point.

Do not expand language syntax in this workstream unless compiler-1 needs it to
compile itself.

### B. AOT User Experience

Purpose: make normal ETL programs pleasant enough to write and debug.

Tasks:

- Stabilize command-line interface.
- Improve diagnostics.
- Add example-focused docs.
- Add `examples-cli` gate.
- Maintain a support matrix for language/runtime features.

### C. Runtime VM

Purpose: support dynamic ETL source inside AOT-built ETL programs.

Tasks:

- Move from the current expression-only stack bytecode to locals and branches.
- Add VM equivalence gates against c0/C and c1/C results.
- Add function table and call frames.
- Add host compile/run APIs.
- Port the VM from C to ETL only after compiler-1 supports the required runtime
  structures cleanly.

### D. Runtime Library

Purpose: provide stable host APIs without turning ETL into a large language.

Tasks:

- Keep pointer values opaque.
- Keep strings as `i8[N]` plus length convention until a deliberate string type
  is needed.
- Add focused runtime APIs only when examples or compiler-1 require them.
- Keep deterministic APIs available for tests.

### E. Examples and Distribution

Purpose: prove the language is usable outside compiler tests.

Tasks:

- Build small CLI examples first.
- Add deterministic graphical examples later.
- Add installation and platform docs.
- Add release gates only after the toolchain is stable enough to version.

## Suggested Execution Order

1. Finish compiler-1 fixed point.
2. Add a stable `etl` CLI wrapper around current compile/run flows.
3. Improve diagnostics enough for normal users.
4. Expand VM bytecode to locals and branches.
5. Add VM function calls and call frames.
6. Add host compile/run APIs for runtime ETL modules.
7. Add CLI examples and an `examples-cli` gate.
8. Add visual/examples gates when runtime APIs are stable.
9. Add platform CI and release packaging.
10. Consider native JIT only after VM semantics and tests are stable.

## Non-Goals Until Level 3 Is Green

- Native machine-code JIT.
- General pointer arithmetic or dereference.
- A large standard library.
- Package manager.
- Full optimizing compiler.
- Broad ABI work beyond what compiler-1, examples, or runtime VM need next.

## Definition of Ready to Use

ETL can be called "ready to use" for small real programs when Level 2 is green.

ETL can be called "ready as an embedded scripting/runtime language" when Level
3 is green.

ETL can be called "ready for applications" when Level 4 is green.
