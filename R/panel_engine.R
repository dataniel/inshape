# The panel engine, shared by ensure_balanced() and describe_panel() so
# both count the same thing.
#
# Step 1, panel_index(): units get dense integer ids without sorting the
# id columns (see group_ids()), periods their position in `periods`. Rows
# with a missing period, or one outside `periods`, get position NA. The
# vectors keep the length of `data`, so no rows are copied.
#
# Step 2, panel_cells(): the observed unit-periods, summarised per unit.
# Normally as a bit matrix, one bit per unit and period, set in a single
# compiled pass (src/panel.c); everything per unit is then read from the
# bits. When the matrix would be much larger than the data itself, e.g.
# daily periods over many years, the cells are sorted instead, and the
# participation patterns are left out: they would be as long as the panel
# and nearly all different.

panel_index <- function(data, ids, time_col, periods) {
  # The time column goes through the engine once; its few distinct values
  # are then matched to the periods, and the positions spread back to rows
  time  <- data[[time_col]]
  code  <- dense_codes(time)
  value <- time[first_row_by(code, attr(code, "n"))]
  periods <- if (is.null(periods)) value[!is.na(value)] else unique(periods)
  periods <- sort(periods)
  unit <- group_ids(data, ids)
  list(unit = as.integer(unit), n_units = attr(unit, "n"),
       pos = match(value, periods)[code], periods = periods)
}

# Whether the bit matrix is cheap: at most 128 MB, or no larger than the
# position vector it is built from
panel_fits_bits <- function(n_units, n_per, n_rows) {
  bytes <- n_units * ((n_per + 63) %/% 64) * 8
  bytes <= max(2^27, 8 * n_rows)
}

# Per unit (1..n_units): n_seen, lo, hi (NA when unseen), runs, pattern
# (0 when unseen) and n_patterns (NA without patterns); dup_rows, the rows
# repeating a unit-period; and two functions, bits_of(u) for the observed
# periods of one unit and missing(units, lo, hi) for the unobserved
# positions between lo and hi of several units.
panel_cells <- function(ix) {
  n_per <- length(ix$periods)
  if (panel_fits_bits(ix$n_units, n_per, length(ix$pos))) {
    sc <- .Call(C_inshape_panel_scan, ix$unit, ix$pos,
                as.integer(ix$n_units), as.integer(n_per), inshape_threads())
    bytes <- ((n_per + 63L) %/% 64L) * 8L
    sc$bits_of <- function(u) {
      raw <- sc$bits[(u - 1) * bytes + seq_len(bytes)]
      as.logical(rawToBits(raw))[seq_len(n_per)]
    }
    sc$missing <- function(units, lo, hi) {
      .Call(C_inshape_panel_missing, sc$bits, as.integer(n_per),
            as.integer(units), as.integer(lo), as.integer(hi))
    }
    return(sc)
  }
  panel_cells_sorted(ix, n_per)
}

# The same summary by sorting the unit-period numbers once
panel_cells_sorted <- function(ix, n_per) {
  rows <- which(!is.na(ix$pos))
  pair <- (ix$unit[rows] - 1) * n_per + ix$pos[rows]
  dup  <- duplicated(pair)
  pair <- sort(pair[!dup], method = "radix")
  u <- as.integer((pair - 1) %/% n_per) + 1L
  p <- as.integer((pair - 1) %% n_per) + 1L
  n <- length(u)
  new_unit <- c(TRUE, u[-1] != u[-n])[seq_len(n)]
  new_run  <- new_unit | c(TRUE, p[-1] != p[-n] + 1L)[seq_len(n)]

  n_seen <- tabulate(u, ix$n_units)
  list(
    n_seen     = n_seen,
    lo         = min_by(p, u, ix$n_units),
    hi         = max_by(p, u, ix$n_units),
    runs       = tabulate(u[new_run], ix$n_units),
    pattern    = integer(ix$n_units),
    n_patterns = NA_integer_,
    dup_rows   = rows[dup],
    bits_of    = function(unit) seq_len(n_per) %in% p[u == unit],
    missing    = function(units, lo, hi) {
      span <- hi - lo + 1L
      want_unit <- rep(units, times = span)
      want_pos  <- sequence(span, from = lo)
      gone <- !((want_unit - 1) * n_per + want_pos) %in% pair
      list(want_unit[gone], want_pos[gone])
    }
  )
}
