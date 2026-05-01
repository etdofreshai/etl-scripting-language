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

## Trace artifact target

    make selfeval-trace

This target verifies a minimal deterministic file artifact for headless runs.
It compiles `examples/selfeval/trace_artifact.etl`, runs it twice, and checks:

1. **Exit status** is `15`, the final simulated state.
2. **stdout** matches `examples/selfeval/trace_artifact.expected`.
3. **Artifact existence** at `build/selfeval/trace_artifact.csv`.
4. **Artifact content** matches `examples/selfeval/trace_artifact.artifact`.
5. **Artifact SHA-256** is
   `cc1c12aecf2110626992b8fa09fe1b63cc32b9f15b986021b20b18cb4b76c2e8`.
6. **Repeatability** requires identical stdout and identical artifact bytes
   across both runs.

## Combined target (selfeval-all)

    make selfeval-all

Runs headless self-evaluation **plus** headless graphics smoke in a single
pass. It also runs the deterministic trace artifact smoke. The pure-C software
framebuffer check always runs because it has no external dependency. SDL3
checks are **skip-safe**: if SDL3 is absent, the target reports SKIP for SDL3
graphics and still passes. The target:

- Runs `scripts/selfeval_smoke.sh` for stdout/exit determinism.
- Runs `scripts/selfeval_trace_smoke.sh` for the text artifact contract.
- Runs the software framebuffer smoke via `scripts/software_graphics_smoke.sh`.
- Checks `build/graphics/software_framebuffer.ppm`.
- Compares deterministic pixel values and the PPM SHA-256 checksum.
- Runs the pixel_fill graphics smoke via `scripts/sdl3_headless_smoke.sh`.
- When SDL3 is available, checks `build/graphics/pixel_fill.ppm` and prints
  its SHA-256.

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
6. `selfeval-all` — deterministic headless self-eval, trace artifacts,
   software graphics, and skip-safe SDL3 graphics.

Passing this gate proves that the repository's current non-interactive
compiler, backend, runtime, and self-evaluation paths are ready to run on a
headless server with the tools available in that environment.

The gate always proves the portable software framebuffer path. It does not
claim SDL3 graphics execution unless SDL3 development libraries are installed.
Without SDL3, SDL3 graphics reports SKIP and the gate still passes. WAT/WASM
runtime execution is also tool-dependent: when `wat2wasm` plus `wasmtime` or `wasmer` are
available, the smoke scripts execute generated WASM; otherwise they validate
the emitted WAT text and report the reduced coverage.

## Contract

Each self-eval program MUST:

- Use only existing language and runtime features (no SDL).
- Produce fully deterministic output across runs.
- Return a known exit code.
- Print structured state to stdout for golden-file comparison.

Trace-producing self-eval programs additionally MUST:

- Write artifacts under `build/selfeval/`.
- Use a stable, portable text format. The current trace format is CSV:
  `tick,state` header followed by one row per simulated tick.
- Keep stdout as the console log contract and the artifact as the persisted
  trace contract; both are checked independently.
- Be repeatable byte-for-byte across consecutive runs.

### Output format (current)

Output is one value per line via `etl_print_i32`. Programs emit pairs of
(tick, state) during simulation, then a final (tick, state) pair. The golden
file documents what each line represents. Trace artifacts use the same tick
and state values in text form so a headless run has both deterministic console
logs and a persisted deterministic artifact.

### Graphics artifact extension

Graphics selfeval extends the contract to include rendered artifacts alongside
the tick/state logs. The software framebuffer path is always available; SDL3
uses the same API and artifact format when installed.

| Artifact          | Path pattern                        | Description                                         |
|-------------------|-------------------------------------|-----------------------------------------------------|
| **Console tick log** | `.expected` golden file          | Per-tick numeric stdout output                      |
| **Trace artifact** | `build/selfeval/<program>.csv`     | Persisted tick/state text artifact                  |
| **State snapshot**| stdout or trace artifact            | Struct/scalar state at key ticks                    |
| **PPM screenshot**| `build/graphics/<program>.ppm`      | Rendered frame as binary PPM                         |
| **Pixel hash**    | script-side expected SHA-256        | SHA-256 of PPM bytes for exact compare               |

The verification flow:

1. Compile ETL program to C via compiler-0 (or compiler-1).
2. Link with `etl_runtime.c` plus one graphics backend when graphics are used.
3. Run headlessly; program emits tick logs to stdout and writes artifacts.
4. Harness compares stdout against golden `.expected` file.
5. Harness compares text artifacts directly and/or computes SHA-256 for exact
   byte comparison.
6. For graphics, harness computes SHA-256 of each PPM and compares against the
   expected hash.
7. Determinism check: run twice, require identical stdout **and** artifact
   bytes/hashes.

When SDL3 is absent, only the SDL3 backend is skipped. The software framebuffer
backend still verifies graphics artifacts, so CI can catch deterministic pixel
regressions without graphics libraries.

### Deterministic ticks to pixels mapping

The selfeval programs emit structured (tick, state) pairs on stdout. Trace
artifact programs persist the same sequence under `build/selfeval/`. When a
graphics self-eval program also renders frames, each tick's state
deterministically produces a corresponding PPM screenshot. This creates a
verifiable chain:

```
tick N -> state S(N) -> stdout + CSV -> render(S(N)) -> framebuffer F(N) -> PPM + sha256
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
5. If the program writes a trace artifact, add an artifact golden and extend
   `scripts/selfeval_trace_smoke.sh`.
6. If the program uses graphics, also run `make selfeval-all` to verify
   software PPM artifact generation and optional SDL3 coverage.
