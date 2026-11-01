#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* A panel as a bit matrix: one row of W 64-bit words per unit, one bit per
   period. A single pass over the rows sets the bits; a bit already set is
   a duplicated unit-period. Everything else is read from the words with
   popcount and bit scans, so nothing is sorted or hashed per row:

     n_seen   set bits
     lo, hi   first and last set bit (1-based period positions)
     runs     separate runs of presence: bits set whose lower neighbour
              is not, carried across word boundaries
     pattern  dense id of the unit's row of words, by a hash over units

   Units are 1-based ids; a position of NA (outside the periods) is
   skipped. The bit matrix is returned as a raw vector, so R can read the
   bits of a few units afterwards (pattern text, missing unit-periods). */

static inline uint64_t mix64(uint64_t x) {
    x ^= x >> 33;
    x *= 0xff51afd7ed558ccdULL;
    x ^= x >> 33;
    x *= 0xc4ceb9fe1a85ec53ULL;
    x ^= x >> 33;
    return x;
}

int inshape_dense_u64(const uint64_t *keys, R_xlen_t n, int *out, int threads);

static int cmp_int(const void *a, const void *b) {
    int x = *(const int *) a, y = *(const int *) b;
    return (x > y) - (x < y);
}

/* Threads set bits with an atomic OR, so they can share the matrix; the
   OR returns the word as it was, so exactly one row of a unit-period finds
   its bit unset. Which row that is depends on timing, but only the number
   of repeats and their unit-periods are used, and the repeated rows are
   returned sorted. */
SEXP inshape_panel_scan(SEXP unit_, SEXP pos_, SEXP n_units_, SEXP n_per_,
                        SEXP threads_) {
    R_xlen_t n = XLENGTH(unit_);
    const int *unit = INTEGER(unit_), *pos = INTEGER(pos_);
    int U = Rf_asInteger(n_units_), T = Rf_asInteger(n_per_);
    int W = (T + 63) / 64;
    int threads = Rf_asInteger(threads_);
    if (threads < 1) threads = 1;

    SEXP bits_ = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t) U * W * 8));
    uint64_t *bits = (uint64_t *) RAW(bits_);
    memset(bits, 0, (size_t) U * W * 8);

    /* Rows that repeat a unit-period, 1-based, one growing buffer per thread */
    int **dup = (int **) calloc(threads, sizeof(int *));
    size_t *n_dup = (size_t *) calloc(threads, sizeof(size_t));
    int oom = dup == NULL || n_dup == NULL;

#ifdef _OPENMP
#pragma omp parallel for num_threads(threads) schedule(static)
#endif
    for (int t = 0; t < threads; t++) {
        if (oom) continue;
        R_xlen_t from = n * t / threads, to = n * (t + 1) / threads;
        size_t cap = 0;
        for (R_xlen_t i = from; i < to; i++) {
            int p = pos[i];
            if (p == NA_INTEGER) continue;
            uint64_t *w = bits + (size_t) (unit[i] - 1) * W + (p - 1) / 64;
            uint64_t b = (uint64_t) 1 << ((p - 1) % 64);
            if (__atomic_fetch_or(w, b, __ATOMIC_RELAXED) & b) {
                if (n_dup[t] == cap) {
                    cap = cap ? cap * 2 : 1024;
                    int *grown = (int *) realloc(dup[t], cap * sizeof(int));
                    if (grown == NULL) { oom = 1; break; }
                    dup[t] = grown;
                }
                dup[t][n_dup[t]++] = (int) i + 1;
            }
        }
    }

    size_t total_dup = 0;
    if (!oom) for (int t = 0; t < threads; t++) total_dup += n_dup[t];
    SEXP dup_ = PROTECT(Rf_allocVector(INTSXP, oom ? 0 : total_dup));
    if (!oom) {
        size_t at = 0;
        for (int t = 0; t < threads; t++) {
            if (n_dup[t]) memcpy(INTEGER(dup_) + at, dup[t], n_dup[t] * sizeof(int));
            at += n_dup[t];
        }
        if (total_dup > 1) qsort(INTEGER(dup_), total_dup, sizeof(int), cmp_int);
    }
    if (dup != NULL) for (int t = 0; t < threads; t++) free(dup[t]);
    free(dup);
    free(n_dup);
    if (oom) Rf_error("Out of memory in the panel engine.");

    SEXP seen_ = PROTECT(Rf_allocVector(INTSXP, U));
    SEXP lo_   = PROTECT(Rf_allocVector(INTSXP, U));
    SEXP hi_   = PROTECT(Rf_allocVector(INTSXP, U));
    SEXP runs_ = PROTECT(Rf_allocVector(INTSXP, U));
    SEXP pat_  = PROTECT(Rf_allocVector(INTSXP, U));
    int *seen = INTEGER(seen_), *lo = INTEGER(lo_), *hi = INTEGER(hi_);
    int *runs = INTEGER(runs_), *pat = INTEGER(pat_);

    /* Per unit, independently */
