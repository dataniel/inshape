#' Describe how well columns work as a key
#'
#' A key should identify each row. When it does not, the next question is
#' what the duplicates are: exact copies of a row, which can simply be
#' dropped, or rows that disagree, which need a rule. `describe_key()`
#' counts the duplicated keys and how many copies each has, separates exact
#' copies from conflicts, and names the columns the conflicting copies
#' disagree in. It judges nothing; require a key with [ensure_unique()].
#'
#' Two copies disagree in a column when their values differ there; a
#' missing value and a present one differ, two missing values do not. Key
#' columns with missing values are counted, since a missing value in a key
#' is usually an error of its own, even when the key is unique.
#'
#' @param data A data frame or tibble, or a database or Arrow table: see
#'   *Database tables* in [checkpoints].
#' @param ... Key columns (tidy-select). If omitted, all columns are used,
#'   which counts fully duplicated rows.
#'
#' @return An object of class `inshape_key`, printed as a summary. It is a
#'   list with `key` (the column names), the counts `n_rows`, `n_keys`
#'   (distinct keys), `n_dup_keys`, `n_dup_rows` (rows sharing a key) and
#'   `n_exact` (duplicated keys whose copies are identical in every
#'   column), and three tibbles: `copies` (`copies`, `keys`), `conflicts`
#'   (`column`, `keys`: the duplicated keys whose copies differ in that
#'   column, most first) and `missing` (`column`, `rows`).
#'
#' @examples
#' firms <- data.frame(
#'   cvr      = c("1", "1", "2", "2", "3"),
#'   year     = c(2024, 2024, 2024, 2024, 2024),
#'   industry = c("A", "A", "B", "C", "A"),
#'   income   = c(10, 10, 5, 5, 7)
#' )
#' # cvr 1 is an exact copy; cvr 2 disagrees on the industry
#' describe_key(firms, cvr, year)
#'
#' @seealso [ensure_unique()] to require a unique key and see the rows,
#'   [describe_panel()] for unit-periods.
#'
#' @export
describe_key <- function(data, ...) {
  tbl <- check_table(data)
  key <- if (...length() == 0) colnames(tbl) else select_names(tbl, ...)
  check_key(key)
  if (is_remote(tbl)) return(remote_describe_key(tbl, key))
  check_atomic(data, key)

  id     <- group_ids(data, key)
  counts <- tabulate(id, attr(id, "n"))
  sizes  <- counts[counts > 1L]
  by_size <- tabulate(sizes)
  keep    <- which(by_size > 0)

  # The duplicated rows only, usually few, with a dense id per key
  rows  <- which(counts[id] > 1L)
  group <- match(id[rows], unique(id[rows]))
  other <- setdiff(names(data), key)
  other <- other[vapply(unclass(data)[other], is.atomic, logical(1))]
  differs <- vapply(other, function(col) {
    sub <- list2DF(list(.g = group, x = data[[col]][rows]))
    pair <- group_ids(sub, c(".g", "x"))
    first <- !duplicated(pair)
    tabulate(group[first], length(sizes)) > 1L
  }, logical(length(sizes)))
  differs <- matrix(differs, nrow = length(sizes))
  n_differ <- colSums(differs)
  ord <- order(n_differ, decreasing = TRUE)
  ord <- ord[n_differ[ord] > 0]

  structure(list(
    key        = key,
    n_rows     = nrow(data),
    n_keys     = sum(counts > 0L),
    n_dup_keys = length(sizes),
    n_dup_rows = length(rows),
    n_exact    = sum(rowSums(differs) == 0),
    copies     = tibble::tibble(copies = keep, keys = by_size[keep]),
    conflicts  = tibble::tibble(column = other[ord], keys = n_differ[ord]),
    missing    = tibble::tibble(
      column = key,
      rows   = vapply(unclass(data)[key], function(x) sum(is.na(x)), integer(1),
                      USE.NAMES = FALSE)
    )
  ), class = "inshape_key")
}

#' @export
print.inshape_key <- function(x, ...) {
  describe_header(paste0("Key: ", toString(x$key)),
                  paste0(count(x$n_rows, "row"), ", ", count(x$n_keys, "distinct key")))
  problem_line(x$n_dup_keys,
               paste0("Duplicated keys: ", big(x$n_dup_keys), " (",
                      count(x$n_dup_rows, "row"), ", ",
                      count(x$n_dup_rows - x$n_dup_keys, "extra row"), ")"),
               "Unique: every key occurs once")
  if (nrow(x$conflicts)) {
    shown <- utils::head(x$conflicts, 5)
    more <- nrow(x$conflicts) - nrow(shown)
    problem_line(1, paste0("Copies differ in: ",
                           paste0(shown$column, " (", big(shown$keys), ")", collapse = ", "),
                           if (more > 0) paste0(" and ", count(more, "more column"))))
  }
  na <- x$missing[x$missing$rows > 0, ]
  problem_line(nrow(na), paste0("Missing values in the key: ",
                                paste0(na$column, " (", big(na$rows), ")", collapse = ", ")))
  if (x$n_dup_keys > 0) {
    note_line(paste0("Exact copies, identical in every column: ",
                     big(x$n_exact), " of ", count(x$n_dup_keys, "key")))
    note_line(paste0("Copies per duplicated key: ",
                     paste0(x$copies$copies, " (", big(x$copies$keys), ")", collapse = ", ")))
  }
  invisible(x)
}
