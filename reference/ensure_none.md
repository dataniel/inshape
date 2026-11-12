# Assert that no rows match a condition

The in-pipeline form of
[`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md).
Instead of filtering for the violations and piping *them* in, pass the
condition directly. The check is the same, but `data` itself is
returned, so the pipeline continues with all rows:

## Usage

``` r
ensure_none(data, ..., success_msg = NULL, warn_msg = NULL, abort_msg = NULL)
```

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- ...:

  Conditions that describe a violating row, as in
  [`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html).

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when rows match and no `abort_msg` is set. Defaults to a
  description of the condition.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

    df |>
      ensure_none(is.na(id), abort_msg = "Rows without an id") |>
      ensure_none(amount < 0) |>
      mutate(...)

Conditions follow
[`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html)
semantics: several conditions are combined with `&`, and a row where a
condition is `NA` does not count as a violation. Test for missing values
explicitly with [`is.na()`](https://rdrr.io/r/base/NA.html) when they
matter, or state the rule positively with
[`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md),
where a missing value is a violation.

Without a message, the condition itself becomes the message
(`"Found rows where amount < 0"`), which is often clear enough during
exploration. Write your own message for checks that stay in production.

## See also

[`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md)
for the rule stated positively, where a missing value is a violation;
[`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md),
[`tally_violations()`](https://dataniel.github.io/inshape/reference/tally_violations.md),
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
mtcars |>
  ensure_none(cyl < 4) |>
  ensure_none(mpg > 40, warn_msg = "Implausibly efficient cars") |>
  nrow()
#> ✔ No rows where cyl < 4
#> ✔ Check passed: Implausibly efficient cars
#> [1] 32

# The rows of a failed check, all of them
violations(ensure_none(mtcars, mpg > 30))
#> # A tibble: 4 × 11
#>     mpg   cyl  disp    hp  drat    wt  qsec    vs    am  gear  carb
#>   <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl> <dbl>
#> 1  32.4     4  78.7    66  4.08  2.2   19.5     1     1     4     1
#> 2  30.4     4  75.7    52  4.93  1.62  18.5     1     1     4     2
#> 3  33.9     4  71.1    65  4.22  1.84  19.9     1     1     4     1
#> 4  30.4     4  95.1   113  3.77  1.51  16.9     1     1     5     2

if (FALSE) { # \dontrun{
dplyr::starwars |>
  ensure_none(is.na(species), abort_msg = "Characters without a species")
} # }
```
