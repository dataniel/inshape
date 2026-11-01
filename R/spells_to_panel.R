#' Turn spell data into a period panel with primo and ultimo status
#'
#' Spell data has one row per spell: an education, an address, a benefit
#' period, with a start date, an end date and a status. Most analyses need it
#' as a panel instead: one row per unit and year (or quarter, or month), with
#' the status at the start and at the end of the period. `spells_to_panel()`
#' does that conversion.
#'
#' Two meanings of status are supported, because registers use both:
#'
#' * `status_is = "state"` (default): the status holds for the whole spell,
#'   e.g. enrolled, on leave. The status at a point is the status of the spell
#'   covering it, and `NA` if no spell does. Spells are closed intervals, as
#'   in `ensure_no_overlap()`.
#' * `status_is = "outcome"`: the status is what happened when the spell
#'   ended, e.g. passed or dropped out, as in education registers. While a
#'   spell is running (start <= point < end, or no end) the status is
#'   `ongoing`. From the end date on, the outcome of the most recently ended
#'   spell is carried forward until a new spell starts.
#'
#' Primo follows the register convention: by default primo of a period is
#' the last day of the previous period (31 December for years), so primo of
#' one year equals ultimo of the year before. Use `primo = "first_day"` for
#' 1 January.
#'
#' If spells overlap, the spell with the latest start decides the status. In
#' state mode, a message counts the points where this happened; find the
#' spells with `ensure_no_overlap()`. Rows with a missing start, or an end
#' before the start, are dropped with a message.
#'
#' @section Why it is fast:
#' Dates are converted to integer days, and spells are sorted once per unit
#' by start. A compiled pass keeps the running maximum of end dates within a
#' unit, so "is a spell running at this point?" and "which spell ended most
#' recently?" are constant-time lookups. Spells are never expanded to days or
#' periods, so the cost is one sort plus a linear pass over spells and output
#' rows.
#'
#' @param data A data frame or tibble with one row per spell.
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr`.
#' @param start,end Columns with the first and last day of each spell (Date).
#'   A missing `end` means an ongoing spell.
#' @param status Column with the status of each spell.
#' @param by Period length: `"year"`, `"quarter"` or `"month"`.
#' @param from,to First and last period in the panel, as a year (e.g. `2015`)
#'   or a Date in the period. When given, every unit gets the same window,
#'   which makes a balanced panel. When `NULL`, each unit runs from the
#'   period of its first start to the period of its last end; ongoing spells
#'   run to the latest date found in `start` and `end`.
#' @param status_is `"state"` or `"outcome"`, see Details.
#' @param ongoing Status shown while a spell is running when
#'   `status_is = "outcome"`, e.g. `"i gang"`.
#' @param primo `"previous_ultimo"` (default) or `"first_day"`.
#'
#' @return A tibble (a data.table if `data` is one) with the `id` columns,
#'   `year`, `quarter` or `month` for sub-year periods, and `primo` and
#'   `ultimo`. Rows are sorted by unit and period.
#'
#' @examples
#' education <- data.frame(
#'   cpr    = c("a", "a", "b"),
#'   start  = as.Date(c("2018-08-15", "2021-08-15", "2019-08-15")),
#'   end    = as.Date(c("2021-06-20", NA,           "2020-03-01")),
#'   status = c("passed", "in progress", "dropped out")
#' )
#'
#' # status describes the outcome at the end of each spell
#' spells_to_panel(education, cpr, start, end, status,
#'                 from = 2018, to = 2022,
#'                 status_is = "outcome", ongoing = "in progress")
#'
#' # status holds during the spell
#' leave <- data.frame(
#'   cpr    = "a",
#'   start  = as.Date(c("2020-01-01", "2020-09-01")),
#'   end    = as.Date(c("2020-08-31", "2021-03-31")),
#'   status = c("enrolled", "on leave")
#' )
#' spells_to_panel(leave, cpr, start, end, status, by = "quarter")
#'
#' @seealso `ensure_no_overlap()` to check spells first, `ensure_balanced()`
#'   to check the resulting panel.
#'
#' @export
spells_to_panel <- function(data, id, start, end, status,
                            by        = c("year", "quarter", "month"),
                            from      = NULL,
                            to        = NULL,
                            status_is = c("state", "outcome"),
                            ongoing   = "ongoing",
                            primo     = c("previous_ultimo", "first_day")) {

  check_data_frame(data)
  by        <- rlang::arg_match(by)
  status_is <- rlang::arg_match(status_is)
  primo     <- rlang::arg_match(primo)
  ids        <- names(dplyr::select(data, {{ id }}))
  start_col  <- names(dplyr::select(data, {{ start }}))
  end_col    <- names(dplyr::select(data, {{ end }}))
  status_col <- names(dplyr::select(data, {{ status }}))
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  for (arg in c("start", "end", "status")) {
    if (length(get(paste0(arg, "_col"))) != 1) {
      cli::cli_abort("{.arg {arg}} must select exactly one column.")
    }
  }
  if (status_is == "outcome" && (!rlang::is_scalar_atomic(ongoing) || is.na(ongoing))) {
    cli::cli_abort("{.arg ongoing} must be a single non-missing value.")
  }
  per_year  <- c(year = 1L, quarter = 4L, month = 12L)[[by]]
  out_names <- c(ids, unique(c("year", by)), "primo", "ultimo")
  if (anyDuplicated(out_names)) {
    clash <- intersect(ids, c("year", by, "primo", "ultimo"))
    cli::cli_abort(c("{cli::qty(clash)}{.arg id} column{?s} {.var {clash}} clash{?es/} with the output columns.",
                     "i" = "{cli::qty(clash)}Rename {?it/them} first."))
  }

  prep   <- prepare_spells(data, ids, start_col, end_col)
  keys   <- prep$keys
  unit   <- prep$unit
  first  <- prep$first
  groups <- prep$groups
  n      <- nrow(keys)

  # Period window per unit, as period codes (year * per_year + sub-period)
  last_day <- if (n) max(c(keys$.start, keys$.end), na.rm = TRUE) else NA_integer_
  # Spells are sorted by start, so a unit's first start is at its first row;
  # the last end is a GForce max over a vector filled once (not per group)
  span <- list(.lo = keys$.start[first], .hi = integer())
  if (n) {
    ends <- data.table::data.table(.unit = unit, .end = data.table::fcoalesce(keys$.end, last_day))
    span$.hi <- ends[, list(.end = max(.end)), by = .unit]$.end
  }
  lo <- if (is.null(from)) period_code(span$.lo, per_year) else
    rep(period_bound(from, per_year, "from"), length(first))
  hi <- if (is.null(to)) period_code(span$.hi, per_year) else
    rep(period_bound(to, per_year, "to"), length(first))

  if (!is.null(from) && !is.null(to) && lo[1] > hi[1]) {
    cli::cli_abort("{.arg from} must not be after {.arg to}.")
  }
  codes <- if (length(first)) seq(min(lo), max(hi, min(lo))) else integer()
  first_days <- period_first_day(c(codes, max(codes, 0L) + 1L), per_year)
  ultimo_days <- first_days[-1] - 1L
  primo_days  <- if (primo == "first_day") first_days[-length(first_days)] else
    first_days[-length(first_days)] - 1L

  base <- if (length(codes)) min(codes) else 0L
  res <- .Call(C_lustrum_spell_status, keys$.start, keys$.end,
               as.integer(groups), as.integer(lo - base), as.integer(hi - base),
               primo_days, ultimo_days, status_is == "outcome")

  if (status_is == "state" && res[[3]] > 0) {
    cli::cli_alert_warning(
      "{res[[3]]} primo/ultimo point{?s} fell in overlapping spells; the latest start was used. See {.fn ensure_no_overlap}.")
  }

  rows <- pmax(hi - lo + 1L, 0L)
  unit_row <- rep(first, rows)
  code <- sequence(rows, from = lo)
  values <- data[[status_col]][keys$.row]
  out <- lapply(keys[, ids, with = FALSE], `[`, unit_row)
  out$year <- as.integer(code %/% per_year)
  if (by != "year") out[[by]] <- as.integer(code %% per_year + 1L)
  out$primo  <- status_values(values, res[[1]], status_is, ongoing)
  out$ultimo <- status_values(values, res[[2]], status_is, ongoing)

  out <- data.table::setDT(out)
  if (data.table::is.data.table(data)) out else tibble::as_tibble(out)
}

# Spell rows as integer days, without unusable rows, sorted by unit and
# start: `first` is each unit's first row and `groups` the 0-based offsets
# the C code walks
#
# `uid` is an optional integer id per row standing in for the id columns:
# spells are then sorted on it instead of on the ids themselves (a
# character cpr sorts slowly), and units come in the order of `uid`.
prepare_spells <- function(data, ids, start_col, end_col, uid = NULL) {
  s <- spell_days(data[[start_col]], start_col)
  e <- spell_days(data[[end_col]], end_col)

  keys <- if (is.null(uid)) data.table::as.data.table(data)[, ids, with = FALSE] else
    data.table::data.table(.uid = uid)
  if (!is.null(uid)) ids <- ".uid"
  data.table::set(keys, j = ".start", value = s)
  data.table::set(keys, j = ".end", value = e)
  data.table::set(keys, j = ".row", value = seq_len(nrow(data)))
  bad_start <- is.na(s)
  bad_order <- !bad_start & !is.na(e) & e < s
  if (any(bad_start)) {
    cli::cli_alert_warning("Dropped {sum(bad_start)} spell{?s} with a missing {.var {start_col}}.")
  }
  if (any(bad_order)) {
    cli::cli_alert_warning("Dropped {sum(bad_order)} spell{?s} where {.var {end_col}} is before {.var {start_col}}.")
  }
  keys <- keys[!(bad_start | bad_order)]
  data.table::setorderv(keys, c(ids, ".start"))

  n     <- nrow(keys)
  unit  <- data.table::rleidv(keys, cols = ids)
  first <- which(c(TRUE, unit[-1] != unit[-n]))
  if (n == 0) first <- integer()
  list(keys = keys, unit = unit, first = first, groups = c(first, n + 1L) - 1L)
}

# Integer days since 1970-01-01 for a Date-like spell column
spell_days <- function(x, col) {
  if (inherits(x, "POSIXt")) x <- as.Date(x)
  if (!inherits(x, "Date")) {
    cli::cli_abort(c("{.var {col}} must be a Date column, not {.cls {class(x)[1]}}.",
                     "i" = "Convert it first, e.g. with {.fn as.Date}."))
  }
  as.integer(floor(unclass(x)))
}

# Period code of each day; converts unique days only, which are few
period_code <- function(days, per_year) {
  u  <- unique(days)
  lt <- as.POSIXlt(as.Date(u))
  code <- as.integer((lt$year + 1900L) * per_year + lt$mon %/% (12L / per_year))
  code[match(days, u)]
}

# First day (integer days) of each period code
period_first_day <- function(codes, per_year) {
  month <- (codes %% per_year) * (12L / per_year) + 1L
  as.integer(as.Date(sprintf("%04d-%02d-01", codes %/% per_year, month)))
}

period_bound <- function(x, per_year, arg) {
  if (inherits(x, "Date") && length(x) == 1 && !is.na(x)) {
    return(period_code(as.integer(x), per_year))
  }
  if (!is.numeric(x) || length(x) != 1 || is.na(x) || x != round(x)) {
    cli::cli_abort("{.arg {arg}} must be a single year (e.g. 2015) or a Date.")
  }
  as.integer(x) * per_year + if (arg == "to") per_year - 1L else 0L
}

# Status values from the indices returned by C_lustrum_spell_status
status_values <- function(values, idx, status_is, ongoing) {
  running <- which(idx == 0L)
  idx[running] <- NA_integer_
  out <- values[idx]
  if (status_is == "outcome" && length(running)) {
    if (is.factor(out) && !ongoing %in% levels(out)) {
      levels(out) <- c(levels(out), as.character(ongoing))
    }
    out[running] <- ongoing
  }
  out
}
