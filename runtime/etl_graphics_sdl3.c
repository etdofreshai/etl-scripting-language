#include "etl_graphics.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* SDL3 headless renderer: creates an offscreen surface, renders pixels,
   and writes PPM artifacts. No window or display required. */

#include <SDL3/SDL.h>

static SDL_Surface *g_surface = NULL;
static int32_t g_width = 0;
static int32_t g_height = 0;

int32_t etl_gfx_create(int32_t width, int32_t height) {
  if (width <= 0 || height <= 0) return -1;
  if (g_surface != NULL) etl_gfx_destroy();

  if (!SDL_Init(SDL_INIT_VIDEO)) return -1;

  g_surface = SDL_CreateSurface(width, height, SDL_PIXELFORMAT_RGB24);
  if (g_surface == NULL) {
    SDL_Quit();
    return -1;
  }
  g_width = width;
  g_height = height;

  /* Start black. */
  memset(g_surface->pixels, 0, (size_t)(width * height * 3));
  return 0;
}

void etl_gfx_destroy(void) {
  if (g_surface != NULL) {
    SDL_DestroySurface(g_surface);
    g_surface = NULL;
  }
  SDL_Quit();
  g_width = 0;
  g_height = 0;
}

int32_t etl_gfx_clear(int32_t r, int32_t g, int32_t b) {
  if (g_surface == NULL) return -1;
  for (int32_t i = 0; i < g_width * g_height; i++) {
    uint8_t *px = (uint8_t *)g_surface->pixels + i * 3;
    px[0] = (uint8_t)r;
    px[1] = (uint8_t)g;
    px[2] = (uint8_t)b;
  }
  return 0;
}

int32_t etl_gfx_set_pixel(int32_t x, int32_t y,
                          int32_t r, int32_t g, int32_t b) {
  if (g_surface == NULL) return -1;
  if (x < 0 || x >= g_width || y < 0 || y >= g_height) return -1;
  uint8_t *px = (uint8_t *)g_surface->pixels + (y * g_width + x) * 3;
  px[0] = (uint8_t)r;
  px[1] = (uint8_t)g;
  px[2] = (uint8_t)b;
  return 0;
}

int32_t etl_gfx_write_ppm(const int8_t *path) {
  if (g_surface == NULL || path == NULL) return -1;
  FILE *f = fopen((const char *)path, "wb");
  if (f == NULL) return -1;

  fprintf(f, "P6\n%d %d\n255\n", g_width, g_height);
  fwrite(g_surface->pixels, 1, (size_t)(g_width * g_height * 3), f);
  fclose(f);
  return 0;
}

int32_t etl_gfx_get_pixel(int32_t x, int32_t y) {
  if (g_surface == NULL) return -1;
  if (x < 0 || x >= g_width || y < 0 || y >= g_height) return -1;
  uint8_t *px = (uint8_t *)g_surface->pixels + (y * g_width + x) * 3;
  return (int32_t)((uint32_t)px[0] << 16 | (uint32_t)px[1] << 8 | (uint32_t)px[2]);
}
