# Assert that a status only changes in allowed ways

A checkpoint for a status that follows a unit over time: a person who
has completed an education must not later be not started on it. Name the
transitions that cannot happen, or a final status that nothing else may
follow, and the rows where they happen are reported, counted per
transition. Returns `data`, so it can sit in the middle of a pipeline.

## Usage

``` r
ensure_transitions(
  data,
  id,
  time,
  status,
  forbid = NULL,
  final = NULL,
  success_msg = NULL,
  warn_msg = NULL,
  abort_msg = NULL
)
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

- forbid:

  Forbidden transitions, as strings `"from -> to"`.

- final:

  Statuses that, once reached, must not change.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when a forbidden transition happens and no `abort_msg`
  is set. Defaults to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

Each row is compared with the unit's next observation in time, whatever
the distance, as in
[`describe_transitions()`](https://dataniel.github.io/inshape/reference/describe_transitions.md),
which shows every transition there is before you write the rule. Rows
with a missing time or status are left out. The unit is what the `id`
columns say: give `id = c(cpr, education)` when a person may complete
one education and start another.

The rule is given as forbidden pairs,
`forbid = "completed -> enrolled"`, since few statuses only go forward
in a fixed order: an interrupted education can be resumed, a completed
one cannot. A final status, `final = "completed"`, is the common case
written short: every change away from it is forbidden. Statuses are
compared as text, so a numeric status is written as its number,
`"3 -> 1"`.

On failure the reported rows are the rows the forbidden transition goes
to, with a `transition` column naming it and a `previous` column holding
the time of the observation it comes from.

## See also

[`describe_transitions()`](https://dataniel.github.io/inshape/reference/describe_transitions.md)
to see every transition first,
[`carry_status()`](https://dataniel.github.io/inshape/reference/carry_status.md)
to let a final status stand,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
education <- data.frame(
  cpr    = c("a", "a", "a", "b", "b", "c", "c"),
  year   = c(2019, 2020, 2021, 2019, 2020, 2019, 2021),
  status = c("not started", "enrolled", "completed",
             "enrolled", "completed", "completed", "not started")
)
ensure_transitions(education, cpr, year, status, final = "completed")
#> Warning: Forbidden transitions: status by year per cpr
#> ℹ 1 row in 1 group
#>   In 1 unit
#>   By transition: completed -> not started (1)
#> ℹ The rows:
#>     transition               cpr   previous  year status
#>     <chr>                    <chr>    <dbl> <dbl> <chr>
#>   1 completed -> not started c         2019  2021 not started
#> ℹ If the final status is right and the later ones wrong: carry_status(education, cpr, year, status, final = "completed")

ensure_transitions(education, cpr, year, status,
                   forbid = c("completed -> not started", "enrolled -> not started"))
#> Warning: Forbidden transitions: status by year per cpr
#> ℹ 1 row in 1 group
#>   In 1 unit
#>   By transition: completed -> not started (1)
#> ℹ The rows:
#>     transition               cpr   previous  year status
#>     <chr>                    <chr>    <dbl> <dbl> <chr>
#>   1 completed -> not started c         2019  2021 not started
```
