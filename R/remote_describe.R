# describe_*() on database and Arrow tables ------------------------------
#
# Each summary is computed in the database with grouped counts, and only
# the small tables of counts are fetched: a register too large for memory
# can be described where it lives. The results have the shape of the
# in-memory summaries, and the tests hold the two to the same numbers. SQL
# skips NULL in COUNT(DISTINCT) and MIN/MAX, so a missing value is counted
# on its own where the in-memory version counts it as a value.

fetch <- function(query) tibble::as_tibble(dplyr::collect(query))

# One row of sums, as plain numbers
fetch_sums <- function(query) {
  vapply(fetch(query), function(v) as.numeric(v[1]) %||% 0, numeric(1))
}

int_or_na <- function(x) {
  x <- as.numeric(x)
  x[is.na(x)] <- 0
  as.integer(x)
}

flag <- function(cond) rlang::expr(dplyr::if_else(!!cond, 1L, 0L))

# COUNT(DISTINCT col), which skips NULL; dbplyr's n_distinct() may count
# NULL as a value of its own
count_distinct <- function(tbl, col) {
  dbplyr::sql(paste0("COUNT(DISTINCT ", DBI::dbQuoteIdentifier(dbplyr::remote_con(tbl), col), ")"))
}

# A column as text, numbers written as R writes them: a whole number
# without decimals, so 1 is "1" in the database as in R, not "1.0"
as_text_sql <- function(tbl, col, numeric) {
  q <- DBI::dbQuoteIdentifier(dbplyr::remote_con(tbl), col)
  if (!numeric) return(dbplyr::sql(paste0("CAST(", q, " AS VARCHAR)")))
  dbplyr::sql(paste0("CASE WHEN ", q, " = ROUND(", q, ") THEN CAST(CAST(", q,
                     " AS BIGINT) AS VARCHAR) ELSE CAST(", q, " AS VARCHAR) END"))
}

# The periods of a period column and an inline table of their positions
remote_periods <- function(tbl, time_col, periods) {
  time <- rlang::sym(time_col)
  if (is.null(periods)) {
    periods <- dplyr::pull(dplyr::distinct(dplyr::filter(tbl, !is.na(!!time)), !!time))
  }
  periods <- sort(unique(periods))
  per <- tibble::tibble(!!time_col := periods, .inshape_pos = seq_along(periods))
  list(periods = periods, table = dbplyr::copy_inline(dbplyr::remote_con(tbl), per))
}

# Counts per value of one column of a lazy table, as two vectors
count_by <- function(query, col) {
  counts <- fetch(dplyr::count(query, .data[[col]], name = ".inshape_count"))
  counts <- counts[!is.na(counts[[col]]), ]
  counts <- counts[order(counts[[col]]), ]
  list(value = counts[[col]], n = int_or_na(counts$.inshape_count))
}


# describe_key() ----------------------------------------------------------

