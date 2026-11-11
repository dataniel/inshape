# Assert that a column only holds codes from a code list

A checkpoint for coded columns: municipality, industry, education. A
value outside the code list is a typo, an old code that should have been
converted, or a code from another classification, and it silently drops
out of every table built on the code list. On failure the offending rows
are reported, with the codes counted. Returns `data`, so it can sit in
the middle of a pipeline.

## Usage

``` r
ensure_codes(
  data,
  column,
  codes,
  time = NULL,
  na_ok = TRUE,
  success_msg = NULL,
  warn_msg = NULL,
  abort_msg = NULL
)
```

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- column:

  The coded column (tidy-select), e.g. `municipality`.

- codes:

  A vector of valid codes, or a local data frame with columns `code`,
  `valid_from`, `valid_to`. An empty temporal list allows no codes.

- time:

  Observation time column (tidy-select), required for a time-dependent
  code list and omitted for a vector.

- na_ok:

  Whether a missing value passes. Default `TRUE`.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when values are outside the code list and no `abort_msg`
  is set. Defaults to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

Missing values pass by default, as missing is a different problem from a
wrong code; set `na_ok = FALSE` to require a code on every row. The code
list is compared as text when the column is text, so `"0955"` and
`"955"` are different codes, as they are in the register.

For time-dependent codes, supply a data frame with `code`, `valid_from`
and `valid_to`, and select the observation's `time` column. Boundaries
are inclusive; missing boundaries are open. Multiple validity intervals
per code are allowed. A non-missing code with missing time fails, since
its validity cannot be established. `na_ok` only controls missing codes.
Time and both boundaries must use the same scale: Date, POSIXct, or
numeric periods. Years and dates are not implicitly mixed. The code list
must have non-missing codes and ordered boundaries.

## See also

[`describe_codes()`](https://dataniel.github.io/inshape/reference/describe_codes.md)
for how codes change over periods,
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
persons <- data.frame(cpr = c("a", "b", "c", "d"),
                      municipality = c("955", "956", "95", NA))
valid <- c("955", "956", "957", "959", "960")
# "95" is not a municipality
ensure_codes(persons, municipality, valid)
#> Warning: Codes not in the code list: municipality
#> ℹ 1 row in 1 group:
#>     municipality cpr
#>     <chr>        <chr>
#>   1 95           c
```
