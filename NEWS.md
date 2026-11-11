# inshape 0.1.0

* `spells_to_panel()` returns the units in the order they first appear in
  the data, as `merge_spells()` does, instead of sorted by the id columns;
  sort with `dplyr::arrange()` if needed. The spells are sorted on an
  integer id per unit, and sorting a character cpr was most of the time:
  on 2.5 million spells it went from 1.9 to about 1 second.
* `ensure_matched()` hashes the keys of the data and the reference
  together instead of joining them (1.2 to 0.3 seconds on 4.5 million
  rows), and `ensure_codes()` with a temporal code list joins only the
  distinct pairs of code and time with the list (1.6 to 0.2 seconds).
  The rows reported are the same.
* `add_spell_status()` converts the distinct periods to days, not the
  rows, and sorts the rows once for primo and ultimo.
* `describe_panel()` on a database table works with dbplyr 2.6.0.
* New `violations()` returns the rows that break a check: wrap the check in
  it, `violations(ensure_unique(persons, cpr))`. It replaces catching the
  `inshape_failure` condition by hand, where a check that passed handed
  back the whole data as if it were the violations.
* A check that aborts (`abort_msg`) now shows the first rows as an aligned
  table. The columns were run together, because the message was formatted
  twice; a warning was not affected.
* `ensure_unique()` and `describe_key()` stop when the key selects no
  columns, e.g. a `starts_with()` that matched nothing. The check passed
  before, with "Unique on" and no columns named.
* Grouped data no longer adds its grouping columns to a key or an id:
  `ensure_unique(group_by(df, year), cpr)` checked `year` and `cpr`.
* `ensure_codes()` takes `time` right after `codes`, before `na_ok`, as in
  `describe_codes()`. Name `na_ok` if it was passed by position.
* `ensure_matched()` and `ensure_valid_spells()` name their columns in the
  default messages, as the other checkpoints do, and counts in failure
  messages have thousands separators.
* Diagnostic columns in uniqueness, overlap and lifetime failures now get
  collision-safe names, preserving original columns in local and database
  violation sets.
* `describe_changes()` reports shared list and matrix columns it cannot
  compare in `columns_skipped` and in the printed summary.
* New `ensure_valid_spells()` checks missing starts and reversed boundaries,
  with `open_end = FALSE` to also reject missing ends.
* `ensure_codes()` accepts temporal code lists with `code`, `valid_from`
  and `valid_to`, plus a `time` selection. Inclusive and open boundaries,
  multiple intervals and missing observation times have explicit rules.
* New `ensure_matched()` checks coverage against a reference register, with
  composite and renamed keys and explicit missing-key matching. Both new
  checkpoints and temporal code checks support database and Arrow inputs.

* First version. The key, panel and spell checks move here from expectr and
  are renamed so the two packages cannot be confused:
  `expect_unique()` is now `ensure_unique()`, `expect_balanced()` is
  `ensure_balanced()` and `expect_no_overlap()` is `ensure_no_overlap()`.
  A failure signals `inshape_failure`.
* inshape is for interactive review of registers and writes nothing to
  disk: the offending rows are personal data. A failure shows the count and
  the first rows at the console and carries all of them on the condition,
  in memory. There is no `log` or `dump` argument, and no options: nothing
  is kept between calls either, and the engine runs on data.table's threads.
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
  partitioned hash on data.table's threads, and panels are checked as bit
  matrices. On 25 million rows `ensure_balanced()` went from 7.3 to 1.8 seconds and the
  grouping of a cpr column from 4.4 to 0.7.
* `spells_to_panel()` and `add_spell_status()` move here from daos,
  unchanged.
