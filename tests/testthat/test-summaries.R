# The summary lines above the preview, and the hints below it

msg_of <- function(expr) {
  cnd <- rlang::catch_cnd(expr, classes = "inshape_failure")
  cli::ansi_strip(conditionMessage(cnd))
}

summary_of <- function(expr) {
  rlang::catch_cnd(expr, classes = "inshape_failure")$summary
}

panel <- data.frame(
  cpr  = c("a", "a", "a", "b", "b", "c"),
  year = c(2020, 2021, 2022, 2020, 2022, 2022)
)
spells <- data.frame(
  cpr   = c("a", "a", "b", "b", "c", "c"),
  start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-06-01",
                    "2020-01-01", "2020-03-01")),
  end   = as.Date(c("2020-12-31", NA, "2020-06-30", "2021-12-31",
                    "2020-01-31", "2020-12-31"))
)
persons <- data.frame(
  cpr  = c("a", "a", "b", "b", "c", "c"),
  year = c(2020, 2021, 2020, 2021, 2020, 2021),
  sex  = c("F", "F", "M", "F", "M", "F"),
  born = c(1, 1, 1, 2, 3, 3)
)

test_that("ensure_balanced() counts the units and the periods, and points to gaps_only", {
  msg <- msg_of(ensure_balanced(panel, cpr, year))
  expect_match(msg, "Missing for 2 units", fixed = TRUE)
  expect_match(msg, "By year: 2021 (2), 2020 (1)", fixed = TRUE)
  expect_match(msg, "ensure_balanced(panel, cpr, year, gaps_only = TRUE)", fixed = TRUE)
  expect_no_match(msg_of(ensure_balanced(panel, cpr, year, gaps_only = TRUE)), "gaps_only = TRUE")
})

test_that("the spell checks count units and point to merge_spells()", {
  msg <- msg_of(ensure_no_overlap(spells, cpr, start, end))
  expect_match(msg, "In 1 unit", fixed = TRUE)
  expect_match(msg, "merge_spells(spells, cpr, start, end)", fixed = TRUE)

  msg <- msg_of(ensure_no_gaps(spells, cpr, start, end))
  expect_match(msg, "In 1 unit", fixed = TRUE)
  expect_match(msg, "Gap length in days: shortest 29, median 29, longest 29", fixed = TRUE)
  expect_match(msg, "merge_spells(spells, cpr, start, end, max_gap = <length>)", fixed = TRUE)
})

test_that("ensure_constant() counts the units per column and shows the choice as a hole", {
  msg <- msg_of(ensure_constant(persons, cpr, sex, born))
  expect_match(msg, "In 2 units", fixed = TRUE)
  expect_match(msg, "Units per column: sex (2), born (1)", fixed = TRUE)
  expect_match(msg, "dplyr::mutate(persons, sex = <first, last or most common>, .by = cpr)",
               fixed = TRUE)
})

test_that("codes, missing values, unmatched keys and reasons are counted", {
  df <- data.frame(kom = c("955", "95", "95", "9", NA), year = 2024)
  expect_match(msg_of(ensure_codes(df, kom, "955")), "Codes: 95 (2), 9 (1)", fixed = TRUE)

  df <- data.frame(a = c(NA, 1, NA), b = c(NA, NA, 1), c = 1)
  expect_match(msg_of(ensure_complete(df)), "Missing per column: a (2), b (2)", fixed = TRUE)
  # one column: the row count says it all
  expect_length(summary_of(ensure_complete(df, a)), 0)

  income <- data.frame(cpr = c("a", "b", "b", "c"), year = 2024)
  expect_match(msg_of(ensure_matched(income, data.frame(cpr = "a", year = 2024), by = c("cpr", "year"))),
               "2 distinct keys missing", fixed = TRUE)

  bad <- data.frame(start = c(2020, NA, 2023, 2024), end = c(NA, 2022, 2022, 2020))
  expect_match(msg_of(ensure_valid_spells(bad, start, end)),
               "Reasons: end before start (2), missing start (1)", fixed = TRUE)
})

test_that("a pattern line needs the rows to gather on few values", {
  v <- data.frame(year = c(2019, 2019, 2019, 2021), cpr = c("a", "b", "c", "d"))
  expect_equal(pattern_lines(v, c("year", "cpr"), 4), "By year: 2019 (3), 2021 (1)")
  expect_equal(pattern_lines(v, "year", 4, groups = 2), character())
  expect_equal(fmt_values(c(2019, NA, 1e6)), c("2019", "NA", "1000000"))
  expect_equal(fmt_values(as.Date("2024-01-31")), "2024-01-31")
})

test_that("a hint names the data as given, or `data` for an expression", {
  expect_equal(data_label("persons"), "persons")
  expect_equal(data_label("dplyr::filter(persons, year > 2020)"), "data")
  expect_equal(code_cols(c("cpr", "my year")), "c(cpr, `my year`)")
})

test_that("the summaries are the same in DuckDB as in memory", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  db <- function(df) {
    name <- paste0("t", sample.int(1e6, 1))
    dplyr::copy_to(con, df, name)
    dplyr::tbl(con, name)
  }
  dups <- data.frame(
    cpr  = c("a", "a", "b", "b", "c", "c", "d"),
    year = c(2019, 2019, 2019, 2019, 2021, 2021, 2021),
    kom  = c("955", "955", "955", "956", "957", "957", "955"),
    sex  = c("F", "F", NA, "M", "M", "M", "F")
  )
  same <- function(check, df, ...) {
    expect_equal(summary_of(check(db(df), ...)), summary_of(check(df, ...)))
  }
  same(ensure_unique, dups, cpr, year)
  same(ensure_balanced, panel, cpr, year)
  same(ensure_no_overlap, spells, cpr, start, end)
  same(ensure_no_gaps, spells, cpr, start, end)
  same(ensure_constant, persons, cpr, sex, born)
  same(ensure_complete, data.frame(a = c(NA, 1, NA), b = c(NA, NA, 1)))
  same(ensure_codes, data.frame(kom = c("955", "95", "95", "9")), kom, "955")
  same(ensure_valid_spells, data.frame(start = c(2020, NA, 2023), end = c(NA, 2022, 2022)),
       start, end)

  # merge_spells() takes a data frame only, so a database table gets no hint
  expect_no_match(msg_of(ensure_no_overlap(db(spells), cpr, start, end)), "merge_spells")
})
