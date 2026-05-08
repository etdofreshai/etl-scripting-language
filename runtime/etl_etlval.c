#include "etl_etlval.h"
#include <stdlib.h>

EtlVal *etlval_int(int32_t i) {
    EtlVal *v = (EtlVal *)malloc(sizeof(EtlVal));
    if (!v) return NULL;
    v->tag = ETLVAL_TAG_INT;
    v->payload.as_int = i;
    return v;
}

EtlVal *etlval_bool(int32_t b) {
    EtlVal *v = (EtlVal *)malloc(sizeof(EtlVal));
    if (!v) return NULL;
    v->tag = ETLVAL_TAG_BOOL;
    v->payload.as_bool = (b != 0) ? 1 : 0;
    return v;
}

EtlVal *etlval_ptr(void *p) {
    EtlVal *v = (EtlVal *)malloc(sizeof(EtlVal));
    if (!v) return NULL;
    v->tag = ETLVAL_TAG_PTR;
    v->payload.as_ptr = p;
    return v;
}

EtlVal *etlval_str(EtlString *s) {
    EtlVal *v = (EtlVal *)malloc(sizeof(EtlVal));
    if (!v) return NULL;
    v->tag = ETLVAL_TAG_STR;
    v->payload.as_str = s;
    return v;
}

int32_t etlval_tag(EtlVal *v) {
    if (!v) return -1;
    return v->tag;
}

int32_t etlval_as_int(EtlVal *v) {
    if (!v || v->tag != ETLVAL_TAG_INT) return 0;
    return v->payload.as_int;
}

int32_t etlval_as_bool(EtlVal *v) {
    if (!v || v->tag != ETLVAL_TAG_BOOL) return 0;
    return v->payload.as_bool;
}

void *etlval_as_ptr(EtlVal *v) {
    if (!v || v->tag != ETLVAL_TAG_PTR) return NULL;
    return v->payload.as_ptr;
}

EtlString *etlval_as_str(EtlVal *v) {
    if (!v || v->tag != ETLVAL_TAG_STR) return NULL;
    return v->payload.as_str;
}

void etlval_free(EtlVal *v) {
    if (!v) return;
    if (v->tag == ETLVAL_TAG_STR && v->payload.as_str != NULL) {
        str_free(v->payload.as_str);
    }
    free(v);
}
