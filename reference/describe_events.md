# Describe events: how many per unit, per period and how far apart

Event data has one row per thing that happened, with a date: moves,
exams, payments, contacts. Several rows per unit and period are the
point, so the panel checks do not apply. `describe_events()` counts the
events and the units, the events per unit (one unit with 4,000 contacts
is usually an error of its own), the events per period (a month without
events is usually a broken extract), and the time between a unit's
consecutive events (a time of 0 between two of the same is often a
duplicate). It judges nothing.

## Usage

``` r
describe_events(data, id, time, event = NULL)
```

## Arguments

- data:

  A data frame or tibble, or a database or Arrow table: see *Database
  and Arrow tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- id:

  Column(s) identifying the unit (tidy-select), e.g. `cpr`.

- time:

  The date or period of each event (one column).

- event:

  The type of event (one column), or `NULL` (default).

## Value

An object of class `inshape_events`, printed as a summary. It is a list
with `ids`, `time`, `event`, the counts `n_events` and `n_units`, and
the tibbles `per_unit` (`events`, `units`: how many units have that many
events), `by_period` (`period`, `events`, `units`), `by_event` (`event`,
`events`, `units`, or `NULL`) and `between` (`n`, `min`, `median`,
`mean`, `max` of the time between a unit's consecutive events, in days
for dates).

## Details

Periods are years for a date column, and the values themselves for a
number such as a year or a month number.

## See also

[`ensure_sequence()`](https://dataniel.github.io/inshape/reference/ensure_sequence.md)
for the order of events,
[`ensure_counts()`](https://dataniel.github.io/inshape/reference/ensure_counts.md)
for at most one of a kind,
[`ensure_within()`](https://dataniel.github.io/inshape/reference/ensure_within.md)
for events outside a unit's lifetime.

## Examples

``` r
moves <- data.frame(
  cpr  = c("a", "a", "a", "b", "c", "c"),
  date = as.Date(c("2020-03-01", "2021-06-15", "2021-06-15",
                   "2022-01-10", "2020-08-01", "2023-02-01")),
  type = c("in", "out", "out", "in", "in", "out")
)
describe_events(moves, cpr, date, type)
#> ── Events: type by date per cpr ────────────────────────────────────────────────
#> 6 events, 3 units
#> 
#> • Events per unit: most 3, 1 unit with one
#> 
#> By event:
#>     event events units
#>   1 in         3     3
#>   2 out        3     2
#> 
#> Units by number of events:
#>     events units
#>   1      1     1
#>   2      2     1
#>   3      3     1
#> 
#> By period:
#>     period events units
#>   1   2020      2     2
#>   2   2021      2     1
#>   3   2022      1     1
#>   4   2023      1     1
#> 
#> Time between a unit's consecutive events, in days:
#>         n   min median  mean   max
#>   1     3     0    471  462.   914
```
