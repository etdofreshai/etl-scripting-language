# Compiler Fixed-Point Plan

This document defines the c1-to-c2 fixed-point milestone for ETL: what it
means, what prerequisites remain, what artifacts prove progress, and how
future worker chunks should sequence the remaining work.

It complements `docs/ROADMAP.md` (phase ladder) and
`docs/self-improvement-roadmap.md` (self-eval mechanisms). This document is
about the **compiler self-compilation chain** and the conditions under which
compiler-0 can be frozen.

## Definitions

- **compiler-0 (c0)**: Python bootstrap compiler (`compiler0/etl0.py`).
  Compiles ETL source to C, then the host C compiler produces a native
  binary. Pipeline: `ETL source → lex → parse → AST → validate → emit_c → C text → cc → native`.

- **compiler-1 (c1)**: ETL compiler written in ETL (`compiler1/*.etl`).
  Built by c0. Currently has lex, parse, sema, and C emission stages.
  The built c1 binary reads ETL source from stdin and writes C output via
  `etl_write_file`.

- **compiler-2 (c2)**: The binary produced when c1 compiles its own source.
  If c2 behaves identically to c1, the compiler has reached **fixed point**.

- **Fixed point**: `c1(source) == c2(source)` for all source in the
  self-compilation corpus. The C text emitted by the c1-built compiler
  is byte-identical to the C text emitted by the c2-built compiler when
  given the same input. At fixed point, c0 is no longer needed for
  ongoing compiler development.

## Current c1 capabilities

The c1 compiler pipeline is functional for the current 20-fixture corpus,
including multi-function programs, recursive user-defined calls, and `i32`
function parameters. The `make selfhost` gate proves:

| Stage | File | What it does |
|---|---|---|
| Lex | `compiler1/lex.etl` | Tokenizes ETL source into `Token` array |
| Parse | `compiler1/parse.etl` | Builds `AstNode` array from tokens |
| Sema | `compiler1/sema.etl` | Validates types, extern call signatures, returns |
| Emit C | `compiler1/emit_c.etl` | Produces C source text from AST |

The c1 equiv smoke (`scripts/c1_equiv_smoke.sh`) compiles 20 corpus fixtures
via both c0 and c1, then verifies matching exit codes. The c1 source-to-C
smoke (`scripts/c1_source_to_c_smoke.sh`) proves end-to-end ETL-in to C-out.

The 18-case shared backend subset (`make backend-subset`) exercises the same
corpus shapes through C, ASM, and WAT/WASM backends.

### What c1 currently emits

C source text for programs of the form:

```etl
extern fn etl_print_i32(value i32)
fn main() i32
  let x i32 = ...
  if ...
  while ...
  ret ...
end
```

Specifically, c1 can emit:
- `extern fn` forward declarations (void and int return)
- Multiple named functions with `i32` return values
- Function parameters for user-defined `i32`, scalar `bool`/`i8`/`byte`,
  narrow byte/i8 array, and narrow by-value struct parameters
- Local declarations with initialization (`let x i32 = expr`)
- Assignment to locals (`x = expr`)
- Integer, boolean, sizeof, and unary-minus literals
- Binary arithmetic (`+`, `-`, `*`, `/`, `%`)
- Comparisons (`==`, `!=`, `<`, `<=`, `>`, `>=`)
- Logical operators (`&&`, `||`, `!`)
- Control flow: `if`/`elif`/`else`, `while`
- Function calls with arguments (extern and user-defined)
- `return` statements
- Narrow `i32` local array declarations with constant-index reads/writes
  (`int32_t arr[N] = {0};`, `arr[0] = 7`, `arr[0] + arr[1]`) — proven by
  `scripts/c1_source_to_c_array_smoke.sh` (fa722e8). Variable-index reads/writes
  (`arr[i]` where `i` is a local integer variable) — proven by
  `scripts/c1_source_to_c_array_var_index_smoke.sh` (6df84e6). `i8` arrays and
  larger arrays are not yet covered.
