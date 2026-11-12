# Checkpoints: shared arguments, personal data and database tables

The `ensure_*()` functions are checkpoints: each states a rule about the
data, warns or aborts with the offending rows when it is broken, and
returns `data` invisibly, so it can sit in the middle of a pipeline.
Most rules are about structure;
[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md),
[`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md)
and
[`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md)
take any rule dplyr can express. This page documents what they share.

## Arguments

- data:

  A data frame or tibble, a database table (dbplyr, e.g. DuckDB) or an
  Arrow table or dataset; see *Database and Arrow tables*.

- success_msg:

  Message shown when the rule holds. If `NULL` (default), it is
  `"Check passed: <message>"` when `warn_msg` or `abort_msg` is given,
  so the console names every check that ran, and a description of the
  check otherwise.

- warn_msg:

  Message shown when the rule is broken and no `abort_msg` is set.
  Defaults to a description of the check.

- abort_msg:

  If provided,
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  is called with this message when the rule is broken. If `NULL`
  (default), a warning is issued instead.

## Details

The offending rows are deliberately not kept in the session afterwards:
on a population register a failed check can hold millions of rows, and
they would stay in memory until the next failure. Messages are shown
literally: braces are not interpolated. Diagnostic columns such as
`dupid`, `missing`, `overlap_id`, `gap`, `outside` and `reason` receive
a numeric suffix when their name is already in the input (for example
`dupid.1`). All original columns keep their names and values.

A failed check signals a condition of class `inshape_failure` (a warning
or an error) that carries the offending rows in its `violations` field.
[`violations()`](https://dataniel.github.io/inshape/reference/violations.md)
catches it and returns the rows, to look at all of them in the session:

    dups <- violations(ensure_unique(persons, cpr))

### Personal data

inshape is made for interactive review of registers, at the console in
the environment where the data lives. The offending rows of a check are
personal data: they hold the key, often a cpr number, and every other
column of the rows. inshape therefore writes nothing to disk, neither
the rows nor a log of the checks, and keeps nothing after a check:

- **The message** shows the number of rows and the first 5 of them at
  the console. Output that is kept, such as a rendered report or a
  shared screen, keeps them too, so run the checks at the console.

- **The condition** carries the rows in memory, until it is caught, by
  [`violations()`](https://dataniel.github.io/inshape/reference/violations.md)
  for one, or dropped. Whether any of them are stored, and where, is for
  the analysis and its data agreement to decide, not the package.

To keep the rows, save them yourself, from what
[`violations()`](https://dataniel.github.io/inshape/reference/violations.md)
returns:

    violations(ensure_none(sales, amount < 0)) |>
      data.table::fwrite("negative_amounts.csv")

### Speed

Every check, and every `describe_*()` function, starts by compressing
the key columns to integer ids with a compiled, multi-threaded hash,
without sorting them. Nothing is kept between calls, so each check
compresses its columns anew; even so,
[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md)
on 5 million rows takes about 0.2 seconds (see the benchmarks in the
repository). The engine uses as many threads as data.table, set with
[`data.table::setDTthreads()`](https://rdrr.io/pkg/data.table/man/openmp-utils.html).

### Database and Arrow tables

Every checkpoint also takes a database table from dbplyr, such as a
DuckDB table, and an Arrow table or dataset, and checks it where it
lives. The violation set is built as a query, and only its size and the
preview rows are fetched into R, so a check on a register too large for
memory still works. Arrow data is queried through DuckDB with
[`arrow::to_duckdb()`](https://arrow.apache.org/docs/r/reference/to_duckdb.html).
This needs the dbplyr package, and duckdb for Arrow.

    con <- DBI::dbConnect(duckdb::duckdb(), "register.duckdb")

    dplyr::tbl(con, "persons") |>
      ensure_unique(cpr, year) |>
      ensure_balanced(cpr, year, gaps_only = TRUE)

A checkpoint returns the table it was given, still unevaluated, so the
pipeline continues in the database. On a failure the condition's
`violations` field, and so
[`violations()`](https://dataniel.github.io/inshape/reference/violations.md),
holds the violation set as a query: `collect()` it to get the rows. Two
things differ from data frames, because a database table has no row
order:
[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md)
numbers `dupid` in the order of the key instead of first appearance, and
spells starting on the same day are ordered by their end in
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md).

The `describe_*()` functions take database and Arrow tables too. Each
summary is computed in the database with grouped counts, and only those
counts are fetched, so describing a register costs a few small queries
whatever its size. The numbers are the same as in memory, which the
tests check. Two differences: participation patterns with the same count
at the cut of
[`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md)'s
`patterns` may be chosen differently, and in
[`describe_changes()`](https://dataniel.github.io/inshape/reference/describe_changes.md)
the keys that came, went or changed stay queries, to `collect()`.

## See also

[`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md),
[`ensure_complete()`](https://dataniel.github.io/inshape/reference/ensure_complete.md),
[`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md),
[`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md),
[`ensure_no_gaps()`](https://dataniel.github.io/inshape/reference/ensure_no_gaps.md),
[`ensure_valid_spells()`](https://dataniel.github.io/inshape/reference/ensure_valid_spells.md),
[`ensure_constant()`](https://dataniel.github.io/inshape/reference/ensure_constant.md),
[`ensure_within()`](https://dataniel.github.io/inshape/reference/ensure_within.md),
[`ensure_codes()`](https://dataniel.github.io/inshape/reference/ensure_codes.md)
and
[`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md)
for the structure,
[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md),
[`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md),
[`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md)
and
[`tally_violations()`](https://dataniel.github.io/inshape/reference/tally_violations.md)
for rules of your own, and
[`violations()`](https://dataniel.github.io/inshape/reference/violations.md)
for the rows that break one.
