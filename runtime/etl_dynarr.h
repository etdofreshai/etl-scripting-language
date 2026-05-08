#ifndef ETL_DYNARR_H
#define ETL_DYNARR_H

#include <stdint.h>

/*
 * EtlDynArr: growable i32 array for the ETL runtime.
 * Capacity doubles on each reallocation.
 */
typedef struct {
    int32_t *buf;   /* heap-allocated element buffer */
    int32_t  len;   /* number of elements in use */
    int32_t  cap;   /* allocated capacity in elements */
} EtlDynArr;

/* Create a new empty EtlDynArr with initial capacity 4.
 * Returns NULL on allocation failure. */
EtlDynArr *dynarr_new(void);

/* Append v to a. Grows the buffer (doubling) as needed.
 * No-op on NULL a. */
void dynarr_push(EtlDynArr *a, int32_t v);

/* Return the number of elements in a. Returns 0 for NULL. */
int32_t dynarr_len(EtlDynArr *a);

/* Return the element at index i (0-based). Returns 0 for NULL or out-of-range. */
int32_t dynarr_get(EtlDynArr *a, int32_t i);

/* Set element at index i to v. No-op for NULL or out-of-range. */
void dynarr_set(EtlDynArr *a, int32_t i, int32_t v);

/* Free the array and its buffer. */
void dynarr_free(EtlDynArr *a);

#endif /* ETL_DYNARR_H */
