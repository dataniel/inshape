# Assert that a panel is balanced, or has no gaps

A checkpoint for register panels: every unit (person, company,
workplace) must be observed in every period. Missing unit-periods are
the violation set, so a failure lists exactly which units lack which
periods. Returns `data`, so it can sit in the middle of a pipeline.

## Usage

``` r
ensure_balanced(
  data,
  id,
  time,
  periods = NULL,
  gaps_only = FALSE,
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

  If `FALSE` (default), every unit must be observed in every period. If
  `TRUE`, only periods between a unit's first and last observation are
  required.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when unit-periods are missing and no `abort_msg` is set.
  Defaults to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

Register populations are rarely fully balanced: people are born, die and
migrate, and firms open and close. `gaps_only = TRUE` relaxes the rule
to what usually *should* hold: a unit may enter late and leave early,
but once present it must not skip a period between its first and last. A
person present in 2019 and 2021 but missing in 2020 is then a gap; a
person first seen in 2021 is not.

### What counts as a period

By default the expected periods are those observed anywhere in the data.
A period missing for *every* unit (e.g. a year that was never loaded) is
therefore invisible. Pass the periods you expect, e.g.
`periods = 2015:2024`, to catch that too. Observations outside `periods`
are ignored, as are rows with a missing period.

Duplicated unit-periods do not make a panel unbalanced, but they are
usually an error of their own: check them with
[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md)`(data, id, time)`.

The check scales to full-population registers: the unit-period grid is
only built for units that actually lack a period.

## See also

[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md)
for duplicated unit-periods,
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md)
for spell data,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md)
for messages and personal data.

## Examples

``` r
panel <- data.frame(
  cpr  = c("a", "a", "a", "b", "b", "c"),
  year = c(2020, 2021, 2022, 2020, 2022, 2022)
)

# Not balanced: b lacks 2021, c lacks 2020 and 2021
ensure_balanced(panel, cpr, year)
#> Warning: Panel is not balanced: missing cpr-year combinations
#> ℹ 3 rows found:
#>     cpr    year
#>     <chr> <dbl>
#>   1 b      2021
#>   2 c      2020
#>   3 c      2021

# Only gaps: b lacks 2021; c simply entered in 2022
ensure_balanced(panel, cpr, year, gaps_only = TRUE)
#> Warning: Gaps in panel: missing cpr-year combinations
#> ℹ 1 row found:
#>     cpr    year
#>     <chr> <dbl>
#>   1 b      2021

# A year missing for everyone is only found with explicit periods
ensure_balanced(panel, cpr, year, periods = 2019:2022, gaps_only = TRUE)
#> Warning: Gaps in panel: missing cpr-year combinations
#> ℹ 1 row found:
#>     cpr    year
#>     <chr> <int>
#>   1 b      2021
```
