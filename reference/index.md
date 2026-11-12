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
- [`describe_match()`](https://dataniel.github.io/inshape/reference/describe_match.md)
  : Describe how the keys of two tables match
- [`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md)
  : Describe the structure of a panel
- [`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md)
  : Describe the structure of spell data
- [`describe_transitions()`](https://dataniel.github.io/inshape/reference/describe_transitions.md)
  : Describe the transitions between statuses over time
- [`describe_varying()`](https://dataniel.github.io/inshape/reference/describe_varying.md)
  : Describe which columns vary within a unit

## Rules

Any rule dplyr can express, stated as “the set of violations must be
empty”.
[`tally_violations()`](https://dataniel.github.io/inshape/reference/tally_violations.md)
counts many rules and judges nothing.

- [`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md)
  : Assert that a set of violations is empty
- [`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md)
  : Assert that no rows match a condition
- [`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md)
  : Assert that every row meets a condition
- [`tally_violations()`](https://dataniel.github.io/inshape/reference/tally_violations.md)
  : Count violations for several rules at once

## Common checks in one call

The structure checks a panel, a set of spells or a lookup table nearly
always needs, run together and reported in one overview.

- [`ensure_panel()`](https://dataniel.github.io/inshape/reference/ensure_panel.md)
  [`ensure_spells()`](https://dataniel.github.io/inshape/reference/ensure_panel.md)
  [`ensure_lookup()`](https://dataniel.github.io/inshape/reference/ensure_panel.md)
  : Check a panel, spells or a lookup table in one call

## Structure checks

Each checkpoint states one rule about the structure of the data, warns
or aborts with the offending rows, and returns its input, so it can sit
in a pipeline.

- [`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md)
  : Assert that key columns identify each row uniquely
- [`ensure_complete()`](https://dataniel.github.io/inshape/reference/ensure_complete.md)
  : Assert that columns have no missing values
- [`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md)
  : Assert that a panel is balanced, or has no gaps
- [`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md)
  : Assert that spells do not overlap within a unit
- [`ensure_no_gaps()`](https://dataniel.github.io/inshape/reference/ensure_no_gaps.md)
  : Assert that a unit's spells leave no gaps
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
- [`ensure_transitions()`](https://dataniel.github.io/inshape/reference/ensure_transitions.md)
  : Assert that a status only changes in allowed ways
- [`violations()`](https://dataniel.github.io/inshape/reference/violations.md)
  : The rows that break a check
- [`checkpoints`](https://dataniel.github.io/inshape/reference/checkpoints.md)
  : Checkpoints: shared arguments, personal data and database tables

## Groups, relations and events

Families, households and workplaces are groups of rows with roles;
spouses and parents are rows that point to each other; events have many
rows per unit. Three building blocks and two event functions cover them,
without a definition of a family built in.

- [`describe_groups()`](https://dataniel.github.io/inshape/reference/describe_groups.md)
  : Describe how groups are composed of roles
- [`ensure_counts()`](https://dataniel.github.io/inshape/reference/ensure_counts.md)
  : Assert how many rows of each role a group has
- [`ensure_references()`](https://dataniel.github.io/inshape/reference/ensure_references.md)
  : Assert that rows pointing to other rows find them, and agree
- [`describe_events()`](https://dataniel.github.io/inshape/reference/describe_events.md)
  : Describe events: how many per unit, per period and how far apart
- [`ensure_sequence()`](https://dataniel.github.io/inshape/reference/ensure_sequence.md)
  : Assert that events come in order

## Numbers

Beyond the shape: do the numbers add up, to a published table and over
periods?

- [`ensure_reconciled()`](https://dataniel.github.io/inshape/reference/ensure_reconciled.md)
  : Assert that microdata add up to a published table
- [`ensure_stock_flow()`](https://dataniel.github.io/inshape/reference/ensure_stock_flow.md)
  : Assert that a stock and its flows add up over periods

## Fixes

Fixes where the rule makes the result unambiguous. Each says what it
changed, and none guesses a value.

- [`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md)
  : Merge spells that follow each other or overlap into one
- [`fill_panel()`](https://dataniel.github.io/inshape/reference/fill_panel.md)
  : Add the missing unit-periods of a panel as rows
- [`carry_status()`](https://dataniel.github.io/inshape/reference/carry_status.md)
  : Let a status stand once it is reached

## Spells and panels

Convert spell data to a period panel, or add the status from spells to a
panel you already have.

- [`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md)
  : Turn spell data into a period panel with primo and ultimo status
- [`add_spell_status()`](https://dataniel.github.io/inshape/reference/add_spell_status.md)
  : Add status from spell data to a panel you already have

## Package

- [`inshape`](https://dataniel.github.io/inshape/reference/inshape-package.md)
  [`inshape-package`](https://dataniel.github.io/inshape/reference/inshape-package.md)
  : inshape: checks for register microdata
