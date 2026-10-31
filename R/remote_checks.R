# Checkpoints on database and Arrow tables --------------------------------
#
# A lazy table (dbplyr, e.g. DuckDB) is checked where it lives: the violation
# set is built as a query, and only its size, the preview rows and, with
# `dump`, the full set are fetched into R. Arrow tables and datasets go
# through DuckDB with arrow::to_duckdb(), so there is one code path. dbplyr,
# duckdb and arrow are only suggested: a data frame never needs them.

#' @importFrom rlang .data
NULL

# The table to check: a data frame as it is, anything else as a lazy table.
check_table <- function(data, call = rlang::caller_env()) {
  if (is.data.frame(data)) return(data)
  if (inherits(data, "tbl_lazy")) {
    rlang::check_installed("dbplyr", "to check a database table.", call = call)
    return(data)
  }
  if (inherits(data, c("ArrowTabular", "Dataset", "arrow_dplyr_query"))) {
    rlang::check_installed(c("duckdb", "dbplyr"), "to check an Arrow table.", call = call)
    return(arrow::to_duckdb(data))
  }
  cli::cli_abort(
    "{.arg data} must be a data frame, a database table or an Arrow table, not {.cls {class(data)}}.",
    call = call
  )
}

is_remote <- function(data) !is.data.frame(data)

# Column names of a selection; names() of a lazy table are its internals.
select_names <- function(data, ...) colnames(dplyr::select(data, ...))

remote_nrow <- function(x) {
  n <- dplyr::pull(dplyr::summarise(dplyr::ungroup(x), .lustrum_n = dplyr::n()))
  as.numeric(n)
}

# DENSE_RANK() over the given columns. dbplyr's dense_rank() takes a single
# column, and the numbering of duplicate and overlap groups needs several.
sql_dense_rank <- function(tbl, cols) {
  con <- dbplyr::remote_con(tbl)
  cols <- DBI::dbQuoteIdentifier(con, cols)
  dbplyr::sql(paste0(
    "DENSE_RANK() OVER (ORDER BY ",
    paste0("CASE WHEN ", cols, " IS NULL THEN 0 ELSE 1 END, ", cols, collapse = ", "),
    ")"
  ))
}

# Rows whose key occurs more than once, numbered by `dupid` in key order.
# A database has no row order, so groups cannot be numbered by first
# appearance as in memory. NULL keys form a group, as NA keys do in memory.
remote_duplicates <- function(tbl, cols) {
  dups <- tbl |>
    dplyr::select(!dplyr::any_of("dupid")) |>
    dplyr::group_by(!!!rlang::syms(cols)) |>
    dplyr::filter(dplyr::n() > 1L) |>
    dplyr::ungroup()
  dups |>
    dplyr::mutate(dupid = !!sql_dense_rank(dups, cols)) |>
    sort_by(rlang::exprs(.data$dupid))
}

# Missing unit-periods, as find_panel_gaps() but as one query. The periods
# travel inline with their positions, so nothing is written to the database.
remote_panel_gaps <- function(tbl, ids, time_col, periods, gaps_only) {
  obs <- tbl |>
    dplyr::select(dplyr::all_of(c(ids, time_col))) |>
    dplyr::filter(!is.na(.data[[time_col]]))
  if (is.null(periods)) {
    periods <- sort(dplyr::pull(dplyr::distinct(obs, .data[[time_col]])))
  } else {
    periods <- sort(unique(periods))
    obs <- dplyr::filter(obs, .data[[time_col]] %in% !!periods)
  }
  per <- tibble::tibble(!!time_col := periods, .lustrum_pos = seq_along(periods))
  per <- dbplyr::copy_inline(dbplyr::remote_con(tbl), per)
  obs <- dplyr::inner_join(dplyr::distinct(obs), per, by = time_col)

  units <- obs |>
    dplyr::group_by(!!!rlang::syms(ids)) |>
    dplyr::summarise(.lustrum_n  = dplyr::n(),
                     .lustrum_lo = min(.data$.lustrum_pos, na.rm = TRUE),
                     .lustrum_hi = max(.data$.lustrum_pos, na.rm = TRUE),
                     .groups = "drop")
  if (!gaps_only) {
    units <- dplyr::mutate(units, .lustrum_lo = 1L, .lustrum_hi = !!length(periods))
  }

  units |>
    dplyr::filter(.data$.lustrum_n < .data$.lustrum_hi - .data$.lustrum_lo + 1L) |>
    dplyr::cross_join(per) |>
    dplyr::filter(.data$.lustrum_pos >= .data$.lustrum_lo, .data$.lustrum_pos <= .data$.lustrum_hi) |>
    dplyr::select(dplyr::all_of(c(ids, time_col))) |>
    dplyr::anti_join(dplyr::select(obs, dplyr::all_of(c(ids, time_col))),
                     by = c(ids, time_col), na_matches = "na") |>
    sort_by(na_first(c(ids, time_col)))
}

