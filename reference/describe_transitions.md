# Describe the transitions between statuses over time

A status that follows a unit over time, such as education, labour market
attachment or civil status, can only change in some ways: a person who
has completed an education cannot later not have started it. The
transition table counts, for every pair of statuses, how many units go
from the one to the other between two observations. Impossible
transitions show as cells that should be empty, before any rule is
written; require one with
[`ensure_transitions()`](https://dataniel.github.io/inshape/reference/ensure_transitions.md).

## Usage

``` r
describe_transitions(data, id, time, status)
```

## Arguments

- data:

  A data frame or tibble, or a database or Arrow table: see *Database
  and Arrow tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- id:

  Column(s) identifying the unit (tidy-select), e.g. `cpr`.

- time:

  The period column, or the start of a spell (one column).

- status:

  The status column (one column).

## Value

An object of class `inshape_transitions`, printed as a summary. It is a
list with `ids`, `time`, `status`, the counts `n_rows`, `n_units` and
`n_transitions` (pairs of consecutive observations), and `transitions`,
a tibble with `from`, `to`, `units` (units making the transition at
least once) and `n` (times it is made).

## Details

Each row is compared with the unit's next observation in time, whatever
the distance: a person observed as completed in 2019 and as not started
in 2021 makes that transition even if 2020 is missing. Find the missing
years with
[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md).
Rows with a missing time or status are left out, as missing is a
different problem than a wrong status.

The unit is what the `id` columns say. A person may complete one
education and start another; then the unit is the person and the
education, `id = c(cpr, education)`, not the person, or the new start
looks like a step back.

The same works for spells: give the start column as `time`, and each
spell is compared with the unit's next spell.

## See also

[`ensure_transitions()`](https://dataniel.github.io/inshape/reference/ensure_transitions.md)
to forbid transitions,
[`carry_status()`](https://dataniel.github.io/inshape/reference/carry_status.md)
to let a status stand once reached.

## Examples

``` r
education <- data.frame(
  cpr    = c("a", "a", "a", "b", "b", "c", "c"),
  year   = c(2019, 2020, 2021, 2019, 2020, 2019, 2021),
  status = c("not started", "enrolled", "completed",
             "enrolled", "completed", "completed", "not started")
)
# c goes from completed to not started
describe_transitions(education, cpr, year, status)
#> ── Transitions: status by year per cpr ─────────────────────────────────────────
#> 7 rows, 3 units, 4 pairs of consecutive observations
#> 
#> • Changing status: 4 of 4 pairs (100.0%)
#> 
#> Units per transition, from (rows) to (columns):
#>   from \ to   completed  enrolled  not started
#>   completed            0         0            1
#>   enrolled             2         0            0
#>   not started          0         1            0
```
