# Assert that rows pointing to other rows find them, and agree

A checkpoint for a column that points to another row of the same table:
a spouse's cpr, a mother's cpr, the reference person of a family. Each
reference must find its row, must not point to its own row, and with
`mutual = TRUE` the row it finds must point back, as spouses do. With
`same`, the row it finds must agree on those columns, such as the family
a spouse belongs to. The rows that break a rule are reported, with a
`problem` column saying which. Returns `data`, so it can sit in the
middle of a pipeline.

## Usage

``` r
ensure_references(
  data,
  id,
  ref,
  within = NULL,
  same = NULL,
  mutual = FALSE,
  success_msg = NULL,
  warn_msg = NULL,
  abort_msg = NULL
)
```

## Arguments

- data:

  A data frame or tibble, or a database or Arrow table: see *Database
  and Arrow tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- id:

  The column identifying each row (one column), e.g. `cpr`.

- ref:

  The column pointing to another row's `id` (one column), e.g. `spouse`.

- within:

  Columns the row pointed to must share to be found (tidy-select), e.g.
  `year`, or `NULL` (default).

- same:

  Columns the row pointed to must agree on once found (tidy-select),
  e.g. `family`, or `NULL` (default).

- mutual:

  If `TRUE`, the row pointed to must point back. Default `FALSE`.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when a reference breaks a rule and no `abort_msg` is
  set. Defaults to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

In a panel a person has a row per year, and a reference should find the
row of the same year: give the period in `within`, and the row is looked
up among the rows with the same values there. `id` must be unique within
`within`; check it with
[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md)
first. A missing reference is no reference, and passes.

Rules about the row a reference finds, such as a mother older than her
child, are written by joining its columns on and stating the rule with
[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md):

    persons |>
      dplyr::left_join(dplyr::select(persons, mother = cpr, mother_born = born),
                       by = "mother") |>
      ensure_none(mother_born >= born)

## See also

[`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md)
for references to another table,
[`ensure_counts()`](https://dataniel.github.io/inshape/reference/ensure_counts.md),
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
persons <- data.frame(
  cpr    = c("a", "b", "c", "d", "e"),
  spouse = c("b", "a", "d", "e", "x"),
  family = c(1, 1, 2, 3, 3)
)
# c points to d, who points to e; e points to x, who is not there; c and
# d are in different families
ensure_references(persons, cpr, spouse, same = family, mutual = TRUE)
#> Warning: Broken references: spouse to cpr
#> ℹ 3 rows in 3 groups
#>   Problems: does not point back (1), in another family (1), not found (1)
#> ℹ The rows:
#>     problem             cpr   spouse family
#>     <chr>               <chr> <chr>   <dbl>
#>   1 in another family   c     d           2
#>   2 does not point back d     e           3
#>   3 not found           e     x           3
```
