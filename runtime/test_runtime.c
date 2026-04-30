#include "etl_runtime.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>

static int expect_i32(const char *name, int32_t got, int32_t want) {
  if (got != want) {
    fprintf(stderr, "%s: got %d, want %d\n", name, got, want);
    return 1;
  }
  return 0;
}

static int expect_bytes(const char *name, const int8_t *got, const char *want, int32_t len) {
  for (int32_t i = 0; i < len; i++) {
    if (got[i] != (int8_t)want[i]) {
      fprintf(stderr, "%s: byte %d got %d, want %d\n", name, i, got[i], (int8_t)want[i]);
      return 1;
    }
  }
  return 0;
}

int main(void) {
  int failures = 0;
  const int8_t abc[] = { 'a', 'b', 'c', 0 };
  const int8_t abc2[] = { 'a', 'b', 'c', 0 };
  const int8_t abd[] = { 'a', 'b', 'd', 0 };
  int8_t dst[] = { 0, 0, 0, 0 };
  int8_t fmt[16] = { 0 };
  int8_t append_dst[8] = { 'a', 'b', 0, 0, 0, 0, 0, 0 };
  const int8_t cd[] = { 'c', 'd' };

  failures += expect_i32("equal same", etl_bytes_equal(abc, 3, abc2, 3), 0);
  failures += expect_i32("equal different length", etl_bytes_equal(abc, 3, abc2, 2), -1);
  failures += expect_i32("equal different content", etl_bytes_equal(abc, 3, abd, 3) == 0, 0);

  etl_bytes_copy(dst, abc, 3);
  failures += expect_i32("copy content", etl_bytes_equal(dst, 3, abc, 3), 0);

  failures += expect_i32("find first", etl_bytes_find(abc, 3, 'a'), 0);
  failures += expect_i32("find middle", etl_bytes_find(abc, 3, 'b'), 1);
  failures += expect_i32("find missing", etl_bytes_find(abc, 3, 'z'), -1);

  failures += expect_i32("format positive len", etl_format_i32(fmt, 16, 12345), 5);
  failures += expect_bytes("format positive bytes", fmt, "12345", 5);
  failures += expect_i32("format negative len", etl_format_i32(fmt, 16, -987), 4);
  failures += expect_bytes("format negative bytes", fmt, "-987", 4);
  failures += expect_i32("format zero len", etl_format_i32(fmt, 16, 0), 1);
  failures += expect_bytes("format zero bytes", fmt, "0", 1);
  failures += expect_i32("format min len", etl_format_i32(fmt, 16, INT32_MIN), 11);
  failures += expect_bytes("format min bytes", fmt, "-2147483648", 11);
  fmt[0] = 'x';
  failures += expect_i32("format overflow", etl_format_i32(fmt, 2, 123), -1);
  failures += expect_i32("format overflow untouched", fmt[0], 'x');

  failures += expect_i32("append success len", etl_append_bytes(append_dst, 2, 8, cd, 2), 4);
  failures += expect_bytes("append success bytes", append_dst, "abcd", 4);
  failures += expect_i32("append overflow", etl_append_bytes(append_dst, 7, 8, cd, 2), -1);

  if (failures != 0) {
    return 1;
  }
  puts("runtime-test: ok");
  return 0;
}
