# Describe how the keys of two tables match

Before a join, the question is what it will do: how many keys are in
both tables, how many rows will find no match, and whether the other
table repeats a key and so multiplies rows. `describe_match()` counts
the keys found in both tables, only in `data` and only in `reference`,
with the rows they stand for, and says how many rows a left join of
`data` to `reference` returns. It judges nothing; require a match with
[`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md).

## Usage

``` r
describe_match(data, reference, by)
```

## Arguments

- data:

  A data frame or tibble, or a database or Arrow table: see *Database
  tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- reference:

  A reference data frame or database/Arrow table. For database input, a
  local reference is sent as an inline query; remote references must be
  on the same connection. Local input requires a local reference. No
  table is written to the database.

- by:

  Character vector of key columns, optionally named to map names in
  `data` to names in `reference`, e.g. `c(cpr = "person_id")`. Required:
  no implicit natural join is performed.

## Value

An object of class `inshape_match`, printed as a summary. It is a list
with `by` (the key columns of `reference`, named by those of `data`),
the counts `n_rows` and `n_ref_rows`, `n_missing` and `n_ref_missing`
(rows with a missing key), `n_ref_dup_keys` (keys occurring more than
once in `reference`) and `n_join_rows` (the rows of a left join of
`data` to `reference`), and a tibble `keys` with one row for each of
`"in both"`, `"only in data"` and `"only in reference"`: `keys`
(distinct keys), `rows` (the rows of `data` with those keys) and
`ref_rows` (the rows of `reference`).

## Details

A key with a missing value in any of its columns matches nothing, as
with `na_matches = "never"` in
[`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md):
those rows are counted on their own and kept out of the keys. A left
join keeps each of them once.

Key columns are compared as they are. An integer and a double column
match, and so do a factor and a character column; other pairs of
different types, such as a number against text, stop with an error
rather than match nothing. In a database the comparison is the
database's own: DuckDB refuses a number against text as well, with its
own error.

## See also

[`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md)
to require that every key is found and see the rows,
[`describe_key()`](https://dataniel.github.io/inshape/reference/describe_key.md)
for the duplicated keys of one table,
[`describe_changes()`](https://dataniel.github.io/inshape/reference/describe_changes.md)
to compare two extracts of the same register.

## Examples

``` r
income <- data.frame(
  cpr    = c("a", "a", "b", "c", NA),
  year   = c(2023, 2024, 2024, 2024, 2024),
  income = c(10, 12, 7, 9, 3)
)
persons <- data.frame(
  person_id = c("a", "b", "b", "d"),
  kommune   = c("955", "956", "957", "960")
)
# c is not in the register, d has no income, and b is there twice, so
# the join returns one row more than income has
describe_match(income, persons, by = c(cpr = "person_id"))
#> ── Match: cpr = person_id ──────────────────────────────────────────────────────
#> data: 5 rows, reference: 4 rows
#> 
#> ⚠ Rows of data without a match: 2 (40.0%), 1 of them with a missing key
#> ⚠ Keys repeated in the reference: 1; a left join returns 6 rows, 1 more than data
#> 
#> Keys:
#>     found              keys  rows ref_rows
#>   1 in both               2     3        3
#>   2 only in data          1     1        0
#>   3 only in reference     1     0        1
```
