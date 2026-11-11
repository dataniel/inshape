# inshape

Checks for register microdata.

Register data comes as one row per unit, one row per unit and period (a
panel), or one row per spell. Every analysis assumes that shape is right:
no duplicated persons, no missing years in the middle of a panel, no
person with two addresses at once. inshape checks those assumptions, fast
enough for full-population registers, and converts spells to panels. Any
other rule dplyr can express is a checkpoint too.

```r
library(inshape)

persons |>
  ensure_unique(cpr, year, abort_msg = "Duplicate person-years") |>
  ensure_balanced(cpr, year, periods = 2015:2024, gaps_only = TRUE) |>
  ensure_none(income < 0, warn_msg = "Negative income")

addresses |>
  ensure_no_overlap(cpr, start, end)
```

## Installation

inshape is not on CRAN. Install it from GitHub:

```r
# install.packages("pak")
pak::pak("dataniel/inshape")
```

## Functions

| Function | Description |
|---|---|
| `add_spell_status()` | Status from spells on a panel you already have, at primo/ultimo or on a date |
| `describe_changes()` | Two extracts of a register: keys that came and went, and per column the values that changed, went missing or were filled in |
| `describe_codes()` | How the codes of a column change over periods: first and last period, codes skipping periods, new and gone codes |
| `describe_key()` | How well columns work as a key: duplicated keys, exact copies vs. conflicts and the columns they differ in |
| `describe_match()` | What a join will do: keys in both tables, only in one, rows without a match, and the rows a left join returns when the reference repeats a key |
| `describe_panel()` | The structure of a panel: units, gaps, entries and exits per period, participation patterns |
| `describe_spells()` | Spell data: gaps, transfers (adjacent spells), overlapping, nested and duplicate spells, ongoing and invalid spells |
| `describe_varying()` | Which columns vary within units: constant, nearly constant (errors) and varying |
| `ensure_all()` | Every row meets a condition written as in `filter()`; a missing value is a violation |
| `ensure_balanced()` | Every unit observed in every period, or no gaps (`gaps_only`) |
| `ensure_codes()` | Codes belong to a code list, optionally within their validity periods |
| `ensure_complete()` | Columns an analysis cannot do without (an id, a date) have no missing values; the rows are reported with the columns missing in each |
| `ensure_constant()` | Columns such as sex or birth date are constant within each unit |
| `ensure_empty()` | A violation set built with `filter()` or an anti-join has no rows |
| `ensure_matched()` | Every key occurs in a reference register, including composite or renamed keys |
| `ensure_no_gaps()` | Spells cover a unit without a break between them, or with gaps of at most `max_gap` days |
| `ensure_no_overlap()` | Spells (addresses, employment) do not overlap within a unit |
| `ensure_none()` | No row matches a condition written as in `filter()` |
| `ensure_unique()` | Key columns identify each row uniquely |
| `ensure_valid_spells()` | Spells have a start and do not end before it, optionally requiring a closed end |
| `ensure_within()` | No rows after death or emigration, or before birth: each row within its unit's lifetime |
| `merge_spells()` | Merge spells that follow each other or overlap (transfers, readmissions within `max_gap` days) into one |
| `spells_to_panel()` | Spells to a yearly, quarterly or monthly panel with primo and ultimo status |
| `tally_violations()` | Violations counted for many rules at once, judging nothing; filter and pipe into `ensure_empty()` |
| `violations()` | The rows that break a check, all of them: wrap the check in it |

The `ensure_*()` checkpoints warn or abort with the offending rows and
return the data. The message shows the first rows; `violations()` returns
all of them:

```r
dups <- violations(ensure_unique(persons, cpr, year))
```

Look at a reference before linking it and require the match, or validate a
code at the time it was observed:

```r
describe_match(income, population, by = c("cpr", "year"))

income |>
  ensure_complete(cpr, year) |>
  ensure_matched(population, by = c("cpr", "year"))

codebook <- data.frame(
  code = c("A", "B"),
  valid_from = c(2015, 2020),
  valid_to = c(2019, NA_real_)
)
persons |>
  ensure_codes(classification, codebook, time = year)

addresses |>
  ensure_valid_spells(start, end) |>
  ensure_no_overlap(cpr, start, end)
```

Code validity bounds are inclusive, and missing bounds are open. Missing
observation times fail for non-missing codes. `ensure_matched()` treats
missing keys as unmatched unless `na_matches = "na"` is requested.
Diagnostic columns get a suffix on name collisions, preserving the input
columns. `describe_changes()` explicitly lists columns it cannot compare
in `columns_skipped` and in its printed summary.

inshape is made for interactive review of registers. The offending rows of
a check are personal data, so inshape writes nothing to disk, neither rows
nor a log: a failure shows the count and the first rows at the console,
and the rest stay in memory, for `violations()` to return. See
`?checkpoints`.

## Built for registers

Character keys such as cpr are compressed to integer ids by a compiled,
partitioned and multi-threaded hash, without sorting them; a panel then
becomes a bit matrix, one bit per unit and period, read with processor bit
instructions; and spell lookups run in one compiled pass over the sorted
spells. On 25 million rows (5 million persons over 5 years),
`describe_panel()` takes under 2 seconds. See `benchmarks/`.

A DuckDB or Arrow table is checked and described in the database, without
loading it into R; the `describe_*()` summaries fetch only their counts:

```r
con <- DBI::dbConnect(duckdb::duckdb(), "register.duckdb")

dplyr::tbl(con, "persons") |>
  ensure_unique(cpr, year) |>
  ensure_balanced(cpr, year, gaps_only = TRUE)
```

## The name

Register data has a shape: one row per unit, per unit and period, or per
spell. An analysis is written for one of them. inshape asks whether the
data is *in shape*, the shape the analysis assumes, before anything is
built on it.

## Origin

The checkpoints and the spell conversions started in
[daos](https://github.com/dataniel/daos). The general checkpoints spent a
while in the expectr package as `expect_empty()`, `expect_none()` and
`expect_all()`, and joined the structure checks here as `ensure_empty()`,
`ensure_none()` and `ensure_all()`, since they share the same contract,
reporting and dependencies.