remote_describe_key <- function(tbl, key) {
  keys <- rlang::syms(key)
  per_key <- dplyr::count(tbl, !!!keys, name = ".inshape_n")
  sums <- fetch_sums(dplyr::summarise(per_key,
    n_keys     = dplyr::n(),
    n_dup_keys = sum(!!flag(rlang::expr(.data$.inshape_n > 1L)), na.rm = TRUE),
    n_dup_rows = sum(dplyr::if_else(.data$.inshape_n > 1L, .data$.inshape_n, 0), na.rm = TRUE)
  ))
  by_copies <- count_by(dplyr::filter(per_key, .data$.inshape_n > 1L), ".inshape_n")

  # Per duplicated key and column: the distinct values, a missing value
  # counting as one of them
  other <- setdiff(colnames(tbl), key)
  dups <- dplyr::semi_join(tbl, dplyr::filter(per_key, .data$.inshape_n > 1L),
                           by = key, na_matches = "na")
  differs <- lapply(other, function(col) {
    x <- rlang::sym(col)
    flag(rlang::expr(!!count_distinct(tbl, col) + max(!!flag(rlang::expr(is.na(!!x))), na.rm = TRUE) > 1L))
  })
  names(differs) <- paste0(".inshape_d", seq_along(other))
  n_differ <- rep(0, length(other))
  n_exact <- sums[["n_dup_keys"]]
  if (length(other) && sums[["n_dup_keys"]] > 0) {
    per_dup <- dplyr::summarise(dplyr::group_by(dups, !!!keys), !!!differs, .groups = "drop")
    any_diff <- Reduce(function(a, b) rlang::expr(!!a + !!b), rlang::syms(names(differs)))
    totals <- fetch_sums(dplyr::summarise(per_dup,
      !!!lapply(rlang::syms(names(differs)), function(d) rlang::expr(sum(!!d, na.rm = TRUE))),
      .inshape_exact = sum(!!flag(rlang::expr(!!any_diff == 0L)), na.rm = TRUE)
    ))
    n_differ <- totals[seq_along(other)]
    n_exact <- totals[[".inshape_exact"]]
  }
  ord <- order(-n_differ, seq_along(other))
  ord <- ord[n_differ[ord] > 0]

  missing <- fetch_sums(dplyr::summarise(tbl,
    .inshape_rows = dplyr::n(),
    !!!lapply(keys, function(k) rlang::expr(sum(!!flag(rlang::expr(is.na(!!k))), na.rm = TRUE)))
  ))

  structure(list(
    key        = key,
    n_rows     = int_or_na(missing[[1]]),
    n_keys     = int_or_na(sums[["n_keys"]]),
    n_dup_keys = int_or_na(sums[["n_dup_keys"]]),
    n_dup_rows = int_or_na(sums[["n_dup_rows"]]),
    n_exact    = int_or_na(n_exact),
    copies     = tibble::tibble(copies = int_or_na(by_copies$value), keys = by_copies$n),
    conflicts  = tibble::tibble(column = other[ord], keys = int_or_na(n_differ[ord])),
    missing    = tibble::tibble(column = key, rows = int_or_na(missing[-1]))
  ), class = "inshape_key")
}


# describe_panel() and describe_codes(): unit-periods --------------------

# Per unit (the `ids` columns): observed periods, first, last, runs of
# presence and, for up to 52 periods, the periods as a bit pattern, from
# the distinct unit-periods
remote_units <- function(cells, ids, n_per) {
  pos <- rlang::sym(".inshape_pos")
  runs <- cells |>
    dplyr::group_by(!!!rlang::syms(ids)) |>
    dbplyr::window_order(!!pos) |>
    dplyr::mutate(.inshape_new = dplyr::if_else(
      is.na(dplyr::lag(!!pos)) | dplyr::lag(!!pos) != !!pos - 1L, 1L, 0L))
  summary <- rlang::exprs(
    .inshape_seen = dplyr::n(),
    .inshape_lo   = min(!!pos, na.rm = TRUE),
    .inshape_hi   = max(!!pos, na.rm = TRUE),
    .inshape_runs = sum(.data$.inshape_new, na.rm = TRUE)
  )
  if (n_per <= 52) summary$.inshape_pattern <- rlang::expr(sum(2^(!!pos - 1L), na.rm = TRUE))
  dplyr::summarise(runs, !!!summary, .groups = "drop")
}

