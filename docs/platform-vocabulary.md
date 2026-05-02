# Platform Compatibility and Language Vocabulary

This document defines the canonical ETL vocabulary, the legacy alias set,
and the compatibility contract for every compilation target and runtime path.

## Canonical full-word vocabulary

These are the preferred spellings. All new ETL code and documentation should
use these forms exclusively.

### Keywords

| Canonical form | Legacy alias | Token kind | Role |
|---|---|---|---|
| `function` | `fn` | `FN` | Function definition |
| `external` | `extern` | `EXTERN` | External (FFI) function declaration |
| `return` | `ret` | `RET` | Return from function |
| `type` | — | `TYPE` | Type/struct declaration |
| `structure` | `struct` | — | Struct body keyword after `type Name` |
| `size` | `sizeof` | `SIZEOF` | Compile-time type size expression |
| `let` | — | `LET` | Local variable declaration |
| `if` | — | `IF` | Conditional branch |
| `elif` | — | `ELIF` | Else-if branch |
| `else` | — | `ELSE` | Else branch |
| `while` | — | `WHILE` | Loop |
| `end` | — | `END` | Block terminator |
| `and` | — | `AND` | Logical AND (short-circuit) |
| `or` | — | `OR` | Logical OR (short-circuit) |
| `not` | — | `NOT` | Logical NOT |
| `true` | — | `TRUE` | Boolean literal |
| `false` | — | `FALSE` | Boolean literal |
| `use` | — | `USE` | Module import (reserved, unused in v0) |

### Type names

| Canonical form | Legacy alias | C representation | Notes |
|---|---|---|---|
| `integer` | `i32` | `int32_t` | Default numeric type |
| `byte` | `i8` | `int8_t` | 8-bit signed; for string buffers |
| `boolean` | `bool` | `bool` (`stdbool.h`) | `true` / `false` |
| `pointer` | `ptr` | `int8_t *` | Opaque FFI-only type |

### Compound types

- `T[N]` — fixed-size array (zero-initialized; element types: `integer`, `boolean`, `byte`, or a previously declared struct type)
- `type Name structure ... end` — named struct

### Legacy alias set (complete)

The compiler-0 lexer accepts these shorter forms as exact synonyms. They are
retained for backward compatibility with existing ETL programs and the
compiler-1 codebase. New programs should use the canonical full-word form.

```
fn       → function
extern   → external
ret      → return
struct   → structure
sizeof   → size
i32      → integer
i8       → byte
bool     → boolean
ptr      → pointer
```

The full-word alias smoke (`scripts/full_word_alias_smoke.sh`) proves that
the canonical forms compile through compiler-0 and produce correct native
output. Running `make smoke` exercises both spellings.

## Compatibility tiers

Each tier defines what a backend or runtime path must support to claim
conformance at that level.

### Tier 1: C backend (compiler-0 and compiler-1)

**Status: Active and complete for v0 feature set.**

The C backend is the bootstrap target and must always work. It supports the
full v0 language:

- All keyword and type forms (canonical and legacy)
- Functions, parameters, return values
- `let` locals, assignment, arrays, structs
- Arithmetic (`+`, `-`, `*`, `/`, `%`), comparison, logical operators
- `if` / `elif` / `else`, `while`
- String literals, `size(T)`, `external function` declarations
- Runtime: `etl_runtime.c` with I/O, allocation, file, and panic externs

**Gate**: `make check` (tests + smoke + runtime-test).

### Tier 2: Compiler-1 self-hosted C backend

**Status: Active, growing.**

Compiler-1 (`compiler1/*.etl`) written in ETL, compiled by compiler-0 to C,
then to a native binary. Currently covers lexing, parsing, semantic analysis,
and C emission for a growing subset, including user-defined `i32`,
`bool`/`i8`/`byte`, narrow byte-array, and narrow by-value struct parameters.

**Gate**: `make selfhost` (c1-pipeline + selfhost-equiv + c1-smoke).

### Tier 3: ASM backend (x86-64 System V)

**Status: Active smoke subset.**

