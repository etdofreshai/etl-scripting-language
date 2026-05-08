# ETL L5 Validation Contract

This file is the source of truth for what each milestone must prove before
being considered done. Validators run against this contract; findings are
recorded here and resolved by cleanup features.

---

## M4 — SDL3 Visual Runtime

### VAL-SDL3-001: SDL3 fetched and built locally

**Criterion:** `.deps/sdl3/include/SDL3/SDL.h` exists after `scripts/setup.sh`
runs; `scripts/setup.sh` is idempotent.

**Evidence:**
- `scripts/setup.sh` implements `fetch_sdl3()` and `verify_sdl3()`.
- SDL3 release-3.4.8 confirmed via probe binary: `SDL3 version: 3.4.8`.
- `.deps/` is gitignored (`git check-ignore .deps/sdl3` → exit 0).

**Status:** PASS (F4.1-fetch-sdl3)

---

### VAL-SDL3-002: Deterministic tick demo compiles and runs

**Criterion:** `examples/visual/tick_demo.etl` compiles through compiler-0,
links the software graphics backend, and exits 0 with deterministic output.

**Evidence:**
- `make visual` passes; `scripts/visual_smoke.sh` covers `tick_demo`.
- `scripts/software_graphics_smoke.sh` validates pixel output.

**Status:** PASS (F4.2-tick-demo-deterministic)

---

### VAL-SDL3-003: SDL3 visual sample with bouncing-rect golden frame

**Criterion:** `examples/visual/bouncing_rect.etl` (or equivalent) compiles,
links the SDL3 offscreen backend, renders one frame, and byte-matches a
committed PPM golden.

**Evidence:**
- `examples/visual/bouncing_rect.etl` and `examples/visual/bouncing_rect.golden.ppm` committed.
- `scripts/visual_smoke.sh` runs the SDL3 live smoke from `.deps/sdl3/` (no SKIP).
- `make visual` is green.

**Status:** PASS (F4.3-sdl3-visual-sample)

---

### VAL-SDL3-004: Phase 6 wave completion — scripted input and Life golden

**Criterion:** waves 6c (scripted input) and 6e (Life golden) are complete.
Wave 6d (deterministic audio runtime stub) is intentionally deferred — out of
mission scope per non-goals (no broad runtime/ABI work beyond next narrow
milestone). `make check` and `make visual` are both green.

**Evidence:**
- Wave 6c: `runtime/etl_input.h`, `runtime/etl_input.c`,
  `examples/visual/scripted_input.etl`, `examples/visual/scripted_input.events`,
  `examples/visual/scripted_input.expected`, `scripts/scripted_input_smoke.sh`
  — all committed; `make visual` covers the scripted-input smoke. (Completed in
  F0.1 / earlier waves; wave number corrected from prior erroneous reference to
  "6d" in the original contract draft.)
- Wave 6e: `examples/visual/life.etl`, `examples/visual/life.golden.ppm`,
  `scripts/life_golden_smoke.sh` committed; wired into `scripts/visual_smoke.sh`
  and `make visual`. Conway's Life runs 10 generations on a 32x32 blinker seed
  and byte-matches the golden PPM.
- Wave 6d (audio stub) remains open; deferred by supervisor reorder. Does not
  block Phase 7 per `docs/PATH_TO_APPS.md`.
- `make check`: 0, `make visual`: 0.

**Status:** PASS (F4.4-phase6-complete) — wave numbering corrected by F4.1.1

---

## Contract maintenance

Cleanup features that only correct documentation must still run `make check`
before merging. They do not need to re-run visual smokes unless they touch
scripts or runtime files.