- Narrow local struct declarations with integer field read/write
  (`typedef struct { ... } Pair;`, `Pair p;`, `p.left = 19`, `p.left + p.right`)
  — proven by `scripts/c1_source_to_c_struct_field_smoke.sh` (902b736). Struct
  parameters, struct arrays, and non-integer field types are not yet covered.
- Narrow `i8[N]` local string literal initialization with constant-index reads
  (`int8_t text[4] = {'a','b','c',0};`, `text[0] + text[1] - text[2]`) — proven
  by `scripts/c1_source_to_c_byte_string_smoke.sh` (ed3d8de). Variable-index
  string reads are proven by `scripts/c1_source_to_c_byte_string_var_index_smoke.sh`.
  Multiple local string buffers coexisting are proven by
  `scripts/c1_source_to_c_byte_string_multi_buffer_smoke.sh`.
- Narrow local `i8[N]` byte array indexed assignment and readback with both
  constant-index (`values[0] = 10`) and variable-index (`values[i]`) reads —
  proven by `scripts/c1_source_to_c_byte_array_assign_smoke.sh` (bd10575).
  Larger `i8` arrays and multi-buffer coexistence are not yet covered.
- Narrow local struct array field read/write with both constant-index
  (`items[0].value = 19`) and variable-index (`items[i].value = items[i].value + 3`)
  indexed field access — proven by `scripts/c1_source_to_c_struct_array_smoke.sh`
  (6c54423). Struct arrays with non-integer fields and nested struct-in-struct
  are not yet covered.
- Narrow scalar `bool`, `i8`, and `byte` parameters for user-defined C
  functions — proven by `scripts/c1_source_to_c_scalar_param_smoke.sh`
  (3a5e395). These are C-backend user-function params only; extern scalar
  typed params and non-i32 returns remain outside this slice.
- Narrow by-value struct parameters for user-defined C functions — proven by
  `scripts/c1_source_to_c_struct_param_smoke.sh` (ec342d7). The follow-up sema
  guard (6c3cf90) keeps this path restricted to declared struct names. Struct
  returns and extern struct parameters are not yet covered.
- Narrow fixed byte/i8 array extern parameters emitted as `signed char *`
  in extern function declarations — proven by
  `scripts/c1_source_to_c_byte_string_extern_smoke.sh` (8d72ca2). Local byte
  string buffers can be passed to an extern C helper function.
- Narrow fixed byte/i8 array user-defined function parameters emitted as
  `signed char *name` in C function signatures — proven by
  `scripts/c1_source_to_c_byte_array_param_smoke.sh`. Local byte string buffers
  can be passed to a user-defined helper and indexed inside that helper.
  Struct parameters/returns and non-byte-array extern param types (structs,
  nested arrays) are not yet covered.

### What c1 cannot emit yet (self-compilation blockers)

These are the concrete gaps that prevent c1 from compiling its own source:

| Gap | Why it blocks self-compilation | Notes |
|---|---|---|
| Multi-function emission | Basic named function emission works, but only for the current narrow function subset | c1 source has ~60+ named functions; broader type coverage is still needed across those functions |
| Function parameters | `i32`, scalar `bool`/`i8`/`byte`, narrow byte/i8 array user-defined parameters, and narrow by-value struct parameters work, but typed params beyond those are not complete | Every emit_c_*, lex, parse function takes params, including arrays and struct buffers |
| Typed locals (not just int) | c1 type mapping is still partial; scalar `bool`/`i8` and composed typed locals are not fully covered | Token/AstNode structs, i8 arrays, bool locals |
| Array locals | c1 emits narrow local arrays, but not all c1-scale array shapes | c1 source uses `Token[128]`, `AstNode[512]`, `i8[1024]`. Narrow `i32` constant-index and variable-index arrays work (fa722e8, 6df84e6); narrow `i8` byte array indexed assignment works (bd10575); larger and struct-typed arrays remain incomplete |
| Struct declarations | c1 emits narrow local i32-only structs and by-value struct parameters, but not the full struct surface | Token, AstNode are core types. Narrow i32-only struct decl + local field read/write works (902b736); narrow local struct array field read/write works (6c54423); narrow by-value struct params work (ec342d7); non-i32 fields and arrays in struct fields do not |
| Struct field access | c1 emits local `.field`, local struct-array field access, and field access through by-value struct params, but not all cross-function patterns | `tokens[i].kind`, `ast[node].a` throughout. Local i32 field access works (902b736); struct array field access with constant and variable index works (6c54423); struct parameter field access works for the narrow C path (ec342d7); struct returns do not |
| Index expressions | c1 emits narrow `arr[i]` patterns, but not all array element types and contexts | All buffer access uses indexing. Constant-index and variable-index `i32` arrays work (fa722e8, 6df84e6); narrow `i8` array indexing works; struct-array field indexing works; larger and parameter-backed indexing remain incomplete |
| String literal data | c1 cannot yet cover all c1-scale string/buffer patterns | Narrow local `i8[N]="..."` with constant-index reads works (ed3d8de); variable-index reads work; multiple string buffers do not |
| Extern fn with typed params | c1 extern parameter type emission is partial | `etl_write_file` takes `i8[64]`, `i8[1024]`, `i32`. Narrow byte/i8 array extern params emitted as `signed char *` works (8d72ca2); non-byte-array extern param types do not |
| Buffer size limits | Source 256 bytes, tokens 128, output 1024 | c1 concatenated source is ~15KB+ |

