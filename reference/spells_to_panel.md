# Turn spell data into a period panel with primo and ultimo status

Spell data has one row per spell: an education, an address, a benefit
period, with a start date, an end date and a status. Most analyses need
it as a panel instead: one row per unit and year (or quarter, or month),
with the status at the start and at the end of the period.
`spells_to_panel()` does that conversion.

## Usage

``` r
spells_to_panel(
  data,
  id,
  start,
  end,
  status,
  by = c("year", "quarter", "month"),
  from = NULL,
  to = NULL,
  status_is = c("state", "outcome"),
  ongoing = "ongoing",
  primo = c("previous_ultimo", "first_day")
)
```

## Arguments

- data:

  A data frame or tibble with one row per spell.

- id:

  Column(s) identifying the unit (tidy-select), e.g. `cpr`.

- start, end:

  Columns with the first and last day of each spell (Date). A missing
  `end` means an ongoing spell.

- status:

  Column with the status of each spell.

- by:

  Period length: `"year"`, `"quarter"` or `"month"`.

- from, to:

  First and last period in the panel, as a year (e.g. `2015`) or a Date
  in the period. When given, every unit gets the same window, which
  makes a balanced panel. When `NULL`, each unit runs from the period of
  its first start to the period of its last end; ongoing spells run to
  the latest date found in `start` and `end`.

- status_is:

  `"state"` or `"outcome"`, see Details.

- ongoing:

  Status shown while a spell is running when `status_is = "outcome"`,
  e.g. `"i gang"`.

- primo:

  `"previous_ultimo"` (default) or `"first_day"`.

## Value

A tibble (a data.table if `data` is one) with the `id` columns, `year`,
`quarter` or `month` for sub-year periods, and `primo` and `ultimo`.
Rows are sorted by unit and period.

## Details

Two meanings of status are supported, because registers use both:

- `status_is = "state"` (default): the status holds for the whole spell,
  e.g. enrolled, on leave. The status at a point is the status of the
  spell covering it, and `NA` if no spell does. Spells are closed
  intervals, as in
  [`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md).

- `status_is = "outcome"`: the status is what happened when the spell
  ended, e.g. passed or dropped out, as in education registers. While a
  spell is running (start \<= point \< end, or no end) the status is
  `ongoing`. From the end date on, the outcome of the most recently
  ended spell is carried forward until a new spell starts.

Primo follows the register convention: by default primo of a period is
the last day of the previous period (31 December for years), so primo of
one year equals ultimo of the year before. Use `primo = "first_day"` for
1 January.

If spells overlap, the spell with the latest start decides the status.
In state mode, a message counts the points where this happened; find the
spells with
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md).
Rows with a missing start, or an end before the start, are dropped with
a message.

## Why it is fast

Dates are converted to integer days, and spells are sorted once per unit
by start. A compiled pass keeps the running maximum of end dates within
a unit, so "is a spell running at this point?" and "which spell ended
most recently?" are constant-time lookups. Spells are never expanded to
days or periods, so the cost is one sort plus a linear pass over spells
and output rows.

## See also

[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md)
to check spells first,
[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
to check the resulting panel.

## Examples

``` r
education <- data.frame(
  cpr    = c("a", "a", "b"),
  start  = as.Date(c("2018-08-15", "2021-08-15", "2019-08-15")),
  end    = as.Date(c("2021-06-20", NA,           "2020-03-01")),
  status = c("passed", "in progress", "dropped out")
)

# status describes the outcome at the end of each spell
spells_to_panel(education, cpr, start, end, status,
                from = 2018, to = 2022,
                status_is = "outcome", ongoing = "in progress")
#> # A tibble: 10 × 4
#>    cpr    year primo       ultimo     
#>    <chr> <int> <chr>       <chr>      
#>  1 a      2018 NA          in progress
#>  2 a      2019 in progress in progress
#>  3 a      2020 in progress in progress
#>  4 a      2021 in progress in progress
#>  5 a      2022 in progress in progress
#>  6 b      2018 NA          NA         
#>  7 b      2019 NA          in progress
#>  8 b      2020 in progress dropped out
#>  9 b      2021 dropped out dropped out
#> 10 b      2022 dropped out dropped out

# status holds during the spell
leave <- data.frame(
  cpr    = "a",
  start  = as.Date(c("2020-01-01", "2020-09-01")),
  end    = as.Date(c("2020-08-31", "2021-03-31")),
  status = c("enrolled", "on leave")
)
spells_to_panel(leave, cpr, start, end, status, by = "quarter")
#> # A tibble: 5 × 5
#>   cpr    year quarter primo    ultimo  
#>   <chr> <int>   <int> <chr>    <chr>   
#> 1 a      2020       1 NA       enrolled
#> 2 a      2020       2 enrolled enrolled
#> 3 a      2020       3 enrolled on leave
#> 4 a      2020       4 on leave on leave
#> 5 a      2021       1 on leave on leave
```
