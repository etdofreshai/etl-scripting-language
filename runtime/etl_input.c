#include "etl_input.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

typedef struct {
  int32_t tick;
  int32_t code;
  int32_t down;
} EtlInputEvent;

static EtlInputEvent g_events[256];
static int32_t g_event_count = 0;
static int32_t g_event_index = 0;
static EtlInputEvent g_current = {0, 0, 0};

static void reset_events(void) {
  g_event_count = 0;
  g_event_index = 0;
  g_current.tick = 0;
  g_current.code = 0;
  g_current.down = 0;
}

static int parse_script(const char *src, int32_t len) {
  const char *p = src;
  const char *end = src + len;

  reset_events();
  while (p < end) {
    while (p < end && isspace((unsigned char)*p)) {
      p++;
    }
    if (p >= end) {
      break;
    }
    if (*p == '#') {
      while (p < end && *p != '\n') {
        p++;
      }
      continue;
    }
    if (g_event_count >= (int32_t)(sizeof(g_events) / sizeof(g_events[0]))) {
      reset_events();
      return -1;
    }

    int tick = 0;
    int code = 0;
    int down = 0;
    int consumed = 0;
    if (sscanf(p, "%d %d %d%n", &tick, &code, &down, &consumed) != 3) {
      reset_events();
      return -1;
    }
    if (tick < 0 || code < 0 || down < 0 || down > 1) {
      reset_events();
      return -1;
    }
    p += consumed;
    while (p < end && *p != '\n') {
      if (!isspace((unsigned char)*p)) {
        reset_events();
        return -1;
      }
      p++;
    }

    g_events[g_event_count].tick = (int32_t)tick;
    g_events[g_event_count].code = (int32_t)code;
    g_events[g_event_count].down = (int32_t)down;
    g_event_count++;
  }

  return g_event_count;
}

int32_t etl_input_load_file(int8_t *path) {
  if (path == NULL) {
    return -1;
  }

  FILE *f = fopen((const char *)path, "rb");
  if (f == NULL) {
    return -1;
  }

  char buf[8192];
  size_t n = fread(buf, 1, sizeof(buf), f);
  if (ferror(f)) {
    fclose(f);
    return -1;
  }
  if (!feof(f)) {
    fclose(f);
    return -1;
  }
  if (fclose(f) != 0) {
    return -1;
  }

  return parse_script(buf, (int32_t)n);
}

int32_t etl_input_load_bytes(int8_t *buf, int32_t len) {
  if (buf == NULL || len < 0) {
    return -1;
  }
  return parse_script((const char *)buf, len);
}

int32_t etl_input_next(void) {
  if (g_event_index >= g_event_count) {
    return 0;
  }
  g_current = g_events[g_event_index];
  g_event_index++;
  return 1;
}

int32_t etl_input_tick(void) {
  return g_current.tick;
}

int32_t etl_input_code(void) {
  return g_current.code;
}

int32_t etl_input_down(void) {
  return g_current.down;
}

int32_t etl_input_remaining(void) {
  return g_event_count - g_event_index;
}
