# Assert that microdata add up to a published table

A checkpoint for the step from microdata to a published table: counted
(or summed) by the table's dimensions, the microdata must give the
numbers in the table, cell for cell. A cell that differs is a sign that
the microdata or the table was built from another extract, with another
definition, or with an error, and it is found before the next table is
built on the same microdata. Returns `data`, so it can sit in the middle
of a pipeline.

## Usage

``` r
ensure_reconciled(
  data,
  published,
  by,
  value = "n",
  sum = NULL,
  tolerance = 0,
  success_msg = NULL,
  warn_msg = NULL,
  abort_msg = NULL
)
```

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- published:

  The published table: a local data frame with the `by` columns and the
  `value` column, one row per cell.

- by:

  Dimension columns, as in
  [`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md):
  a character vector, optionally named to map names in `data` to names
  in `published`, e.g. `c(year = "tid", municipality = "omraade")`.

- value:

  Name of the column of `published` holding the numbers. Default `"n"`.

- sum:

  Column of `data` to sum (tidy-select). If `NULL` (default), rows are
  counted.

- tolerance:

  The largest difference that is accepted, for a table rounded or
  perturbed for disclosure. Default 0.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when cells differ and no `abort_msg` is set. Defaults to
  a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

The table is a data frame you give it, with one row per cell: the
dimension columns named in `by` and the number in `value`. The package
does not fetch tables itself; read the table from the statistics bank
and pass it in. Dimension columns of the table are converted to the type
of the microdata column first, so a year read as text matches a numeric
year.

On failure the cells that differ are reported, with the microdata number
in `data`, the table's in `published` and `difference` (data minus
published). A cell in the microdata that the table does not have is
reported with a missing `published`; a cell in the table that the
microdata do not have counts as 0 in the microdata. A cell whose
published value is missing, such as one suppressed for disclosure, is
not compared, and the message says how many there are.

The reported rows are counts, not persons. The microdata are counted
where they live, so only the counts of a database table are fetched.

## See also

[`ensure_stock_flow()`](https://dataniel.github.io/inshape/reference/ensure_stock_flow.md)
for a population account over periods,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
persons <- data.frame(
  cpr  = c("a", "b", "c", "d", "e"),
  year = c(2023, 2023, 2024, 2024, 2024),
  sex  = c("F", "M", "F", "F", "M")
)
published <- data.frame(
  tid = c("2023", "2023", "2024", "2024"),
  sex = c("F", "M", "F", "M"),
  n   = c(1, 1, 3, 1)
)
# The table has 3 women in 2024, the microdata 2
ensure_reconciled(persons, published, by = c(year = "tid", "sex"))
#> Warning: The count differs from the table by year, sex
#> ℹ 1 row
#>   Of 4 cells compared
#>   Difference: total -1, largest -1
#> ℹ The rows:
#>      year sex    data published difference
#>     <dbl> <chr> <dbl>     <dbl>      <dbl>
#>   1  2024 F         2         3         -1
#> ℹ If the table is rounded or perturbed for disclosure: tolerance = <largest accepted difference>
```
