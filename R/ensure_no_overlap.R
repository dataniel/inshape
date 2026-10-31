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
#' `start` are ignored; find them with `dplyr::filter(data, is.na(start))`,
#' and spells that end before they start with
#' `dplyr::filter(data, end < start)`.
#'
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr`.
#' @param start,end Columns with the first and last period of each spell
#'   (dates, or integers such as years).
#' @inheritParams checkpoints
#' @param warn_msg Message shown (and logged) when spells overlap and no
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
#' @seealso [ensure_balanced()] for yearly panels, [checkpoints].
#'
#' @export
ensure_no_overlap <- function(data, id, start, end,
                              success_msg = NULL,
                              warn_msg    = NULL,
                              abort_msg   = NULL,
                              log         = getOption("lustrum.log"),
                              dump        = getOption("lustrum.dump")) {

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
    log         = log,
    dump        = dump,
    key         = c(ids, start_col, end_col),
    group       = "overlap_id"
  )
  invisible(data)
}

# Overlapping spells with an `overlap_id` per connected group of spells.
# Spells are sorted by integer unit id and start (see group_ids()), not by
# the id columns themselves; only the overlapping spells, usually few, are
# sorted by those for the report.
find_overlaps <- function(data, ids, start_col, end_col) {
  start <- as.numeric(data[[start_col]])
  rows  <- which(!is.na(start))
  spells <- data.table::data.table(
    unit = group_ids(data, ids)[rows], start = start[rows], row = rows
  )
  data.table::setorderv(spells, c("unit", "start"))
  rows  <- spells$row
  unit  <- spells$unit
  start <- spells$start
  ends  <- as.numeric(data[[end_col]])[rows]
  ends[is.na(ends)] <- Inf
  n     <- length(rows)

  # A spell opens a new group unless it starts on or before the latest end
  # among the unit's earlier spells
  new_unit   <- c(TRUE, unit[-1] != unit[-n])[seq_len(n)]
  latest_end <- cummax_by(ends, cumsum(new_unit))
  new_group  <- new_unit | start > c(-Inf, latest_end[-n])[seq_len(n)]
  group      <- cumsum(new_group)
  hit        <- tabulate(group)[group] > 1

  # Report in the order of the id columns and start, as setorderv() sorts
  hits <- data.table::setDT(c(
    stats::setNames(lapply(unclass(data)[ids], `[`, rows[hit]),
                    paste0(".id", seq_along(ids))),
    list(.start = start[hit], .row = rows[hit], .group = group[hit])
  ))
  data.table::setorderv(hits, c(paste0(".id", seq_along(ids)), ".start", ".row"))

  out <- tibble::as_tibble(data)[hits$.row, ]
  tibble::add_column(out, overlap_id = match(hits$.group, unique(hits$.group)),
                     .before = 1)
}

# cummax() within runs of `unit` (consecutive 1, 2, ...), in one vectorised
# pass. A grouped cummax() calls R once per unit, which is slow for a
# population of persons. Ranks keep the values small (Inf included), and an
# offset per unit lifts each unit above the previous one, so a single global
# cummax() cannot carry over between units. Beyond the exact range of a
# double, it falls back to the grouped cummax().
cummax_by <- function(x, unit) {
  if (length(x) == 0) return(x)
  values <- sort(unique(x))
  if (max(unit) * (length(values) + 1) > 2^52) {
    return(stats::ave(x, unit, FUN = cummax))
  }
  rank   <- match(x, values)
  offset <- (unit - 1) * (length(values) + 1)
  values[cummax(rank + offset) - offset]
}
