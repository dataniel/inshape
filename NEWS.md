# lustrum 0.1.0

* First version. The key, panel and spell checks move here from expectr and
  are renamed so the two packages cannot be confused:
  `expect_unique()` is now `ensure_unique()`, `expect_balanced()` is
  `ensure_balanced()` and `expect_no_overlap()` is `ensure_no_overlap()`.
  Their options are `lustrum.log` and `lustrum.dump`, and a failure signals
  `lustrum_failure`.
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
* New `describe_varying()` shows which columns vary within units, and
  `ensure_constant()` requires columns such as sex or birth date to be
  constant within each unit; a missing value is not a contradiction.
* A compiled grouping engine: keys are compressed to integer ids by a
  partitioned, multi-threaded hash (`options(lustrum.threads = )`, default
  data.table's threads), and panels are checked as bit matrices. On 25
  million rows `ensure_balanced()` went from 7.3 to 1.8 seconds and the
  grouping of a cpr column from 4.4 to 0.7.
* The ids of the last three large key columns are kept for the session and
  reused when the same column is checked again, recognised by a checksum of
  its content (`options(lustrum.cache = FALSE)` turns it off). On 25 million
  rows each further check of a cpr column saves the 0.15–0.2 seconds of
  compressing it; see `?checkpoints`.
* `spells_to_panel()` and `add_spell_status()` move here from daos,
  unchanged.
