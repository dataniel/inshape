# Assert that a stock and its flows add up over periods

A checkpoint for an account over periods: the population at the end of a
year must be the population at the end of the year before, plus the born
and the immigrated, minus the dead and the emigrated. For a population
statistic it is the check that catches most, since every person who is
lost or counted twice between the stock and the flows breaks it. Returns
`data`, so it can sit in the middle of a pipeline.

## Usage

``` r
ensure_stock_flow(
  data,
  time,
  stock,
  inflow,
  outflow,
  by = NULL,
  stock_at = c("end", "start"),
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

- time:

  The period column (one column).

- stock:

  The stock column (one column).

- inflow, outflow:

  Columns of flows into and out of the stock (tidy-select, one or more
  each), e.g. `c(born, immigrated)`.

- by:

  Columns grouping the account (tidy-select), e.g. `sex`, or `NULL`
  (default) for one account.

- stock_at:

  `"end"` (default) or `"start"`: when in the period the stock is
  counted.

- tolerance:

  The largest difference that is accepted. Default 0.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when the account does not add up and no `abort_msg` is
  set. Defaults to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

`data` holds one row per period (and per group, with `by`): the stock
and the flows during the period, as counted from the registers. Inflows
and outflows may be several columns each; they are added up per row.

With `stock_at = "end"` (default) the stock is counted at the end of
each period, so it is the stock before plus the period's flows. With
`stock_at = "start"` it is counted at the start, so it is the stock
before plus the flows of the period before.

On failure the periods where the account does not add up are reported,
with `expected` (the stock before plus the flows) and `difference` (the
stock minus expected). The first period of each group has no stock
before it and is not checked. A period missing in the middle makes the
next one compared with the one before the gap; find such gaps with
[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md).
Rows with a missing stock or flow are not checked.

The table is small, one row per period and group, so a database or Arrow
table is fetched into R before the check.

## See also

[`ensure_reconciled()`](https://dataniel.github.io/inshape/reference/ensure_reconciled.md)
to compare microdata with a published table,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
account <- data.frame(
  year       = 2021:2024,
  population = c(56000, 56100, 56210, 56300),
  born       = c(800, 820, 790, 810),
  immigrated = c(2000, 2100, 2050, 2200),
  dead       = c(500, 520, 510, 530),
  emigrated  = c(2200, 2300, 2280, 2330)
)
# 2023 has 60 persons more than its flows give, so 2024 has 60 fewer
ensure_stock_flow(account, year, population,
                  inflow = c(born, immigrated), outflow = c(dead, emigrated))
#> Warning: The account does not add up: population by year
#> ℹ 2 rows
#>   Difference: total 0, largest 60
#> ℹ The rows:
#>      year population difference expected  born immigrated  dead emigrated
#>     <int>      <dbl>      <dbl>    <dbl> <dbl>      <dbl> <dbl>     <dbl>
#>   1  2023      56210         60    56150   790       2050   510      2280
#>   2  2024      56300        -60    56360   810       2200   530      2330
```
