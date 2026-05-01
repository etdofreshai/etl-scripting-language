#include "etl_graphics.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Pure-C software framebuffer backend.
   This implements the same extern API as the SDL3 backend without any display,
   GPU, window-system, or third-party library dependency. Pixels are RGB24. */

static uint8_t *g_pixels = NULL;
static int32_t g_width = 0;
static int32_t g_height = 0;
static size_t g_size = 0;

static int valid_color(int32_t value) {
  return value >= 0 && value <= 255;
}

static uint8_t *pixel_at(int32_t x, int32_t y) {
  return g_pixels + ((size_t)y * (size_t)g_width + (size_t)x) * 3u;
}

int32_t etl_gfx_create(int32_t width, int32_t height) {
  size_t pixels;
  size_t bytes;

  if (width <= 0 || height <= 0) return -1;
  if (width > INT_MAX / height) return -1;

  pixels = (size_t)width * (size_t)height;
  if (pixels > SIZE_MAX / 3u) return -1;
  bytes = pixels * 3u;

  if (g_pixels != NULL) etl_gfx_destroy();

  g_pixels = (uint8_t *)calloc(bytes, 1u);
  if (g_pixels == NULL) return -1;

  g_width = width;
  g_height = height;
  g_size = bytes;
  return 0;
}

void etl_gfx_destroy(void) {
  free(g_pixels);
  g_pixels = NULL;
  g_width = 0;
  g_height = 0;
  g_size = 0;
}

int32_t etl_gfx_clear(int32_t r, int32_t g, int32_t b) {
  int32_t x;
  int32_t y;

  if (g_pixels == NULL) return -1;
  if (!valid_color(r) || !valid_color(g) || !valid_color(b)) return -1;

  for (y = 0; y < g_height; y++) {
    for (x = 0; x < g_width; x++) {
      uint8_t *px = pixel_at(x, y);
      px[0] = (uint8_t)r;
      px[1] = (uint8_t)g;
      px[2] = (uint8_t)b;
    }
  }
  return 0;
}

int32_t etl_gfx_set_pixel(int32_t x, int32_t y,
                          int32_t r, int32_t g, int32_t b) {
  uint8_t *px;

  if (g_pixels == NULL) return -1;
  if (x < 0 || x >= g_width || y < 0 || y >= g_height) return -1;
  if (!valid_color(r) || !valid_color(g) || !valid_color(b)) return -1;

  px = pixel_at(x, y);
  px[0] = (uint8_t)r;
  px[1] = (uint8_t)g;
  px[2] = (uint8_t)b;
  return 0;
}

int32_t etl_gfx_write_ppm(const int8_t *path) {
  FILE *f;
  int ok;
  int close_ok;

  if (g_pixels == NULL || path == NULL) return -1;

  f = fopen((const char *)path, "wb");
  if (f == NULL) return -1;

  ok = fprintf(f, "P6\n%d %d\n255\n", g_width, g_height) > 0;
  ok = ok && fwrite(g_pixels, 1u, g_size, f) == g_size;
  close_ok = fclose(f) == 0;
  ok = ok && close_ok;

  return ok ? 0 : -1;
}

int32_t etl_gfx_get_pixel(int32_t x, int32_t y) {
  uint8_t *px;

  if (g_pixels == NULL) return -1;
  if (x < 0 || x >= g_width || y < 0 || y >= g_height) return -1;

  px = pixel_at(x, y);
  return (int32_t)((uint32_t)px[0] << 16 |
                   (uint32_t)px[1] << 8 |
                   (uint32_t)px[2]);
}