### Phase 5f buffer scout (2026-05-02)

The current fixed buffers are too small for a direct c1 self-compile, and
they are embedded in function signatures rather than only in harness locals:

| Buffer | Current cap | Exact fixed sites | Required c1 C-backend size |
|---|---:|---|---:|
| Source text | 256 bytes | `compiler1/lex.etl` (`source i8[256]`), `compiler1/parse.etl`, `compiler1/sema.etl`, `compiler1/emit_c.etl`, plus `compiler1/test_source_to_c*.etl` harness locals | 81,198 bytes for `main+lex+parse+sema+emit_c` |
| Tokens | 128 | `Token[128]` in `lex`, `parse`, `sema`, `emit_c`, and source-to-C/equiv harnesses | 20,370 tokens including EOF, measured by compiler-0 |
| AST nodes | 512 | `AstNode[512]` in `parse`, `sema`, `emit_c`, and source-to-C/equiv harnesses | 20,993 compiler-0 dataclass AST nodes as a scale proxy |
| C output | 1,024 bytes | `out i8[1024]` and `emit_c(... out i8[1024] ...)`; `etl_write_file1024` externs in source-to-C harnesses | Larger than source input; exact c1 emitted-C size still needs a successful c1-scale emit |
| `main.etl` stdin buffer | 64 bytes | `etl_read_file(path, buf, 64)` with `buf i8[64]` | Must cover the full concatenated source before c1 can read itself |

A probe with a larger local source buffer failed under compiler-0 type
checking (`lex` expected `i8[256]`, got `i8[512]`), so a safe cap increase is
not just a local harness edit. The low-risk next chunk is a mechanical
capacity migration across the c1 C-backend path: raise `source i8[256]`,
`Token[128]`, `AstNode[512]`, and `out i8[1024]` consistently in
`lex/parse/sema/emit_c`, `compiler1/main.etl`, `scripts/c1_equiv_smoke.sh`,
and the `compiler1/test_source_to_c*.etl` harnesses, then rerun
`make check` and `make selfhost`.

## The self-compilation chain

### Stage A: c0 builds c1 (current)

```
compiler1/main.etl + lex.etl + parse.etl + sema.etl + emit_c.etl
  → c0 (Python) → c1.c → cc → c1 (native binary)
```

This works today. `scripts/build_etl.sh` concatenates the compiler-1 source
files, runs c0 to produce C, then compiles with the host C compiler and links
with `runtime/etl_runtime.c`.

### Stage B: c1 compiles a fixture corpus (Phase 5f goal)

```
for each fixture in tests/c1_corpus/:
  fixture.etl → c1 → fixture.c → cc → fixture (native)
  verify: exit code matches c0-compiled version
```

This partially works today (20 fixtures pass via `make selfhost-equiv`). The
5f milestone extends this to a broader corpus that exercises the full v0
feature set including structs, arrays, strings, and multi-function programs.

