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

| Backend | File | Status | Notes |
|---------|------|--------|-------|
| C | `compiler1/emit_c.etl` | Active | Compiler-1 source-to-C backend for the current Phase 5 subset, including multi-function programs, user-defined `i32` and narrow byte/i8 array parameters, and narrow by-value struct parameters. |
| ASM | `compiler1/emit_asm.etl` | Active smoke subset | Emits x86-64 System V assembly with locals, arithmetic, comparisons, logical ops, `if`/`elif`/`else`, `while`, local `i32` array declaration plus constant-index and variable-index read/write, local `byte[N]`/`i8[N]` array indexed assignment/read via `movsbq`/`movb`, local `byte[N]`/`i8[N]` string literal initialization with constant-index reads, local struct declaration with i32 field store/load, local fixed struct array indexed field store/load, multiple user-defined i32-parameter/i32-return helper functions with direct intra-module calls, helper `byte[N]`/`i8[N]` array parameter indexed reads/writes via saved base pointers and `movsbq`/`movb`, and source `extern fn` declarations with `i32`/`integer` params and `i32` return lowered to direct `call` to named symbols resolved by the linker; assembled and linked by smoke tests. |
| WAT/WASM | `compiler1/emit_wasm.etl` | Active WAT subset | Emits WAT text with locals, arithmetic, comparisons, logical ops, `if`/`elif`/`else`, `while`, boolean literals, local `i32` array declaration plus indexed read/write, local `byte[N]`/`i8[N]` array indexed read/write including string literal initialization, helper `byte[N]`/`i8[N]` array parameter indexed reads/writes via `i32.load8_s`/`i32.store8` (param passed as i32 base pointer), local struct declaration with i32 field store/load, local fixed struct array indexed field store/load, multiple user-defined i32-parameter/i32-return helper functions with direct calls (`_start` exported as `main`), and source `extern fn` declarations with `i32`/`integer` params and `i32` return lowered to `(import "env" ...)` with `call $name`; smoke validates text and executes when tools are installed. |

## Shared backend subset smoke

`make backend-subset` runs a deliberately small corpus through all three
compiler-1 backends. C and ASM outputs are compiled to native executables and
their exit codes are checked. WAT output is always text-validated; when
`wat2wasm` plus `wasmtime` or `wasmer` are available, the generated WASM is
also executed.

The current corpus contains 18 test cases spanning return, arithmetic,
local initialization, single and multi-local assignment, `if` and `if`/`else`,
`while`, all six comparison operators (`==`, `!=`, `<`, `>`, `<=`, `>=`),
and eager logical operators (`and`, `or`, `not`).

| Source shape | Corpus example | C | ASM | WAT/WASM | Notes |
|--------------|----------------|---|-----|----------|-------|
| Return literal | `fn main() i32 ret 42 end` | Run | Run | Validate, optionally run | Baseline `i32` return. |
| Arithmetic return | `fn main() i32 ret 1 + 2 * 3 end` | Run | Run | Validate, optionally run | Covers precedence and `+`/`*`. |
| Local init/return | `fn main() i32 let x i32 = 12 ret x end` | Run | Run | Validate, optionally run | Covers local declaration, initialization, lookup, and return. |
| Assignment | `fn main() i32 let x i32 = 1 x = x + 8 ret x end` | Run | Run | Validate, optionally run | Covers simple local reassignment. |
| Multi-local assign | `fn main() i32 let a i32 = 2 let b i32 = 7 a = b + 3 ret a end` | Run | Run | Validate, optionally run | Two locals with cross-assignment. |
| If-then | `fn main() i32 let x i32 = 1 if x x = 9 end ret x end` | Run | Run | Validate, optionally run | `if` without `else`. |
| If/else | `fn main() i32 let x i32 = 0 if x x = 1 else x = 7 end ret x end` | Run | Run | Validate, optionally run | `elif` chains supported in ASM (52804e9) and WAT (298b6c2). |
| While | `fn main() i32 let x i32 = 0 while x < 4 x = x + 1 end ret x end` | Run | Run | Validate, optionally run | Deterministic bounded loop. |
| Comparisons (6) | `==`, `!=`, `<=`, `>`, `>=`, `<` (true and false cases) | Run | Run | Validate, optionally run | All signed comparison operators. |
| Logical (2) | `not false or 0`, `2 and 3` | Run | Run | Validate, optionally run | Eager logical lowering, not short-circuiting. |

