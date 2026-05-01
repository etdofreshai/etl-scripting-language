# Compiler-1 Corpus Expansion Plan

This document maps the fixed-point self-compilation blockers to ordered corpus
fixtures and smoke tests. Each fixture has a concrete acceptance criterion.
Fixture order mirrors the dependency chain in `docs/fixed-point-plan.md` chunk
sequence (5f-CORPUS through 5f-STRINGS).

## Current corpus (16 fixtures, all passing)

The existing corpus exercises single-function programs with `i32` locals,
integer arithmetic, comparisons, logical operators, `if`/`elif`/`else`,
`while`, assignment, `return`, and extern/user function calls with arguments.
See `scripts/c1_equiv_smoke.sh` for the full list.

All 16 produce matching exit codes when compiled by c0 vs c1.

## What the current corpus does NOT cover

The 10 self-compilation blockers from `fixed-point-plan.md` and which fixture
category addresses each:

| Blocker | Addressed by fixture tier |
|---|---|
| Multi-function emission | Tier 1: `multi_fn_*` |
| Function parameters | Tier 1: `fn_params_*` |
| Typed locals (not just int) | Tier 2: `local_bool_*`, `local_i8_*` |
| Array locals | Tier 3: `local_array_*` |
| Struct declarations | Tier 4: `struct_decl_*` |
| Struct field access | Tier 4: `field_access_*` |
| Index expressions | Tier 3: `index_expr_*` |
| String literal data | Tier 5: `string_local_*` |
| Extern fn with typed params | Tier 6: `extern_typed_*` |
| Buffer size limits | Not a fixture issue; addressed by 5f-BUFFERS chunk |

## Fixture tiers

### Tier 1: Multi-function and parameters

These fixtures test the two largest blockers. They use only `i32` types so
no type-mapping changes are required.

#### `multi_fn_basic.etl`

```etl
fn helper() i32
  ret 7
end

fn main() i32
  ret helper()
end
```

**Acceptance**: c0 exit 7, c1 exit 7. Proves c1 can emit a named function
other than `main` and a call to it.

#### `multi_fn_chain.etl`

```etl
fn double(x i32) i32
  ret x * 2
end

fn add_one(x i32) i32
  ret x + 1
end

fn main() i32
  let v i32 = double(5)
  ret add_one(v)
end
```

**Acceptance**: c0 exit 11, c1 exit 11. Proves c1 emits multiple named
functions with integer parameters and chains calls through locals.

#### `fn_params_two.etl`

```etl
fn add(a i32, b i32) i32
  ret a + b
end

fn main() i32
  ret add(20, 22)
end
```

**Acceptance**: c0 exit 42, c1 exit 42. Proves multi-parameter function
emission with correct argument passing.

#### `fn_recursive.etl`

```etl
fn fib(n i32) i32
  if n < 2
    ret n
  end
  ret fib(n - 1) + fib(n - 2)
end

fn main() i32
  ret fib(10)
end
```

**Acceptance**: c0 exit 55, c1 exit 55. Proves recursive user-defined
function calls work through c1's emitter.

**Unlocks**: 5f-MULTIFN and 5f-PARAMS chunks in fixed-point-plan.

---

### Tier 2: Typed locals (bool, i8)

These require the 5f-TYPES emitter change (mapping ETL types to C types).

#### `local_bool.etl`

```etl
fn main() i32
  let flag bool = true
  if flag
    ret 1
  end
  ret 0
end
```

**Acceptance**: c0 exit 1, c1 exit 1. Proves c1 emits `bool` locals
instead of always emitting `int`.

#### `local_bool_expr.etl`

```etl
fn main() i32
  let a i32 = 5
  let b i32 = 3
  let greater bool = a > b
  if greater
    ret 99
  end
  ret 0
end
```

**Acceptance**: c0 exit 99, c1 exit 99. Proves `bool` locals can hold
comparison results and drive control flow.

#### `local_i8.etl`

```etl
fn main() i32
  let ch i8 = 65
  ret ch
end
```

**Acceptance**: c0 exit 65, c1 exit 65. Proves c1 emits `int8_t` locals.

**Unlocks**: 5f-TYPES chunk.

---

### Tier 3: Arrays and indexing

These require the 5f-ARRAYS emitter change (array declarations and index
expressions).

> **Status (2026-05-01):** A narrow `i32` local array indexing smoke has landed
> (`scripts/c1_source_to_c_array_smoke.sh`, commit fa722e8). It proves c1 can
> emit `int32_t arr[N] = {0}` declarations, constant-index writes (`arr[0] = 7`),
> and constant-index reads (`arr[0] + arr[1]`) for `i32` arrays. A narrow
> variable-index smoke has also landed
> (`scripts/c1_source_to_c_array_var_index_smoke.sh`, commit 6df84e6), proving
> c1 can emit `arr[i]` reads and writes where `i` is a local integer variable.
> A narrow `i8` byte array indexed assignment smoke has also landed
> (`scripts/c1_source_to_c_byte_array_assign_smoke.sh`, commit bd10575), proving
> c1 can emit `int8_t values[N] = {0}` declarations with both constant-index and
> variable-index assignment/readback for `i8` arrays. The fixtures below expand
> coverage to larger arrays — which is not yet covered.

