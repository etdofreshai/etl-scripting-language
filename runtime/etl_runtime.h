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
int8_t *etl_alloc(int32_t bytes);
void etl_free(int8_t *p);
bool etl_is_null(int8_t *p);
int32_t etl_read_file(int8_t *path, int8_t *buf, int32_t cap);
int32_t etl_write_file(int8_t *path, int8_t *buf, int32_t len);
void etl_panic(int8_t *msg);

#endif
