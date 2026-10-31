#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#ifdef _OPENMP
#include <omp.h>
#endif

/* Dense group ids 1..k, the grouping engine of every check.

   The result equals dense_ids(match(x, x)) up to the numbering of the
   groups: equal values share an id, different values do not, and NA is a
   value of its own, as in match(). -0 equals 0, and every NaN equals every
   other NaN, apart from NA. Strings are compared by their CHARSXP pointer,
   which R's string cache makes unique per string and encoding; strings
   marked latin1 or bytes could equal a UTF-8 string with another pointer,
   so for those the function returns NULL and R falls back to match().

   Three paths, chosen by size and type:

   - Integers with a small range (years, codes, factors) index an array
     directly: no hashing at all.
   - Small vectors use one open-addressing hash table, ids in order of
     first appearance.
   - Large vectors are partitioned first. The rows are split into 1024
     partitions by the top bits of their hash, in row order within each
     partition; each partition then gets its own small table, which stays
     in the processor cache instead of missing it on every row as one large
     table does, and the partitions run in parallel. Ids are numbered
     partition by partition, so the result does not depend on the number
     of threads. */

static inline uint64_t mix64(uint64_t x) {
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33;
    x *= 0xc4ceb9fe1a85ec53ULL;
    x ^= x >> 33;
    return x;
}

static inline uint64_t real_key(double v) {
    if (ISNA(v)) return 0x7ff00000000007a2ULL;
    if (ISNAN(v)) return 0x7ff8000000000000ULL;
    if (v == 0) return 0;
    uint64_t k;
    memcpy(&k, &v, sizeof k);
    return k;
}

/* Key types: R vectors, or a plain array of 64-bit keys (panel patterns) */
#define K_STR 1
#define K_INT 2
#define K_REAL 3
#define K_U64 4

static inline uint64_t key_at(int type, const void *px, R_xlen_t i) {
    switch (type) {
    case K_STR:  return (uint64_t) (uintptr_t) ((const SEXP *) px)[i];
    case K_INT:  return (uint64_t) (uint32_t) ((const int *) px)[i];
    case K_REAL: return real_key(((const double *) px)[i]);
    default:     return ((const uint64_t *) px)[i];
    }
}

static inline int foreign_string(int type, const void *px, R_xlen_t i) {
    if (type != K_STR) return 0;
    cetype_t ce = Rf_getCharCE(((const SEXP *) px)[i]);
    return ce == CE_LATIN1 || ce == CE_BYTES;
}

/* A growable open-addressing table of (key, id), malloc'ed so threads can
   own one each */
typedef struct {
    uint64_t *key;
    int *id;
    size_t cap, used;
} table_t;

static int table_init(table_t *t, size_t cap) {
    t->cap = cap;
    t->used = 0;
    t->key = (uint64_t *) malloc(cap * sizeof(uint64_t));
    t->id = (int *) calloc(cap, sizeof(int));
    return t->key != NULL && t->id != NULL;
}

static void table_free(table_t *t) {
    free(t->key);
    free(t->id);
}

static int table_grow(table_t *t) {
    table_t g;
    if (!table_init(&g, t->cap * 2)) { table_free(&g); return 0; }
    for (size_t j = 0; j < t->cap; j++) {
        if (t->id[j] == 0) continue;
        size_t h = mix64(t->key[j]) & (g.cap - 1);
        while (g.id[h] != 0) h = (h + 1) & (g.cap - 1);
        g.key[h] = t->key[j];
        g.id[h] = t->id[j];
    }
    g.used = t->used;
    table_free(t);
    *t = g;
    return 1;
}

/* Id of key k, claiming the next id (*n_ids + 1) when it is new; returns 0
   when out of memory, and sets *is_new */
static inline int table_id(table_t *t, uint64_t k, int *n_ids, int *is_new) {
    size_t h = mix64(k) & (t->cap - 1);
    for (;;) {
        int v = t->id[h];
        if (v == 0) {
            t->key[h] = k;
            t->id[h] = ++(*n_ids);
            t->used++;
            *is_new = 1;
            v = t->id[h];
            if (t->used * 2 > t->cap && !table_grow(t)) return 0;
            return v;
        }
        if (t->key[h] == k) { *is_new = 0; return v; }
        h = (h + 1) & (t->cap - 1);
    }
}

/* Dense ids of n keys into out; returns the number of groups, -1 for a
   foreign string, -2 when out of memory */
static int dense_serial(int type, const void *px, R_xlen_t n, int *out) {
    table_t t;
    if (!table_init(&t, 1 << 10)) { table_free(&t); return -2; }
    int n_ids = 0, is_new, foreign = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        int v = table_id(&t, key_at(type, px, i), &n_ids, &is_new);
        if (v == 0) { table_free(&t); return -2; }
        if (is_new) foreign |= foreign_string(type, px, i);
        out[i] = v;
    }
    table_free(&t);
    return foreign ? -1 : n_ids;
}

