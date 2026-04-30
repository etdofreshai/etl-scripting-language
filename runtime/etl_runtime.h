#ifndef ETL_RUNTIME_H
#define ETL_RUNTIME_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

void etl_print_i32(int32_t value);
void etl_print_bool(bool value);
void etl_print_str(const int8_t *s);
void etl_print_str_n(const int8_t *s, int32_t n);
void etl_exit(int32_t code);
int32_t etl_read_i32(void);

#endif
