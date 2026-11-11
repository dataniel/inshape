#' Assert that every key occurs in a reference register
#'
#' Reports rows of `data` whose key does not occur in `reference`. Duplicate
#' reference keys do not multiply rows; use [ensure_unique()] separately if
#' the reference must also be unique. Only the direction from `data` to
#' `reference` is checked. Missing key components never match by default.
#'
#' @param reference A reference data frame or database/Arrow table.
#'   For database input, a local reference is sent as an inline query;
#'   remote references must be on the same connection. Local input requires
#'   a local reference. No table is written to the database.
#' @param by Character vector of key columns, optionally named to map names
#'   in `data` to names in `reference`, e.g. `c(cpr = "person_id")`.
#'   Required: no implicit natural join is performed.
#' @param na_matches `"never"` (default), or `"na"` to match missing keys.
#' @inheritParams checkpoints
#' @param warn_msg Message when unmatched rows are found.
#' @return `data` invisibly, unchanged. Failures carry unmatched input rows.
#' @seealso [ensure_unique()], [checkpoints].
#' @examples
#' income <- data.frame(cpr = c("a", "b"), year = 2024)
#' population <- data.frame(cpr = "a", year = 2024)
#' ensure_matched(income, population, by = c("cpr", "year"))
#' @export
ensure_matched <- function(data, reference, by, na_matches = c("never", "na"),
                           success_msg = NULL, warn_msg = NULL,
                           abort_msg = NULL) {
  tbl <- check_table(data)
  ref <- check_table(reference)
  na_matches <- match.arg(na_matches)
  if (missing(by) || !is.character(by) || !length(by) || anyNA(by) || any(!nzchar(by))) {
    cli::cli_abort("{.arg by} must be a non-empty character vector of key columns.")
  }
  left <- names(by)
  if (is.null(left)) left <- by
  if (anyNA(left)) cli::cli_abort("Names in {.arg by} must not be missing.")
  left[!nzchar(left)] <- by[!nzchar(left)]
  if (anyDuplicated(left) || anyDuplicated(unname(by))) {
    cli::cli_abort("{.arg by} must not repeat a key column.")
  }
  if (!all(left %in% colnames(tbl)) || !all(by %in% colnames(ref))) {
    cli::cli_abort("All {.arg by} columns must exist in their respective tables.")
  }
  by <- stats::setNames(unname(by), left)
  ref <- dplyr::select(ref, dplyr::all_of(unname(by)))
  if (is_remote(tbl)) {
    if (!is_remote(ref)) ref <- dbplyr::copy_inline(dbplyr::remote_con(tbl), ref)
    if (!dplyr::same_src(tbl, ref)) cli::cli_abort("Database tables must use the same connection.")
  } else if (is_remote(ref)) {
    cli::cli_abort("A local {.arg data} requires a local {.arg reference}.")
  }
  rows <- if (is_remote(tbl)) {
    sort_by(dplyr::anti_join(tbl, ref, by = by, na_matches = na_matches), na_first(left))
  } else if (same_classes(data, ref, left, unname(by))) {
    tibble::as_tibble(data)[unmatched_rows(data, ref, left, unname(by), na_matches), ]
  } else {
    # Keys of different classes are left to the join, which converts them
    dplyr::anti_join(tbl, ref, by = by, na_matches = na_matches)
  }
  report_check(
    rows,
    pass = paste0("Matched in the reference: ", toString(left)),
    fail = paste0("Keys missing from the reference: ", toString(left)),
    success_msg, warn_msg, abort_msg,
    key = left
  )
  invisible(data)
}

# Whether the columns `x_cols` of `x` and `y_cols` of `y` have the same
# classes pairwise, so that their values can be combined with c()
same_classes <- function(x, y, x_cols, y_cols) {
  all(mapply(function(a, b) identical(class(x[[a]]), class(y[[b]])), x_cols, y_cols))
}

# Rows of `data` whose key is not in `ref`, in the order of the data. The
# keys of both tables are compressed together in one hash pass (see
# group_ids()), where a join on a character cpr is several times slower.
# A missing value is a value of its own there, as with na_matches = "na";
# with "never" a row with a missing key is unmatched whatever `ref` holds.
unmatched_rows <- function(data, ref, cols, ref_cols, na_matches) {
  n <- nrow(data)
  both <- lapply(seq_along(cols), function(k) c(data[[cols[k]]], ref[[ref_cols[k]]]))
  names(both) <- paste0("k", seq_along(cols))
  id <- group_ids(data.table::setDT(both), names(both))
  in_ref <- logical(attr(id, "n"))
  in_ref[id[n + seq_len(nrow(ref))]] <- TRUE
  bad <- !in_ref[id[seq_len(n)]]
  if (na_matches == "never") {
    for (col in cols) bad <- bad | is.na(data[[col]])
  }
  which(bad)
}
