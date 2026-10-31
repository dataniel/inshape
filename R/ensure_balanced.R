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
#' @param warn_msg Message shown (and logged) when unit-periods are missing
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
#'   [ensure_no_overlap()] for spell data, [checkpoints] for logging and dumps.
#'
#' @export
ensure_balanced <- function(data, id, time,
                            periods     = NULL,
                            gaps_only   = FALSE,
                            success_msg = NULL,
                            warn_msg    = NULL,
                            abort_msg   = NULL,
                            log         = getOption("lustrum.log"),
                            dump        = getOption("lustrum.dump")) {

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

  what  <- if (gaps_only) "Gaps in panel" else "Panel is not balanced"
  label <- abort_msg %||% warn_msg
  report_check(
    violations  = missing_periods,
    success_msg = success_msg %||%
      if (!is.null(label)) paste0("Check passed: ", label)
      else if (gaps_only) paste0("No gaps in ", time_col, " per ", toString(ids))
      else paste0("Balanced panel: ", toString(ids), " by ", time_col),
    fail_msg    = label %||%
      paste0(what, ": missing ", toString(ids), "-", time_col, " combinations"),
    abort       = !is.null(abort_msg),
    log         = log,
    dump        = dump
  )
  invisible(data)
}

# Unit-periods that should exist but don't, as a tibble of id + time columns.
#
# Nothing is sorted on the id columns, the expensive step on a population of
# persons: units get integer ids (see group_ids()), periods their position,
# and the counts, first and last periods per unit are vectorised. Only the
# missing unit-periods, usually few, are sorted at the end.
find_panel_gaps <- function(data, ids, time_col, periods, gaps_only) {
  time <- data[[time_col]]
  keep <- !is.na(time)
  if (is.null(periods)) {
    periods <- sort(unique(time[keep]))
  } else {
    periods <- sort(unique(periods))
    keep <- keep & time %in% periods
  }
  rows    <- which(keep)
  unit    <- group_ids(data, ids)
  n_units <- attr(unit, "n")
  unit    <- unit[rows]
  pos     <- match(time[rows], periods)

  # A repeated unit-period counts once. Ids of units without kept rows have
  # no count and are skipped.
  pair    <- (unit - 1) * length(periods) + pos
  n_seen  <- tabulate(unit[!duplicated(pair)], n_units)

  lo  <- if (gaps_only) min_by(pos, unit, n_units) else rep(1L, n_units)
  hi  <- if (gaps_only) max_by(pos, unit, n_units) else rep(length(periods), n_units)
  bad <- which(n_seen > 0L & n_seen < hi - lo + 1L)

  # The expected unit-periods of the incomplete units, minus those observed
  span      <- hi[bad] - lo[bad] + 1L
  want_unit <- rep(bad, times = span)
  want_pos  <- sequence(span, from = lo[bad])
  is_bad    <- logical(n_units)
  is_bad[bad] <- TRUE
  missing   <- !((want_unit - 1) * length(periods) + want_pos) %in% pair[is_bad[unit]]

  first <- rows[first_row_by(unit, n_units)[want_unit[missing]]]
  grid  <- data.table::setDT(lapply(unclass(data)[ids], `[`, first))
  data.table::set(grid, j = time_col, value = periods[want_pos[missing]])
  data.table::setorderv(grid, c(ids, time_col))
  tibble::as_tibble(grid)
}
