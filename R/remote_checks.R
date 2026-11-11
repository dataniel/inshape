# Checkpoints on database and Arrow tables --------------------------------
#
# A lazy table (dbplyr, e.g. DuckDB) is checked where it lives: the violation
# set is built as a query, and only its size and the preview rows are
# fetched into R. Arrow tables and datasets go
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
# Ungrouped first: select() on grouped data adds the grouping columns, and
# a key or an id would then hold columns that were never asked for.
select_names <- function(data, ...) {
  colnames(dplyr::select(dplyr::ungroup(data), ...))
}

remote_nrow <- function(x) {
  n <- dplyr::pull(dplyr::summarise(dplyr::ungroup(x), .inshape_n = dplyr::n()))
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
  diagnostic <- diagnostic_name(tbl, "dupid")
  dups <- tbl |>
    dplyr::group_by(!!!rlang::syms(cols)) |>
    dplyr::filter(dplyr::n() > 1L) |>
    dplyr::ungroup()
  dups |>
    dplyr::mutate(!!diagnostic := !!sql_dense_rank(dups, cols)) |>
    sort_by(list(rlang::sym(diagnostic)))
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
  per <- tibble::tibble(!!time_col := periods, .inshape_pos = seq_along(periods))
  per <- dbplyr::copy_inline(dbplyr::remote_con(tbl), per)
  obs <- dplyr::inner_join(dplyr::distinct(obs), per, by = time_col)

  units <- obs |>
    dplyr::group_by(!!!rlang::syms(ids)) |>
    dplyr::summarise(.inshape_n  = dplyr::n(),
                     .inshape_lo = min(.data$.inshape_pos, na.rm = TRUE),
                     .inshape_hi = max(.data$.inshape_pos, na.rm = TRUE),
                     .groups = "drop")
  if (!gaps_only) {
    units <- dplyr::mutate(units, .inshape_lo = 1L, .inshape_hi = !!length(periods))
  }

  units |>
    dplyr::filter(.data$.inshape_n < .data$.inshape_hi - .data$.inshape_lo + 1L) |>
    dplyr::cross_join(per) |>
    dplyr::filter(.data$.inshape_pos >= .data$.inshape_lo, .data$.inshape_pos <= .data$.inshape_hi) |>
    dplyr::select(dplyr::all_of(c(ids, time_col))) |>
    dplyr::anti_join(dplyr::select(obs, dplyr::all_of(c(ids, time_col))),
                     by = c(ids, time_col), na_matches = "na") |>
    sort_by(na_first(c(ids, time_col)))
}

# Overlapping spells, as find_overlaps() but with window functions: per
# unit, ordered by start, a spell opens a new group unless it starts on or
# before the latest end of the earlier spells, or an earlier spell is open.
remote_overlaps <- function(tbl, ids, start_col, end_col) {
  diagnostic <- diagnostic_name(tbl, "overlap_id")
  original_start <- start_col
  original_end <- end_col
  internal <- c(".inshape_prev_end", ".inshape_prev_open", ".inshape_new", ".inshape_grp")
  collisions <- intersect(colnames(tbl), internal)
  saved <- stats::setNames(vapply(collisions, function(nm) diagnostic_name(tbl, nm), character(1)), collisions)
  if (length(collisions)) {
    tbl <- dplyr::rename(tbl, !!!stats::setNames(rlang::syms(collisions), saved))
    ids <- vapply(ids, function(nm) if (nm %in% collisions) saved[[nm]] else nm, character(1))
    if (start_col %in% collisions) start_col <- saved[[start_col]]
    if (end_col %in% collisions) end_col <- saved[[end_col]]
  }
  start <- rlang::sym(start_col)
  end   <- rlang::sym(end_col)

  spells <- tbl |>
    dplyr::filter(!is.na(!!start)) |>
    dplyr::group_by(!!!rlang::syms(ids)) |>
    dbplyr::window_order(!!start, !!end) |>
    dbplyr::window_frame(-Inf, -1) |>
    dplyr::mutate(
      .inshape_prev_end  = max(!!end, na.rm = TRUE),
      .inshape_prev_open = max(dplyr::if_else(is.na(!!end), 1L, 0L), na.rm = TRUE)
    ) |>
    dplyr::mutate(
      .inshape_new = dplyr::if_else(
        dplyr::coalesce(.data$.inshape_prev_open, 0L) == 1L, 0L,
        dplyr::if_else(is.na(.data$.inshape_prev_end) | !!start > .data$.inshape_prev_end, 1L, 0L)
      )
    ) |>
    dplyr::mutate(.inshape_grp = cumsum(.data$.inshape_new)) |>
    # the frame would otherwise carry into n() below
    dbplyr::window_frame(-Inf, Inf) |>
    dplyr::group_by(!!!rlang::syms(c(ids, ".inshape_grp"))) |>
    dplyr::filter(dplyr::n() > 1L) |>
    dplyr::ungroup()

  out <- spells |>
    dplyr::mutate(!!diagnostic := !!sql_dense_rank(spells, c(ids, ".inshape_grp"))) |>
    dplyr::select(!dplyr::all_of(internal))
  if (length(collisions)) {
    out <- dplyr::rename(out, !!!stats::setNames(rlang::syms(saved), collisions))
  }
  sort_by(out, rlang::syms(c(diagnostic, original_start, original_end)))
}

