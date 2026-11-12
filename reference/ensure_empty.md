# Assert that a set of violations is empty

The most general checkpoint. Express a rule as "the set of violations
must be empty", build that set with an ordinary
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html)
or an anti-join, and pipe it in. A rule that dplyr can express is a rule
`ensure_empty()` can check, also one no other checkpoint covers:

## Usage

``` r
ensure_empty(data, success_msg = NULL, warn_msg = NULL, abort_msg = NULL)
```

## Arguments

- data:

  The violation set: a data frame or tibble, a database table (dbplyr,
  e.g. DuckDB) or an Arrow table or dataset; see *Database and Arrow
  tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when `data` has rows and no `abort_msg` is set. Defaults
  to `"The dataset is not empty."`.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

    income |>
      dplyr::anti_join(population, by = "cpr") |>
      ensure_empty(abort_msg = "Income for persons outside the population")

When the data has no rows, a success line is printed. Otherwise
`ensure_empty()` warns, or aborts with `abort_msg`, and shows the number
of rows and the first few of them. Wrap the check in
[`violations()`](https://dataniel.github.io/inshape/reference/violations.md)
to get all of them.

Unlike the other checkpoints, `ensure_empty()` returns the violation set
it was given, not the data the rule is about, so it usually ends a
pipeline. Use
[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md)
or
[`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md)
to check a condition and carry on with all rows.

## See also

[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md)
and
[`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md)
to check a condition without leaving the pipeline,
[`tally_violations()`](https://dataniel.github.io/inshape/reference/tally_violations.md)
to count many rules at once,
[`violations()`](https://dataniel.github.io/inshape/reference/violations.md)
for all rows of a failed check,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
# Success: no rows
ensure_empty(data.frame())
#> ✔ The dataset is empty.

# Warning: unexpected rows
mtcars |>
  dplyr::filter(cyl > 6) |>
  ensure_empty(warn_msg = "Eight-cylinder cars found")
#> Warning: Eight-cylinder cars found
#> ℹ 14 rows found:
#>       mpg   cyl  disp    hp  drat    wt  qsec    vs    am  gear  carb
#>     <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl>
#>   1  18.7     8  360    175  3.15  3.44  17.0     0     0     3     2
#>   2  14.3     8  360    245  3.21  3.57  15.8     0     0     3     4
#>   3  16.4     8  276.   180  3.07  4.07  17.4     0     0     3     3
#>   4  17.3     8  276.   180  3.07  3.73  17.6     0     0     3     3
#>   5  15.2     8  276.   180  3.07  3.78  18       0     0     3     3
#>   # ℹ 9 more rows
#> ℹ For all rows: violations(ensure_empty(dplyr::filter(mtcars, cyl > 6)))

# Many rules at once, then one judgement
mtcars |>
  tally_violations(
    "Few cylinders" = cyl < 4,
    "High mileage"  = mpg > 30
  ) |>
  dplyr::filter(n > 0) |>
  ensure_empty(warn_msg = "Rules with violations")
#> Warning: Rules with violations
#> ℹ 1 row found:
#>     rule             n total rows
#>     <chr>        <int> <int> <list>
#>   1 High mileage     4    32 <int [4]>

if (FALSE) { # \dontrun{
# Abort: treat unexpected rows as a hard error
dplyr::starwars |>
  dplyr::filter(height < 0) |>
  ensure_empty(abort_msg = "Impossible: negative height")
} # }
```
