# ETL L5 Mission — Validation Contract

Testable behavioral assertions for taking ETL from c1 self-compile fixed
point to a complete L5 minimal language with VM-in-ETL, multi-platform
distribution, live SDL3, and full backend validation.

Each assertion has a stable ID. Every ID must be claimed by exactly one
feature in `features.json`. Validators check assertions against the running
codebase; they never see implementation diffs first.

---

## Area: Foundation (M0)

### VAL-FND-001: Working tree clean on main
`git status` on `main` clean (excluding `.missions/`, `.local/`, `.deps/`).

### VAL-FND-002: afk merged to main
`git merge-base --is-ancestor dcd8040 main` exits 0.

### VAL-FND-003: Pre-mission gates green on main
`make check`, `scripts/c1_equiv_smoke.sh`, `make selfhost`,
`make selfhost-selfcompile`, `make selfhost-bootstrap`, `make backend-vm`,
`make examples-cli`, `make visual`, `make examples` exit 0.
Note: `make visual` may exit 0 with SKIP when SDL3 absent at M0; M4 requires SDL3 live.

### VAL-FND-004: In-flight scripted-input work resolved
Uncommitted scripted-input/sema changes committed (smoke passes) or reverted with reason.

---

## Area: Language Surface (M1)

### VAL-LANG-001: Heap allocator builtins
`alloc(n)->ptr` / `free(p)` from compiler-1, C+VM backends, valgrind clean.

### VAL-LANG-002: Heap-backed mutable strings
str type: literal, length, concat, indexing, equality. C+VM identical. ≥3 fixtures.

### VAL-LANG-003: Dynamic arrays
dynarr: push/length/get/set/grow. C+VM agree. ≥3 fixtures.

### VAL-LANG-004: Tagged unions
etlval: int/bool/ptr/str variants, tag discrimination. C+VM agree. ≥2 fixtures.

### VAL-LANG-005: Surface additions documented
SPEC, DESIGN, support-matrix describe new surface accurately with limitations.

---

## Area: VM in ETL (M2)

### VAL-VMETL-001: VM core in ETL
`compiler1/vm.etl` implements interpreter (dispatch, stack, frames, locals, branches, arithmetic). Compiles via c1, runs bytecode corpus.

### VAL-VMETL-002: C VM as oracle
`runtime/etl_vm.c` retained. `make vm-equivalence` ≥10 fixtures match.

### VAL-VMETL-003: Triple equivalence
`scripts/triple_equiv_smoke.sh` ≥20 fixtures match across c0/C, c1/C, c1-VM-in-ETL.

### VAL-VMETL-004: ETL-VM reachable from AOT host
ETL host calls etl_compile_module + etl_run_main_i32 routed through ETL VM (ETL_VM_ETL). Smoke verifies via stderr log.

---

## Area: CLI Samples (M3)

### VAL-CLI-001: Calculator REPL
stdin loop, +/-/*/(), errors without crash, EOF→exit 0, smoke matches expected.

### VAL-CLI-002: File transform
Read input, transform (uppercase), write output, missing-file handled cleanly. Round-trip smoke.

### VAL-CLI-003: Rule engine via runtime VM
Loads rule script at runtime via ETL VM, evaluates records, prints decisions. Smoke verifies VM invocation via stderr log.

### VAL-CLI-004: examples-cli green
`make examples-cli` covers all three samples.

---

## Area: SDL3 Live (M4)

### VAL-SDL3-001: SDL3 in ./.deps/
`./.deps/sdl3/include/SDL3/SDL.h` + `lib/libSDL3.{so,a}`. Gitignored. Reproducible setup.

### VAL-SDL3-002: Deterministic tick demo
3 consecutive runs byte-identical.

### VAL-SDL3-003: SDL3 visual sample (live)
At least one sample runs against live SDL3 from `./.deps/sdl3/`, matches golden frame.

### VAL-SDL3-004: Phase 6 waves complete
Waves 6c (scripted input, done in F0.1) and 6e (Life golden) complete. Wave 6d (audio stub) intentionally deferred — out of mission scope per non-goals.

---

## Area: Backend Validation (M5)

### VAL-BE-001: backend-subset all four backends
≥10 fixtures match across C, VM, ASM, WAT. Documented in backend-plan.md.

### VAL-BE-002: backend-asm executes
`make backend-asm` assembles + runs ASM on x86_64; matches C.

### VAL-BE-003: backend-wasm via wasmtime
`./.deps/wasmtime` + `./.deps/wat2wasm` fetched. `make backend-wasm` ETL→WAT→wasm→wasmtime; matches C.

### VAL-BE-004: Support matrix accurate
support-matrix.md verified against fixtures.

---

## Area: Multi-Platform (M6)

### VAL-DIST-001: Linux x86_64 release tarball
`build/release/etl-linux-x86_64.tar.gz`. Untar+smoke on temp dir.

### VAL-DIST-002: Linux aarch64 + qemu
`./.deps/qemu-aarch64-static` fetched. Cross-compile, run c1 corpus subset under qemu.

### VAL-DIST-003: macOS cross-compile
Mach-O produced for x86_64+arm64 (build-validated only, no runner).

### VAL-DIST-004: WASM/WASI + browser
WASI calculator via wasmtime. Browser harness via headless Chrome.

### VAL-DIST-005: release-check all platforms
Top-level `make release-check` exits 0.

---

## Area: Release (M7)

### VAL-REL-001: All gates green
Full gate sequence on main exits 0.

### VAL-REL-002: Docs accurate
SPEC, DESIGN, ROADMAP, language-goal-roadmap, runtime-vm-plan, backend-plan, support-matrix, PATH_TO_APPS describe shipped state.

### VAL-REL-003: Clean-checkout reproducible
Fresh worktree + `scripts/setup.sh` + `make release-check` succeeds.

### VAL-REL-004: Release tag
`v0.1.0-rc1` tagged; CHANGELOG.md committed.
