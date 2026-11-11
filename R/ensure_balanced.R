#' Assert that a panel is balanced, or has no gaps
#'
#' A checkpoint for register panels: every unit (person, company, workplace)
#' must be observed in every period. Missing unit-periods are the violation
#' set, so a failure lists exactly which units lack which periods. Returns
#' `data`, so it can sit in the middle of a pipeline.
#'
#' Register populations are rarely fully balanced: people are born, die and
#' migrate, and firms open and close. `gaps_only = TRUE` relaxes the rule to
#' what usually *should* hold: a unit may enter late and leave early, but
#' once present it must not skip a period between its first and last. A
#' person present in 2019 and 2021 but missing in 2020 is then a gap; a
#' person first seen in 2021 is not.
#'
#' ## What counts as a period
#'
#' By default the expected periods are those observed anywhere in the data.
#' A period missing for *every* unit (e.g. a year that was never loaded) is
#' therefore invisible. Pass the periods you expect, e.g.
#' `periods = 2015:2024`, to catch that too. Observations outside `periods`
#' are ignored, as are rows with a missing period.
#'
#' Duplicated unit-periods do not make a panel unbalanced, but they are
#' usually an error of their own: check them with
#' [ensure_unique()]`(data, id, time)`.
#'
#' The check scales to full-population registers: the unit-period grid is
#' only built for units that actually lack a period.
#'
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr` or
#'   `c(cvr, lbnr)`.
#' @param time The period column (one column), e.g. `year`. Any type that
#'   sorts, such as integer years or dates.
#' @param periods Expected periods. Defaults to the periods observed in
#'   `data`.
#' @param gaps_only If `FALSE` (default), every unit must be observed in every
#'   period. If `TRUE`, only periods between a unit's first and last
#'   observation are required.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when unit-periods are missing
#'   and no `abort_msg` is set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' panel <- data.frame(
#'   cpr  = c("a", "a", "a", "b", "b", "c"),
#'   year = c(2020, 2021, 2022, 2020, 2022, 2022)
#' )
#'
#' # Not balanced: b lacks 2021, c lacks 2020 and 2021
#' ensure_balanced(panel, cpr, year)
#'
#' # Only gaps: b lacks 2021; c simply entered in 2022
#' ensure_balanced(panel, cpr, year, gaps_only = TRUE)
#'
#' # A year missing for everyone is only found with explicit periods
#' ensure_balanced(panel, cpr, year, periods = 2019:2022, gaps_only = TRUE)
#'
#' @seealso [ensure_unique()] for duplicated unit-periods,
#'   [ensure_no_overlap()] for spell data, [checkpoints] for messages and personal data.
#'
#' @export
ensure_balanced <- function(data, id, time,
                            periods     = NULL,
                            gaps_only   = FALSE,
                            success_msg = NULL,
                            warn_msg    = NULL,
                            abort_msg   = NULL) {

  tbl      <- check_table(data)
  ids      <- select_names(tbl, {{ id }})
  time_col <- select_names(tbl, {{ time }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(time_col) != 1) cli::cli_abort("{.arg time} must select exactly one column.")

  missing_periods <- if (is_remote(tbl)) {
    remote_panel_gaps(tbl, ids, time_col, periods, gaps_only)
  } else {
    find_panel_gaps(data, ids, time_col, periods, gaps_only)
  }

  what <- if (gaps_only) "Gaps in panel" else "Panel is not balanced"
  report_check(
    missing_periods,
    pass = if (gaps_only) paste0("No gaps in ", time_col, " per ", toString(ids))
           else paste0("Balanced panel: ", toString(ids), " by ", time_col),
    fail = paste0(what, ": missing ", toString(ids), "-", time_col, " combinations"),
    success_msg, warn_msg, abort_msg
  )
  invisible(data)
}

# Unit-periods that should exist but don't, as a tibble of id + time columns,
# from the panel engine (see panel_cells()). A repeated unit-period counts
# once, and units without observed periods are skipped. Only the missing
# unit-periods, usually few, are sorted at the end.
find_panel_gaps <- function(data, ids, time_col, periods, gaps_only) {
  ix    <- panel_index(data, ids, time_col, periods)
  cells <- panel_cells(ix)
  n_per <- length(ix$periods)

  lo  <- if (gaps_only) cells$lo else rep(1L, ix$n_units)
  hi  <- if (gaps_only) cells$hi else rep(n_per, ix$n_units)
  bad <- which(cells$n_seen > 0L & cells$n_seen < hi - lo + 1L)
  gone <- cells$missing(bad, lo[bad], hi[bad])

  first <- first_row_by(ix$unit, ix$n_units)[gone[[1]]]
  grid  <- data.table::setDT(lapply(unclass(data)[ids], `[`, first))
  data.table::set(grid, j = time_col, value = ix$periods[gone[[2]]])
  data.table::setorderv(grid, c(ids, time_col))
  tibble::as_tibble(grid)
}
