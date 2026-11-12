# inshape 0.1.0

* Groups and relations, built so they fit families, households,
  workplaces and school classes alike, with no definition of a family
  built in: `describe_groups()` counts the groups per composition of
  roles; `ensure_counts()` requires a count per role and group, such as
  exactly one reference person or at most two parents; and
  `ensure_references()` checks a column pointing to another row, such as a
  spouse, which must be found, not be the row itself, point back with
  `mutual = TRUE`, and agree on `same` columns such as the family.
* Events: `describe_events()` counts events per unit, per period and per
  type and the time between a unit's events; `ensure_sequence()` requires
  one event before another, such as enrolment before an exam.
* `?ensure_constant` shows how it checks hierarchies, such as settlements
  within municipalities.

* inshape now also asks whether the numbers add up. New
  `ensure_reconciled()` counts or sums microdata by the dimensions of a
  published table you give it and reports the cells that differ, both
  ways, with a `tolerance` for tables rounded for disclosure; suppressed
  cells are not compared. New `ensure_stock_flow()` checks that a stock is
  the stock before plus the inflows minus the outflows, per period and
  group, with the stock counted at the end or the start of each period.

* New `describe_transitions()` and `ensure_transitions()` for a status that
  follows a unit over time. The description is a table of units per
  transition, where impossible transitions show as cells that should be
  empty; the check forbids transitions written as `"completed -> not
  started"`, or every change away from a `final` status, and counts the
  rows per transition. Each observation is compared with the unit's next
  one, whatever the distance, and spells work with their start as `time`.
* New `carry_status()` fixes those transitions when the rule is given: a
  `final` status holds once reached, or the status never falls in an
  `order`. The result goes to a new column by default, and the message
  counts the rows and units per change.
* New `fill_panel()` adds the missing unit-periods of a panel as rows of
  missing values and says how many; `ensure_balanced()` points to it.

* New `ensure_panel()`, `ensure_spells()` and `ensure_lookup()` run the
  checks a panel, a set of spells or a lookup table nearly always needs and
  report them in one overview: what passed, what failed with its counts,
  and the call that gives the rows. All checks run, so every problem shows
  at once; overlaps and gaps wait until the spells are valid.
  `violations()` on a wrapper names the single checks to wrap instead.
* The seven `describe_*()` summaries print in one layout: the size, then
  the problems, then the neutral counts, then the tables. A problem that is
  present has a warning sign and one that could be there but is not a
  tick, so "Ongoing: 12,400" and "Ending before they start: 3" no longer
  look alike. `describe_varying()` flags columns that vary for under 1% of
  units as nearly constant. The returned objects are unchanged.
* A failed structure check now shows the pattern before the rows: exact
  copies against copies that differ, and in which columns
  (`ensure_unique()`); units and periods (`ensure_balanced()`); codes,
  missing values per column, units per varying column, gap lengths and
  reasons; and the values that half the rows, or all of them on a few
  values, share, such as `By year: 2019 (388), 2021 (24)`. Counts are
  computed only on failure, as queries on a database table.
* The message ends with the next step as code to copy, with the column
  names filled in: `violations(ensure_unique(persons, cpr, year))`,
  `dplyr::distinct()` for exact copies, `merge_spells()` for overlaps and
  gaps, `gaps_only = TRUE` for a panel with late entries. Where the fix
  takes a choice, the code has a hole in it, such as `<column>`.
* On a console too narrow for all columns, the preview keeps the key, the
  diagnostic column and the columns that explain the failure, and names
  the ones it leaves out.

* The general checkpoints from the expectr package are now part of
  inshape, renamed to the `ensure_` prefix and built on the same reporting
  as the structure checks:

  | expectr              | inshape              |
  |----------------------|----------------------|
  | `expect_empty()`     | `ensure_empty()`     |
  | `expect_none()`      | `ensure_none()`      |
  | `expect_all()`       | `ensure_all()`       |
  | `tally_violations()` | `tally_violations()` |

  A failure signals `inshape_failure`, and `violations()` returns its rows.
* expectr's `log` and `dump` arguments and the options `expectr.log`,
  `expectr.dump` and `expectr.quiet` are gone: inshape never writes rows to
  disk itself. Save the rows from `violations()` if you need them. A call
  that still passes `log =` or `dump =` fails instead of being ignored:
  `ensure_empty()` with "unused argument", `ensure_none()` and
  `ensure_all()` because their conditions must not be named.

* New `describe_match()` says what a join will do before it is made: the
  keys found in both tables, only in the data and only in the reference,
  the rows without a match, and how many rows a left join returns when the
  reference repeats a key. Missing keys match nothing and are counted on
  their own. Keys of different types, such as a number against text, stop
  with an error instead of matching nothing.
* New `ensure_complete()` checks that columns have no missing values, all
  columns if none are named. The rows are reported with a `missing` column
  that names the columns missing in each, e.g. `"cpr, born"`. Both new
  functions take database and Arrow tables too.
* New `ensure_no_gaps()` checks that a unit's spells cover it without a
  break, e.g. that a resident has an address every day: the spell after
  each gap is reported with the length of the gap, and `max_gap` accepts
  short ones. It is the counterpart of `ensure_no_overlap()` and takes
  database and Arrow tables too.
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
