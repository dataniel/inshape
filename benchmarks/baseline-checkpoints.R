# Frozen snapshot of the key-based checkpoints before the speed-up
# (commit b9e3fa4), for benchmarks/benchmark-checkpoints.R. Not package code.

# ---- R/flag_duplicates.R ---------------------------------------------
#' Flag duplicate rows
#'
#' Prepends two columns to a data frame: `isdup` (logical, `TRUE` when the row
#' appears more than once) and `dupid` (integer group identifier, `0` for
#' unique rows). Uses `data.table` internally for speed.
#'
#' @param data A data frame or tibble.
#' @param ... Columns used to identify duplicates (tidy-select). If omitted,
#'   all columns are used.
#'
#' @return A tibble with `isdup` and `dupid` prepended.
#'
#' @examples
#' # All columns
#' flag_duplicates(ggplot2::mpg)
#'
#' # Specific columns
#' flag_duplicates(ggplot2::mpg, manufacturer, model, year)
#'
#' # Combined with expect_empty() for a validation pipeline:
#' \dontrun{
#' ggplot2::mpg |>
#'   flag_duplicates() |>
#'   dplyr::filter(isdup) |>
#'   expect_empty(warn_msg = "Duplicate rows found")
#' }
#'
#' @seealso [daos::expect_empty()]
#'
#' @importFrom cli cli_abort
#' @importFrom dplyr select
#' @importFrom data.table as.data.table setcolorder
#' @importFrom tibble as_tibble
#' @export
flag_duplicates <- function(data, ...) {

  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame or tibble, not {.cls {class(data)}}.")
  }

  cols <- if (...length() == 0) names(data) else names(dplyr::select(data, ...))

  non_atomic <- cols[!vapply(data[cols], is.atomic, logical(1))]
  if (length(non_atomic) > 0) {
    cli::cli_abort(c(
      "All grouping columns must be atomic.",
      "x" = "These columns are not atomic: {.var {non_atomic}}."
    ))
  }

  dt <- data.table::as.data.table(data)
  # Both columns in a single grouping pass; a per-group ifelse() is slow.
  dt[, c("isdup", "dupid") := list(.N > 1L, .GRP), by = cols]
  dt[!(isdup), dupid := 0L]

  data.table::setcolorder(dt, c("isdup", "dupid"))

  tibble::as_tibble(dt)
}

# ---- R/expect_unique.R -----------------------------------------------
#' Assert that key columns identify each row uniquely
#'
#' A checkpoint for keys: every combination of the selected columns must
#' occur at most once. On failure the duplicated rows are reported (and
#' dumped, see [expect_empty()]) grouped by a `dupid` column, so each group
#' of copies can be inspected together. Returns `data`, so it can sit in the
#' middle of a pipeline.
#'
#' The most valuable place for it is just before a join. A lookup table with
#' a duplicated key makes `left_join()` silently multiply rows; checking the
#' key first turns that into an explicit message:
#'
#' ```r
#' codes |>
#'   expect_unique(branche, abort_msg = "Codebook has duplicate codes") |>
#'   left_join(x = df, by = "branche")
#' ```
#'
#' This is [flag_duplicates()] + `filter(isdup)` + [expect_empty()] in one
#' step.
#'
#' @param data A data frame or tibble.
#' @param ... Key columns (tidy-select). If omitted, all columns are used,
#'   which checks for fully duplicated rows.
#' @inheritParams expect_empty
#' @param warn_msg Message shown (and logged) when duplicates exist and no
#'   `abort_msg` is set. Defaults to a description naming the key columns.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' # Success: one row per model
#' dplyr::distinct(ggplot2::mpg, model) |>
#'   expect_unique(model)
#'
#' # Warning: models appear in several years and variants
#' ggplot2::mpg |>
#'   expect_unique(model, year)
#'
#' \dontrun{
#' df |>
#'   expect_unique(cvr, year, abort_msg = "Duplicate company-years")
#' }
#'
#' @seealso [flag_duplicates()], [expect_empty()], [expect_none()]
#'
#' @export
expect_unique <- function(data, ...,
                          success_msg = NULL,
                          warn_msg    = NULL,
                          abort_msg   = NULL,
                          log         = getOption("daos.check_log"),
                          dump        = getOption("daos.check_dump")) {

  check_data_frame(data)
  key_cols <- if (...length() > 0) names(dplyr::select(data, ...))
  keys <- if (is.null(key_cols)) "all columns" else paste(key_cols, collapse = ", ")

  flagged <- flag_duplicates(data, ...)
  dups <- flagged[flagged$isdup, setdiff(names(flagged), "isdup")]
  dups <- dups[order(dups$dupid), ]

  label <- abort_msg %||% warn_msg
  report_check(
    violations  = dups,
    success_msg = success_msg %||%
      if (is.null(label)) paste0("Unique on ", keys) else paste0("Check passed: ", label),
    fail_msg    = label %||% paste0("Duplicate rows on ", keys),
    abort       = !is.null(abort_msg),
    log         = log,
    dump        = dump,
    key         = key_cols,
    group       = "dupid"
  )
  invisible(data)
}

