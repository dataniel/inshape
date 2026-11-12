# Assert that columns are constant within each unit

A checkpoint for attributes that belong to the unit, not to the row: sex
and birth date per person, the founding year per company. In a panel or
a set of spells they are repeated on every row, and a unit with two
values is an error, usually of linkage or of a register correction
applied to some years only. On failure, every row of the units that vary
is reported, so the conflicting values sit together. Returns `data`, so
it can sit in the middle of a pipeline.

## Usage

``` r
ensure_constant(
  data,
  id,
  ...,
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

- ...:

  Columns that must be constant within a unit (tidy-select), e.g.
  `sex, birth_date`.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when a column varies and no `abort_msg` is set. Defaults
  to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

The same check covers hierarchies: that each settlement lies in one
municipality, or each 4-digit code in one 2-digit code, is the parent
column constant within the child,
`ensure_constant(places, settlement, municipality)`. With years, give
both, `ensure_constant(places, c(settlement, year), municipality)`, so a
settlement may move between municipalities in a reform but not within a
year.

A missing value does not break the rule: a sex that is missing in one
year and known in another is incomplete, not contradictory. Find such
units with
[`describe_varying()`](https://dataniel.github.io/inshape/reference/describe_varying.md),
which counts them as partly missing.

## See also

[`describe_varying()`](https://dataniel.github.io/inshape/reference/describe_varying.md)
to see which columns vary, and how much.

## Examples

``` r
persons <- data.frame(
  cpr  = c("a", "a", "b", "b", "c", "c"),
  year = c(2020, 2021, 2020, 2021, 2020, 2021),
  sex  = c("F", "F", "M", "F", "M", NA)
)
# b changes sex; c is only missing in 2021
ensure_constant(persons, cpr, sex)
#> Warning: Varies within units: sex per cpr
#> ℹ 2 rows
#>   In 1 unit
#> ℹ The rows:
#>     cpr   sex    year
#>     <chr> <chr> <dbl>
#>   1 b     M      2020
#>   2 b     F      2021
#> ℹ Which value holds is a choice, e.g. dplyr::mutate(persons, sex = <first, last or most common>, .by = cpr)
```
