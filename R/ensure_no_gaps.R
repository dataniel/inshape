#' Assert that a unit's spells leave no gaps
#'
#' A checkpoint for spell data that should cover a unit without a break:
#' everyone resident has an address every day, an insured person a policy,
#' a dwelling an owner. A spell that starts later than the day after the
#' unit's earlier spells have ended leaves days that no spell covers.
#' Returns `data`, so it can sit in the middle of a pipeline.
#'
#' It is the counterpart of [ensure_no_overlap()]: that a unit is in at
#' most one spell at a time, and here in at least one, between its first
#' start and its last end. Together they say exactly one. The time before a
#' unit's first spell and after its last is not a gap; compare those with
#' birth, death or migration dates with [ensure_within()].
#'
#' On failure the spell that starts after each gap is reported, with a
#' `gap` column prepended holding the number of days (or periods) that no
#' spell covers before it. The spell that ended last before the gap is the
#' one with the latest end among the unit's earlier spells, not always the
#' row above.
#'
#' Spells are closed intervals, as in [ensure_no_overlap()]: a spell ending
#' 31 January and one starting 1 February leave no gap, one starting
#' 2 February leaves a gap of one day. A missing `end` means an ongoing
#' spell, and nothing after its start is a gap. Rows with a missing
#' `start`, or an `end` before the `start`, are ignored, as in
#' [describe_spells()]; find them with [ensure_valid_spells()].
#'
#' @inheritParams ensure_no_overlap
#' @param max_gap The longest gap that is accepted, in days (or periods).
#'   The default 0 accepts none. As in [merge_spells()], `max_gap = 1`
#'   lets a spell start two days after the previous one ended.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when there are gaps and no `abort_msg` is
#'   set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' addresses <- data.frame(
#'   cpr   = c("a", "a", "b", "b"),
#'   start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-07-04")),
#'   end   = as.Date(c("2020-12-31", NA,           "2020-06-30", "2021-12-31"))
#' )
#'
#' # b has no address on 1, 2 and 3 July 2020
#' ensure_no_gaps(addresses, cpr, start, end)
#'
#' # Accept up to a week without an address
#' ensure_no_gaps(addresses, cpr, start, end, max_gap = 7)
#'
#' @seealso [describe_spells()] to count the gaps and their lengths first,
#'   [ensure_no_overlap()] for the opposite rule, [merge_spells()] to join
#'   spells across short gaps, [checkpoints].
#'
#' @export
ensure_no_gaps <- function(data, id, start, end, max_gap = 0,
                           success_msg = NULL,
                           warn_msg    = NULL,
                           abort_msg   = NULL) {

  tbl       <- check_table(data)
  ids       <- select_names(tbl, {{ id }})
  start_col <- select_names(tbl, {{ start }})
  end_col   <- select_names(tbl, {{ end }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(start_col) != 1 || length(end_col) != 1) {
    cli::cli_abort("{.arg start} and {.arg end} must each select exactly one column.")
  }
  if (!is.numeric(max_gap) || length(max_gap) != 1 || is.na(max_gap) ||
      max_gap < 0 || max_gap != round(max_gap)) {
    cli::cli_abort("{.arg max_gap} must be a single whole number, 0 or more.")
  }
  max_gap <- as.integer(max_gap)

  gaps <- if (is_remote(tbl)) {
    remote_spell_gaps(tbl, ids, start_col, end_col, max_gap)
  } else {
    find_spell_gaps(data, ids, start_col, end_col, max_gap)
  }

  what <- paste0(if (max_gap > 0) paste0(" longer than ", max_gap), " per ", toString(ids))
  report_check(
    gaps,
    pass = paste0("No gaps between spells", what),
    fail = paste0("Gaps between spells", what),
    success_msg, warn_msg, abort_msg,
    key = c(diagnostic_name(tbl, "gap"), ids, start_col, end_col)
  )
  invisible(data)
}

# The spells that start after a gap longer than `max_gap`, with the length
# of the gap in `gap`. The sorted pass of describe_spells() gives each
# spell's relation to the latest end among the unit's earlier spells (see
# spell_scan()); a gap is one of those relations, with its length. Only
# the spells after a gap, usually few, are sorted by the id columns.
find_spell_gaps <- function(data, ids, start_col, end_col, max_gap) {
  start  <- spell_numbers(data[[start_col]], start_col)
  end    <- spell_numbers(data[[end_col]], end_col)
  usable <- !is.na(start) & (is.na(end) | end >= start)
  spells <- spell_scan(group_ids(data, ids), start, end, usable)
  hit    <- which(spells$rel == 1L & spells$gap > max_gap)

  # Report in the order of the id columns and start, as setorderv() sorts
  hits <- data.table::setDT(c(
    stats::setNames(lapply(unclass(data)[ids], `[`, spells$row[hit]),
                    paste0(".id", seq_along(ids))),
    list(.start = spells$s[hit], .row = spells$row[hit], .gap = spells$gap[hit])
  ))
  data.table::setorderv(hits, c(paste0(".id", seq_along(ids)), ".start", ".row"))

  out <- tibble::as_tibble(data)[hits$.row, ]
  tibble::add_column(out, !!diagnostic_name(data, "gap") := hits$.gap, .before = 1)
}
