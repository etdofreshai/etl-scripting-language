#ifndef ETL_ETLVAL_H
#define ETL_ETLVAL_H

#include <stdint.h>
#include "etl_string.h"

/*
 * EtlVal: tagged-union for ETL VM values.
 * Tag constants: 0=int, 1=bool, 2=ptr, 3=str
 * The str variant stores an EtlString *; caller must not free the inner string
 * independently — etlval_free handles it.
 */
#define ETLVAL_TAG_INT  0
#define ETLVAL_TAG_BOOL 1
#define ETLVAL_TAG_PTR  2
#define ETLVAL_TAG_STR  3

typedef struct {
    int32_t tag;
    union {
        int32_t    as_int;
        int32_t    as_bool;
        void      *as_ptr;
        EtlString *as_str;
    } payload;
} EtlVal;

/* Constructors — each allocates an EtlVal on the heap. */
EtlVal *etlval_int(int32_t i);
EtlVal *etlval_bool(int32_t b);
EtlVal *etlval_ptr(void *p);
EtlVal *etlval_str(EtlString *s);

/* Return the tag (0/1/2/3). Returns -1 for NULL. */
int32_t etlval_tag(EtlVal *v);

/* Payload getters — return 0/NULL on type mismatch or NULL v. */
int32_t    etlval_as_int(EtlVal *v);
int32_t    etlval_as_bool(EtlVal *v);
void      *etlval_as_ptr(EtlVal *v);
EtlString *etlval_as_str(EtlVal *v);

/* Free the EtlVal and (for str variant) its embedded EtlString. */
void etlval_free(EtlVal *v);

#endif /* ETL_ETLVAL_H */
