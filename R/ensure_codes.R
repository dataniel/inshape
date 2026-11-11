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
#' are different codes, as they are in the register.
#'
#' For time-dependent codes, supply a data frame with `code`, `valid_from`
#' and `valid_to`, and select the observation's `time` column. Boundaries
#' are inclusive; missing boundaries are open. Multiple validity intervals
#' per code are allowed. A non-missing code with missing time fails, since
#' its validity cannot be established. `na_ok` only controls missing codes.
#' Time and both boundaries must use the same scale: Date, POSIXct, or
#' numeric periods. Years and dates are not implicitly mixed.
#' The code list must have non-missing codes and ordered boundaries.
#'
#' @param column The coded column (tidy-select), e.g. `municipality`.
#' @param codes A vector of valid codes, or a local data frame with columns
#'   `code`, `valid_from`, `valid_to`. An empty temporal list allows no codes.
#' @param time Observation time column (tidy-select), required for a
#'   time-dependent code list and omitted for a vector.
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
ensure_codes <- function(data, column, codes, time = NULL, na_ok = TRUE,
                         success_msg = NULL,
                         warn_msg    = NULL,
                         abort_msg   = NULL) {

  tbl <- check_table(data)
  col <- select_names(tbl, {{ column }})
  if (length(col) != 1) cli::cli_abort("{.arg column} must select exactly one column.")
  temporal <- is.data.frame(codes)
  time_col <- select_names(tbl, {{ time }})
  if (temporal && length(time_col) != 1) {
    cli::cli_abort("Select exactly one {.arg time} column for a temporal code list.")
  }
  if (!temporal && length(time_col)) cli::cli_abort("{.arg time} requires a temporal code list.")
  if (!temporal && (!is.atomic(codes) || length(codes) == 0)) {
    cli::cli_abort("{.arg codes} must be a non-empty vector of codes.")
  }
  if (!rlang::is_bool(na_ok)) cli::cli_abort("{.arg na_ok} must be TRUE or FALSE.")
  if (!temporal) codes <- unique(codes[!is.na(codes)])

  rows <- if (temporal) {
    temporal_code_violations(tbl, col, codes, time_col, na_ok)
  } else if (is_remote(tbl)) {
    remote_not_in(tbl, col, codes, na_ok)
  } else {
    x <- data[[col]]
    if (is.factor(x)) x <- as.character(x)
    if (is.character(x)) codes <- as.character(codes)
    known <- if (is.character(x)) data.table::`%chin%`(x, codes) else x %in% codes
    bad <- !known & (!na_ok | !is.na(x))
    tibble::as_tibble(data)[which(bad), ]
  }

  report_check(
    rows,
    pass = paste0("Valid codes: ", col),
    fail = paste0("Codes not in the code list: ", col),
    success_msg, warn_msg, abort_msg,
    key = col, group = col
  )
  invisible(data)
}

# Split open/closed intervals so both local non-equi joins and SQL can use
# ordinary comparison predicates. Semi joins never multiply observations.
temporal_code_violations <- function(tbl, col, codes, time, na_ok) {
  required <- c("code", "valid_from", "valid_to")
  if (!all(required %in% names(codes))) {
    cli::cli_abort("A temporal code list needs {.field code}, {.field valid_from} and {.field valid_to}.")
  }
  proto <- table_prototype(tbl)
  check_time_scale(list(proto[[time]], codes$valid_from, codes$valid_to))
  if (!is.atomic(codes$code) || !is.null(dim(codes$code)) || anyNA(codes$code)) {
    cli::cli_abort("The code list must contain non-missing atomic codes.")
  }
  if (any(codes$valid_from > codes$valid_to, na.rm = TRUE)) {
    cli::cli_abort("The code list has {.field valid_to} before {.field valid_from}.")
  }
  codes <- tibble::as_tibble(codes)[required]
  if (is.factor(codes$code)) codes$code <- as.character(codes$code)
  if (is.character(proto[[col]]) || is.factor(proto[[col]])) codes$code <- as.character(codes$code)
  keys <- unique(c(col, time))
  candidates <- tbl |>
    dplyr::select(dplyr::all_of(keys)) |>
    dplyr::filter(!is.na(.data[[col]]), !is.na(.data[[time]]))
  matches <- NULL
  for (lower in c(FALSE, TRUE)) for (upper in c(FALSE, TRUE)) {
    part <- codes[(!is.na(codes$valid_from) == lower) & (!is.na(codes$valid_to) == upper), ]
    if (!nrow(part)) next
    # Build qualified column references for join_by, including unusual names.
    x_code <- rlang::call2("$", rlang::sym("x"), rlang::sym(col))
    x_time <- rlang::call2("$", rlang::sym("x"), rlang::sym(time))
    y_code <- rlang::call2("$", rlang::sym("y"), rlang::sym("code"))
    y_from <- rlang::call2("$", rlang::sym("y"), rlang::sym("valid_from"))
    y_to <- rlang::call2("$", rlang::sym("y"), rlang::sym("valid_to"))
    tests <- list(rlang::expr(!!x_code == !!y_code))
    if (lower) tests <- c(tests, list(rlang::expr(!!x_time >= !!y_from)))
    if (upper) tests <- c(tests, list(rlang::expr(!!x_time <= !!y_to)))
    if (is_remote(tbl)) part <- dbplyr::copy_inline(dbplyr::remote_con(tbl), part)
    hit <- dplyr::semi_join(candidates, part, by = dplyr::join_by(!!!tests), na_matches = "never")
    matches <- if (is.null(matches)) hit else dplyr::union_all(matches, hit)
  }
  rows <- if (is.null(matches)) tbl else dplyr::anti_join(tbl, matches, by = keys, na_matches = "never")
  if (na_ok) rows <- dplyr::filter(rows, !is.na(.data[[col]]))
  if (is_remote(tbl)) rows <- sort_by(rows, na_first(keys))
  rows
}
