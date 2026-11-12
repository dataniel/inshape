#' Assert that microdata add up to a published table
#'
#' A checkpoint for the step from microdata to a published table: counted
#' (or summed) by the table's dimensions, the microdata must give the
#' numbers in the table, cell for cell. A cell that differs is a sign that
#' the microdata or the table was built from another extract, with another
#' definition, or with an error, and it is found before the next table is
#' built on the same microdata. Returns `data`, so it can sit in the middle
#' of a pipeline.
#'
#' The table is a data frame you give it, with one row per cell: the
#' dimension columns named in `by` and the number in `value`. The package
#' does not fetch tables itself; read the table from the statistics bank
#' and pass it in. Dimension columns of the table are converted to the
#' type of the microdata column first, so a year read as text matches a
#' numeric year.
#'
#' On failure the cells that differ are reported, with the microdata number
#' in `data`, the table's in `published` and `difference` (data minus
#' published). A cell in the microdata that the table does not have is
#' reported with a missing `published`; a cell in the table that the
#' microdata do not have counts as 0 in the microdata. A cell whose
#' published value is missing, such as one suppressed for disclosure, is
#' not compared, and the message says how many there are.
#'
#' The reported rows are counts, not persons. The microdata are counted
#' where they live, so only the counts of a database table are fetched.
#'
#' @param published The published table: a local data frame with the `by`
#'   columns and the `value` column, one row per cell.
#' @param by Dimension columns, as in [ensure_matched()]: a character
#'   vector, optionally named to map names in `data` to names in
#'   `published`, e.g. `c(year = "tid", municipality = "omraade")`.
#' @param value Name of the column of `published` holding the numbers.
#'   Default `"n"`.
#' @param sum Column of `data` to sum (tidy-select). If `NULL` (default),
#'   rows are counted.
#' @param tolerance The largest difference that is accepted, for a table
#'   rounded or perturbed for disclosure. Default 0.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when cells differ and no `abort_msg` is
#'   set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' persons <- data.frame(
#'   cpr  = c("a", "b", "c", "d", "e"),
#'   year = c(2023, 2023, 2024, 2024, 2024),
#'   sex  = c("F", "M", "F", "F", "M")
#' )
#' published <- data.frame(
#'   tid = c("2023", "2023", "2024", "2024"),
#'   sex = c("F", "M", "F", "M"),
#'   n   = c(1, 1, 3, 1)
#' )
#' # The table has 3 women in 2024, the microdata 2
#' ensure_reconciled(persons, published, by = c(year = "tid", "sex"))
#'
#' @seealso [ensure_stock_flow()] for a population account over periods,
#'   [checkpoints].
#'
#' @export
ensure_reconciled <- function(data, published, by, value = "n", sum = NULL, tolerance = 0,
                              success_msg = NULL,
                              warn_msg    = NULL,
                              abort_msg   = NULL) {
  tbl <- check_table(data)
  if (!is.data.frame(published)) {
    cli::cli_abort("{.arg published} must be a local data frame, one row per cell.")
  }
  if (missing(by)) by <- NULL
  by <- match_by(by, tbl, published)
  left <- names(by)
  if (!rlang::is_string(value) || !value %in% names(published)) {
    cli::cli_abort("{.arg value} must name a column of {.arg published}.")
  }
  if (!is.numeric(published[[value]])) cli::cli_abort("{.field {value}} of {.arg published} must be numeric.")
  sum_col <- select_names(tbl, {{ sum }})
  # The argument shadows base::sum(): R forces it when it looks for the
  # function, so it is dropped once the column is known
  sum <- NULL
  if (length(sum_col) > 1) cli::cli_abort("{.arg sum} must select at most one column.")
  check_tolerance(tolerance)

  # The table, with the names and types of the microdata
  proto <- table_prototype(tbl)
  pub <- tibble::as_tibble(published)[c(unname(by), value)]
  names(pub) <- c(left, ".inshape_pub")
  for (col in left) pub[[col]] <- as_type_of(pub[[col]], proto[[col]])
  if (anyDuplicated(pub[left])) {
    cli::cli_abort("{.arg published} has more than one row for some cells of {.val {left}}.")
  }

  micro <- dplyr::ungroup(tbl) |>
    dplyr::group_by(!!!rlang::syms(left)) |>
    dplyr::summarise(.inshape_data = !!(if (length(sum_col)) {
      rlang::expr(base::sum(!!rlang::sym(sum_col), na.rm = TRUE))
    } else {
      rlang::expr(dplyr::n())
    }), .groups = "drop") |>
    dplyr::collect()
  micro$.inshape_data <- as.numeric(micro$.inshape_data)

  cells <- dplyr::full_join(micro, pub, by = left, na_matches = "na")
  in_table <- !is.na(match(do.call(paste, c(cells[left], sep = "\r")),
                           do.call(paste, c(pub[left], sep = "\r"))))
  cells$.inshape_data[is.na(cells$.inshape_data)] <- 0
  suppressed <- in_table & is.na(cells$.inshape_pub)
  compared <- in_table & !suppressed
  diff <- cells$.inshape_data - cells$.inshape_pub
  bad <- (!in_table) | (compared & abs(diff) > tolerance)

  d_col <- diagnostic_name(cells[left], "data")
  p_col <- diagnostic_name(cells[left], "published")
  f_col <- diagnostic_name(cells[left], "difference")
  rows <- tibble::as_tibble(cells[bad, left])
  rows[[d_col]] <- cells$.inshape_data[bad]
  rows[[p_col]] <- cells$.inshape_pub[bad]
  rows[[f_col]] <- diff[bad]
  o <- do.call(order, c(unname(as.list(rows[left])), list(method = "radix", na.last = FALSE)))
  rows <- rows[o, ]

  n_suppressed <- sum(suppressed)
  what <- if (length(sum_col)) paste0("sum of ", sum_col) else "count"
  report_check(
    rows,
    pass = paste0("The ", what, " matches the table in ", count(sum(compared), "cell"),
                  if (n_suppressed) paste0(", ", big(n_suppressed), " missing in the table and not compared")),
    fail = paste0("The ", what, " differs from the table by ", toString(left)),
    success_msg, warn_msg, abort_msg,
    key = left,
    summary = function(v, n) {
      d <- v[[f_col]]
      not_there <- sum(is.na(v[[p_col]]))
      list(
        lines = c(
          paste0("Of ", count(sum(compared), "cell"), " compared",
                 if (n_suppressed) paste0("; ", big(n_suppressed), " missing in the table, not compared")),
          if (not_there) paste0(count(not_there, "cell"), " in the data but not in the table"),
          if (any(!is.na(d))) paste0("Difference: total ", big(sum(d, na.rm = TRUE)),
                                     ", largest ", big(d[which.max(abs(d))])),
          pattern_lines(v, left, n)
        ),
        hints = if (tolerance == 0 && any(!is.na(d))) {
          "If the table is rounded or perturbed for disclosure: tolerance = <largest accepted difference>"
        }
      )
    }
  )
  invisible(data)
}

