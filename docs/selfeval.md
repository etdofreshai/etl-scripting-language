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

### Future graphics extension

When SDL3 rendering is added, the contract will grow to include:

| Artifact          | Description                                         |
|-------------------|-----------------------------------------------------|
| **Tick log**      | Per-tick numeric output (current `.expected` files) |
| **State snapshot**| Struct dump at key ticks (struct i32 fields)        |
| **Screenshot**    | Rendered frame written to an artifact path           |
| **Pixel hash**    | SHA-256 of raw framebuffer bytes for exact compare   |

Screenshot paths will follow the convention
`build/selfeval/<program>/<tick>.png`.  Pixel hashes will be stored in
a sidecar `<tick>.sha256` file.  The verification script will compare
hashes rather than binary pixel data to keep golden files compact.

## Adding new self-eval programs

1. Write an ETL program in `examples/selfeval/`.
2. Add a line to `examples/selfeval/MANIFEST`:
   `filename.etl  <expected_exit>  <description>`
3. Capture golden output in `examples/selfeval/<filename>.expected`.
4. Run `make headless-selfeval` to verify.
