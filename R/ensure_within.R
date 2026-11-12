#' Assert that observations lie within each unit's lifetime
#'
#' A checkpoint for rows that cannot exist: a person observed after death,
#' after emigrating, or before being born; a company with income after it
#' was dissolved. They come from linking registers updated at different
#' times, and from late corrections: a death registered after the extract
#' was made. Each row's `time` must lie within its own `from` and `to`,
#' columns of the data such as the birth date and the date of death. On
#' failure the offending rows are reported with an `outside` column
#' prepended that says which bound they break. Returns `data`, so it can sit
#' in the middle of a pipeline.
#'
#' A missing bound is open: a person without a date of death is alive, and
#' rows with a missing `time` are not checked. Bounds are inclusive, so an
#' observation on the day of death is within.
#'
#' ## Years against dates
#'
#' `time` and the bounds may be dates or whole numbers such as years, in any
#' combination. When one side is a year and the other a date, the date
#' counts by its year: a yearly panel row for 2024 is within for a person
#' who died in March 2024, and outside for one who died in 2023. Two dates
#' are compared by day, and two numbers as they are.
#'
#' ## Bounds from another register
#'
#' The bounds usually come from the population register, not from the data
#' being checked. Join them on first:
#'
#' ```r
#' income |>
#'   dplyr::left_join(population, by = "cpr") |>
#'   ensure_within(year, from = birth_date, to = death_date)
#' ```
#'
#' `to` is the final exit: death, or an emigration without return. A person
#' who emigrates and comes back has a residence history, not one exit date;
#' check rows against residence spells with [add_spell_status()] instead.
#'
#' @section Why it is fast:
#' Each bound is one compiled pass over the rows that returns only the rows
#' outside it, with no vector as long as the data in between. A year meets
#' a date through a table of the few years present, so the dates are never
#' converted to years.
#'
#' @param time Column with the period or date of each row (tidy-select),
#'   e.g. `year`.
#' @param from,to Columns with the first and last period or date the unit
#'   can be observed, e.g. `birth_date` and `death_date`. At least one is
#'   required.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when rows lie outside and no
#'   `abort_msg` is set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' panel <- data.frame(
#'   cpr   = c("a", "a", "a", "b", "b"),
#'   year  = c(2022, 2023, 2024, 2022, 2023),
#'   born  = as.Date(c("1950-04-01", "1950-04-01", "1950-04-01",
#'                     "2023-01-10", "2023-01-10")),
#'   death = as.Date(c("2023-05-01", "2023-05-01", "2023-05-01", NA, NA))
#' )
#' # a has a row after the year of death, b one before birth
#' ensure_within(panel, year, from = born, to = death)
#'
#' @seealso [checkpoints], [describe_panel()] for entries and exits per
#'   period.
#'
#' @export
ensure_within <- function(data, time, from = NULL, to = NULL,
                          success_msg = NULL,
                          warn_msg    = NULL,
                          abort_msg   = NULL) {

  tbl      <- check_table(data)
  time_col <- select_names(tbl, {{ time }})
  from_col <- select_names(tbl, {{ from }})
  to_col   <- select_names(tbl, {{ to }})
  if (length(time_col) != 1) cli::cli_abort("{.arg time} must select exactly one column.")
  if (length(from_col) > 1 || length(to_col) > 1) {
    cli::cli_abort("{.arg from} and {.arg to} must each select at most one column.")
  }
  if (length(from_col) + length(to_col) == 0) {
    cli::cli_abort("Give {.arg from}, {.arg to} or both.")
  }

  rows <- if (is_remote(tbl)) {
    remote_outside(tbl, time_col, from_col, to_col)
  } else {
    find_outside(data, time_col, from_col, to_col)
  }

  what <- if (length(from_col) == 0) paste(time_col, "until", to_col)
          else if (length(to_col) == 0) paste(time_col, "from", from_col)
          else paste(time_col, "within", from_col, "to", to_col)
  report_check(
    rows,
    pass = paste0("All rows: ", what),
    fail = paste0("Rows outside: ", what),
    success_msg, warn_msg, abort_msg,
    key   = c(time_col, from_col, to_col),
    group = diagnostic_name(tbl, "outside"),
    summary = function(v, n) {
      c(tally_line("Bounds broken", top_values(v, diagnostic_name(tbl, "outside"))),
        pattern_lines(v, time_col, n))
    }
  )
  invisible(data)
}

