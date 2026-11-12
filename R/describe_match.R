#' Describe how the keys of two tables match
#'
#' Before a join, the question is what it will do: how many keys are in
#' both tables, how many rows will find no match, and whether the other
#' table repeats a key and so multiplies rows. `describe_match()` counts
#' the keys found in both tables, only in `data` and only in `reference`,
#' with the rows they stand for, and says how many rows a left join of
#' `data` to `reference` returns. It judges nothing; require a match with
#' [ensure_matched()].
#'
#' A key with a missing value in any of its columns matches nothing, as
#' with `na_matches = "never"` in [ensure_matched()]: those rows are
#' counted on their own and kept out of the keys. A left join keeps each
#' of them once.
#'
#' Key columns are compared as they are. An integer and a double column
#' match, and so do a factor and a character column; other pairs of
#' different types, such as a number against text, stop with an error
#' rather than match nothing. In a database the comparison is the
#' database's own: DuckDB refuses a number against text as well, with its
#' own error.
#'
#' @param data A data frame or tibble, or a database or Arrow table: see
#'   *Database tables* in [checkpoints].
#' @inheritParams ensure_matched
#'
#' @return An object of class `inshape_match`, printed as a summary. It is
#'   a list with `by` (the key columns of `reference`, named by those of
#'   `data`), the counts `n_rows` and `n_ref_rows`, `n_missing` and
#'   `n_ref_missing` (rows with a missing key), `n_ref_dup_keys` (keys
#'   occurring more than once in `reference`) and `n_join_rows` (the rows
#'   of a left join of `data` to `reference`), and a tibble `keys` with one
#'   row for each of `"in both"`, `"only in data"` and
#'   `"only in reference"`: `keys` (distinct keys), `rows` (the rows of
#'   `data` with those keys) and `ref_rows` (the rows of `reference`).
#'
#' @examples
#' income <- data.frame(
#'   cpr    = c("a", "a", "b", "c", NA),
#'   year   = c(2023, 2024, 2024, 2024, 2024),
#'   income = c(10, 12, 7, 9, 3)
#' )
#' persons <- data.frame(
#'   person_id = c("a", "b", "b", "d"),
#'   kommune   = c("955", "956", "957", "960")
#' )
#' # c is not in the register, d has no income, and b is there twice, so
#' # the join returns one row more than income has
#' describe_match(income, persons, by = c(cpr = "person_id"))
#'
#' @seealso [ensure_matched()] to require that every key is found and see
#'   the rows, [describe_key()] for the duplicated keys of one table,
#'   [describe_changes()] to compare two extracts of the same register.
#'
#' @export
describe_match <- function(data, reference, by) {
  tbl <- check_table(data)
  ref <- check_table(reference)
  if (missing(by)) by <- NULL
  by  <- match_by(by, tbl, ref)
  ref <- match_reference(tbl, ref, by)
  if (is_remote(tbl)) return(remote_describe_match(tbl, ref, by))

  call <- rlang::current_env()
  n <- nrow(data)
  both <- lapply(seq_along(by), function(k) {
    match_values(data[[names(by)[k]]], ref[[by[[k]]]], names(by)[k], by[[k]], call = call)
  })
  names(both) <- paste0("k", seq_along(by))
  whole <- !Reduce(`|`, lapply(both, is.na))
  id <- group_ids(data.table::setDT(both), names(both))
  # A logical index: with no rows in data, `-seq_len(0)` would select
  # nothing of the reference instead of all of it
  in_data <- seq_along(id) <= n

  # Rows per key in each table, over the keys without missing values
  d <- tabulate(id[in_data & whole], attr(id, "n"))
  r <- tabulate(id[!in_data & whole], attr(id, "n"))
  n_missing <- n - sum(d)
  new_match(
    by, n_rows = n, n_ref_rows = nrow(ref),
    n_missing = n_missing, n_ref_missing = nrow(ref) - sum(r),
    counts = list(c(sum(d > 0L & r > 0L), sum(d > 0L & r == 0L), sum(d == 0L & r > 0L)),
                c(sum(d[r > 0L]), sum(d[r == 0L]), 0),
                c(sum(r[d > 0L]), 0, sum(r[d == 0L]))),
    n_ref_dup_keys = sum(r > 1L),
    n_join_rows = sum(as.double(d) * pmax(r, 1L)) + n_missing
  )
}

# The key values of both tables in one vector, data first
match_values <- function(x, y, x_col, y_col, call = rlang::caller_env()) {
  if (is.factor(x) || is.factor(y)) {
    if ((is.factor(x) || is.character(x)) && (is.factor(y) || is.character(y))) {
      return(c(as.character(x), as.character(y)))
    }
  } else if (identical(class(x), class(y)) ||
             (is.numeric(x) && is.numeric(y) && !is.object(x) && !is.object(y))) {
    return(c(x, y))
  }
  cli::cli_abort(c(
    "The key columns must have the same type in both tables.",
    "x" = "{.var {x_col}} is {.cls {class(x)[1]}} in {.arg data}, {.var {y_col}} is {.cls {class(y)[1]}} in {.arg reference}.",
    "i" = "Convert one of them first."
  ), call = call)
}

new_match <- function(by, n_rows, n_ref_rows, n_missing, n_ref_missing, counts,
                      n_ref_dup_keys, n_join_rows) {
  structure(list(
    by             = by,
    n_rows         = as.integer(n_rows),
    n_ref_rows     = as.integer(n_ref_rows),
    n_missing      = as.integer(n_missing),
    n_ref_missing  = as.integer(n_ref_missing),
    keys           = tibble::tibble(
      found    = c("in both", "only in data", "only in reference"),
      keys     = as.integer(counts[[1]]),
      rows     = as.integer(counts[[2]]),
      ref_rows = as.integer(counts[[3]])
    ),
    n_ref_dup_keys = as.integer(n_ref_dup_keys),
    # a join can return more rows than an integer counts
    n_join_rows    = as.double(n_join_rows)
  ), class = "inshape_match")
}

#' @export
print.inshape_match <- function(x, ...) {
  same <- names(x$by) == x$by
  describe_header(
    paste0("Match: ", toString(ifelse(same, x$by, paste0(names(x$by), " = ", x$by)))),
    paste0("data: ", count(x$n_rows, "row"), ", reference: ", count(x$n_ref_rows, "row"))
  )
  k <- x$keys
  unmatched <- k$rows[2] + x$n_missing
  problem_line(unmatched,
               paste0("Rows of data without a match: ", big(unmatched),
                      share(unmatched, x$n_rows),
                      if (x$n_missing > 0) paste0(", ", big(x$n_missing), " of them with a missing key")),
               "Every row of data has a match")
  extra <- x$n_join_rows - x$n_rows
  problem_line(x$n_ref_dup_keys,
               paste0("Keys repeated in the reference: ", big(x$n_ref_dup_keys), "; a left join returns ",
                      count(x$n_join_rows, "row"), ", ", big(extra), " more than data"),
               "The reference has each key once: a left join keeps the rows of data as they are")
  problem_line(x$n_ref_missing, paste0("Rows of the reference with a missing key: ", big(x$n_ref_missing)))
  table_block("Keys:", k)
  invisible(x)
}
