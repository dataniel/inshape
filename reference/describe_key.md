# Describe how well columns work as a key

A key should identify each row. When it does not, the next question is
what the duplicates are: exact copies of a row, which can simply be
dropped, or rows that disagree, which need a rule. `describe_key()`
counts the duplicated keys and how many copies each has, separates exact
copies from conflicts, and names the columns the conflicting copies
disagree in. It judges nothing; require a key with
[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md).

## Usage

``` r
describe_key(data, ...)
```

## Arguments

- data:

  A data frame or tibble, or a database or Arrow table: see *Database
  tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- ...:

  Key columns (tidy-select). If omitted, all columns are used, which
  counts fully duplicated rows.

## Value

An object of class `inshape_key`, printed as a summary. It is a list
with `key` (the column names), the counts `n_rows`, `n_keys` (distinct
keys), `n_dup_keys`, `n_dup_rows` (rows sharing a key) and `n_exact`
(duplicated keys whose copies are identical in every column), and three
tibbles: `copies` (`copies`, `keys`), `conflicts` (`column`, `keys`: the
duplicated keys whose copies differ in that column, most first) and
`missing` (`column`, `rows`).

## Details

Two copies disagree in a column when their values differ there; a
missing value and a present one differ, two missing values do not. Key
columns with missing values are counted, since a missing value in a key
is usually an error of its own, even when the key is unique.

## See also

[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md)
to require a unique key and see the rows,
[`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md)
for unit-periods.

## Examples

``` r
firms <- data.frame(
  cvr      = c("1", "1", "2", "2", "3"),
  year     = c(2024, 2024, 2024, 2024, 2024),
  industry = c("A", "A", "B", "C", "A"),
  income   = c(10, 10, 5, 5, 7)
)
# cvr 1 is an exact copy; cvr 2 disagrees on the industry
describe_key(firms, cvr, year)
#> ── Key: cvr, year ──────────────────────────────────────────────────────────────
#> 5 rows, 3 distinct keys
#> 
#> ⚠ Duplicated keys: 2 (4 rows, 2 extra rows)
#> ⚠ Copies differ in: industry (1)
#> • Exact copies, identical in every column: 1 of 2 keys
#> • Copies per duplicated key: 2 (2)
```