# Spells starting after a gap, as find_spell_gaps(): the same window as
# remote_overlaps(), the latest end among the unit's earlier spells, and a
# spell is after a gap when none of those is open and it starts more than
# max_gap + 1 after that end. The helper columns get names the table does
# not have.
remote_spell_gaps <- function(tbl, ids, start_col, end_col, max_gap) {
  diagnostic <- diagnostic_name(tbl, "gap")
  prev_end   <- diagnostic_name(tbl, ".inshape_prev_end")
  prev_open  <- diagnostic_name(tbl, ".inshape_prev_open")
  start <- rlang::sym(start_col)
  end   <- rlang::sym(end_col)

  tbl |>
    dplyr::filter(!is.na(!!start), is.na(!!end) | !!end >= !!start) |>
    dplyr::group_by(!!!rlang::syms(ids)) |>
    dbplyr::window_order(!!start, !!end) |>
    dbplyr::window_frame(-Inf, -1) |>
    dplyr::mutate(
      !!prev_end  := max(!!end, na.rm = TRUE),
      !!prev_open := max(dplyr::if_else(is.na(!!end), 1L, 0L), na.rm = TRUE)
    ) |>
    dplyr::ungroup() |>
    # the order and the frame are for the window above only
    dbplyr::window_order() |>
    dbplyr::window_frame(-Inf, Inf) |>
    dplyr::filter(dplyr::coalesce(.data[[prev_open]], 0L) == 0L,
                  !!start > .data[[prev_end]] + !!(max_gap + 1L)) |>
    dplyr::mutate(!!diagnostic := as.integer(!!start - .data[[prev_end]] - 1L)) |>
    dplyr::select(!dplyr::all_of(c(prev_end, prev_open))) |>
    dplyr::relocate(dplyr::all_of(diagnostic)) |>
    sort_by(c(na_first(ids), list(start)))
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
    dplyr::summarise(.inshape_bad = !!Reduce(function(a, b) rlang::expr(!!a | !!b), tests),
                     .groups = "drop") |>
    dplyr::filter(.data$.inshape_bad) |>
    dplyr::select(dplyr::all_of(ids))
  tbl |>
    dplyr::semi_join(units, by = ids, na_matches = "na") |>
    sort_by(na_first(ids))
}

# Rows outside their bounds, as find_outside() in memory. A comparison with
# NULL is NULL, which WHERE drops, so missing bounds are open without a
# test of their own. A date compared with a year counts by its year.
remote_outside <- function(tbl, time_col, from_col, to_col) {
  diagnostic <- diagnostic_name(tbl, "outside")
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
    dplyr::filter(!!test) |>
    dplyr::mutate(!!diagnostic := !!label) |>
    dplyr::relocate(dplyr::all_of(diagnostic)) |>
    sort_by(c(list(rlang::sym(diagnostic)), na_first(time_col)))
}

# The finders return their query unsorted, since a sorted query that is
# counted or summarised makes dbplyr warn, and attach the sort order for
# report_check() to apply when rows are fetched.
sort_by <- function(query, order) structure(query, inshape_order = order)

# Sort keys putting NULL first, as data.table sorts NA, for arrange(). The
# CASE form works on every backend; NULLS FIRST does not (SQL Server).
na_first <- function(cols) {
  unlist(lapply(rlang::syms(cols), function(col) {
    list(rlang::expr(dplyr::if_else(is.na(!!col), 0L, 1L)), col)
  }), recursive = FALSE)
}

# Rows with NULL in any of `cols`, as find_incomplete(), with the names of
# the NULL columns joined by CONCAT_WS(), which skips the NULL of a column
# that has a value.
remote_incomplete <- function(tbl, cols, diagnostic) {
  con <- dbplyr::remote_con(tbl)
  any_null <- Reduce(function(a, b) rlang::expr(!!a | !!b),
                     lapply(rlang::syms(cols), function(col) rlang::expr(is.na(!!col))))
  names_sql <- paste0("CASE WHEN ", DBI::dbQuoteIdentifier(con, cols), " IS NULL THEN ",
                      DBI::dbQuoteString(con, cols), " END", collapse = ", ")
  tbl |>
    dplyr::filter(!!any_null) |>
    dplyr::mutate(!!diagnostic := !!dbplyr::sql(paste0("CONCAT_WS(', ', ", names_sql, ")"))) |>
    dplyr::relocate(dplyr::all_of(diagnostic)) |>
    sort_by(c(list(rlang::sym(diagnostic)), na_first(cols)))
}

# A database casts a number to a boolean without complaint, so a rule such
# as `amount * 2` would count every row. The types are read from a query
# that fetches no rows, which keeps the check as strict as on a data frame.
#
# `rules` are named with the column names to use in the query, `labels` are
# what the user called them. A grouped table keeps its grouping columns in
# the result, so the rules are picked out by name.
check_remote_logical <- function(tbl, rules, labels, call, what = "Rule") {
  probe <- tryCatch(
    dplyr::collect(utils::head(dplyr::transmute(tbl, !!!rules), 0)),
    error = function(e) {
      cli::cli_abort("The {tolower(what)}s could not be evaluated in the database.",
                     parent = e, call = call)
    }
  )
  probe <- probe[names(rules)]
  bad <- which(!vapply(probe, is.logical, logical(1)))
  if (length(bad) > 0) {
    i <- bad[1]
    cli::cli_abort(
      "{what} {.val {labels[[i]]}} must give a logical vector, not {.cls {class(probe[[i]])}}.",
      call = call
    )
  }
}