#define PART_BITS 10
#define N_PART (1 << PART_BITS)

static int dense_partitioned(int type, const void *px, R_xlen_t n, int *out,
                             int threads) {
    if (threads < 1) threads = 1;
    /* Rows of each thread's chunk counted per partition, then scattered in
       row order: partition-major, thread order within a partition */
    size_t *count = (size_t *) calloc((size_t) threads * N_PART, sizeof(size_t));
    int *perm = (int *) malloc((size_t) n * sizeof(int));
    size_t *start = (size_t *) malloc((N_PART + 1) * sizeof(size_t));
    int *n_ids = (int *) calloc(N_PART, sizeof(int));
    int status = 0, foreign = 0;
    if (!count || !perm || !start || !n_ids) { status = -2; goto done; }

#ifdef _OPENMP
#pragma omp parallel for num_threads(threads) schedule(static)
#endif
    for (int t = 0; t < threads; t++) {
        R_xlen_t lo = n * t / threads, hi = n * (t + 1) / threads;
        size_t *c = count + (size_t) t * N_PART;
        for (R_xlen_t i = lo; i < hi; i++) {
            c[mix64(key_at(type, px, i)) >> (64 - PART_BITS)]++;
        }
    }
    size_t at = 0;
    for (int p = 0; p < N_PART; p++) {
        start[p] = at;
        for (int t = 0; t < threads; t++) {
            size_t c = count[(size_t) t * N_PART + p];
            count[(size_t) t * N_PART + p] = at;
            at += c;
        }
    }
    start[N_PART] = at;

#ifdef _OPENMP
#pragma omp parallel for num_threads(threads) schedule(static)
#endif
    for (int t = 0; t < threads; t++) {
        R_xlen_t lo = n * t / threads, hi = n * (t + 1) / threads;
        size_t *c = count + (size_t) t * N_PART;
        for (R_xlen_t i = lo; i < hi; i++) {
            perm[c[mix64(key_at(type, px, i)) >> (64 - PART_BITS)]++] = (int) i;
        }
    }

    /* Each partition on its own table; local ids first */
#ifdef _OPENMP
#pragma omp parallel for num_threads(threads) schedule(dynamic, 8) reduction(|:foreign)
#endif
    for (int p = 0; p < N_PART; p++) {
        if (status != 0) continue;
        table_t t;
        if (!table_init(&t, 1 << 10)) { table_free(&t); status = -2; continue; }
        int m = 0, is_new;
        for (size_t j = start[p]; j < start[p + 1]; j++) {
            int i = perm[j];
            int v = table_id(&t, key_at(type, px, i), &m, &is_new);
            if (v == 0) { status = -2; break; }
            if (is_new) foreign |= foreign_string(type, px, i);
            out[i] = v;
        }
        n_ids[p] = m;
        table_free(&t);
    }
    if (status != 0) goto done;

    /* Offset the local ids by the groups of the earlier partitions */
    int base[N_PART];
    long long total = 0;
    for (int p = 0; p < N_PART; p++) {
        base[p] = (int) total;
        total += n_ids[p];
    }
#ifdef _OPENMP
#pragma omp parallel for num_threads(threads) schedule(dynamic, 8)
#endif
    for (int p = 0; p < N_PART; p++) {
        for (size_t j = start[p]; j < start[p + 1]; j++) out[perm[j]] += base[p];
    }
    status = foreign ? -1 : (int) total;

done:
    free(count);
    free(perm);
    free(start);
    free(n_ids);
    return status;
}

/* Integers with a small range: an array indexed by value, ids in order of
   first appearance. Returns -3 when the range is too wide. */
static int dense_direct(const int *px, R_xlen_t n, int *out) {
    int lo = INT_MAX, hi = INT_MIN;
    for (R_xlen_t i = 0; i < n; i++) {
        int v = px[i];
        if (v == NA_INTEGER) continue;
        if (v < lo) lo = v;
        if (v > hi) hi = v;
    }
    if (lo > hi) { lo = 0; hi = 0; }
    double range = (double) hi - lo + 1;
    if (range > 4.0 * n + 1024 || range > 1e8) return -3;
    int *map = (int *) calloc((size_t) range + 1, sizeof(int));
    if (map == NULL) return -2;
    int n_ids = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        int v = px[i];
        size_t slot = v == NA_INTEGER ? (size_t) range : (size_t) (v - lo);
        if (map[slot] == 0) map[slot] = ++n_ids;
        out[i] = map[slot];
    }
    free(map);
    return n_ids;
}