# Overlapping spells, as find_overlaps() but with window functions: per
# unit, ordered by start, a spell opens a new group unless it starts on or
# before the latest end of the earlier spells, or an earlier spell is open.
remote_overlaps <- function(tbl, ids, start_col, end_col) {
  start <- rlang::sym(start_col)
  end   <- rlang::sym(end_col)

  spells <- tbl |>
    dplyr::filter(!is.na(!!start)) |>
    dplyr::group_by(!!!rlang::syms(ids)) |>
    dbplyr::window_order(!!start, !!end) |>
    dbplyr::window_frame(-Inf, -1) |>
    dplyr::mutate(
      .lustrum_prev_end  = max(!!end, na.rm = TRUE),
      .lustrum_prev_open = max(dplyr::if_else(is.na(!!end), 1L, 0L), na.rm = TRUE)
    ) |>
    dplyr::mutate(
      .lustrum_new = dplyr::if_else(
        dplyr::coalesce(.data$.lustrum_prev_open, 0L) == 1L, 0L,
        dplyr::if_else(is.na(.data$.lustrum_prev_end) | !!start > .data$.lustrum_prev_end, 1L, 0L)
      )
    ) |>
    dplyr::mutate(.lustrum_grp = cumsum(.data$.lustrum_new)) |>
    # the frame would otherwise carry into n() below
    dbplyr::window_frame(-Inf, Inf) |>
    dplyr::group_by(!!!rlang::syms(c(ids, ".lustrum_grp"))) |>
    dplyr::filter(dplyr::n() > 1L) |>
    dplyr::ungroup()

  spells |>
    dplyr::mutate(overlap_id = !!sql_dense_rank(spells, c(ids, ".lustrum_grp"))) |>
    dplyr::select(!dplyr::starts_with(".lustrum_")) |>
    sort_by(rlang::exprs(.data$overlap_id, !!start, !!end))
}

# Rows of the units where a column has two different non-missing values,
# as varying_units() in memory: min() and max() skip NULL in SQL, so they
# differ exactly then.
remote_varying <- function(tbl, ids, cols) {
  tests <- lapply(rlang::syms(cols), function(col) {
    rlang::expr(min(!!col, na.rm = TRUE) != max(!!col, na.rm = TRUE))
  })
  units <- tbl |>
    dplyr::group_by(!!!rlang::syms(ids)) |>
    dplyr::summarise(.lustrum_bad = !!Reduce(function(a, b) rlang::expr(!!a | !!b), tests),
                     .groups = "drop") |>
    dplyr::filter(.data$.lustrum_bad) |>
    dplyr::select(dplyr::all_of(ids))
  tbl |>
    dplyr::semi_join(units, by = ids, na_matches = "na") |>
    sort_by(na_first(ids))
}

# Rows outside their bounds, as find_outside() in memory. A comparison with
# NULL is NULL, which WHERE drops, so missing bounds are open without a
# test of their own. A date compared with a year counts by its year.
remote_outside <- function(tbl, time_col, from_col, to_col) {
  proto <- dplyr::collect(utils::head(
    dplyr::select(tbl, dplyr::all_of(c(time_col, from_col, to_col))), 0L))
  is_date <- function(col) inherits(proto[[col]], c("Date", "POSIXt"))
  con <- dbplyr::remote_con(tbl)
  on_scale <- function(col, other) {
    if (is_date(col) && !is_date(other)) {
      dbplyr::sql(paste0("EXTRACT(YEAR FROM ", DBI::dbQuoteIdentifier(con, col), ")"))
    } else {
      rlang::sym(col)
    }
  }
  before <- if (length(from_col)) {
    rlang::expr(!!on_scale(time_col, from_col) < !!on_scale(from_col, time_col))
  }
  after <- if (length(to_col)) {
    rlang::expr(!!on_scale(time_col, to_col) > !!on_scale(to_col, time_col))
  }
  test <- if (is.null(before)) after else if (is.null(after)) before
          else rlang::expr(!!before | !!after)
  label <- if (is.null(before)) {
    paste("after", to_col)
  } else if (is.null(after)) {
    paste("before", from_col)
  } else {
    rlang::expr(dplyr::case_when(!!before ~ !!paste("before", from_col),
                                 TRUE ~ !!paste("after", to_col)))
  }
  tbl |>
    dplyr::select(!dplyr::any_of("outside")) |>
    dplyr::filter(!!test) |>
    dplyr::mutate(outside = !!label) |>
    dplyr::relocate("outside") |>
    sort_by(c(rlang::exprs(.data$outside), na_first(time_col)))
}

# The finders return their query unsorted, since a sorted query that is
# counted or summarised makes dbplyr warn, and attach the sort order for
# report_check() to apply when rows are fetched.
sort_by <- function(query, order) structure(query, lustrum_order = order)

# Sort keys putting NULL first, as data.table sorts NA, for arrange(). The
# CASE form works on every backend; NULLS FIRST does not (SQL Server).
na_first <- function(cols) {
  unlist(lapply(rlang::syms(cols), function(col) {
    list(rlang::expr(dplyr::if_else(is.na(!!col), 0L, 1L)), col)
  }), recursive = FALSE)
}
