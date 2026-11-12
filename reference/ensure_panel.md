# Check a panel, spells or a lookup table in one call

The checks that register data of a common shape nearly always needs, run
together and reported in one overview: what passed, what failed with its
counts, and the call that gives the rows. Each returns `data`, so it can
sit in the middle of a pipeline.

## Usage

``` r
ensure_panel(
  data,
  id,
  time,
  periods = NULL,
  gaps_only = TRUE,
  success_msg = NULL,
  warn_msg = NULL,
  abort_msg = NULL
)

ensure_spells(
  data,
  id,
  start,
  end,
  no_gaps = FALSE,
  success_msg = NULL,
  warn_msg = NULL,
  abort_msg = NULL
)

ensure_lookup(
  data,
  reference,
  by,
  success_msg = NULL,
  warn_msg = NULL,
  abort_msg = NULL
)
```

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- id:

  Column(s) identifying the unit (tidy-select), e.g. `cpr` or
  `c(cvr, lbnr)`.

- time:

  The period column (one column), e.g. `year`. Any type that sorts, such
  as integer years or dates.

- periods:

  Expected periods. Defaults to the periods observed in `data`.

- gaps_only:

  If `TRUE` (default), a unit may enter late and leave early, but must
  not skip a period in between. If `FALSE`, every unit must be observed
  in every period.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when a check fails and no `abort_msg` is set. Defaults
  to a line naming the data and how many checks failed.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

- start, end:

  Columns with the first and last period of each spell.

- no_gaps:

  If `TRUE`, the spells must also cover each unit from its first start
  to its last end, see
  [`ensure_no_gaps()`](https://dataniel.github.io/inshape/reference/ensure_no_gaps.md).
  Default `FALSE`.

- reference:

  The lookup table, for `ensure_lookup()`.

- by:

  Key columns, as in
  [`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md):
  a character vector, optionally named to map names in `data` to names
  in `reference`.

## Value

`data` invisibly, unchanged.

## Details

- `ensure_panel()`, one row per unit and period: the key is complete
  ([`ensure_complete()`](https://dataniel.github.io/inshape/reference/ensure_complete.md)),
  unique
  ([`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md))
  and has no gaps
  ([`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)).

- `ensure_spells()`, a start and an end per spell: the unit is complete,
  the spells are valid
  ([`ensure_valid_spells()`](https://dataniel.github.io/inshape/reference/ensure_valid_spells.md))
  and do not overlap
  ([`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md)),
  and, with `no_gaps = TRUE`, leave no gaps
  ([`ensure_no_gaps()`](https://dataniel.github.io/inshape/reference/ensure_no_gaps.md)).

- `ensure_lookup()`, a table to join on: its key is unique, so the join
  does not multiply rows, and every key of `data` is in it
  ([`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md)).

All checks run, also after one has failed, so the overview shows every
problem at once. The exception is a check that assumes another: overlaps
and gaps mean nothing until the spells are valid, and are shown as not
checked until then.

The choices are fixed where a register nearly always needs the same: a
panel may have units that enter late and leave early
(`gaps_only = TRUE`, unlike
[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)),
and a spell without an end is ongoing. For other choices, run the single
checks; the overview names them.

A failure is one condition of class `inshape_failure` for the whole
overview, and carries no rows. To get the rows of one check, wrap that
check in
[`violations()`](https://dataniel.github.io/inshape/reference/violations.md),
as the overview shows.

## See also

[`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md),
[`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md)
and
[`describe_match()`](https://dataniel.github.io/inshape/reference/describe_match.md)
to look at the same data without a rule,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
panel <- data.frame(
  cpr  = c("a", "a", "a", "b", "b", "c"),
  year = c(2020, 2021, 2022, 2020, 2022, 2022)
)
# b lacks 2021
ensure_panel(panel, cpr, year)
#> Warning: Panel cpr by year: 1 of 3 checks failed
#> ✔ Complete: cpr, year
#> ✔ Unique on cpr, year
#> ✖ Gaps in panel: missing cpr-year combinations (1 row)
#>   Missing for 1 unit
#>   By year: 2021 (1)
#> ℹ For the rows: violations(ensure_balanced(panel, cpr, year, gaps_only = TRUE))

addresses <- data.frame(
  cpr   = c("a", "a", "b", "b"),
  start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-06-01")),
  end   = as.Date(c("2020-12-31", NA,           "2020-06-30", "2021-12-31"))
)
# b has two addresses in June 2020
ensure_spells(addresses, cpr, start, end)
#> Warning: Spells per cpr: 1 of 3 checks failed
#> ✔ Complete: cpr
#> ✔ Valid spells: start to end
#> ✖ Overlapping spells per cpr (2 rows in 1 group)
#>   In 1 unit
#> ℹ For the rows: violations(ensure_no_overlap(addresses, cpr, start, end))

codes <- data.frame(kom = c("955", "956", "956"), name = c("A", "B", "B"))
persons <- data.frame(cpr = c("a", "b"), kom = c("955", "957"))
# 956 is in the code list twice, and 957 not at all
ensure_lookup(persons, codes, by = "kom")
#> Warning: Lookup on kom: 2 of 2 checks failed
#> ✖ Duplicate keys in codes: kom (2 rows in 1 group)
#>   The copies are identical in every column
#> ✖ Keys missing from the reference: kom (1 row)
#> ℹ For the rows: violations(ensure_unique(codes, kom))
#> ℹ For the rows: violations(ensure_matched(persons, codes, by = "kom"))
```
