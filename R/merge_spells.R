#' Merge spells that follow each other or overlap into one
#'
#' A stay in hospital moved between wards, a job continued with a new
#' contract, an address re-registered the day after: registers often record
#' one spell as several, back to back or overlapping, and every count of
#' spells, lengths and transitions is wrong until they are merged.
#' [describe_spells()] shows how often it happens; `merge_spells()` does the
#' merging, one row per merged spell.
#'
#' ## When spells are merged
#'
#' Within a unit, spells are taken in order of start, and a spell is merged
#' into the one before when the number of days between them, from the latest
#' end so far to its start, is at most `max_gap`:
#'
#' * `max_gap = 0` (default) merges spells that overlap, share a day, or
#'   where one starts the day after the other ends: the transfers.
#' * `max_gap = -1` merges only spells that share at least one day, and
#'   keeps transfers apart.
#' * `max_gap = 30` also merges spells less than a month apart, e.g. a
#'   readmission within 30 days counted as the same episode.
#'
#' The merged spell runs from the first start to the latest end, and is
#' ongoing (missing end) if any of its spells is. Use `by` to merge only
#' spells that agree in a column, e.g. the employer or the status, so a job
#' followed directly by unemployment stays two spells: spells are then
#' grouped by the `id` and `by` columns together.
#'
#' Columns other than `id`, `by`, `start` and `end` are dropped, as one
#' merged spell may have several values for them; `n_spells` counts the
#' spells merged into each row. Rows with a missing start or an end before
#' the start are dropped with a message, as in [spells_to_panel()].
#'
#' `start` and `end` may be dates or whole numbers (years, month numbers),
#' compared by that unit.
#'
#' @section Why it is fast:
#' It shares the compiled pass of [describe_spells()]: units are compressed
#' to integer ids (see [checkpoints]), spells are
#' sorted once by data.table's radix sort, and one sequential pass relates
#' each spell to the earlier ones. The result is not sorted by the id
#' columns, which on a population register means sorting millions of
#' strings and would take most of the time; units keep the order of the
#' data, which for an extract sorted by cpr is the same.
#'
#' @param data A data frame or tibble with one row per spell.
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr`.
#' @param start,end Columns with the first and last day (or period) of each
#'   spell. A missing `end` means an ongoing spell.
#' @param by Optional column(s) (tidy-select) that must be equal for spells
#'   to be merged, e.g. `employer`.
#' @param max_gap Largest number of days (or periods) between two spells
#'   that are still merged: `0` merges spells that follow the next day, `-1`
#'   only spells that share a day. A whole number from -1.
#'
#' @return A tibble (a data.table if `data` is one) with the `id` and `by`
#'   columns, `start`, `end` and `n_spells`, one row per merged spell. Units
#'   come in the order they first appear in `data`, and each unit's spells
#'   by start; use `dplyr::arrange()` to sort by the id columns.
#'
#' @examples
#' admissions <- data.frame(
#'   cpr   = c("a", "a", "a", "b", "b"),
#'   start = as.Date(c("2020-01-01", "2020-01-11", "2020-03-01",
#'                     "2020-01-01", "2020-01-05")),
#'   end   = as.Date(c("2020-01-10", "2020-01-20", "2020-03-05",
#'                     "2020-01-31", "2020-01-10")),
#'   ward  = c("A", "B", "A", "A", "C")
#' )
#' # a is moved from ward A to B on 11 January: one stay, then a new one
#' merge_spells(admissions, cpr, start, end)
#'
#' # Readmissions within 60 days count as the same episode
#' merge_spells(admissions, cpr, start, end, max_gap = 60)
#'
#' # Only stays in the same ward
#' merge_spells(admissions, cpr, start, end, by = ward)
#'
#' @seealso [describe_spells()] to see how many spells follow each other or
#'   overlap, [ensure_no_overlap()] to require that none overlap.
#'
#' @export
merge_spells <- function(data, id, start, end, by = NULL, max_gap = 0) {
  check_data_frame(data)
  ids       <- select_names(data, {{ id }})
  by_cols   <- setdiff(select_names(data, {{ by }}), ids)
  start_col <- select_names(data, {{ start }})
  end_col   <- select_names(data, {{ end }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(start_col) != 1 || length(end_col) != 1) {
    cli::cli_abort("{.arg start} and {.arg end} must each select exactly one column.")
  }
  if (!rlang::is_scalar_integerish(max_gap) || is.na(max_gap) || max_gap < -1) {
    cli::cli_abort("{.arg max_gap} must be a whole number from -1, e.g. {.code 0} or {.code 30}.")
  }
  keep <- c(ids, by_cols)
  clash <- intersect(keep, c(start_col, end_col, "n_spells"))
  if (length(clash) > 0) {
    cli::cli_abort("{.arg id} and {.arg by} must not include {.var {clash}}.")
  }

  s <- spell_numbers(data[[start_col]], start_col)
  e <- spell_numbers(data[[end_col]], end_col)
  bad_start <- is.na(s)
  bad_order <- !bad_start & !is.na(e) & e < s
  if (any(bad_start)) {
    cli::cli_alert_warning("Dropped {sum(bad_start)} spell{?s} with a missing {.var {start_col}}.")
  }
  if (any(bad_order)) {
    cli::cli_alert_warning("Dropped {sum(bad_order)} spell{?s} where {.var {end_col}} is before {.var {start_col}}.")
  }

  spells <- spell_scan(first_appearance_ids(data, keep), s, e, !bad_start & !bad_order)
  rel <- spells$rel
  # A spell opens a merged spell unless at most max_gap days lie between
  # it and the latest end so far: none for adjacent, fewer than none for
  # touching, overlapping, nested and duplicate spells
  opens <- rel == 0L | (rel == 1L & spells$gap > max_gap) | (rel == 2L & max_gap < 0L)
  # Merged spells are runs of sorted rows: the first start is the run's
  # first row, the latest end a grouped max (data.table's GForce)
  heads <- which(opens)
  data.table::set(spells, j = "m", value = cumsum(opens))
  ends <- if (length(heads)) spells[, list(e = max(e)), by = "m"]$e else integer()
  ends[ends == .Machine$integer.max] <- NA_integer_

  out <- lapply(unclass(data)[keep], `[`, spells$row[heads])
  out[[start_col]] <- spell_values(spells$s[heads], data[[start_col]])
  out[[end_col]]   <- spell_values(ends, data[[end_col]])
  out$n_spells     <- diff(c(heads, nrow(spells) + 1L))
  out <- data.table::setDT(out)
  if (data.table::is.data.table(data)) out else tibble::as_tibble(out)
}

# Unit ids numbered in the order the units first appear in the data, so
# that sorting the spells by unit id keeps that order. Sorting by the key
# itself would sort millions of strings, the slowest step by far on a
# population register; first appearance needs only an integer order, and
# a register extract sorted by cpr comes out sorted by cpr.
first_appearance_ids <- function(data, cols) {
  unit <- group_ids(data, cols)
  first <- first_row_by(unit, attr(unit, "n"))
  rank <- integer(length(first))
  present <- which(first > 0L)
  rank[present[order(first[present], method = "radix")]] <- seq_along(present)
  rank[unit]
}

# Integer days or numbers back in the type of the original column
spell_values <- function(x, like) {
  if (inherits(like, c("Date", "POSIXt"))) return(as.Date(x))
  if (is.double(like)) return(as.double(x))
  x
}