remote_describe_panel <- function(tbl, ids, time_col, periods, keep) {
  time <- rlang::sym(time_col)
  pr <- remote_periods(tbl, time_col, periods)
  periods <- pr$periods
  n_per <- length(periods)

  obs <- dplyr::inner_join(dplyr::select(tbl, dplyr::all_of(c(ids, time_col))),
                           pr$table, by = time_col)
  cells <- dplyr::count(obs, !!!rlang::syms(ids), .data$.inshape_pos, name = ".inshape_n")
  units <- remote_units(cells, ids, n_per)

  any_na_id <- Reduce(function(a, b) rlang::expr(!!a | !!b),
                      lapply(rlang::syms(ids), function(i) rlang::expr(is.na(!!i))))
  rows <- fetch_sums(dplyr::summarise(tbl,
    n_rows = dplyr::n(),
    n_missing_id = sum(!!flag(any_na_id), na.rm = TRUE),
    n_missing_time = sum(!!flag(rlang::expr(is.na(!!time))), na.rm = TRUE)
  ))
  n_in <- fetch_sums(dplyr::summarise(cells,
    n_in = sum(.data$.inshape_n, na.rm = TRUE),
    n_dup_cells = sum(!!flag(rlang::expr(.data$.inshape_n > 1L)), na.rm = TRUE),
    n_dup_rows = sum(.data$.inshape_n - 1L, na.rm = TRUE)
  ))
  per_unit <- fetch_sums(dplyr::summarise(units,
    n_units = dplyr::n(),
    n_complete = sum(!!flag(rlang::expr(.data$.inshape_seen == !!n_per)), na.rm = TRUE),
    n_with_gaps = sum(!!flag(rlang::expr(.data$.inshape_hi - .data$.inshape_lo + 1L > .data$.inshape_seen)), na.rm = TRUE),
    n_gap_cells = sum(.data$.inshape_hi - .data$.inshape_lo + 1L - .data$.inshape_seen, na.rm = TRUE)
  ))

  spread <- function(counts) {
    out <- integer(n_per)
    out[counts$value] <- counts$n
    out
  }
  entries <- spread(count_by(units, ".inshape_lo"))
  exits   <- spread(count_by(units, ".inshape_hi"))
  seen    <- spread(count_by(cells, ".inshape_pos"))
  spanning <- cumsum(entries) - (cumsum(exits) - exits)
  by_runs <- count_by(units, ".inshape_runs")

  patterns <- tibble::tibble(pattern = character(), units = integer(), share = numeric())
  if (n_per <= 52 && keep > 0 && per_unit[["n_units"]] > 0) {
    top <- fetch(utils::head(dplyr::arrange(
      dplyr::count(units, .data$.inshape_pattern, name = ".inshape_n"),
      dplyr::desc(.data$.inshape_n), .data$.inshape_pattern), keep))
    bits <- lapply(as.numeric(top$.inshape_pattern), function(p) {
      floor(p / 2^(seq_len(n_per) - 1)) %% 2 == 1
    })
    patterns <- tibble::tibble(
      pattern = vapply(bits, function(b) paste(ifelse(b, "1", "."), collapse = ""), character(1)),
      units   = int_or_na(top$.inshape_n),
      share   = as.numeric(top$.inshape_n) / per_unit[["n_units"]]
    )
  }

  structure(list(
    ids            = ids,
    time           = time_col,
    periods        = periods,
    n_rows         = int_or_na(rows[["n_rows"]]),
    n_units        = int_or_na(per_unit[["n_units"]]),
    n_complete     = int_or_na(per_unit[["n_complete"]]),
    n_with_gaps    = int_or_na(per_unit[["n_with_gaps"]]),
    n_gap_cells    = int_or_na(per_unit[["n_gap_cells"]]),
    n_dup_cells    = int_or_na(n_in[["n_dup_cells"]]),
    n_dup_rows     = int_or_na(n_in[["n_dup_rows"]]),
    n_missing_id   = int_or_na(rows[["n_missing_id"]]),
    n_missing_time = int_or_na(rows[["n_missing_time"]]),
    n_outside      = int_or_na(rows[["n_rows"]] - rows[["n_missing_time"]] - n_in[["n_in"]]),
    by_period      = tibble::tibble(
      period  = periods,
      units   = seen,
      entries = replace(entries, 1, NA),
      exits   = replace(exits, n_per, NA),
      gaps    = spanning - seen
    ),
    runs           = tibble::tibble(runs = int_or_na(by_runs$value), units = by_runs$n),
    patterns       = patterns
  ), class = "inshape_panel")
}