### Stage C: c1 compiles c1 source (Phase 5f stretch / 5g entry)

```
compiler1/*.etl (concatenated)
  → c1 → c1_self.c → cc → c2 (native binary)
```

This is the self-compilation step. c1 reads its own source and produces C.
That C is compiled by the host compiler into c2. If c2 can also successfully
compile the same source and produce identical C output, fixed point is
reached.

### Stage D: c2 matches c1 (fixed point, Phase 5g)

```
compiler1/*.etl → c1 → output_v1.c
compiler1/*.etl → c2 → output_v2.c
diff output_v1.c output_v2.c  # must be empty
```

Fixed point requires:
1. c2 compiles c1 source without errors.
2. The C text emitted by c2 is byte-identical to C text emitted by c1.
3. c2's compiled binary passes all gates that c1 passes.
4. This holds for at least three consecutive bootstraps (c1→c2→c3→c4, all
   producing identical C output).

## Verification gates and artifacts

### Phase 5f gates (c0→c1 builds c1; c1 compiles corpus)

| Gate | Command | What it proves |
|---|---|---|
| Existing equiv | `make selfhost-equiv` | 20 corpus fixtures: c0 and c1 produce same exit code |
| Expanded corpus | New equiv with structs/arrays/strings | c1 handles full v0 feature set |
| C text diff | `diff <(c0_emit fixture.etl) <(c1_emit fixture.etl)` | Normalized C text equivalence (per ROADMAP standing decision) |
| Self-compile attempt | `c1 < compiler1_all.etl > c1_self.c` | c1 can process its own source without crashing |

### Phase 5g gates (c1→c2 fixed point)

| Gate | Command | What it proves |
|---|---|---|
| Bootstrap chain | `c0→c1→c2` three-stage build | Full bootstrap produces a working c2 |
| C text identity | `diff c1_output.c c2_output.c` | c1 and c2 emit identical C for c1 source |
| c2 passes selfhost | `c2 < fixture.etl` for all corpus | c2 is a correct compiler |
| Triple bootstrap | `c0→c1→c2→c3→c4` identical output | Stability across multiple bootstraps |
| headless-ready | `make headless-ready` | No regressions in any existing gate |

### Provenance artifacts

At fixed point, the following artifacts should be recorded:

| Artifact | Location | Purpose |
|---|---|---|
| c1 concatenated source hash | `build/fixedpoint/c1_source.sha256` | Pin the exact c1 source that reaches fixed point |
| c1 output C | `build/fixedpoint/c1_output.c` | Canonical C emitted by c1 |
| c1 output C hash | `build/fixedpoint/c1_output.sha256` | Byte-level identity reference |
| c2 output C hash | `build/fixedpoint/c2_output.sha256` | Must match c1 output hash |
| Corpus results | `build/fixedpoint/corpus_results.csv` | All corpus fixture exit codes from c1 and c2 |
| Bootstrap log | `build/fixedpoint/bootstrap.log` | Full c0→c1→c2→c3→c4 log with timestamps |

## Prerequisites remaining

### Before Phase 5f can complete

These are ordered by dependency; earlier items unblock later ones.

1. **Broader multi-function emission**: c1 now emits named functions for the
   current `i32` corpus, including recursive calls. Self-compilation still
   needs that path to compose with arrays, structs, byte buffers, typed
   externs, and larger c1 source buffers across ~60+ named functions.

2. **Function parameters beyond `i32`**: c1 now emits user-defined `i32`,
   scalar `bool`/`i8`/`byte`, narrow fixed byte/i8 array, and narrow by-value
   struct parameters. Self-compilation still needs the remaining parameter
   shapes, especially full struct/array/buffer composition and extern typed
   parameters.

3. **Typed local emission**: c1 must emit `int32_t`, `int8_t`, `bool`, and
   struct-typed locals instead of always emitting `int`.

4. **Array local emission**: c1 must emit fixed-size array declarations like
   `int32_t arr[128] = {0};` and `int8_t buf[256] = {0};`.

5. **Struct declaration emission**: c1 must emit `typedef struct { ... } Name;`
   for struct type definitions.

