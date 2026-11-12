# Assert that key columns identify each row uniquely

A checkpoint for keys: every combination of the selected columns must
occur at most once. On failure the duplicated rows are reported (see
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md))
grouped by a `dupid` column, so each group of copies can be inspected
together. Returns `data`, so it can sit in the middle of a pipeline.

## Usage

``` r
ensure_unique(data, ..., success_msg = NULL, warn_msg = NULL, abort_msg = NULL)
```

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- ...:

  Key columns (tidy-select). If omitted, all columns are used, which
  checks for fully duplicated rows.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when duplicates exist and no `abort_msg` is set.
  Defaults to a description naming the key columns.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

The most valuable place for it is just before a join. A lookup table
with a duplicated key makes `left_join()` silently multiply rows;
checking the key first turns that into an explicit message:

    codes |>
      ensure_unique(branche, abort_msg = "Codebook has duplicate codes") |>
      left_join(x = df, by = "branche")

It is fast on a population register: the key is grouped without sorting
it, and the full rows are only touched when there are duplicates to
report.

## See also

[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
for unit-periods,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
persons <- data.frame(
  cpr  = c("a", "b", "b", "c"),
  year = c(2024, 2024, 2024, 2024)
)

# Success: one row per person
ensure_unique(persons[persons$cpr != "b", ], cpr, year)
#> ✔ Unique on cpr, year

# Warning: b appears twice in 2024
ensure_unique(persons, cpr, year)
#> Warning: Duplicate rows on cpr, year
#> ℹ 2 rows in 1 group
#>   The copies are identical in every column
#> ℹ The rows:
#>     dupid cpr    year
#>     <int> <chr> <dbl>
#>   1     1 b      2024
#>   2     1 b      2024
#> ℹ To drop the exact copies: dplyr::distinct(persons)

if (FALSE) { # \dontrun{
df |>
  ensure_unique(cvr, year, abort_msg = "Duplicate company-years")
} # }
```
