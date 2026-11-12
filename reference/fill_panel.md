# Add the missing unit-periods of a panel as rows

The fix for a panel that
[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
reports: every unit-period that should be there and is not becomes a
row, with the unit and the period filled in and every other column
missing. A count of persons per year then counts a person who is missing
in a year as missing, instead of leaving the year out, and a lag over
years compares the years it should.

## Usage

``` r
fill_panel(data, id, time, periods = NULL, gaps_only = TRUE, flag = NULL)
```

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- id:

  Column(s) identifying the unit (tidy-select), e.g. `cpr` or
  `c(cvr, lbnr)`.

- time:

  The period column (one column), e.g. `year`. Any type that sorts, such
  as integer years or dates.

- periods:

  Expected periods. Defaults to the periods observed in `data`.

- gaps_only:

  If `TRUE` (default), only periods between a unit's first and last
  observation are added. If `FALSE`, every unit gets every period.

- flag:

  Name of a logical column marking the added rows, or `NULL` (default)
  for none.

## Value

`data` with the missing unit-periods added: a tibble for a data frame, a
query for a database or Arrow table.

## Details

It is the one fix for a panel that needs no choice: the missing rows are
given by the unit and the periods, and their values are unknown. It does
not guess them; carry a status forward with
[`carry_status()`](https://dataniel.github.io/inshape/reference/carry_status.md)
if that is what the analysis needs.

The fix is never silent: it says how many rows it added, and for how
many units. With `flag`, the added rows are marked in a logical column
of that name, so they can be found afterwards.

The periods and `gaps_only` work as in
[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md):
by default a unit gets the periods between its first and last
observation, so a person who enters late or leaves early is not given
rows before birth or after death. With `gaps_only = FALSE` every unit
gets every period.

A data frame comes back with the added rows sorted in among the others,
by unit and period. A database or Arrow table comes back as a query that
adds the rows, without changing the table.

## See also

[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
and
[`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md)
to find the gaps first.

## Examples

``` r
panel <- data.frame(
  cpr    = c("a", "a", "a", "b", "b"),
  year   = c(2020, 2021, 2022, 2020, 2022),
  income = c(100, 110, 120, 90, 95)
)
# b lacks 2021
fill_panel(panel, cpr, year)
#> ℹ Added 1 row for 1 unit, with every column but cpr, year missing.
#> # A tibble: 6 × 3
#>   cpr    year income
#>   <chr> <dbl>  <dbl>
#> 1 a      2020    100
#> 2 a      2021    110
#> 3 a      2022    120
#> 4 b      2020     90
#> 5 b      2021     NA
#> 6 b      2022     95

fill_panel(panel, cpr, year, flag = "filled")
#> ℹ Added 1 row for 1 unit, with every column but cpr, year missing.
#> # A tibble: 6 × 4
#>   cpr    year income filled
#>   <chr> <dbl>  <dbl> <lgl> 
#> 1 a      2020    100 FALSE 
#> 2 a      2021    110 FALSE 
#> 3 a      2022    120 FALSE 
#> 4 b      2020     90 FALSE 
#> 5 b      2021     NA TRUE  
#> 6 b      2022     95 FALSE 
```
