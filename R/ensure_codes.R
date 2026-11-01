#' Assert that a column only holds codes from a code list
#'
#' A checkpoint for coded columns: municipality, industry, education. A
#' value outside the code list is a typo, an old code that should have been
#' converted, or a code from another classification, and it silently drops
#' out of every table built on the code list. On failure the offending rows
#' are reported, with the codes counted. Returns `data`, so it can sit in
#' the middle of a pipeline.
#'
#' Missing values pass by default, as missing is a different problem from a
#' wrong code; set `na_ok = FALSE` to require a code on every row. The code
#' list is compared as text when the column is text, so `"0955"` and `"955"`
#' are different codes, as they are in the register. When the valid codes
#' depend on the period, check each period with its own list, e.g. after
#' `dplyr::filter(data, year >= 2018)`; see [describe_codes()] for how the
#' codes change.
#'
#' @param column The coded column (tidy-select), e.g. `municipality`.
#' @param codes The valid codes: a vector, e.g. a column of a code list.
#' @param na_ok Whether a missing value passes. Default `TRUE`.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when values are outside the
#'   code list and no `abort_msg` is set. Defaults to a description of the
#'   check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' persons <- data.frame(cpr = c("a", "b", "c", "d"),
#'                       municipality = c("955", "956", "95", NA))
#' valid <- c("955", "956", "957", "959", "960")
#' # "95" is not a municipality
#' ensure_codes(persons, municipality, valid)
#'
#' @seealso [describe_codes()] for how codes change over periods,
#'   [checkpoints].
#'
#' @export
ensure_codes <- function(data, column, codes, na_ok = TRUE,
                         success_msg = NULL,
                         warn_msg    = NULL,
                         abort_msg   = NULL) {

  tbl <- check_table(data)
  col <- select_names(tbl, {{ column }})
  if (length(col) != 1) cli::cli_abort("{.arg column} must select exactly one column.")
  if (is.data.frame(codes)) {
    cli::cli_abort(c("{.arg codes} must be a vector of codes, not a data frame.",
                     "i" = "Pass one column of it, e.g. {.code codes$code}."))
  }
  if (!is.atomic(codes) || length(codes) == 0) {
    cli::cli_abort("{.arg codes} must be a non-empty vector of codes.")
  }
  if (!rlang::is_bool(na_ok)) cli::cli_abort("{.arg na_ok} must be TRUE or FALSE.")
  codes <- unique(codes[!is.na(codes)])

  rows <- if (is_remote(tbl)) {
    remote_not_in(tbl, col, codes, na_ok)
  } else {
    x <- data[[col]]
    if (is.factor(x)) x <- as.character(x)
    if (is.character(x)) codes <- as.character(codes)
    known <- if (is.character(x)) data.table::`%chin%`(x, codes) else x %in% codes
    bad <- !known & (!na_ok | !is.na(x))
    tibble::as_tibble(data)[which(bad), ]
  }

  label <- abort_msg %||% warn_msg
  report_check(
    violations  = rows,
    success_msg = success_msg %||%
      if (is.null(label)) paste0("Valid codes: ", col) else paste0("Check passed: ", label),
    fail_msg    = label %||% paste0("Codes not in the code list: ", col),
    abort       = !is.null(abort_msg),
    key         = col,
    group       = col
  )
  invisible(data)
}
