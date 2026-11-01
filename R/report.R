#' Checkpoints: shared arguments, logging and database tables
#'
#' The `ensure_*()` functions are checkpoints: each states a rule about the
#' structure of the data, warns or aborts with the offending rows when it is
#' broken, and returns `data` invisibly, so it can sit in the middle of a
#' pipeline. This page documents what they share.
#'
#' The offending rows are deliberately not kept in the session afterwards: on
#' a population register a failed check can hold millions of rows, and they
#' would stay in memory until the next failure. Messages are shown literally:
#' braces are not interpolated.
#'
#' A failed check signals a condition of class `inshape_failure` (a warning or
#' an error) that carries the offending rows in its `violations` field.
#' Catch it to keep the rows:
#'
#' ```r
#' tryCatch(
#'   ensure_unique(persons, cpr, abort_msg = "Duplicate persons"),
#'   inshape_failure = \(e) saveRDS(e$violations, "duplicates.rds")
#' )
#' ```
#'
#' ## Personal data
#'
#' The offending rows of a check on a register are personal data: they hold
#' the key, often a cpr number, and every other column of the rows. inshape
#' therefore never writes them to disk itself. Where they may be stored, and
#' in which format, is a decision for the analysis and its data agreement,
#' so it belongs in the script as a line that can be read and reviewed, as
#' in the `tryCatch()` above, not in an option that one line at the top of a
#' script turns on for every check.
#'
#' What inshape does show or write:
#'
#' * **The message** shows the first rows of a failure, 5 by default. A
#'   message also ends up in the output of a scheduled job and in a rendered
#'   report. `options(inshape.preview = 0)` shows only the number of rows
#'   (and groups), never their content; set it in unattended runs and in
#'   documents that leave the secure environment.
#' * **The log** holds the time, the message and the number of rows, never
#'   the rows. The message is your own `warn_msg` or `abort_msg`, or a
#'   description of the check that names only columns.
#' * **The condition** carries the rows in memory, until it is caught or
#'   dropped.
#'
#' ## Logging
#'
#' `log` appends one line per check to a text file. It defaults to a global
#' option, so a script can switch it on once at the top instead of
#' repeating the path in every check:
#'
#' ```r
#' options(inshape.log = format(Sys.time(), "log/%Y%m%d_%H%M%S_checks.log"))
#' ```
#'
#' A log line has the form `time | symbol | message | rows`, where the
#' symbol is a check mark for success, `!` for a warning and a cross for an
#' abort (shown as `v` below):
#'
#' ```
#' 2026-06-11 09:00:03 | v | Unique on cpr, year | 0 rows
#' 2026-06-11 09:00:03 | ! | Gaps in panel | 3 rows
#' ```
#'
#' ## Several checks on the same columns
#'
#' Every check, and every `describe_*()` function, starts by compressing
#' the key columns to integer ids, and on a population register that is
#' the largest single step. A script usually checks the same key several
#' times, so the ids of the last three large columns (from 100,000 rows)
#' are kept for the session and reused when the same column is checked
#' again. A column is recognised by its content, read in one parallel pass
#' that costs a fraction of the compression, never by its name: a column
#' changed in any way, also in place by data.table, is compressed anew.
#' The ids take 4 bytes per row; `options(inshape.cache = FALSE)` turns the
#' cache off and frees it at the next check.
#'
#' ## Database and Arrow tables
#'
#' Every checkpoint also takes a database table from dbplyr, such as a
#' DuckDB table, and an Arrow table or dataset, and checks it where it
#' lives. The violation set is built as a query, and only its size and the
#' preview rows are fetched into R, so a check on a register too large for
#' memory still works. Arrow data is queried through DuckDB with
#' `arrow::to_duckdb()`. This needs the dbplyr package, and duckdb for
#' Arrow.
#'
#' ```r
#' con <- DBI::dbConnect(duckdb::duckdb(), "register.duckdb")
#'
#' dplyr::tbl(con, "persons") |>
#'   ensure_unique(cpr, year) |>
#'   ensure_balanced(cpr, year, gaps_only = TRUE)
#' ```
#'
#' A checkpoint returns the table it was given, still unevaluated, so the
#' pipeline continues in the database. On a failure the condition's
#' `violations` field holds the violation set as a query: `collect()` it to
#' get the rows, or `compute()` it to keep them as a table in the same
#' database, under the access rules of the register itself. Two things differ
#' from data frames, because a database table has no row order:
#' [ensure_unique()] numbers `dupid` in the order of the key instead of
#' first appearance, and spells starting on the same day are ordered by
#' their end in [ensure_no_overlap()].
#'
#' The `describe_*()` functions take database and Arrow tables too. Each
#' summary is computed in the database with grouped counts, and only those
#' counts are fetched, so describing a register costs a few small queries
#' whatever its size. The numbers are the same as in memory, which the
#' tests check. Two differences: participation patterns with the same count
#' at the cut of [describe_panel()]'s `patterns` may be chosen differently,
#' and in [describe_changes()] the keys that came, went or changed stay
#' queries, to `collect()`.
#'
#' @param data A data frame or tibble, a database table (dbplyr, e.g.
#'   DuckDB) or an Arrow table or dataset; see *Database and Arrow tables*.
#' @param success_msg Message shown (and logged) when the rule holds. If
#'   `NULL` (default), it is `"Check passed: <message>"` when `warn_msg` or
#'   `abort_msg` is given, so the log names every check that ran, and a
#'   description of the check otherwise.
#' @param warn_msg Message shown (and logged) when the rule is broken and no
#'   `abort_msg` is set. Defaults to a description of the check.
#' @param abort_msg If provided, `cli::cli_abort()` is called with this
#'   message when the rule is broken. If `NULL` (default), a warning is
#'   issued instead.
#' @param log Optional path to a log file. The directory is created
#'   automatically. Defaults to `getOption("inshape.log")`. The log holds
#'   messages and row counts, never rows; see *Personal data*.
#'
#' @name checkpoints
#' @seealso [ensure_unique()], [ensure_balanced()], [ensure_no_overlap()],
#'   [ensure_constant()], [ensure_within()]
NULL


