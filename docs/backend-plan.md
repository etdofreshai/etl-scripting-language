# Multi-Backend Architecture Plan

This document defines the multi-backend target architecture for ETL. The goal
is to make **C**, **ASM**, and **WASM** first-class future compilation targets
while preserving C as the current bootstrap backend.

## Current state

- **compiler-0** (`compiler0/etl0.py`): Python bootstrap compiler.
  Pipeline: `ETL source → lex → parse → AST → validate → emit_c → C text`.
- **compiler-1** (`compiler1/*.etl`): Self-hosted ETL compiler (in progress).
  Currently has `lex.etl`, `parse.etl`, `sema.etl`, `emit_c.etl`.
- Only the C backend is active. No IR layer exists yet.

## Architecture overview

```
ETL source
  │
  ▼
┌─────────┐
│  Lexer   │   (compiler0: Python, compiler1: lex.etl)
└────┬─────┘
     ▼
┌─────────┐
│  Parser  │   (compiler0: Python, compiler1: parse.etl)
└────┬─────┘
     ▼
┌─────────┐
│   AST    │   Typed AST with kind/a/b/c/token fields
└────┬─────┘
     ▼
┌─────────┐
│   Sema   │   (compiler0: Python validate(), compiler1: sema.etl)
└────┬─────┘
     ▼
┌──────────────────────────────────────────────────┐
│              Backend dispatch                     │
│                                                   │
│   ┌───────────┐  ┌───────────┐  ┌───────────┐   │
│   │ emit_c    │  │ emit_asm  │  │ emit_wasm  │   │
│   │ (active)  │  │ (future)  │  │ (future)   │   │
│   └───────────┘  └───────────┘  └───────────┘   │
└──────────────────────────────────────────────────┘
     │               │               │
     ▼               ▼               ▼
   C text          ASM text       WASM binary
                                 or WAT text
```

## Backend interface contract

Every backend emitter in compiler-1 must implement the same top-level
function signature:

```etl
fn emit_<backend>(ast AstNode[512], ast_count i32, out i8[N], out_cap i32) i32
```

- **Input**: typed AST array + count, output buffer + capacity.
- **Returns**: new write position (≥ 0) on success, or -1 on error.

All backends share:
- The same `AstNode` struct definition from `compiler1/main.etl`.
- The same AST node kind constants (`AN_PROGRAM`, `AN_FN`, etc.).
- The same token kind constants (`TK_PLUS`, `TK_IF`, etc.).

### Error codes

```etl
fn EMIT_OK() i32 ret 0 end
fn EMIT_ERR_CAPACITY() i32 ret -1 end
fn EMIT_ERR_UNSUPPORTED() i32 ret -2 end
fn EMIT_ERR_BAD_AST() i32 ret -3 end
```

These live in `compiler1/backend_defs.etl`. Future backends should use these
codes for consistent error handling.

## Backend status

| Backend   | File                  | Status      | Notes                              |
|-----------|-----------------------|-------------|------------------------------------|
| C         | `compiler1/emit_c.etl`  | **Active**  | Full arithmetic return emission    |
| ASM       | `compiler1/emit_asm.etl`| Scaffold    | Placeholder; not linked into build |
| WASM      | `compiler1/emit_wasm.etl`| Scaffold   | Placeholder; not linked into build |

## C backend (current)

The C backend translates ETL AST directly to C source text. This is the
bootstrap path and must remain fully functional at all times.

**Ownership**: The C backend emitter (`compiler1/emit_c.etl`) is owned by the
compiler-1 Phase 5 effort. Other workers should not modify it.

## ASM backend (future)

### Target: x86-64 System V / Linux initially

The ASM backend will emit x86-64 assembly text (`.s` files) that can be
assembled with `as` and linked with `ld`.

### Prerequisites

1. **Stack layout convention**: Define how ETL function frames map to x86-64
   stack frames (RBP-based, RSP-aligned).
2. **Calling convention**: Map ETL function calls to System V AMD64 ABI.
   - Integer args: RDI, RSI, RDX, RCX, R8, R9.
   - Return value: RAX.
3. **Type size map**: `i32` → 4 bytes (32-bit register operations),
   `bool` → 1 byte, `i8` → 1 byte, `ptr` → 8 bytes.
4. **Extern function support**: ETL `extern fn` calls will need a separate
   C shim or direct `call` to named symbols that the linker resolves.

### Implementation chunk

```
emit_asm.etl: emit x86-64 assembly text from AST
  - emit_asm_program: program header, data section, text section
  - emit_asm_function: function prologue/epilogue
  - emit_asm_block: statement list
  - emit_asm_return: return expression in RAX
  - emit_asm_expr: recursive expression → register allocation
```

### Delegation notes

This can be delegated as an independent chunk **after** compiler-1 reaches
self-hosting fixed point (Phase 5f). The ASM emitter must not be linked into
the main compiler-1 build until it is fully tested.

