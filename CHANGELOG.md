# Changelog

## v0.1.0-rc1 — 2026-05-08

First release candidate of ETL — minimal AOT-first language with embedded
runtime VM.

### Compiler
- compiler-1 self-hosting fixed point achieved (3-stage stable).
- compiler-0 frozen as historical bootstrap.
- ETL VM core ported to ETL itself (compiler1/vm.etl).

### Language Surface
- Heap allocator (alloc/free, ptr type).
- Heap-backed mutable strings (str type).
- Dynamic arrays (dynarr type).
- Tagged unions (etlval type).
- 64KB bytecode buffer (raised from 1024).

### Backends
- C (primary AOT path).
- ETL VM bytecode (interpreted, also implemented in ETL).
- ASM (x86_64 native execution).
- WAT/WASM (executed via wasmtime WASI).
- Triple-equivalence gate: 20 fixtures match c0/C, c1/C, c1-VM-in-ETL.

### Samples
- CLI: calculator REPL, file transform, runtime rule engine.
- Visual: deterministic tick demo, Conway's Life golden, SDL3 bouncing-rect (live).

### Distribution
- Linux x86_64: native build + release tarball smoke gate.
- Linux aarch64: cross-compile + qemu execution.
- macOS x86_64 + arm64: cross-compile build-validated (no runner).
- WASM/WASI: live execution via wasmtime; browser-equivalent via Node.js WebAssembly API.

### Limitations / Known Gaps
- Browser harness uses Node.js WebAssembly API as a substitute for headless Chrome
  (Chrome not in .deps/; documented gap in scripts/release_smoke_wasm_browser.sh).
- SDL3 headless self-eval skipped when SDL3 not available via pkg-config on host
  (visual smoke uses .deps/sdl3 successfully; selfeval-all exits 0).
- str_new VM literal-content limit (known VM constraint).
- Logical and/or not in VM bytecode.
- emit_bytecode missing: unary minus literal, bool/i8 locals, i8 arrays, array ops,
  keyword aliases.
- Wave 6d audio runtime stub deferred.
- Native JIT, large stdlib, package manager: out of L5 scope.

### Gates
All 16 release gates green (see .missions/etl-l5/release-log.txt):
- make check (263 unit tests)
- scripts/c1_equiv_smoke.sh
- make selfhost, make selfhost-selfcompile, make selfhost-bootstrap
- make backend-vm, make backend-asm, make backend-wasm, make backend-subset
- make headless-ready, make examples-cli, make visual, make examples
- make vm-equivalence
- scripts/triple_equiv_smoke.sh
- make release-check (all platforms: x86_64, aarch64, macOS, WASM/WASI)

### Mission Artifacts
- Validation contract: 33 VAL-IDs across 7 areas.
- 8 milestones (M0–M7), all sealed.
- 36 features + 7 cleanup features.
- Clean-checkout reproducibility validated (fresh worktree, no pre-existing .deps/,
  ~150 s total wall time).