# Shared engine for the ensure_*() checkpoints ----------------------------

check_data_frame <- function(data, call = rlang::caller_env()) {
  if (!is.data.frame(data)) {
    cli::cli_abort(
      "{.arg data} must be a data frame or tibble, not {.cls {class(data)}}.",
      call = call
    )
  }
}

# Group ids for the key columns, without sorting or copying them ----------
#
# Sorting a character key such as cpr is the expensive step on a population
# register, and grouping does not need an order. Each column is compressed
# to dense integer ids 1..k by the compiled engine (src/group.c), with NA
# as a value of its own, as in match(); see dense_codes().

# Dense ids from "index of the first row with this value", in one pass:
# the fallback for vectors the compiled engine does not take.
dense_ids <- function(first) {
  head <- first == seq_along(first)
  map <- integer(length(first))
  map[head] <- seq_len(sum(head))
  map[first]
}

# Per row, the id of its combination of `cols`. Columns are combined by
# arithmetic, `(id - 1) * k + code`, and only re-numbered by the engine
# when the id space would outgrow the data. The number of groups (or an
# upper bound on it) is kept in the "n" attribute, for tabulate().
group_ids <- function(data, cols) {
  n  <- nrow(data)
  id <- NULL
  k  <- 1
  for (col in cols) {
    code <- dense_codes(data[[col]])
    kx   <- attr(code, "n")
    if (is.null(id)) {
      id <- code
      k  <- kx
    } else if (as.double(k) * kx <= min(4 * n, .Machine$integer.max)) {
      id <- (id - 1L) * kx + code
      k  <- k * kx
    } else {
      id <- dense_codes((id - 1) * kx + code)
      k  <- attr(id, "n")
    }
  }
  if (is.null(id)) id <- rep.int(1L, n)
  # Ids straight from dense_codes() carry only "n" already; copying them
  # to drop attributes would cost 4 bytes a row, also on a cache hit
  if (identical(names(attributes(id)), "n") && identical(attr(id, "n"), k)) return(id)
  structure(as.vector(id), n = k)
}

