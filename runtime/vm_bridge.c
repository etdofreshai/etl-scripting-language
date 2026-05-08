/*
 * vm_bridge.c — handle-table bridge between vm.etl and the real runtime.
 *
 * vm.etl uses i32 "handles" on its value stack to refer to opaque heap
 * objects (EtlString *, EtlDynArr *, EtlVal *).  These bridge functions map
 * handles → real pointers, call the actual runtime function, and return the
 * result as an i32 handle or scalar.
 *
 * Handle index 0 is the null/invalid handle (no live object).
 * Each table supports up to 64 live objects — matching the VM's stack depth.
 *
 * The ETL VM is a single-instance interpreter (one vm_run() call at a time),
 * so a single set of global tables is safe.
 *
 * The C VM (runtime/etl_vm.c) is NOT modified.
 */

#include <stdint.h>
#include <stddef.h>
#include "etl_string.h"
#include "etl_dynarr.h"
#include "etl_etlval.h"

/* ── handle tables ──────────────────────────────────────────────────────── */

#define VM_HTAB_CAP 64

/* raw heap pointers (etl_alloc / etl_free) — stored as void * */
static void      *ha_tab[VM_HTAB_CAP];
static int32_t    ha_next = 1;   /* next slot to allocate; 0 = null */

/* EtlString handles */
static EtlString *hs_tab[VM_HTAB_CAP];
static int32_t    hs_next = 1;

/* EtlDynArr handles */
static EtlDynArr *hd_tab[VM_HTAB_CAP];
static int32_t    hd_next = 1;

/* EtlVal handles */
static EtlVal    *hv_tab[VM_HTAB_CAP];
static int32_t    hv_next = 1;

/* Reset all tables — called by vm_bridge_reset() before each vm_run() */
void vm_bridge_reset(void)
{
    for (int i = 0; i < VM_HTAB_CAP; i++) {
        ha_tab[i] = NULL;
        hs_tab[i] = NULL;
        hd_tab[i] = NULL;
        hv_tab[i] = NULL;
    }
    ha_next = 1;
    hs_next = 1;
    hd_next = 1;
    hv_next = 1;
}

/* ── heap (HA/HF) ────────────────────────────────────────────────────────── */

/* etl_alloc wrapper — declared extern in vm.etl as vm_ha_alloc */
int32_t vm_ha_alloc(int32_t sz)
{
    extern int8_t *etl_alloc(int32_t);
    if (sz <= 0) return 0;
    if (ha_next >= VM_HTAB_CAP) return 0;
    void *p = (void *)etl_alloc(sz);
    if (!p) return 0;
    int32_t h = ha_next++;
    ha_tab[h] = p;
    return h;
}

/* etl_free wrapper */
void vm_ha_free(int32_t h)
{
    extern void etl_free(int8_t *);
    if (h <= 0 || h >= VM_HTAB_CAP) return;
    if (ha_tab[h]) {
        etl_free((int8_t *)ha_tab[h]);
        ha_tab[h] = NULL;
    }
}

/* return the raw pointer for a handle (used by vm_hs_new) */
static void *vm_ha_get(int32_t h)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return NULL;
    return ha_tab[h];
}

/* ── strings (HS*) ───────────────────────────────────────────────────────── */

/* HSN: str_new(ptr_handle) → str_handle */
int32_t vm_hs_new(int32_t ptr_handle)
{
    if (hs_next >= VM_HTAB_CAP) return 0;
    void *literal = vm_ha_get(ptr_handle);
    EtlString *s = str_new(literal);
    if (!s) return 0;
    int32_t h = hs_next++;
    hs_tab[h] = s;
    return h;
}

/* HSL: str_len(str_handle) → i32 */
int32_t vm_hs_len(int32_t h)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return 0;
    EtlString *s = hs_tab[h];
    if (!s) return 0;
    return str_len(s);
}

/* HSC: str_concat(a_handle, b_handle) → new str_handle */
int32_t vm_hs_concat(int32_t ah, int32_t bh)
{
    if (hs_next >= VM_HTAB_CAP) return 0;
    EtlString *a = (ah > 0 && ah < VM_HTAB_CAP) ? hs_tab[ah] : NULL;
    EtlString *b = (bh > 0 && bh < VM_HTAB_CAP) ? hs_tab[bh] : NULL;
    EtlString *c = str_concat(a, b);
    if (!c) return 0;
    int32_t h = hs_next++;
    hs_tab[h] = c;
    return h;
}

/* HSA: str_at(str_handle, idx) → i32 */
int32_t vm_hs_at(int32_t sh, int32_t idx)
{
    if (sh <= 0 || sh >= VM_HTAB_CAP) return 0;
    EtlString *s = hs_tab[sh];
    if (!s) return 0;
    return str_at(s, idx);
}

/* HSE: str_eq(a_handle, b_handle) → i32 */
int32_t vm_hs_eq(int32_t ah, int32_t bh)
{
    EtlString *a = (ah > 0 && ah < VM_HTAB_CAP) ? hs_tab[ah] : NULL;
    EtlString *b = (bh > 0 && bh < VM_HTAB_CAP) ? hs_tab[bh] : NULL;
    return str_eq(a, b);
}

/* HSF: str_free(str_handle) */
void vm_hs_free(int32_t h)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return;
    if (hs_tab[h]) {
        str_free(hs_tab[h]);
        hs_tab[h] = NULL;
    }
}

