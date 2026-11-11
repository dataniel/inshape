# Assert that spell boundaries are valid

Missing starts and ends before starts are violations. A missing end is
an ongoing spell and passes by default; use `open_end = FALSE` to
require closed spells. Equal boundaries are valid one-day or one-period
spells. Boundaries must both be dates, both date-times, or both numeric
periods. The diagnostic `reason` column identifies the first problem on
each row: missing start, missing end, then end before start.

## Usage

``` r
ensure_valid_spells(
  data,
  start,
  end,
  open_end = TRUE,
  success_msg = NULL,
  warn_msg = NULL,
  abort_msg = NULL
)
```

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- start, end:

  Columns containing spell boundaries (tidy-select).

- open_end:

  Allow missing end values. Default `TRUE`.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message when invalid spells are found.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged. Failures carry the offending rows.

## See also

[`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md),
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md),
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
spells <- data.frame(start = c(2020, NA, 2023), end = c(NA, 2022, 2022))
ensure_valid_spells(spells, start, end)
#> Warning: Invalid spells: start to end
#> ℹ 2 rows in 2 groups:
#>     reason           start   end
#>     <chr>            <dbl> <dbl>
#>   1 missing start       NA  2022
#>   2 end before start  2023  2022
```
