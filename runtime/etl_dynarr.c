#include "etl_dynarr.h"
#include <stdlib.h>

#define ETL_DYNARR_INIT_CAP 4

EtlDynArr *dynarr_new(void) {
    EtlDynArr *a = (EtlDynArr *)malloc(sizeof(EtlDynArr));
    if (!a) return NULL;
    a->buf = (int32_t *)malloc((size_t)ETL_DYNARR_INIT_CAP * sizeof(int32_t));
    if (!a->buf) { free(a); return NULL; }
    a->len = 0;
    a->cap = ETL_DYNARR_INIT_CAP;
    return a;
}

void dynarr_push(EtlDynArr *a, int32_t v) {
    if (!a) return;
    if (a->len >= a->cap) {
        int32_t new_cap = a->cap * 2;
        int32_t *new_buf = (int32_t *)malloc((size_t)new_cap * sizeof(int32_t));
        if (!new_buf) return;
        for (int32_t i = 0; i < a->len; i = i + 1) { new_buf[i] = a->buf[i]; }
        free(a->buf);
        a->buf = new_buf;
        a->cap = new_cap;
    }
    a->buf[a->len] = v;
    a->len = a->len + 1;
}

int32_t dynarr_len(EtlDynArr *a) {
    if (!a) return 0;
    return a->len;
}

int32_t dynarr_get(EtlDynArr *a, int32_t i) {
    if (!a || i < 0 || i >= a->len) return 0;
    return a->buf[i];
}

void dynarr_set(EtlDynArr *a, int32_t i, int32_t v) {
    if (!a || i < 0 || i >= a->len) return;
    a->buf[i] = v;
}

void dynarr_free(EtlDynArr *a) {
    if (!a) return;
    free(a->buf);
    free(a);
}
