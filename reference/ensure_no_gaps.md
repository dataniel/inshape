# Assert that a unit's spells leave no gaps

A checkpoint for spell data that should cover a unit without a break:
everyone resident has an address every day, an insured person a policy,
a dwelling an owner. A spell that starts later than the day after the
unit's earlier spells have ended leaves days that no spell covers.
Returns `data`, so it can sit in the middle of a pipeline.

## Usage

``` r
ensure_no_gaps(
  data,
  id,
  start,
  end,
  max_gap = 0,
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

- max_gap:

  The longest gap that is accepted, in days (or periods). The default 0
  accepts none. As in
  [`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md),
  `max_gap = 1` lets a spell start two days after the previous one
  ended.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when there are gaps and no `abort_msg` is set. Defaults
  to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

It is the counterpart of
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md):
that a unit is in at most one spell at a time, and here in at least one,
between its first start and its last end. Together they say exactly one.
The time before a unit's first spell and after its last is not a gap;
compare those with birth, death or migration dates with
[`ensure_within()`](https://dataniel.github.io/inshape/reference/ensure_within.md).

On failure the spell that starts after each gap is reported, with a
`gap` column prepended holding the number of days (or periods) that no
spell covers before it. The spell that ended last before the gap is the
one with the latest end among the unit's earlier spells, not always the
row above.

Spells are closed intervals, as in
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md):
a spell ending 31 January and one starting 1 February leave no gap, one
starting 2 February leaves a gap of one day. A missing `end` means an
ongoing spell, and nothing after its start is a gap. Rows with a missing
`start`, or an `end` before the `start`, are ignored, as in
[`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md);
find them with
[`ensure_valid_spells()`](https://dataniel.github.io/inshape/reference/ensure_valid_spells.md).

## See also

[`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md)
to count the gaps and their lengths first,
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md)
for the opposite rule,
[`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md)
to join spells across short gaps,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
addresses <- data.frame(
  cpr   = c("a", "a", "b", "b"),
  start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-07-04")),
  end   = as.Date(c("2020-12-31", NA,           "2020-06-30", "2021-12-31"))
)

# b has no address on 1, 2 and 3 July 2020
ensure_no_gaps(addresses, cpr, start, end)
#> Warning: Gaps between spells per cpr
#> ℹ 1 row
#>   In 1 unit
#>   Gap length in days: shortest 3, median 3, longest 3
#> ℹ The rows:
#>       gap cpr   start      end
#>     <int> <chr> <date>     <date>
#>   1     3 b     2020-07-04 2021-12-31
#> ℹ To join spells across gaps up to a length you choose: merge_spells(addresses, cpr, start, end, max_gap = <length>)

# Accept up to a week without an address
ensure_no_gaps(addresses, cpr, start, end, max_gap = 7)
#> ✔ No gaps between spells longer than 7 days per cpr
```