remote_describe_codes <- function(tbl, code_col, time_col, periods) {
  code <- rlang::sym(code_col)
  time <- rlang::sym(time_col)
  pr <- remote_periods(tbl, time_col, periods)
  periods <- pr$periods
  n_per <- length(periods)

  obs <- dplyr::inner_join(dplyr::select(tbl, dplyr::all_of(c(code_col, time_col))),
                           pr$table, by = time_col)
  coded <- dplyr::filter(obs, !is.na(!!code))
  cells <- dplyr::count(coded, !!code, .data$.inshape_pos, name = ".inshape_n")
  per_code <- dplyr::summarise(dplyr::group_by(cells, !!code),
    .inshape_rows = sum(.data$.inshape_n, na.rm = TRUE),
    .inshape_seen = dplyr::n(),
    .inshape_lo   = min(.data$.inshape_pos, na.rm = TRUE),
    .inshape_hi   = max(.data$.inshape_pos, na.rm = TRUE),
    .groups = "drop")
  codes <- fetch(per_code)
  codes <- codes[order(codes[[code_col]], method = "radix"), ]
  lo <- int_or_na(codes$.inshape_lo)
  hi <- int_or_na(codes$.inshape_hi)
  seen <- int_or_na(codes$.inshape_seen)

  rows <- fetch_sums(dplyr::summarise(tbl,
    n_rows = dplyr::n(),
    n_missing = sum(!!flag(rlang::expr(is.na(!!code))), na.rm = TRUE),
    n_missing_time = sum(!!flag(rlang::expr(is.na(!!time))), na.rm = TRUE)
  ))
  n_in <- fetch_sums(dplyr::summarise(obs, n = dplyr::n()))[[1]]
  spread <- function(counts) {
    out <- integer(n_per)
    out[counts$value] <- counts$n
    out
  }

  structure(list(
    code           = code_col,
    time           = time_col,
    periods        = periods,
    n_rows         = int_or_na(rows[["n_rows"]]),
    n_codes        = nrow(codes),
    n_every_period = sum(seen == n_per),
    n_with_gaps    = sum(hi - lo + 1L > seen),
    n_missing      = int_or_na(rows[["n_missing"]]),
    n_missing_time = int_or_na(rows[["n_missing_time"]]),
    n_outside      = int_or_na(rows[["n_rows"]] - rows[["n_missing_time"]] - n_in),
    codes          = tibble::tibble(
      code    = codes[[code_col]],
      first   = periods[lo],
      last    = periods[hi],
      periods = seen,
      gaps    = hi - lo + 1L - seen,
      rows    = int_or_na(codes$.inshape_rows)
    ),
    by_period      = tibble::tibble(
      period  = periods,
      codes   = spread(count_by(cells, ".inshape_pos")),
      new     = replace(tabulate(lo, n_per), 1, NA),
      gone    = replace(tabulate(hi + 1L, n_per), 1, NA),
      missing = spread(count_by(dplyr::filter(obs, is.na(!!code)), ".inshape_pos"))
    )
  ), class = "inshape_codes")
}


# describe_varying() -------------------------------------------------------

remote_describe_varying <- function(tbl, ids, cols) {
  stats <- unlist(lapply(seq_along(cols), function(k) {
    col <- rlang::sym(cols[k])
    stats::setNames(list(
      count_distinct(tbl, cols[k]),
      rlang::expr(sum(!!flag(rlang::expr(is.na(!!col))), na.rm = TRUE))
    ), paste0(c(".inshape_v", ".inshape_m"), k))
  }), recursive = FALSE)
  per_unit <- dplyr::summarise(dplyr::group_by(tbl, !!!rlang::syms(ids)), !!!stats,
                               .groups = "drop")
  sums <- unlist(lapply(seq_along(cols), function(k) {
    v <- rlang::sym(paste0(".inshape_v", k))
    m <- rlang::sym(paste0(".inshape_m", k))
    stats::setNames(list(
      rlang::expr(sum(!!flag(rlang::expr(!!v > 1L)), na.rm = TRUE)),
      rlang::expr(sum(!!flag(rlang::expr(!!v >= 1L & !!m > 0L)), na.rm = TRUE)),
      rlang::expr(sum(!!flag(rlang::expr(!!v == 0L)), na.rm = TRUE))
    ), paste0(c(".inshape_var", ".inshape_part", ".inshape_all"), k))
  }), recursive = FALSE)
  totals <- fetch_sums(dplyr::summarise(per_unit, .inshape_units = dplyr::n(), !!!sums))
  n_units <- totals[[".inshape_units"]]
  at <- function(prefix) {
    int_or_na(totals[paste0(prefix, seq_along(cols))])
  }
  varying <- at(".inshape_var")
  all_missing <- at(".inshape_all")
  with_value <- n_units - all_missing
  columns <- tibble::tibble(
    column         = cols,
    varying        = varying,
    share          = ifelse(with_value == 0, NA_real_, varying / with_value),
    partly_missing = at(".inshape_part"),
    all_missing    = all_missing
  )
  columns <- columns[order(columns$share, columns$column, na.last = TRUE), ]
  structure(list(ids = ids, n_units = int_or_na(n_units), columns = columns),
            class = "inshape_varying")
}


