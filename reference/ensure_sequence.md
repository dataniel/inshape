# Assert that events come in order

A checkpoint for events that need another before them: an exam needs an
enrolment, a move out a move in, a divorce a marriage. Every `then`
event of a unit must come on or after the unit's first `first` event.
The `then` events that come before it, or in a unit with no `first`
event at all, are reported, with a `reason` column saying which. Returns
`data`, so it can sit in the middle of a pipeline.

## Usage

``` r
ensure_sequence(
  data,
  id,
  time,
  event,
  first,
  then,
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

  The date or period of each event (one column).

- event:

  The type of event (one column).

- first:

  The event that must come first, e.g. `"enrolled"`.

- then:

  The event that must not come before it, e.g. `"exam"`.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when events come out of order and no `abort_msg` is set.
  Defaults to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

Events on the same day are in order. Rows with a missing time are only
reported when the unit has no `first` event. The unit is what the `id`
columns say: give `id = c(cpr, education)` when an exam needs an
enrolment in the same education.

Too many events of one kind, such as two deaths, is
[`ensure_counts()`](https://dataniel.github.io/inshape/reference/ensure_counts.md)
with the event as the role.

## See also

[`describe_events()`](https://dataniel.github.io/inshape/reference/describe_events.md),
[`ensure_transitions()`](https://dataniel.github.io/inshape/reference/ensure_transitions.md)
for a status that changes over time,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
events <- data.frame(
  cpr   = c("a", "a", "b", "b", "c"),
  date  = as.Date(c("2020-08-15", "2021-06-01", "2021-06-01", "2021-08-15",
                    "2021-06-01")),
  event = c("enrolled", "exam", "exam", "enrolled", "exam")
)
# b takes an exam before enrolling, c without enrolling
ensure_sequence(events, cpr, date, event, first = "enrolled", then = "exam")
#> Warning: exam before enrolled per cpr
#> ℹ 2 rows in 2 groups
#>   In 2 units
#>   Reasons: before enrolled (1), no enrolled (1)
#> ℹ The rows:
#>     reason          cpr   date       event
#>     <chr>           <chr> <date>     <chr>
#>   1 before enrolled b     2021-06-01 exam
#>   2 no enrolled     c     2021-06-01 exam
```