#### `local_array_sum.etl`

```etl
fn main() i32
  let arr i32[4]
  arr[0] = 10
  arr[1] = 20
  arr[2] = 30
  arr[3] = 40
  ret arr[0] + arr[1] + arr[2] + arr[3]
end
```

**Acceptance**: c0 exit 100, c1 exit 100. Proves c1 emits
`int32_t arr[4] = {0};` declarations and `arr[i]` index expressions for both
reads and writes. The narrow `i32` constant-index smoke already covers the
core mechanism (declare + write + read); this fixture extends to 4-element
arrays with multi-read sum expressions.

#### `local_array_loop.etl`

```etl
fn main() i32
  let arr i32[8]
  let i i32 = 0
  while i < 8
    arr[i] = i * i
    i = i + 1
  end
  ret arr[7]
end
```

**Acceptance**: c0 exit 49, c1 exit 49. Proves array indexing with variable
subscripts inside loops. The narrow variable-index smoke (6df84e6) covers
`arr[i]` reads and writes for a single local variable index; this fixture
extends to 8-element arrays with loop-driven variable subscripts.

#### `local_i8_array.etl`

```etl
fn main() i32
  let buf i8[8]
  buf[0] = 72
  buf[1] = 105
  ret buf[0]
end
```

**Acceptance**: c0 exit 72, c1 exit 72. Proves `int8_t buf[8] = {0};`
declarations and i8 array indexing. Narrow `i8` byte array indexed assignment
works (bd10575); this fixture extends to 8-element `i8` arrays.

**Unlocks**: 5f-ARRAYS chunk. The narrow `i32` constant-index, variable-index,
and `i8` byte array smokes cover a subset; larger arrays still require the full
5f-ARRAYS emitter work.

---

### Tier 4: Structs and field access

These require the 5f-STRUCTS emitter change (typedef struct and dot-access).

> **Status (2026-05-01):** A narrow local integer struct field C smoke has landed
> (`scripts/c1_source_to_c_struct_field_smoke.sh`, commit 902b736). It proves c1
> can emit `typedef struct { ... } Pair;` declarations, `Pair p;` struct locals,
> integer field writes (`p.left = 19`), and integer field reads (`p.left + p.right`)
> for local struct variables with `i32` fields. A narrow struct array field smoke
> has also landed (`scripts/c1_source_to_c_struct_array_smoke.sh`, commit 6c54423),
> proving c1 can emit local struct arrays (`Item items[2]`) with both constant-index
> and variable-index field read/write (`items[0].value`, `items[i].value`).
> The fixtures below expand coverage to struct parameters passed across function
> boundaries and combined struct + array access patterns with larger arrays —
> struct params and non-integer field types are not yet covered.

#### `struct_decl.etl`

```etl
struct Point
  x i32
  y i32
end

fn main() i32
  let p Point
  p.x = 3
  p.y = 4
  ret p.x + p.y
end
```

**Acceptance**: c0 exit 7, c1 exit 7. Proves c1 emits `typedef struct { ... } Point;`
and initializes struct locals. The narrow local integer struct field smoke already
covers the core mechanism (declare + write + read for i32 fields); this fixture
adds a second distinct struct type as a regression guard.

#### `field_access_fn.etl`

```etl
struct Pair
  first i32
  second i32
end

fn sum_pair(p Pair) i32
  ret p.first + p.second
end

fn main() i32
  let v Pair
  v.first = 10
  v.second = 32
  ret sum_pair(v)
end
```

**Acceptance**: c0 exit 42, c1 exit 42. Proves struct parameters and
field access across function boundaries. **Not yet covered** — the existing
smoke only tests local struct fields within `main`.

#### `struct_array.etl`

```etl
struct Item
  value i32
end

fn main() i32
  let items Item[3]
  items[0].value = 100
  items[1].value = 200
  items[2].value = 300
  ret items[1].value
end
```

**Acceptance**: c0 exit 200, c1 exit 200. Proves combined struct + array:
`Item items[3]` declarations and `items[i].field` access patterns.
Narrow struct array field read/write with constant and variable index works
(6c54423); this fixture extends to 3-element struct arrays.

**Unlocks**: 5f-STRUCTS chunk. The narrow struct field and struct array smokes
cover a subset (struct declarations + local i32 field read/write + local struct
array indexed field access); struct parameters, non-integer field types, and
larger struct arrays still require the full 5f-STRUCTS emitter work.

---

### Tier 5: String literals and byte buffers

These require the 5f-STRINGS emitter change (i8[] initialization from string
literals).