6. **Struct field access emission**: c1 must emit `expr.field` for dot-access
   expressions on struct values.

7. **Index expression emission**: c1 must emit `arr[i]` for array indexing
   expressions.

8. **String literal emission**: c1 must emit string initializers for `i8[]`
   locals, including null-terminated C string data.

9. **Extern fn typed params**: c1 must emit correct C types for extern
   function parameters (not all `int`).

10. **Buffer expansion**: The c1 harness buffers (`source i8[256]`,
    `tokens Token[128]`, `out i8[1024]`) must be expanded to handle the
    full concatenated c1 source (~15KB+ source, ~500+ tokens, ~20KB+ output).

### Before Phase 5g can start

Phase 5g requires Phase 5f to be complete, plus:

1. The c1→c2 bootstrap chain must succeed without errors.
2. c2 must produce identical C output to c1.
3. At least three consecutive bootstraps must agree.

## Future worker chunks

These chunks are scoped to not change compiler/runtime behavior. Each chunk
is documentation, test infrastructure, or corpus expansion.

### Chunk 5f-CORPUS: Expand the c1 equiv corpus

**Scope**: Add new corpus fixtures to `tests/c1_corpus/` that exercise
features c1 will need for self-compilation. No compiler changes.

See `docs/c1-corpus-expansion-plan.md` for the full fixture catalog with
acceptance criteria, tier ordering, and blocker mapping. Summary:

- Tier 1 (4 fixtures): multi-function, `i32` parameters, recursive calls
- Tier 2 (3 fixtures): `bool` locals, `i8` locals
- Tier 3 (3 fixtures): array locals, index expressions, variable subscripts
- Tier 4 (3 fixtures): struct declarations, field access, struct arrays
- Tier 5 (2 fixtures): string-initialized `i8[]` locals
- Tier 6 (1 fixture): typed extern function parameters

Each fixture has an expected exit code. Tier 1 is now included in the default
c1 equiv gate and passes; later tiers should be added to the smoke array as
their matching emitter support lands.

**Prerequisite**: None (documentation/test-only).
**Estimated waves**: 1–2.

### Chunk 5f-MULTIFN: Multi-function C emission

**Scope**: Extend `compiler1/emit_c.etl` to emit named functions with
arbitrary names instead of hardcoding `main`. This is a compiler change, but
it must not break existing c1 equiv results.

- `emit_c_function` reads the function name token and emits it.
- All existing 20 corpus fixtures continue to pass.
- Tier 1 multi-function fixtures remain green.

**Status**: Basic `i32` multi-function emission landed in 6ab989e.
**Prerequisite**: Broader type coverage before this can be considered complete
for self-compilation.
**Estimated waves**: 2–3.

### Chunk 5f-PARAMS: Function parameter emission

**Scope**: Extend `emit_c_function` to emit parameter lists with typed
parameters. Remove the `ast[params].b != 0` guard.

- Parameters are emitted with their C types (`int32_t`, `int8_t`, etc.).
- All existing 20 corpus fixtures continue to pass.
- Tier 1 parameter fixtures remain green.

**Status**: Basic user-defined `i32` parameter emission landed in 6ab989e.
**Prerequisite**: Broader type coverage before this can be considered complete
for self-compilation.
**Estimated waves**: 2–3.

### Chunk 5f-TYPES: Typed local and extern parameter emission

**Scope**: Emit correct C types for locals and extern parameters.

- `emit_c_let` maps ETL types to C types: `i32` → `int32_t`, `i8` → `int8_t`,
  `bool` → `bool`, `ptr` → `int8_t*`.
- `emit_c_extern_param_list` uses actual parameter types instead of `int`.
- `local_bool.etl` and typed-extern fixtures now pass.

**Prerequisite**: 5f-PARAMS.
**Estimated waves**: 2–3.

### Chunk 5f-ARRAYS: Array local and index emission

**Scope**: Emit fixed-size array declarations and index expressions.

- `emit_c_let` detects array types and emits `T name[N] = {0};`.
- `emit_c_expr` handles `AN_INDEX` nodes: `arr[idx]`.
- `local_array.etl` and `index_expr.etl` now pass.

