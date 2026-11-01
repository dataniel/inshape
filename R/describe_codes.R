#' Describe how the codes of a column change over periods
#'
#' Code lists change: municipalities merge, industry codes are revised, a
#' code is retired and a new one takes its place. In a register spanning
#' many years the codes of one column then come and go, and so do errors
#' that look like codes: a typo that occurs in one year, an old code that
#' should have been converted. `describe_codes()` shows, for every code,
#' the first and last period it occurs in and whether it skips periods in
#' between, and per period how many codes are new and how many are gone. It
#' judges nothing; require a code list with [ensure_codes()].
#'
#' A code that skips periods is usually an error or a conversion applied
#' to some years only. A period with many new and many gone codes is a
#' revision of the code list, and the data before and after it are not
#' comparable without a conversion key.
#'
#' Missing codes are counted per period, not as a code. In `by_period`,
#' `new` is `NA` in the first period and `gone` counts the codes last seen
#' in the period before.
#'
#' @section Why it is fast:
#' The code and period columns are compressed to integer ids by the
#' compiled hash, and the distinct code-periods are found by one more hash
#' pass. A code column has few distinct values and nearly every row repeats
#' a code-period, so everything else is counted on the code-periods, a few
#' hundred or thousand, not on the millions of rows.
#'
#' @param data A data frame or tibble, or a database or Arrow table: see
#'   *Database tables* in [checkpoints].
#' @param code The code column (one column), e.g. `municipality`.
#' @param time The period column (one column), e.g. `year`.
#' @param periods Expected periods. Defaults to those observed in `data`.
#'
#' @return An object of class `lustrum_codes`, printed as a summary. It is a
#'   list with the counts `n_rows`, `n_codes`, `n_every_period`,
#'   `n_with_gaps`, `n_missing` (rows with a missing code),
#'   `n_missing_time` and `n_outside`, the `periods`, and two tibbles:
#'   `codes` (`code`, `first`, `last`, `periods`, `gaps`, `rows`) and
#'   `by_period` (`period`, `codes`, `new`, `gone`, `missing`).
#'
#' @examples
#' persons <- data.frame(
#'   year = rep(2018:2021, each = 3),
#'   municipality = c("955", "956", "957",  "955", "956", "957",
#'                    "960", "956", "957",  "960", "965", "957")
#' )
#' # 955 becomes 960 in 2020 and 956 becomes 965 in 2021
#' describe_codes(persons, municipality, year)
#'
#' @seealso [ensure_codes()] to require codes from a code list.
#'
#' @export
describe_codes <- function(data, code, time, periods = NULL) {
  tbl      <- check_table(data)
  code_col <- select_names(tbl, {{ code }})
  time_col <- select_names(tbl, {{ time }})
  if (length(code_col) != 1 || length(time_col) != 1) {
    cli::cli_abort("{.arg code} and {.arg time} must each select exactly one column.")
  }
  if (is_remote(tbl)) return(remote_describe_codes(tbl, code_col, time_col, periods))

  # A code column has few distinct values and nearly every row repeats a
  # code-period, so the rows are counted per code-period in one pass, and
  # everything else is read from those counts, not from the rows
  ix    <- panel_index(data, code_col, time_col, periods)
  n_per <- length(ix$periods)
  x     <- data[[code_col]]
  first <- first_row_by(ix$unit, ix$n_units)
  value <- x[replace(first, first == 0L, NA)]
  na_rows <- is.na(x)
  na_unit <- if (any(na_rows)) ix$unit[which(na_rows)[1]] else 0L

  cells <- code_periods(ix$unit, ix$pos, ix$n_units, n_per)
  keep <- cells$unit != na_unit
  cell_unit <- cells$unit[keep]
  cell_pos  <- cells$pos[keep]
  cell_rows <- cells$rows[keep]

  n_seen <- tabulate(cell_unit, ix$n_units)
  present <- which(n_seen > 0L)
  lo <- min_by(cell_pos, cell_unit, ix$n_units)[present]
  hi <- max_by(cell_pos, cell_unit, ix$n_units)[present]
  rows <- as.integer(rowsum(cell_rows, cell_unit, reorder = TRUE)[, 1])
  n_seen <- n_seen[present]

  by_value <- order(value[present], method = "radix")
  codes <- tibble::tibble(
    code    = value[present],
    first   = ix$periods[lo],
    last    = ix$periods[hi],
    periods = n_seen,
    gaps    = hi - lo + 1L - n_seen,
    rows    = rows
  )[by_value, ]

  by_period <- tibble::tibble(
    period  = ix$periods,
    codes   = tabulate(cell_pos, n_per),
    new     = replace(tabulate(lo, n_per), 1, NA),
    gone    = replace(tabulate(hi + 1L, n_per), 1, NA),
    missing = tabulate(ix$pos[na_rows], n_per)
  )

  missing_time <- is.na(data[[time_col]])
  structure(list(
    code           = code_col,
    time           = time_col,
    periods        = ix$periods,
    n_rows         = nrow(data),
    n_codes        = length(present),
    n_every_period = sum(n_seen == n_per),
    n_with_gaps    = sum(hi - lo + 1L > n_seen),
    n_missing      = sum(na_rows),
    n_missing_time = sum(missing_time),
    n_outside      = sum(!missing_time) - sum(!is.na(ix$pos)),
    codes          = codes,
    by_period      = by_period
  ), class = "lustrum_codes")
}

