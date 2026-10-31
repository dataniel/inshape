#' Add status from spell data to a panel you already have
#'
#' [spells_to_panel()] builds a panel from spells. Often the panel already
#' exists, e.g. a population with one row per person and year, or events with
#' a date, and the spell data should only add a status to it: was the person
#' enrolled at the end of the year, on leave on the day of the diagnosis?
#' `add_spell_status()` looks up the spell covering each row's point in time
#' and adds its status as new column(s).
#'
#' It exists because an interval join, e.g. `dplyr::left_join()` with
#' `join_by(between())`, goes wrong exactly where register data is messy:
#' overlapping spells duplicate panel rows silently, an ongoing spell with a
#' missing end matches nothing, and an outcome (passed, dropped out) cannot
#' be carried forward. Here the rows of `data` are never added, dropped or
#' reordered, and the rules are those of [spells_to_panel()]: on a yearly
#' panel, `add_spell_status(panel, spells, cpr, year, ...)` gives the same
#' primo and ultimo status as [spells_to_panel()] joined on `cpr` and `year`.
#'
#' The point in time comes from `at`:
#'
#' * A **Date** column: the status on that day, one new column.
#' * A **year** column (with `by = "year"`), or a year and a quarter or month
#'   column (with `by = "quarter"` or `"month"`): the status at primo and/or
#'   ultimo of the period, chosen with `when`. Primo follows `primo`, as in
#'   [spells_to_panel()].
#'
#' `status_is`, `ongoing` and the treatment of overlapping spells are as in
#' [spells_to_panel()]: the latest start wins, with a message counting the
#' points where this happened. Use `overlap = "error"` to stop instead, e.g.
#' in a pipeline that must fail hard. Rows whose unit has no spells, or whose
#' point is missing, get `NA`. Spells with a missing start, or an end before
#' the start, are dropped with a message.
#'
#' @param data A data frame or tibble, e.g. a panel with one row per unit and
#'   period. Its rows and columns are kept as they are.
#' @param spells A data frame with one row per spell.
#' @param id Column(s) identifying the unit (tidy-select, in `data`), e.g.
#'   `cpr`. `spells` must have columns of the same names; rename first if not.
#' @param at Column(s) in `data` with the point in time: a Date column, or a
#'   year column, or a year and a quarter/month column. See Details.
#' @param start,end,status Columns in `spells`, as in [spells_to_panel()].
#' @param by Period of `at` when it is not a date: `"year"`, `"quarter"` or
#'   `"month"`. Ignored for a Date `at`.
#' @param when For periods: `"both"` (default) adds a primo and an ultimo
#'   column, `"primo"` or `"ultimo"` adds one. Ignored for a Date `at`.
#' @param status_is,ongoing,primo As in [spells_to_panel()].
#' @param overlap `"latest_start"` (default) or `"error"`. Only state mode
#'   checks overlaps; in outcome mode the most recently ended spell decides.
#' @param name Name of the new column. Defaults to the name of `status`, with
#'   `_primo` and `_ultimo` appended for periods. With `when = "both"`, `name`
#'   is the prefix for the two columns.
#'
#' @return `data` with the new column(s) added at the end, same class.
#'
#' @examples
#' education <- data.frame(
#'   cpr    = c("a", "a", "b"),
#'   start  = as.Date(c("2018-08-15", "2021-08-15", "2019-08-15")),
#'   end    = as.Date(c("2021-06-20", NA,           "2020-03-01")),
#'   status = c("passed", "in progress", "dropped out")
#' )
#' population <- data.frame(cpr = c("a", "a", "b", "c"),
#'                          year = c(2020, 2021, 2020, 2020))
#'
#' # primo and ultimo status for each person and year
#' add_spell_status(population, education, cpr, year, start, end, status,
#'                  status_is = "outcome", ongoing = "in progress")
#'
#' # status on the day of an event
#' events <- data.frame(cpr = c("a", "b"),
#'                      date = as.Date(c("2019-05-01", "2021-01-01")))
#' add_spell_status(events, education, cpr, date, start, end, status,
#'                  status_is = "outcome", ongoing = "in progress",
#'                  name = "education")
#'
#' @seealso [spells_to_panel()] to build the panel from the spells,
#'   `ensure_no_overlap()` to check the spells first.
#'
#' @export
add_spell_status <- function(data, spells, id, at, start, end, status,
                             by        = c("year", "quarter", "month"),
                             when      = c("both", "primo", "ultimo"),
                             status_is = c("state", "outcome"),
                             ongoing   = "ongoing",
                             primo     = c("previous_ultimo", "first_day"),
                             overlap   = c("latest_start", "error"),
                             name      = NULL) {

  check_data_frame(data)
  check_data_frame(spells)
  by        <- rlang::arg_match(by)
  when      <- rlang::arg_match(when)
  status_is <- rlang::arg_match(status_is)
  primo     <- rlang::arg_match(primo)
  overlap   <- rlang::arg_match(overlap)
  ids        <- names(dplyr::select(data, {{ id }}))
  at_cols    <- names(dplyr::select(data, {{ at }}))
  start_col  <- names(dplyr::select(spells, {{ start }}))
  end_col    <- names(dplyr::select(spells, {{ end }}))
  status_col <- names(dplyr::select(spells, {{ status }}))
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  for (arg in c("start", "end", "status")) {
    if (length(get(paste0(arg, "_col"))) != 1) {
      cli::cli_abort("{.arg {arg}} must select exactly one column.")
    }
  }
  missing_ids <- setdiff(ids, names(spells))
  if (length(missing_ids)) {
    cli::cli_abort(c("{.arg spells} has no {cli::qty(missing_ids)}column{?s} {.var {missing_ids}}.",
                     "i" = "The {.arg id} columns must have the same names in both; rename first."))
  }
  if (status_is == "outcome" && (!rlang::is_scalar_atomic(ongoing) || is.na(ongoing))) {
    cli::cli_abort("{.arg ongoing} must be a single non-missing value.")
  }
  if (!is.null(name) && !rlang::is_string(name)) {
    cli::cli_abort("{.arg name} must be a single string.")
  }

  points <- spell_points(data, at_cols, by, when, primo)
  base <- name %||% status_col
  out_names <- if (length(points) == 2) paste0(base, c("_primo", "_ultimo")) else
    if (inherits(data[[at_cols[1]]], c("Date", "POSIXt")) || !is.null(name)) base else
      paste0(base, "_", when)
  clash <- intersect(out_names, names(data))
  if (length(clash)) {
    cli::cli_abort(c("{cli::qty(clash)}Column{?s} {.var {clash}} already exist{?s/} in {.arg data}.",
                     "i" = "Choose another {.arg name}."))
  }

  prep <- prepare_spells(spells, ids, start_col, end_col)
  keys <- prep$keys

  # The spell unit of each row of data, NA when the unit has no spells
  units <- keys[prep$first, ids, with = FALSE]
  data.table::set(units, j = ".unit", value = seq_along(prep$first))
  rows <- data.table::as.data.table(data)[, ids, with = FALSE]
  unit_of <- units[rows, on = ids, .unit]

  values <- spells[[status_col]][keys$.row]
  ambiguous <- 0L
  new <- lapply(points, function(day) {
    ok  <- which(!is.na(unit_of) & !is.na(day))
    ord <- ok[order(unit_of[ok], day[ok])]
    qgroups <- c(0L, cumsum(tabulate(unit_of[ord], nbins = length(prep$first))))
    res <- .Call(C_lustrum_spell_lookup, keys$.start, keys$.end,
                 as.integer(prep$groups), as.integer(qgroups),
                 as.integer(day[ord]), status_is == "outcome")
    ambiguous <<- ambiguous + res[[2]]
    idx <- rep(NA_integer_, nrow(data))
    idx[ord] <- res[[1]]
    status_values(values, idx, status_is, ongoing)
  })

  if (status_is == "state" && ambiguous > 0) {
    msg <- "{ambiguous} point{?s} fell in overlapping spells"
    if (overlap == "error") {
      cli::cli_abort(c(paste0(msg, "."), "i" = "Find the spells with {.fn ensure_no_overlap}."))
    }
    cli::cli_alert_warning(paste0(msg, "; the latest start was used. See {.fn ensure_no_overlap}."))
  }

  result <- if (data.table::is.data.table(data)) data.table::copy(data) else data
  for (i in seq_along(new)) result[[out_names[i]]] <- new[[i]]
  result
}

