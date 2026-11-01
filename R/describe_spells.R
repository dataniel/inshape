#' Describe the structure of spell data
#'
#' Spell data, one row per spell with a start and an end, is where register
#' data is most often subtly wrong: spells that overlap, a transfer recorded
#' as two spells, a spell that ends before it starts, a spell that never
#' ends. `describe_spells()` counts all of it in one pass and judges
#' nothing; require what should hold with [ensure_no_overlap()].
#'
#' ## How each spell relates to the earlier ones
#'
#' Within a unit, spells are taken in order of start, and each is compared
#' with the latest end among the unit's earlier spells:
#'
#' * `gap`: it starts after a gap. The gap lengths are summarised.
#' * `adjacent`: it starts the day (or period) after an earlier spell ends.
#'   Two adjacent spells are often one spell recorded twice, e.g. a
#'   transfer between wards or employers, and may need merging with
#'   [merge_spells()] before spells are counted.
#' * `touching`: it starts on the day an earlier spell ends. Spells are
#'   closed intervals, so the two share that day and overlap by one day,
#'   the usual way a discharge and a readmission on the same day look.
#' * `overlapping`: it starts inside an earlier spell and ends after it.
#' * `nested`: it lies entirely within an earlier spell, or starts after
#'   an ongoing one.
#' * `duplicate`: it has the same start and end as the spell before it.
#'
#' Spells with the same start are taken longest first, so a shorter one is
#' `nested` in the longer. A missing end means an ongoing spell. Spells
#' with a missing start, or an end before the start, are counted and left
#' out of the rest.
#'
#' `start` and `end` may be dates, compared by day, or whole numbers such as
#' years or month numbers, compared by that unit.
#'
#' @section Why it is fast:
#' Units are compressed to integer ids by the compiled engine, the spells
#' are sorted once by data.table's multi-threaded radix sort, and one
#' compiled pass then relates each spell to the earlier ones, reading memory
#' in order. Counts and lengths are read from counts per day, never from
#' sorting millions of values.
#'
#' @param data A data frame or tibble with one row per spell, or a database
#'   or Arrow table: see *Database tables* in [checkpoints].
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr`.
#' @param start,end Columns with the first and last day (or period) of each
#'   spell. A missing `end` means an ongoing spell.
#'
#' @return An object of class `inshape_spells`, printed as a summary. It is
#'   a list with the counts `n_rows`, `n_spells` (usable spells), `n_units`,
#'   `n_missing_start`, `n_end_before_start`, `n_ongoing`, `n_single`
#'   (spells of one day or period) and `n_units_overlapping` (units with a
#'   touching, overlapping, nested or duplicate spell), and the tibbles
#'   `relations` (`relation`, `spells`), `gaps` and `lengths` (summaries of
#'   gap and spell lengths), `spells_per_unit` (`spells`, `units`) and
#'   `by_year` (`year`, `starts`, `ends`; by value for whole numbers).
#'
#' @examples
#' admissions <- data.frame(
#'   cpr   = c("a", "a", "a", "b", "b", "c"),
#'   start = as.Date(c("2020-01-01", "2020-01-11", "2020-03-01",
#'                     "2020-01-01", "2020-01-05", "2021-06-01")),
#'   end   = as.Date(c("2020-01-10", "2020-01-20", "2020-03-05",
#'                     "2020-01-31", "2020-01-10", NA))
#' )
#' # a: a transfer on 11 January, then a gap; b: a nested spell; c: ongoing
#' describe_spells(admissions, cpr, start, end)
#'
#' @seealso [merge_spells()] to merge adjacent and overlapping spells,
#'   [ensure_no_overlap()] to require spells not to overlap,
#'   [spells_to_panel()] to turn spells into a panel.
#'
#' @export
describe_spells <- function(data, id, start, end) {
  tbl       <- check_table(data)
  ids       <- select_names(tbl, {{ id }})
  start_col <- select_names(tbl, {{ start }})
  end_col   <- select_names(tbl, {{ end }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(start_col) != 1 || length(end_col) != 1) {
    cli::cli_abort("{.arg start} and {.arg end} must each select exactly one column.")
  }
  if (is_remote(tbl)) return(remote_describe_spells(tbl, ids, start_col, end_col))
  s <- spell_numbers(data[[start_col]], start_col)
  e <- spell_numbers(data[[end_col]], end_col)
  is_date <- inherits(data[[start_col]], c("Date", "POSIXt"))

  missing_start <- is.na(s)
  bad_order <- !missing_start & !is.na(e) & e < s
  usable <- !missing_start & !bad_order
  unit <- group_ids(data, ids)
  n_units <- attr(unit, "n")
  spells <- spell_scan(unit, s, e, usable)
  rel <- spells$rel
  closed <- which(usable & !is.na(e))

  names_rel <- c("gap", "adjacent", "touching", "overlapping", "nested", "duplicate")
  per_unit <- tabulate(unit[usable], n_units)
  per_unit <- tabulate(per_unit[per_unit > 0])
  by_n <- which(per_unit > 0)

  starts_by <- count_values(s[usable])
  ends_by   <- count_values(e[closed])
  if (is_date) {
    starts_by <- per_year(starts_by)
    ends_by   <- per_year(ends_by)
  }
  periods <- sort(unique(c(starts_by$value, ends_by$value)))

  structure(list(
    ids                 = ids,
    start               = start_col,
    end                 = end_col,
    unit_word           = if (is_date) "day" else "period",
    n_rows              = nrow(data),
    n_spells            = sum(usable),
    n_units             = sum(per_unit),
    n_missing_start     = sum(missing_start),
    n_end_before_start  = sum(bad_order),
    n_ongoing           = sum(usable) - length(closed),
    n_single            = sum(e[closed] == s[closed]),
    n_units_overlapping = length(unique(spells$u[rel >= 3L])),
    relations = tibble::tibble(relation = names_rel,
                               spells = tabulate(rel, 6L)),
    gaps      = number_summary(spells$gap[rel == 1L]),
    lengths   = number_summary(e[closed] - s[closed] + 1L),
    spells_per_unit = tibble::tibble(spells = by_n, units = per_unit[by_n]),
    by_year   = tibble::tibble(
      year   = periods,
      starts = spread_counts(starts_by, periods),
      ends   = spread_counts(ends_by, periods)
    )
  ), class = "inshape_spells")
}

# The usable spells sorted by unit, start and longest first, with each
# spell's relation and gap (see src/spells.c) and its row in the data. An
# ongoing spell ends at the largest integer.
spell_scan <- function(unit, start, end, usable) {
  ok <- which(usable)
  ends <- end[ok]
  ends[is.na(ends)] <- .Machine$integer.max
  # setDT() on a list: the columns are new already, and data.table() would
  # copy them again
  spells <- data.table::setDT(list(u = unit[ok], s = start[ok], e = ends, row = ok))
  data.table::setorderv(spells, c("u", "s", "e"), order = c(1L, 1L, -1L))
  res <- .Call(C_inshape_spell_relations, spells$u, spells$s, spells$e)
  data.table::set(spells, j = "rel", value = res[[1]])
  data.table::set(spells, j = "gap", value = res[[2]])
  spells
}

# Spell bounds as integers: days for dates, the value for whole numbers
spell_numbers <- function(x, col, call = rlang::caller_env()) {
  if (inherits(x, "POSIXt")) x <- as.Date(x)
  if (inherits(x, "Date")) return(as.integer(floor(unclass(x))))
  if (is.numeric(x) && !is.object(x) &&
      all(is.na(x) | (x == round(x) & abs(x) < .Machine$integer.max))) {
    return(as.integer(x))
  }
  cli::cli_abort(c("{.var {col}} must be a Date column or whole numbers, not {.cls {class(x)[1]}}.",
                   "i" = "Convert it first, e.g. with {.fn as.Date}."), call = call)
}

# The distinct values of an integer vector with their counts. Dates and
# lengths span a few thousand values, so a counting pass (tabulate)
# replaces sorting or hashing millions of rows; a wide range falls back to
# a grouped count.
count_values <- function(x) {
  if (length(x) == 0) return(list(value = integer(), n = integer()))
  lo <- min(x)
  width <- as.double(max(x)) - lo + 1
  if (width <= max(1e7, length(x))) {
    n <- tabulate(x - lo + 1L, width)
    keep <- which(n > 0L)
    return(list(value = keep + lo - 1L, n = n[keep]))
  }
  code <- dense_codes(x)
  first <- first_row_by(code, attr(code, "n"))
  value <- x[first]
  o <- order(value)
  list(value = value[o], n = tabulate(code, attr(code, "n"))[o])
}

# Counts per day to counts per year
per_year <- function(counts) {
  year <- as.POSIXlt(as.Date(counts$value))$year + 1900L
  sums <- rowsum(counts$n, year, reorder = TRUE)
  list(value = as.integer(rownames(sums)), n = as.integer(sums[, 1]))
}

spread_counts <- function(counts, values) {
  out <- integer(length(values))
  out[match(counts$value, values)] <- counts$n
  out
}

# Count, minimum, quartiles, mean and maximum of a vector of lengths, read
# from the counts of each value (type 1 quantiles: an observed value)
number_summary <- function(x) summary_of_counts(count_values(x))

# The same summary from distinct values and their counts, sorted by value,
# as a database returns them
summary_of_counts <- function(counts) {
  if (length(counts$value) == 0) {
    return(tibble::tibble(n = 0L, min = NA_real_, q25 = NA_real_, median = NA_real_,
                          mean = NA_real_, q75 = NA_real_, max = NA_real_))
  }
  counts$value <- as.numeric(counts$value)
  total <- sum(counts$n)
  at <- cumsum(counts$n)
  q <- vapply(c(.25, .5, .75), function(p) {
    counts$value[which(at >= ceiling(p * total))[1]]
  }, numeric(1))
  tibble::tibble(n = total, min = counts$value[1], q25 = q[1], median = q[2],
                 mean = sum(as.double(counts$value) * counts$n) / total,
                 q75 = q[3], max = counts$value[length(counts$value)])
}

#' @export
print.inshape_spells <- function(x, ...) {
  cli::cat_rule(paste0("Spells: ", x$start, " to ", x$end, " per ", toString(x$ids)))
  cli::cat_line(count(x$n_rows, "row"), ", ", count(x$n_spells, "usable spell"),
                ", ", count(x$n_units, "unit"))
  cli::cat_line()
  if (x$n_missing_start > 0) cli::cat_bullet(paste0("Missing ", x$start, ": ", big(x$n_missing_start)))
  if (x$n_end_before_start > 0) cli::cat_bullet(paste0("Ending before they start: ", big(x$n_end_before_start)))
  cli::cat_bullet(paste0("Ongoing (no ", x$end, "): ", big(x$n_ongoing)))
  cli::cat_bullet(paste0("Units with overlapping spells: ", big(x$n_units_overlapping),
                         share(x$n_units_overlapping, x$n_units)))
  cli::cat_line()
  cli::cat_line("Relation to the unit's earlier spells:")
  print_table(x$relations)
  w <- x$unit_word
  if (x$gaps$n > 0) {
    cli::cat_line()
    cli::cat_line("Gaps between spells, in ", w, "s:")
    print_table(x$gaps)
  }
  if (x$lengths$n > 0) {
    cli::cat_line()
    cli::cat_line("Length of ended spells, in ", w, "s:")
    print_table(x$lengths)
  }
  invisible(x)
}
