# Package index

## Describe

Look at the structure before choosing a rule. Each returns a summary
that prints, and judges nothing.

- [`describe_changes()`](https://dataniel.github.io/inshape/reference/describe_changes.md)
  : Describe what changed between two extracts of a register
- [`describe_codes()`](https://dataniel.github.io/inshape/reference/describe_codes.md)
  : Describe how the codes of a column change over periods
- [`describe_key()`](https://dataniel.github.io/inshape/reference/describe_key.md)
  : Describe how well columns work as a key
- [`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md)
  : Describe the structure of a panel
- [`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md)
  : Describe the structure of spell data
- [`describe_varying()`](https://dataniel.github.io/inshape/reference/describe_varying.md)
  : Describe which columns vary within a unit

## Checkpoints

Each checkpoint states one rule about the structure of the data, warns
or aborts with the offending rows, and returns its input, so it can sit
in a pipeline.

- [`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md)
  : Assert that key columns identify each row uniquely
- [`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
  : Assert that a panel is balanced, or has no gaps
- [`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md)
  : Assert that spells do not overlap within a unit
- [`ensure_constant()`](https://dataniel.github.io/inshape/reference/ensure_constant.md)
  : Assert that columns are constant within each unit
- [`ensure_within()`](https://dataniel.github.io/inshape/reference/ensure_within.md)
  : Assert that observations lie within each unit's lifetime
- [`ensure_codes()`](https://dataniel.github.io/inshape/reference/ensure_codes.md)
  : Assert that a column only holds codes from a code list
- [`ensure_valid_spells()`](https://dataniel.github.io/inshape/reference/ensure_valid_spells.md)
  : Assert that spell boundaries are valid
- [`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md)
  : Assert that every key occurs in a reference register
- [`violations()`](https://dataniel.github.io/inshape/reference/violations.md)
  : The rows that break a check
- [`checkpoints`](https://dataniel.github.io/inshape/reference/checkpoints.md)
  : Checkpoints: shared arguments, personal data and database tables

## Spells and panels

Merge spells recorded as several, convert spell data to a period panel,
or add the status from spells to a panel you already have.

- [`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md)
  : Merge spells that follow each other or overlap into one
- [`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md)
  : Turn spell data into a period panel with primo and ultimo status
- [`add_spell_status()`](https://dataniel.github.io/inshape/reference/add_spell_status.md)
  : Add status from spell data to a panel you already have

## Package

- [`inshape`](https://dataniel.github.io/inshape/reference/inshape-package.md)
  [`inshape-package`](https://dataniel.github.io/inshape/reference/inshape-package.md)
  : inshape: structure checks for register microdata