# Threads for the compiled engine: data.table's setting unless
# options(inshape.threads = ) says otherwise
inshape_threads <- function() {
  as.integer(getOption("inshape.threads", data.table::getDTthreads()))
}

# Dense ids of one vector, with the number of distinct values in "n". The
# compiled hash (src/group.c) does it in one pass; vectors it does not take
# (latin1 strings, lists, integer64) go through match(). Large vectors are
# looked up in the cache first; see dense_cache.
dense_codes <- function(x) {
  if (is.factor(x)) x <- as.integer(x)
  if (inherits(x, "integer64")) return(dense_codes_match(x))
  use_cache <- isTRUE(getOption("inshape.cache", TRUE))
  if (!use_cache && length(dense_cache$codes) > 0) cache_clear()
  key <- if (use_cache && length(x) >= cache_min_rows) {
    .Call(C_inshape_fingerprint, x, inshape_threads())
  }
  if (!is.null(key) && !is.null(code <- dense_cache$codes[[key]])) return(code)
  code <- .Call(C_inshape_dense_ids, x, inshape_threads()) %||% dense_codes_match(x)
  if (!is.null(key)) cache_put(key, code)
  code
}

dense_codes_match <- function(x) {
  code <- dense_ids(if (is.character(x)) data.table::chmatch(x, x) else match(x, x))
  attr(code, "n") <- max(code, 0L)
  code
}

# Cache of dense ids ----------------------------------------------------
#
# Compressing the key, a cpr column on a population register, is the one
# step every check repeats, and a pipeline checks the same column again and
# again: ensure_unique(), then ensure_balanced(), then describe_varying().
# The ids of the last few large columns are kept, keyed by a fingerprint of
# the column's content (src/group.c): its type, length and a checksum of
# every value in order, one parallel pass that costs a small part of the
# compression itself. A column changed in any way, even in place by
# data.table, gets another fingerprint, so stale ids are never used.
# Integer columns with a small range, years and codes, are compressed as
# fast as they are fingerprinted and are not kept.
dense_cache <- new.env(parent = emptyenv())
dense_cache$codes <- list()
cache_min_rows <- 1e5
cache_size <- 3

# Newest last; the oldest beyond cache_size are dropped
cache_put <- function(key, code) {
  codes <- dense_cache$codes
  codes[[key]] <- NULL
  codes[[key]] <- code
  dense_cache$codes <- utils::tail(codes, cache_size)
}

cache_clear <- function() {
  dense_cache$codes <- list()
}

# Last write wins in `x[i] <- v`, so writing in descending order of `value`
# leaves each group's minimum: a grouped min() without sorting the groups.
min_by <- function(value, group, n_groups) {
  o <- order(value, decreasing = TRUE, method = "radix")
  out <- rep(NA_integer_, n_groups)
  out[group[o]] <- value[o]
  out
}

max_by <- function(value, group, n_groups) -min_by(-value, group, n_groups)

# The first row of each group (0 for a group without rows), in one
# compiled forward pass.
first_row_by <- function(group, n_groups) {
  .Call(C_inshape_first_rows, as.integer(group), as.integer(n_groups))
}