static SEXP dense_result(SEXP res, int n_ids) {
    if (n_ids == -2) Rf_error("Out of memory in the grouping engine.");
    if (n_ids < 0) return R_NilValue;
    Rf_setAttrib(res, Rf_install("n"), Rf_ScalarInteger(n_ids));
    return res;
}

SEXP lustrum_dense_ids(SEXP x, SEXP threads_) {
    R_xlen_t n = XLENGTH(x);
    if (n > INT_MAX - 1) Rf_error("Too many rows for the grouping engine.");
    int threads = Rf_asInteger(threads_);
    int type;
    const void *px;
    switch (TYPEOF(x)) {
    case STRSXP:  type = K_STR;  px = (const void *) STRING_PTR_RO(x); break;
    case INTSXP:
    case LGLSXP:  type = K_INT;  px = (const void *) INTEGER(x); break;
    case REALSXP: type = K_REAL; px = (const void *) REAL(x); break;
    default: return R_NilValue;
    }
    SEXP res = PROTECT(Rf_allocVector(INTSXP, n));
    int *out = INTEGER(res);
    int n_ids = -3;
    if (type == K_INT) n_ids = dense_direct((const int *) px, n, out);
    if (n_ids == -3) {
        n_ids = n < (1 << 17) ? dense_serial(type, px, n, out)
                              : dense_partitioned(type, px, n, out, threads);
    }
    res = dense_result(res, n_ids);
    UNPROTECT(1);
    return res;
}

/* A fingerprint of a vector's content for the cache of dense ids in
   dense_codes(): type, length and a 64-bit checksum, as one string. The
   checksum sums a mix of each element with its position, so it changes
   with any value or order and runs in parallel in one pass. Strings are
   summed by their CHARSXP pointer: equal pointers mean equal strings, so
   equal fingerprints mean equal groups. Returns NULL for vectors the cache
   should skip: other types, and integers with a range small enough for
   dense_direct(), which is as fast as the checksum itself. */
SEXP lustrum_fingerprint(SEXP x, SEXP threads_) {
    R_xlen_t n = XLENGTH(x);
    int threads = Rf_asInteger(threads_);
    if (threads < 1) threads = 1;
    int type;
    const void *px;
    switch (TYPEOF(x)) {
    case STRSXP:  type = K_STR;  px = (const void *) STRING_PTR_RO(x); break;
    case INTSXP:
    case LGLSXP:  type = K_INT;  px = (const void *) INTEGER(x); break;
    case REALSXP: type = K_U64;  px = (const void *) REAL(x); break;
    default: return R_NilValue;
    }
    uint64_t sum = 0;
    int lo = INT_MAX, hi = INT_MIN;
#ifdef _OPENMP
#pragma omp parallel for num_threads(threads) schedule(static) reduction(+:sum) reduction(min:lo) reduction(max:hi)
#endif
    for (R_xlen_t i = 0; i < n; i++) {
        uint64_t k = key_at(type, px, i);
        sum += mix64(k ^ ((uint64_t) i * 0x9e3779b97f4a7c15ULL));
        if (type == K_INT) {
            int v = (int) (uint32_t) k;
            if (v != NA_INTEGER) {
                if (v < lo) lo = v;
                if (v > hi) hi = v;
            }
        }
    }
    if (type == K_INT) {
        double range = lo > hi ? 1 : (double) hi - lo + 1;
        if (!(range > 4.0 * n + 1024 || range > 1e8)) return R_NilValue;
    }
    char buf[64];
    snprintf(buf, sizeof buf, "%d %.0f %016llx", TYPEOF(x), (double) n,
             (unsigned long long) sum);
    return Rf_mkString(buf);
}

/* The first row (1-based) of each group 1..n_groups, 0 for an empty
   group: one forward pass */
SEXP lustrum_first_rows(SEXP ids_, SEXP n_groups_) {
    R_xlen_t n = XLENGTH(ids_);
    int k = Rf_asInteger(n_groups_);
    const int *ids = INTEGER(ids_);
    SEXP res = PROTECT(Rf_allocVector(INTSXP, k));
    int *out = INTEGER(res);
    memset(out, 0, (size_t) k * sizeof(int));
    for (R_xlen_t i = 0; i < n; i++) {
        int g = ids[i];
        if (g < 1 || g > k) continue;
        if (out[g - 1] == 0) out[g - 1] = (int) i + 1;
    }
    UNPROTECT(1);
    return res;
}

/* Dense ids of 64-bit keys, for the panel engine (src/panel.c) */
int lustrum_dense_u64(const uint64_t *keys, R_xlen_t n, int *out, int threads) {
    return n < (1 << 17) ? dense_serial(K_U64, keys, n, out)
                         : dense_partitioned(K_U64, keys, n, out, threads);
}
