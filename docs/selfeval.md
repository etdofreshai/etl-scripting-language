# Headless Self-Evaluation Harness

The self-evaluation harness runs ETL programs on a headless server and
verifies deterministic behaviour without a display.

## Running

    make headless-selfeval

This compiles every program listed in `examples/selfeval/MANIFEST` via
compiler-0, runs each twice, and checks:

1. **Exit status** matches the value in the MANIFEST.
2. **stdout** matches the corresponding `.expected` golden file.
3. **Determinism** — both runs produce identical output.

## Combined target (selfeval-all)

    make selfeval-all

Runs headless self-evaluation **plus** headless graphics smoke in a single
pass. Graphics checks are **skip-safe**: if SDL3 is absent, the target
reports SKIP for graphics and still passes. When SDL3 is present, the
target additionally:

- Runs the pixel_fill graphics smoke via `scripts/sdl3_headless_smoke.sh`.
- Checks for the PPM artifact at `build/graphics/pixel_fill.ppm`.
- Computes and prints the SHA-256 of the PPM (seed for future golden hashes).

This target is the recommended entry point for CI: it exercises the full
selfeval contract and automatically exercises graphics when SDL3 becomes
available, without requiring any CI configuration changes.

## Headless readiness gate

    make headless-ready

`headless-ready` is the one-command gate for the current
headless-server-ready surface. It runs, in order:

1. `check` — compiler-0 tests, smoke coverage, and runtime tests.
2. `selfhost` — compiler-1 pipeline and self-host equivalence smoke.
3. `backend-plan` — backend plan smoke plus ASM backend smoke.
4. `backend-subset` — shared C, ASM, and WAT cases across the supported
   backend subset.
5. `backend-wasm` — WAT/WASM return-value smoke.
6. `selfeval-all` — deterministic headless self-eval plus skip-safe
   headless graphics.

Passing this gate proves that the repository's current non-interactive
compiler, backend, runtime, and self-evaluation paths are ready to run on a
headless server with the tools available in that environment.

The gate is intentionally still opt-in and does not claim full SDL3 graphics
execution unless SDL3 development libraries are installed. Without SDL3,
graphics reports SKIP and the gate still passes. WAT/WASM runtime execution
is also tool-dependent: when `wat2wasm` plus `wasmtime` or `wasmer` are
available, the smoke scripts execute generated WASM; otherwise they validate
the emitted WAT text and report the reduced coverage.

## Contract

Each self-eval program MUST:

- Use only existing language and runtime features (no SDL).
- Produce fully deterministic output across runs.
- Return a known exit code.
- Print structured state to stdout for golden-file comparison.

### Output format (current)

Output is one value per line via `etl_print_i32`. Programs emit pairs of
(tick, state) during simulation, then a final (tick, state) pair. The
golden file documents what each line represents.

### Graphics artifact extension

When SDL3 rendering is available, the selfeval contract extends to include
rendered artifacts alongside the tick/state logs:

| Artifact          | Path pattern                        | Description                                         |
|-------------------|-------------------------------------|-----------------------------------------------------|
| **Tick log**      | `.expected` golden file             | Per-tick numeric output (current `.expected` files) |
| **State snapshot**| stdout                              | Struct dump at key ticks (struct i32 fields)        |
| **PPM screenshot**| `build/graphics/<program>.ppm`      | Rendered frame as binary PPM                         |
| **Pixel hash**    | `build/graphics/<program>.sha256`   | SHA-256 of raw framebuffer bytes for exact compare   |

The verification flow when SDL3 is present:

1. Compile ETL program to C via compiler-0 (or compiler-1).
2. Link with `etl_runtime.c` + `etl_graphics_sdl3.c` + SDL3.
3. Run headlessly; program emits tick logs to stdout and writes PPM.
4. Harness compares stdout against golden `.expected` file.
5. Harness computes SHA-256 of each PPM and compares against `.sha256` sidecar.
6. Determinism check: run twice, require identical stdout **and** pixel hashes.

When SDL3 is absent, steps 2–6 are skipped. The harness reports SKIP for
graphics artifacts and passes as long as the tick/state log verification
succeeds. This ensures CI is green today while the artifact contract is
ready for automatic activation when SDL3 is installed.

### Deterministic ticks to pixels mapping

The selfeval programs emit structured (tick, state) pairs on stdout.
When a graphics self-eval program also renders frames, each tick's state
deterministically produces a corresponding PPM screenshot. This creates a
verifiable chain:

```
tick N → state S(N) → render(S(N)) → framebuffer F(N) → PPM + sha256
```

Because both the numeric state and the framebuffer are deterministic,
future pixel/hash comparison can detect rendering regressions without
needing to store large binary golden files — only the compact SHA-256
sidecar is required.

## Adding new self-eval programs

1. Write an ETL program in `examples/selfeval/`.
2. Add a line to `examples/selfeval/MANIFEST`:
   `filename.etl  <expected_exit>  <description>`
3. Capture golden output in `examples/selfeval/<filename>.expected`.
4. Run `make headless-selfeval` to verify.
5. If the program uses graphics, also run `make selfeval-all` to verify
   PPM artifact generation (requires SDL3).
