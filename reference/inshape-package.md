# inshape: checks for register microdata

Register microdata comes in a few shapes: one row per unit, one row per
unit and period (a panel), or one row per spell with a start and an end.
Every analysis assumes the shape is right: no duplicated persons, no
missing years in the middle of a panel, no person with two addresses at
once. inshape checks those assumptions, fast enough for full-population
registers. See
[`vignette("inshape")`](https://dataniel.github.io/inshape/articles/inshape.md).

## Details

### The name

Register data has a shape, and an analysis is written for one of them.
inshape asks whether the data is *in shape*, the shape the analysis
assumes: are the keys unique, the panels whole, the spells consistent,
before anyone builds on them?

### Where to start

- [`describe_key()`](https://dataniel.github.io/inshape/reference/describe_key.md),
  [`describe_panel()`](https://dataniel.github.io/inshape/reference/describe_panel.md),
  [`describe_spells()`](https://dataniel.github.io/inshape/reference/describe_spells.md),
  [`describe_varying()`](https://dataniel.github.io/inshape/reference/describe_varying.md)
  and
  [`describe_codes()`](https://dataniel.github.io/inshape/reference/describe_codes.md):
  look at the structure before choosing a rule.

- [`describe_changes()`](https://dataniel.github.io/inshape/reference/describe_changes.md):
  what changed since the last extract.

- [`describe_match()`](https://dataniel.github.io/inshape/reference/describe_match.md):
  what a join of two tables will do, before it is made.

- [`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md):
  a key identifies each row.

- [`ensure_complete()`](https://dataniel.github.io/inshape/reference/ensure_complete.md):
  the columns an analysis cannot do without have no missing values.

- [`ensure_balanced()`](https://dataniel.github.io/inshape/reference/ensure_balanced.md):
  every unit is observed in every period, or at least has no gaps.

- [`ensure_valid_spells()`](https://dataniel.github.io/inshape/reference/ensure_valid_spells.md):
  a spell has a start and does not end before it.

- [`ensure_no_overlap()`](https://dataniel.github.io/inshape/reference/ensure_no_overlap.md):
  a unit is in one spell at a time.

- [`ensure_no_gaps()`](https://dataniel.github.io/inshape/reference/ensure_no_gaps.md):
  and in one all the time, without a break between its spells.

- [`ensure_constant()`](https://dataniel.github.io/inshape/reference/ensure_constant.md):
  sex, birth date and the like do not change within a unit.

- [`ensure_within()`](https://dataniel.github.io/inshape/reference/ensure_within.md):
  no one is observed after death or emigration, or before birth.

- [`ensure_codes()`](https://dataniel.github.io/inshape/reference/ensure_codes.md):
  a coded column holds only codes from the code list, valid at the time
  of the row.

- [`ensure_matched()`](https://dataniel.github.io/inshape/reference/ensure_matched.md):
  every key occurs in a reference register.

- [`ensure_panel()`](https://dataniel.github.io/inshape/reference/ensure_panel.md),
  [`ensure_spells()`](https://dataniel.github.io/inshape/reference/ensure_panel.md)
  and
  [`ensure_lookup()`](https://dataniel.github.io/inshape/reference/ensure_panel.md):
  the checks a panel, a set of spells or a lookup table nearly always
  needs, in one call with one overview.

- [`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md),
  [`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md)
  and
  [`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md):
  any other rule dplyr can express, such as no negative amounts.

- [`tally_violations()`](https://dataniel.github.io/inshape/reference/tally_violations.md):
  count many rules at once, without judging.

- [`violations()`](https://dataniel.github.io/inshape/reference/violations.md):
  the rows that break a check, all of them.

- [`describe_groups()`](https://dataniel.github.io/inshape/reference/describe_groups.md),
  [`ensure_counts()`](https://dataniel.github.io/inshape/reference/ensure_counts.md)
  and
  [`ensure_references()`](https://dataniel.github.io/inshape/reference/ensure_references.md):
  families and other groups, and rows that point to each other.

- [`describe_events()`](https://dataniel.github.io/inshape/reference/describe_events.md)
  and
  [`ensure_sequence()`](https://dataniel.github.io/inshape/reference/ensure_sequence.md):
  events and their order.

- [`ensure_reconciled()`](https://dataniel.github.io/inshape/reference/ensure_reconciled.md)
  and
  [`ensure_stock_flow()`](https://dataniel.github.io/inshape/reference/ensure_stock_flow.md):
  the numbers add up, to a published table and over periods.

- [`describe_transitions()`](https://dataniel.github.io/inshape/reference/describe_transitions.md)
  and
  [`ensure_transitions()`](https://dataniel.github.io/inshape/reference/ensure_transitions.md):
  how a status changes over time, and the changes that cannot happen.

- [`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md):
  one spell recorded as several, merged into one.

- [`fill_panel()`](https://dataniel.github.io/inshape/reference/fill_panel.md):
  the missing unit-periods of a panel added as rows.

- [`carry_status()`](https://dataniel.github.io/inshape/reference/carry_status.md):
  a status that holds once reached, carried forward.

- [`spells_to_panel()`](https://dataniel.github.io/inshape/reference/spells_to_panel.md)
  and
  [`add_spell_status()`](https://dataniel.github.io/inshape/reference/add_spell_status.md):
  from spells to a panel.

The `ensure_*()` functions are checkpoints: they warn or abort with the
offending rows and return the data, so they sit in a pipeline. What they
share (messages, personal data, database tables) is described in
[checkpoints](https://dataniel.github.io/inshape/reference/checkpoints.md).

    persons |>
      ensure_unique(cpr, year, abort_msg = "Duplicate person-years") |>
      ensure_balanced(cpr, year, gaps_only = TRUE)

    gaps <- violations(ensure_balanced(persons, cpr, year, gaps_only = TRUE))

### Why a package of its own

The checkpoints and the spell conversions started in the daos package.
They moved here because they share an engine the rest of daos does not:
the grouping of keys such as cpr without sorting them, the compiled pass
over sorted spells, and one way of reporting a broken rule. The general
checkpoints,
[`ensure_none()`](https://dataniel.github.io/inshape/reference/ensure_none.md),
[`ensure_all()`](https://dataniel.github.io/inshape/reference/ensure_all.md),
[`ensure_empty()`](https://dataniel.github.io/inshape/reference/ensure_empty.md)
and
[`tally_violations()`](https://dataniel.github.io/inshape/reference/tally_violations.md),
spent a while in the expectr package and joined the rest here, since
they share the same contract, the same reporting and the same
dependencies.

## See also

Useful links:

- <https://dataniel.github.io/inshape>

- <https://github.com/dataniel/inshape>

- Report bugs at <https://github.com/dataniel/inshape/issues>

## Author

**Maintainer**: Daniel Madsen <danielmadsen@live.dk>

Authors:

- Daniel Madsen <danielmadsen@live.dk>
