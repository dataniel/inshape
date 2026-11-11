# inshape: structure checks for register microdata

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

- [`ensure_unique()`](https://dataniel.github.io/inshape/reference/ensure_unique.md):
  a key identifies each row.

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

- [`violations()`](https://dataniel.github.io/inshape/reference/violations.md):
  the rows that break a check, all of them.

- [`merge_spells()`](https://dataniel.github.io/inshape/reference/merge_spells.md):
  one spell recorded as several, merged into one.

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

The key, panel and spell checks started in the expectr package and the
spell conversions in daos. They moved here because they share an engine
the rest does not: the grouping of keys such as cpr without sorting
them, and the compiled pass over sorted spells. expectr keeps the
general checkpoints (`expect_empty()`, `expect_none()`), and the two
packages do not depend on each other; the `ensure_` prefix keeps their
functions apart in a script that uses both.

## See also

Useful links:

- <https://dataniel.github.io/inshape>

- <https://github.com/dataniel/inshape>

- Report bugs at <https://github.com/dataniel/inshape/issues>

## Author

**Maintainer**: Daniel Madsen <danielmadsen@live.dk>

Authors:

- Daniel Madsen <danielmadsen@live.dk>
