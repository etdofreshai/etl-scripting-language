# ETL Support Matrix

## Summary

ETL is currently a bootstrap-stage, ahead-of-time compiled language with C as
the primary durable backend. Compiler-1 can lex, parse, type-check, and emit C
for a 32-fixture self-host equivalence corpus; ASM and WAT/WASM cover active
validation subsets; the VM executes a narrow expression, local-slot, control-flow,
and function bytecode subset through the same frontend path. Full compiler fixed
point, runtime-loaded ETL modules, graphical examples, release packaging, and broad
application support remain in progress or not implemented.

## Language feature support

Column key for the grid below:

- ✓ SUPPORTED — proven by a passing gate fixture.
- △ PARTIAL — works for a documented subset; limitation noted.
- ✗ UNSUPPORTED — no fixture exists; do not claim this path works.

| Feature | c0/C | c1/C | c1/VM | c1/ASM | c1/WAT | Notes / proving gate |
|---|---|---|---|---|---|---|
| integer arithmetic (i32 +,-,*,/,%) | ✓ | ✓ | ✓ | ✓ | ✓ | `make check`, `scripts/c1_equiv_smoke.sh`, `scripts/backend_subset_smoke.sh`, `scripts/c1_vm_expr_smoke.sh`. Sixteen four-backend fixtures cover +, *, -, comparisons, and precedence. |
| comparisons (==, !=, <, <=, >, >=) | ✓ | ✓ | ✓ | ✓ | ✓ | All six comparison operators proven across all four backends via `scripts/backend_subset_smoke.sh` (cmp_eq, cmp_neq, cmp_lte, cmp_gt, cmp_gte, cmp_false). |
| logical `not` (unary) | ✓ | ✓ | ✓ | ✓ | ✓ | ret_not_true and ret_not_false in 16 four-backend shared set (`scripts/backend_subset_smoke.sh`). |
| logical `and` / `or` (binary) | ✓ | ✓ | ✗ | ✓ | ✓ | VM excluded: emit_bytecode has no TK_AND/TK_OR opcode; etl_vm.c dispatcher has no matching case. Two three-backend fixtures (ret_logical, eager_and_truthy) proven via C/ASM/WAT only (`scripts/backend_subset_smoke.sh`). |
| `if`/`elif`/`else` | ✓ | ✓ | △ | ✓ | ✓ | VM: if/else proven (if_then_local, if_else_local in 16 four-backend set). elif not confirmed in VM. ASM/WAT: full if/elif/else proven (`scripts/c1_equiv_smoke.sh`, `scripts/backend_subset_smoke.sh`). |
| `while` | ✓ | ✓ | ✓ | ✓ | ✓ | while_count in 16 four-backend shared set (`scripts/backend_subset_smoke.sh`). |
| `fn` declaration (single function) | ✓ | ✓ | ✓ | ✓ | ✓ | All 16 four-backend fixtures use `fn main() i32`. `scripts/backend_subset_smoke.sh`. |
| `fn` params i32 | ✓ | ✓ | ✗ | ✓ | ✓ | VM: no i32-param helper-function fixture in four-backend set; emit_bytecode does not support i32 array params; multi-function with params not proven in VM. ASM/WAT proven by `scripts/c1_asm_function_call_smoke.sh`, `scripts/c1_wat_function_call_smoke.sh`. |
| `fn` params bool/i8/byte | ✓ | ✓ | ✗ | △ | △ | ASM/WAT narrow slice (scalar bool/i8/byte helper params) proven; full ABI unsupported. VM: no fixture. `scripts/c1_source_to_c_scalar_param_smoke.sh`, `scripts/c1_asm_array_smoke.sh`, `scripts/c1_wat_array_smoke.sh`. |
| recursion | ✓ | ✓ | ✗ | ✗ | ✗ | C only. `scripts/c1_equiv_smoke.sh`. |
| local i32 | ✓ | ✓ | ✓ | ✓ | ✓ | local_init_return, local_assign_return, multi_local_assign in 16 four-backend set (`scripts/backend_subset_smoke.sh`). |
| local bool/i8 | ✓ | ✓ | ✗ | △ | △ | VM: emit_bytecode does not support bool or i8 scalar local types (excluded from triple-equiv, F2.3). ASM/WAT: narrow scalar bool/i8/byte slice proven. `scripts/c1_equiv_smoke.sh`. |
| local i32 array constant index | ✓ | ✓ | ✗ | ✓ | ✓ | VM: emit_bytecode does not support array ops (F2.3 exclusion). ASM/WAT proven by `scripts/c1_asm_array_smoke.sh`, `scripts/c1_wat_array_smoke.sh`. |
| local i32 array variable index | ✓ | ✓ | ✗ | ✓ | ✓ | VM: same emit_bytecode gap. ASM/WAT proven by `scripts/c1_asm_array_smoke.sh`, `scripts/c1_wat_array_smoke.sh`. |
| local i8 array | ✓ | ✓ | ✗ | ✓ | ✓ | VM: emit_bytecode does not support i8 array indexing (F2.3: local_i8_array excluded). ASM/WAT proven by `scripts/c1_asm_array_smoke.sh`, `scripts/c1_wat_array_smoke.sh`. |
| local string i8[N]="..." | ✓ | ✓ | ✗ | ✓ | ✓ | VM: no fixture. ASM/WAT proven by `scripts/c1_source_to_c_byte_string_smoke.sh`, `scripts/c1_asm_array_smoke.sh`, `scripts/c1_wat_array_smoke.sh`. |
| struct decl + i32 field | ✓ | ✓ | ✗ | ✓ | ✓ | VM: no fixture. ASM/WAT proven by `scripts/c1_asm_struct_field_smoke.sh`, `scripts/c1_wat_struct_field_smoke.sh`. |
| struct array field (i32 fields) | ✓ | ✓ | ✗ | ✓ | ✓ | VM: no fixture. ASM/WAT proven by `scripts/c1_asm_struct_array_smoke.sh`, `scripts/c1_wat_struct_array_smoke.sh`. |
| by-value struct param | ✓ | ✓ | ✗ | ✗ | ✗ | C only. `scripts/c1_source_to_c_struct_param_smoke.sh`. |
| extern fn void return | ✓ | ✓ | ✗ | △ | △ | ASM: narrow extern i32/scalar-param call proven; void-return extern not confirmed in ASM. WAT: extern import/call smoke runs wat2wasm validation only (no host runtime). VM: no fixture. `scripts/c1_asm_extern_call_smoke.sh`, `scripts/c1_wat_extern_call_smoke.sh`. |
| extern fn i32 return | ✓ | ✓ | ✗ | △ | △ | ASM: proven via C helpers (`scripts/c1_asm_extern_call_smoke.sh`). WAT: validation-only (wat2wasm; no host WASI runtime for env imports). VM: no fixture. `scripts/c1_wat_extern_import_smoke.sh`. |
| extern bool/i8/byte param | ✓ | ✓ | ✗ | △ | ✗ | ASM: extern scalar bool/i8/byte param proven (`scripts/c1_asm_extern_scalar_param_smoke.sh`). WAT: not confirmed. VM: no fixture. |
| extern byte-array pointer param | ✓ | ✓ | ✗ | ✗ | ✗ | C only. `scripts/c1_source_to_c_byte_string_extern_smoke.sh`. |
| `sizeof` | ✓ | ✓ | ✗ | ✗ | ✗ | C only. `scripts/sizeof_smoke.sh`, `make check`. |
| unary minus | ✓ | ✓ | ✗ | △ | △ | VM: emit_bytecode does not support unary-minus literal (F2.3: ret_unary_minus excluded). ASM/WAT: EXPERIMENTAL in c1 per equivalence corpus. `scripts/c1_equiv_smoke.sh`. |
| `return` | ✓ | ✓ | ✓ | ✓ | ✓ | All 16 four-backend fixtures use `ret`. `scripts/backend_subset_smoke.sh`. |
| keyword aliases (full-word: `integer`, `boolean`, etc.) | ✓ | ✓ | ✗ | ✓ | ✓ | VM: emit_bytecode does not support keyword-alias syntax (F2.3: full_word_aliases excluded). ASM/WAT: aliases handled at lex/parse level, emitter unaffected. |
| **ptr (opaque heap pointer)** | ✗ | ✓ | △ | ✗ | ✗ | c1/C proven (`scripts/c1_equiv_smoke.sh` incl. heap_alloc_basic.etl; valgrind clean). VM: functional but BC buffer (1024 bytes) limits complex programs (`scripts/c1_vm_heap_alloc_smoke.sh`). ASM/WAT: not supported. |
| **str (heap mutable string)** | ✗ | ✓ | △ | ✗ | ✗ | c1/C proven (`scripts/c1_string_equiv_smoke.sh`; valgrind clean). VM: str_new ignores its ptr input and creates an empty string; meaningful string content requires str_concat. BC buffer limit applies. ASM/WAT: not supported. |
| **dynarr (growable i32 array)** | ✗ | ✓ | △ | ✗ | ✗ | c1/C proven (`scripts/c1_dynarr_equiv_smoke.sh`; valgrind clean). VM: functional; BC buffer limit applies. dynarr element type is i32 only; no bounds checking. ASM/WAT: not supported. |
| **etlval (tagged union int/bool/ptr/str)** | ✗ | ✓ | △ | ✗ | ✗ | c1/C proven (`scripts/c1_tagged_union_equiv_smoke.sh`; valgrind clean). VM: str variant fixture elided; BC buffer limit applies. ASM/WAT: not supported. |