# The observed code-periods with their rows: counted in one tabulate()
# pass over a code x period table when it is small, as for a code column
# it is; otherwise the distinct pairs are found by the hash
code_periods <- function(unit, pos, n_units, n_per) {
  cells <- as.double(n_units) * n_per
  if (cells <= max(1e7, length(unit))) {
    counts <- tabulate((unit - 1L) * n_per + pos, cells)
    nz <- which(counts > 0L)
    return(list(unit = (nz - 1L) %/% n_per + 1L, pos = (nz - 1L) %% n_per + 1L,
                rows = counts[nz]))
  }
  inside <- which(!is.na(pos))
  pair <- dense_codes((as.double(unit[inside]) - 1) * n_per + pos[inside])
  heads <- first_row_by(pair, attr(pair, "n"))
  list(unit = unit[inside[heads]], pos = pos[inside[heads]],
       rows = tabulate(pair, attr(pair, "n")))
}

#' @export
print.lustrum_codes <- function(x, ...) {
  per <- x$periods
  span <- if (length(per)) paste0(", ", format(per[1]), "-", format(per[length(per)])) else ""
  cli::cat_rule(paste0("Codes: ", x$code, " by ", x$time))
  cli::cat_line(count(x$n_rows, "row"), ", ", count(x$n_codes, "code"), ", ",
                count(length(per), "period"), span)
  cli::cat_line()
  cli::cat_bullet(paste0("In every period: ", count(x$n_every_period, "code"),
                         share(x$n_every_period, x$n_codes)))
  cli::cat_bullet(paste0("Skipping periods: ", count(x$n_with_gaps, "code"),
                         share(x$n_with_gaps, x$n_codes)))
  if (x$n_missing > 0) cli::cat_bullet(paste0("Rows with a missing ", x$code, ": ", big(x$n_missing)))
  if (x$n_missing_time > 0) cli::cat_bullet(paste0("Rows with a missing ", x$time, ": ", big(x$n_missing_time)))
  if (x$n_outside > 0) cli::cat_bullet(paste0("Rows outside the periods: ", big(x$n_outside)))
  cli::cat_line()
  cli::cat_line("By period:")
  print_table(x$by_period)
  odd <- x$codes[x$codes$periods < length(per), ]
  if (nrow(odd)) {
    odd <- odd[order(-odd$gaps, odd$periods, odd$first), ]
    cli::cat_line()
    cli::cat_line("Codes not in every period, skipping first:")
    print_table(odd, n = 10)
  }
  invisible(x)
}
