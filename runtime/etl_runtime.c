#include "etl_runtime.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

void etl_print_i32(int32_t value) {
  printf("%d\n", value);
}

void etl_print_bool(bool value) {
  fputs(value ? "true\n" : "false\n", stdout);
}

void etl_print_str(const int8_t *s) {
  if (s == NULL) {
    return;
  }
  fputs((const char *)s, stdout);
}

void etl_print_str_n(const int8_t *s, int32_t n) {
  if (s == NULL || n <= 0) {
    return;
  }
  fwrite(s, 1, (size_t)n, stdout);
}

int32_t etl_format_i32(int8_t *buf, int32_t cap, int32_t value) {
  char tmp[16];
  int n = snprintf(tmp, sizeof(tmp), "%" PRId32, value);
  if (buf == NULL || cap < 0 || n < 0 || n > cap) {
    return -1;
  }
  memcpy(buf, tmp, (size_t)n);
  return (int32_t)n;
}

int32_t etl_append_bytes(int8_t *dst, int32_t dst_len, int32_t dst_cap,
                         const int8_t *src, int32_t src_len) {
  if (dst == NULL || src == NULL || dst_len < 0 || dst_cap < dst_len || src_len < 0) {
    return -1;
  }
  if (src_len > dst_cap - dst_len) {
    return -1;
  }
  memcpy(dst + dst_len, src, (size_t)src_len);
  return dst_len + src_len;
}

void etl_eprint(int8_t *buf, int32_t len) {
  if (buf == NULL || len <= 0) {
    return;
  }
  fwrite(buf, 1, (size_t)len, stderr);
}

void etl_eprint_i32(int32_t value) {
  int8_t buf[16];
  int32_t n = etl_format_i32(buf, (int32_t)sizeof(buf), value);
  if (n > 0) {
    etl_eprint(buf, n);
  }
}

void etl_exit(int32_t code) {
  exit(code);
}

int32_t etl_read_i32(void) {
  char buf[64];
  if (fgets(buf, sizeof(buf), stdin) == NULL) {
    return -1;
  }
  return (int32_t)atoi(buf);
}

int32_t etl_read_byte(void) {
  int c = fgetc(stdin);
  return c == EOF ? -1 : (int32_t)(unsigned char)c;
}

int32_t etl_write_byte(int32_t b) {
  return fputc((unsigned char)b, stdout) == EOF ? -1 : 0;
}

int32_t etl_read_stdin(int8_t *buf, int32_t cap) {
  if (buf == NULL || cap < 0) {
    return -1;
  }
  size_t n = fread(buf, 1, (size_t)cap, stdin);
  return ferror(stdin) ? -1 : (int32_t)n;
}

int8_t *etl_alloc(int32_t bytes) {
  if (bytes <= 0) {
    return NULL;
  }
  return (int8_t *)calloc((size_t)bytes, 1);
}

void etl_free(int8_t *p) {
  free(p);
}

bool etl_is_null(int8_t *p) {
  return p == NULL;
}

int32_t etl_read_file(int8_t *path, int8_t *buf, int32_t cap) {
  if (path == NULL || buf == NULL || cap < 0) {
    return -1;
  }
  FILE *f = fopen((const char *)path, "rb");
  if (f == NULL) {
    return -1;
  }
  size_t n = fread(buf, 1, (size_t)cap, f);
  if (ferror(f)) {
    fclose(f);
    return -1;
  }
  if (fclose(f) != 0) {
    return -1;
  }
  return (int32_t)n;
}

int32_t etl_write_file(int8_t *path, int8_t *buf, int32_t len) {
  if (path == NULL || buf == NULL || len < 0) {
    return -1;
  }
  FILE *f = fopen((const char *)path, "wb");
  if (f == NULL) {
    return -1;
  }
  size_t written = fwrite(buf, 1, (size_t)len, f);
  if (written != (size_t)len || ferror(f)) {
    fclose(f);
    return -1;
  }
  if (fclose(f) != 0) {
    return -1;
  }
  return 0;
}

int32_t etl_write_file1024(int8_t *path, int8_t *buf, int32_t len) {
  return etl_write_file(path, buf, len);
}

int32_t etl_bytes_equal(const int8_t *a, int32_t alen, const int8_t *b, int32_t blen) {
  if (alen != blen) {
    return -1;
  }
  return memcmp(a, b, (size_t)alen);
}

void etl_bytes_copy(int8_t *dst, const int8_t *src, int32_t len) {
  memcpy(dst, src, (size_t)len);
}

int32_t etl_bytes_find(const int8_t *buf, int32_t len, int32_t b) {
  const int8_t *p = memchr(buf, (unsigned char)b, (size_t)len);
  return p == NULL ? -1 : (int32_t)(p - buf);
}

void etl_panic(int8_t *msg) {
  if (msg == NULL) {
    fputs("panic\n", stderr);
  } else {
    fprintf(stderr, "panic: %s\n", (const char *)msg);
  }
  exit(1);
}

/* --- Calculator REPL helpers --- */

/* etl_read_line: reads one line from stdin into buf (up to cap-1 bytes).
 * Strips the trailing newline.
 * Returns number of bytes stored (0 for empty line), or -1 on EOF/error. */
int32_t etl_read_line(int8_t *buf, int32_t cap) {
  if (buf == NULL || cap <= 0) return -1;
  if (fgets((char *)buf, (int)cap, stdin) == NULL) return -1;
  int32_t n = (int32_t)strlen((char *)buf);
  /* strip trailing newline */
  while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r')) {
    buf[--n] = 0;
  }
  return n;
}