## Platform / distribution

| Platform | Architecture | Status | Artifact | Notes |
|---|---|---|---|---|
| Linux x86_64 | x86_64 | BUILD + RUN | `build/release/etl-linux-x86_64.tar.gz` | Native ELF; smoke-tested via `make release-check-x86_64`. |
| Linux aarch64 | aarch64 | BUILD + RUN (qemu) | `build/release/etl-linux-aarch64.tar.gz` | Cross-compiled via zig cc (musl); run under `.deps/qemu-aarch64-static`; gate: `make release-check-aarch64`. |
| macOS x86_64 | x86_64 | BUILD-VALIDATED | `build/release/etl-macos-x86_64.tar.gz` | Mach-O cross-compiled via zig cc (`-target x86_64-macos`). No Apple SDK needed. Confirmed via `file`. Not executed (Linux host). Gate: `make release-check-macos`. |
| macOS arm64 | arm64 | BUILD-VALIDATED | `build/release/etl-macos-arm64.tar.gz` | Mach-O cross-compiled via zig cc (`-target aarch64-macos`). No Apple SDK needed. Confirmed via `file`. Not executed (Linux host). Gate: `make release-check-macos`. |
| WASM/WASI | wasm32 | BUILD + RUN (wasmtime) | WAT text + wasm binary | Via `.deps/wasmtime` + `.deps/wat2wasm`; gate: `make release-check-wasm`. |
| WASM/browser-equivalent | wasm32 | BUILD + RUN (Node.js WebAssembly API) | WAT text + wasm binary | Node.js WebAssembly harness exercises proc_exit trap path; gate: `make release-check-wasm`. Headless Chrome not yet implemented (gap). |

