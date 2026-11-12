#' Let a status stand once it is reached
#'
#' The fix for the transitions [ensure_transitions()] forbids, when you know
#' which status holds: a completed education stays completed, the highest
#' education completed never falls. The status is carried forward over the
#' unit's later observations, and the earlier, wrong ones after it are
#' overwritten in a new column. Once the rule is given there is one right
#' result, so the function does not guess, as [merge_spells()] does not.
#'
#' Two ways to give the rule, one operation:
#'
#' * `final`: once a unit reaches one of these statuses, it holds in every
#'   later observation. With several, the first one reached holds.
#' * `order`: the statuses from lowest to highest; a unit's status is the
#'   highest it has had so far, so it never goes back in the order. Every
#'   status in the data must be in `order`.
#'
#' Later observations are taken in time order, whatever the distance, as in
#' [describe_transitions()]. A missing status after the status is reached
#' gets it too; one before keeps its missing value. Rows with a missing time
#' are left as they are.
#'
#' The fix is never silent: it says how many rows and units it changed,
#' counted per change, such as `not started -> completed: 37 rows in 31
#' units`. The result goes to a new column by default, so the original
#' status stands beside it and the changed rows can be found by comparing
#' the two; numbers behind a published table should not change without a
#' trace of where. Give `name = <the status column>` to overwrite it.
#'
#' The unit is what the `id` columns say. Carried per person, a completed
#' education overwrites the start of the next one; carry per person and
#' education, `id = c(cpr, education)`.
#'
#' @inheritParams describe_transitions
#' @param final Statuses that hold once reached.
#' @param order All statuses, from lowest to highest.
#' @param name Name of the column for the result. Defaults to the status
#'   column's name followed by `_carried`.
#'
#' @return `data` with the carried status in the column `name`: a tibble
#'   for a data frame, in the original row order, or a query for a database
#'   or Arrow table.
#'
#' @examples
#' education <- data.frame(
#'   cpr    = c("a", "a", "a", "b", "b", "b"),
#'   year   = c(2019, 2020, 2021, 2019, 2020, 2021),
#'   status = c("enrolled", "completed", "enrolled",
#'              "not started", "enrolled", "completed")
#' )
#' carry_status(education, cpr, year, status, final = "completed")
#'
#' # The highest level so far
#' levels <- data.frame(cpr = "a", year = 2019:2022, level = c(1, 3, 2, 4))
#' carry_status(levels, cpr, year, level, order = 1:4)
#'
#' @seealso [ensure_transitions()] and [describe_transitions()] to find the
#'   transitions first.
#'
#' @export
carry_status <- function(data, id, time, status, final = NULL, order = NULL, name = NULL) {
  tbl  <- check_table(data)
  cols <- transition_columns(tbl, {{ id }}, {{ time }}, {{ status }})
  if (is.null(final) == is.null(order)) {
    cli::cli_abort("Give either {.arg final} or {.arg order}.")
  }
  rule <- final %||% order
  if (!is.atomic(rule) || anyNA(rule) || length(rule) == 0 || anyDuplicated(rule)) {
    cli::cli_abort("{.arg {if (is.null(final)) 'order' else 'final'}} must be a vector of distinct statuses.")
  }
  rule <- as.character(rule)
  name <- name %||% paste0(cols$status, "_carried")
  if (!rlang::is_string(name) || (name %in% colnames(tbl) && name != cols$status)) {
    cli::cli_abort("{.arg name} must be a new column, or the status column to overwrite it.")
  }

  if (is_remote(tbl)) {
    out <- remote_carry(tbl, cols, final, rule, name)
    old <- if (name == cols$status) ".inshape_old" else cols$status
    report_carry(out, cols$ids, old, name, remote = TRUE)
    if (name == cols$status) out <- dplyr::select(out, !".inshape_old")
    return(out)
  }

  st   <- data[[cols$status]]
  time <- data[[cols$time]]
  unit <- group_ids(data, cols$ids)
  n_units <- attr(unit, "n")
  usable <- which(!is.na(time))
  new <- st
  if (!is.null(final)) {
    # The first row per unit with a final status, by time
    hits <- usable[as.character(st[usable]) %in% rule]
    hits <- hits[order(unit[hits], time[hits], hits, method = "radix")]
    first <- hits[!duplicated(unit[hits])]
    reached <- integer(n_units)
    reached[unit[first]] <- first
    r <- reached[unit[usable]]
    on <- r > 0L
    on[on] <- time[usable[on]] >= time[r[on]]
    new[usable[on]] <- st[r[on]]
  } else {
    rank <- match(as.character(st), rule)
    unknown <- unique(st[!is.na(st) & is.na(rank)])
    if (length(unknown)) {
      cli::cli_abort(c("Every status must be in {.arg order}.",
                       "x" = "Not in it: {.val {fmt_values(utils::head(unknown, 5))}}."))
    }
    rank[is.na(rank)] <- 0L
    o <- usable[order(unit[usable], time[usable], usable, method = "radix")]
    run <- data.table::data.table(u = unit[o], r = rank[o])[, list(m = cummax(r)), by = "u"]$m
    values <- st[match(rule, as.character(st))]
    on <- run > 0L
    new[o[on]] <- values[run[on]]
  }

  out <- tibble::as_tibble(data)
  out[[name]] <- new
  shown <- out
  if (name == cols$status) shown[[".inshape_old"]] <- st
  report_carry(shown, cols$ids, if (name == cols$status) ".inshape_old" else cols$status, name)
  out
}

