#include <stdint.h>

int32_t add(int32_t a, int32_t b);
int32_t main(void);

int32_t add(int32_t a, int32_t b) {
  return (a + b);
}

int32_t main(void) {
  int32_t x = add(2, 3);
  return x;
}