/* Recursive-descent parser state */
typedef struct {
  const char *s;
  int         pos;
  int         len;
  int         err; /* 1 if parse error */
} CalcState;

static void calc_skip_ws(CalcState *st) {
  while (st->pos < st->len && isspace((unsigned char)st->s[st->pos]))
    st->pos++;
}

static int32_t calc_expr(CalcState *st);

static int32_t calc_primary(CalcState *st) {
  calc_skip_ws(st);
  if (st->pos >= st->len) { st->err = 1; return 0; }
  char c = st->s[st->pos];
  if (c == '(') {
    st->pos++;
    int32_t v = calc_expr(st);
    calc_skip_ws(st);
    if (st->pos >= st->len || st->s[st->pos] != ')') { st->err = 1; return 0; }
    st->pos++;
    return v;
  }
  if (c == '-') {
    st->pos++;
    return -calc_primary(st);
  }
  if (isdigit((unsigned char)c)) {
    int32_t v = 0;
    while (st->pos < st->len && isdigit((unsigned char)st->s[st->pos])) {
      v = v * 10 + (st->s[st->pos] - '0');
      st->pos++;
    }
    return v;
  }
  st->err = 1;
  return 0;
}

static int32_t calc_term(CalcState *st) {
  int32_t v = calc_primary(st);
  while (!st->err) {
    calc_skip_ws(st);
    if (st->pos >= st->len) break;
    char op = st->s[st->pos];
    if (op != '*' && op != '/') break;
    st->pos++;
    int32_t r = calc_primary(st);
    if (st->err) break;
    if (op == '*') v = v * r;
    else {
      if (r == 0) { st->err = 1; fputs("error: division by zero\n", stderr); return 0; }
      v = v / r;
    }
  }
  return v;
}

static int32_t calc_expr(CalcState *st) {
  int32_t v = calc_term(st);
  while (!st->err) {
    calc_skip_ws(st);
    if (st->pos >= st->len) break;
    char op = st->s[st->pos];
    if (op != '+' && op != '-') break;
    st->pos++;
    int32_t r = calc_term(st);
    if (st->err) break;
    if (op == '+') v = v + r;
    else           v = v - r;
  }
  return v;
}

/* etl_calc_eval: parses and evaluates the expression in buf[0..len-1].
 * Prints the result to stdout on success.
 * Prints an error message to stderr on failure.
 * Returns 0 on success, -1 on error. */
int32_t etl_calc_eval(int8_t *buf, int32_t len) {
  if (buf == NULL || len < 0) {
    fputs("error: bad input\n", stderr);
    return -1;
  }
  /* skip blank lines */
  int all_ws = 1;
  for (int i = 0; i < len; i++) {
    if (!isspace((unsigned char)((char *)buf)[i])) { all_ws = 0; break; }
  }
  if (all_ws) return 0;
  CalcState st;
  st.s   = (const char *)buf;
  st.pos = 0;
  st.len = (int)len;
  st.err = 0;
  int32_t result = calc_expr(&st);
  if (st.err) {
    fputs("error: malformed expression\n", stderr);
    return -1;
  }
  calc_skip_ws(&st);
  if (st.pos < st.len) {
    fputs("error: unexpected token\n", stderr);
    return -1;
  }
  printf("%d\n", result);
  return 0;
}

/* etl_calc_line: void wrapper around etl_calc_eval; suitable for ETL
 * expression statements. */
void etl_calc_line(int8_t *buf, int32_t len) {
  etl_calc_eval(buf, len);
}

/* --- argv helpers (Linux: read /proc/self/cmdline) --- */
/* Lazily parsed; first call populates g_etl_args[]. */

#define ETL_MAX_ARGS 64
#define ETL_ARG_BUF  4096

static int32_t  g_etl_argc = -1;
static char     g_etl_argbuf[ETL_ARG_BUF];
static char    *g_etl_args[ETL_MAX_ARGS];

static void etl_argv_init(void) {
  if (g_etl_argc >= 0) return;
  g_etl_argc = 0;
  FILE *f = fopen("/proc/self/cmdline", "rb");
  if (f == NULL) return;
  size_t n = fread(g_etl_argbuf, 1, ETL_ARG_BUF - 1, f);
  fclose(f);
  if (n == 0) return;
  g_etl_argbuf[n] = '\0';
  size_t i = 0;
  while (i < n && g_etl_argc < ETL_MAX_ARGS) {
    g_etl_args[g_etl_argc++] = &g_etl_argbuf[i];
    while (i < n && g_etl_argbuf[i] != '\0') i++;
    i++; /* skip NUL */
  }
}

int32_t etl_argc(void) {
  etl_argv_init();
  return g_etl_argc;
}

/* Copy argument i into buf (NUL-terminated). Returns length or -1. */
int32_t etl_argv_copy(int32_t i, int8_t *buf, int32_t cap) {
  etl_argv_init();
  if (i < 0 || i >= g_etl_argc || buf == NULL || cap <= 0) return -1;
  const char *src = g_etl_args[i];
  int32_t len = (int32_t)strlen(src);
  if (len >= cap) len = cap - 1;
  memcpy(buf, src, (size_t)len);
  buf[len] = '\0';
  return len;
}

/* --- String transform helpers --- */

void etl_toupper_buf(int8_t *buf, int32_t len) {
  if (buf == NULL || len <= 0) return;
  for (int32_t i = 0; i < len; i++) {
    unsigned char c = (unsigned char)buf[i];
    if (c >= 'a' && c <= 'z') buf[i] = (int8_t)(c - 32);
  }
}

void etl_argv_get(int32_t i, int8_t *buf, int32_t cap) {
  etl_argv_copy(i, buf, cap);
}