# The carry as a query: for `final` the first final status of each unit
# joined on, for `order` the running maximum of the status's rank
remote_carry <- function(tbl, cols, final, rule, name) {
  tbl <- dplyr::ungroup(tbl)
  st   <- rlang::sym(cols$status)
  time <- rlang::sym(cols$time)
  typed <- typed_values(rule, table_prototype(tbl)[[cols$status]])
  if (name == cols$status) tbl <- dplyr::mutate(tbl, .inshape_old = !!st)
  if (!is.null(final)) {
    first <- tbl |>
      dplyr::filter(!!st %in% !!typed, !is.na(!!time)) |>
      dplyr::group_by(!!!rlang::syms(cols$ids)) |>
      dplyr::filter(!!time == min(!!time, na.rm = TRUE)) |>
      dplyr::summarise(.inshape_ft = min(!!time, na.rm = TRUE),
                       .inshape_fs = min(!!st, na.rm = TRUE), .groups = "drop")
    tbl |>
      dplyr::left_join(first, by = cols$ids, na_matches = "na") |>
      dplyr::mutate(!!name := dplyr::if_else(
        !is.na(.data$.inshape_ft) & !is.na(!!time) & !!time >= .data$.inshape_ft,
        .data$.inshape_fs, !!st)) |>
      dplyr::select(!dplyr::all_of(c(".inshape_ft", ".inshape_fs")))
  } else {
    seen <- dplyr::pull(dplyr::distinct(dplyr::filter(tbl, !is.na(!!st)), !!st))
    unknown <- seen[!seen %in% typed]
    if (length(unknown)) {
      cli::cli_abort(c("Every status must be in {.arg order}.",
                       "x" = "Not in it: {.val {fmt_values(utils::head(unknown, 5))}}."))
    }
    values <- seen[match(typed, seen)]
    rank <- rlang::expr(dplyr::case_when(!!!lapply(seq_along(typed), function(k) {
      rlang::expr(!!st == !!typed[k] ~ !!k)
    }), .default = 0L))
    present <- which(!is.na(values))
    back <- rlang::expr(dplyr::case_when(!!!lapply(present, function(k) {
      rlang::expr(.data$.inshape_m == !!k ~ !!values[k])
    }), .default = !!st))
    tbl |>
      dplyr::mutate(.inshape_r = !!rank) |>
      dplyr::group_by(!!!rlang::syms(cols$ids)) |>
      dbplyr::window_order(!!time) |>
      dplyr::mutate(.inshape_m = cummax(.data$.inshape_r)) |>
      dplyr::ungroup() |>
      dbplyr::window_order() |>
      dplyr::mutate(!!name := dplyr::if_else(is.na(!!time), !!st, !!back)) |>
      dplyr::select(!dplyr::all_of(c(".inshape_r", ".inshape_m")))
  }
}

# Statuses given as text, in the type of the status column, so a database
# compares them as it stores them: a number cast to text in SQL can read
# "1.0" where R reads "1"
typed_values <- function(values, proto, call = rlang::caller_env()) {
  out <- if (is.logical(proto)) as.logical(values)
         else if (is.integer(proto)) suppressWarnings(as.integer(values))
         else if (is.numeric(proto)) suppressWarnings(as.numeric(values))
         else as.character(values)
  if (anyNA(out)) {
    cli::cli_abort("The statuses {.val {values[is.na(out)]}} are not values of the status column.",
                   call = call)
  }
  out
}

# The message of a carry: rows and units changed, per change
report_carry <- function(out, ids, old, new, remote = FALSE) {
  changed <- if (remote) {
    dplyr::filter(out, !is.na(.data[[new]]),
                  is.na(.data[[old]]) | .data[[old]] != .data[[new]])
  } else {
    o <- out[[old]]
    v <- out[[new]]
    out[which(!is.na(v) & (is.na(o) | as.character(o) != as.character(v))), ]
  }
  n <- if (remote) remote_nrow(changed) else nrow(changed)
  if (n == 0) {
    cli::cli_alert_info("Nothing to change: no status goes back after it is reached.")
    return(invisible())
  }
  units <- n_distinct_rows(changed, ids)
  per <- if (remote) {
    rows <- dplyr::collect(dplyr::count(changed, .data[[old]], .data[[new]], name = "rows"))
    u <- dplyr::collect(dplyr::count(dplyr::distinct(changed, !!!rlang::syms(c(ids, old, new))),
                                     .data[[old]], .data[[new]], name = "units"))
    dplyr::left_join(rows, u, by = c(old, new))
  } else {
    rows <- dplyr::count(changed, .data[[old]], .data[[new]], name = "rows")
    u <- dplyr::count(dplyr::distinct(changed, !!!rlang::syms(c(ids, old, new))),
                      .data[[old]], .data[[new]], name = "units")
    dplyr::left_join(rows, u, by = c(old, new))
  }
  # Ties by value: a database returns its groups in no fixed order
  per <- per[order(-per$rows, per[[old]], per[[new]]), ]
  lines <- paste0(fmt_values(per[[old]]), " -> ", fmt_values(per[[new]]), ": ",
                  count(per$rows, "row"), " in ", count(per$units, "unit"))
  head <- paste0("Changed ", count(n, "row"), " in ", count(units, "unit"), ":")
  shown <- utils::head(lines, 10)
  if (length(lines) > 10) shown <- c(shown, paste0("... and ", count(length(lines) - 10, "more change")))
  esc <- function(x) gsub("([{}])", "\\1\\1", x)
  cli::cli_inform(c("i" = esc(head), stats::setNames(esc(shown), rep(" ", length(shown)))))
}
