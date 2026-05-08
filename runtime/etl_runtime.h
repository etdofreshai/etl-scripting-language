#ifndef ETL_RUNTIME_H
#define ETL_RUNTIME_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

void etl_print_i32(int32_t value);
void etl_print_bool(bool value);
void etl_print_str(const int8_t *s);
void etl_print_str_n(const int8_t *s, int32_t n);
int32_t etl_format_i32(int8_t *buf, int32_t cap, int32_t value);
int32_t etl_append_bytes(int8_t *dst, int32_t dst_len, int32_t dst_cap,
                         const int8_t *src, int32_t src_len);
void etl_eprint(int8_t *buf, int32_t len);
void etl_eprint_i32(int32_t value);
void etl_exit(int32_t code);
int32_t etl_read_i32(void);
int32_t etl_read_byte(void);
int32_t etl_write_byte(int32_t b);
int32_t etl_read_stdin(int8_t *buf, int32_t cap);
int8_t *etl_alloc(int32_t bytes);
void etl_free(int8_t *p);
bool etl_is_null(int8_t *p);
int32_t etl_read_file(int8_t *path, int8_t *buf, int32_t cap);
int32_t etl_write_file(int8_t *path, int8_t *buf, int32_t len);
int32_t etl_write_file1024(int8_t *path, int8_t *buf, int32_t len);
int32_t etl_bytes_equal(const int8_t *a, int32_t alen, const int8_t *b, int32_t blen);
void etl_bytes_copy(int8_t *dst, const int8_t *src, int32_t len);
int32_t etl_bytes_find(const int8_t *buf, int32_t len, int32_t b);
void etl_panic(int8_t *msg);

#endif
