#ifndef ETL_STRING_H
#define ETL_STRING_H

#include <stdint.h>

/*
 * EtlString: heap-backed mutable string for the ETL runtime.
 * Always NUL-terminated internally; len does not include the NUL byte.
 */
typedef struct {
    int8_t  *buf;   /* heap-allocated, NUL-terminated */
    int32_t  len;   /* byte count excluding NUL */
} EtlString;

/* Construct a new EtlString by copying the C string literal at `literal`.
 * The literal may point to read-only data; str_new copies into heap.
 * Returns NULL on allocation failure. */
EtlString *str_new(void *literal);

/* Return the byte length of s (excluding NUL). */
int32_t str_len(EtlString *s);

/* Concatenate a and b into a new EtlString. Caller must str_free the result.
 * Returns NULL on allocation failure. */
EtlString *str_concat(EtlString *a, EtlString *b);

/* Return the byte at index i (0-based). Out-of-range returns 0. */
int str_at(EtlString *s, int32_t i);

/* Return 1 (true) if a and b have equal content, 0 otherwise. */
int32_t str_eq(EtlString *a, EtlString *b);

/* Free the EtlString and its internal buffer. */
void str_free(EtlString *s);

#endif /* ETL_STRING_H */
