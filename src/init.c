#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

SEXP lustrum_dense_ids(SEXP, SEXP);
SEXP lustrum_first_rows(SEXP, SEXP);
SEXP lustrum_fingerprint(SEXP, SEXP);
SEXP lustrum_varying_units(SEXP, SEXP, SEXP);
SEXP lustrum_outside(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
SEXP lustrum_pair_changes(SEXP, SEXP, SEXP, SEXP);
SEXP lustrum_panel_scan(SEXP, SEXP, SEXP, SEXP, SEXP);
SEXP lustrum_panel_missing(SEXP, SEXP, SEXP, SEXP, SEXP);
SEXP lustrum_spell_status(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
SEXP lustrum_spell_lookup(SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
SEXP lustrum_spell_relations(SEXP, SEXP, SEXP);

static const R_CallMethodDef call_methods[] = {
    {"lustrum_dense_ids", (DL_FUNC) &lustrum_dense_ids, 2},
    {"lustrum_first_rows", (DL_FUNC) &lustrum_first_rows, 2},
    {"lustrum_fingerprint", (DL_FUNC) &lustrum_fingerprint, 2},
    {"lustrum_varying_units", (DL_FUNC) &lustrum_varying_units, 3},
    {"lustrum_outside", (DL_FUNC) &lustrum_outside, 7},
    {"lustrum_pair_changes", (DL_FUNC) &lustrum_pair_changes, 4},
    {"lustrum_panel_scan", (DL_FUNC) &lustrum_panel_scan, 5},
    {"lustrum_panel_missing", (DL_FUNC) &lustrum_panel_missing, 5},
    {"lustrum_spell_status", (DL_FUNC) &lustrum_spell_status, 8},
    {"lustrum_spell_lookup", (DL_FUNC) &lustrum_spell_lookup, 6},
    {"lustrum_spell_relations", (DL_FUNC) &lustrum_spell_relations, 3},
    {NULL, NULL, 0}
};

void attribute_visible R_init_lustrum(DllInfo *dll) {
    R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
