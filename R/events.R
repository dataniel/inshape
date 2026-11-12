#' Describe events: how many per unit, per period and how far apart
#'
#' Event data has one row per thing that happened, with a date: moves,
#' exams, payments, contacts. Several rows per unit and period are the
#' point, so the panel checks do not apply. `describe_events()` counts the
#' events and the units, the events per unit (one unit with 4,000 contacts
#' is usually an error of its own), the events per period (a month without
#' events is usually a broken extract), and the time between a unit's
#' consecutive events (a time of 0 between two of the same is often a
#' duplicate). It judges nothing.
#'
#' Periods are years for a date column, and the values themselves for a
#' number such as a year or a month number.
#'
#' @inheritParams describe_transitions
#' @param time The date or period of each event (one column).
#' @param event The type of event (one column), or `NULL` (default).
#'
#' @return An object of class `inshape_events`, printed as a summary. It is
#'   a list with `ids`, `time`, `event`, the counts `n_events` and
#'   `n_units`, and the tibbles `per_unit` (`events`, `units`: how many
#'   units have that many events), `by_period` (`period`, `events`,
#'   `units`), `by_event` (`event`, `events`, `units`, or `NULL`) and
#'   `between` (`n`, `min`, `median`, `mean`, `max` of the time between a
#'   unit's consecutive events, in days for dates).
#'
#' @examples
#' moves <- data.frame(
#'   cpr  = c("a", "a", "a", "b", "c", "c"),
#'   date = as.Date(c("2020-03-01", "2021-06-15", "2021-06-15",
#'                    "2022-01-10", "2020-08-01", "2023-02-01")),
#'   type = c("in", "out", "out", "in", "in", "out")
#' )
#' describe_events(moves, cpr, date, type)
#'
#' @seealso [ensure_sequence()] for the order of events, [ensure_counts()]
#'   for at most one of a kind, [ensure_within()] for events outside a
#'   unit's lifetime.
#'
#' @export
describe_events <- function(data, id, time, event = NULL) {
  tbl <- dplyr::ungroup(check_table(data))
  ids      <- select_names(tbl, {{ id }})
  time_col <- select_names(tbl, {{ time }})
  ev_col   <- select_names(tbl, {{ event }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(time_col) != 1) cli::cli_abort("{.arg time} must select exactly one column.")
  if (length(ev_col) > 1) cli::cli_abort("{.arg event} must select at most one column.")
  remote <- is_remote(tbl)
  fetch <- function(q) tibble::as_tibble(if (remote) dplyr::collect(q) else q)
  is_date <- inherits(table_prototype(tbl)[[time_col]], c("Date", "POSIXt"))

  n_events <- if (remote) remote_nrow(tbl) else nrow(tbl)
  n_units  <- n_distinct_rows(tbl, ids)

  per_unit <- tbl |>
    dplyr::count(!!!rlang::syms(ids), name = "events") |>
    dplyr::count(.data$events, name = "units") |>
    fetch()
  per_unit <- per_unit[order(per_unit$events), ]
  per_unit[] <- lapply(per_unit, as.numeric)

  period <- if (!is_date) {
    rlang::sym(time_col)
  } else if (remote) {
    con <- dbplyr::remote_con(tbl)
    dbplyr::sql(paste0("EXTRACT(YEAR FROM ", DBI::dbQuoteIdentifier(con, time_col), ")"))
  } else {
    rlang::expr(as.integer(format(.data[[!!time_col]], "%Y")))
  }
  with_period <- dplyr::mutate(tbl, .inshape_period = !!period)
  by_period <- dplyr::left_join(
    fetch(dplyr::count(with_period, .data$.inshape_period, name = "events")),
    fetch(dplyr::count(dplyr::distinct(with_period, !!!rlang::syms(c(ids, ".inshape_period"))),
                       .data$.inshape_period, name = "units")),
    by = ".inshape_period")
  names(by_period)[1] <- "period"
  by_period <- by_period[order(by_period$period), ]
  by_period[c("events", "units")] <- lapply(by_period[c("events", "units")], as.numeric)

  by_event <- if (length(ev_col)) {
    out <- dplyr::left_join(
      fetch(dplyr::count(tbl, .data[[ev_col]], name = "events")),
      fetch(dplyr::count(dplyr::distinct(tbl, !!!rlang::syms(c(ids, ev_col))), .data[[ev_col]],
                         name = "units")),
      by = ev_col)
    names(out)[1] <- "event"
    out[c("events", "units")] <- lapply(out[c("events", "units")], as.numeric)
    out[order(-out$events), ]
  }

  gaps <- tbl |>
    dplyr::filter(!is.na(.data[[time_col]])) |>
    dplyr::group_by(!!!rlang::syms(ids))
  gaps <- if (remote) dbplyr::window_order(gaps, .data[[time_col]]) else dplyr::arrange(gaps, .data[[time_col]], .by_group = TRUE)
  gaps <- gaps |>
    dplyr::mutate(.inshape_gap = .data[[time_col]] - dplyr::lag(.data[[time_col]])) |>
    dplyr::ungroup()
  if (remote) gaps <- dbplyr::window_order(gaps)
  gaps <- dplyr::filter(gaps, !is.na(.data$.inshape_gap))
  between <- if (remote) {
    out <- gaps |>
      dplyr::summarise(n = dplyr::n(), min = min(.data$.inshape_gap, na.rm = TRUE),
                       median = stats::median(.data$.inshape_gap, na.rm = TRUE),
                       mean = mean(.data$.inshape_gap, na.rm = TRUE),
                       max = max(.data$.inshape_gap, na.rm = TRUE)) |>
      dplyr::collect()
    tibble::as_tibble(lapply(out, as.numeric))
  } else {
    g <- as.numeric(gaps$.inshape_gap)
    tibble::tibble(n = length(g), min = if (length(g)) min(g) else NA_real_,
                   median = stats::median(g), mean = if (length(g)) mean(g) else NA_real_,
                   max = if (length(g)) max(g) else NA_real_)
  }

  structure(list(ids = ids, time = time_col, event = if (length(ev_col)) ev_col,
                 n_events = n_events, n_units = n_units, per_unit = per_unit,
                 by_period = by_period, by_event = by_event, between = between,
                 unit_word = if (is_date) "day" else "period"),
            class = "inshape_events")
}

#' @export
print.inshape_events <- function(x, ...) {
  describe_header(
    paste0("Events: ", if (!is.null(x$event)) paste0(x$event, " ") else "", "by ", x$time,
           " per ", toString(x$ids)),
    paste0(count(x$n_events, "event"), ", ", count(x$n_units, "unit"))
  )
  pu <- x$per_unit
  if (nrow(pu)) {
    note_line(paste0("Events per unit: most ", big(max(pu$events)), ", ",
                     count(sum(pu$units[pu$events == 1]), "unit"), " with one"))
  }
  if (!is.null(x$by_event)) table_block("By event:", x$by_event)
  table_block("Units by number of events:", utils::tail(pu, 10), n = 10)
  table_block("By period:", x$by_period)
  if (isTRUE(x$between$n > 0)) {
    table_block(paste0("Time between a unit's consecutive events, in ", x$unit_word, "s:"), x$between)
  }
  invisible(x)
}

#' Assert that events come in order
#'
#' A checkpoint for events that need another before them: an exam needs an
#' enrolment, a move out a move in, a divorce a marriage. Every `then`
#' event of a unit must come on or after the unit's first `first` event.
#' The `then` events that come before it, or in a unit with no `first`
#' event at all, are reported, with a `reason` column saying which.
#' Returns `data`, so it can sit in the middle of a pipeline.
#'
#' Events on the same day are in order. Rows with a missing time are only
#' reported when the unit has no `first` event. The unit is what the `id`
#' columns say: give `id = c(cpr, education)` when an exam needs an
#' enrolment in the same education.
#'
#' Too many events of one kind, such as two deaths, is
#' [ensure_counts()] with the event as the role.
#'
#' @inheritParams describe_events
#' @param event The type of event (one column).
#' @param first The event that must come first, e.g. `"enrolled"`.
#' @param then The event that must not come before it, e.g. `"exam"`.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when events come out of order and no
#'   `abort_msg` is set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' events <- data.frame(
#'   cpr   = c("a", "a", "b", "b", "c"),
#'   date  = as.Date(c("2020-08-15", "2021-06-01", "2021-06-01", "2021-08-15",
#'                     "2021-06-01")),
#'   event = c("enrolled", "exam", "exam", "enrolled", "exam")
#' )
#' # b takes an exam before enrolling, c without enrolling
#' ensure_sequence(events, cpr, date, event, first = "enrolled", then = "exam")
#'
#' @seealso [describe_events()], [ensure_transitions()] for a status that
#'   changes over time, [checkpoints].
#'
#' @export
ensure_sequence <- function(data, id, time, event, first, then,
                            success_msg = NULL,
                            warn_msg    = NULL,
                            abort_msg   = NULL) {
  tbl <- dplyr::ungroup(check_table(data))
  ids      <- select_names(tbl, {{ id }})
  time_col <- select_names(tbl, {{ time }})
  ev_col   <- select_names(tbl, {{ event }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(time_col) != 1 || length(ev_col) != 1) {
    cli::cli_abort("{.arg time} and {.arg event} must each select exactly one column.")
  }
  if (!rlang::is_scalar_atomic(first) || !rlang::is_scalar_atomic(then) || is.na(first) || is.na(then)) {
    cli::cli_abort("{.arg first} and {.arg then} must each be one event.")
  }
  proto <- table_prototype(tbl)[[ev_col]]
  first_v <- typed_values(as.character(first), if (is.factor(proto)) character() else proto)
  then_v  <- typed_values(as.character(then), if (is.factor(proto)) character() else proto)
  reason_col <- diagnostic_name(tbl, "reason")

  firsts <- tbl |>
    dplyr::filter(.data[[ev_col]] == !!first_v, !is.na(.data[[time_col]])) |>
    dplyr::group_by(!!!rlang::syms(ids)) |>
    dplyr::summarise(.inshape_first = min(.data[[time_col]], na.rm = TRUE), .groups = "drop")
  rows <- tbl |>
    dplyr::filter(.data[[ev_col]] == !!then_v) |>
    dplyr::left_join(firsts, by = ids, na_matches = "na") |>
    dplyr::filter(is.na(.data$.inshape_first) | .data[[time_col]] < .data$.inshape_first) |>
    dplyr::mutate(!!reason_col := dplyr::if_else(is.na(.data$.inshape_first),
                                                  !!paste("no", first), !!paste("before", first))) |>
    dplyr::select(!".inshape_first") |>
    dplyr::relocate(dplyr::all_of(reason_col))
  rows <- if (is_remote(rows)) {
    sort_by(rows, c(na_first(ids), list(rlang::sym(time_col))))
  } else {
    o <- do.call(order, c(unname(as.list(rows[c(ids, time_col)])), list(method = "radix", na.last = FALSE)))
    rows[o, ]
  }

  report_check(
    rows,
    pass = paste0("Every ", then, " on or after ", first, " per ", toString(ids)),
    fail = paste0(then, " before ", first, " per ", toString(ids)),
    success_msg, warn_msg, abort_msg,
    key = c(ids, time_col, ev_col),
    group = reason_col,
    show = character(),
    summary = function(v, n) {
      c(paste0("In ", count(n_distinct_rows(v, ids), "unit")),
        tally_line("Reasons", top_values(v, reason_col)))
    }
  )
  invisible(data)
}