Emits x86-64 assembly for small `main` programs with integer return,
arithmetic, local initialization, local assignment, `if`/`elif`/`else`
chains, `while` loops, all comparison operators, boolean literals, eager
logical expressions (`and`, `or`, `not`), local `i32` array declaration
plus constant-index and variable-index read/write, local `byte[N]`/`i8[N]`
array indexed assignment/read via `movsbq`/`movb`, local `byte[N]`/`i8[N]`
string literal initialization with constant-index reads, and local struct
declarations with `i32`-only field store/load via `mov` with RBP offsets,
and local fixed struct array indexed field store/load via computed base
offset with `imul` struct-size scaling. Also emits multiple user-defined
helper functions with `i32`/`integer` parameters, scalar `bool`/`boolean`
and `i8`/`byte` helper parameters, i32 returns, and direct calls
using System V integer argument registers. Helper `byte[N]`/`i8[N]` array
parameters can be passed as saved base pointers and read/written through
indexed `movsbq`/`movb`. Source `extern fn` declarations with `i32`/`integer` params
and `i32` return are lowered to direct `call` to named symbols resolved by
the linker.
No void-return extern declarations, non-scalar function parameters or returns
beyond existing byte-array helper slices and struct local support, extern
scalar ABI beyond existing i32 extern call slice, array/struct parameters or
returns, varargs, indirect calls, runtime strings, pointer decay beyond the
helper-call byte array slice, extern byte arrays, nested structs,
non-i32 struct fields, bounds checks, or dynamic arrays yet.

**Gate**: `make backend-asm` (exercises ASM emitter via compiler-1).

### Tier 4: WAT/WASM backend

**Status: Active WAT subset.**

Emits WAT text for `main` programs with integer/boolean return, arithmetic,
all comparisons, logical operators, `let` locals, assignment, `if`/`elif`/`else`,
`while` loops, boolean literals, local `i32` array declaration plus
constant-index and variable-index read/write, local `byte[N]`/`i8[N]`
array indexed assignment/read via `i32.store8`/`i32.load8_s`, local
`i8[N]` string literal initialization with constant-index reads, local
struct declarations with `i32`-only field store/load via
`i32.store`/`i32.load` with offset, local fixed struct array indexed
field store/load, multiple user-defined `i32`-parameter/`i32`-return
helper functions with direct intra-module calls (`_start` exported as
`main`), scalar `bool`/`boolean` and `i8`/`byte` helper parameters mapped
as `i32` params/locals, and source `extern fn` declarations with `i32`/`integer` params
and `i32` return lowered to `(import "env" "name" (func $name ... (result i32)))`
with `call $name`. Helper `byte[N]`/`i8[N]` array parameter indexed reads/writes
(passed as i32 base pointer, using `i32.load8_s`/`i32.store8`) are supported.
No void-return extern import statements, runtime host
execution, runtime strings, pointer decay, extern byte arrays,
nested structs, non-i32 struct fields,
struct or array parameters or returns beyond scalar bool/byte and byte-array
indexed read/write, byte/string/pointer params
(as opposed to byte-array param reads),
varargs, imported memory, or broader ABI, bounds checks, or
dynamic arrays yet. Text validation always runs.
Runtime execution requires `wat2wasm` plus `wasmtime` or `wasmer`; otherwise
the smoke reports reduced coverage and still passes. The active subset covers
integer return, arithmetic, local initialization, local assignment, simple
`if`/`elif`/`else`, simple `while`, comparison, eager logical expressions,
local `i32` array indexing, local `byte[N]`/`i8[N]` array indexed read/write,
local `i8[N]` string literal initialization with constant-index reads,
local i32 struct field store/load, local fixed struct array indexed
field store/load, i32-parameter/i32-return helper function calls
within a single module, scalar `bool`/`boolean` and `i8`/`byte` helper
parameters mapped as `i32` params/locals, narrow i32 extern import/call emission,
and narrow `byte[N]`/`i8[N]` array helper parameter indexed reads/writes.

**Gate**: `make backend-wasm` (skip-safe for runtime tools).

### Tier 5: Shared backend subset matrix

**Status: Active.**

Runs a small corpus through all three compiler-1 backends (C, ASM, WAT/WASM)
and verifies consistent behavior. C and ASM produce native executables;
WAT is validated and optionally executed. The current matrix contains 18 test
cases covering return, arithmetic, locals, assignment, control flow,
all six comparison operators, and eager logical operators.

| Source shape | C | ASM | WAT/WASM |
|---|---|---|---|
| Return literal | Run | Run | Validate, optionally run |
| Arithmetic return | Run | Run | Validate, optionally run |
| Local init/return | Run | Run | Validate, optionally run |
| Assignment (single, multi-local) | Run | Run | Validate, optionally run |
| If-then, if/else | Run | Run | Validate, optionally run |
| While | Run | Run | Validate, optionally run |
| Comparisons (6 operators) | Run | Run | Validate, optionally run |
| Logical (`and`, `or`, `not`) | Run | Run | Validate, optionally run |

**Gate**: `make backend-subset`.

### Tier 6: Software graphics (headless framebuffer)

**Status: Active, always available.**

Pure C software framebuffer with no external dependencies. Renders to PPM,
computes deterministic pixel hashes. Runs on any headless server with a C
compiler.

**Gate**: `make graphics-software` (also included in `make selfeval-all`).