Limitations: the shared matrix intentionally excludes functions with
parameters, extern calls, arrays, structs, strings, and general I/O. Basic
multi-function programs and user-defined `i32` parameters are covered by the
C path through `make selfhost-equiv`, but they are not shared C/ASM/WAT
contracts yet. Keep matrix programs small enough for the compiler-1 harness
buffers (`source i8[256]`, `tokens Token[128]`, `out i8[1024]`).

## C backend (current)

The C backend translates ETL AST directly to C source text. This is the
bootstrap path and must remain fully functional at all times.

**Ownership**: The C backend emitter (`compiler1/emit_c.etl`) is owned by the
compiler-1 Phase 5 effort. Other workers should not modify it.

## ASM backend (active subset)

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

## WASM backend (active WAT subset)

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
| `compiler1/emit_asm.etl`          | ASM backend emitter (locals, arithmetic, control flow). |
| `compiler1/emit_wasm.etl`         | WAT/WASM backend emitter (locals, arithmetic, control flow). |
| `scripts/backend_plan_smoke.sh`   | Verifies scaffolds compile via compiler-0.    |
| `scripts/c1_emit_asm_smoke.sh`    | ASM backend smoke (arithmetic expression).    |
| `scripts/c1_asm_extern_call_smoke.sh` | ASM i32 extern call smoke.               |
| `scripts/c1_wat_return_smoke.sh`  | WAT/WASM return-value and extended smoke.     |
| `scripts/c1_wat_function_call_smoke.sh` | WAT/WASM i32 helper/user function call smoke. |
| `scripts/c1_wat_extern_import_smoke.sh` | WAT/WASM i32 extern import emission smoke. |
| `scripts/c1_wat_extern_call_smoke.sh` | WAT/WASM i32 extern call emission smoke. |
| `Makefile`                        | `make backend-plan` target.                   |

## Verification

```sh
make backend-plan   # Verify scaffolds compile through compiler-0
make backend-subset # Opt-in shared C/ASM/WAT subset matrix smoke
make check          # Unchanged — all existing tests must pass
make selfhost       # Unchanged — compiler-1 pipeline must pass
```

## Recommended next chunks

### Chunk ASM-1: x86-64 return-only emitter — **Done.**

### Chunk ASM-2: x86-64 arithmetic expressions — **Done.**

### Chunk ASM-3: x86-64 locals and control flow — **Done.**
Locals, assignment, `if`/`elif`/`else`, and `while` implemented.
No multi-function or parameter support yet.

### Chunk ASM-3B: x86-64 i32 array indexing — **Done.**
Local `i32` array declarations with constant-index read/write and
variable-index read/write proven by `scripts/c1_asm_array_smoke.sh`
(1a906f4, merged 981623a). Scalar-after-array stack layout verified.
Byte string literals, extern/param byte arrays, structs, struct arrays,
bounds checks, and dynamic arrays remain unsupported in ASM.

### Chunk ASM-3C: x86-64 byte/i8 array indexing — **Done.**
Local `byte[N]` and `i8[N]` array indexed assignment/read via `movsbq`
(for sign-extending read) and `movb` (for byte-width write), using
per-element 1-byte stride. Proven by `scripts/c1_asm_array_smoke.sh`
(722e30c, merged a387729). Scalar-after-byte-array and
byte-array-after-i32-array stack layouts verified. Local `byte[N]`/`i8[N]`
string literal initialization with constant-index reads proven by the same
smoke script (141756a, merged e006f5f). Helper `byte[N]`/`i8[N]` array
parameter indexed reads proven by the same smoke script (2f16e17, merged
69e0a05): local byte arrays are passed with `lea`, helper params are saved
base pointers, and reads use `movsbq`. Helper `byte[N]`/`i8[N]` array
parameter indexed writes proven by `scripts/c1_asm_array_smoke.sh` (99c6493,
merged 8db6ae1): `i8_array_param_write_idx` writes 42 into `buf[1]` and reads
it back, returning native exit 42. Extern byte arrays, runtime strings,
pointer decay beyond this helper-call slice, nested structs, non-i32 fields,
bounds checks, and dynamic arrays remain unsupported in ASM.

### Chunk WASM-1: WAT return-only emitter — **Done.**

### Chunk WASM-2: WAT arithmetic and locals — **Done.**
Locals, assignment, `if`/`else`, `while`, boolean literals, comparisons,
and logical operators all implemented and smoke-tested.

