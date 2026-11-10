#' Assert that spells do not overlap within a unit
#'
#' A checkpoint for spell data, the other common shape of register data:
#' address periods, employment spells, benefit periods. Each unit can only be
#' in one spell at a time, so two spells for the same person that share a
#' day are an error. Returns `data`, so it can sit in the middle of a
#' pipeline.
#'
#' On failure the overlapping spells are reported with an `overlap_id`
#' column prepended, in the spirit of `dupid` in [ensure_unique()]: spells
#' that overlap each other (directly or through a chain) share an id, so
#' each conflict can be inspected as a group.
#'
#' Spells are treated as closed intervals, as register dates usually are: a
#' spell ending 31 January and one starting 1 February do not overlap, while
#' one ending and one starting on 1 February do. A missing `end` means an
#' ongoing spell and overlaps everything after its start. Rows with a missing
#' `start` are ignored. Check missing starts and ends before starts with
#' [ensure_valid_spells()] before checking overlaps.
#'
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr`.
#' @param start,end Columns with the first and last period of each spell
#'   (dates, or integers such as years).
#' @inheritParams checkpoints
#' @param warn_msg Message shown when spells overlap and no
#'   `abort_msg` is set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' addresses <- data.frame(
#'   cpr   = c("a", "a", "b", "b"),
#'   start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-06-01")),
#'   end   = as.Date(c("2020-12-31", NA,           "2020-06-30", "2021-12-31"))
#' )
#'
#' # b has two addresses in June 2020
#' ensure_no_overlap(addresses, cpr, start, end)
#'
#' @seealso [describe_spells()] to see how spells relate first,
#'   [merge_spells()] when overlapping spells are one spell recorded
#'   twice, [ensure_balanced()] for yearly panels, [checkpoints].
#'
#' @export
ensure_no_overlap <- function(data, id, start, end,
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

  overlaps <- if (is_remote(tbl)) {
    remote_overlaps(tbl, ids, start_col, end_col)
  } else {
    find_overlaps(data, ids, start_col, end_col)
  }

  label <- abort_msg %||% warn_msg
  report_check(
    violations  = overlaps,
    success_msg = success_msg %||%
      if (is.null(label)) paste0("No overlapping spells per ", toString(ids))
      else paste0("Check passed: ", label),
    fail_msg    = label %||% paste0("Overlapping spells per ", toString(ids)),
    abort       = !is.null(abort_msg),
    key         = c(ids, start_col, end_col),
    group       = diagnostic_name(tbl, "overlap_id")
  )
  invisible(data)
}

# Overlapping spells with an `overlap_id` per connected group of spells.
# Spells are sorted by integer unit id and start (see group_ids()), not by
# the id columns themselves, and the compiled pass of describe_spells()
# relates each to the unit's earlier spells: a spell opens a new group
# unless it starts on or before the latest end among them, i.e. unless it
# is touching, overlapping, nested or a duplicate. Only the overlapping
# spells, usually few, are sorted by the id columns for the report.
find_overlaps <- function(data, ids, start_col, end_col) {
  start <- spell_numbers(data[[start_col]], start_col)
  end   <- spell_numbers(data[[end_col]], end_col)
  spells <- spell_scan(group_ids(data, ids), start, end, !is.na(start))
  rows  <- spells$row
  start <- spells$s
  group <- cumsum(spells$rel <= 2L)
  hit   <- tabulate(group)[group] > 1

  # Report in the order of the id columns and start, as setorderv() sorts
  hits <- data.table::setDT(c(
    stats::setNames(lapply(unclass(data)[ids], `[`, rows[hit]),
                    paste0(".id", seq_along(ids))),
    list(.start = start[hit], .row = rows[hit], .group = group[hit])
  ))
  data.table::setorderv(hits, c(paste0(".id", seq_along(ids)), ".start", ".row"))

  out <- tibble::as_tibble(data)[hits$.row, ]
  tibble::add_column(out, !!diagnostic_name(data, "overlap_id") := match(hits$.group, unique(hits$.group)),
                     .before = 1)
}
