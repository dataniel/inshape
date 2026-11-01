#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

SEXP inshape_dense_ids(SEXP, SEXP);
SEXP inshape_first_rows(SEXP, SEXP);
SEXP inshape_varying_units(SEXP, SEXP, SEXP);
SEXP inshape_outside(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
SEXP inshape_pair_changes(SEXP, SEXP, SEXP, SEXP);
SEXP inshape_panel_scan(SEXP, SEXP, SEXP, SEXP, SEXP);
SEXP inshape_panel_missing(SEXP, SEXP, SEXP, SEXP, SEXP);
SEXP inshape_spell_status(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
SEXP inshape_spell_lookup(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
SEXP inshape_spell_relations(SEXP, SEXP, SEXP);

static const R_CallMethodDef call_methods[] = {
    {"inshape_dense_ids", (DL_FUNC) &inshape_dense_ids, 2},
    {"inshape_first_rows", (DL_FUNC) &inshape_first_rows, 2},
    {"inshape_varying_units", (DL_FUNC) &inshape_varying_units, 3},
    {"inshape_outside", (DL_FUNC) &inshape_outside, 7},
    {"inshape_pair_changes", (DL_FUNC) &inshape_pair_changes, 4},
    {"inshape_panel_scan", (DL_FUNC) &inshape_panel_scan, 5},
    {"inshape_panel_missing", (DL_FUNC) &inshape_panel_missing, 5},
    {"inshape_spell_status", (DL_FUNC) &inshape_spell_status, 8},
    {"inshape_spell_lookup", (DL_FUNC) &inshape_spell_lookup, 6},
    {"inshape_spell_relations", (DL_FUNC) &inshape_spell_relations, 3},
    {NULL, NULL, 0}
};

void attribute_visible R_init_inshape(DllInfo *dll) {
    R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
