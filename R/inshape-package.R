#' inshape: checks for register microdata
#'
#' Register microdata comes in a few shapes: one row per unit, one row per
#' unit and period (a panel), or one row per spell with a start and an end.
#' Every analysis assumes the shape is right: no duplicated persons, no
#' missing years in the middle of a panel, no person with two addresses at
#' once. inshape checks those assumptions, fast enough for full-population
#' registers. See `vignette("inshape")`.
#'
#' ## The name
#'
#' Register data has a shape, and an analysis is written for one of them.
#' inshape asks whether the data is *in shape*, the shape the analysis
#' assumes: are the keys unique, the panels whole, the spells consistent,
#' before anyone builds on them?
#'
#' ## Where to start
#'
#' * [describe_key()], [describe_panel()], [describe_spells()],
#'   [describe_varying()] and [describe_codes()]: look at the structure
#'   before choosing a rule.
#' * [describe_changes()]: what changed since the last extract.
#' * [describe_match()]: what a join of two tables will do, before it is
#'   made.
#' * [ensure_unique()]: a key identifies each row.
#' * [ensure_complete()]: the columns an analysis cannot do without have no
#'   missing values.
#' * [ensure_balanced()]: every unit is observed in every period, or at
#'   least has no gaps.
#' * [ensure_valid_spells()]: a spell has a start and does not end before it.
#' * [ensure_no_overlap()]: a unit is in one spell at a time.
#' * [ensure_no_gaps()]: and in one all the time, without a break between
#'   its spells.
#' * [ensure_constant()]: sex, birth date and the like do not change within a
#'   unit.
#' * [ensure_within()]: no one is observed after death or emigration, or
#'   before birth.
#' * [ensure_codes()]: a coded column holds only codes from the code list,
#'   valid at the time of the row.
#' * [ensure_matched()]: every key occurs in a reference register.
#' * [ensure_none()], [ensure_all()] and [ensure_empty()]: any other rule
#'   dplyr can express, such as no negative amounts.
#' * [tally_violations()]: count many rules at once, without judging.
#' * [violations()]: the rows that break a check, all of them.
#' * [merge_spells()]: one spell recorded as several, merged into one.
#' * [spells_to_panel()] and [add_spell_status()]: from spells to a panel.
#'
#' The `ensure_*()` functions are checkpoints: they warn or abort with the
#' offending rows and return the data, so they sit in a pipeline. What they
#' share (messages, personal data, database tables) is described in
#' [checkpoints].
#'
#' ```r
#' persons |>
#'   ensure_unique(cpr, year, abort_msg = "Duplicate person-years") |>
#'   ensure_balanced(cpr, year, gaps_only = TRUE)
#'
#' gaps <- violations(ensure_balanced(persons, cpr, year, gaps_only = TRUE))
#' ```
#'
#' ## Why a package of its own
#'
#' The checkpoints and the spell conversions started in the daos package.
#' They moved here because they share an engine the rest of daos does not:
#' the grouping of keys such as cpr without sorting them, the compiled pass
#' over sorted spells, and one way of reporting a broken rule. The general
#' checkpoints, [ensure_none()], [ensure_all()], [ensure_empty()] and
#' [tally_violations()], spent a while in the expectr package and joined
#' the rest here, since they share the same contract, the same reporting
#' and the same dependencies.
#'
#' @keywords internal
"_PACKAGE"

#' @importFrom rlang %||% := .data
#' @useDynLib inshape, .registration = TRUE, .fixes = "C_"
NULL

# data.table only applies its own `[` syntax in packages that declare
# themselves aware of it; without an import from data.table, this does.
.datatable.aware <- TRUE

# data.table uses non-standard evaluation; declare its symbols so R CMD
# check does not flag them as undefined globals.
utils::globalVariables(c(".end", ".unit", ".start", "e"))
