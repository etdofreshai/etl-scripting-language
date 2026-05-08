#ifndef ETL_INPUT_H
#define ETL_INPUT_H

#include <stdint.h>

int32_t etl_input_load_file(int8_t *path);
int32_t etl_input_load_bytes(int8_t *buf, int32_t len);
int32_t etl_input_next(void);
int32_t etl_input_tick(void);
int32_t etl_input_code(void);
int32_t etl_input_down(void);
int32_t etl_input_remaining(void);

#endif