# Reports a violation set: success alert when empty, otherwise warning or
# error of class `inshape_failure` carrying the rows. `key` names the
# columns the rule is about; they are moved to the front so a narrow console
# cuts the other columns, not these. `group` names a column grouping the rows
# (`dupid`, `overlap_id`), counted in the summary. `call` defaults to the
# exported checkpoint that called this, so errors name that function.
#
# `violations` may be a lazy table (see check_table()). It is then counted
# and previewed by queries, never fetched in full, and carried on the
# condition as the query itself.
#
# The rows are never written to disk here: they are personal data, and
# where they may be stored is the analysis's decision (see ?checkpoints).
report_check <- function(violations, success_msg, fail_msg, abort,
                         log = NULL,
                         key = character(), group = NULL,
                         call = rlang::caller_env()) {
  remote <- is_remote(violations)
  n <- if (remote) remote_nrow(violations) else nrow(violations)

  if (n == 0) {
    cli::cli_alert_success("{success_msg}")
    write_check_log(log, "\u2714", success_msg, n)
    return(invisible(TRUE))
  }

  n_groups <- if (!is.null(group)) {
    if (remote) remote_nrow(dplyr::distinct(violations, .data[[group]]))
    else length(unique(violations[[group]]))
  }

  n_shown <- preview_count()
  if (remote) {
    # Sorted only now, for the rows that are fetched; see sort_by()
    order <- attr(violations, "inshape_order")
    violations <- dplyr::relocate(violations, dplyr::any_of(c(group, key)))
    if (length(order) > 0) violations <- dplyr::arrange(violations, !!!order)
    # With no preview, no row leaves the database
    shown <- if (n_shown > 0) dplyr::collect(utils::head(violations, n_shown))
  } else {
    violations <- tibble::as_tibble(violations)
    violations <- violations[c(intersect(c(group, key), names(violations)),
                               setdiff(names(violations), c(group, key)))]
    shown <- violations
  }

  write_check_log(log, if (abort) "\u2716" else "!", fail_msg, n)

  found <- if (is.null(n_groups)) "{n} row{?s} found" else "{n} row{?s} in {n_groups} group{?s}"
  bullets <- c(
    "{fail_msg}",
    "i" = paste0(found, if (n_shown > 0) ":" else "."),
    if (n_shown > 0) preview_rows(shown, n = n_shown),
    if (n > n_shown) c("i" = "Catch the {.cls inshape_failure} condition to get all rows; see {.topic inshape::checkpoints}.")
  )

  signal <- if (abort) cli::cli_abort else cli::cli_warn
  signal(bullets, class = "inshape_failure", violations = violations,
         call = call)
  invisible(FALSE)
}

# Rows shown in a failure message: options(inshape.preview = ), 5 by
# default, 0 for counts only (see "Personal data" in ?checkpoints)
preview_count <- function() {
  n <- getOption("inshape.preview", 5)
  if (!is.numeric(n) || length(n) != 1 || is.na(n) || n < 0 || n != trunc(n)) {
    cli::cli_abort(
      "{.code options(inshape.preview = )} must be a whole number of rows, 0 or more.",
      call = NULL
    )
  }
  as.integer(n)
}

# One line per check: time, symbol, message and row count, never the rows
write_check_log <- function(log, symbol, msg, n) {
  if (is.null(log)) return(invisible())
  dir.create(dirname(log), recursive = TRUE, showWarnings = FALSE)
  line <- paste(
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    symbol,
    msg,
    paste(n, if (n == 1) "row" else "rows"),
    sep = " | "
  )
  cat(line, "\n", file = log, append = TRUE, sep = "")
}

# The first rows as a tibble printout, one escaped cli bullet per line. The
# "# A tibble" header repeats the summary bullet and the "print(n = ...)"
# hint does not apply to a message, so both are dropped. Spaces become
# non-breaking, because cli would otherwise collapse the column alignment.
preview_rows <- function(data, n = 5, width = cli::console_width() - 2) {
  if (ncol(data) == 0) return(character())
  lines <- format(tibble::as_tibble(data), n = n, width = width)
  lines <- lines[!grepl("^# A tibble|print\\(n = ", cli::ansi_strip(lines))]
  lines <- gsub(" ", "\u00a0", cli_escape(sub("\\s+$", "", lines)), fixed = TRUE)
  stats::setNames(lines, rep(" ", length(lines)))
}

cli_escape <- function(x) {
  gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE)
}
