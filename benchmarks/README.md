# Benchmarks

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

Median seconds, three alternating repetitions, on the Windows/R system
recorded in `checkpoints-session.txt` (R 4.6.1). Measured while the code
was still part of daos 0.2.0, where the functions were named `expect_*()`.

| Case | Before | After | Speedup |
| --- | ---: | ---: | ---: |
| `ensure_unique(cpr, year)`, no duplicates | 5.92 | 0.49 | 12x |
| `ensure_unique(cpr, year)`, 10,000 duplicates | 6.65 | 0.70 | 9.5x |
| `ensure_balanced(cpr, year)`, 10,000 gaps | 3.00 | 0.92 | 3.3x |
| `ensure_balanced(gaps_only = TRUE)`, 10,000 gaps | 3.24 | 1.04 | 3.1x |
| `ensure_no_overlap(cpr, start, end)` | 2.17 | 1.11 | 2.0x |

The gain comes from not sorting the character key: rows are grouped in
one linear pass with `data.table::chmatch(x, x)`, and only the reported
rows are sorted. Times are local measurements, not universal guarantees.
The checks on DuckDB tables are not part of this script.
`daos::flag_duplicates()`, which uses the same grouping, went from 6.33 to
0.57 seconds in the same run.
