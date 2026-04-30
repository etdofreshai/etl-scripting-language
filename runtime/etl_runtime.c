#include "etl_runtime.h"

#include <stdio.h>
#include <stdlib.h>

void etl_print_i32(int32_t value) {
  printf("%d\n", value);
}

void etl_print_bool(bool value) {
  fputs(value ? "true\n" : "false\n", stdout);
}

void etl_print_str(const int8_t *s) {
  if (s == NULL) {
    return;
  }
  fputs((const char *)s, stdout);
}

void etl_print_str_n(const int8_t *s, int32_t n) {
  if (s == NULL || n <= 0) {
    return;
  }
  fwrite(s, 1, (size_t)n, stdout);
}

void etl_exit(int32_t code) {
  exit(code);
}

int32_t etl_read_i32(void) {
  char buf[64];
  if (fgets(buf, sizeof(buf), stdin) == NULL) {
    return -1;
  }
  return (int32_t)atoi(buf);
}

int8_t *etl_alloc(int32_t bytes) {
  if (bytes <= 0) {
    return NULL;
  }
  return (int8_t *)calloc((size_t)bytes, 1);
}

void etl_free(int8_t *p) {
  free(p);
}

bool etl_is_null(int8_t *p) {
  return p == NULL;
}

int32_t etl_read_file(int8_t *path, int8_t *buf, int32_t cap) {
  if (path == NULL || buf == NULL || cap < 0) {
    return -1;
  }
  FILE *f = fopen((const char *)path, "rb");
  if (f == NULL) {
    return -1;
  }
  size_t n = fread(buf, 1, (size_t)cap, f);
  if (ferror(f)) {
    fclose(f);
    return -1;
  }
  if (fclose(f) != 0) {
    return -1;
  }
  return (int32_t)n;
}

int32_t etl_write_file(int8_t *path, int8_t *buf, int32_t len) {
  if (path == NULL || buf == NULL || len < 0) {
    return -1;
  }
  FILE *f = fopen((const char *)path, "wb");
  if (f == NULL) {
    return -1;
  }
  size_t written = fwrite(buf, 1, (size_t)len, f);
  if (written != (size_t)len || ferror(f)) {
    fclose(f);
    return -1;
  }
  if (fclose(f) != 0) {
    return -1;
  }
  return 0;
}

void etl_panic(int8_t *msg) {
  if (msg == NULL) {
    fputs("panic\n", stderr);
  } else {
    fprintf(stderr, "panic: %s\n", (const char *)msg);
  }
  exit(1);
}
