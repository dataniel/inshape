#' Checkpoints: shared arguments, logging and database tables
#'
#' The `expect_*()` functions are checkpoints: each states a rule about the
#' structure of the data, warns or aborts with the offending rows when it is
#' broken, and returns `data` invisibly, so it can sit in the middle of a
#' pipeline. This page documents what they share.
#'
#' The offending rows are deliberately not kept in the session afterwards: on
#' a population register a failed check can hold millions of rows, and they
#' would stay in memory until the next failure. Messages are shown literally:
#' braces are not interpolated.
#'
#' A failed check signals a condition of class `lustrum_failure` (a warning or
#' an error) that carries the offending rows in its `violations` field.
#' Scheduled pipelines can catch it and keep the rows:
#'
#' ```r
#' tryCatch(
#'   ensure_unique(persons, cpr, abort_msg = "Duplicate persons"),
#'   lustrum_failure = \(e) saveRDS(e$violations, "duplicates.rds")
#' )
#' ```
#'
#' ## Logging and dumping
#'
#' `log` appends one line per check to a text file, and `dump` writes the
#' offending rows to a CSV file in a directory. Both default to a global
#' option, so a script can switch them on once at the top instead of
#' repeating the path in every check:
#'
#' ```r
#' options(
#'   lustrum.log  = format(Sys.time(), "log/%Y%m%d_%H%M%S_checks.log"),
#'   lustrum.dump = "log/violations"
#' )
#' ```
#'
#' A log line has the form `time | symbol | message | rows [| dump file]`,
#' where the symbol is a check mark for success, `!` for a warning and a
#' cross for an abort (shown as `v` below):
#'
#' ```
#' 2026-06-11 09:00:03 | v | Unique on cpr, year | 0 rows
#' 2026-06-11 09:00:03 | ! | Gaps in panel | 3 rows | log/violations/20260611_090003_Gaps_in_panel.csv
#' ```
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
#' get the rows. `dump` fetches and writes all of them. Two things differ
#' from data frames, because a database table has no row order:
#' [ensure_unique()] numbers `dupid` in the order of the key instead of
#' first appearance, and spells starting on the same day are ordered by
#' their end in [ensure_no_overlap()].
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
#'   automatically. Defaults to `getOption("lustrum.log")`.
#' @param dump Optional directory. When the check fails, the offending rows
#'   are written there as a timestamped CSV file (UTF-8 with BOM, so Excel
#'   reads Danish letters correctly). Defaults to `getOption("lustrum.dump")`.
#'
#' @name checkpoints
#' @seealso [ensure_unique()], [ensure_balanced()], [ensure_no_overlap()]
NULL


# Shared engine for the expect_*() checkpoints ----------------------------

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
# register, and grouping does not need an order. R stores each distinct
# string once, and data.table::chmatch() uses that to find, for every row,
# the first row with the same string in one linear pass. The ids below are
# built from that: dense integers 1..k in order of first appearance, with
# NA as a value of its own, as in duplicated().

# Dense ids from "index of the first row with this value", in one pass.
dense_ids <- function(first) {
  head <- first == seq_along(first)
  map <- integer(length(first))
  map[head] <- seq_len(sum(head))
  map[first]
}

# Per row, the id of its combination of `cols`. Columns are combined by
# arithmetic, `(id - 1) * k + code`, and only re-numbered through match()
# when the id space would outgrow the data. The number of groups (or an
# upper bound on it) is kept in the "n" attribute, for tabulate().
group_ids <- function(data, cols) {
  n  <- nrow(data)
  id <- rep.int(1L, n)
  k  <- 1
  for (col in cols) {
    x <- data[[col]]
    if (is.factor(x)) x <- as.integer(x)
    code <- dense_ids(if (is.character(x)) data.table::chmatch(x, x) else match(x, x))
    kx   <- max(code, 0L)
    if (k * kx <= 4 * n && k * kx <= .Machine$integer.max) {
      id <- (id - 1L) * kx + code
      k  <- k * kx
    } else {
      id <- (id - 1) * kx + code
      id <- dense_ids(match(id, id))
      k  <- max(id, 0L)
    }
  }
  structure(id, n = k)
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

# The first row of each group, by the same last-write-wins rule.
first_row_by <- function(group, n_groups) {
  out <- integer(n_groups)
  rows <- rev(seq_along(group))
  out[group[rows]] <- rows
  out
}

# Reports a violation set: success alert when empty, otherwise warning or
# error of class `lustrum_failure` carrying the rows. `key` names the
# columns the rule is about; they are moved to the front so a narrow console
# cuts the other columns, not these. `group` names a column grouping the rows
# (`dupid`, `overlap_id`), counted in the summary. `call` defaults to the
# exported checkpoint that called this, so errors name that function.
#
# `violations` may be a lazy table (see check_table()). It is then counted
# and previewed by queries, only fetched in full for `dump`, and carried on
# the condition as the query itself.
report_check <- function(violations, success_msg, fail_msg, abort,
                         log = NULL, dump = NULL,
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

  if (remote) {
    # Sorted only now, for the rows that are fetched; see sort_by()
    order <- attr(violations, "lustrum_order")
    violations <- dplyr::relocate(violations, dplyr::any_of(c(group, key)))
    if (length(order) > 0) violations <- dplyr::arrange(violations, !!!order)
    shown <- dplyr::collect(utils::head(violations, preview_n))
  } else {
    violations <- tibble::as_tibble(violations)
    violations <- violations[c(intersect(c(group, key), names(violations)),
                               setdiff(names(violations), c(group, key)))]
    shown <- violations
  }

  dump_file <- dump_violations(violations, dump, fail_msg)
  write_check_log(log, if (abort) "\u2716" else "!", fail_msg, n, dump_file)

  bullets <- c(
    "{fail_msg}",
    "i" = if (is.null(n_groups)) "{n} row{?s} found:"
          else "{n} row{?s} in {n_groups} group{?s}:",
    preview_rows(shown, n = preview_n),
    if (!is.null(dump_file)) c("i" = "All rows written to {.path {dump_file}}.")
    else if (n > preview_n) c("i" = "Set {.arg dump} or {.code options(lustrum.dump = )} to write all rows to a CSV file.")
  )

  signal <- if (abort) cli::cli_abort else cli::cli_warn
  signal(bullets, class = "lustrum_failure", violations = violations,
         call = call)
  invisible(FALSE)
}

# Rows shown in a failure message
preview_n <- 5

write_check_log <- function(log, symbol, msg, n, dump_file = NULL) {
  if (is.null(log)) return(invisible())
  dir.create(dirname(log), recursive = TRUE, showWarnings = FALSE)
  line <- paste(c(
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    symbol,
    msg,
    paste(n, if (n == 1) "row" else "rows"),
    dump_file
  ), collapse = " | ")
  cat(line, "\n", file = log, append = TRUE, sep = "")
}

dump_violations <- function(violations, dump, msg) {
  if (is.null(dump)) return(NULL)
  dir.create(dump, recursive = TRUE, showWarnings = FALSE)
  slug <- substr(gsub("^_+|_+$", "", gsub("[^[:alnum:]]+", "_", msg)), 1, 60)
  file <- file.path(dump, paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", slug, ".csv"))
  if (is_remote(violations)) violations <- dplyr::collect(violations)
  data.table::fwrite(violations, file, bom = TRUE)
  file
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