**BUILD-VALIDATED**: Mach-O binary produced by zig cross-compile and confirmed via `file` output.
No execution on the CI/Linux host. Requires a macOS host to verify runtime behavior.

## Runtime / tooling

CLI subcommands:

| Tooling surface | Status | Notes / gate |
|---|---|---|
| `etl check FILE.etl` | EXPERIMENTAL | Uses the c1 lex+parse+sema path; `docs/cli.md`; `make examples-cli` |
| `etl compile FILE.etl -o OUT` | SUPPORTED | Uses the durable c0 -> C -> cc AOT path; `docs/cli.md`; `make examples-cli` |
| `etl run FILE.etl` | SUPPORTED | Compiles through c0/C to a temporary native executable and forwards its exit code; `make examples-cli` |

Makefile gates:

| Gate | Status | Notes |
|---|---|---|
| `make check` | GREEN | Unit tests, core smokes, compiler-1 focused smokes, bytecode emit smoke, runtime C tests. |
| `make selfhost` | GREEN | `c1-pipeline`, `selfhost-equiv`, and `scripts/c1_smoke.sh`. |
| `make selfhost-equiv` | GREEN | 33-fixture c0/C vs c1/C equivalence corpus (incl. nested_let_block, i32_array_param). |
| `make selfhost-selfcompile` | GREEN | c1 emits its own source as 112,575 bytes of valid C; cc builds c2 successfully. |
| `make selfhost-bootstrap` | GREEN | Three-stage fixed point achieved: sha256(c1_self.c)==sha256(c2_self.c)==sha256(c3_self.c). c0 is frozen as historical bootstrap. |
| `make backend-vm` | GREEN | Bytecode emit + VM return + expr/locals + control flow + functions + runtime-compile equivalence smokes. |
| `make backend-subset` | GREEN | 16 four-backend (C/VM/ASM/WAT) + 2 three-backend (C/ASM/WAT) shared fixtures. |
| `make backend-asm` | GREEN | Focused x86-64 System V assembly smokes; assembles and executes on x86_64. |
| `make backend-wasm` | GREEN | 23 WAT cases executed via wasmtime; 2 extern cases via wat2wasm validation only. |
| `make examples-cli` | GREEN | 4-case CLI suite: hello, calculator, file_transform, config_rules. |
| `make visual` | GREEN | tick_demo + software_pixel; SDL3 branch SKIPs cleanly when SDL3 absent. |
| `make examples` | GREEN | examples-cli + visual + runtime-compile (VM) example. |
| `make release-check` | GREEN | Orchestrates all M6 platform checks: release-check-x86_64 (Linux x86_64), release-check-aarch64 (Linux aarch64/qemu), release-check-macos (macOS x86_64+arm64 Mach-O), release-check-wasm (WASI+browser-equiv). Also aggregates check + selfhost + every backend gate + examples. Exit 0 on dev workstation. |
| `make headless-ready` | GREEN | Integration target wired through current readiness gates. |

