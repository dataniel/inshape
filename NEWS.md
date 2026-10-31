# lustrum 0.1.0

* First version. The key, panel and spell checks move here from expectr and
  are renamed so the two packages cannot be confused:
  `expect_unique()` is now `ensure_unique()`, `expect_balanced()` is
  `ensure_balanced()` and `expect_no_overlap()` is `ensure_no_overlap()`.
  Their options are `lustrum.log` and `lustrum.dump`, and a failure signals
  `lustrum_failure`.
* `spells_to_panel()` and `add_spell_status()` move here from daos,
  unchanged.
