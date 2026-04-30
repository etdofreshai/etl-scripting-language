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
