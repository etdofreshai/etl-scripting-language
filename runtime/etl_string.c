#include "etl_string.h"
#include <stdlib.h>
#include <string.h>

EtlString *str_new(void *literal_v) {
    if (!literal_v) return NULL;
    const int8_t *literal = (const int8_t *)literal_v;
    int32_t len = 0;
    while (literal[len] != 0) { len = len + 1; }
    EtlString *s = (EtlString *)malloc(sizeof(EtlString));
    if (!s) return NULL;
    s->buf = (int8_t *)malloc((size_t)(len + 1));
    if (!s->buf) { free(s); return NULL; }
    for (int32_t i = 0; i < len; i = i + 1) { s->buf[i] = literal[i]; }
    s->buf[len] = 0;
    s->len = len;
    return s;
}

int32_t str_len(EtlString *s) {
    if (!s) return 0;
    return s->len;
}

EtlString *str_concat(EtlString *a, EtlString *b) {
    if (!a || !b) return NULL;
    int32_t total = a->len + b->len;
    EtlString *s = (EtlString *)malloc(sizeof(EtlString));
    if (!s) return NULL;
    s->buf = (int8_t *)malloc((size_t)(total + 1));
    if (!s->buf) { free(s); return NULL; }
    for (int32_t i = 0; i < a->len; i = i + 1) { s->buf[i] = a->buf[i]; }
    for (int32_t i = 0; i < b->len; i = i + 1) { s->buf[a->len + i] = b->buf[i]; }
    s->buf[total] = 0;
    s->len = total;
    return s;
}

int str_at(EtlString *s, int32_t i) {
    if (!s || i < 0 || i >= s->len) return 0;
    return (int)s->buf[i];
}

int32_t str_eq(EtlString *a, EtlString *b) {
    if (!a || !b) return 0;
    if (a->len != b->len) return 0;
    for (int32_t i = 0; i < a->len; i = i + 1) {
        if (a->buf[i] != b->buf[i]) return 0;
    }
    return 1;
}

void str_free(EtlString *s) {
    if (!s) return;
    free(s->buf);
    free(s);
}
