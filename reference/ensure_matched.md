# Assert that every key occurs in a reference register

Reports rows of `data` whose key does not occur in `reference`.
Duplicate reference keys do not multiply rows; use
[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md)
separately if the reference must also be unique. Only the direction from
`data` to `reference` is checked. Missing key components never match by
default.

## Usage

``` r
ensure_matched(
  data,
  reference,
  by,
  na_matches = c("never", "na"),
  success_msg = NULL,
  warn_msg = NULL,
  abort_msg = NULL
)
```

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- reference:

  A reference data frame or database/Arrow table. For database input, a
  local reference is sent as an inline query; remote references must be
  on the same connection. Local input requires a local reference. No
  table is written to the database.

- by:

  Character vector of key columns, optionally named to map names in
  `data` to names in `reference`, e.g. `c(cpr = "person_id")`. Required:
  no implicit natural join is performed.

- na_matches:

  `"never"` (default), or `"na"` to match missing keys.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message when unmatched rows are found.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged. Failures carry unmatched input rows.

## See also

[`describe_match()`](https://dataniel.github.io/inshape/reference/describe_match.md)
to look at the match from both sides first,
[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md),
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
income <- data.frame(cpr = c("a", "b"), year = 2024)
population <- data.frame(cpr = "a", year = 2024)
ensure_matched(income, population, by = c("cpr", "year"))
#> Warning: Keys missing from the reference: cpr, year
#> ℹ 1 row found:
#>     cpr    year
#>     <chr> <dbl>
#>   1 b      2024
```
