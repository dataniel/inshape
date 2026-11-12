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
#' @param warn_msg Message shown when duplicates exist and no
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
                          abort_msg   = NULL) {

  tbl <- check_table(data)
  key_cols <- if (...length() > 0) select_names(tbl, ...)
  keys <- if (is.null(key_cols)) "all columns" else paste(key_cols, collapse = ", ")
  cols <- key_cols %||% colnames(tbl)
  check_key(cols)

  if (is_remote(tbl)) {
    dups <- remote_duplicates(tbl, cols)
  } else {
    check_atomic(data, cols)
    dupid <- dup_ids(data, cols)
    rows  <- which(dupid > 0L)
    rows  <- rows[order(dupid[rows])]
    dups  <- tibble::as_tibble(data)[rows, ]
    dups <- tibble::add_column(dups,
      !!diagnostic_name(data, "dupid") := dupid[rows], .before = 1)
  }

  group <- diagnostic_name(tbl, "dupid")
  name  <- data_label(rlang::caller_arg(data))
  report_check(
    dups,
    pass = paste0("Unique on ", keys),
    fail = paste0("Duplicate rows on ", keys),
    success_msg, warn_msg, abort_msg,
    key   = key_cols,
    group = group,
    # a check on all columns has no columns to leave out
    show  = if (!is.null(key_cols)) character(),
    summary = function(v, n) summarise_duplicates(v, group, cols, key_cols, name, n)
  )
  invisible(data)
}

# What a set of duplicates is: groups that are exact copies, which
# dplyr::distinct() drops, and groups that differ, which need a rule, with
# the columns they differ in (the same count as describe_key()). Two
# missing values do not differ; a missing and a present one do.
summarise_duplicates <- function(v, group, cols, key_cols, name, n) {
  other <- setdiff(colnames(v), c(group, cols))
  if (is_remote(v)) {
    differs <- remote_group_differs(v, group, other)
  } else {
    other <- other[vapply(unclass(v)[other], function(x) is.atomic(x) && is.null(dim(x)), logical(1))]
    g <- v[[group]]
    n_groups <- max(g, 0L)
    flags <- vapply(other, function(col) {
      pair <- group_ids(list2DF(list(.g = g, x = v[[col]])), c(".g", "x"))
      first <- !duplicated(pair)
      tabulate(g[first], n_groups) > 1L
    }, logical(n_groups))
    flags <- matrix(flags, nrow = n_groups)
    differs <- list(n_groups = n_groups,
                    exact = sum(rowSums(flags) == 0),
                    per_column = stats::setNames(colSums(flags), other))
  }
  per <- sort(differs$per_column[differs$per_column > 0], decreasing = TRUE)
  n_differ <- differs$n_groups - differs$exact

  one <- differs$n_groups == 1
  lines <- character()
  if (differs$exact > 0) {
    lines <- c(lines,
      if (one) "The copies are identical in every column"
      else if (n_differ == 0) "All groups are exact copies"
      else paste(big(differs$exact), if (differs$exact == 1) "group is an exact copy" else "groups are exact copies"))
  }
  if (n_differ > 0) {
    shown <- utils::head(per, 5)
    lines <- c(lines, paste0(
      if (one) "The copies differ" else paste(big(n_differ), if (n_differ == 1) "group differs" else "groups differ"),
      " in: ",
      if (one) paste(names(shown), collapse = ", ")
      else paste0(names(shown), " (", big(shown), ")", collapse = ", "),
      if (length(per) > 5) paste0(" and ", count(length(per) - 5, "more column"))))
  }
  lines <- c(lines, pattern_lines(v, key_cols, n, groups = differs$n_groups))

  hints <- character()
  if (differs$exact > 0) {
    hints <- c(hints, paste0("To drop the exact copies: dplyr::distinct(", name, ")"))
  }
  if (n_differ > 0 && length(key_cols)) {
    hints <- c(hints, paste0(
      "Copies that differ need a rule for which to keep, e.g. ",
      "dplyr::slice_max(", name, ", <column>, by = ", code_cols(key_cols), ")"))
  }
  list(lines = lines, hints = hints, show = names(utils::head(per, 3)))
}

# The same counts in one query: per group whether each column holds two
# values, as min() and max() differing or some but not all rows missing.
remote_group_differs <- function(v, group, other) {
  v <- dplyr::ungroup(v)
  n_groups <- remote_nrow(dplyr::distinct(v, .data[[group]]))
  if (length(other) == 0) {
    return(list(n_groups = n_groups, exact = n_groups, per_column = integer()))
  }
  flag_cols <- paste0(".inshape_d", seq_along(other))
  flags <- lapply(rlang::syms(other), function(col) {
    rlang::expr(dplyr::if_else(
      min(!!col, na.rm = TRUE) != max(!!col, na.rm = TRUE) |
        (sum(dplyr::if_else(is.na(!!col), 1L, 0L), na.rm = TRUE) > 0L &
           sum(dplyr::if_else(is.na(!!col), 1L, 0L), na.rm = TRUE) < dplyr::n()),
      1L, 0L, missing = 0L))
  })
  names(flags) <- flag_cols
  per_group <- v |>
    dplyr::group_by(.data[[group]]) |>
    dplyr::summarise(!!!flags, .groups = "drop")
  any_flag <- Reduce(function(a, b) rlang::expr(!!a + !!b), rlang::syms(flag_cols))
  sums <- lapply(rlang::syms(flag_cols), function(col) rlang::expr(sum(!!col, na.rm = TRUE)))
  names(sums) <- flag_cols
  totals <- per_group |>
    dplyr::summarise(!!!sums,
                     .inshape_exact = sum(dplyr::if_else(!!any_flag == 0L, 1L, 0L), na.rm = TRUE)) |>
    dplyr::collect()
  list(n_groups = n_groups,
       exact = as.numeric(totals$.inshape_exact),
       per_column = stats::setNames(as.numeric(unlist(totals[flag_cols])), other))
}

# A key of no columns would make every row a copy of every other. It comes
# from a selection that matched nothing, e.g. a misspelt starts_with(), and
# passing it by would report a key as unique that was never looked at.
check_key <- function(cols, call = rlang::caller_env()) {
  if (length(cols) == 0) {
    cli::cli_abort(c(
      "The key selects no columns.",
      "i" = "Leave the selection out to use all columns."
    ), call = call)
  }
}

# Key columns must be vectors: a list column has no values to group by.
check_atomic <- function(data, cols, call = rlang::caller_env()) {
  non_atomic <- cols[!vapply(unclass(data)[cols], is.atomic, logical(1))]
  if (length(non_atomic) > 0) {
    cli::cli_abort(c(
      "All grouping columns must be atomic.",
      "x" = "These columns are not atomic: {.var {non_atomic}}."
    ), call = call)
  }
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
