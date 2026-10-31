#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <limits.h>
#include <math.h>

/* The rows of time outside a bound, for ensure_within(): time < bound for
   a lower bound, time > bound for an upper one. Either side may first be
   mapped through a lookup table, from a year to its first or last day,
   when a year meets a date; a value off the table or not a whole year
   makes the function return NULL, and R explains. Missing values on
   either side compare as false. One pass to count, one to fill: no vector
   as long as the data is allocated besides the result. */

/* A numeric vector read as doubles, its type looked up once */
typedef struct {
    const int *ip;
    const double *dp;
} values_t;

static values_t values_of(SEXP x) {
    values_t v = {NULL, NULL};
    if (TYPEOF(x) == INTSXP || TYPEOF(x) == LGLSXP) v.ip = INTEGER(x);
    else v.dp = REAL(x);
    return v;
}

static inline double value_at(values_t x, R_xlen_t i) {
    if (x.ip) return x.ip[i] == NA_INTEGER ? NAN : (double) x.ip[i];
    return x.dp[i];
}

/* Value i of x, through the table when there is one; NAN for missing, and
   *bad set for a value the table does not cover */
static inline double mapped(values_t x, R_xlen_t i, const double *lut, R_xlen_t n_lut,
                            double lo, int *bad) {
    double v = value_at(x, i);
    if (lut == NULL || ISNAN(v)) return v;
    double k = v - lo;
    if (k != floor(k) || k < 0 || k >= (double) n_lut) { *bad = 1; return NAN; }
    return lut[(R_xlen_t) k];
}

SEXP lustrum_outside(SEXP time, SEXP bound, SEXP upper_, SEXP t_lut_, SEXP t_lo_,
                     SEXP b_lut_, SEXP b_lo_) {
    R_xlen_t n = XLENGTH(time);
    if (XLENGTH(bound) != n) Rf_error("Time and bound must have the same length.");
    int upper = Rf_asLogical(upper_);
    const double *t_lut = Rf_isNull(t_lut_) ? NULL : REAL(t_lut_);
    const double *b_lut = Rf_isNull(b_lut_) ? NULL : REAL(b_lut_);
    R_xlen_t nt = Rf_isNull(t_lut_) ? 0 : XLENGTH(t_lut_);
    R_xlen_t nb = Rf_isNull(b_lut_) ? 0 : XLENGTH(b_lut_);
    double t_lo = Rf_asReal(t_lo_), b_lo = Rf_asReal(b_lo_);
    if (!Rf_isNumeric(time) || !Rf_isNumeric(bound)) Rf_error("Time and bound must be numeric.");
    values_t tv = values_of(time), bv = values_of(bound);
    int bad = 0;

    R_xlen_t count = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        double t = mapped(tv, i, t_lut, nt, t_lo, &bad);
        double b = mapped(bv, i, b_lut, nb, b_lo, &bad);
        if (upper ? t > b : t < b) count++;
    }
    if (bad) return R_NilValue;

    SEXP res = PROTECT(Rf_allocVector(n > INT_MAX ? REALSXP : INTSXP, count));
    R_xlen_t k = 0;
    for (R_xlen_t i = 0; i < n && k < count; i++) {
        double t = mapped(tv, i, t_lut, nt, t_lo, &bad);
        double b = mapped(bv, i, b_lut, nb, b_lo, &bad);
        if (upper ? t > b : t < b) {
            if (TYPEOF(res) == INTSXP) INTEGER(res)[k++] = (int) (i + 1);
            else REAL(res)[k++] = (double) (i + 1);
        }
    }
    UNPROTECT(1);
    return res;
}
