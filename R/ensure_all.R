#' Assert that every row meets a condition
#'
#' The positive form of [ensure_none()]: state what must hold instead of
#' what must not occur. `data` itself is returned, so the pipeline continues
#' with all rows:
#'
#' ```r
#' df |>
#'   ensure_all(amount >= 0, abort_msg = "Amounts must not be negative") |>
#'   ensure_all(year %in% 2015:2024) |>
#'   mutate(...)
#' ```
#'
#' ## Why both `ensure_all()` and `ensure_none()`
#'
#' The two are not each other's negation, because they treat a missing
#' value differently. A row violates `ensure_all()` unless the condition is
#' `TRUE`, so a row where it is `NA` is a violation: the rule cannot be shown
#' to hold. In `ensure_none()` such a row passes, as it would in
#' [dplyr::filter()].
#'
#' ```r
#' df <- data.frame(amount = c(10, -5, NA))
#'
#' ensure_none(df, amount < 0)   # 1 row: -5
#' ensure_all(df, amount >= 0)   # 2 rows: -5 and NA
#' ```
#'
#' Use `ensure_all()` when a value has to be present *and* right, and
#' `ensure_none()` when a missing value is acceptable or is a separate rule
#' with its own message.
#'
#' Several conditions must all hold, so a row is a violation when any of
#' them is `FALSE` or `NA`.
#'
#' @param ... Conditions every row must meet, written as in
#'   [dplyr::filter()].
#' @inheritParams checkpoints
#' @param warn_msg Message shown when rows fail the condition
#'   and no `abort_msg` is set. Defaults to a description of the condition.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' mtcars |>
#'   ensure_all(cyl %in% c(4, 6, 8)) |>
#'   ensure_all(mpg > 15, warn_msg = "Thirsty cars") |>
#'   nrow()
#'
#' # A missing value is a violation here, but not in ensure_none()
#' df <- data.frame(amount = c(10, -5, NA))
#' ensure_all(df, amount >= 0)
#' ensure_none(df, amount < 0)
#'
#' @seealso [ensure_none()], [ensure_empty()], [tally_violations()],
#'   [checkpoints]
#'
#' @export
ensure_all <- function(data, ...,
                       success_msg = NULL,
                       warn_msg    = NULL,
                       abort_msg   = NULL) {

  tbl <- check_table(data)
  conditions <- rlang::enquos(...)
  if (length(conditions) == 0) {
    cli::cli_abort("Supply at least one condition in {.arg ...}.")
  }
  named <- names(conditions)[names(conditions) != ""]
  if (length(named) > 0) {
    cli::cli_abort(c(
      "Conditions in {.arg ...} must not be named.",
      "i" = "Did you write {.code =} where you meant {.code ==}, or misspell the argument {.arg {named[1]}}?"
    ))
  }
  rule <- paste(vapply(conditions, rlang::as_label, character(1)), collapse = " & ")

  # A row passes only when every condition is TRUE, so NA is a violation
  holds <- Reduce(function(a, b) rlang::quo(!!a & !!b), unname(conditions))
  fails <- rlang::quo(dplyr::if_else(!!holds, FALSE, TRUE, missing = TRUE))
  violations <- filter_violations(tbl, list(fails), rule, rlang::current_env(),
                                  as_written = unname(conditions))

  report_check(
    violations,
    pass = paste0("All rows meet ", rule),
    fail = paste0("Found rows that do not meet ", rule),
    success_msg, warn_msg, abort_msg
  )
  invisible(data)
}
