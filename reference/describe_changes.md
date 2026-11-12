# Describe what changed between two extracts of a register

A register is delivered again and again, and each delivery should differ
from the last only where the world did: new persons, new years. When the
same person-year has another birth date, sex or municipality than last
time, a correction was made, and in the Greenlandic and Danish CPR,
corrections have no time limit. `describe_changes()` compares two
extracts by their key and counts the keys that came and went, the
columns that came, went or changed type, and for every column the keys
whose value changed, went missing or was filled in. It judges nothing.

## Usage

``` r
describe_changes(old, new, ...)
```

## Arguments

- old, new:

  The earlier and the later extract: data frames, or two database tables
  on the same connection (see *Database tables*).

- ...:

  Key columns (tidy-select), e.g. `cpr, year`, present in both.

## Value

An object of class `inshape_changes`, printed as a summary. It is a list
with the counts `n_old`, `n_new`, `n_kept` (keys in both), `n_added`,
`n_removed` and `n_changed` (kept keys with any changed column);
`columns_added`, `columns_removed` and `type_changed` (column names);
`columns_skipped` (shared columns not compared); `columns`, a tibble
with one row per compared shared column: `column`, `changed` (another
value), `went_missing` (a value, now missing), `filled_in` (missing, now
a value) and `share` (of the kept keys with any of the three), most
changed first; and `added` and `removed` (the keys) and `changed` (the
keys with `n_columns`, the number of columns that changed).

## Details

Both extracts must be unique on the key; check with
[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md)
or
[`describe_key()`](https://dataniel.github.io/inshape/reference/describe_key.md)
first. Two missing values are equal. A column whose type changed, e.g.
from integer to character, is compared as text, and integer and double
columns as numbers. Shared non-key list or matrix columns are not
compared. Their names are returned in `columns_skipped` and shown when
the summary is printed.

## Why it is fast

The keys of both extracts are compressed to integer ids together, by the
compiled engine, so matching a row to its row in the other extract is an
array lookup, with no join or sort. Each shared column is then compared
in one compiled pass over the matched rows.

## Database tables

Two dbplyr tables on the same connection, such as two DuckDB tables or
two Parquet files read through DuckDB, are compared in the database: the
counts are fetched, and `added`, `removed` and `changed` stay queries,
to
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
when needed.

## See also

[`describe_key()`](https://dataniel.github.io/inshape/reference/describe_key.md)
to check the key first.

## Examples

``` r
old <- data.frame(cpr = c("a", "b", "c"), year = 2023,
                  sex = c("F", "M", "F"), born = c(1950, 1960, NA))
new <- data.frame(cpr = c("a", "b", "d"), year = 2023,
                  sex = c("F", "F", "M"), born = c(1950, 1960, 1990))
# c is gone, d is new, and b changed sex
describe_changes(old, new, cpr, year)
#> ── Changes by cpr, year ────────────────────────────────────────────────────────
#> 3 rows before, 3 rows now, 2 keys in both
#> 
#> ✔ The same columns, with the same types
#> • New keys: 1 (33.3%)
#> • Keys gone: 1 (33.3%)
#> • Keys with a changed value: 1 (50.0%)
#> 
#> Changes per column, among the keys in both:
#>     column changed went_missing filled_in share 
#>   1 sex          1            0         0 50.00%
#>   2 born         0            0         0 0.00% 
```
