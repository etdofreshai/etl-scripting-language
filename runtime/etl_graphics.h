#ifndef ETL_GRAPHICS_H
#define ETL_GRAPHICS_H

#include <stdint.h>

/* Minimal headless graphics API for ETL programs.
   Implemented by etl_graphics_sdl3.c (or a future stub/wasm backend).
   All functions return 0 on success, negative on error. */

/* Create an offscreen rendering context (width x height, no window). */
int32_t etl_gfx_create(int32_t width, int32_t height);

/* Destroy the offscreen context and free resources. */
void etl_gfx_destroy(void);

/* Fill the entire surface with a solid color (r, g, b in 0..255). */
int32_t etl_gfx_clear(int32_t r, int32_t g, int32_t b);

/* Set a single pixel at (x, y) to color (r, g, b). */
int32_t etl_gfx_set_pixel(int32_t x, int32_t y,
                          int32_t r, int32_t g, int32_t b);

/* Write the current framebuffer to a PPM file at the given path. */
int32_t etl_gfx_write_ppm(const int8_t *path);

/* Read back the pixel at (x, y). Returns packed 0x00RRGGBB, negative on error. */
int32_t etl_gfx_get_pixel(int32_t x, int32_t y);

#endif
