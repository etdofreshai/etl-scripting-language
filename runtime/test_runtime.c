#include "etl_runtime.h"

#include <stdint.h>
#include <stdio.h>

static int expect_i32(const char *name, int32_t got, int32_t want) {
  if (got != want) {
    fprintf(stderr, "%s: got %d, want %d\n", name, got, want);
    return 1;
  }
  return 0;
}

int main(void) {
  int failures = 0;
  const int8_t abc[] = { 'a', 'b', 'c', 0 };
  const int8_t abc2[] = { 'a', 'b', 'c', 0 };
  const int8_t abd[] = { 'a', 'b', 'd', 0 };
  int8_t dst[] = { 0, 0, 0, 0 };

  failures += expect_i32("equal same", etl_bytes_equal(abc, 3, abc2, 3), 0);
  failures += expect_i32("equal different length", etl_bytes_equal(abc, 3, abc2, 2), -1);
  failures += expect_i32("equal different content", etl_bytes_equal(abc, 3, abd, 3) == 0, 0);

  etl_bytes_copy(dst, abc, 3);
  failures += expect_i32("copy content", etl_bytes_equal(dst, 3, abc, 3), 0);

  failures += expect_i32("find first", etl_bytes_find(abc, 3, 'a'), 0);
  failures += expect_i32("find middle", etl_bytes_find(abc, 3, 'b'), 1);
  failures += expect_i32("find missing", etl_bytes_find(abc, 3, 'z'), -1);

  if (failures != 0) {
    return 1;
  }
  puts("runtime-test: ok");
  return 0;
}
