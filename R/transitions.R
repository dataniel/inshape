#' Describe the transitions between statuses over time
#'
#' A status that follows a unit over time, such as education, labour market
#' attachment or civil status, can only change in some ways: a person who
#' has completed an education cannot later not have started it. The
#' transition table counts, for every pair of statuses, how many units go
#' from the one to the other between two observations. Impossible
#' transitions show as cells that should be empty, before any rule is
#' written; require one with [ensure_transitions()].
#'
#' Each row is compared with the unit's next observation in time, whatever
#' the distance: a person observed as completed in 2019 and as not started
#' in 2021 makes that transition even if 2020 is missing. Find the missing
#' years with [ensure_balanced()]. Rows with a missing time or status are
#' left out, as missing is a different problem than a wrong status.
#'
#' The unit is what the `id` columns say. A person may complete one
#' education and start another; then the unit is the person and the
#' education, `id = c(cpr, education)`, not the person, or the new start
#' looks like a step back.
#'
#' The same works for spells: give the start column as `time`, and each
#' spell is compared with the unit's next spell.
#'
#' @param data A data frame or tibble, or a database or Arrow table: see
#'   *Database and Arrow tables* in [checkpoints].
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr`.
#' @param time The period column, or the start of a spell (one column).
#' @param status The status column (one column).
#'
#' @return An object of class `inshape_transitions`, printed as a summary.
#'   It is a list with `ids`, `time`, `status`, the counts `n_rows`,
#'   `n_units` and `n_transitions` (pairs of consecutive observations), and
#'   `transitions`, a tibble with `from`, `to`, `units` (units making the
#'   transition at least once) and `n` (times it is made).
#'
#' @examples
#' education <- data.frame(
#'   cpr    = c("a", "a", "a", "b", "b", "c", "c"),
#'   year   = c(2019, 2020, 2021, 2019, 2020, 2019, 2021),
#'   status = c("not started", "enrolled", "completed",
#'              "enrolled", "completed", "completed", "not started")
#' )
#' # c goes from completed to not started
#' describe_transitions(education, cpr, year, status)
#'
#' @seealso [ensure_transitions()] to forbid transitions, [carry_status()]
#'   to let a status stand once reached.
#'
#' @export
describe_transitions <- function(data, id, time, status) {
  tbl  <- check_table(data)
  cols <- transition_columns(tbl, {{ id }}, {{ time }}, {{ status }})

  if (is_remote(tbl)) {
    pairs <- remote_transitions(tbl, cols$ids, cols$time, cols$status)
    n_tr  <- remote_nrow(pairs)
    counts <- pairs |>
      dplyr::count(.data$.inshape_from, .data[[cols$status]], name = "n") |>
      dplyr::collect()
    units <- pairs |>
      dplyr::distinct(!!!rlang::syms(c(cols$ids, ".inshape_from", cols$status))) |>
      dplyr::count(.data$.inshape_from, .data[[cols$status]], name = "units") |>
      dplyr::collect()
    tab <- dplyr::left_join(counts, units, by = c(".inshape_from", cols$status))
    tab <- tibble::tibble(from = tab$.inshape_from, to = tab[[cols$status]],
                          units = as.numeric(tab$units), n = as.numeric(tab$n))
    kept <- dplyr::filter(dplyr::ungroup(tbl), !is.na(.data[[cols$time]]), !is.na(.data[[cols$status]]))
    n_rows  <- remote_nrow(tbl)
    n_units <- n_distinct_rows(kept, cols$ids)
  } else {
    tr <- local_transitions(data, cols$ids, cols$time, cols$status)
    n_tr <- length(tr$from)
    pair <- group_ids(list2DF(list(f = tr$from, t = tr$to)), c("f", "t"))
    k <- attr(pair, "n")
    first <- first_row_by(pair, k)
    seen <- which(first > 0L)
    unit_pair <- group_ids(list2DF(list(u = tr$unit, p = pair)), c("u", "p"))
    one_per_unit <- !duplicated(unit_pair)
    tab <- tibble::tibble(
      from  = tr$from[first[seen]],
      to    = tr$to[first[seen]],
      units = tabulate(pair[one_per_unit], k)[seen],
      n     = tabulate(pair, k)[seen]
    )
    n_rows  <- nrow(data)
    n_units <- tr$n_units
  }
  tab <- tab[order(tab$from, tab$to, method = "radix"), ]

  structure(list(
    ids = cols$ids, time = cols$time, status = cols$status,
    n_rows = n_rows, n_units = n_units, n_transitions = n_tr,
    transitions = tab
  ), class = "inshape_transitions")
}

#' @export
print.inshape_transitions <- function(x, ...) {
  describe_header(
    paste0("Transitions: ", x$status, " by ", x$time, " per ", toString(x$ids)),
    paste0(count(x$n_rows, "row"), ", ", count(x$n_units, "unit"), ", ",
           count(x$n_transitions, "pair"), " of consecutive observations")
  )
  tab <- x$transitions
  change <- tab$from != tab$to
  note_line(paste0("Changing status: ", big(sum(tab$n[change])), " of ",
                   count(x$n_transitions, "pair"), share(sum(tab$n[change]), x$n_transitions)))
  states <- sort(unique(c(tab$from, tab$to)))
  if (length(states) == 0) return(invisible(x))
  if (length(states) <= 10) {
    # Units per transition as a table: from in rows, to in columns. Cells
    # that should be empty are where the impossible transitions show.
    m <- matrix(0, length(states), length(states))
    m[cbind(match(tab$from, states), match(tab$to, states))] <- tab$units
    labels <- fmt_values(states)
    cells <- rbind(c("from \\ to", labels),
                   cbind(labels, matrix(big(m), nrow = length(states))))
    width <- apply(nchar(cells), 2, max)
    cells[, 1] <- formatC(cells[, 1], width = -width[1])
    for (j in seq_len(ncol(cells))[-1]) cells[, j] <- formatC(cells[, j], width = width[j])
    cli::cat_line()
    cli::cat_line("Units per transition, from (rows) to (columns):")
    cli::cat_line(paste0("  ", apply(cells, 1, paste, collapse = "  ")))
  } else {
    shown <- tab[change, ]
    shown <- shown[order(-shown$units), ]
    table_block("Changes of status, most units first:", shown)
  }
  invisible(x)
}

#' Assert that a status only changes in allowed ways
#'
#' A checkpoint for a status that follows a unit over time: a person who
#' has completed an education must not later be not started on it. Name the
#' transitions that cannot happen, or a final status that nothing else may
#' follow, and the rows where they happen are reported, counted per
#' transition. Returns `data`, so it can sit in the middle of a pipeline.
#'
#' Each row is compared with the unit's next observation in time, whatever
#' the distance, as in [describe_transitions()], which shows every
#' transition there is before you write the rule. Rows with a missing time
#' or status are left out. The unit is what the `id` columns say: give
#' `id = c(cpr, education)` when a person may complete one education and
#' start another.
#'
#' The rule is given as forbidden pairs, `forbid = "completed -> enrolled"`,
#' since few statuses only go forward in a fixed order: an interrupted
#' education can be resumed, a completed one cannot. A final status,
#' `final = "completed"`, is the common case written short: every change
#' away from it is forbidden. Statuses are compared as text, so a numeric
#' status is written as its number, `"3 -> 1"`.
#'
#' On failure the reported rows are the rows the forbidden transition goes
#' to, with a `transition` column naming it and a `previous` column holding
#' the time of the observation it comes from.
#'
#' @inheritParams describe_transitions
#' @param forbid Forbidden transitions, as strings `"from -> to"`.
#' @param final Statuses that, once reached, must not change.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when a forbidden transition happens and no
#'   `abort_msg` is set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' education <- data.frame(
#'   cpr    = c("a", "a", "a", "b", "b", "c", "c"),
#'   year   = c(2019, 2020, 2021, 2019, 2020, 2019, 2021),
#'   status = c("not started", "enrolled", "completed",
#'              "enrolled", "completed", "completed", "not started")
#' )
#' ensure_transitions(education, cpr, year, status, final = "completed")
#'
#' ensure_transitions(education, cpr, year, status,
#'                    forbid = c("completed -> not started", "enrolled -> not started"))
#'
#' @seealso [describe_transitions()] to see every transition first,
#'   [carry_status()] to let a final status stand, [checkpoints].
#'
#' @export
ensure_transitions <- function(data, id, time, status, forbid = NULL, final = NULL,
                               success_msg = NULL,
                               warn_msg    = NULL,
                               abort_msg   = NULL) {
  tbl  <- check_table(data)
  cols <- transition_columns(tbl, {{ id }}, {{ time }}, {{ status }})
  pairs <- parse_transitions(forbid)
  if (!is.null(final) && (!is.atomic(final) || anyNA(final) || length(final) == 0)) {
    cli::cli_abort("{.arg final} must be a vector of statuses.")
  }
  if (is.null(pairs) && is.null(final)) {
    cli::cli_abort("Give the transitions to {.arg forbid}, a {.arg final} status, or both.")
  }
  final <- if (!is.null(final)) as.character(final)
  label_col <- diagnostic_name(tbl, "transition")
  prev_col  <- diagnostic_name(tbl, "previous")

  rows <- if (is_remote(tbl)) {
    remote_forbidden(tbl, cols, pairs, final, label_col, prev_col)
  } else {
    tr <- local_transitions(data, cols$ids, cols$time, cols$status)
    from <- as.character(tr$from)
    to   <- as.character(tr$to)
    label <- paste(from, "->", to)
    bad <- label %in% pairs | (from %in% final & to != from)
    hit <- which(bad)
    out <- tibble::as_tibble(data)[tr$row[hit], ]
    out <- tibble::add_column(out, !!label_col := label[hit],
                              !!prev_col := data[[cols$time]][tr$prev[hit]], .before = 1)
    o <- do.call(order, c(unname(as.list(out[c(cols$ids, cols$time)])),
                          list(method = "radix", na.last = FALSE)))
    out[o, ]
  }

  name <- data_label(rlang::caller_arg(data))
  what <- paste0(cols$status, " by ", cols$time, " per ", toString(cols$ids))
  report_check(
    rows,
    pass = paste0("No forbidden transitions: ", what),
    fail = paste0("Forbidden transitions: ", what),
    success_msg, warn_msg, abort_msg,
    key = c(cols$ids, prev_col, cols$time, cols$status),
    group = label_col,
    show = character(),
    summary = function(v, n) {
      list(
        lines = c(paste0("In ", count(n_distinct_rows(v, cols$ids), "unit")),
                  tally_line("By transition", top_values(v, label_col))),
        hints = if (!is.null(final)) paste0(
          "If the final status is right and the later ones wrong: carry_status(", name, ", ",
          code_cols(cols$ids), ", ", code_name(cols$time), ", ", code_name(cols$status),
          ", final = ", deparse1(final), ")")
      )
    }
  )
  invisible(data)
}

# The id, time and status columns of a transition function, checked
transition_columns <- function(tbl, id, time, status, call = rlang::caller_env()) {
  ids      <- select_names(tbl, {{ id }})
  time_col <- select_names(tbl, {{ time }})
  st_col   <- select_names(tbl, {{ status }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.", call = call)
  if (length(time_col) != 1) cli::cli_abort("{.arg time} must select exactly one column.", call = call)
  if (length(st_col) != 1) cli::cli_abort("{.arg status} must select exactly one column.", call = call)
  list(ids = ids, time = time_col, status = st_col)
}

# "from -> to" strings, checked and with the spaces around the arrow made
# the same as in the labels of the violations
parse_transitions <- function(forbid, call = rlang::caller_env()) {
  if (is.null(forbid)) return(NULL)
  if (!is.character(forbid) || anyNA(forbid)) {
    cli::cli_abort("{.arg forbid} must be strings such as {.str completed -> enrolled}.", call = call)
  }
  parts <- strsplit(forbid, "\\s*->\\s*")
  bad <- lengths(parts) != 2 | vapply(parts, function(p) any(!nzchar(trimws(p))), logical(1))
  if (any(bad)) {
    cli::cli_abort(c(
      "Each transition in {.arg forbid} must be written {.str from -> to}.",
      "x" = "Not understood: {.str {forbid[bad]}}."
    ), call = call)
  }
  vapply(parts, function(p) paste(trimws(p[1]), "->", trimws(p[2])), character(1))
}

# Consecutive observations of each unit in memory: the rows sorted by unit
# id and time, and each paired with the next row of the same unit. Returns
# the statuses `from` and `to`, the row numbers of the later (`row`) and
# earlier (`prev`) observation, the unit id per pair, and the number of
# units with an observation.
local_transitions <- function(data, ids, time_col, status_col) {
  time   <- data[[time_col]]
  status <- data[[status_col]]
  keep   <- which(!is.na(time) & !is.na(status))
  unit   <- group_ids(data, ids)
  o <- keep[order(unit[keep], time[keep], keep, method = "radix")]
  n <- length(o)
  n_units <- if (n) sum(tabulate(unit[o], attr(unit, "n")) > 0L) else 0
  if (n < 2) {
    return(list(from = status[0], to = status[0], row = integer(), prev = integer(),
                unit = integer(), n_units = n_units))
  }
  same <- unit[o[-1]] == unit[o[-n]]
  list(from = status[o[-n]][same], to = status[o[-1]][same],
       row = o[-1][same], prev = o[-n][same], unit = unit[o[-1]][same],
       n_units = n_units)
}

# The same pairs as a query: each row with the status and time of the
# unit's previous observation, rows without one left out
remote_transitions <- function(tbl, ids, time_col, status_col) {
  tbl |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(.data[[time_col]]), !is.na(.data[[status_col]])) |>
    dplyr::group_by(!!!rlang::syms(ids)) |>
    dbplyr::window_order(.data[[time_col]]) |>
    dplyr::mutate(.inshape_from = dplyr::lag(.data[[status_col]]),
                  .inshape_prev = dplyr::lag(.data[[time_col]])) |>
    dplyr::ungroup() |>
    dbplyr::window_order() |>
    dplyr::filter(!is.na(.data$.inshape_from))
}

remote_forbidden <- function(tbl, cols, pairs, final, label_col, prev_col) {
  # Compared in the type of the status column, and labelled as R writes
  # the values: a whole number cast to text in SQL may read "1.0"
  proto <- table_prototype(tbl)[[cols$status]]
  from_raw <- rlang::expr(.data$.inshape_from)
  to_raw   <- rlang::expr(.data[[!!cols$status]])
  as_text <- function(x) {
    if (is.double(proto)) rlang::expr(as.character(as.integer(!!x))) else rlang::expr(as.character(!!x))
  }
  tests <- list()
  if (length(pairs)) {
    split <- strsplit(pairs, " -> ", fixed = TRUE)
    from_v <- typed_values(vapply(split, `[`, character(1), 1), proto)
    to_v   <- typed_values(vapply(split, `[`, character(1), 2), proto)
    tests <- c(tests, lapply(seq_along(pairs), function(k) {
      rlang::expr(!!from_raw == !!from_v[k] & !!to_raw == !!to_v[k])
    }))
  }
  if (length(final)) {
    final_v <- typed_values(final, proto)
    tests <- c(tests, list(rlang::expr(!!from_raw %in% !!final_v & !!to_raw != !!from_raw)))
  }
  test <- Reduce(function(a, b) rlang::expr(!!a | !!b), tests)
  remote_transitions(tbl, cols$ids, cols$time, cols$status) |>
    dplyr::filter(!!test) |>
    dplyr::mutate(!!label_col := paste0(!!as_text(from_raw), " -> ", !!as_text(to_raw))) |>
    dplyr::rename(!!prev_col := ".inshape_prev") |>
    dplyr::select(!".inshape_from") |>
    dplyr::relocate(dplyr::all_of(c(label_col, prev_col))) |>
    sort_by(c(na_first(cols$ids), list(rlang::sym(cols$time))))
}
