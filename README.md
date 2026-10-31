# lustrum

Structure checks for register microdata.

Register data comes as one row per unit, one row per unit and period (a
panel), or one row per spell. Every analysis assumes that shape is right:
no duplicated persons, no missing years in the middle of a panel, no
person with two addresses at once. lustrum checks those assumptions, fast
enough for full-population registers, and converts spells to panels.

```r
library(lustrum)

persons |>
  ensure_unique(cpr, year, abort_msg = "Duplicate person-years") |>
  ensure_balanced(cpr, year, periods = 2015:2024, gaps_only = TRUE)

addresses |>
  ensure_no_overlap(cpr, start, end)
```

## Installation

lustrum is not on CRAN. Install it from GitHub:

```r
# install.packages("pak")
pak::pak("dataniel/lustrum")
```

## Functions

| Function | Description |
|---|---|
| `add_spell_status()` | Status from spells on a panel you already have, at primo/ultimo or on a date |
| `describe_key()` | How well columns work as a key: duplicated keys, exact copies vs. conflicts and the columns they differ in |
| `describe_panel()` | The structure of a panel: units, gaps, entries and exits per period, participation patterns |
| `describe_spells()` | Spell data: gaps, transfers (adjacent spells), overlapping, nested and duplicate spells, ongoing and invalid spells |
| `describe_varying()` | Which columns vary within units: constant, nearly constant (errors) and varying |
| `ensure_balanced()` | Every unit observed in every period, or no gaps (`gaps_only`) |
| `ensure_constant()` | Columns such as sex or birth date are constant within each unit |
| `ensure_no_overlap()` | Spells (addresses, employment) do not overlap within a unit |
| `ensure_unique()` | Key columns identify each row uniquely |
| `ensure_within()` | No rows after death or emigration, or before birth: each row within its unit's lifetime |
| `merge_spells()` | Merge spells that follow each other or overlap (transfers, readmissions within `max_gap` days) into one |
| `spells_to_panel()` | Spells to a yearly, quarterly or monthly panel with primo and ultimo status |

The `ensure_*()` checkpoints warn or abort with the offending rows and
return the data. Each can append a line to a log and write the rows to a
CSV file, set once per script with
`options(lustrum.log = ..., lustrum.dump = ...)`. A failure signals a
condition of class `lustrum_failure` that carries the rows.

## Built for registers

Character keys such as cpr are compressed to integer ids by a compiled,
partitioned and multi-threaded hash, without sorting them; a panel then
becomes a bit matrix, one bit per unit and period, read with processor bit
instructions; and spell lookups run in one compiled pass over the sorted
spells. On 25 million rows (5 million persons over 5 years),
`describe_panel()` takes under 2 seconds. See `benchmarks/`.

A DuckDB or Arrow table is checked in the database, without loading it
into R:

```r
con <- DBI::dbConnect(duckdb::duckdb(), "register.duckdb")

dplyr::tbl(con, "persons") |>
  ensure_unique(cpr, year) |>
  ensure_balanced(cpr, year, gaps_only = TRUE)
```

## The name

Each Roman census was closed by the *lustrum*, a purification of the
people just registered, before the register was accepted. This package is
that last step for register data: a registration of the registrations.

## Origin

The checks started as `expect_unique()`, `expect_balanced()` and
`expect_no_overlap()` in [expectr](https://github.com/dataniel/expectr),
and the spell conversions in [daos](https://github.com/dataniel/daos).
They were renamed to `ensure_*()` when they moved, so a script using both
packages cannot confuse them. expectr keeps the general checkpoints, and
the packages do not depend on each other.
