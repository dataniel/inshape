#' lustrum: structure checks for register microdata
#'
#' Register microdata comes in a few shapes: one row per unit, one row per
#' unit and period (a panel), or one row per spell with a start and an end.
#' Every analysis assumes the shape is right: no duplicated persons, no
#' missing years in the middle of a panel, no person with two addresses at
#' once. lustrum checks those assumptions, fast enough for full-population
#' registers. See `vignette("lustrum")`.
#'
#' ## The name
#'
#' In Rome the censors registered every citizen, and each census was closed
#' by the *lustrum*: a ceremony that purified the people just counted,
#' before the register was accepted. This package is that last step for
#' register data, a registration of the registrations: are the keys
#' unique, the panels whole, the spells consistent, before anyone builds on
#' them? The word also came to mean the five-year period between two
#' censuses, which suits a package about periods.
#'
#' ## Where to start
#'
#' * [describe_key()], [describe_panel()], [describe_spells()] and
#'   [describe_varying()]: look at the structure before choosing a rule.
#' * [ensure_unique()]: a key identifies each row.
#' * [ensure_balanced()]: every unit is observed in every period, or at
#'   least has no gaps.
#' * [ensure_no_overlap()]: a unit is in one spell at a time.
#' * [ensure_constant()]: sex, birth date and the like do not change within a
#'   unit.
#' * [merge_spells()]: one spell recorded as several, merged into one.
#' * [spells_to_panel()] and [add_spell_status()]: from spells to a panel.
#'
#' The `ensure_*()` functions are checkpoints: they warn or abort with the
#' offending rows and return the data, so they sit in a pipeline. What they
#' share (messages, logging, dumps, database tables) is described in
#' [checkpoints].
#'
#' ## Why a package of its own
#'
#' The key, panel and spell checks started in the expectr package and the
#' spell conversions in daos. They moved here because they share an engine
#' the rest does not: the grouping of keys such as cpr without sorting
#' them, and the compiled pass over sorted spells. expectr keeps the
#' general checkpoints (`expect_empty()`, `expect_none()`), and the two
#' packages do not depend on each other; the `ensure_` prefix keeps their
#' functions apart in a script that uses both.
#'
#' @keywords internal
"_PACKAGE"

#' @importFrom rlang %||% := .data
#' @useDynLib lustrum, .registration = TRUE, .fixes = "C_"
NULL

# data.table only applies its own `[` syntax in packages that declare
# themselves aware of it; without an import from data.table, this does.
.datatable.aware <- TRUE

# data.table uses non-standard evaluation; declare its symbols so R CMD
# check does not flag them as undefined globals.
utils::globalVariables(c(".end", ".unit", ".start", "e"))
