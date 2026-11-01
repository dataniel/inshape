# Add status from spell data to a panel you already have

[`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md)
builds a panel from spells. Often the panel already exists, e.g. a
population with one row per person and year, or events with a date, and
the spell data should only add a status to it: was the person enrolled
at the end of the year, on leave on the day of the diagnosis?
`add_spell_status()` looks up the spell covering each row's point in
time and adds its status as new column(s).

## Usage

``` r
add_spell_status(
  data,
  spells,
  id,
  at,
  start,
  end,
  status,
  by = c("year", "quarter", "month"),
  when = c("both", "primo", "ultimo"),
  status_is = c("state", "outcome"),
  ongoing = "ongoing",
  primo = c("previous_ultimo", "first_day"),
  overlap = c("latest_start", "error"),
  name = NULL
)
```

## Arguments

- data:

  A data frame or tibble, e.g. a panel with one row per unit and period.
  Its rows and columns are kept as they are.

- spells:

  A data frame with one row per spell.

- id:

  Column(s) identifying the unit (tidy-select, in `data`), e.g. `cpr`.
  `spells` must have columns of the same names; rename first if not.

- at:

  Column(s) in `data` with the point in time: a Date column, or a year
  column, or a year and a quarter/month column. See Details.

- start, end, status:

  Columns in `spells`, as in
  [`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md).

- by:

  Period of `at` when it is not a date: `"year"`, `"quarter"` or
  `"month"`. Ignored for a Date `at`.

- when:

  For periods: `"both"` (default) adds a primo and an ultimo column,
  `"primo"` or `"ultimo"` adds one. Ignored for a Date `at`.

- status_is, ongoing, primo:

  As in
  [`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md).

- overlap:

  `"latest_start"` (default) or `"error"`. Only state mode checks
  overlaps; in outcome mode the most recently ended spell decides.

- name:

  Name of the new column. Defaults to the name of `status`, with
  `_primo` and `_ultimo` appended for periods. With `when = "both"`,
  `name` is the prefix for the two columns.

## Value

`data` with the new column(s) added at the end, same class.

## Details

It exists because an interval join, e.g.
[`dplyr::left_join()`](https://dplyr.tidyverse.org/reference/mutate-joins.html)
with `join_by(between())`, goes wrong exactly where register data is
messy: overlapping spells duplicate panel rows silently, an ongoing
spell with a missing end matches nothing, and an outcome (passed,
dropped out) cannot be carried forward. Here the rows of `data` are
never added, dropped or reordered, and the rules are those of
[`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md):
on a yearly panel, `add_spell_status(panel, spells, cpr, year, ...)`
gives the same primo and ultimo status as
[`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md)
joined on `cpr` and `year`.

The point in time comes from `at`:

- A **Date** column: the status on that day, one new column.

- A **year** column (with `by = "year"`), or a year and a quarter or
  month column (with `by = "quarter"` or `"month"`): the status at primo
  and/or ultimo of the period, chosen with `when`. Primo follows
  `primo`, as in
  [`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md).

`status_is`, `ongoing` and the treatment of overlapping spells are as in
[`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md):
the latest start wins, with a message counting the points where this
happened. Use `overlap = "error"` to stop instead, e.g. in a pipeline
that must fail hard. Rows whose unit has no spells, or whose point is
missing, get `NA`. Spells with a missing start, or an end before the
start, are dropped with a message.

## See also

[`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md)
to build the panel from the spells,
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md)
to check the spells first.

## Examples

``` r
education <- data.frame(
  cpr    = c("a", "a", "b"),
  start  = as.Date(c("2018-08-15", "2021-08-15", "2019-08-15")),
  end    = as.Date(c("2021-06-20", NA,           "2020-03-01")),
  status = c("passed", "in progress", "dropped out")
)
population <- data.frame(cpr = c("a", "a", "b", "c"),
                         year = c(2020, 2021, 2020, 2020))

# primo and ultimo status for each person and year
add_spell_status(population, education, cpr, year, start, end, status,
                 status_is = "outcome", ongoing = "in progress")
#>   cpr year status_primo status_ultimo
#> 1   a 2020  in progress   in progress
#> 2   a 2021  in progress   in progress
#> 3   b 2020  in progress   dropped out
#> 4   c 2020         <NA>          <NA>

# status on the day of an event
events <- data.frame(cpr = c("a", "b"),
                     date = as.Date(c("2019-05-01", "2021-01-01")))
add_spell_status(events, education, cpr, date, start, end, status,
                 status_is = "outcome", ongoing = "in progress",
                 name = "education")
#>   cpr       date   education
#> 1   a 2019-05-01 in progress
#> 2   b 2021-01-01 dropped out
```
