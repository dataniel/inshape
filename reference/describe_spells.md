# Describe the structure of spell data

Spell data, one row per spell with a start and an end, is where register
data is most often subtly wrong: spells that overlap, a transfer
recorded as two spells, a spell that ends before it starts, a spell that
never ends. `describe_spells()` counts all of it in one pass and judges
nothing; require what should hold with
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md).

## Usage

``` r
describe_spells(data, id, start, end)
```

## Arguments

- data:

  A data frame or tibble with one row per spell, or a database or Arrow
  table: see *Database tables* in
  [checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

- id:

  Column(s) identifying the unit (tidy-select), e.g. `cpr`.

- start, end:

  Columns with the first and last day (or period) of each spell. A
  missing `end` means an ongoing spell.

## Value

An object of class `inshape_spells`, printed as a summary. It is a list
with the counts `n_rows`, `n_spells` (usable spells), `n_units`,
`n_missing_start`, `n_end_before_start`, `n_ongoing`, `n_single` (spells
of one day or period) and `n_units_overlapping` (units with a touching,
overlapping, nested or duplicate spell), and the tibbles `relations`
(`relation`, `spells`), `gaps` and `lengths` (summaries of gap and spell
lengths), `spells_per_unit` (`spells`, `units`) and `by_year` (`year`,
`starts`, `ends`; by value for whole numbers).

## Details

### How each spell relates to the earlier ones

Within a unit, spells are taken in order of start, and each is compared
with the latest end among the unit's earlier spells:

- `gap`: it starts after a gap. The gap lengths are summarised.

- `adjacent`: it starts the day (or period) after an earlier spell ends.
  Two adjacent spells are often one spell recorded twice, e.g. a
  transfer between wards or employers, and may need merging with
  [`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md)
  before spells are counted.

- `touching`: it starts on the day an earlier spell ends. Spells are
  closed intervals, so the two share that day and overlap by one day,
  the usual way a discharge and a readmission on the same day look.

- `overlapping`: it starts inside an earlier spell and ends after it.

- `nested`: it lies entirely within an earlier spell, or starts after an
  ongoing one.

- `duplicate`: it has the same start and end as the spell before it.

Spells with the same start are taken longest first, so a shorter one is
`nested` in the longer. A missing end means an ongoing spell. Spells
with a missing start, or an end before the start, are counted and left
out of the rest.

`start` and `end` may be dates, compared by day, or whole numbers such
as years or month numbers, compared by that unit.

## Why it is fast

Units are compressed to integer ids by the compiled engine, the spells
are sorted once by data.table's multi-threaded radix sort, and one
compiled pass then relates each spell to the earlier ones, reading
memory in order. Counts and lengths are read from counts per day, never
from sorting millions of values.

## See also

[`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md)
to merge adjacent and overlapping spells,
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md)
to require spells not to overlap,
[`ensure_no_gaps()`](https://dataniel.github.io/inshape/reference/ensure_no_gaps.md)
to require that they leave no gaps,
[`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md)
to turn spells into a panel.

## Examples

``` r
admissions <- data.frame(
  cpr   = c("a", "a", "a", "b", "b", "c"),
  start = as.Date(c("2020-01-01", "2020-01-11", "2020-03-01",
                    "2020-01-01", "2020-01-05", "2021-06-01")),
  end   = as.Date(c("2020-01-10", "2020-01-20", "2020-03-05",
                    "2020-01-31", "2020-01-10", NA))
)
# a: a transfer on 11 January, then a gap; b: a nested spell; c: ongoing
describe_spells(admissions, cpr, start, end)
#> ── Spells: start to end per cpr ────────────────────────────────────────────────
#> 6 rows, 6 usable spells, 3 units
#> 
#> • Ongoing (no end): 1
#> • Units with overlapping spells: 1 (33.3%)
#> 
#> Relation to the unit's earlier spells:
#>     relation    spells
#>   1 gap              1
#>   2 adjacent         1
#>   3 touching         0
#>   4 overlapping      0
#>   5 nested           1
#>   6 duplicate        0
#> 
#> Gaps between spells, in days:
#>         n   min   q25 median  mean   q75   max
#>   1     1    40    40     40    40    40    40
#> 
#> Length of ended spells, in days:
#>         n   min   q25 median  mean   q75   max
#>   1     5     5     6     10  12.4    10    31
```
