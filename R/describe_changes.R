#' Describe what changed between two extracts of a register
#'
#' A register is delivered again and again, and each delivery should differ
#' from the last only where the world did: new persons, new years. When the
#' same person-year has another birth date, sex or municipality than last
#' time, a correction was made, and in the Greenlandic and Danish CPR,
#' corrections have no time limit. `describe_changes()` compares two
#' extracts by their key and counts the keys that came and went, the
#' columns that came, went or changed type, and for every column the keys
#' whose value changed, went missing or was filled in. It judges nothing.
#'
#' Both extracts must be unique on the key; check with [ensure_unique()] or
#' [describe_key()] first. Two missing values are equal. A column whose
#' type changed, e.g. from integer to character, is compared as text, and
#' integer and double columns as numbers.
#' Shared non-key list or matrix columns are not compared. Their names are
#' returned in `columns_skipped` and shown when the summary is printed.
#'
#' @section Why it is fast:
#' The keys of both extracts are compressed to integer ids together, by
#' the compiled engine, so matching a row to its row in the other extract
#' is an array lookup, with no join or sort. Each shared column is then
#' compared in one compiled pass over the matched rows.
#'
#' @param old,new The earlier and the later extract: data frames, or two
#'   database tables on the same connection (see *Database tables*).
#' @param ... Key columns (tidy-select), e.g. `cpr, year`, present in both.
#'
#' @section Database tables:
#' Two dbplyr tables on the same connection, such as two DuckDB tables or
#' two Parquet files read through DuckDB, are compared in the database:
#' the counts are fetched, and `added`, `removed` and `changed` stay
#' queries, to `dplyr::collect()` when needed.
#'
#' @return An object of class `inshape_changes`, printed as a summary. It is
#'   a list with the counts `n_old`, `n_new`, `n_kept` (keys in both),
#'   `n_added`, `n_removed` and `n_changed` (kept keys with any changed
#'   column); `columns_added`, `columns_removed` and `type_changed`
#'   (column names); `columns_skipped` (shared columns not compared);
#'   `columns`, a tibble with one row per compared shared column:
#'   `column`, `changed` (another value), `went_missing` (a value, now
#'   missing), `filled_in` (missing, now a value) and `share` (of the kept
#'   keys with any of the three), most changed first; and `added` and
#'   `removed` (the keys) and `changed` (the keys with `n_columns`, the
#'   number of columns that changed).
#'
#' @examples
#' old <- data.frame(cpr = c("a", "b", "c"), year = 2023,
#'                   sex = c("F", "M", "F"), born = c(1950, 1960, NA))
#' new <- data.frame(cpr = c("a", "b", "d"), year = 2023,
#'                   sex = c("F", "F", "M"), born = c(1950, 1960, 1990))
#' # c is gone, d is new, and b changed sex
#' describe_changes(old, new, cpr, year)
#'
#' @seealso [describe_key()] to check the key first.
#'
#' @export
describe_changes <- function(old, new, ...) {
  if (is_remote(old) || is_remote(new)) {
    return(remote_changes(check_table(old), check_table(new), ...))
  }
  check_data_frame(old)
  check_data_frame(new)
  key <- select_names(old, ...)
  if (length(key) == 0) cli::cli_abort("Select at least one key column.")
  missing_key <- setdiff(key, names(new))
  if (length(missing_key)) {
    cli::cli_abort("Key column{?s} {.var {missing_key}} {?is/are} not in {.arg new}.")
  }

  n_old <- nrow(old)
  n_new <- nrow(new)
  both <- list2DF(lapply(stats::setNames(key, key), function(k) {
    v <- aligned(old[[k]], new[[k]])
    c(v$a, v$b)
  }))
  id <- group_ids(both, key)
  n_ids <- attr(id, "n")
  id_old <- id[seq_len(n_old)]
  id_new <- id[n_old + seq_len(n_new)]
  for (side in c("old", "new")) {
    ids <- if (side == "old") id_old else id_new
    if (any(tabulate(ids, n_ids) > 1L)) {
      cli::cli_abort(c("The key {.var {key}} is not unique in {.arg {side}}.",
                       "i" = "See the duplicates with {.code describe_key({side}, {toString(key)})}."))
    }
  }

  row_new <- integer(n_ids)
  row_new[id_new] <- seq_len(n_new)
  row_old <- integer(n_ids)
  row_old[id_old] <- seq_len(n_old)
  match_new <- row_new[id_old]
  kept_old <- which(match_new > 0L)
  kept_new <- match_new[kept_old]
  removed  <- which(match_new == 0L)
  added    <- which(row_old[id_new] == 0L)

  shared <- setdiff(intersect(names(old), names(new)), key)
  skipped <- skipped_changes(old, new, shared)
  shared <- setdiff(shared, skipped)
  type_changed <- shared[!vapply(shared, function(col) {
    identical(class(old[[col]]), class(new[[col]]))
  }, logical(1))]

  # Per column the counts of codes 1-3, and the kept keys that changed,
  # usually few, collected per column rather than counted on every key
  hits <- vector("list", length(shared))
  counts <- matrix(0L, nrow = 3, ncol = length(shared))
  for (k in seq_along(shared)) {
    code <- pair_changes(old[[shared[k]]], new[[shared[k]]], kept_old, kept_new)
    counts[, k] <- tabulate(code, 3L)
    if (sum(counts[, k]) > 0L) hits[[k]] <- which(code > 0L)
  }
  hits <- unlist(hits)
  hit <- sort(unique(hits))
  n_columns <- tabulate(match(hits, hit), length(hit))
  any_change <- colSums(counts)
  columns <- tibble::tibble(
    column       = shared,
    changed      = counts[1, ],
    went_missing = counts[2, ],
    filled_in    = counts[3, ],
    share        = if (length(kept_old)) any_change / length(kept_old) else rep(NA_real_, length(shared))
  )
  columns <- columns[order(-any_change, columns$column), ]

  changed <- tibble::as_tibble(lapply(unclass(old)[key], `[`, kept_old[hit]))
  changed$n_columns <- n_columns

  structure(list(
    key             = key,
    n_old           = n_old,
    n_new           = n_new,
    n_kept          = length(kept_old),
    n_added         = length(added),
    n_removed       = length(removed),
    n_changed       = length(hit),
    columns_added   = setdiff(names(new), names(old)),
    columns_removed = setdiff(names(old), names(new)),
    type_changed    = type_changed,
    columns_skipped = skipped,
    columns         = columns,
    added           = tibble::as_tibble(lapply(unclass(new)[key], `[`, added)),
    removed         = tibble::as_tibble(lapply(unclass(old)[key], `[`, removed)),
    changed         = changed
  ), class = "inshape_changes")
}

