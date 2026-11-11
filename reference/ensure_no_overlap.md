# Assert that spells do not overlap within a unit

A checkpoint for spell data, the other common shape of register data:
address periods, employment spells, benefit periods. Each unit can only
be in one spell at a time, so two spells for the same person that share
a day are an error. Returns `data`, so it can sit in the middle of a
pipeline.

## Usage

``` r
ensure_no_overlap(
  data,
  id,
  start,
  end,
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

  Column(s) identifying the unit (tidy-select), e.g. `cpr`.

- start, end:

  Columns with the first and last period of each spell (dates, or
  integers such as years).

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when spells overlap and no `abort_msg` is set. Defaults
  to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

On failure the overlapping spells are reported with an `overlap_id`
column prepended, in the spirit of `dupid` in
[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md):
spells that overlap each other (directly or through a chain) share an
id, so each conflict can be inspected as a group.

Spells are treated as closed intervals, as register dates usually are: a
spell ending 31 January and one starting 1 February do not overlap,
while one ending and one starting on 1 February do. A missing `end`
means an ongoing spell and overlaps everything after its start. Rows
with a missing `start` are ignored. Check missing starts and ends before
starts with
[`ensure_valid_spells()`](https://dataniel.github.io/inshape/reference/ensure_valid_spells.md)
before checking overlaps.

## See also

[`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md)
to see how spells relate first,
[`ensure_no_gaps()`](https://dataniel.github.io/inshape/reference/ensure_no_gaps.md)
for the opposite rule,
[`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md)
when overlapping spells are one spell recorded twice,
[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
for yearly panels,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
addresses <- data.frame(
  cpr   = c("a", "a", "b", "b"),
  start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-06-01")),
  end   = as.Date(c("2020-12-31", NA,           "2020-06-30", "2021-12-31"))
)

# b has two addresses in June 2020
ensure_no_overlap(addresses, cpr, start, end)
#> Warning: Overlapping spells per cpr
#> ℹ 2 rows in 1 group:
#>     overlap_id cpr   start      end
#>          <int> <chr> <date>     <date>
#>   1          1 b     2020-01-01 2020-06-30
#>   2          1 b     2020-06-01 2021-12-31
```
