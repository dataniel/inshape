#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <limits.h>

/* Status of each unit at the primo and ultimo point of each period.

   Spells arrive sorted by (unit, start) with dates as integer days. For each
   spell we keep the running maximum of end dates within its unit (cm) and the
   index of the spell that holds it (cmi, ties to the later start). With p the
   number of the unit's spells started on or before a point t:

     cm[p-1] >= t  some spell covers t (closed intervals)
     cm[p-1] >  t  some spell is still ongoing at t (outcome mode)
     cmi[p-1]      otherwise the spell that ended most recently

   Points only increase within a unit, so p is advanced by a pointer and the
   whole pass is linear in spells + output rows.

   Returned indices are 1-based into the sorted spells; 0 means "ongoing"
   (outcome mode) and NA means no status. */

static int status_at(int t, int g0, int p, const int *e, const int *cm,
                     const int *cmi, int outcome, int *ambiguous) {
    if (p == g0) return NA_INTEGER;
    int last = p - 1;
    if (outcome) {
        if (cm[last] > t) return 0;
        return cmi[last] + 1;
    }
    if (cm[last] < t) return NA_INTEGER;
    /* Latest start among the covering spells; earlier spells cannot cover t
       once the running maximum of their ends falls below t. */
    for (int i = last; i >= g0; i--) {
        if (cm[i] < t) break;
        if (e[i] >= t) {
            if (i > g0 && cm[i - 1] >= t) (*ambiguous)++;
            return i + 1;
        }
    }
    return NA_INTEGER;
}

/* Ends with NA as INT_MAX, and the running maximum of ends per unit */
static void running_max(const int *e_in, const int *g, R_xlen_t n_groups,
                        int *e, int *cm, int *cmi) {
    for (R_xlen_t k = 0; k < n_groups; k++) {
        for (int i = g[k]; i < g[k + 1]; i++) {
            e[i] = e_in[i] == NA_INTEGER ? INT_MAX : e_in[i];
            if (i == g[k] || e[i] >= cm[i - 1]) {
                cm[i] = e[i];
                cmi[i] = i;
            } else {
                cm[i] = cm[i - 1];
                cmi[i] = cmi[i - 1];
            }
        }
    }
}

SEXP lustrum_spell_status(SEXP start, SEXP end, SEXP groups, SEXP lo, SEXP hi,
                       SEXP primo, SEXP ultimo, SEXP outcome_) {
    const int *s = INTEGER(start), *e_in = INTEGER(end), *g = INTEGER(groups);
    const int *glo = INTEGER(lo), *ghi = INTEGER(hi);
    const int *pp = INTEGER(primo), *pu = INTEGER(ultimo);
    int outcome = Rf_asLogical(outcome_);
    R_xlen_t n = XLENGTH(start);
    R_xlen_t n_groups = XLENGTH(lo);

    R_xlen_t n_out = 0;
    for (R_xlen_t k = 0; k < n_groups; k++) {
        if (ghi[k] >= glo[k]) n_out += (R_xlen_t) ghi[k] - glo[k] + 1;
    }

    int *e  = (int *) R_alloc(n > 0 ? n : 1, sizeof(int));
    int *cm = (int *) R_alloc(n > 0 ? n : 1, sizeof(int));
    int *cmi = (int *) R_alloc(n > 0 ? n : 1, sizeof(int));
    running_max(e_in, g, n_groups, e, cm, cmi);

    SEXP out = PROTECT(Rf_allocVector(VECSXP, 3));
    SEXP res_p = Rf_allocVector(INTSXP, n_out);
    SET_VECTOR_ELT(out, 0, res_p);
    SEXP res_u = Rf_allocVector(INTSXP, n_out);
    SET_VECTOR_ELT(out, 1, res_u);
    int *rp = INTEGER(res_p), *ru = INTEGER(res_u);

    int ambiguous = 0;
    R_xlen_t row = 0;
    for (R_xlen_t k = 0; k < n_groups; k++) {
        int g0 = g[k], g1 = g[k + 1], p = g0;
        for (int j = glo[k]; j <= ghi[k]; j++) {
            int t = pp[j];
            while (p < g1 && s[p] <= t) p++;
            rp[row] = status_at(t, g0, p, e, cm, cmi, outcome, &ambiguous);
            t = pu[j];
            while (p < g1 && s[p] <= t) p++;
            ru[row] = status_at(t, g0, p, e, cm, cmi, outcome, &ambiguous);
            row++;
        }
        if ((k & 1023) == 0) R_CheckUserInterrupt();
    }

    SET_VECTOR_ELT(out, 2, Rf_ScalarInteger(ambiguous));
    UNPROTECT(1);
    return out;
}

/* Status at arbitrary points, for add_spell_status(). Points arrive sorted
   by (unit, day); qgroups[k] .. qgroups[k + 1] - 1 are unit k's points, in
   the same unit order as the spell groups. Same pointer pass as above. */
SEXP lustrum_spell_lookup(SEXP start, SEXP end, SEXP groups, SEXP qgroups,
                       SEXP qday, SEXP outcome_) {
    const int *s = INTEGER(start), *e_in = INTEGER(end), *g = INTEGER(groups);
    const int *qg = INTEGER(qgroups), *qd = INTEGER(qday);
    int outcome = Rf_asLogical(outcome_);
    R_xlen_t n = XLENGTH(start);
    R_xlen_t n_groups = XLENGTH(groups) - 1;

    int *e  = (int *) R_alloc(n > 0 ? n : 1, sizeof(int));
    int *cm = (int *) R_alloc(n > 0 ? n : 1, sizeof(int));
    int *cmi = (int *) R_alloc(n > 0 ? n : 1, sizeof(int));
    running_max(e_in, g, n_groups, e, cm, cmi);

    SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
    SEXP res = Rf_allocVector(INTSXP, XLENGTH(qday));
    SET_VECTOR_ELT(out, 0, res);
    int *r = INTEGER(res);

    int ambiguous = 0;
    for (R_xlen_t k = 0; k < n_groups; k++) {
        int g0 = g[k], g1 = g[k + 1], p = g0;
        for (int j = qg[k]; j < qg[k + 1]; j++) {
            int t = qd[j];
            while (p < g1 && s[p] <= t) p++;
            r[j] = status_at(t, g0, p, e, cm, cmi, outcome, &ambiguous);
        }
        if ((k & 1023) == 0) R_CheckUserInterrupt();
    }

    SET_VECTOR_ELT(out, 1, Rf_ScalarInteger(ambiguous));
    UNPROTECT(1);
    return out;
}
