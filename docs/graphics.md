# Headless Graphics (SDL3)

## Overview

The graphics bridge allows ETL programs to render deterministic pixel output
on headless servers via SDL3. It compiles ETL through compiler-0 to C, links
with SDL3, and runs without any window or display.

## Current status

SDL3 is **optional**. The `make graphics-headless` target detects SDL3 via
`pkg-config sdl3`. If SDL3 is not installed, the target prints a skip notice
and exits 0 — it never fails CI.

### Enabling SDL3

Install SDL3 development headers and libraries for your platform, then verify:

    pkg-config --modversion sdl3

### Running

    make graphics-headless

This compiles `examples/graphics/pixel_fill.etl`, renders an 8x8 offscreen
image, writes a PPM artifact, and validates expected pixel values.

## Runtime API

All functions live in `runtime/etl_graphics.h` and are exposed as `extern fn`
in ETL programs. The SDL3 implementation is in `runtime/etl_graphics_sdl3.c`.

| Function | Signature | Description |
|---|---|---|
| `etl_gfx_create` | `(width, height) i32` | Create offscreen surface |
| `etl_gfx_destroy` | `()` | Free surface and SDL |
| `etl_gfx_clear` | `(r, g, b) i32` | Fill with solid color |
| `etl_gfx_set_pixel` | `(x, y, r, g, b) i32` | Set one pixel |
| `etl_gfx_get_pixel` | `(x, y) i32` | Read pixel as 0x00RRGGBB |
| `etl_gfx_write_ppm` | `(path) i32` | Write framebuffer to PPM |

## Artifact structure

When SDL3 is available, rendered images are written under `build/graphics/`:

    build/graphics/
      pixel_fill.ppm        # 8x8 PPM test image

## Future screenshot contract

When the full graphics pipeline is wired into the self-evaluation harness,
each self-eval graphics program will produce:

| Artifact | Path pattern | Description |
|---|---|---|
| Tick log | `build/selfeval/<program>/<tick>.txt` | Per-tick numeric state |
| PPM screenshot | `build/selfeval/<program>/<tick>.ppm` | Rendered frame at that tick |
| Pixel hash | `build/selfeval/<program>/<tick>.sha256` | SHA-256 of raw framebuffer bytes |

### Verification flow

1. Compile ETL program to C via compiler-0 (or compiler-1).
2. Link with `etl_runtime.c` + `etl_graphics_sdl3.c` + SDL3.
3. Run headlessly; program emits tick logs to stdout and writes PPM per tick.
4. Harness compares stdout against golden `.expected` file.
5. Harness computes SHA-256 of each PPM and compares against `.sha256` sidecar.
6. Determinism check: run twice, require identical stdout and pixel hashes.

### Portability notes

- PPM is used now for simplicity; PNG can be added when libpng or stb_image_write
  is available.
- The API surface is SDL3-agnostic. A stub backend or WASM/Canvas backend can
  implement the same `etl_graphics.h` functions without SDL3.
- No window, no GPU, no display server required — pure offscreen rendering.