#' Assert that a stock and its flows add up over periods
#'
#' A checkpoint for an account over periods: the population at the end of
#' a year must be the population at the end of the year before, plus the
#' born and the immigrated, minus the dead and the emigrated. For a
#' population statistic it is the check that catches most, since every
#' person who is lost or counted twice between the stock and the flows
#' breaks it. Returns `data`, so it can sit in the middle of a pipeline.
#'
#' `data` holds one row per period (and per group, with `by`): the stock
#' and the flows during the period, as counted from the registers. Inflows
#' and outflows may be several columns each; they are added up per row.
#'
#' With `stock_at = "end"` (default) the stock is counted at the end of
#' each period, so it is the stock before plus the period's flows. With
#' `stock_at = "start"` it is counted at the start, so it is the stock
#' before plus the flows of the period before.
#'
#' On failure the periods where the account does not add up are reported,
#' with `expected` (the stock before plus the flows) and `difference` (the
#' stock minus expected). The first period of each group has no stock
#' before it and is not checked. A period missing in the middle makes the
#' next one compared with the one before the gap; find such gaps with
#' [ensure_balanced()]. Rows with a missing stock or flow are not checked.
#'
#' The table is small, one row per period and group, so a database or
#' Arrow table is fetched into R before the check.
#'
#' @param time The period column (one column).
#' @param stock The stock column (one column).
#' @param inflow,outflow Columns of flows into and out of the stock
#'   (tidy-select, one or more each), e.g. `c(born, immigrated)`.
#' @param by Columns grouping the account (tidy-select), e.g. `sex`, or
#'   `NULL` (default) for one account.
#' @param stock_at `"end"` (default) or `"start"`: when in the period the
#'   stock is counted.
#' @param tolerance The largest difference that is accepted. Default 0.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when the account does not add up and no
#'   `abort_msg` is set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' account <- data.frame(
#'   year       = 2021:2024,
#'   population = c(56000, 56100, 56210, 56300),
#'   born       = c(800, 820, 790, 810),
#'   immigrated = c(2000, 2100, 2050, 2200),
#'   dead       = c(500, 520, 510, 530),
#'   emigrated  = c(2200, 2300, 2280, 2330)
#' )
#' # 2023 has 60 persons more than its flows give, so 2024 has 60 fewer
#' ensure_stock_flow(account, year, population,
#'                   inflow = c(born, immigrated), outflow = c(dead, emigrated))
#'
#' @seealso [ensure_reconciled()] to compare microdata with a published
#'   table, [checkpoints].
#'
#' @export
ensure_stock_flow <- function(data, time, stock, inflow, outflow, by = NULL,
                              stock_at = c("end", "start"), tolerance = 0,
                              success_msg = NULL,
                              warn_msg    = NULL,
                              abort_msg   = NULL) {
  tbl <- check_table(data)
  time_col  <- select_names(tbl, {{ time }})
  stock_col <- select_names(tbl, {{ stock }})
  in_cols   <- select_names(tbl, {{ inflow }})
  out_cols  <- select_names(tbl, {{ outflow }})
  by_cols   <- select_names(tbl, {{ by }})
  stock_at  <- match.arg(stock_at)
  if (length(time_col) != 1) cli::cli_abort("{.arg time} must select exactly one column.")
  if (length(stock_col) != 1) cli::cli_abort("{.arg stock} must select exactly one column.")
  if (length(in_cols) + length(out_cols) == 0) {
    cli::cli_abort("Give the flows in {.arg inflow}, {.arg outflow} or both.")
  }
  check_tolerance(tolerance)

  acc <- if (is_remote(tbl)) dplyr::collect(tbl) else tibble::as_tibble(data)
  acc <- dplyr::ungroup(acc)
  if (anyDuplicated(acc[c(by_cols, time_col)])) {
    cli::cli_abort(c(
      "The account has more than one row for some periods.",
      "i" = "Find them with {.code ensure_unique()} on {.val {c(by_cols, time_col)}}."
    ))
  }
  flow_sum <- function(cols) {
    if (length(cols) == 0) return(rep(0, nrow(acc)))
    Reduce(`+`, lapply(acc[cols], as.numeric))
  }
  net <- flow_sum(in_cols) - flow_sum(out_cols)
  o <- do.call(order, c(unname(as.list(acc[c(by_cols, time_col)])), list(method = "radix")))
  group <- if (length(by_cols)) group_ids(acc, by_cols) else rep(1L, nrow(acc))
  g <- group[o]
  s <- as.numeric(acc[[stock_col]])[o]
  f <- net[o]
  n <- length(o)
  prev <- c(NA, seq_len(n - 1))
  prev[c(TRUE, g[-1] != g[-n])] <- NA
  ok_prev <- !is.na(prev)
  expected <- rep(NA_real_, n)
  pi <- prev[ok_prev]
  expected[ok_prev] <- s[pi] + if (stock_at == "end") f[ok_prev] else f[pi]
  diff <- s - expected
  bad <- which(!is.na(diff) & abs(diff) > tolerance)

  e_col <- diagnostic_name(acc, "expected")
  d_col <- diagnostic_name(acc, "difference")
  rows <- acc[o[bad], ]
  rows <- tibble::add_column(rows, !!e_col := expected[bad], !!d_col := diff[bad], .before = 1)

  report_check(
    rows,
    pass = paste0("The account adds up: ", stock_col, " by ", time_col,
                  if (length(by_cols)) paste0(" per ", toString(by_cols))),
    fail = paste0("The account does not add up: ", stock_col, " by ", time_col,
                  if (length(by_cols)) paste0(" per ", toString(by_cols))),
    success_msg, warn_msg, abort_msg,
    key = c(by_cols, time_col, stock_col, d_col, e_col),
    summary = function(v, n) {
      d <- v[[d_col]]
      c(paste0("Difference: total ", big(sum(d)), ", largest ", big(d[which.max(abs(d))])),
        pattern_lines(v, c(time_col, by_cols), n))
    }
  )
  invisible(data)
}

check_tolerance <- function(tolerance, call = rlang::caller_env()) {
  if (!is.numeric(tolerance) || length(tolerance) != 1 || is.na(tolerance) || tolerance < 0) {
    cli::cli_abort("{.arg tolerance} must be a single number, 0 or more.", call = call)
  }
}

# A column of a published table in the type of the microdata column it
# is joined to: a year read as text becomes a number, and so on
as_type_of <- function(x, proto) {
  if (is.factor(x)) x <- as.character(x)
  if (inherits(proto, "Date")) return(as.Date(x))
  if (is.integer(proto)) return(as.integer(x))
  if (is.numeric(proto)) return(as.numeric(x))
  if (is.character(proto) || is.factor(proto)) return(as.character(x))
  x
}
