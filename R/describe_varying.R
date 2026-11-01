#' Describe which columns vary within a unit
#'
#' Some columns should be constant within a unit: sex and birth date per
#' person, the start year of a company. Others are expected to vary: income,
#' address. `describe_varying()` shows, for each column, how many units have
#' more than one value, so the constant columns, the varying ones and the
#' nearly constant ones stand apart. A column that varies for a handful of
#' units out of millions is rarely meant to vary: those units are usually
#' errors, and [ensure_constant()] lists them.
#'
#' A missing value is not counted as a value of its own: a person whose sex
#' is missing in one year and known in another has not changed sex, but is
#' partly missing, which is counted separately.
#'
#' It is the within-unit view of Stata's `xtsum`, for categories as well as
#' numbers.
#'
#' @section Why it is fast:
#' Units are grouped once by the compiled engine, and reused from its
#' cache when the same id column was checked before (see [checkpoints]).
#' For each column, one compiled pass compares every row with the first
#' non-missing value of its unit, with no hashing or sorting of the column
#' and one memory word of state per unit.
#'
#' @param data A data frame or tibble, or a database or Arrow table: see
#'   *Database tables* in [checkpoints].
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr`.
#' @param ... Columns to describe (tidy-select). Defaults to all other
#'   columns.
#'
#' @return An object of class `inshape_varying`, printed as a summary. It
#'   is a list with `ids`, `n_units` and `columns`, a tibble with one row
#'   per column: `column`, `varying` (units with more than one non-missing
#'   value), `share` (of the units with a value), `partly_missing` (units
#'   with both missing and non-missing values) and `all_missing`, sorted
#'   from the most constant to the most varying.
#'
#' @examples
#' persons <- data.frame(
#'   cpr    = c("a", "a", "b", "b", "c", "c"),
#'   year   = c(2020, 2021, 2020, 2021, 2020, 2021),
#'   sex    = c("F", "F", "M", "F", "M", NA),
#'   income = c(100, 120, 90, 95, 80, 85)
#' )
#' describe_varying(persons, cpr)
#'
#' @seealso [ensure_constant()] to require a column to be constant within
#'   units and list the units that break it.
#'
#' @export
describe_varying <- function(data, id, ...) {
  tbl <- check_table(data)
  ids <- select_names(tbl, {{ id }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  cols <- if (...length() == 0) setdiff(colnames(tbl), ids) else select_names(tbl, ...)
  cols <- setdiff(cols, ids)
  if (is_remote(tbl)) return(remote_describe_varying(tbl, ids, cols))
  cols <- cols[vapply(unclass(data)[cols], is.atomic, logical(1))]

  unit <- group_ids(data, ids)
  n_units <- attr(unit, "n")
  rows <- lapply(cols, function(col) varying_units(data[[col]], unit, n_units))
  columns <- tibble::tibble(
    column         = cols,
    varying        = vapply(rows, function(r) sum(r$varying), integer(1)),
    share          = vapply(rows, function(r) {
      with_value <- sum(!r$all_missing)
      if (with_value == 0) NA_real_ else sum(r$varying) / with_value
    }, numeric(1)),
    partly_missing = vapply(rows, function(r) sum(r$partly_missing), integer(1)),
    all_missing    = vapply(rows, function(r) sum(r$all_missing), integer(1))
  )
  columns <- columns[order(columns$share, columns$column, na.last = TRUE), ]

  structure(list(ids = ids, n_units = n_units, columns = columns),
            class = "inshape_varying")
}

# Per unit (1..n_units): whether column `x` has two different non-missing
# values (varying), both missing and non-missing values (partly_missing),
# or only missing values (all_missing). Every row is compared with the
# first non-missing value of its unit, in one compiled pass (src/group.c);
# columns it does not take, such as integer64, go through the same
# comparison in R.
varying_units <- function(x, unit, n_units) {
  if (is.factor(x)) x <- as.integer(x)
  flag <- if (!inherits(x, "integer64")) {
    .Call(C_inshape_varying_units, x, unit, as.integer(n_units))
  }
  if (!is.null(flag)) {
    has_value <- bitwAnd(flag, 2L) > 0L
    has_na    <- bitwAnd(flag, 4L) > 0L
    return(list(
      varying        = bitwAnd(flag, 1L) > 0L,
      partly_missing = has_value & has_na,
      all_missing    = !has_value & has_na
    ))
  }
  missing <- is.na(x)
  has <- which(!missing)
  first <- first_row_by(unit[has], n_units)
  ref <- integer(n_units)
  ref[first > 0] <- has[first[first > 0]]
  differs <- has[x[has] != x[ref[unit[has]]]]
  n_value <- tabulate(unit[has], n_units)
  n_na <- tabulate(unit[missing], n_units)
  list(
    varying        = tabulate(unit[differs], n_units) > 0L,
    partly_missing = n_value > 0L & n_na > 0L,
    all_missing    = n_value == 0L & n_na > 0L
  )
}

#' @export
print.inshape_varying <- function(x, ...) {
  cli::cat_rule(paste0("Within ", toString(x$ids)))
  cli::cat_line(count(x$n_units, "unit"), ", ", count(nrow(x$columns), "column"))
  cli::cat_line()
  shown <- x$columns
  shown$share <- ifelse(is.na(shown$share), "",
                        sprintf("%.2f%%", 100 * shown$share))
  print_table(shown)
  invisible(x)
}
