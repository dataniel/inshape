# Benchmarks

Both scripts build an optimised DLL before they time anything.
`pkgload::load_all()` on its own compiles with `-O0` for debugging, and
the compiled checks then run about twice as slow: the results from
2026-11-11 were measured that way, and `describe_varying()` seemed to
have slowed from 0.39 to 0.80 seconds when nothing had changed.

## Key-based checkpoints on population-sized data

`benchmark-checkpoints.R` compares `ensure_unique()`,
`ensure_balanced()` and `ensure_no_overlap()` before the speed-up
(`baseline-checkpoints.R`, a frozen copy from daos commit b9e3fa4) with the
current implementation, in memory.

```sh
Rscript benchmarks/benchmark-checkpoints.R
# Or select the number of persons (five years each):
Rscript benchmarks/benchmark-checkpoints.R 200000
```

The data is synthetic: one million 10-digit cpr strings over five years,
5 million rows in random order, with ten numeric columns and spell dates.
Variants add 10,000 duplicated keys or remove 10,000 person-years. Before
timing, every case checks that both implementations report the same
violations (for `dupid`, the same grouping, since groups are now numbered
by first appearance). Results are in `checkpoints-results.csv`, with
session details in `checkpoints-session.txt`.

### Local results: 5 million rows

Median seconds of three repetitions in alternating order, on the
Windows/R system recorded in `checkpoints-session.txt` (R 4.6.2, 10
threads). Nothing is kept between calls, so each check groups its key
from scratch.

| Case | Before | After | Speedup |
| --- | ---: | ---: | ---: |
| `ensure_unique(cpr, year)`, no duplicates | 5.83 | 0.16 | 36x |
| `ensure_unique(cpr, year)`, 10,000 duplicates | 5.80 | 0.25 | 23x |
| `ensure_balanced(cpr, year)`, 10,000 gaps | 2.75 | 0.13 | 21x |
| `ensure_balanced(gaps_only = TRUE)`, 10,000 gaps | 2.74 | 0.13 | 21x |
| `ensure_no_overlap(cpr, start, end)` | 2.06 | 0.31 | 6.6x |

The gain comes from never sorting the character key: rows are grouped in
one parallel pass of a compiled hash table, panels are checked in a bit
matrix of units by periods, and only the reported rows are sorted. Times
are local measurements, not universal guarantees. The checks on DuckDB
tables are not part of this script.

The first version of this table, measured while the code was still part
of daos 0.2.0 and grouped with `data.table::chmatch(x, x)`, had speedups
of 2x to 12x.

## Every function on a register-shaped population

`benchmark-functions.R` times every exported function once the data looks
like a register rather than like a stress test: the earlier lesson was
that spells with heavy random overlaps made the spell checks look three
times slower than they are on real data, because they then report
millions of rows.

```sh
Rscript benchmarks/benchmark-functions.R
Rscript benchmarks/benchmark-functions.R 200000
```

One million persons give 4.5 million person-years, in random order. Most
persons are present all five years, some enter or leave; 0.1% skip a
year, 0.05% of person-years are loaded twice, 0.01% change sex in one
year. The spell data has one to four spells per person (2.5 million
rows), a fifth of them starting the day after the previous one ends, and
0.1% overlapping. `describe_changes()` compares two extracts on a unique
key, the later one with 1% of incomes corrected and 0.1% of rows gone.
The temporal code list gives three of the five codes a validity period,
and the reference register lacks 0.01% of the persons. The pauses between
spells are at most 200 days, so `ensure_no_gaps()` runs with
`max_gap = 200` and reports nothing; with the default it reports the 1.2
million spells after a pause, in 0.9 seconds.
Results are in `functions-results.csv`, session details in
`functions-session.txt`.

Median seconds of three repetitions:

| Function | Rows | Seconds |
| --- | ---: | ---: |
| `describe_key(cpr, year)` | 4.5M | 0.18 |
| `describe_panel(cpr, year)` | 4.5M | 0.15 |
| `describe_varying(cpr)` | 4.5M | 0.44 |
| `describe_codes(kommune, year)` | 4.5M | 0.10 |
| `describe_changes(old, new, cpr, year)` | 4.5M | 0.93 |
| `describe_spells(cpr, start, end)` | 2.5M | 0.32 |
| `describe_match(reference, by = "cpr")` | 4.5M | 0.28 |
| `ensure_unique(cpr, year)` | 4.5M | 0.17 |
| `ensure_complete()` on six columns | 4.5M | 0.05 |
| `ensure_balanced(gaps_only = TRUE)` | 4.5M | 0.13 |
| `ensure_constant(cpr, sex, born)` | 4.5M | 0.22 |
| `ensure_within(year, from = born, to = left)` | 4.5M | 0.15 |
| `ensure_codes(kommune, codes)` | 4.5M | 0.04 |
| `ensure_codes(kommune, code_list, time = year)` | 4.5M | 0.18 |
| `ensure_matched(reference, by = "cpr")` | 4.5M | 0.23 |
| `ensure_valid_spells(start, end)` | 2.5M | 0.07 |
| `ensure_no_overlap(cpr, start, end)` | 2.5M | 0.18 |
| `ensure_no_gaps(cpr, start, end, max_gap = 200)` | 2.5M | 0.20 |
| `merge_spells(cpr, start, end)` | 2.5M | 0.54 |
| `spells_to_panel(from = 2016, to = 2020)` | 2.5M | 1.00 |
| `add_spell_status()` onto the panel | 4.5M | 1.35 |
