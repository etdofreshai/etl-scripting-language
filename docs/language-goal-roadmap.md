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

As of this roadmap (M7-release milestone):

- `make check` passes.
- `make selfhost` passes.
- `make selfhost-selfcompile` passes (c1 emits its own source; cc builds c2).
- `make selfhost-bootstrap` passes: three-stage fixed point achieved (sha256(c1_self.c)==sha256(c2_self.c)==sha256(c3_self.c)). Compiler-0 is frozen.
- `scripts/c1_equiv_smoke.sh` passes the 33-fixture c0/C vs c1/C equivalence corpus.
- `make backend-vm` passes: bytecode emit + VM return + expr + locals + control flow + functions + runtime-compile equivalence smokes.
- `make backend-subset` passes: 16 four-backend (C/VM/ASM/WAT) + 2 three-backend shared fixtures.
- `make backend-asm` passes: focused x86-64 System V assembly smokes.
- `make backend-wasm` passes: 23 WAT cases executed via wasmtime.
- `make examples-cli` passes: 4-case CLI suite (hello, calculator, file_transform, config_rules).
- `make visual` passes: tick_demo + software_pixel + Conway's Life golden + SDL3 bouncing-rect live.
- `make examples` passes: examples-cli + visual + runtime-compile (VM) example.
- `make release-check` passes: Linux x86_64 (run+test), Linux aarch64 (qemu), macOS x86_64+arm64 (build-validated), WASM/WASI (wasmtime), browser-equivalent (Node.js).
- The C backend is the durable AOT path. VM-in-ETL (M2) is shipped: `compiler1/vm.etl` implements the full VM with stack, local slots, branches, call frames, and M1 opaque-type bridges.
- ASM (x86-64 System V) and WAT/WASM backends have active validated subsets.
- M1 opaque types (ptr, str, dynarr, etlval) are shipped in c1/C and c1/VM backends.
- Wave 6d (audio runtime stub) is deferred (not in M7 scope).

The language has crossed Level 0 (Bootstrap Lab) and Level 1 (Self-Hosted AOT Language). Levels 2–5 have partial completion (see individual level gates below). General application development (Level 4) and full multi-platform distribution (Level 5) require further work listed below.

## Readiness Levels

### Level 0: Bootstrap Lab

ETL can compile small programs and support compiler development.

Required gates:

```sh
make check
make selfhost
make backend-vm
```

Status: **COMPLETE** (M0–M2 sealed; all required gates green as of M7-release).

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

Status: **COMPLETE** (M2/selfhost-bootstrap sealed; c0 frozen; 33-fixture equiv corpus green).

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

Status: **PARTIAL** — `make check`, `make selfhost`, and `make examples-cli` are green. The `etl` CLI supports compile/run/check. Diagnostics remain uneven (no file:line:col in all paths). Compatibility aliases work. Limitations: no REPL, no package manager, no incremental cache.

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

Status: **COMPLETE** (M2 sealed; `make backend-vm` green; `compiler1/vm.etl` shipped; host bridge routes through ETL VM via `ETL_VM_ETL=1`; `scripts/c1_runtime_compile_smoke.sh` passes). Limitation: emit_bytecode does not support all language constructs (see support-matrix.md).

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

Status: **COMPLETE** (M4 sealed; `make headless-ready`, `make visual`, `make examples` all green; Conway's Life golden, SDL3 bouncing-rect, scripted input all shipped). Limitation: wave 6d (audio runtime stub) deferred; not in M7 scope.

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

Status: **PARTIAL** — `make release-check` is green on this dev workstation (Linux x86_64 run+test, Linux aarch64/qemu, macOS x86_64+arm64 build-validated, WASM/WASI via wasmtime, browser-equivalent via Node.js WebAssembly API). Limitations: Windows not yet supported; install instructions not published; no versioned language spec or backward-compatibility policy yet; headless Chrome not implemented (Node.js equivalent provided instead).

## Workstreams

### A. Compiler-1 Fixed Point

Purpose: make ETL self-hosted.

Status: **COMPLETE** (M2 sealed). Three-stage fixed point achieved. Compiler-0 frozen.

Completed tasks:
- Finished c1 corpus/backend parity (33-fixture equiv corpus green).
- Bootstrap chain smoke (`make selfhost-bootstrap`) passes.
- Compiler-0 is frozen as the historical bootstrap reference.

Do not expand language syntax unless compiler-1 needs it.

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

Status: **COMPLETE** (M2 sealed). `compiler1/vm.etl` implements the full ETL VM with dispatch, stack, local slots, branches, call frames, and M1 opaque-type bridges. Host bridge routes through ETL VM via `ETL_VM_ETL=1`. 21-fixture C-VM vs ETL-VM equivalence and 20-fixture triple-equivalence (c0/C, c1/C, c1-VM-in-ETL) pass.

Completed tasks:
- Locals and branches: done.
- VM equivalence gates: done (`make vm-equivalence`).
- Function table and call frames: done.
- Host compile/run APIs: done (`etl_compile_module`, `etl_run_main_i32`).
- VM ported to ETL: done (`compiler1/vm.etl`).

Remaining limitation: emit_bytecode does not support all language constructs (see support-matrix.md).

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
