# inshape 0.1.0

* First version. The key, panel and spell checks move here from expectr and
  are renamed so the two packages cannot be confused:
  `expect_unique()` is now `ensure_unique()`, `expect_balanced()` is
  `ensure_balanced()` and `expect_no_overlap()` is `ensure_no_overlap()`.
  A failure signals `inshape_failure`.
* inshape is for interactive review of registers and writes nothing to
  disk: the offending rows are personal data. A failure shows the count and
  the first rows at the console and carries all of them on the condition,
  in memory. There is no `log` or `dump` argument and no option for them.
  See "Personal data" in `?checkpoints`.
* New `describe_key()` and `describe_panel()` describe a key and a panel
  before a rule is chosen: duplicated keys split into exact copies and
  conflicts by column, and the panel's units, gaps, entries, exits and
  participation patterns, in the spirit of Stata's `xtdescribe`.
* New `describe_spells()` relates each spell to the unit's earlier spells:
  after a gap, adjacent (a transfer that may need merging), touching on one
  day, overlapping, nested or duplicate, and counts ongoing spells and
  spells that end before they start. `ensure_no_overlap()` shares its
  compiled pass over the sorted spells, and went from 6.0 to 2.8 seconds on
  25 million spells.
* New `describe_changes()` compares two extracts of a register by their
  key: keys that came and went, columns that came, went or changed type,
  and per column the values that changed, went missing or were filled in,
  the late corrections of a register without a time limit on them.
* New `describe_codes()` shows how the codes of a column change over
  periods (first and last period, codes skipping periods, new and gone
  codes per period), on the panel engine, and `ensure_codes()` requires
  codes from a code list.
* Every `describe_*()` function now takes a database or Arrow table and
  computes its summary in the database, fetching only the counts; the
  tests hold the numbers to those in memory.
* New `ensure_within()` requires each row to lie within its unit's
  lifetime: no observations after death or emigration, or before birth.
  A year compared with a date counts by the date's year, and a missing
  bound is open. A compiled pass checks 25 million rows against birth and
  death dates in under half a second.
* New `merge_spells()` merges spells recorded as several: back to back
  (transfers), overlapping, or less than `max_gap` days apart, optionally
  only when they agree in `by` columns such as the employer. It shares the
  compiled pass of `describe_spells()` and merges 25 million spells in
  about 5.5 seconds.
* New `describe_varying()` shows which columns vary within units, and
  `ensure_constant()` requires columns such as sex or birth date to be
  constant within each unit; a missing value is not a contradiction. Both
  compare each row with its unit's first value in one compiled pass; on 25
  million rows `ensure_constant(sex)` takes 0.15 seconds.
* Grouping by several key columns no longer fails when the product of
  their numbers of values passes the integer range.
* A compiled grouping engine: keys are compressed to integer ids by a
  partitioned, multi-threaded hash (`options(inshape.threads = )`, default
  data.table's threads), and panels are checked as bit matrices. On 25
  million rows `ensure_balanced()` went from 7.3 to 1.8 seconds and the
  grouping of a cpr column from 4.4 to 0.7.
* The ids of the last three large key columns are kept for the session and
  reused when the same column is checked again, recognised by a checksum of
  its content (`options(inshape.cache = FALSE)` turns it off). On 25 million
  rows each further check of a cpr column saves the 0.15–0.2 seconds of
  compressing it; see `?checkpoints`.
* `spells_to_panel()` and `add_spell_status()` move here from daos,
  unchanged.
