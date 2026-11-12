#' Add the missing unit-periods of a panel as rows
#'
#' The fix for a panel that [ensure_balanced()] reports: every unit-period
#' that should be there and is not becomes a row, with the unit and the
#' period filled in and every other column missing. A count of persons per
#' year then counts a person who is missing in a year as missing, instead
#' of leaving the year out, and a lag over years compares the years it
#' should.
#'
#' It is the one fix for a panel that needs no choice: the missing rows are
#' given by the unit and the periods, and their values are unknown. It does
#' not guess them; carry a status forward with [carry_status()] if that is
#' what the analysis needs.
#'
#' The fix is never silent: it says how many rows it added, and for how
#' many units. With `flag`, the added rows are marked in a logical column of
#' that name, so they can be found afterwards.
#'
#' The periods and `gaps_only` work as in [ensure_balanced()]: by default a
#' unit gets the periods between its first and last observation, so a
#' person who enters late or leaves early is not given rows before birth or
#' after death. With `gaps_only = FALSE` every unit gets every period.
#'
#' A data frame comes back with the added rows sorted in among the others,
#' by unit and period. A database or Arrow table comes back as a query that
#' adds the rows, without changing the table.
#'
#' @inheritParams ensure_balanced
#' @param gaps_only If `TRUE` (default), only periods between a unit's first
#'   and last observation are added. If `FALSE`, every unit gets every
#'   period.
#' @param flag Name of a logical column marking the added rows, or `NULL`
#'   (default) for none.
#'
#' @return `data` with the missing unit-periods added: a tibble for a data
#'   frame, a query for a database or Arrow table.
#'
#' @examples
#' panel <- data.frame(
#'   cpr    = c("a", "a", "a", "b", "b"),
#'   year   = c(2020, 2021, 2022, 2020, 2022),
#'   income = c(100, 110, 120, 90, 95)
#' )
#' # b lacks 2021
#' fill_panel(panel, cpr, year)
#'
#' fill_panel(panel, cpr, year, flag = "filled")
#'
#' @seealso [ensure_balanced()] and [describe_panel()] to find the gaps
#'   first.
#'
#' @export
fill_panel <- function(data, id, time, periods = NULL, gaps_only = TRUE, flag = NULL) {
  tbl      <- check_table(data)
  ids      <- select_names(tbl, {{ id }})
  time_col <- select_names(tbl, {{ time }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(time_col) != 1) cli::cli_abort("{.arg time} must select exactly one column.")
  if (!rlang::is_bool(gaps_only)) cli::cli_abort("{.arg gaps_only} must be TRUE or FALSE.")
  if (!is.null(flag) && (!rlang::is_string(flag) || flag %in% colnames(tbl))) {
    cli::cli_abort("{.arg flag} must be the name of a new column.")
  }

  if (is_remote(tbl)) {
    gaps <- remote_panel_gaps(tbl, ids, time_col, periods, gaps_only)
    attr(gaps, "inshape_order") <- NULL
    n     <- remote_nrow(gaps)
    units <- if (n > 0) n_distinct_rows(gaps, ids) else 0
    if (!is.null(flag)) {
      tbl  <- dplyr::mutate(tbl, !!flag := FALSE)
      gaps <- dplyr::mutate(gaps, !!flag := TRUE)
    }
    out <- if (n > 0) dplyr::union_all(tbl, gaps) else tbl
  } else {
    gaps  <- find_panel_gaps(data, ids, time_col, periods, gaps_only)
    n     <- nrow(gaps)
    units <- if (n > 0) n_distinct_rows(gaps, ids) else 0
    out   <- tibble::as_tibble(data)
    if (!is.null(flag)) {
      out[[flag]]  <- rep(FALSE, nrow(out))
      gaps[[flag]] <- rep(TRUE, n)
    }
    if (n > 0) {
      out <- dplyr::bind_rows(out, gaps)
      o <- do.call(order, c(unname(as.list(out[c(ids, time_col)])),
                            list(method = "radix", na.last = FALSE)))
      out <- out[o, ]
    }
  }

  msg <- if (n == 0) "Nothing to fill: no unit lacks a period." else {
    paste0("Added ", count(n, "row"), " for ", count(units, "unit"),
           ", with every column but ", toString(c(ids, time_col)), " missing.")
  }
  cli::cli_alert_info("{msg}")
  out
}
