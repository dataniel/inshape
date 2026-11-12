# Assert that every row meets a condition

The positive form of
[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md):
state what must hold instead of what must not occur. `data` itself is
returned, so the pipeline continues with all rows:

## Usage

``` r
ensure_all(data, ..., success_msg = NULL, warn_msg = NULL, abort_msg = NULL)
```

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- ...:

  Conditions every row must meet, written as in
  [`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html).

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when rows fail the condition and no `abort_msg` is set.
  Defaults to a description of the condition.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

    df |>
      ensure_all(amount >= 0, abort_msg = "Amounts must not be negative") |>
      ensure_all(year %in% 2015:2024) |>
      mutate(...)

### Why both `ensure_all()` and [`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md)

The two are not each other's negation, because they treat a missing
value differently. A row violates `ensure_all()` unless the condition is
`TRUE`, so a row where it is `NA` is a violation: the rule cannot be
shown to hold. In
[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md)
such a row passes, as it would in
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html).

    df <- data.frame(amount = c(10, -5, NA))

    ensure_none(df, amount < 0)   # 1 row: -5
    ensure_all(df, amount >= 0)   # 2 rows: -5 and NA

Use `ensure_all()` when a value has to be present *and* right, and
[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md)
when a missing value is acceptable or is a separate rule with its own
message.

Several conditions must all hold, so a row is a violation when any of
them is `FALSE` or `NA`.

## See also

[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md),
[`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md),
[`tally_violations()`](https://dataniel.github.io/inshape/reference/tally_violations.md),
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md)

## Examples

``` r
mtcars |>
  ensure_all(cyl %in% c(4, 6, 8)) |>
  ensure_all(mpg > 15, warn_msg = "Thirsty cars") |>
  nrow()
#> ✔ All rows meet cyl %in% c(4, 6, 8)
#> Warning: Thirsty cars
#> ℹ 6 rows found:
#>       mpg   cyl  disp    hp  drat    wt  qsec    vs    am  gear  carb
#>     <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl>
#>   1  14.3     8   360   245  3.21  3.57  15.8     0     0     3     4
#>   2  10.4     8   472   205  2.93  5.25  18.0     0     0     3     4
#>   3  10.4     8   460   215  3     5.42  17.8     0     0     3     4
#>   4  14.7     8   440   230  3.23  5.34  17.4     0     0     3     4
#>   5  13.3     8   350   245  3.73  3.84  15.4     0     0     3     4
#>   # ℹ 1 more row
#> ℹ For all rows: violations(ensure_all(ensure_all(mtcars, cyl %in% c(4, 6, 8)), mpg > 15))
#> [1] 32

# A missing value is a violation here, but not in ensure_none()
df <- data.frame(amount = c(10, -5, NA))
ensure_all(df, amount >= 0)
#> Warning: Found rows that do not meet amount >= 0
#> ℹ 2 rows found:
#>     amount
#>      <dbl>
#>   1     -5
#>   2     NA
ensure_none(df, amount < 0)
#> Warning: Found rows where amount < 0
#> ℹ 1 row found:
#>     amount
#>      <dbl>
#>   1     -5
```