#ifdef _OPENMP
#pragma omp parallel for num_threads(threads) schedule(static)
#endif
    for (int u = 0; u < U; u++) {
        const uint64_t *row = bits + (size_t) u * W;
        int count = 0, first = -1, last = -1, r = 0;
        uint64_t carry = 0;
        for (int j = 0; j < W; j++) {
            uint64_t w = row[j];
            if (w == 0) { carry = 0; continue; }
            count += __builtin_popcountll(w);
            if (first < 0) first = j * 64 + __builtin_ctzll(w);
            last = j * 64 + 63 - __builtin_clzll(w);
            r += __builtin_popcountll(w & ~((w << 1) | carry));
            carry = w >> 63;
        }
        seen[u] = count;
        runs[u] = r;
        lo[u] = count ? first + 1 : NA_INTEGER;
        hi[u] = count ? last + 1 : NA_INTEGER;
    }

    /* Pattern ids: a single word is its own key, for the grouping engine;
       longer rows are hashed and compared word by word */
    int n_pat = 0;
    if (W == 1) {
        int k = inshape_dense_u64(bits, U, pat, threads);
        if (k == -2) Rf_error("Out of memory in the panel engine.");
        int empty = 0;
        for (int u = 0; u < U; u++) if (seen[u] == 0) { empty = pat[u]; break; }
        for (int u = 0; u < U; u++) {
            if (seen[u] == 0) pat[u] = 0;
            else if (empty && pat[u] > empty) pat[u]--;
        }
        n_pat = empty ? k - 1 : k;
    } else {
        size_t cap = 1024;
        while (cap < (size_t) U * 2 && cap < ((size_t) 1 << 30)) cap <<= 1;
        int *slot = (int *) R_alloc(cap, sizeof(int));
        memset(slot, 0, cap * sizeof(int));
        for (int u = 0; u < U; u++) {
            if (seen[u] == 0) { pat[u] = 0; continue; }
            const uint64_t *row = bits + (size_t) u * W;
            uint64_t h = 0x9e3779b97f4a7c15ULL;
            for (int j = 0; j < W; j++) h = mix64(h ^ row[j]);
            size_t s = h & (cap - 1);
            for (;;) {
                int v = slot[s];
                if (v == 0) {
                    slot[s] = u + 1;
                    pat[u] = ++n_pat;
                    break;
                }
                if (memcmp(bits + (size_t) (v - 1) * W, row, (size_t) W * 8) == 0) {
                    pat[u] = pat[v - 1];
                    break;
                }
                s = (s + 1) & (cap - 1);
            }
            if ((u & 65535) == 0) R_CheckUserInterrupt();
        }
    }

    SEXP out = PROTECT(Rf_allocVector(VECSXP, 8));
    SET_VECTOR_ELT(out, 0, seen_);
    SET_VECTOR_ELT(out, 1, lo_);
    SET_VECTOR_ELT(out, 2, hi_);
    SET_VECTOR_ELT(out, 3, runs_);
    SET_VECTOR_ELT(out, 4, pat_);
    SET_VECTOR_ELT(out, 5, Rf_ScalarInteger(n_pat));
    SET_VECTOR_ELT(out, 6, dup_);
    SET_VECTOR_ELT(out, 7, bits_);
    SEXP nms = PROTECT(Rf_allocVector(STRSXP, 8));
    const char *names[] = {"n_seen", "lo", "hi", "runs", "pattern", "n_patterns",
                           "dup_rows", "bits"};
    for (int i = 0; i < 8; i++) SET_STRING_ELT(nms, i, Rf_mkChar(names[i]));
    Rf_setAttrib(out, R_NamesSymbol, nms);
    UNPROTECT(9);
    return out;
}

/* The unset bits between lo and hi (1-based, inclusive) of the given units:
   the missing unit-periods, as a unit vector and a position vector. */
SEXP inshape_panel_missing(SEXP bits_, SEXP n_per_, SEXP units_, SEXP lo_, SEXP hi_) {
    const uint64_t *bits = (const uint64_t *) RAW(bits_);
    int T = Rf_asInteger(n_per_), W = (T + 63) / 64;
    R_xlen_t k = XLENGTH(units_);
    const int *units = INTEGER(units_), *lo = INTEGER(lo_), *hi = INTEGER(hi_);

    R_xlen_t total = 0;
    for (R_xlen_t i = 0; i < k; i++) {
        const uint64_t *row = bits + (size_t) (units[i] - 1) * W;
        for (int p = lo[i]; p <= hi[i]; p++) {
            if (!((row[(p - 1) / 64] >> ((p - 1) % 64)) & 1)) total++;
        }
    }
    SEXP u_ = PROTECT(Rf_allocVector(INTSXP, total));
    SEXP p_ = PROTECT(Rf_allocVector(INTSXP, total));
    int *uo = INTEGER(u_), *po = INTEGER(p_);
    R_xlen_t m = 0;
    for (R_xlen_t i = 0; i < k; i++) {
        const uint64_t *row = bits + (size_t) (units[i] - 1) * W;
        for (int p = lo[i]; p <= hi[i]; p++) {
            if (!((row[(p - 1) / 64] >> ((p - 1) % 64)) & 1)) {
                uo[m] = units[i];
                po[m] = p;
                m++;
            }
        }
    }
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
    SET_VECTOR_ELT(out, 0, u_);
    SET_VECTOR_ELT(out, 1, p_);
    UNPROTECT(3);
    return out;
}