## WASM backend (future)

### Target: WASM MVP (no SIMD, no threads)

The WASM backend will emit either:
- **WAT text format** (human-readable WebAssembly text), or
- **Raw WASM binary** (compact, directly executable in runtimes).

WAT is recommended first because it is debuggable and can be validated with
`wat2wasm` from the WABT toolkit.

### Prerequisites

1. **WASM module structure**: Define how ETL programs map to WASM modules
   (memory, functions, exports).
2. **Linear memory model**: ETL locals/arrays/structs → WASM linear memory
   addresses.
3. **Function import mapping**: ETL `extern fn` → WASM `(import ...)`.
4. **Type mapping**: `i32` → `i32`, `bool` → `i32` (0/1), `i8` → `i32`
   (WASM has no 8-bit locals; load/store with alignment handles `i8`).
5. **Stack machine**: Expression evaluation uses WASM's stack machine model
   rather than registers.

### Implementation chunk

```
emit_wasm.etl: emit WAT text from AST
  - emit_wat_module: module header, memory declaration
  - emit_wat_function: function with locals, body
  - emit_wat_block: statement list
  - emit_wat_return: return expression
  - emit_wat_expr: stack-machine expression emission
```

### Delegation notes

Per ROADMAP.md standing decisions: "WASM does not start until the C path has
shipped at least one graphical example." This backend should not begin
implementation until Phase 6 (SDL3 + visual) is complete.

## IR layer (future consideration)

Currently the AST feeds directly into the C emitter. As additional backends
come online, an intermediate representation (IR) layer may become valuable:

```
AST → IR → backend-specific emitter
```

A future IR would:
- Flatten control flow into basic blocks.
- Make variable lifetimes and types explicit.
- Provide a backend-agnostic representation.

**Decision**: Do not build the IR layer yet. Let the C backend mature, and
extract common patterns when the ASM or WASM backend actually needs them.
Premature IR abstraction is a known risk.

## File inventory

| File                              | Purpose                                      |
|-----------------------------------|----------------------------------------------|
| `docs/backend-plan.md`            | This document. Architecture + delegation.    |
| `compiler1/backend_defs.etl`      | Shared backend constants (error codes).       |
| `compiler1/emit_asm.etl`          | ASM backend scaffold (placeholder).           |
| `compiler1/emit_wasm.etl`         | WASM backend scaffold (placeholder).          |
| `scripts/backend_plan_smoke.sh`   | Verifies scaffolds parse via compiler-0.      |
| `Makefile`                        | `make backend-plan` target.                   |

## Verification

```sh
make backend-plan   # Verify scaffolds compile through compiler-0
make check          # Unchanged — all existing tests must pass
make selfhost       # Unchanged — compiler-1 pipeline must pass
```

## Recommended next chunks

These chunks can be delegated to independent workers in the future:

### Chunk ASM-1: x86-64 return-only emitter
- Implement `emit_asm_program` and `emit_asm_function` for programs
  containing only `fn main() i32 ret N end` (single integer return).
- Verify: assembled and linked binary exits with code N.
- File: `compiler1/emit_asm.etl` (replace scaffold).
- Depends on: Phase 5f (self-hosting fixed point).

### Chunk ASM-2: x86-64 arithmetic expressions
- Extend ASM emitter to handle `AN_BINARY` and `AN_UNARY` expressions
  in return statements using x86-64 register operations.
- Verify: `fn main() i32 ret 1 + 2 * 3 end` → exit 7.
- Depends on: Chunk ASM-1.

### Chunk ASM-3: x86-64 locals and control flow
- Add local variable support (stack slots), `let`, assignment,
  `if`/`elif`/`else`, `while`.
- Verify: compile and run `fib(10) == 55` via ASM backend.
- Depends on: Chunk ASM-2.

### Chunk WASM-1: WAT return-only emitter
- Implement `emit_wat_module` and `emit_wat_function` for programs
  containing only `fn main() i32 ret N end`.
- Verify: `wat2wasm` produces valid binary, runtime executes with
  correct exit code.
- Depends on: Phase 6 complete (per standing decision).

### Chunk WASM-2: WAT arithmetic and locals
- Extend WASM emitter for expressions, locals, control flow.
- Verify: compile and run corpus via WASM backend.
- Depends on: Chunk WASM-1.

### Chunk IR-1: AST-to-IR lowering
- Define a minimal IR node format (basic blocks, three-address code).
- Build a lowering pass: AST → IR.
- Verify: IR output round-trips through C backend unchanged.
- Depends on: Phase 5f and at least one non-C backend at Chunk *-2.

## Constraints

- Do not modify compiler-0 behavior.
- Do not modify `compiler1/emit_c.etl` (owned by Phase 5 worker).
- ASM and WASM scaffolds must not be linked into any build target.
- `make check` and `make selfhost` must continue to pass.