## Optional dependencies

- SDL3 is needed for the SDL3 headless path exercised by
  `scripts/sdl3_headless_smoke.sh` through `make headless-ready`. When SDL3
  development headers or libraries are missing, the SDL3-specific smoke is
  expected to skip rather than fail the whole readiness gate.
- `wat2wasm` from WABT (v1.0.41, fetched by `scripts/setup.sh` to `.deps/wat2wasm`)
  is used to convert emitted WAT text into WASM.
- `wasmtime` (v36.0.9, fetched by `scripts/setup.sh` to `.deps/wasmtime`) is
  needed to execute generated WASM. Without it, WAT/WASM smokes stop after
  text validation or `wat2wasm` validation.
- The ASM backend assumes x86-64 System V tooling (`as`, `cc`, and a compatible
  host/linker). It is an active validation backend, not the primary portability
  path.

## Limitations

- ETL remains single-file from the compiler's perspective. Compiler-1 smoke
  scripts concatenate modules into one temporary compilation unit.
- C is the stable AOT production path. Compiler-1 fixed point is not complete;
  compiler-0 is not frozen yet.
- Runtime ETL must use the same frontend and semantic rules as AOT ETL, but
  runtime-loaded ETL modules are not implemented yet. The current VM is a
  bootstrap C helper for a small ASCII bytecode subset.
- No broad pointer arithmetic, dereference, field access through pointers, or
  pointer comparison exists. `pointer` is an opaque FFI boundary type.
- Strings are fixed-size `byte[N]` or `i8[N]` buffers with a null terminator in
  the core language. The M1 `str` opaque type provides a heap-backed mutable
  string surface via extern calls; compiler-1 (c1/C) supports it but
  compiler-0 (c0) does not. ASM and WAT backends do not support `str`.
- Arrays are fixed-size locals or narrow parameter forms in the proven subsets
  for the core language. The M1 `dynarr` opaque type provides a growable
  i32-only array surface via extern calls; compiler-1 (c1/C) supports it but
  compiler-0 (c0) does not. ASM and WAT backends do not support `dynarr`.
- `dynarr` element type is i32 only in M1. No bounds checking is performed by
  the C backend.
- The VM bytecode buffer is 1024 bytes, which limits the complexity of programs
  using M1 opaque types in the VM backend. This is tracked as tech debt;
  expansion is needed before VM-in-ETL (M2).
- The VM `str_new` extern ignores its `ptr` input and creates an empty string.
  Programs requiring meaningful string content in the VM must construct it via
  `str_concat` or equivalent operations.
- ASM and WAT backends do not support M1 opaque types (`ptr` heap alloc, `str`,
  `dynarr`, `etlval`).
- emit_bytecode (VM backend) does not support: unary-minus literal, bool/i8
  scalar local types, i8 array indexing, logical `and`/`or` binary ops, general
  array ops (sum, loop, i32 array params), and keyword-alias syntax. These
  constructs are excluded from VM coverage and from the triple-equivalence gate.
- Structs are value types for the proven subsets. Struct returns, extern struct
  parameters, recursive structs, and broad nested struct shapes remain outside
  the supported surface.
- WASI exit code range accepted by wasmtime v36 is [0..126); ETL programs
  returning values ≥ 126 receive exit code 1 from wasmtime.
- The WAT/WASM extern-call smokes (c1_wat_extern_call_smoke.sh,
  c1_wat_extern_import_smoke.sh) run wat2wasm validation only; a WASI host
  providing the `env/etl_write_file1024` import is not implemented.
- The CLI has no REPL, package manager, project manifest, incremental cache, or
  release packaging flow.
- Diagnostics are improving but remain uneven across c0, c1, and backend smoke
  harnesses; unsupported features should be documented and tested as such before
  being treated as user-facing contracts.
