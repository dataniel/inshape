#' Assert that columns have no missing values
#'
#' A checkpoint for the columns an analysis cannot do without: an id, a
#' date, the outcome. A missing value in them drops the row from a model
#' without a word, or makes it a group of its own in a count. Returns
#' `data`, so it can sit in the middle of a pipeline.
#'
#' On failure the rows with a missing value in any of the columns are
#' reported, with a `missing` column prepended that names the columns
#' missing in that row, e.g. `"born, sex"`. The summary counts the rows and
#' the different combinations of missing columns.
#'
#' Missing means `NA`, and for numbers `NaN` too, as in [is.na()]; an empty
#' string is a value. In a database table missing means `NULL`.
#'
#' @param ... Columns that must be complete (tidy-select). If omitted, all
#'   columns are checked.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when values are missing and no
#'   `abort_msg` is set. Defaults to a description naming the columns.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' persons <- data.frame(
#'   cpr  = c("a", "b", NA, "d"),
#'   born = as.Date(c("1980-05-01", NA, NA, "1975-02-11")),
#'   sex  = c("F", "M", "F", NA)
#' )
#'
#' # Success: no one lacks a sex among the first three
#' ensure_complete(persons[1:3, ], sex)
#'
#' # Warning: b lacks a birth date, the third row a cpr as well
#' ensure_complete(persons, cpr, born)
#'
#' # All columns
#' ensure_complete(persons)
#'
#' @seealso [describe_varying()] and [describe_key()], which count missing
#'   values per column, [ensure_valid_spells()] for missing spell bounds,
#'   [checkpoints].
#'
#' @export
ensure_complete <- function(data, ...,
                            success_msg = NULL,
                            warn_msg    = NULL,
                            abort_msg   = NULL) {

  tbl  <- check_table(data)
  cols <- if (...length() > 0) select_names(tbl, ...) else colnames(tbl)
  what <- if (...length() > 0) toString(cols) else "all columns"
  if (length(cols) == 0) {
    cli::cli_abort(c(
      "The selection has no columns.",
      "i" = "Leave it out to check all columns."
    ))
  }
  diagnostic <- diagnostic_name(tbl, "missing")

  rows <- if (is_remote(tbl)) {
    remote_incomplete(tbl, cols, diagnostic)
  } else {
    find_incomplete(data, cols, diagnostic)
  }

  report_check(
    rows,
    pass = paste0("Complete: ", what),
    fail = paste0("Missing values in: ", what),
    success_msg, warn_msg, abort_msg,
    key = cols, group = diagnostic
  )
  invisible(data)
}

# Rows with a missing value in any of `cols`, in the order of the data,
# with the names of the columns missing in each row. The names are put
# together for the incomplete rows only, usually few.
find_incomplete <- function(data, cols, diagnostic) {
  gone <- lapply(unclass(data)[cols], function(x) {
    # a list or data frame column has no single answer per row
    if (is.atomic(x) && is.null(dim(x))) which(is.na(x)) else integer()
  })
  rows <- sort(unique(unlist(gone, use.names = FALSE)))
  label <- character(length(rows))
  for (col in cols) {
    hit <- match(gone[[col]], rows)
    label[hit] <- paste0(label[hit], ifelse(nzchar(label[hit]), ", ", ""), col)
  }
  out <- tibble::as_tibble(data)[rows, ]
  tibble::add_column(out, !!diagnostic := label, .before = 1)
}