### Tier 7: SDL3 graphics (offscreen surface)

**Status: Active, skip-safe.**

Uses SDL3 for offscreen rendering when available. Identical API surface to
the software backend. If SDL3 is not installed, the smoke prints SKIP and
exits 0.

**Gate**: `make graphics-headless` (skip-safe).

### Tier 8: Headless self-evaluation

**Status: Active.**

Compiles every program in `examples/selfeval/MANIFEST`, runs each twice,
and verifies exit codes, stdout golden files, and determinism.

**Gate**: `make headless-selfeval`.

## The headless-ready contract

`make headless-ready` is the one-command readiness gate. It runs, in order:

1. **check** — compiler-0 tests, full smoke suite, runtime tests.
2. **selfhost** — compiler-1 pipeline and self-host equivalence.
3. **backend-plan** — backend-plan smoke + ASM backend smoke.
4. **backend-subset** — shared C/ASM/WAT matrix across supported subset.
5. **backend-wasm** — WAT/WASM return-value smoke.
6. **selfeval-all** — deterministic headless self-eval + trace artifacts
   + software framebuffer + skip-safe SDL3 graphics.

Passing `headless-ready` proves:

- The compiler-0 pipeline is correct and complete for the v0 language.
- Compiler-1 builds via compiler-0 and passes its self-host smoke.
- All three compiler-1 backends produce consistent output for the shared
  subset.
- Self-eval programs produce deterministic, golden-matched output.
- Trace artifacts are byte-for-byte deterministic with verified SHA-256.
- The portable software framebuffer renders deterministic pixel output.
- SDL3 graphics are skip-safe: they run when available, skip cleanly when not.

## What is unsupported or skip-safe

### Not yet implemented (future phases)

- Break/continue in loops
- First-class arrays (pass/return/whole-assignment)
- First-class structs (pass/return/whole-assignment/comparison)
- Pointer dereference or arithmetic
- Struct or array returns from extern functions
- `const` qualifier
- IR layer (AST currently feeds directly to emitters)
- WASM binary emission (WAT text only)
- PNG output (PPM only)
- `use` module system

### Skip-safe in CI (run when tools available, pass otherwise)

- SDL3 offscreen rendering (`make graphics-headless`)
- WASM runtime execution via `wasmtime`/`wasmer` (`make backend-wasm`)
  (WAT text validation always runs)

### Intentionally excluded from v0

- Implicit truthiness (conditions must be `boolean`)
- Floating-point types
- Garbage collection
- Exception handling
- Closures or first-class functions
- Reflection or runtime type information

## Self-improvement loop

`docs/self-improvement-roadmap.md` defines how the language progresses from the
current headless-ready state to a self-improving loop: what the self-eval
surface covers today, how each mechanism (console logs, trace artifacts, PPM
screenshots, backend equivalence) should be used, and the contract for future
AFK worker chunks.

## Guidance for future worker chunks

### Keeping the word list minimal

1. **Do not add keywords without updating this document.** Every new keyword
   must be listed here with its token kind, role, and any legacy alias.

2. **Prefer extending existing forms over adding new syntax.** Before
   introducing a new keyword, consider whether an existing keyword plus a
   parameter can express the same thing (e.g., `type X structure ... end`
   rather than a separate `struct` declaration form).

3. **Canonical forms are the public API.** Legacy aliases exist for
   compatibility only. Documentation, examples, and new ETL code should use
   the canonical full-word forms (`function`, `external`, `return`,
   `structure`, `integer`, `byte`, `boolean`, `pointer`, `size`).

4. **Both spellings must parse identically.** If you add a new canonical
   form, the compiler must accept the legacy alias as a exact synonym. Update
   `KEYWORD_ALIASES` and `TYPE_ALIASES` in `compiler0/etl0.py` together.

5. **The alias smoke must continue to pass.** After any keyword or type
   change, run `make smoke` to verify both spellings.

### Backend portability

1. **New backends must be skip-safe.** Any smoke script for a new backend
   must detect missing tools and print SKIP rather than failing. Follow the
   pattern in `scripts/c1_wat_return_smoke.sh` and
   `scripts/sdl3_headless_smoke.sh`.

2. **Shared subset matrix grows deliberately.** Add a row to the
   `make backend-subset` matrix only when all active backends can implement
   it. Features only supported by C (extern calls, structs, strings) stay in
   the C-only smoke tests.

3. **The software graphics backend is the portable floor.** Any new graphics
   feature must work through the software framebuffer before it can rely on
   SDL3. The software backend must never acquire a dependency beyond the C
   standard library.

4. **`make headless-ready` is the integration gate.** All worker chunks must
   pass this gate before committing. It is the single source of truth for
   whether the repository is ready to run on a headless server.