# describe_spells() --------------------------------------------------------

# The relation of each usable spell to the unit's earlier ones, as in
# src/spells.c, with window functions: the latest end among the earlier
# spells (a frame up to the row before) and the spell just before. An
# ongoing spell ends at a far date (or number), as it does in memory.
remote_describe_spells <- function(tbl, ids, start_col, end_col) {
  s <- rlang::sym(start_col)
  e <- rlang::sym(end_col)
  proto <- dplyr::collect(utils::head(dplyr::select(tbl, dplyr::all_of(c(start_col, end_col))), 0L))
  is_date <- inherits(proto[[start_col]], c("Date", "POSIXt"))
  far <- if (is_date) as.Date("9999-12-31") else .Machine$integer.max

  rows <- fetch_sums(dplyr::summarise(tbl,
    n_rows = dplyr::n(),
    n_missing_start = sum(!!flag(rlang::expr(is.na(!!s))), na.rm = TRUE),
    n_end_before_start = sum(!!flag(rlang::expr(!is.na(!!s) & !is.na(!!e) & !!e < !!s)), na.rm = TRUE)
  ))
  usable <- dplyr::filter(tbl, !is.na(!!s) & (is.na(!!e) | !!e >= !!s))
  usable <- dplyr::mutate(usable, .inshape_e = dplyr::coalesce(!!e, !!far),
                          .inshape_open = !!flag(rlang::expr(is.na(!!e))))
  rel <- usable |>
    dplyr::group_by(!!!rlang::syms(ids)) |>
    # desc() as a bare call, which dbplyr translates; a namespaced one fails
    dbplyr::window_order(!!s, !!rlang::call2("desc", rlang::sym(".inshape_e"))) |>
    dbplyr::window_frame(-Inf, -1) |>
    dplyr::mutate(.inshape_cover = max(.data$.inshape_e, na.rm = TRUE)) |>
    dbplyr::window_frame(-Inf, Inf) |>
    dplyr::mutate(.inshape_ps = dplyr::lag(!!s), .inshape_pe = dplyr::lag(.data$.inshape_e)) |>
    dplyr::ungroup() |>
    dplyr::mutate(.inshape_rel = dplyr::case_when(
      is.na(.data$.inshape_cover) ~ 0L,
      !!s == .data$.inshape_ps & .data$.inshape_e == .data$.inshape_pe ~ 6L,
      .data$.inshape_e <= .data$.inshape_cover ~ 5L,
      !!s < .data$.inshape_cover ~ 4L,
      !!s == .data$.inshape_cover ~ 3L,
      !!s == .data$.inshape_cover + 1L ~ 2L,
      TRUE ~ 1L
    ))
  rel <- dplyr::mutate(rel, .inshape_gap = dplyr::if_else(
    .data$.inshape_rel == 1L, !!s - .data$.inshape_cover - 1L, NA))

  relations <- count_by(rel, ".inshape_rel")
  counts <- integer(7)
  counts[relations$value + 1L] <- relations$n
  overlapping <- dplyr::distinct(dplyr::filter(rel, .data$.inshape_rel >= 3L), !!!rlang::syms(ids))
  closed <- dplyr::filter(usable, .data$.inshape_open == 0L)
  closed <- dplyr::mutate(closed, .inshape_len = !!e - !!s + 1L)
  spells <- fetch_sums(dplyr::summarise(usable,
    n_spells = dplyr::n(),
    n_ongoing = sum(.data$.inshape_open, na.rm = TRUE)
  ))
  n_single <- fetch_sums(dplyr::summarise(closed,
    n = sum(!!flag(rlang::expr(!!e == !!s)), na.rm = TRUE)))[[1]]

  per_unit <- count_by(dplyr::count(usable, !!!rlang::syms(ids), name = ".inshape_k"), ".inshape_k")
  year_of <- function(col) {
    if (is_date) dbplyr::sql(paste0("EXTRACT(YEAR FROM ",
                                    DBI::dbQuoteIdentifier(dbplyr::remote_con(tbl), col), ")"))
    else rlang::sym(col)
  }
  starts_by <- count_by(dplyr::mutate(usable, .inshape_y = !!year_of(start_col)), ".inshape_y")
  ends_by   <- count_by(dplyr::mutate(closed, .inshape_y = !!year_of(end_col)), ".inshape_y")
  starts_by$value <- int_or_na(starts_by$value)
  ends_by$value   <- int_or_na(ends_by$value)
  periods <- sort(unique(c(starts_by$value, ends_by$value)))

  structure(list(
    ids                 = ids,
    start               = start_col,
    end                 = end_col,
    unit_word           = if (is_date) "day" else "period",
    n_rows              = int_or_na(rows[["n_rows"]]),
    n_spells            = int_or_na(spells[["n_spells"]]),
    n_units             = sum(per_unit$n),
    n_missing_start     = int_or_na(rows[["n_missing_start"]]),
    n_end_before_start  = int_or_na(rows[["n_end_before_start"]]),
    n_ongoing           = int_or_na(spells[["n_ongoing"]]),
    n_single            = int_or_na(n_single),
    n_units_overlapping = int_or_na(fetch_sums(dplyr::summarise(overlapping, n = dplyr::n()))[[1]]),
    relations = tibble::tibble(
      relation = c("gap", "adjacent", "touching", "overlapping", "nested", "duplicate"),
      spells   = counts[-1]
    ),
    gaps      = summary_of_counts(count_by(rel, ".inshape_gap")),
    lengths   = summary_of_counts(count_by(closed, ".inshape_len")),
    spells_per_unit = tibble::tibble(spells = int_or_na(per_unit$value), units = per_unit$n),
    by_year   = tibble::tibble(
      year   = periods,
      starts = spread_counts(starts_by, periods),
      ends   = spread_counts(ends_by, periods)
    )
  ), class = "inshape_spells")
}