> **Status (2026-05-01):** A narrow local byte string array smoke has landed
> (`scripts/c1_source_to_c_byte_string_smoke.sh`, commit ed3d8de). It proves c1
> can emit `int8_t text[N]` declarations initialized from string literals and
> constant-index reads (`text[0] + text[1] - text[2]`) for local `i8` arrays.
> The fixtures below expand coverage to multi-read sum expressions and multiple
> string-initialized locals coexisting — the multi-buffer coexistence test is
> not yet covered.

#### `string_local.etl`

```etl
fn main() i32
  let msg i8[12] = "hello world"
  ret msg[0]
end
```

**Acceptance**: c0 exit 104 (ASCII 'h'), c1 exit 104. Proves c1 emits
string-initialized `i8[]` locals with correct byte values. The narrow byte
string smoke already covers the core mechanism (local `i8[N]="..."` declaration
+ constant-index read); this fixture extends to a 12-byte buffer with a longer
string literal.

#### `string_multi.etl`

```etl
fn main() i32
  let a i8[4] = "abc"
  let b i8[4] = "xyz"
  ret a[1]
end
```

**Acceptance**: c0 exit 98 (ASCII 'b'), c1 exit 98. Proves multiple
string-initialized locals coexist without buffer corruption. **Not yet covered**
— the existing smoke tests only a single string-initialized local.

**Unlocks**: 5f-STRINGS chunk. The narrow local byte string smoke covers a
subset (single `i8[N]="..."` local with constant-index reads); multiple string
locals, variable-index string reads, and extern parameter string buffers still
require the full 5f-STRINGS emitter work.

---

### Tier 6: Typed extern parameters

These require the extern parameter type emission part of 5f-TYPES.

> **Status (2026-05-01):** A narrow byte string extern C pointer param smoke has
> landed (`scripts/c1_source_to_c_byte_string_extern_smoke.sh`, commit 8d72ca2).
> It proves c1 can emit `signed char *` for fixed byte/i8 array extern parameters,
> allowing local byte string buffers to be passed to an extern C helper. The
> fixture below expands coverage to user-defined byte-array parameters and
> non-byte-array extern param types — those are not yet covered.

#### `extern_typed_write.etl`

```etl
extern fn etl_write_file(path i8[64], buf i8[1024], len i32) i32

fn main() i32
  let path i8[64] = "out.txt"
  let buf i8[1024] = "ok"
  let rc i32 = etl_write_file(path, buf, 2)
  if rc < 0
    ret 1
  end
  ret 0
end
```

**Acceptance**: c0 exit 0, c1 exit 0 (and `out.txt` contains "ok"). Proves
extern function declarations emit typed parameters (`int8_t*`, `int32_t`)
instead of all-`int`.

**Unlocks**: Rest of 5f-TYPES for extern parameters.

---

## Integration with existing gates

| Gate | Current behavior | After full corpus expansion |
|---|---|---|
| `make selfhost-equiv` | 16 fixtures, all single-function i32 | 16 + up to 19 new fixtures across all tiers |
| `make selfhost` | c1 pipeline + 16-fixture equiv | c1 pipeline + expanded equiv |
| `make headless-ready` | check + selfhost + backend-subset + selfeval | No change (absorbs expanded selfhost) |

New fixtures are added to the `fixtures` array in
`scripts/c1_equiv_smoke.sh` as each emitter chunk lands. Until the matching
emitter change is implemented, a fixture will fail equiv (c1 cannot emit it
yet). The fixture file is committed but excluded from the smoke array until
its tier's emitter chunk is complete.

## Ordering vs fixed-point-plan chunks

| Corpus tier | Emitter chunk (fixed-point-plan) | Dependencies |
|---|---|---|
| Tier 1 (multi-fn, params) | 5f-MULTIFN, 5f-PARAMS | 5f-CORPUS (this document) |
| Tier 2 (bool, i8 locals) | 5f-TYPES | 5f-PARAMS |
| Tier 3 (arrays, indexing) | 5f-ARRAYS | 5f-TYPES |
| Tier 4 (structs, fields) | 5f-STRUCTS | 5f-ARRAYS |
| Tier 5 (strings) | 5f-STRINGS | 5f-STRUCTS |
| Tier 6 (typed extern) | 5f-TYPES (extern params) | 5f-PARAMS |
| Buffer expansion | 5f-BUFFERS | 5f-STRINGS |
| Self-compile attempt | 5f-SELFCOMPILE | 5f-BUFFERS |

The 5f-CORPUS chunk from fixed-point-plan is this document. After this chunk
lands, worker chunks can add fixture files to `tests/c1_corpus/` and
corresponding entries to the smoke script as each emitter capability is
implemented.

## Total fixture count

| Category | Count | Running total |
|---|---|---|
| Existing corpus | 16 | 16 |
| Tier 1: Multi-function and parameters | 4 | 20 |
| Tier 2: Typed locals | 3 | 23 |
| Tier 3: Arrays and indexing | 3 | 26 |
| Tier 4: Structs and fields | 3 | 29 |
| Tier 5: String literals | 2 | 31 |
| Tier 6: Typed extern | 1 | 32 |

**Target: 32 corpus fixtures** covering all c1 emitter capabilities needed
for self-compilation.
