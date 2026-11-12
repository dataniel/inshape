# Let a status stand once it is reached

The fix for the transitions
[`ensure_transitions()`](https://dataniel.github.io/inshape/reference/ensure_transitions.md)
forbids, when you know which status holds: a completed education stays
completed, the highest education completed never falls. The status is
carried forward over the unit's later observations, and the earlier,
wrong ones after it are overwritten in a new column. Once the rule is
given there is one right result, so the function does not guess, as
[`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md)
does not.

## Usage

``` r
carry_status(data, id, time, status, final = NULL, order = NULL, name = NULL)
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

- final:

  Statuses that hold once reached.

- order:

  All statuses, from lowest to highest.

- name:

  Name of the column for the result. Defaults to the status column's
  name followed by `_carried`.

## Value

`data` with the carried status in the column `name`: a tibble for a data
frame, in the original row order, or a query for a database or Arrow
table.

## Details

Two ways to give the rule, one operation:

- `final`: once a unit reaches one of these statuses, it holds in every
  later observation. With several, the first one reached holds.

- `order`: the statuses from lowest to highest; a unit's status is the
  highest it has had so far, so it never goes back in the order. Every
  status in the data must be in `order`.

Later observations are taken in time order, whatever the distance, as in
[`describe_transitions()`](https://dataniel.github.io/inshape/reference/describe_transitions.md).
A missing status after the status is reached gets it too; one before
keeps its missing value. Rows with a missing time are left as they are.

The fix is never silent: it says how many rows and units it changed,
counted per change, such as
`not started -> completed: 37 rows in 31 units`. The result goes to a
new column by default, so the original status stands beside it and the
changed rows can be found by comparing the two; numbers behind a
published table should not change without a trace of where. Give
`name = <the status column>` to overwrite it.

The unit is what the `id` columns say. Carried per person, a completed
education overwrites the start of the next one; carry per person and
education, `id = c(cpr, education)`.

## See also

[`ensure_transitions()`](https://dataniel.github.io/inshape/reference/ensure_transitions.md)
and
[`describe_transitions()`](https://dataniel.github.io/inshape/reference/describe_transitions.md)
to find the transitions first.

## Examples

``` r
education <- data.frame(
  cpr    = c("a", "a", "a", "b", "b", "b"),
  year   = c(2019, 2020, 2021, 2019, 2020, 2021),
  status = c("enrolled", "completed", "enrolled",
             "not started", "enrolled", "completed")
)
carry_status(education, cpr, year, status, final = "completed")
#> ℹ Changed 1 row in 1 unit:
#>   enrolled -> completed: 1 row in 1 unit
#> # A tibble: 6 × 4
#>   cpr    year status      status_carried
#>   <chr> <dbl> <chr>       <chr>         
#> 1 a      2019 enrolled    enrolled      
#> 2 a      2020 completed   completed     
#> 3 a      2021 enrolled    completed     
#> 4 b      2019 not started not started   
#> 5 b      2020 enrolled    enrolled      
#> 6 b      2021 completed   completed     

# The highest level so far
levels <- data.frame(cpr = "a", year = 2019:2022, level = c(1, 3, 2, 4))
carry_status(levels, cpr, year, level, order = 1:4)
#> ℹ Changed 1 row in 1 unit:
#>   2 -> 3: 1 row in 1 unit
#> # A tibble: 4 × 4
#>   cpr    year level level_carried
#>   <chr> <int> <dbl>         <dbl>
#> 1 a      2019     1             1
#> 2 a      2020     3             3
#> 3 a      2021     2             3
#> 4 a      2022     4             4
```
