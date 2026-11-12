# Describe how groups are composed of roles

A family, a household or a workplace is a group of rows, and each row
has a role in it: reference person, partner, child. The composition of a
group is how many of each role it has, and `describe_groups()` counts
the groups with each composition: "1 reference + 1 partner + 2 child:
4,210", "1 child: 12". Like the transition table of
[`describe_transitions()`](https://dataniel.github.io/inshape/reference/describe_transitions.md)
it is the diagnosis itself: the impossible groups show before any rule
is written. Require a composition with
[`ensure_counts()`](https://dataniel.github.io/inshape/reference/ensure_counts.md).

## Usage

``` r
describe_groups(data, group, role)
```

## Arguments

- data:

  A data frame or tibble, or a database or Arrow table: see *Database
  and Arrow tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- group:

  Column(s) identifying the group (tidy-select), e.g. `c(family, year)`.

- role:

  The role column (one column), e.g. `role`.

## Value

An object of class `inshape_groups`, printed as a summary. It is a list
with `group`, `role`, the counts `n_rows` and `n_groups`, `roles` (the
roles, as text) and `compositions`, a tibble with one column per role
holding its count, `composition` (the same as text) and `groups`, most
common first.

## Details

The group is what the `group` columns say: a family id, or a family id
and a year for families over time. A missing role is a role of its own,
shown as `NA`.

## See also

[`ensure_counts()`](https://dataniel.github.io/inshape/reference/ensure_counts.md)
to require a composition,
[`ensure_references()`](https://dataniel.github.io/inshape/reference/ensure_references.md)
for rows that point to each other.

## Examples

``` r
families <- data.frame(
  family = c(1, 1, 1, 2, 2, 3, 4, 4),
  role   = c("reference", "partner", "child", "reference", "child",
             "child", "reference", "reference")
)
# family 3 has no reference person, family 4 has two
describe_groups(families, family, role)
#> ── Groups: family by role ──────────────────────────────────────────────────────
#> 8 rows, 4 groups, 3 roles
#> 
#> • Compositions: 4
#> 
#> Most common compositions:
#>     composition                       groups share
#>   1 1 child                                1 25.0%
#>   2 1 child + 1 partner + 1 reference      1 25.0%
#>   3 1 child + 1 reference                  1 25.0%
#>   4 2 reference                            1 25.0%
```