### Chunk WASM-2B: WAT i32 array indexing — **Done.**
Local `i32` array declarations with constant-index and variable-index
read/write proven by `scripts/c1_wat_array_smoke.sh` (ea5408c, merged
760a303). Local `byte[N]` and `i8[N]` array indexed assignment/read
using `i32.store8`/`i32.load8_s` proven by the same smoke script
(cd65f69, merged 7ce9043). Local `i8[N]` string literal initialization
with constant-index reads proven by the same smoke script (c173e18,
merged 44ac63e). Helper `byte[N]`/`i8[N]` array parameter indexed reads
(passed as i32 base pointer, using `i32.load8_s`) proven by the same
smoke script (df35de9, merged 1d20f20): `first(text i8[4]) i32` returns
`text[0] + text[1] - text[2]` = 96 from a local `i8[4] = "abc"`.
Helper `byte[N]`/`i8[N]` array parameter indexed writes (using
`i32.store8`) and readback proven by the same smoke script (a67d121,
merged d070a1d): `i8_array_param_helper_write_idx` returns 42 after
writing 42 into `buf[1]` and reading it back. Extern byte arrays,
structs, struct arrays, bounds checks, and dynamic arrays remain
unsupported.

### Chunk ASM-3D: x86-64 local i32 struct field store/load — **Done.**
Local struct declarations with `i32`-only fields, field store via
`mov $imm, %rax` + `mov %rax, -offset(%rbp)`, and field load via
`mov -offset(%rbp), %rax` proven by
`scripts/c1_asm_struct_field_smoke.sh` (f2d7ba9, merged 87fc689).
Smoke returns 42 via `type Pair structure left integer right integer
end` with `p.left = 19; p.right = 23; ret p.left + p.right`.
Nested structs, non-i32 fields, function parameters, extern calls,
bounds checks, and dynamic memory remain unsupported in ASM.

### Chunk ASM-3E: x86-64 local fixed struct array indexed field store/load — **Done.**
Local fixed arrays of structs with `i32`-only fields, constant-index
and variable-index field store/load via `imul` struct-size scaling and
RBP-relative indexed addressing (`-offset(%rbp,%reg,1)`) proven by
`scripts/c1_asm_struct_array_smoke.sh` (dd4d3b0, merged 04f1f67).
Smoke returns 42 via `type Item structure left integer right integer
end` with `items[0].left = 19; items[i].right = 23; ret
items[0].left + items[i].right`. Nested structs, non-i32 fields,
function parameters, extern calls, bounds checks, and dynamic memory
remain unsupported in ASM.

### Chunk WASM-2C: WAT local i32 struct field store/load — **Done.**
Local struct declarations with `i32`-only fields, field store via
`i32.store offset=N`, and field load via `i32.load offset=N` proven by
`scripts/c1_wat_struct_field_smoke.sh` (b822e55, merged 5dbb744).
Smoke returns 42 via `type Pair structure left integer right integer
end` with `p.left = 19; p.right = 23; ret p.left + p.right`.
Struct arrays, nested structs, non-i32 fields, function parameters,
extern calls, bounds checks, and dynamic memory remain unsupported in
WAT.

### Chunk WASM-2D: WAT local fixed struct array indexed field store/load — **Done.**
Local fixed arrays of structs with `i32`-only fields, constant-index
and variable-index field store/load via computed base offset plus
`i32.store offset=field`/`i32.load offset=field` proven by
`scripts/c1_wat_struct_array_smoke.sh` (b7bfbd1, merged f5e020e).
Smoke returns 42 via `type Item structure value integer end` with
`items[0].value = 19; items[1].value = 20; i = 1; items[i].value =
items[i].value + 3; ret items[0].value + items[i].value`. Nested
structs, non-i32 fields, function parameters, extern calls, bounds
checks, and dynamic memory remain unsupported in WAT.

### Chunk WASM-3: WAT i32 helper/user function calls — **Partially done (narrow i32 slice).**
Multiple user-defined functions with `i32` parameters and `i32` return values,
direct intra-module calls, and `_start` export proven by
`scripts/c1_wat_function_call_smoke.sh` (cc78aaf, merged 99caf9a). Smoke
validates `add(a,b)`, `bump(x)`, and `main` returning 42. Source `extern fn`
declarations with `i32`/`integer` params and `i32` return lowered to
`(import "env" "name" (func $name ... (result i32)))` with `call $name`
proven by `scripts/c1_wat_extern_import_smoke.sh` and
`scripts/c1_wat_extern_call_smoke.sh`. General parameter
types (byte, bool, struct, array), void-return extern import statements, runtime
host execution, ABI work for non-i32 params/returns, runtime
strings, pointer decay, extern byte arrays,
nested structs, non-i32 fields, bounds checks, and dynamic arrays
remain unsupported in WAT.