# describe_changes() --------------------------------------------------------

remote_changes <- function(old, new, ...) {
  if (!is_remote(old) || !is_remote(new)) {
    cli::cli_abort("{.arg old} and {.arg new} must both be data frames or both be database tables.",
                   call = rlang::caller_env(2))
  }
  key <- select_names(old, ...)
  if (length(key) == 0) cli::cli_abort("Select at least one key column.")
  missing_key <- setdiff(key, colnames(new))
  if (length(missing_key)) {
    cli::cli_abort("Key column{?s} {.var {missing_key}} {?is/are} not in {.arg new}.")
  }
  keys <- rlang::syms(key)
  for (side in list(list("old", old), list("new", new))) {
    n_dup <- fetch_sums(dplyr::summarise(dplyr::filter(
      dplyr::count(side[[2]], !!!keys, name = ".inshape_n"), .data$.inshape_n > 1L), n = dplyr::n()))[[1]]
    if (n_dup > 0) {
      cli::cli_abort(c("The key {.var {key}} is not unique in {.arg {side[[1]]}}.",
                       "i" = "See the duplicates with {.code describe_key({side[[1]]}, {toString(key)})}."))
    }
  }

  proto_old <- dplyr::collect(utils::head(old, 0L))
  proto_new <- dplyr::collect(utils::head(new, 0L))
  shared <- setdiff(intersect(colnames(old), colnames(new)), key)
  type_changed <- shared[!vapply(shared, function(col) {
    identical(class(proto_old[[col]]), class(proto_new[[col]]))
  }, logical(1))]
  as_text <- shared[vapply(shared, function(col) {
    a <- proto_old[[col]]
    b <- proto_new[[col]]
    !identical(class(a), class(b)) && !(is.numeric(a) && is.numeric(b))
  }, logical(1))]

  rename_side <- function(tbl, suffix) {
    cols <- stats::setNames(shared, paste0(shared, suffix))
    dplyr::select(tbl, dplyr::all_of(key), dplyr::all_of(cols))
  }
  kept <- dplyr::inner_join(rename_side(old, ".inshape_old"), rename_side(new, ".inshape_new"),
                            by = key, na_matches = "na")
  value <- function(col, suffix) {
    name <- paste0(col, suffix)
    if (!col %in% as_text) return(rlang::sym(name))
    proto <- if (suffix == ".inshape_old") proto_old else proto_new
    as_text_sql(kept, name, is.numeric(proto[[col]]))
  }
  conds <- lapply(shared, function(col) {
    a <- value(col, ".inshape_old")
    b <- value(col, ".inshape_new")
    list(changed = rlang::expr(!is.na(!!a) & !is.na(!!b) & !!a != !!b),
         went    = rlang::expr(!is.na(!!a) & is.na(!!b)),
         filled  = rlang::expr(is.na(!!a) & !is.na(!!b)))
  })
  any_col <- lapply(conds, function(cd) flag(rlang::expr(!!cd$changed | !!cd$went | !!cd$filled)))
  n_columns <- if (length(shared)) Reduce(function(a, b) rlang::expr(!!a + !!b), any_col) else 0L

  sums <- unlist(lapply(seq_along(shared), function(k) {
    stats::setNames(lapply(conds[[k]], function(cd) rlang::expr(sum(!!flag(cd), na.rm = TRUE))),
                    paste0(c(".inshape_c", ".inshape_w", ".inshape_f"), k))
  }), recursive = FALSE)
  totals <- fetch_sums(dplyr::summarise(dplyr::mutate(kept, .inshape_k = !!n_columns),
    .inshape_kept = dplyr::n(),
    .inshape_changed = sum(!!flag(rlang::expr(.data$.inshape_k > 0L)), na.rm = TRUE),
    !!!sums))
  n_kept <- totals[[".inshape_kept"]]
  at <- function(prefix) int_or_na(totals[paste0(prefix, seq_along(shared))])
  columns <- tibble::tibble(
    column = shared, changed = at(".inshape_c"), went_missing = at(".inshape_w"),
    filled_in = at(".inshape_f")
  )
  any_change <- columns$changed + columns$went_missing + columns$filled_in
  columns$share <- if (n_kept > 0) any_change / n_kept else rep(NA_real_, length(shared))
  columns <- columns[order(-any_change, columns$column), ]

  added   <- dplyr::select(dplyr::anti_join(new, old, by = key, na_matches = "na"), dplyr::all_of(key))
  removed <- dplyr::select(dplyr::anti_join(old, new, by = key, na_matches = "na"), dplyr::all_of(key))
  changed <- kept |>
    dplyr::mutate(n_columns = !!n_columns) |>
    dplyr::filter(.data$n_columns > 0L) |>
    dplyr::select(dplyr::all_of(c(key, "n_columns")))
  count_rows <- function(q) int_or_na(fetch_sums(dplyr::summarise(q, n = dplyr::n()))[[1]])

  structure(list(
    key             = key,
    n_old           = count_rows(old),
    n_new           = count_rows(new),
    n_kept          = int_or_na(n_kept),
    n_added         = count_rows(added),
    n_removed       = count_rows(removed),
    n_changed       = int_or_na(totals[[".inshape_changed"]]),
    columns_added   = setdiff(colnames(new), colnames(old)),
    columns_removed = setdiff(colnames(old), colnames(new)),
    type_changed    = type_changed,
    columns         = columns,
    added           = added,
    removed         = removed,
    changed         = changed
  ), class = "inshape_changes")
}


# ensure_codes() -------------------------------------------------------------

remote_not_in <- function(tbl, col, codes, na_ok) {
  x <- rlang::sym(col)
  query <- if (na_ok) {
    dplyr::filter(tbl, !is.na(!!x) & !(!!x %in% !!codes))
  } else {
    dplyr::filter(tbl, is.na(!!x) | !(!!x %in% !!codes))
  }
  sort_by(query, na_first(col))
}