skipped_changes <- function(old, new, shared) {
  supported <- function(x) is.atomic(x) && is.null(dim(x))
  shared[!vapply(shared, function(col) {
    supported(old[[col]]) && supported(new[[col]])
  }, logical(1))]
}

# Two columns as vectors of one type that compare as R's == does: factors
# as their labels, dates and times as numbers, integer and double as
# double, and anything else that differs in type as text
aligned <- function(a, b) {
  if (is.factor(a)) a <- as.character(a)
  if (is.factor(b)) b <- as.character(b)
  if (inherits(a, "POSIXt") && inherits(b, "POSIXt")) return(list(a = as.double(a), b = as.double(b)))
  if (inherits(a, "Date") && inherits(b, "Date")) return(list(a = as.double(a), b = as.double(b)))
  if (is.object(a) || is.object(b)) return(list(a = as.character(a), b = as.character(b)))
  if (typeof(a) == typeof(b)) return(list(a = a, b = b))
  if (is.numeric(a) && is.numeric(b)) return(list(a = as.double(a), b = as.double(b)))
  list(a = as.character(a), b = as.character(b))
}

# Per matched pair: 0 equal, 1 changed, 2 went missing, 3 filled in; in one
# compiled pass (src/group.c), or in R for types the pass does not take
pair_changes <- function(a, b, ia, ib) {
  v <- aligned(a, b)
  code <- .Call(C_inshape_pair_changes, v$a, v$b, as.integer(ia), as.integer(ib))
  if (!is.null(code)) return(code)
  x <- v$a[ia]
  y <- v$b[ib]
  na_x <- is.na(x)
  na_y <- is.na(y)
  out <- integer(length(ia))
  out[!na_x & !na_y & x != y] <- 1L
  out[!na_x & na_y] <- 2L
  out[na_x & !na_y] <- 3L
  out
}

#' @export
print.inshape_changes <- function(x, ...) {
  cli::cat_rule(paste0("Changes by ", toString(x$key)))
  cli::cat_line(count(x$n_old, "row"), " before, ", count(x$n_new, "row"), " now, ",
                count(x$n_kept, "key"), " in both")
  cli::cat_line()
  cli::cat_bullet(paste0("New keys: ", big(x$n_added), share(x$n_added, x$n_new)))
  cli::cat_bullet(paste0("Keys gone: ", big(x$n_removed), share(x$n_removed, x$n_old)))
  cli::cat_bullet(paste0("Keys with a changed value: ", big(x$n_changed),
                         share(x$n_changed, x$n_kept)))
  if (length(x$columns_added)) cli::cat_bullet(paste0("New columns: ", toString(x$columns_added)))
  if (length(x$columns_removed)) cli::cat_bullet(paste0("Columns gone: ", toString(x$columns_removed)))
  if (length(x$type_changed)) cli::cat_bullet(paste0("Columns with another type: ", toString(x$type_changed)))
  if (length(x$columns_skipped)) cli::cat_bullet(paste0("Columns not compared: ", toString(x$columns_skipped)))
  if (nrow(x$columns)) {
    cli::cat_line()
    cli::cat_line("Changes per column, among the keys in both:")
    shown <- x$columns
    shown$share <- ifelse(is.na(shown$share), "", sprintf("%.2f%%", 100 * shown$share))
    print_table(shown)
  }
  invisible(x)
}
