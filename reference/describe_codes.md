# Describe how the codes of a column change over periods

Code lists change: municipalities merge, industry codes are revised, a
code is retired and a new one takes its place. In a register spanning
many years the codes of one column then come and go, and so do errors
that look like codes: a typo that occurs in one year, an old code that
should have been converted. `describe_codes()` shows, for every code,
the first and last period it occurs in and whether it skips periods in
between, and per period how many codes are new and how many are gone. It
judges nothing; require a code list with
[`ensure_codes()`](https://dataniel.github.io/inshape/reference/ensure_codes.md).

## Usage

``` r
describe_codes(data, code, time, periods = NULL)
```

## Arguments

- data:

  A data frame or tibble, or a database or Arrow table: see *Database
  tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- code:

  The code column (one column), e.g. `municipality`.

- time:

  The period column (one column), e.g. `year`.

- periods:

  Expected periods. Defaults to those observed in `data`.

## Value

An object of class `inshape_codes`, printed as a summary. It is a list
with the counts `n_rows`, `n_codes`, `n_every_period`, `n_with_gaps`,
`n_missing` (rows with a missing code), `n_missing_time` and
`n_outside`, the `periods`, and two tibbles: `codes` (`code`, `first`,
`last`, `periods`, `gaps`, `rows`) and `by_period` (`period`, `codes`,
`new`, `gone`, `missing`).

## Details

A code that skips periods is usually an error or a conversion applied to
some years only. A period with many new and many gone codes is a
revision of the code list, and the data before and after it are not
comparable without a conversion key.

Missing codes are counted per period, not as a code. In `by_period`,
`new` is `NA` in the first period and `gone` counts the codes last seen
in the period before.

## Why it is fast

The code and period columns are compressed to integer ids by the
compiled hash, and the distinct code-periods are found by one more hash
pass. A code column has few distinct values and nearly every row repeats
a code-period, so everything else is counted on the code-periods, a few
hundred or thousand, not on the millions of rows.

## See also

[`ensure_codes()`](https://dataniel.github.io/inshape/reference/ensure_codes.md)
to require codes from a code list.

## Examples

``` r
persons <- data.frame(
  year = rep(2018:2021, each = 3),
  municipality = c("955", "956", "957",  "955", "956", "957",
                   "960", "956", "957",  "960", "965", "957")
)
# 955 becomes 960 in 2020 and 956 becomes 965 in 2021
describe_codes(persons, municipality, year)
#> ── Codes: municipality by year ─────────────────────────────────────────────────
#> 12 rows, 5 codes, 4 periods, 2018-2021
#> 
#> • In every period: 1 code (20.0%)
#> • Skipping periods: 0 codes (0.0%)
#> 
#> By period:
#>     period codes   new  gone missing
#>   1   2018     3    NA    NA       0
#>   2   2019     3     0     0       0
#>   3   2020     3     1     1       0
#>   4   2021     3     1     1       0
#> 
#> Codes not in every period, skipping first:
#>     code  first  last periods  gaps  rows
#>   1 965    2021  2021       1     0     1
#>   2 955    2018  2019       2     0     2
#>   3 960    2020  2021       2     0     2
#>   4 956    2018  2020       3     0     3
```
