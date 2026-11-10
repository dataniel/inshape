#' Assert that spell boundaries are valid
#'
#' Missing starts and ends before starts are violations. A missing end is
#' an ongoing spell and passes by default; use `open_end = FALSE` to require
#' closed spells. Equal boundaries are valid one-day or one-period spells.
#' Boundaries must both be dates, both date-times, or both numeric periods.
#' The diagnostic `reason` column identifies the first problem on each row:
#' missing start, missing end, then end before start.
#'
#' @param start,end Columns containing spell boundaries (tidy-select).
#' @param open_end Allow missing end values. Default `TRUE`.
#' @inheritParams checkpoints
#' @param warn_msg Message when invalid spells are found.
#' @return `data` invisibly, unchanged. Failures carry the offending rows.
#' @seealso [describe_spells()], [ensure_no_overlap()], [checkpoints].
#' @examples
#' spells <- data.frame(start = c(2020, NA, 2023), end = c(NA, 2022, 2022))
#' ensure_valid_spells(spells, start, end)
#' @export
ensure_valid_spells <- function(data, start, end, open_end = TRUE,
                                success_msg = NULL, warn_msg = NULL,
                                abort_msg = NULL) {
  tbl <- check_table(data)
  s <- select_names(tbl, {{ start }})
  e <- select_names(tbl, {{ end }})
  if (length(s) != 1 || length(e) != 1) {
    cli::cli_abort("{.arg start} and {.arg end} must each select exactly one column.")
  }
  if (!rlang::is_bool(open_end)) cli::cli_abort("{.arg open_end} must be TRUE or FALSE.")
  proto <- table_prototype(tbl)
  check_time_scale(list(proto[[s]], proto[[e]]))
  diagnostic <- diagnostic_name(tbl, "reason")
  rows <- tbl |>
    dplyr::mutate(!!diagnostic := dplyr::case_when(
      is.na(.data[[s]]) ~ "missing start",
      !open_end & is.na(.data[[e]]) ~ "missing end",
      .data[[e]] < .data[[s]] ~ "end before start",
      TRUE ~ NA_character_
    )) |>
    dplyr::filter(!is.na(.data[[diagnostic]]))
  if (is_remote(tbl)) rows <- sort_by(rows, na_first(c(s, e)))
  label <- abort_msg %||% warn_msg
  report_check(rows, success_msg %||% if (is.null(label)) "Valid spell boundaries" else paste0("Check passed: ", label),
               label %||% "Invalid spell boundaries", !is.null(abort_msg),
               key = c(s, e), group = diagnostic)
  invisible(data)
}

# Only column types are fetched from databases.
table_prototype <- function(tbl) {
  if (is_remote(tbl)) dplyr::collect(utils::head(tbl, 0L)) else tbl[0, , drop = FALSE]
}

check_time_scale <- function(columns) {
  scale <- vapply(columns, function(x) {
    if (inherits(x, "Date")) "date"
    else if (inherits(x, "POSIXct")) "datetime"
    else if (is.numeric(x) && !is.object(x)) "numeric"
    else "unsupported"
  }, character(1))
  if ("unsupported" %in% scale || length(unique(scale)) != 1) {
    cli::cli_abort("Time and boundary columns must use the same scale: dates, date-times, or numeric periods.")
  }
}