**Prerequisite**: 5f-TYPES.
**Estimated waves**: 2–3.

### Chunk 5f-STRUCTS: Struct declaration and field access

**Scope**: Emit struct typedefs and field access expressions.

- New `emit_c_struct` function for `typedef struct { ... } Name;`.
- `emit_c_expr` handles `AN_FIELD_ACCESS` nodes: `expr.field`.
- `struct_decl.etl` and `field_access.etl` now pass.

**Prerequisite**: 5f-ARRAYS.
**Estimated waves**: 2–3.

### Chunk 5f-STRINGS: String literal emission

**Scope**: Emit `i8[N]` locals initialized with string literals.

- String data is emitted as C character arrays with initializer lists or
  string literals.
- `string_local.etl` now passes.

**Prerequisite**: 5f-STRUCTS.
**Estimated waves**: 1–2.

### Chunk 5f-BUFFERS: Expand harness buffer sizes

**Scope**: Increase buffer sizes in the equiv smoke harness to handle
c1-scale programs.

- `source i8[256]` → `source i8[16384]` (16KB).
- `tokens Token[128]` → `tokens Token[1024]`.
- `out i8[1024]` → `out i8[32768]` (32KB).
- Adjust `emit_c` internal buffers proportionally.

**Prerequisite**: 5f-STRINGS.
**Estimated waves**: 1–2.

### Chunk 5f-SELFCOMPILE: c1 compiles c1 source

**Scope**: Wire the self-compilation attempt into the test harness.

- New script: `scripts/c1_selfcompile_smoke.sh`.
- Concatenates c1 source, feeds to c1-built binary, captures C output.
- Verifies C output compiles with `cc` and links with runtime.
- Does not yet require identical output to c0-compiled c1.
- Gate target added to Makefile: `make selfhost-selfcompile`.

**Prerequisite**: 5f-BUFFERS.
**Estimated waves**: 1–2.

### Chunk 5g-BOOTSTRAP: Three-stage bootstrap verification

**Scope**: Prove c1→c2 fixed point.

- New script: `scripts/c1_bootstrap_smoke.sh`.
- Runs c0→c1→c2→c3 chain.
- Verifies C output hashes are identical at each stage.
- Records provenance artifacts under `build/fixedpoint/`.
- Gate target: `make selfhost-bootstrap`.

**Prerequisite**: 5f-SELFCOMPILE.
**Estimated waves**: 2–3.

### Chunk 5g-FREEZE: Freeze compiler-0

**Scope**: Declare c0 frozen and update all documentation.

- ROADMAP Phase 5 marked done.
- c0 is declared maintenance-only (bug fixes only).
- All future compiler development happens in ETL.
- Update `docs/DESIGN.md` bootstrap strategy section.

**Prerequisite**: 5g-BOOTSTRAP.
**Estimated waves**: 1.

## Ordering dependency graph

```
5f-CORPUS ──→ 5f-MULTIFN/PARAMS (basic i32 done) ──→ 5f-TYPES ──→ 5f-ARRAYS
                 │                                            │
                 │                                            ▼
                 │                                      5f-STRUCTS ──→ 5f-STRINGS
                 │                                                       │
                 │                                                       ▼
                 │                                              5f-BUFFERS ──→ 5f-SELFCOMPILE
                 │                                                               │
                 │                                                               ▼
                 │                                                        5g-BOOTSTRAP ──→ 5g-FREEZE
```

Total estimated waves: 18–28.

## Success criteria

The fixed-point milestone is complete when all of the following hold:

1. `make headless-ready` passes.
2. `make selfhost-selfcompile` passes: c1 compiles its own source to C, and
   that C compiles to a working c2 binary.
3. `make selfhost-bootstrap` passes: c0→c1→c2→c3 chain produces identical C
   output at every stage.
4. c2 passes all corpus fixtures that c1 passes.
5. Provenance artifacts are recorded in `build/fixedpoint/`.
6. `docs/ROADMAP.md` Phase 5 is marked done.
7. compiler-0 is declared frozen.
