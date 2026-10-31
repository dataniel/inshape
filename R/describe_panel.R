#' Describe the structure of a panel
#'
#' Before deciding which rule a panel must meet, look at what it is: how
#' many units and periods, how many units are observed throughout, who
#' enters and leaves when, where the gaps are, and which participation
#' patterns are common. `describe_panel()` answers that in one pass and
#' judges nothing; turn what you learn into a rule with [ensure_balanced()]
#' or [ensure_unique()].
#'
#' It is the panel summary of Stata's `xtdescribe`, made for population
#' registers: a sudden fall in the number of units in one period, a period
#' with no units at all, or many units with a single missing year are the
#' signs of a broken extract, and they are visible here at a glance.
#'
#' ## What is counted
#'
#' A unit-period is counted once, however many rows it has; the extra rows
#' are reported as duplicates. Rows with a missing period, or a period
#' outside `periods`, are left out and counted. A missing id is a unit of
#' its own, as in [ensure_balanced()], and the rows are counted.
#'
#' In `by_period`, `entries` are the units first observed in a period and
#' `exits` those last observed in it. Neither is known at the edges, where
#' a unit may have been present before the first or after the last period,
#' so `entries` is `NA` in the first period and `exits` in the last. `gaps`
#' counts the units absent in a period although they are observed both
#' before and after it.
#'
#' A participation pattern has one character per period, `1` when the unit
#' is observed and `.` when not, as in `xtdescribe`: `11.11` is a unit
#' missing in the middle period of five.
#'
#' @section Why it is fast:
#' The id columns are compressed to integer unit ids by one compiled hash
#' pass, without sorting them. The panel then becomes a bit matrix, one bit
#' per unit and period (6 million persons over 64 periods take 48 MB), set
#' in a single pass over the rows; a bit already set is a duplicate. First
#' and last period, counts, runs and patterns are read from the bits with
#' processor bit instructions, so nothing is sorted per row. When the bit
#' matrix would be much larger than the data, as for daily periods over
#' many years, the unit-periods are sorted instead and the patterns, as long
#' as the panel and nearly all different, are left out.
#'
#' @param data A data frame or tibble.
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr`.
#' @param time The period column (one column), e.g. `year`.
#' @param periods Expected periods. Defaults to those observed in `data`.
#'   Pass them, e.g. `2015:2024`, to see a period that is missing for
#'   everyone.
#' @param patterns Number of participation patterns to keep, most common
#'   first.
#'
#' @return An object of class `lustrum_panel`, printed as a summary. It is
#'   a list with the counts (`n_rows`, `n_units`, `n_complete`,
#'   `n_with_gaps`, `n_gap_cells`, `n_dup_cells`, `n_dup_rows`,
#'   `n_missing_id`, `n_missing_time`, `n_outside`), the `periods`, and
#'   three tibbles: `by_period` (`period`, `units`, `entries`, `exits`,
#'   `gaps`), `runs` (units by number of separate runs of presence) and
#'   `patterns` (`pattern`, `units`, `share`).
#'
#' @examples
#' panel <- data.frame(
#'   cpr  = c("a", "a", "a", "b", "b", "c", "d", "d", "d"),
#'   year = c(2020, 2021, 2022, 2020, 2022, 2022, 2020, 2021, 2022)
#' )
#' describe_panel(panel, cpr, year)
#'
#' # The counts are there to use
#' p <- describe_panel(panel, cpr, year)
#' p$by_period
#'
#' @seealso [ensure_balanced()] to require a balanced panel or no gaps,
#'   [describe_key()] for duplicated keys.
#'
#' @export
describe_panel <- function(data, id, time, periods = NULL, patterns = 10) {
  check_data_frame(data)
  ids      <- select_names(data, {{ id }})
  time_col <- select_names(data, {{ time }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(time_col) != 1) cli::cli_abort("{.arg time} must select exactly one column.")
  if (!rlang::is_scalar_integerish(patterns) || patterns < 0) {
    cli::cli_abort("{.arg patterns} must be a single non-negative whole number.")
  }

  ix    <- panel_index(data, ids, time_col, periods)
  cells <- panel_cells(ix)
  n_per <- length(ix$periods)

  present <- which(cells$n_seen > 0L)
  n_seen  <- cells$n_seen[present]
  lo      <- cells$lo[present]
  hi      <- cells$hi[present]
  dup_rows <- cells$dup_rows

  # Spanning units in a period, minus those observed in it, are its gaps
  entries <- tabulate(lo, n_per)
  exits   <- tabulate(hi, n_per)
  units   <- tabulate(ix$pos, n_per) - tabulate(ix$pos[dup_rows], n_per)
  spanning <- cumsum(entries) - (cumsum(exits) - exits)
  by_period <- tibble::tibble(
    period  = ix$periods,
    units   = units,
    entries = replace(entries, 1, NA),
    exits   = replace(exits, n_per, NA),
    gaps    = spanning - units
  )

  dup_cells <- (ix$unit[dup_rows] - 1) * n_per + ix$pos[dup_rows]
  by_runs <- tabulate(cells$runs[present])
  missing_time <- is.na(data[[time_col]])
  structure(list(
    ids            = ids,
    time           = time_col,
    periods        = ix$periods,
    n_rows         = nrow(data),
    n_units        = length(present),
    n_complete     = sum(n_seen == n_per),
    n_with_gaps    = sum(hi - lo + 1L > n_seen),
    n_gap_cells    = sum(hi - lo + 1L - n_seen),
    n_dup_cells    = length(unique(dup_cells)),
    n_dup_rows     = length(dup_rows),
    n_missing_id   = sum(Reduce(`|`, lapply(unclass(data)[ids], is.na))),
    n_missing_time = sum(missing_time),
    n_outside      = sum(!missing_time) - sum(!is.na(ix$pos)),
    by_period      = by_period,
    runs           = tibble::tibble(runs = which(by_runs > 0), units = by_runs[by_runs > 0]),
    patterns       = panel_patterns(cells, present, n_per, patterns)
  ), class = "lustrum_panel")
}

# The most common participation patterns, from the pattern ids the engine
# gives each unit; only the kept patterns are turned into text. Without
# pattern ids (very long panels, see panel_cells()) there are none.
panel_patterns <- function(cells, present, n_per, keep) {
  empty <- tibble::tibble(pattern = character(), units = integer(), share = numeric())
  if (length(present) == 0 || keep == 0 || is.na(cells$n_patterns)) return(empty)
  counts <- tabulate(cells$pattern[present], cells$n_patterns)
  top <- utils::head(order(counts, decreasing = TRUE), keep)
  first <- match(top, cells$pattern)
  text <- vapply(first, function(u) {
    paste(ifelse(cells$bits_of(u), "1", "."), collapse = "")
  }, character(1))
  tibble::tibble(pattern = text, units = counts[top],
                 share = counts[top] / length(present))
}

#' @export
print.lustrum_panel <- function(x, ...) {
  per <- x$periods
  span <- if (length(per)) paste0(", ", format(per[1]), "-", format(per[length(per)])) else ""

  cli::cat_rule(paste0("Panel: ", toString(x$ids), " by ", x$time))
  cli::cat_line(count(x$n_rows, "row"), ", ", count(x$n_units, "unit"), ", ",
                count(length(per), "period"), span)
  cli::cat_line()
  cli::cat_bullet(paste0("Observed in every period: ", count(x$n_complete, "unit"),
                         share(x$n_complete, x$n_units)))
  cli::cat_bullet(paste0("With gaps: ", count(x$n_with_gaps, "unit"),
                         share(x$n_with_gaps, x$n_units), ", ",
                         count(x$n_gap_cells, "missing unit-period"), " inside their span"))
  cli::cat_bullet(paste0("Duplicated unit-periods: ", big(x$n_dup_cells),
                         " (", count(x$n_dup_rows, "extra row"), ")"))
  empty <- per[x$by_period$units == 0]
  if (length(empty)) {
    cli::cat_bullet(paste0("Periods without units: ", toString(format(empty))))
  }
  if (x$n_missing_id > 0) cli::cat_bullet(paste0("Rows with a missing id: ", big(x$n_missing_id)))
  if (x$n_missing_time > 0) cli::cat_bullet(paste0("Rows with a missing ", x$time, ": ", big(x$n_missing_time)))
  if (x$n_outside > 0) cli::cat_bullet(paste0("Rows outside the periods: ", big(x$n_outside)))

  cli::cat_line()
  cli::cat_line("By period:")
  print_table(x$by_period)
  if (nrow(x$patterns)) {
    cli::cat_line()
    cli::cat_line("Most common patterns:")
    pat <- x$patterns
    pat$share <- sprintf("%.1f%%", 100 * pat$share)
    print_table(pat)
  }
  invisible(x)
}

# Number formatting for the describe_*() summaries
big <- function(v) format(v, big.mark = ",", scientific = FALSE, trim = TRUE)
count <- function(v, noun) paste(big(v), if (v == 1) noun else paste0(noun, "s"))
share <- function(v, of) if (of == 0) "" else sprintf(" (%.1f%%)", 100 * v / of)

# A tibble printed without its header and footer lines
print_table <- function(df, n = 20) {
  lines <- format(tibble::as_tibble(df), n = n)
  lines <- lines[!grepl("^# A tibble|^# \u2139|print\\(n = |<[a-z]{3}>", cli::ansi_strip(lines))]
  cli::cat_line(paste0("  ", lines))
}
