# Assert that columns have no missing values

A checkpoint for the columns an analysis cannot do without: an id, a
date, the outcome. A missing value in them drops the row from a model
without a word, or makes it a group of its own in a count. Returns
`data`, so it can sit in the middle of a pipeline.

## Usage

``` r
ensure_complete(
  data,
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

- ...:

  Columns that must be complete (tidy-select). If omitted, all columns
  are checked.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when values are missing and no `abort_msg` is set.
  Defaults to a description naming the columns.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

On failure the rows with a missing value in any of the columns are
reported, with a `missing` column prepended that names the columns
missing in that row, e.g. `"born, sex"`. The summary counts the rows and
the different combinations of missing columns.

Missing means `NA`, and for numbers `NaN` too, as in
[`is.na()`](https://rdrr.io/r/base/NA.html); an empty string is a value.
In a database table missing means `NULL`.

## See also

[`describe_varying()`](https://dataniel.github.io/inshape/reference/describe_varying.md)
and
[`describe_key()`](https://dataniel.github.io/inshape/reference/describe_key.md),
which count missing values per column,
[`ensure_valid_spells()`](https://dataniel.github.io/inshape/reference/ensure_valid_spells.md)
for missing spell bounds,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
persons <- data.frame(
  cpr  = c("a", "b", NA, "d"),
  born = as.Date(c("1980-05-01", NA, NA, "1975-02-11")),
  sex  = c("F", "M", "F", NA)
)

# Success: no one lacks a sex among the first three
ensure_complete(persons[1:3, ], sex)
#> ✔ Complete: sex

# Warning: b lacks a birth date, the third row a cpr as well
ensure_complete(persons, cpr, born)
#> Warning: Missing values in: cpr, born
#> ℹ 2 rows in 2 groups
#>   Missing per column: born (2), cpr (1)
#> ℹ The rows:
#>     missing   cpr   born   sex
#>     <chr>     <chr> <date> <chr>
#>   1 born      b     NA     M
#>   2 cpr, born NA    NA     F

# All columns
ensure_complete(persons)
#> Warning: Missing values in: all columns
#> ℹ 3 rows in 3 groups
#>   Missing per column: born (2), cpr (1), sex (1)
#> ℹ The rows:
#>     missing   cpr   born       sex
#>     <chr>     <chr> <date>     <chr>
#>   1 born      b     NA         M
#>   2 cpr, born NA    NA         F
#>   3 sex       d     1975-02-11 NA
```
