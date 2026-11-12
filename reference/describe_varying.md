# Describe which columns vary within a unit

Some columns should be constant within a unit: sex and birth date per
person, the start year of a company. Others are expected to vary:
income, address. `describe_varying()` shows, for each column, how many
units have more than one value, so the constant columns, the varying
ones and the nearly constant ones stand apart. A column that varies for
a handful of units out of millions is rarely meant to vary: those units
are usually errors, and
[`ensure_constant()`](https://dataniel.github.io/inshape/reference/ensure_constant.md)
lists them.

## Usage

``` r
describe_varying(data, id, ...)
```

## Arguments

- data:

  A data frame or tibble, or a database or Arrow table: see *Database
  tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- id:

  Column(s) identifying the unit (tidy-select), e.g. `cpr`.

- ...:

  Columns to describe (tidy-select). Defaults to all other columns.

## Value

An object of class `inshape_varying`, printed as a summary. It is a list
with `ids`, `n_units` and `columns`, a tibble with one row per column:
`column`, `varying` (units with more than one non-missing value),
`share` (of the units with a value), `partly_missing` (units with both
missing and non-missing values) and `all_missing`, sorted from the most
constant to the most varying.

## Details

A missing value is not counted as a value of its own: a person whose sex
is missing in one year and known in another has not changed sex, but is
partly missing, which is counted separately.

It is the within-unit view of Stata's `xtsum`, for categories as well as
numbers.

## Why it is fast

Units are grouped once by the compiled engine (see
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md)).
For each column, one compiled pass compares every row with the first
non-missing value of its unit, with no hashing or sorting of the column
and one memory word of state per unit.

## See also

[`ensure_constant()`](https://dataniel.github.io/inshape/reference/ensure_constant.md)
to require a column to be constant within units and list the units that
break it.

## Examples

``` r
persons <- data.frame(
  cpr    = c("a", "a", "b", "b", "c", "c"),
  year   = c(2020, 2021, 2020, 2021, 2020, 2021),
  sex    = c("F", "F", "M", "F", "M", NA),
  income = c(100, 120, 90, 95, 80, 85)
)
describe_varying(persons, cpr)
#> ── Within cpr ──────────────────────────────────────────────────────────────────
#> 3 units, 3 columns
#> 
#> ✔ No column is nearly constant
#> • Constant: 0 columns
#> 
#> Per column:
#>     column varying share   partly_missing all_missing
#>   1 sex          1 33.33%               1           0
#>   2 income       3 100.00%              0           0
#>   3 year         3 100.00%              0           0
```
