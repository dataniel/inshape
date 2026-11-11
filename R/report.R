#' Checkpoints: shared arguments, personal data and database tables
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
#' Diagnostic columns such as `dupid`, `overlap_id`, `outside` and `reason`
#' receive a numeric suffix when their name is already in the input (for
#' example `dupid.1`). All original columns keep their names and values.
#'
#' A failed check signals a condition of class `inshape_failure` (a warning or
#' an error) that carries the offending rows in its `violations` field.
#' [violations()] catches it and returns the rows, to look at all of them
#' in the session:
#'
#' ```r
#' dups <- violations(ensure_unique(persons, cpr))
#' ```
#'
#' ## Personal data
#'
#' inshape is made for interactive review of registers, at the console in
#' the environment where the data lives. The offending rows of a check are
#' personal data: they hold the key, often a cpr number, and every other
#' column of the rows. inshape therefore writes nothing to disk, neither
#' the rows nor a log of the checks, and keeps nothing after a check:
#'
#' * **The message** shows the number of rows and the first 5 of them at
#'   the console. Output that is kept, such as a rendered report or a
#'   shared screen, keeps them too, so run the checks at the console.
#' * **The condition** carries the rows in memory, until it is caught, by
#'   [violations()] for one, or dropped. Whether any of them are stored, and where, is for the analysis
#'   and its data agreement to decide, not the package.
#'
#' ## Speed
#'
#' Every check, and every `describe_*()` function, starts by compressing
#' the key columns to integer ids with a compiled, multi-threaded hash,
#' without sorting them. Nothing is kept between calls, so each check
#' compresses its columns anew; even so, [ensure_unique()] on 5 million
#' rows takes about 0.2 seconds (see the benchmarks in the repository). The
#' engine uses as many threads as data.table, set with
#' [data.table::setDTthreads()].
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
#' `violations` field, and so [violations()], holds the violation set as a
#' query: `collect()` it to get the rows. Two things differ
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
#' @param success_msg Message shown when the rule holds. If `NULL`
#'   (default), it is `"Check passed: <message>"` when `warn_msg` or
#'   `abort_msg` is given, so the console names every check that ran, and a
#'   description of the check otherwise.
#' @param warn_msg Message shown when the rule is broken and no `abort_msg`
#'   is set. Defaults to a description of the check.
#' @param abort_msg If provided, `cli::cli_abort()` is called with this
#'   message when the rule is broken. If `NULL` (default), a warning is
#'   issued instead.
#'
#' @name checkpoints
#' @seealso [ensure_unique()], [ensure_balanced()], [ensure_no_overlap()],
#'   [ensure_valid_spells()], [ensure_constant()], [ensure_within()],
#'   [ensure_codes()] and [ensure_matched()] for the rules, and
#'   [violations()] for the rows that break one.
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
  # to drop attributes would cost 4 bytes a row
  if (identical(names(attributes(id)), "n") && identical(attr(id, "n"), k)) return(id)
  structure(as.vector(id), n = k)
}

# Threads for the compiled engine: data.table's setting
inshape_threads <- function() {
  as.integer(data.table::getDTthreads())
}

# Dense ids of one vector, with the number of distinct values in "n". The
# compiled hash (src/group.c) does it in one pass; vectors it does not take
# (latin1 strings, lists, integer64) go through match(). Nothing is kept
# between calls.
dense_codes <- function(x) {
  if (is.factor(x)) x <- as.integer(x)
  if (inherits(x, "integer64")) return(dense_codes_match(x))
  .Call(C_inshape_dense_ids, x, inshape_threads()) %||% dense_codes_match(x)
}

dense_codes_match <- function(x) {
  code <- dense_ids(if (is.character(x)) data.table::chmatch(x, x) else match(x, x))
  attr(code, "n") <- max(code, 0L)
  code
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
# error of class `inshape_failure` carrying the rows. `pass` and `fail`
# describe the check; the user's `success_msg`, `warn_msg` and `abort_msg`
# replace them, and an `abort_msg` turns the warning into an error. `key`
# names the columns the rule is about; they are moved to the front so a
# narrow console cuts the other columns, not these. `group` names a column
# grouping the rows (`dupid`, `overlap_id`), counted in the summary. `call`
# defaults to the exported checkpoint that called this, so errors name that
# function.
#
# `violations` may be a lazy table (see check_table()). It is then counted
# and previewed by queries, never fetched in full, and carried on the
# condition as the query itself.
#
# Nothing is written to disk here, neither rows nor a log: the rows are
# personal data, and inshape is for interactive review (see ?checkpoints).
report_check <- function(violations, pass, fail,
                         success_msg = NULL, warn_msg = NULL, abort_msg = NULL,
                         key = character(), group = NULL,
                         call = rlang::caller_env()) {
  label  <- abort_msg %||% warn_msg
  remote <- is_remote(violations)
  n <- if (remote) remote_nrow(violations) else nrow(violations)

  if (n == 0) {
    success_msg <- success_msg %||%
      if (is.null(label)) pass else paste0("Check passed: ", label)
    cli::cli_alert_success("{success_msg}")
    return(invisible(TRUE))
  }

  n_groups <- if (!is.null(group)) {
    if (remote) remote_nrow(dplyr::distinct(violations, .data[[group]]))
    else length(unique(violations[[group]]))
  }

  if (remote) {
    # Sorted only now, for the rows that are fetched; see sort_by()
    order <- attr(violations, "inshape_order")
    violations <- dplyr::relocate(violations, dplyr::any_of(c(group, key)))
    if (length(order) > 0) violations <- dplyr::arrange(violations, !!!order)
    shown <- dplyr::collect(utils::head(violations, preview_n))
  } else {
    violations <- tibble::as_tibble(violations)
    violations <- violations[c(intersect(c(group, key), names(violations)),
                               setdiff(names(violations), c(group, key)))]
    shown <- violations
  }

  # The message is laid out here, once, and signalled as it is. Handed to
  # cli as bullets, an aborting check formats them twice, and the second
  # pass collapses the spaces that align the columns of the preview.
  info <- cli::col_cyan(cli::symbol$info)
  lines <- c(
    label %||% fail,
    paste0(info, " ", count(n, "row"),
           if (is.null(n_groups)) " found:"
           else paste0(" in ", count(n_groups, "group"), ":")),
    preview_rows(shown, n = preview_n),
    if (n > preview_n) paste0(info, " Wrap the check in violations() to get all rows.")
  )

  signal <- if (is.null(abort_msg)) rlang::warn else rlang::abort
  signal(paste(lines, collapse = "\n"), class = "inshape_failure",
         violations = violations, call = call, use_cli_format = FALSE)
  invisible(FALSE)
}

# Rows shown in a failure message
preview_n <- 5

# Keep every input column; suffix only the diagnostic column on collision.
diagnostic_name <- function(data, name) {
  utils::tail(make.unique(c(colnames(data), name)), 1L)
}

# The first rows as the lines of a tibble printout, indented. The
# "# A tibble" header repeats the summary line and the "print(n = ...)" hint
# does not apply to a message, so both are dropped.
preview_rows <- function(data, n = 5, width = cli::console_width() - 4) {
  if (ncol(data) == 0) return(character())
  lines <- format(tibble::as_tibble(data), n = n, width = width)
  lines <- lines[!grepl("^# A tibble|print\\(n = ", cli::ansi_strip(lines))]
  paste0("  ", sub("\\s+$", "", lines))
}
