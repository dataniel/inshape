# Merge spells that follow each other or overlap into one

A stay in hospital moved between wards, a job continued with a new
contract, an address re-registered the day after: registers often record
one spell as several, back to back or overlapping, and every count of
spells, lengths and transitions is wrong until they are merged.
[`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md)
shows how often it happens; `merge_spells()` does the merging, one row
per merged spell.

## Usage

``` r
merge_spells(data, id, start, end, by = NULL, max_gap = 0)
```

## Arguments

- data:

  A data frame or tibble with one row per spell.

- id:

  Column(s) identifying the unit (tidy-select), e.g. `cpr`.

- start, end:

  Columns with the first and last day (or period) of each spell. A
  missing `end` means an ongoing spell.

- by:

  Optional column(s) (tidy-select) that must be equal for spells to be
  merged, e.g. `employer`.

- max_gap:

  Largest number of days (or periods) between two spells that are still
  merged: `0` merges spells that follow the next day, `-1` only spells
  that share a day. A whole number from -1.

## Value

A tibble (a data.table if `data` is one) with the `id` and `by` columns,
`start`, `end` and `n_spells`, one row per merged spell. Units come in
the order they first appear in `data`, and each unit's spells by start;
use
[`dplyr::arrange()`](https://dplyr.tidyverse.org/reference/arrange.html)
to sort by the id columns.

## Details

### When spells are merged

Within a unit, spells are taken in order of start, and a spell is merged
into the one before when the number of days between them, from the
latest end so far to its start, is at most `max_gap`:

- `max_gap = 0` (default) merges spells that overlap, share a day, or
  where one starts the day after the other ends: the transfers.

- `max_gap = -1` merges only spells that share at least one day, and
  keeps transfers apart.

- `max_gap = 30` also merges spells less than a month apart, e.g. a
  readmission within 30 days counted as the same episode.

The merged spell runs from the first start to the latest end, and is
ongoing (missing end) if any of its spells is. Use `by` to merge only
spells that agree in a column, e.g. the employer or the status, so a job
followed directly by unemployment stays two spells: spells are then
grouped by the `id` and `by` columns together.

Columns other than `id`, `by`, `start` and `end` are dropped, as one
merged spell may have several values for them; `n_spells` counts the
spells merged into each row. Rows with a missing start or an end before
the start are dropped with a message, as in
[`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md).

`start` and `end` may be dates or whole numbers (years, month numbers),
compared by that unit.

## Why it is fast

It shares the compiled pass of
[`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md):
units are compressed to integer ids (see
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md)),
spells are sorted once by data.table's radix sort, and one sequential
pass relates each spell to the earlier ones. The result is not sorted by
the id columns, which on a population register means sorting millions of
strings and would take most of the time; units keep the order of the
data, which for an extract sorted by cpr is the same.

## See also

[`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md)
to see how many spells follow each other or overlap,
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md)
to require that none overlap.

## Examples

``` r
admissions <- data.frame(
  cpr   = c("a", "a", "a", "b", "b"),
  start = as.Date(c("2020-01-01", "2020-01-11", "2020-03-01",
                    "2020-01-01", "2020-01-05")),
  end   = as.Date(c("2020-01-10", "2020-01-20", "2020-03-05",
                    "2020-01-31", "2020-01-10")),
  ward  = c("A", "B", "A", "A", "C")
)
# a is moved from ward A to B on 11 January: one stay, then a new one
merge_spells(admissions, cpr, start, end)
#> # A tibble: 3 × 4
#>   cpr   start      end        n_spells
#>   <chr> <date>     <date>        <int>
#> 1 a     2020-01-01 2020-01-20        2
#> 2 a     2020-03-01 2020-03-05        1
#> 3 b     2020-01-01 2020-01-31        2

# Readmissions within 60 days count as the same episode
merge_spells(admissions, cpr, start, end, max_gap = 60)
#> # A tibble: 2 × 4
#>   cpr   start      end        n_spells
#>   <chr> <date>     <date>        <int>
#> 1 a     2020-01-01 2020-03-05        3
#> 2 b     2020-01-01 2020-01-31        2

# Only stays in the same ward
merge_spells(admissions, cpr, start, end, by = ward)
#> # A tibble: 5 × 5
#>   cpr   ward  start      end        n_spells
#>   <chr> <chr> <date>     <date>        <int>
#> 1 a     A     2020-01-01 2020-01-10        1
#> 2 a     A     2020-03-01 2020-03-05        1
#> 3 a     B     2020-01-11 2020-01-20        1
#> 4 b     A     2020-01-01 2020-01-31        1
#> 5 b     C     2020-01-05 2020-01-10        1
```
