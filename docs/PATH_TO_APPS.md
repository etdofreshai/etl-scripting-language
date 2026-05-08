# Path to Apps

This document breaks the graphical/playable work into one-wave increments.
It is subordinate to `docs/ROADMAP.md`, `docs/SPEC.md`, and `docs/DESIGN.md`:
no wave may add source syntax. Runtime-facing capability reaches ETL through
`extern fn` declarations and C-side runtime implementations.

## Current Selection

Next wave: **7a** (Calculator).

Reason: Phase 6 visual runtime is complete. Wave 6d (audio stub) was skipped
by supervisor reorder — Life golden (6e) was prioritised for earlier graphical
payoff. 6e landed in F4.4-phase6-complete: `make visual` now runs the Conway's
Life golden and the live SDL3 bouncing-rect smoke without any SKIP.

## Phase 6: Visual Runtime

Gate: `make visual` passes with the Conway's Life golden once 6e lands. ✅

- [x] **6a: Graphics extern surface and SDL3/software shims**
  - Deliverables:
    - Add a reusable graphics extern API under `runtime/`.
    - Provide a deterministic software framebuffer backend.
    - Provide an optional SDL3 offscreen backend that skips cleanly when SDL3
      is unavailable.
    - Add a smoke script under `scripts/` and a small ETL graphics example.
  - Gate: graphics smoke compiles ETL through compiler-0, links the runtime
    graphics backend, writes a framebuffer artifact, and validates pixels.
  - Evidence in current tree:
    - `runtime/etl_graphics.h`
    - `runtime/etl_graphics_software.c`
    - `runtime/etl_graphics_sdl3.c`
    - `scripts/software_graphics_smoke.sh`
    - `scripts/sdl3_headless_smoke.sh`
    - `examples/graphics/software_framebuffer.etl`
    - `examples/graphics/pixel_fill.etl`

- [x] **6b: Headless visual smoke target**
  - Deliverables:
    - Add a deterministic `make visual` target.
    - Add at least one visual smoke under `scripts/`.
    - Wire the visual target into `make examples`.
  - Gate: `make visual` is green without requiring SDL3.
  - Evidence in current tree:
    - `Makefile` target `visual`
    - `Makefile` target `examples: examples-cli visual`
    - `scripts/visual_smoke.sh`
    - `examples/visual/tick_demo.etl`
    - `examples/visual/software_pixel.etl`

- [x] **6c: Deterministic scripted input runtime**
  - Deliverables:
    - Add a small C runtime input module under `runtime/` that reads scripted
      input events from a file or fixed byte buffer. No live keyboard polling.
    - Expose input through `extern fn` declarations in the smoke/example that
      uses it.
    - Add an ETL smoke under `scripts/` with checked golden output or exit
      status, and wire it into `make visual`.
    - Document the input event format and determinism contract.
  - Gate: `make check` and the new input smoke are green locally.
  - Constraint: do not add parser syntax or language features.
  - Evidence in current tree:
    - `runtime/etl_input.h`
    - `runtime/etl_input.c`
    - `examples/visual/scripted_input.etl`
    - `examples/visual/scripted_input.events`
    - `examples/visual/scripted_input.expected`
    - `scripts/scripted_input_smoke.sh`
    - `Makefile` target `visual`

- [ ] **6d: Deterministic audio runtime stub**
  - Deliverables:
    - Add a deterministic audio event/buffer runtime surface under `runtime/`.
      The test path must not touch host audio devices.
    - Expose the surface through `extern fn` in a smoke/example.
    - Add an ETL smoke under `scripts/` with a golden sample/count/hash and
      wire it into `make visual`.
    - Document the audio determinism contract.
  - Gate: `make check` and the new audio smoke are green locally.
  - Constraint: no wall-clock timing or live audio device dependency.
  - Note: skipped by supervisor reorder in F4.4; deferred to a future wave.

- [x] **6e: Conway's Life visual golden**
  - Deliverables:
    - Add a Conway's Life ETL example under `examples/visual/`.
    - Render with the deterministic software graphics backend and fixed tick
      count (10 generations).
    - Blinker seed (horizontal, cells 15,16,17 on row 16 of a 32x32 grid).
    - Add a PPM framebuffer golden committed to `examples/visual/`.
    - Add `scripts/life_golden_smoke.sh` that builds, runs, and byte-compares
      the output against the golden.
    - Wire life_golden_smoke.sh into `scripts/visual_smoke.sh`.
    - Update `scripts/visual_smoke.sh` to run SDL3 live from `.deps/sdl3/`
      instead of SKIPping via pkg-config.
  - Gate: `make check` and `make visual` are green; `make visual` verifies the
    Life golden and runs the SDL3 bouncing-rect smoke live.
  - Evidence in current tree:
    - `examples/visual/life.etl`
    - `examples/visual/life.golden.ppm`
    - `scripts/life_golden_smoke.sh`
    - `scripts/visual_smoke.sh` (updated: .deps/sdl3 detection, no SKIP)

## Phase 7: App Ladder

Gate: `make examples` passes after each wave's golden is added.

- [ ] **7a: Calculator**
  - Deliverables: deterministic calculator example, scripted input, expected
    output golden, and `make examples` wiring.
  - Gate: `make check` and the calculator example smoke are green.

- [ ] **7b: Breakout**
  - Deliverables: deterministic breakout example with scripted input and
    framebuffer/state golden.
  - Gate: `make check` and the breakout smoke are green.

- [ ] **7c: Snake**
  - Deliverables: deterministic snake example with scripted input and
    framebuffer/state golden.
  - Gate: `make check` and the snake smoke are green.

- [ ] **7d: Asteroids**
  - Deliverables: deterministic asteroids example with seeded randomness,
    scripted input, and framebuffer/state golden.
  - Gate: `make check` and the asteroids smoke are green.

- [ ] **7e: Pong**
  - Deliverables: deterministic pong example with scripted input and
    framebuffer/state golden.
  - Gate: `make check` and the pong smoke are green.

- [ ] **7f: CLI app polish**
  - Deliverables: final CLI example coverage and `make examples` aggregation
    cleanup.
  - Gate: `make check` and `make examples` are green.

## Open Questions

- Wave 6d (audio stub) is still open. It does not block Phase 7; the supervisor
  may schedule it between 7a and 7b or defer further.
- The final app list in Phase 7 is fixed here to match `docs/ROADMAP.md`.
  Later additions should be appended after 7f, not inserted into this ladder.
