#' Assert that key columns identify each row uniquely
#'
#' A checkpoint for keys: every combination of the selected columns must
#' occur at most once. On failure the duplicated rows are reported (see
#' [checkpoints]) grouped by a `dupid` column, so each group
#' of copies can be inspected together. Returns `data`, so it can sit in the
#' middle of a pipeline.
#'
#' The most valuable place for it is just before a join. A lookup table with
#' a duplicated key makes `left_join()` silently multiply rows; checking the
#' key first turns that into an explicit message:
#'
#' ```r
#' codes |>
#'   ensure_unique(branche, abort_msg = "Codebook has duplicate codes") |>
#'   left_join(x = df, by = "branche")
#' ```
#'
#' It is fast on a population register: the key is grouped without sorting
#' it, and the full rows are only touched when there are duplicates to
#' report.
#'
#' @param ... Key columns (tidy-select). If omitted, all columns are used,
#'   which checks for fully duplicated rows.
#' @inheritParams checkpoints
#' @param warn_msg Message shown (and logged) when duplicates exist and no
#'   `abort_msg` is set. Defaults to a description naming the key columns.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' persons <- data.frame(
#'   cpr  = c("a", "b", "b", "c"),
#'   year = c(2024, 2024, 2024, 2024)
#' )
#'
#' # Success: one row per person
#' ensure_unique(persons[persons$cpr != "b", ], cpr, year)
#'
#' # Warning: b appears twice in 2024
#' ensure_unique(persons, cpr, year)
#'
#' \dontrun{
#' df |>
#'   ensure_unique(cvr, year, abort_msg = "Duplicate company-years")
#' }
#'
#' @seealso [ensure_balanced()] for unit-periods, [checkpoints].
#'
#' @export
ensure_unique <- function(data, ...,
                          success_msg = NULL,
                          warn_msg    = NULL,
                          abort_msg   = NULL,
                          log         = getOption("inshape.log")) {

  tbl <- check_table(data)
  key_cols <- if (...length() > 0) select_names(tbl, ...)
  keys <- if (is.null(key_cols)) "all columns" else paste(key_cols, collapse = ", ")

  if (is_remote(tbl)) {
    dups <- remote_duplicates(tbl, key_cols %||% colnames(tbl))
  } else {
    dupid <- dup_ids(data, dup_cols(data, ...))
    rows  <- which(dupid > 0L)
    rows  <- rows[order(dupid[rows])]
    dups  <- tibble::as_tibble(data)[rows, ]
    dups  <- tibble::add_column(dups[setdiff(names(dups), "dupid")],
                                dupid = dupid[rows], .before = 1)
  }

  label <- abort_msg %||% warn_msg
  report_check(
    violations  = dups,
    success_msg = success_msg %||%
      if (is.null(label)) paste0("Unique on ", keys) else paste0("Check passed: ", label),
    fail_msg    = label %||% paste0("Duplicate rows on ", keys),
    abort       = !is.null(abort_msg),
    log         = log,
    key         = key_cols,
    group       = "dupid"
  )
  invisible(data)
}

# The key columns for a duplicate check: the selection, or all columns.
dup_cols <- function(data, ..., call = rlang::caller_env()) {
  cols <- if (...length() == 0) names(data) else names(dplyr::select(data, ...))

  non_atomic <- cols[!vapply(unclass(data)[cols], is.atomic, logical(1))]
  if (length(non_atomic) > 0) {
    cli::cli_abort(c(
      "All grouping columns must be atomic.",
      "x" = "These columns are not atomic: {.var {non_atomic}}."
    ), call = call)
  }
  cols
}

# Per row: 0 for a unique key, otherwise the number of its duplicate group,
# counted in order of first appearance. Counting the rows per group id
# finds the duplicates without sorting the key, see group_ids().
dup_ids <- function(data, cols) {
  dupid <- integer(nrow(data))
  if (nrow(data) < 2 || length(cols) == 0) return(dupid)

  id   <- group_ids(data, cols)
  rows <- which(tabulate(id, attr(id, "n"))[id] > 1L)
  dupid[rows] <- match(id[rows], unique(id[rows]))
  dupid
}
