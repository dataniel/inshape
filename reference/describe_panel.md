# Describe the structure of a panel

Before deciding which rule a panel must meet, look at what it is: how
many units and periods, how many units are observed throughout, who
enters and leaves when, where the gaps are, and which participation
patterns are common. `describe_panel()` answers that in one pass and
judges nothing; turn what you learn into a rule with
[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
or
[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md).

## Usage

``` r
describe_panel(data, id, time, periods = NULL, patterns = 10)
```

## Arguments

- data:

  A data frame or tibble, or a database or Arrow table: see *Database
  tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- id:

  Column(s) identifying the unit (tidy-select), e.g. `cpr`.

- time:

  The period column (one column), e.g. `year`.

- periods:

  Expected periods. Defaults to those observed in `data`. Pass them,
  e.g. `2015:2024`, to see a period that is missing for everyone.

- patterns:

  Number of participation patterns to keep, most common first.

## Value

An object of class `inshape_panel`, printed as a summary. It is a list
with the counts (`n_rows`, `n_units`, `n_complete`, `n_with_gaps`,
`n_gap_cells`, `n_dup_cells`, `n_dup_rows`, `n_missing_id`,
`n_missing_time`, `n_outside`), the `periods`, and three tibbles:
`by_period` (`period`, `units`, `entries`, `exits`, `gaps`), `runs`
(units by number of separate runs of presence) and `patterns`
(`pattern`, `units`, `share`).

## Details

It is the panel summary of Stata's `xtdescribe`, made for population
registers: a sudden fall in the number of units in one period, a period
with no units at all, or many units with a single missing year are the
signs of a broken extract, and they are visible here at a glance.

### What is counted

A unit-period is counted once, however many rows it has; the extra rows
are reported as duplicates. Rows with a missing period, or a period
outside `periods`, are left out and counted. A missing id is a unit of
its own, as in
[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md),
and the rows are counted.

In `by_period`, `entries` are the units first observed in a period and
`exits` those last observed in it. Neither is known at the edges, where
a unit may have been present before the first or after the last period,
so `entries` is `NA` in the first period and `exits` in the last. `gaps`
counts the units absent in a period although they are observed both
before and after it.

A participation pattern has one character per period, `1` when the unit
is observed and `.` when not, as in `xtdescribe`: `11.11` is a unit
missing in the middle period of five.

## Why it is fast

The id columns are compressed to integer unit ids by one compiled hash
pass, without sorting them. The panel then becomes a bit matrix, one bit
per unit and period (6 million persons over 64 periods take 48 MB), set
in a single pass over the rows; a bit already set is a duplicate. First
and last period, counts, runs and patterns are read from the bits with
processor bit instructions, so nothing is sorted per row. When the bit
matrix would be much larger than the data, as for daily periods over
many years, the unit-periods are sorted instead and the patterns, as
long as the panel and nearly all different, are left out.

## See also

[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
to require a balanced panel or no gaps,
[`describe_key()`](https://dataniel.github.io/inshape/reference/describe_key.md)
for duplicated keys.

## Examples

``` r
panel <- data.frame(
  cpr  = c("a", "a", "a", "b", "b", "c", "d", "d", "d"),
  year = c(2020, 2021, 2022, 2020, 2022, 2022, 2020, 2021, 2022)
)
describe_panel(panel, cpr, year)
#> ── Panel: cpr by year ──────────────────────────────────────────────────────────
#> 9 rows, 4 units, 3 periods, 2020-2022
#> 
#> ⚠ With gaps: 1 unit (25.0%), 1 missing unit-period inside their span
#> ✔ No duplicated unit-periods
#> • Observed in every period: 2 units (50.0%)
#> 
#> By period:
#>     period units entries exits  gaps
#>   1   2020     3      NA     0     0
#>   2   2021     2       0     0     1
#>   3   2022     4       1    NA     0
#> 
#> Most common patterns:
#>     pattern units share
#>   1 111         2 50.0%
#>   2 1.1         1 25.0%
#>   3 ..1         1 25.0%

# The counts are there to use
p <- describe_panel(panel, cpr, year)
p$by_period
#> # A tibble: 3 × 5
#>   period units entries exits  gaps
#>    <dbl> <int>   <int> <int> <int>
#> 1   2020     3      NA     0     0
#> 2   2021     2       0     0     1
#> 3   2022     4       1    NA     0
```