### Chunk ASM-4: x86-64 i32 helper/user function calls — **Partially done (narrow i32 slice).**
Multiple user-defined functions with `i32`/`integer` parameters and `i32` return
values, direct intra-module calls via System V AMD64 ABI (integer args in
RDI, RSI, RDX, RCX, R8, R9; return in RAX), and `.globl` export for all user
functions proven by `scripts/c1_asm_function_call_smoke.sh` (a30d3cd, merged
7ff9414). Smoke exercises `add(a,b)`, `bump(x)`, and `main` returning native
exit 42. Source `extern fn` declarations with `i32`/`integer` params and
`i32` return lowered to direct `call` to named symbols resolved by the linker
proven by `scripts/c1_asm_extern_call_smoke.sh` (535c56c, merged b66e5e0).
Smoke exercises `forty_one()`, `bump(x)`, and `add_i32(a,b)` returning native
exit 42 via external C helpers. Helper `byte[N]`/`i8[N]` array parameter
indexed reads are also proven by `scripts/c1_asm_array_smoke.sh` (2f16e17,
merged 69e0a05). Helper `byte[N]`/`i8[N]` array parameter indexed writes are
proven by the same smoke script (99c6493, merged 8db6ae1). General parameter
types (bool, struct, non-byte arrays), void-return extern declarations,
varargs, indirect calls, ABI work for non-integer args, runtime strings,
pointer decay, extern byte arrays, nested structs, non-i32 fields, bounds
checks, and dynamic arrays remain unsupported in ASM.

### Chunk IR-1: AST-to-IR lowering
- Define a minimal IR node format (basic blocks, three-address code).
- Build a lowering pass: AST → IR.
- Verify: IR output round-trips through C backend unchanged.
- Depends on: Phase 5f and at least one non-C backend at Chunk *-2.

### Future chunks
- ASM-4: function parameters and multi-function support — **narrow i32 helper-call slice done** (a30d3cd); **narrow i32 extern call slice done** (535c56c); **narrow byte/i8 array helper param read slice done** (2f16e17); **narrow byte/i8 array helper param write slice done** (99c6493); general param types, void-return extern, and full ABI remain.
- ASM-5: `elif` chains — **Done** (52804e9, merged 6e255dd).
- WASM-3: function parameters and multi-function support — **narrow i32 helper-call slice done** (cc78aaf); **narrow i32 extern import/call slice done** (538cc0d / 64316a8); **narrow byte/i8 array helper param read slice done** (df35de9); **narrow byte/i8 array helper param write slice done** (a67d121); general param types, void-return extern imports, runtime host execution, and full ABI remain.
- WASM-4: `elif` chains — **Done** (298b6c2, merged ccc1f42).
- These can be delegated to independent workers.

## Build integration

Backends are selected at build time by the concatenation-based module system.
Exactly one `emit_<target>` module is included per compiler build:

```
main.etl (shared decls, minus fn main)
  + lex.etl
  + parse.etl
  + sema.etl
  + emit_<target>.etl
  + test_<target>.etl
```

No runtime dispatch is needed. The backend is baked into the compiler binary
at build time.

### Adding a new backend

1. Create `compiler1/emit_<target>.etl` implementing the contract above.
2. Create `compiler1/test_<target>.etl` with byte-level output assertions.
3. Create `scripts/c1_emit_<target>_smoke.sh` following the concatenation
   pattern from `scripts/c1_emit_c_smoke.sh`. Start as a skip-safe placeholder.
4. Wire the smoke script into `scripts/c1_pipeline_smoke.sh` behind a
   conditional check (see existing pattern for sema/emit_c).

## Reference gate outputs

These are the expected outputs for the gate test programs that each backend
must match before being considered functional.

### WASM gate: `fn main() i32 ret 1 + 2 * (9 - 4) end`

```wat
(module
  (func (export "_start") (result i32)
    i32.const 1
    i32.const 2
    i32.const 9
    i32.const 4
    i32.sub
    i32.mul
    i32.add
  )
)
```

### ASM gate: `fn main() i32 ret 42 end`

```asm
    .text
    .globl main
main:
    mov $42, %eax
    ret
```

## Vocabulary and compatibility

`docs/platform-vocabulary.md` defines the canonical full-word vocabulary,
the complete legacy alias set, and the compatibility tiers for every backend.
Consult it before adding new keywords or backend features.

## Constraints

- Do not modify compiler-0 behavior.
- Do not modify `compiler1/emit_c.etl` (owned by Phase 5 worker).
- ASM and WASM scaffolds must not be linked into any build target.
- `make check` and `make selfhost` must continue to pass.
