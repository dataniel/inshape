# Get started with inshape

Register microdata comes in a few shapes: one row per unit, one row per
unit and period (a panel), or one row per spell with a start and an end.
Every analysis assumes the shape is right, and the errors that break it
are silent: a duplicated key multiplies rows in a join, a missing year
looks like an exit, an overlapping spell gives a person two addresses at
once.

inshape checks the shape before anything is built on it, in two steps.
The `describe_*()` functions look at the structure and judge nothing;
the `ensure_*()` functions are *checkpoints*: each states one rule,
warns or aborts with the rows that break it, and returns the data, so it
sits in a pipeline. Most rules are about structure;
[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md),
[`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md)
and
[`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md)
take any rule dplyr can express.

| Function | The rule | Returns |
|----|----|----|
| [`describe_key()`](https://dataniel.github.io/inshape/reference/describe_key.md) | (look) duplicated keys, exact copies vs. conflicts | a summary |
| [`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md) | (look) units, gaps, entries, exits, patterns | a summary |
| [`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md) | (look) gaps, transfers, overlapping and nested spells | a summary |
| [`describe_varying()`](https://dataniel.github.io/inshape/reference/describe_varying.md) | (look) which columns vary within units | a summary |
| [`describe_codes()`](https://dataniel.github.io/inshape/reference/describe_codes.md) | (look) how the codes of a column change over periods | a summary |
| [`describe_changes()`](https://dataniel.github.io/inshape/reference/describe_changes.md) | (look) what changed between two extracts | a summary |
| [`describe_match()`](https://dataniel.github.io/inshape/reference/describe_match.md) | (look) what a join of two tables will do | a summary |
| [`ensure_codes()`](https://dataniel.github.io/inshape/reference/ensure_codes.md) | a coded column holds only codes from the code list | the data |
| [`ensure_complete()`](https://dataniel.github.io/inshape/reference/ensure_complete.md) | the columns named have no missing values | the data |
| [`ensure_constant()`](https://dataniel.github.io/inshape/reference/ensure_constant.md) | sex, birth date and the like are constant within a unit | the data |
| [`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md) | the key columns identify each row | the data |
| [`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md) | every unit is observed in every period, or has no gaps | the data |
| [`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md) | a unit’s spells do not overlap | the data |
| [`ensure_no_gaps()`](https://dataniel.github.io/inshape/reference/ensure_no_gaps.md) | a unit’s spells leave no gaps between them | the data |
| [`ensure_within()`](https://dataniel.github.io/inshape/reference/ensure_within.md) | no rows after death or emigration, or before birth | the data |
| [`ensure_valid_spells()`](https://dataniel.github.io/inshape/reference/ensure_valid_spells.md) | a spell has a start and does not end before it | the data |
| [`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md) | every key occurs in a reference register | the data |
| [`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md) | no row matches a condition (`NA` passes) | the data |
| [`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md) | every row meets a condition (`NA` fails) | the data |
| [`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md) | a violation set you built yourself has no rows | the set |
| [`tally_violations()`](https://dataniel.github.io/inshape/reference/tally_violations.md) | (count) violations for many rules at once | a tally |
| [`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md) | (conversion) spells recorded as several, merged | merged spells |
| [`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md) | (conversion) spells to a period panel | a panel |
| [`add_spell_status()`](https://dataniel.github.io/inshape/reference/add_spell_status.md) | (conversion) status from spells on an existing panel | the data plus status |

## Look first: `describe_panel()` and `describe_key()`

A rule is easier to choose when you have seen the data.
[`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md)
summarises a panel in one pass: how many units are observed throughout,
who enters and leaves when, where the gaps are, and which participation
patterns are common, as Stata’s `xtdescribe` does.

``` r
persons <- tibble(
  cpr  = c("a", "a", "a", "b", "b", "c", "d", "d", "d", "d"),
  year = c(2020, 2021, 2022, 2020, 2022, 2022, 2020, 2021, 2022, 2022)
)

describe_panel(persons, cpr, year)
#> ── Panel: cpr by year ──────────────────────────────────────────────────────────
#> 10 rows, 4 units, 3 periods, 2020-2022
#> 
#> • Observed in every period: 2 units (50.0%)
#> • With gaps: 1 unit (25.0%), 1 missing unit-period inside their span
#> • Duplicated unit-periods: 1 (1 extra row)
#> 
#> By period:
#>     period units entries exits  gaps
#>   1   2020     3      NA     0     0
#>   2   2021     2       0     0     1
#>   3   2022     4       1    NA     0
#> 
#> Most common patterns:
#>     pattern units share
#>   1 111         2 50.0%
#>   2 1.1         1 25.0%
#>   3 ..1         1 25.0%
```

A period with no units, or a sudden fall in `units`, is the sign of a
broken extract. The counts are there to use as well, e.g.
`describe_panel(persons, cpr, year)$by_period`.

[`describe_key()`](https://dataniel.github.io/inshape/reference/describe_key.md)
looks at a key. When it is not unique, the question is what the
duplicates are: exact copies, which can be dropped, or rows that
disagree, which need a rule. It tells them apart and names the columns
the copies disagree in:

``` r
firms <- tibble(
  cvr      = c("1", "1", "2", "2", "3"),
  year     = 2024,
  industry = c("A", "A", "B", "C", "A")
)

describe_key(firms, cvr, year)
#> ── Key: cvr, year ──────────────────────────────────────────────────────────────
#> 5 rows, 3 distinct keys
#> 
#> • Duplicated keys: 2 (4 rows, 2 extra rows)
#> • Exact copies, identical in every column: 1 of 2 keys
#> • Copies differ in: industry (1)
#> • Copies per duplicated key: 2 (2)
```

## Keys: `ensure_unique()`

Duplicate keys are the most common error in register data, and the most
costly one sits right before a join. A lookup table with a duplicated
key makes `left_join()` multiply rows without a word. Check the key
first:

``` r
df <- tibble(
  cvr  = c("11111111", "22222222", "11111111"),
  year = c(2024, 2024, 2024)
)

df |>
  ensure_unique(cvr, year, warn_msg = "Duplicate company-years")
#> Warning in ensure_unique(df, cvr, year, warn_msg = "Duplicate company-years"): Duplicate company-years
#> ℹ 2 rows in 1 group:
#>     dupid cvr       year
#>     <int> <chr>    <dbl>
#>   1     1 11111111  2024
#>   2     1 11111111  2024
```

The reported rows carry a `dupid`, so the copies in each group sit
together.

## Missing values: `ensure_complete()`

Some columns an analysis cannot do without: the id, the date, the
outcome. A missing value in them drops the row from a model without a
word, or becomes a group of its own in a count.
[`ensure_complete()`](https://dataniel.github.io/inshape/reference/ensure_complete.md)
requires the columns named to have a value in every row, or all columns
if none are named. The reported rows carry a `missing` column that names
the columns missing in each:

``` r
register <- tibble(
  cpr  = c("a", "b", NA, "d"),
  born = as.Date(c("1980-05-01", NA, NA, "1975-02-11")),
  sex  = c("F", "M", "F", NA)
)

ensure_complete(register, cpr, born)
#> Warning in ensure_complete(register, cpr, born): Missing values in: cpr, born
#> ℹ 2 rows in 2 groups:
#>     missing   cpr   born   sex
#>     <chr>     <chr> <date> <chr>
#>   1 born      b     NA     M
#>   2 cpr, born NA    NA     F
```

Missing means `NA`; an empty string is a value.

## Panels: `ensure_balanced()`

A yearly register extract is a panel: one row per person (or company)
and year. Whether it is *balanced*, every unit present in every year,
decides which methods are valid and often reveals a broken extract.

``` r
panel <- tibble(
  cpr  = c("a", "a", "a", "b", "b", "c"),
  year = c(2020, 2021, 2022, 2020, 2022, 2022)
)

ensure_balanced(panel, cpr, year)
#> Warning in ensure_balanced(panel, cpr, year): Panel is not balanced: missing cpr-year combinations
#> ℹ 3 rows found:
#>     cpr    year
#>     <chr> <dbl>
#>   1 b      2021
#>   2 c      2020
#>   3 c      2021
```

Real populations are rarely balanced. People are born, die and migrate.
What usually *should* hold is that a unit, once present, does not skip a
year before it leaves. `gaps_only = TRUE` checks that: `c` entering in
2022 is fine, `b` missing in 2021 is not.

``` r
ensure_balanced(panel, cpr, year, gaps_only = TRUE)
#> Warning in ensure_balanced(panel, cpr, year, gaps_only = TRUE): Gaps in panel: missing cpr-year combinations
#> ℹ 1 row found:
#>     cpr    year
#>     <chr> <dbl>
#>   1 b      2021
```

By default the expected years are those found in the data, so a year
that was never loaded goes unnoticed. State the years you expect to
catch that as well:

``` r
ensure_balanced(panel, cpr, year, periods = 2015:2024, gaps_only = TRUE)
```

## Spells: `ensure_no_overlap()`

The other shape of register data is spells: address periods, employment,
benefit periods. A person has only one address at a time, so overlapping
spells within a person are an error:

``` r
addresses <- tibble(
  cpr   = c("a", "a", "b", "b"),
  start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-06-01")),
  end   = as.Date(c("2020-12-31", NA,           "2020-06-30", "2021-12-31"))
)

ensure_no_overlap(addresses, cpr, start, end)
#> Warning in ensure_no_overlap(addresses, cpr, start, end): Overlapping spells per cpr
#> ℹ 2 rows in 1 group:
#>     overlap_id cpr   start      end
#>          <int> <chr> <date>     <date>
#>   1          1 b     2020-01-01 2020-06-30
#>   2          1 b     2020-06-01 2021-12-31
```

Spells are closed intervals, and a missing end means the spell is
ongoing. The reported rows carry an `overlap_id` that groups spells
overlapping each other, the same idea as `dupid`.

The opposite rule is
[`ensure_no_gaps()`](https://dataniel.github.io/inshape/reference/ensure_no_gaps.md):
where a person must have an address every day, a spell that starts later
than the day after the earlier ones ended leaves days without one. The
spell after each gap is reported with the length of the gap, and
`max_gap` accepts short ones:

``` r
moves <- tibble(
  cpr   = c("a", "a", "b", "b"),
  start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-07-04")),
  end   = as.Date(c("2020-12-31", NA,           "2020-06-30", "2021-12-31"))
)

ensure_no_gaps(moves, cpr, start, end)
#> Warning in ensure_no_gaps(moves, cpr, start, end): Gaps between spells per cpr
#> ℹ 1 row found:
#>       gap cpr   start      end
#>     <int> <chr> <date>     <date>
#>   1     3 b     2020-07-04 2021-12-31
```

Before requiring that, look at how the spells relate to each other.
[`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md)
takes each unit’s spells in order and says, for each, how it relates to
the earlier ones: after a gap, adjacent (starting the day after one
ends, often a transfer recorded as two spells), touching on one shared
day, overlapping, nested or a duplicate. In patient registers up to a
quarter of the entries can be such transfers, and counting spells
without merging them first inflates every count.

``` r
admissions <- tibble(
  cpr   = c("a", "a", "a", "b", "b", "c"),
  start = as.Date(c("2020-01-01", "2020-01-11", "2020-03-01",
                    "2020-01-01", "2020-01-05", "2021-06-01")),
  end   = as.Date(c("2020-01-10", "2020-01-20", "2020-03-05",
                    "2020-01-31", "2020-01-10", NA))
)

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

[`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md)
merges them: by default spells that overlap or follow the next day
become one, from the first start to the latest end, and `n_spells`
counts what was merged. `max_gap = 30` also merges spells less than a
month apart, a readmission counted as the same episode, and `by` merges
only spells that agree in a column such as the employer:

``` r
merge_spells(admissions, cpr, start, end)
#> # A tibble: 4 × 4
#>   cpr   start      end        n_spells
#>   <chr> <date>     <date>        <int>
#> 1 a     2020-01-01 2020-01-20        2
#> 2 a     2020-03-01 2020-03-05        1
#> 3 b     2020-01-01 2020-01-31        2
#> 4 c     2021-06-01 NA                1
```

## Attributes of the unit: `describe_varying()` and `ensure_constant()`

Sex and birth date belong to the person, not to the year, yet a panel
repeats them on every row, and a person with two values is an error,
usually of linkage or of a correction applied to some years only.
[`describe_varying()`](https://dataniel.github.io/inshape/reference/describe_varying.md)
shows which columns vary within units, from the constant to the varying.
A column that varies for a handful of units out of millions is rarely
meant to vary:

``` r
persons <- tibble(
  cpr    = c("a", "a", "b", "b", "c", "c"),
  year   = c(2020, 2021, 2020, 2021, 2020, 2021),
  sex    = c("F", "F", "M", "F", "M", NA),
  income = c(100, 120, 90, 95, 80, 85)
)

describe_varying(persons, cpr)
#> ── Within cpr ──────────────────────────────────────────────────────────────────
#> 3 units, 3 columns
#> 
#>     column varying share   partly_missing all_missing
#>   1 sex          1 33.33%               1           0
#>   2 income       3 100.00%              0           0
#>   3 year         3 100.00%              0           0
```

[`ensure_constant()`](https://dataniel.github.io/inshape/reference/ensure_constant.md)
turns that into a rule and lists every row of the units that break it. A
missing value is not a contradiction, so `c` passes:

``` r
ensure_constant(persons, cpr, sex)
#> Warning in ensure_constant(persons, cpr, sex): Varies within units: sex per cpr
#> ℹ 2 rows found:
#>     cpr   sex    year income
#>     <chr> <chr> <dbl>  <dbl>
#>   1 b     M      2020     90
#>   2 b     F      2021     95
```

## Codes over time: `describe_codes()` and `ensure_codes()`

Code lists change: municipalities merge, industry codes are revised.
[`describe_codes()`](https://dataniel.github.io/inshape/reference/describe_codes.md)
shows when each code occurs, so a revision stands out as a period with
many new and many gone codes, and a typo as a code seen once:

``` r
residents <- tibble(
  year = rep(2018:2021, each = 4),
  municipality = c("955", "956", "957", NA,    "955", "956", "957", "957",
                   "960", "956", "957", "95",  "960", "965", "957", "956")
)

describe_codes(residents, municipality, year)
#> ── Codes: municipality by year ─────────────────────────────────────────────────
#> 16 rows, 6 codes, 4 periods, 2018-2021
#> 
#> • In every period: 2 codes (33.3%)
#> • Skipping periods: 0 codes (0.0%)
#> • Rows with a missing municipality: 1
#> 
#> By period:
#>     period codes   new  gone missing
#>   1   2018     3    NA    NA       1
#>   2   2019     3     0     0       0
#>   3   2020     4     2     1       0
#>   4   2021     4     1     1       0
#> 
#> Codes not in every period, skipping first:
#>     code  first  last periods  gaps  rows
#>   1 95     2020  2020       1     0     1
#>   2 965    2021  2021       1     0     1
#>   3 955    2018  2019       2     0     2
#>   4 960    2020  2021       2     0     2
```

[`ensure_codes()`](https://dataniel.github.io/inshape/reference/ensure_codes.md)
requires the codes of a code list:

``` r
ensure_codes(residents, municipality, c("955", "956", "957", "960", "965"))
#> Warning in ensure_codes(residents, municipality, c("955", "956", "957", : Codes not in the code list: municipality
#> ℹ 1 row in 1 group:
#>     municipality  year
#>     <chr>        <int>
#>   1 95            2020
```

## A new extract: `describe_changes()`

A register is delivered again and again, and the same person-year should
not change between deliveries unless it was corrected.
[`describe_changes()`](https://dataniel.github.io/inshape/reference/describe_changes.md)
compares two extracts by their key:

``` r
before <- tibble(cpr = c("a", "b", "c"), year = 2023,
                 sex = c("F", "M", "F"), born = c(1950, 1960, NA))
after  <- tibble(cpr = c("a", "b", "d"), year = 2023,
                 sex = c("F", "F", "M"), born = c(1950, 1960, 1990))

describe_changes(before, after, cpr, year)
#> ── Changes by cpr, year ────────────────────────────────────────────────────────
#> 3 rows before, 3 rows now, 2 keys in both
#> 
#> • New keys: 1 (33.3%)
#> • Keys gone: 1 (33.3%)
#> • Keys with a changed value: 1 (50.0%)
#> 
#> Changes per column, among the keys in both:
#>     column changed went_missing filled_in share 
#>   1 sex          1            0         0 50.00%
#>   2 born         0            0         0 0.00%
```

## Within a lifetime: `ensure_within()`

Registers are updated at different times, so a linked extract can hold a
person after death or emigration, or income before birth.
[`ensure_within()`](https://dataniel.github.io/inshape/reference/ensure_within.md)
requires each row to lie between its own bounds, usually joined on from
the population register. A yearly row counts by the year, so the year of
death itself is fine:

``` r
panel <- tibble(
  cpr   = c("a", "a", "a", "b", "b"),
  year  = c(2022, 2023, 2024, 2022, 2023),
  born  = as.Date(c("1950-04-01", "1950-04-01", "1950-04-01", "2023-01-10", "2023-01-10")),
  death = as.Date(c("2023-05-01", "2023-05-01", "2023-05-01", NA, NA))
)

ensure_within(panel, year, from = born, to = death)
#> Warning in ensure_within(panel, year, from = born, to = death): Rows outside: year within born to death
#> ℹ 2 rows in 2 groups:
#>     outside      year born       death      cpr
#>     <chr>       <dbl> <date>     <date>     <chr>
#>   1 after death  2024 1950-04-01 2023-05-01 a
#>   2 before born  2022 2023-01-10 NA         b
```

## From spells to a panel: `spells_to_panel()`

[`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md)
turns spells into one row per unit and year (or
`by = "quarter"`/`"month"`), with the status at primo and ultimo. By
default primo is the previous ultimo, so primo 2021 is the status on 31
December 2020.

In an education register the status is the *outcome* of the spell,
passed or dropped out. With `status_is = "outcome"`, a running spell
shows as `ongoing` and the outcome applies from the end date until a new
spell starts:

``` r
education <- data.frame(
  cpr    = c("a", "a", "b"),
  start  = as.Date(c("2018-08-15", "2021-08-15", "2019-08-15")),
  end    = as.Date(c("2021-06-20", NA,           "2020-03-01")),
  status = c("passed", "in progress", "dropped out")
)

education |>
  spells_to_panel(cpr, start, end, status,
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
```

With the default `status_is = "state"`, the status holds for the whole
spell (enrolled, on leave) and is `NA` outside spells. `from` and `to`
give every unit the same window, which makes a balanced panel.

## Status on a panel you have: `add_spell_status()`

Often the panel exists already, and the spells should only add a status
to it. A `left_join(join_by(between()))` does that until the data gets
messy: overlapping spells duplicate rows, and an ongoing spell with no
end matches nothing.
[`add_spell_status()`](https://dataniel.github.io/inshape/reference/add_spell_status.md)
keeps the rows of the panel exactly as they are and uses the rules of
[`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md):

``` r
population <- data.frame(cpr  = c("a", "a", "b", "c"),
                         year = c(2020, 2021, 2020, 2020))

population |>
  add_spell_status(education, cpr, year, start, end, status,
                   status_is = "outcome", ongoing = "in progress")
#>   cpr year status_primo status_ultimo
#> 1   a 2020  in progress   in progress
#> 2   a 2021  in progress   in progress
#> 3   b 2020  in progress   dropped out
#> 4   c 2020         <NA>          <NA>
```

## Valid boundaries and reference coverage

Validate spell boundaries before checking their relationships. Missing
ends represent ongoing spells; `open_end = FALSE` requires closed
spells.

``` r
ensure_valid_spells(education, start, end)
#> ✔ Valid spells: start to end
```

Check that each observation can be linked to a reference register.
Duplicate reference keys do not multiply rows, and missing keys do not
match unless `na_matches = "na"` is specified.

``` r
observations <- tibble(cpr = c("a", "b", "c"), year = 2020)
reference <- tibble(person_id = c("a", "b"), year = 2020)
ensure_matched(observations, reference, by = c(cpr = "person_id", "year"))
#> Warning in ensure_matched(observations, reference, by = c(cpr = "person_id", : Keys missing from the reference: cpr, year
#> ℹ 1 row found:
#>     cpr    year
#>     <chr> <dbl>
#>   1 c      2020
```

## Before a join: `describe_match()`

[`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md)
asks one question of a join, whether every row finds a match.
[`describe_match()`](https://dataniel.github.io/inshape/reference/describe_match.md)
looks at the whole of it first: how many keys are in both tables, how
many only in one, and whether the reference repeats a key, so that a
left join returns more rows than it was given. Here `c` is not in the
register, `d` has no income, and `b` is registered twice:

``` r
income <- tibble(
  cpr    = c("a", "a", "b", "c", NA),
  year   = c(2023, 2024, 2024, 2024, 2024),
  income = c(10, 12, 7, 9, 3)
)
population_register <- tibble(
  person_id = c("a", "b", "b", "d"),
  kommune   = c("955", "956", "957", "960")
)

describe_match(income, population_register, by = c(cpr = "person_id"))
#> ── Match: cpr = person_id ──────────────────────────────────────────────────────
#> data: 5 rows, reference: 4 rows
#> 
#> Keys:
#>     found              keys  rows ref_rows
#>   1 in both               2     3        3
#>   2 only in data          1     1        0
#>   3 only in reference     1     0        1
#> 
#> • Rows of data without a match: 2 (40.0%), 1 of them with a missing key
#> • Keys repeated in the reference: 1; a left join returns 6 rows, 1 more than data
```

A row with a missing key matches nothing and is counted on its own. The
key must be stated in `by`: a join on whatever names two registers
happen to share is how a wrong key goes unnoticed.

## Codes valid at the observation time

A temporal code list has `code`, `valid_from` and `valid_to`. Bounds are
inclusive, missing bounds are open, and a code may have several
intervals. Time and bounds use the same scale: dates, date-times, or
numeric periods. Missing observation times fail for non-missing codes.
`na_ok` controls missing codes separately.

``` r
codebook <- tibble(code = c("A", "B"),
                   valid_from = c(2015, 2020), valid_to = c(2019, NA_real_))
coded <- tibble(classification = c("A", "A", "B"), year = c(2019, 2020, 2020))
ensure_codes(coded, classification, codebook, time = year)
#> Warning in ensure_codes(coded, classification, codebook, time = year): Codes not in the code list: classification
#> ℹ 1 row in 1 group:
#>     classification  year
#>     <chr>          <dbl>
#>   1 A               2020
```

## Rules of your own: `ensure_none()`, `ensure_all()` and `ensure_empty()`

The structure checks cover the rules every register has. The rest are
particular to a delivery: no negative amounts, every cvr eight digits, a
total that matches its parts. Any rule dplyr can express is a
checkpoint, stated as “the set of violations must be empty”.

[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md)
takes the condition for a violating row and returns the full data, so
checks chain before the real work continues:

``` r
sales <- tibble(
  order_id    = 1001:1006,
  customer_id = c(12, 17, NA, 25, 31, NA),
  amount      = c(250, -40, 120, 80, -15, 300)
)

sales |>
  ensure_none(amount < 0, warn_msg = "Negative amounts") |>
  ensure_none(amount > 1e6) |>
  nrow()
#> Warning in ensure_none(sales, amount < 0, warn_msg = "Negative amounts"): Negative amounts
#> ℹ 2 rows found:
#>     order_id customer_id amount
#>        <int>       <dbl>  <dbl>
#>   1     1002          17    -40
#>   2     1005          31    -15
#> ✔ No rows where amount > 1e+06
#> [1] 6
```

Without a message, the condition becomes one, which is often enough at
the console. Give checks that stay in a script a message in your own
words. Messages are shown literally, so `"cvr must match ^\\d{8}$"` is
safe.

The condition follows [`filter()`](https://rdrr.io/r/stats/filter.html):
a row where it is `NA` is not a violation.
[`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md)
states the rule positively instead, and there a row passes only when the
condition is `TRUE`, so a missing value is a violation:

``` r
sales |>
  ensure_none(customer_id < 0)
#> ✔ No rows where customer_id < 0

sales |>
  ensure_all(customer_id > 0)
#> Warning in ensure_all(sales, customer_id > 0): Found rows that do not meet customer_id > 0
#> ℹ 2 rows found:
#>     order_id customer_id amount
#>        <int>       <dbl>  <dbl>
#>   1     1003          NA    120
#>   2     1006          NA    300
```

No customer id is negative, but two are missing. Use
[`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md)
when a value has to be present *and* right, and
[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md)
when a missing value is acceptable or a rule of its own, such as
[`ensure_complete()`](https://dataniel.github.io/inshape/reference/ensure_complete.md).

[`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md)
is the most general form: build the violation set yourself, with a
[`filter()`](https://rdrr.io/r/stats/filter.html) or an anti-join, and
pipe it in.

``` r
expected |>
  dplyr::anti_join(delivery, by = "cvr") |>
  ensure_empty(warn_msg = "Firms missing from the delivery")
```

### Many rules at once: `tally_violations()`

A chain of checkpoints stops at the first abort. When a delivery has
five problems, you want to hear about all five in one go.
[`tally_violations()`](https://dataniel.github.io/inshape/reference/tally_violations.md)
evaluates every rule and counts the violating rows, but never warns or
stops: the checkpoints judge, the tally only counts.

``` r
report <- sales |>
  tally_violations(
    "Negative amount" = amount < 0,
    "No customer"     = is.na(customer_id),
    "Huge amount"     = amount > 1e6
  )
report
#> # A tibble: 3 × 4
#>   rule                n total rows     
#>   <chr>           <int> <int> <list>   
#> 1 Negative amount     2     6 <int [2]>
#> 2 No customer         2     6 <int [2]>
#> 3 Huge amount         0     6 <int [0]>
```

`rows` holds the row numbers of each rule’s violations. Filtered to the
rules that failed, the tally is itself a violation set. `total` is the
number of rows checked, so the same tally can warn about every broken
rule and stop only for those broken at scale:

``` r
report |>
  dplyr::filter(n > 0) |>
  ensure_empty(warn_msg = "Rules with violations")

report |>
  dplyr::filter(n / total > 0.001) |>
  ensure_empty(abort_msg = "Rules broken by more than 0.1 % of the rows")
```

## Personal data and large registers

inshape is made for interactive review of registers, at the console in
the environment where the data lives. The offending rows of a check are
personal data, so inshape writes nothing to disk, neither rows nor a
log. A failure shows the count and the first rows. Wrap the check in
[`violations()`](https://dataniel.github.io/inshape/reference/violations.md)
to get all of them, to look at in the session; when the check passes, it
returns no rows:

``` r
gaps <- violations(ensure_balanced(panel, cpr, year, gaps_only = TRUE))
#> ✔ No gaps in year per cpr
gaps
#> # A tibble: 0 × 4
#> # ℹ 4 variables: cpr <chr>, year <dbl>, born <date>, death <date>
```

Whether rows are kept anywhere is for the analysis and its data
agreement to decide. To save them, do it yourself, from the rows
[`violations()`](https://dataniel.github.io/inshape/reference/violations.md)
returns:

``` r
violations(ensure_none(sales, amount < 0)) |>
  data.table::fwrite("negative_amounts.csv")
```

A DuckDB or Arrow table is checked where it lives, and only the count
and the first rows are fetched into R. See
[`?checkpoints`](https://dataniel.github.io/inshape/reference/checkpoints.md)
for both.