/* ── dynarr (HD*) ─────────────────────────────────────────────────────────── */

/* HDN: dynarr_new() → dynarr_handle */
int32_t vm_hd_new(void)
{
    if (hd_next >= VM_HTAB_CAP) return 0;
    EtlDynArr *a = dynarr_new();
    if (!a) return 0;
    int32_t h = hd_next++;
    hd_tab[h] = a;
    return h;
}

/* HDP: dynarr_push(dynarr_handle, v) */
void vm_hd_push(int32_t h, int32_t v)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return;
    EtlDynArr *a = hd_tab[h];
    if (!a) return;
    dynarr_push(a, v);
}

/* HDL: dynarr_len(dynarr_handle) → i32 */
int32_t vm_hd_len(int32_t h)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return 0;
    EtlDynArr *a = hd_tab[h];
    if (!a) return 0;
    return dynarr_len(a);
}

/* HDG: dynarr_get(dynarr_handle, idx) → i32 */
int32_t vm_hd_get(int32_t h, int32_t idx)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return 0;
    EtlDynArr *a = hd_tab[h];
    if (!a) return 0;
    return dynarr_get(a, idx);
}

/* HDS: dynarr_set(dynarr_handle, idx, v) */
void vm_hd_set(int32_t h, int32_t idx, int32_t v)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return;
    EtlDynArr *a = hd_tab[h];
    if (!a) return;
    dynarr_set(a, idx, v);
}

/* HDF: dynarr_free(dynarr_handle) */
void vm_hd_free(int32_t h)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return;
    if (hd_tab[h]) {
        dynarr_free(hd_tab[h]);
        hd_tab[h] = NULL;
    }
}

/* ── etlval (HV*) ─────────────────────────────────────────────────────────── */

/* HVI: etlval_int(i) → etlval_handle */
int32_t vm_hv_int(int32_t i)
{
    if (hv_next >= VM_HTAB_CAP) return 0;
    EtlVal *v = etlval_int(i);
    if (!v) return 0;
    int32_t h = hv_next++;
    hv_tab[h] = v;
    return h;
}

/* HVB: etlval_bool(b) → etlval_handle */
int32_t vm_hv_bool(int32_t b)
{
    if (hv_next >= VM_HTAB_CAP) return 0;
    EtlVal *v = etlval_bool(b);
    if (!v) return 0;
    int32_t h = hv_next++;
    hv_tab[h] = v;
    return h;
}

/* HVP: etlval_ptr(ptr_handle) → etlval_handle */
int32_t vm_hv_ptr(int32_t ptr_handle)
{
    if (hv_next >= VM_HTAB_CAP) return 0;
    void *p = vm_ha_get(ptr_handle);
    EtlVal *v = etlval_ptr(p);
    if (!v) return 0;
    int32_t h = hv_next++;
    hv_tab[h] = v;
    return h;
}

/* HVS: etlval_str(str_handle) → etlval_handle */
int32_t vm_hv_str(int32_t str_handle)
{
    if (hv_next >= VM_HTAB_CAP) return 0;
    EtlString *s = (str_handle > 0 && str_handle < VM_HTAB_CAP) ? hs_tab[str_handle] : NULL;
    EtlVal *v = etlval_str(s);
    if (!v) return 0;
    int32_t h = hv_next++;
    hv_tab[h] = v;
    return h;
}

/* HVT: etlval_tag(etlval_handle) → i32 */
int32_t vm_hv_tag(int32_t h)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return -1;
    EtlVal *v = hv_tab[h];
    return etlval_tag(v);
}

/* HVAI: etlval_as_int(etlval_handle) → i32 */
int32_t vm_hv_as_int(int32_t h)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return 0;
    EtlVal *v = hv_tab[h];
    return etlval_as_int(v);
}

/* HVAB: etlval_as_bool(etlval_handle) → i32 */
int32_t vm_hv_as_bool(int32_t h)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return 0;
    EtlVal *v = hv_tab[h];
    return etlval_as_bool(v);
}

/* HVAP: etlval_as_ptr → return ptr_handle for the pointer (or 0) */
int32_t vm_hv_as_ptr(int32_t h)
{
    /* We cannot return a raw pointer as i32 on 64-bit systems.
     * Instead we allocate a new ha_tab slot pointing to the same memory.
     * The caller is responsible for not double-freeing. */
    if (h <= 0 || h >= VM_HTAB_CAP) return 0;
    EtlVal *v = hv_tab[h];
    void *p = etlval_as_ptr(v);
    if (!p) return 0;
    if (ha_next >= VM_HTAB_CAP) return 0;
    int32_t ph = ha_next++;
    ha_tab[ph] = p;
    return ph;
}

/* HVAS: etlval_as_str → return str_handle (alias, not a copy) */
int32_t vm_hv_as_str(int32_t h)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return 0;
    EtlVal *v = hv_tab[h];
    EtlString *s = etlval_as_str(v);
    if (!s) return 0;
    if (hs_next >= VM_HTAB_CAP) return 0;
    int32_t sh = hs_next++;
    hs_tab[sh] = s;   /* alias — do NOT str_free this slot separately */
    return sh;
}

/* HVF: etlval_free(etlval_handle) */
void vm_hv_free(int32_t h)
{
    if (h <= 0 || h >= VM_HTAB_CAP) return;
    if (hv_tab[h]) {
        etlval_free(hv_tab[h]);
        hv_tab[h] = NULL;
    }
}
