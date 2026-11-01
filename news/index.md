# Changelog

## inshape 0.1.0

- First version. The key, panel and spell checks move here from expectr
  and are renamed so the two packages cannot be confused:
  `expect_unique()` is now
  [`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md),
  `expect_balanced()` is
  [`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
  and `expect_no_overlap()` is
  [`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md).
  A failure signals `inshape_failure`.
- inshape is for interactive review of registers and writes nothing to
  disk: the offending rows are personal data. A failure shows the count
  and the first rows at the console and carries all of them on the
  condition, in memory. There is no `log` or `dump` argument, and no
  options: nothing is kept between calls either, and the engine runs on
  data.table’s threads. See “Personal data” in
  [`?checkpoints`](https://dataniel.github.io/inshape/reference/checkpoints.md).
- New
  [`describe_key()`](https://dataniel.github.io/inshape/reference/describe_key.md)
  and
  [`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md)
  describe a key and a panel before a rule is chosen: duplicated keys
  split into exact copies and conflicts by column, and the panel’s
  units, gaps, entries, exits and participation patterns, in the spirit
  of Stata’s `xtdescribe`.
- New
  [`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md)
  relates each spell to the unit’s earlier spells: after a gap, adjacent
  (a transfer that may need merging), touching on one day, overlapping,
  nested or duplicate, and counts ongoing spells and spells that end
  before they start.
  [`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md)
  shares its compiled pass over the sorted spells, and went from 6.0 to
  2.8 seconds on 25 million spells.
- New
  [`describe_changes()`](https://dataniel.github.io/inshape/reference/describe_changes.md)
  compares two extracts of a register by their key: keys that came and
  went, columns that came, went or changed type, and per column the
  values that changed, went missing or were filled in, the late
  corrections of a register without a time limit on them.
- New
  [`describe_codes()`](https://dataniel.github.io/inshape/reference/describe_codes.md)
  shows how the codes of a column change over periods (first and last
  period, codes skipping periods, new and gone codes per period), on the
  panel engine, and
  [`ensure_codes()`](https://dataniel.github.io/inshape/reference/ensure_codes.md)
  requires codes from a code list.
- Every `describe_*()` function now takes a database or Arrow table and
  computes its summary in the database, fetching only the counts; the
  tests hold the numbers to those in memory.
- New
  [`ensure_within()`](https://dataniel.github.io/inshape/reference/ensure_within.md)
  requires each row to lie within its unit’s lifetime: no observations
  after death or emigration, or before birth. A year compared with a
  date counts by the date’s year, and a missing bound is open. A
  compiled pass checks 25 million rows against birth and death dates in
  under half a second.
- New
  [`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md)
  merges spells recorded as several: back to back (transfers),
  overlapping, or less than `max_gap` days apart, optionally only when
  they agree in `by` columns such as the employer. It shares the
  compiled pass of
  [`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md)
  and merges 25 million spells in about 5.5 seconds.
- New
  [`describe_varying()`](https://dataniel.github.io/inshape/reference/describe_varying.md)
  shows which columns vary within units, and
  [`ensure_constant()`](https://dataniel.github.io/inshape/reference/ensure_constant.md)
  requires columns such as sex or birth date to be constant within each
  unit; a missing value is not a contradiction. Both compare each row
  with its unit’s first value in one compiled pass; on 25 million rows
  `ensure_constant(sex)` takes 0.15 seconds.
- Grouping by several key columns no longer fails when the product of
  their numbers of values passes the integer range.
- A compiled grouping engine: keys are compressed to integer ids by a
  partitioned hash on data.table’s threads, and panels are checked as
  bit matrices. On 25 million rows
  [`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
  went from 7.3 to 1.8 seconds and the grouping of a cpr column from 4.4
  to 0.7.
- [`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md)
  and
  [`add_spell_status()`](https://dataniel.github.io/inshape/reference/add_spell_status.md)
  move here from daos, unchanged.