# Rows outside their bounds, in the order of the data, with `outside`
# naming the bound broken. which() skips the NA of a missing time or bound,
# so missing bounds are open without a test of their own. A row before
# `from` and after `to` at once (from after to) is reported as before.
find_outside <- function(data, time_col, from_col, to_col) {
  time <- data[[time_col]]
  before <- after <- integer()
  if (length(from_col)) {
    before <- outside_rows(time, data[[from_col]], "from", time_col, from_col)
  }
  if (length(to_col)) {
    after <- outside_rows(time, data[[to_col]], "to", time_col, to_col)
    if (length(before)) after <- after[!after %in% before]
  }
  hit <- c(before, after)
  o <- order(hit, method = "radix")
  out <- tibble::as_tibble(data)[hit[o], ]
  outside <- c(rep(paste("before", from_col), length(before)),
               rep(paste("after", to_col), length(after)))
  tibble::add_column(out, !!diagnostic_name(data, "outside") := outside[o], .before = 1)
}

# Rows where time is before (side "from") or after (side "to") the bound,
# found in one compiled pass (src/within.c). Two dates are compared by day
# and two numbers as they are. When one is a year and the other a date,
# the year becomes a day through a table of the years present: the last
# day of the year against a lower bound (a year is before birth only if
# all of it is), the first day against an upper bound. That converts the
# few distinct years, never the millions of dates.
outside_rows <- function(time, bound, side, time_col, bound_col, call = rlang::caller_env()) {
  t_date <- inherits(time, c("Date", "POSIXt"))
  b_date <- inherits(bound, c("Date", "POSIXt"))
  t <- if (t_date) date_days(time) else numbers_or_abort(time, time_col, call)
  b <- if (b_date) date_days(bound) else numbers_or_abort(bound, bound_col, call)
  t_lut <- b_lut <- NULL
  t_lo <- b_lo <- 0
  if (b_date && !t_date) {
    t_lo  <- year_floor(t)
    t_lut <- year_days(t, t_lo, last = side == "from")
  }
  if (t_date && !b_date) {
    b_lo  <- year_floor(b)
    b_lut <- year_days(b, b_lo, last = side == "to")
  }
  rows <- .Call(C_inshape_outside, t, b, side == "to", t_lut, t_lo, b_lut, b_lo)
  if (is.null(rows)) {
    col <- if (is.null(t_lut)) bound_col else time_col
    cli::cli_abort("{.var {col}} is compared with dates, so it must hold whole years.",
                   call = call)
  }
  rows
}

date_days <- function(x) {
  if (inherits(x, "POSIXt")) x <- as.Date(x)
  unclass(x)
}

numbers_or_abort <- function(x, col, call) {
  if (!is.numeric(x) || is.object(x)) {
    cli::cli_abort("{.var {col}} must be a Date column or whole numbers such as years, not {.cls {class(x)[1]}}.",
                   call = call)
  }
  x
}

year_floor <- function(years) {
  lo <- suppressWarnings(min(years, na.rm = TRUE))
  if (is.finite(lo)) floor(lo) else 0
}

# Days since 1970-01-01 of the first (or last) day of each year from `lo`
# to the largest year present: the table outside_rows() looks years up in
year_days <- function(years, lo, last) {
  hi <- suppressWarnings(max(years, na.rm = TRUE))
  if (!is.finite(hi)) return(numeric())
  if (hi - lo > 1e5) cli::cli_abort("Years must lie within 100,000 years of each other.")
  first <- unclass(as.Date(sprintf("%04d-01-01", as.integer(seq(lo, floor(hi) + 1)))))
  as.double(if (last) first[-1] - 1 else first[-length(first)])
}