# Lookup days (integer) for each row of data: one vector for a Date `at`,
# else primo and/or ultimo of the period
spell_points <- function(data, at_cols, by, when, primo) {
  if (length(at_cols) == 1 && inherits(data[[at_cols]], c("Date", "POSIXt"))) {
    return(list(spell_days(data[[at_cols]], at_cols)))
  }
  n_cols <- if (by == "year") 1L else 2L
  if (length(at_cols) != n_cols) {
    cli::cli_abort(c("{.arg at} must select a Date column, or {.val {n_cols}} column{?s} for {.code by = \"{by}\"}.",
                     "i" = if (by == "year") "For quarters or months, set {.arg by} and select the year and the sub-period, e.g. {.code c(year, quarter)}."
                           else "Select the year and the {by}, e.g. {.code c(year, {by})}."))
  }
  per_year <- c(year = 1L, quarter = 4L, month = 12L)[[by]]
  year <- whole_numbers(data[[at_cols[1]]], at_cols[1], 1, 9999)
  sub  <- if (n_cols == 2) whole_numbers(data[[at_cols[2]]], at_cols[2], 1, per_year) else 1L
  code <- year * per_year + sub - 1L

  first_day <- codes_first_day(code, per_year)
  ultimo    <- codes_first_day(code + 1L, per_year) - 1L
  primo_day <- if (primo == "first_day") first_day else first_day - 1L
  switch(when, both = list(primo_day, ultimo), primo = list(primo_day),
         ultimo = list(ultimo))
}

whole_numbers <- function(x, col, lo, hi) {
  if (!is.numeric(x) || is.object(x) ||
      any(!is.na(x) & (x != round(x) | x < lo | x > hi))) {
    cli::cli_abort("{.var {col}} must contain whole numbers from {lo} to {hi}.")
  }
  as.integer(x)
}

# period_first_day() for codes that may be missing; converts unique codes only
codes_first_day <- function(code, per_year) {
  u <- unique(code[!is.na(code)])
  period_first_day(u, per_year)[match(code, u)]
}
