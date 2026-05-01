# Headless Graphics

## Overview

The graphics bridge allows ETL programs to render deterministic pixel output
on headless servers. It compiles ETL through compiler-0 to C and links one
implementation of the `runtime/etl_graphics.h` extern API.

## Current status

Two backends are available:

| Backend | Runtime file | Dependency | Target |
|---|---|---|---|
| Software framebuffer | `runtime/etl_graphics_software.c` | C standard library only | `make graphics-software` |
| SDL3 offscreen surface | `runtime/etl_graphics_sdl3.c` | SDL3 via `pkg-config sdl3` | `make graphics-headless` |

The software framebuffer is the portable fallback and is part of
`make selfeval-all` and `make headless-ready`. SDL3 remains **optional**. The
`make graphics-headless` target detects SDL3; if it is not installed, the
target prints a skip notice and exits 0.

### Software fallback contract

The software backend:

- Requires no window, GPU, display server, SDL, or third-party library.
- Stores pixels as deterministic RGB24 bytes.
- Writes binary PPM (`P6`) artifacts.
- Returns packed pixels as `0x00RRGGBB` from `etl_gfx_get_pixel`.
- Treats invalid dimensions, coordinates, colors outside `0..255`, missing
  framebuffers, and failed writes as negative return values.

Run it with:

    make graphics-software

This compiles `examples/graphics/software_framebuffer.etl`, renders a 4x4
image, writes `build/graphics/software_framebuffer.ppm`, verifies selected
pixel values, and compares the PPM SHA-256 checksum.

### Enabling SDL3

Install SDL3 development headers and libraries for your platform, then verify:

    pkg-config --modversion sdl3

### Running

    make graphics-headless

This compiles `examples/graphics/pixel_fill.etl`, renders an 8x8 offscreen
image, writes a PPM artifact, and validates expected pixel values.

## Runtime API

All functions live in `runtime/etl_graphics.h` and are exposed as `extern fn`
in ETL programs. Link exactly one graphics backend into a program.

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
      software_framebuffer.ppm # 4x4 software framebuffer smoke image
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
2. Link with `etl_runtime.c` plus one graphics backend.
3. Run headlessly; program emits tick logs to stdout and writes PPM per tick.
4. Harness compares stdout against golden `.expected` file.
5. Harness computes SHA-256 of each PPM and compares against `.sha256` sidecar.
6. Determinism check: run twice, require identical stdout and pixel hashes.

The combined `make selfeval-all` target runs headless selfeval, the software
graphics smoke, and the skip-safe SDL3 smoke in a single pass. See
`docs/selfeval.md` for the full combined contract.

### Portability notes

- PPM is used now for simplicity; PNG can be added when libpng or stb_image_write
  is available.
- The API surface is SDL3-agnostic. The software backend is the default
  portable implementation; a WASM/Canvas backend can implement the same
  `etl_graphics.h` functions later.
- No window, no GPU, no display server required — pure offscreen rendering.
