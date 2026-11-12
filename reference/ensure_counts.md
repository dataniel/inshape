# Assert how many rows of each role a group has

A checkpoint for the composition of groups: a family has exactly one
reference person and at most two adults, a child has at most two
parents, a person dies at most once. The groups that break a limit are
reported, with every row of the group and a `broken` column naming the
limits broken, such as `"reference: 0 (needs 1)"`. Returns `data`, so it
can sit in the middle of a pipeline.

## Usage

``` r
ensure_counts(
  data,
  group,
  role = NULL,
  limits,
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

- group:

  Column(s) identifying the group (tidy-select), e.g. `c(family, year)`.

- role:

  The role column (one column), or `NULL` to count rows.

- limits:

  A named list of limits per role, or without `role` a single limit: a
  number, or the least and the most as two numbers.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when a group breaks a limit and no `abort_msg` is set.
  Defaults to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Value

`data` invisibly, unchanged.

## Details

Give the limits per role as a list,
`list(reference = 1, adult = c(1, 2))`: one number for an exact count,
two for the least and the most, with `Inf` for no upper limit. A group
with no row of a role has 0 of it, so a family without a reference
person breaks `reference = 1`. Roles not named are not limited. Without
`role`, `limits` is one such number or pair, for the number of rows per
group.

The same check covers relations and events: rows per child in a table of
parents (`limits = c(0, 2)`), and deaths per person in a table of events
(`role = event, limits = list(death = c(0, 1))`). To check a composition
per family type, such as single parents with one adult, run it on the
families of that type.

## See also

[`describe_groups()`](https://dataniel.github.io/inshape/reference/describe_groups.md)
to see the compositions first,
[`ensure_references()`](https://dataniel.github.io/inshape/reference/ensure_references.md),
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

## Examples

``` r
families <- data.frame(
  family = c(1, 1, 1, 2, 2, 3, 4, 4),
  role   = c("reference", "partner", "child", "reference", "child",
             "child", "reference", "reference")
)
ensure_counts(families, family, role,
              limits = list(reference = 1, partner = c(0, 1)))
#> Warning: Outside the limits: role per family
#> ℹ 3 rows
#>   In 2 groups
#>   reference: 0 (needs 1) in 1 group
#>   reference: 2 (needs 1) in 1 group
#> ℹ The rows:
#>     family role      broken
#>      <dbl> <chr>     <chr>
#>   1      3 child     reference: 0 (needs 1)
#>   2      4 reference reference: 2 (needs 1)
#>   3      4 reference reference: 2 (needs 1)

# At most two parents per child
parents <- data.frame(child = c("a", "a", "b", "b", "b"),
                      parent = c("m", "f", "m", "f", "x"))
ensure_counts(parents, child, limits = c(0, 2))
#> Warning: Outside the limits: rows per child
#> ℹ 3 rows
#>   In 1 group
#>   rows: 3 (needs at most 2) in 1 group
#> ℹ The rows:
#>     child broken                    parent
#>     <chr> <chr>                     <chr>
#>   1 b     rows: 3 (needs at most 2) m
#>   2 b     rows: 3 (needs at most 2) f
#>   3 b     rows: 3 (needs at most 2) x
```