# ---- R/expect_balanced.R ---------------------------------------------
#' Assert that a panel is balanced, or has no gaps
#'
#' A checkpoint for register panels: every unit (person, company, workplace)
#' must be observed in every period. Missing unit-periods are the violation
#' set, so a failure lists exactly which units lack which periods. Returns
#' `data`, so it can sit in the middle of a pipeline.
#'
#' Register populations are rarely fully balanced: people are born, die and
#' migrate, and firms open and close. `gaps_only = TRUE` relaxes the rule to
#' what usually *should* hold: a unit may enter late and leave early, but
#' once present it must not skip a period between its first and last. A
#' person present in 2019 and 2021 but missing in 2020 is then a gap; a
#' person first seen in 2021 is not.
#'
#' ## What counts as a period
#'
#' By default the expected periods are those observed anywhere in the data.
#' A period missing for *every* unit (e.g. a year that was never loaded) is
#' therefore invisible. Pass the periods you expect, e.g.
#' `periods = 2015:2024`, to catch that too. Observations outside `periods`
#' are ignored, as are rows with a missing period.
#'
#' Duplicated unit-periods do not make a panel unbalanced, but they are
#' usually an error of their own: check them with
#' [expect_unique()]`(data, id, time)`.
#'
#' The check scales to full-population registers: the unit-period grid is
#' only built for units that actually lack a period.
#'
#' @param data A data frame or tibble.
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr` or
#'   `c(cvr, lbnr)`.
#' @param time The period column (one column), e.g. `year`. Any type that
#'   sorts, such as integer years or dates.
#' @param periods Expected periods. Defaults to the periods observed in
#'   `data`.
#' @param gaps_only If `FALSE` (default), every unit must be observed in every
#'   period. If `TRUE`, only periods between a unit's first and last
#'   observation are required.
#' @inheritParams expect_empty
#' @param warn_msg Message shown (and logged) when unit-periods are missing
#'   and no `abort_msg` is set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' panel <- data.frame(
#'   cpr  = c("a", "a", "a", "b", "b", "c"),
#'   year = c(2020, 2021, 2022, 2020, 2022, 2022)
#' )
#'
#' # Not balanced: b lacks 2021, c lacks 2020 and 2021
#' expect_balanced(panel, cpr, year)
#'
#' # Only gaps: b lacks 2021; c simply entered in 2022
#' expect_balanced(panel, cpr, year, gaps_only = TRUE)
#'
#' # A year missing for everyone is only found with explicit periods
#' expect_balanced(panel, cpr, year, periods = 2019:2022, gaps_only = TRUE)
#'
#' @seealso [expect_unique()] for duplicated unit-periods,
#'   [expect_no_overlap()] for spell data, [expect_empty()].
#'
#' @export
expect_balanced <- function(data, id, time,
                            periods     = NULL,
                            gaps_only   = FALSE,
                            success_msg = NULL,
                            warn_msg    = NULL,
                            abort_msg   = NULL,
                            log         = getOption("daos.check_log"),
                            dump        = getOption("daos.check_dump")) {

  check_data_frame(data)
  ids      <- names(dplyr::select(data, {{ id }}))
  time_col <- names(dplyr::select(data, {{ time }}))
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(time_col) != 1) cli::cli_abort("{.arg time} must select exactly one column.")

  missing_periods <- find_panel_gaps(data, ids, time_col, periods, gaps_only)

  what  <- if (gaps_only) "Gaps in panel" else "Panel is not balanced"
  label <- abort_msg %||% warn_msg
  report_check(
    violations  = missing_periods,
    success_msg = success_msg %||%
      if (!is.null(label)) paste0("Check passed: ", label)
      else if (gaps_only) paste0("No gaps in ", time_col, " per ", toString(ids))
      else paste0("Balanced panel: ", toString(ids), " by ", time_col),
    fail_msg    = label %||%
      paste0(what, ": missing ", toString(ids), "-", time_col, " combinations"),
    abort       = !is.null(abort_msg),
    log         = log,
    dump        = dump
  )
  invisible(data)
}

# Unit-periods that should exist but don't, as a tibble of id + time columns.
find_panel_gaps <- function(data, ids, time_col, periods, gaps_only) {
  obs <- data.table::as.data.table(data)[, c(ids, time_col), with = FALSE]
  obs <- obs[!is.na(obs[[time_col]])]
  periods <- sort(unique(periods %||% obs[[time_col]]))
  obs <- unique(obs[obs[[time_col]] %in% periods])
  data.table::setorderv(obs, c(ids, time_col))

  # One group per unit; counting before expanding keeps the grid small
  unit   <- data.table::rleidv(obs, cols = ids)
  first  <- !duplicated(unit)
  n_seen <- tabulate(unit)
  pos    <- match(obs[[time_col]], periods)
  lo     <- if (gaps_only) pos[first] else rep(1L, sum(first))
  hi     <- if (gaps_only) pos[!duplicated(unit, fromLast = TRUE)] else rep(length(periods), sum(first))
  bad    <- which(n_seen < hi - lo + 1L)

  units <- obs[first, ids, with = FALSE][bad]
  span  <- hi[bad] - lo[bad] + 1L
  grid  <- units[rep(seq_len(nrow(units)), times = span)]
  data.table::set(grid, j = time_col,
                  value = periods[sequence(span, from = lo[bad])])

  tibble::as_tibble(grid[!obs, on = c(ids, time_col)])
}

# ---- R/expect_no_overlap.R -------------------------------------------
#' Assert that spells do not overlap within a unit
#'
#' A checkpoint for spell data, the other common shape of register data:
#' address periods, employment spells, benefit periods. Each unit can only be
#' in one spell at a time, so two spells for the same person that share a
#' day are an error. Returns `data`, so it can sit in the middle of a
#' pipeline.
#'
#' On failure the overlapping spells are reported with an `overlap_id`
#' column prepended, in the spirit of `dupid` in [flag_duplicates()]: spells
#' that overlap each other (directly or through a chain) share an id, so
#' each conflict can be inspected as a group.
#'
#' Spells are treated as closed intervals, as register dates usually are: a
#' spell ending 31 January and one starting 1 February do not overlap, while
#' one ending and one starting on 1 February do. A missing `end` means an
#' ongoing spell and overlaps everything after its start. Rows with a missing
#' `start` are ignored; check them with [expect_none()]`(data, is.na(start))`,
#' and spells that end before they start with
#' [expect_none()]`(data, end < start)`.
#'
#' @param data A data frame or tibble.
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr`.
#' @param start,end Columns with the first and last period of each spell
#'   (dates, or integers such as years).
#' @inheritParams expect_empty
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
#' expect_no_overlap(addresses, cpr, start, end)
#'
#' @seealso [expect_balanced()] for yearly panels, [expect_empty()].
#'
#' @export
expect_no_overlap <- function(data, id, start, end,
                              success_msg = NULL,
                              warn_msg    = NULL,
                              abort_msg   = NULL,
                              log         = getOption("daos.check_log"),
                              dump        = getOption("daos.check_dump")) {

  check_data_frame(data)
  ids       <- names(dplyr::select(data, {{ id }}))
  start_col <- names(dplyr::select(data, {{ start }}))
  end_col   <- names(dplyr::select(data, {{ end }}))
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(start_col) != 1 || length(end_col) != 1) {
    cli::cli_abort("{.arg start} and {.arg end} must each select exactly one column.")
  }

  overlaps <- find_overlaps(data, ids, start_col, end_col)

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
find_overlaps <- function(data, ids, start_col, end_col) {
  keys <- data.table::as.data.table(data)[, ids, with = FALSE]
  data.table::set(keys, j = ".start", value = as.numeric(data[[start_col]]))
  data.table::set(keys, j = ".row", value = seq_len(nrow(data)))
  keys <- keys[!is.na(keys$.start)]
  data.table::setorderv(keys, c(ids, ".start"))

  ends <- as.numeric(data[[end_col]])[keys$.row]
  ends[is.na(ends)] <- Inf
  unit <- data.table::rleidv(keys, cols = ids)
  n    <- length(unit)

  # A spell opens a new group unless it starts on or before the latest end
  # among the unit's earlier spells
  latest_end <- data.table::data.table(.unit = unit, .end = ends)[
    , .latest := cummax(.end), by = .unit]$.latest
  new_unit  <- c(TRUE, unit[-1] != unit[-n])
  new_group <- new_unit | keys$.start > c(-Inf, latest_end[-n])
  group     <- cumsum(new_group)
  hit       <- tabulate(group)[group] > 1

  out <- tibble::as_tibble(data[keys$.row[hit], , drop = FALSE])
  tibble::add_column(out, overlap_id = match(group[hit], unique(group[hit])),
                     .before = 1)
}

