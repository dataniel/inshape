panel <- data.frame(
  cpr  = c("a", "a", "a", "b", "b", "c", "d", "d", "d", "d"),
  year = c(2020, 2021, 2022, 2020, 2022, 2022, 2020, 2021, 2022, 2022)
)

test_that("the counts describe units, gaps and duplicates", {
  p <- describe_panel(panel, cpr, year)
  expect_s3_class(p, "lustrum_panel")
  expect_equal(p$n_rows, 10)
  expect_equal(p$n_units, 4)
  expect_equal(p$n_complete, 2)     # a and d
  expect_equal(p$n_with_gaps, 1)    # b
  expect_equal(p$n_gap_cells, 1)
  expect_equal(p$n_dup_cells, 1)    # d in 2022
  expect_equal(p$n_dup_rows, 1)
})

test_that("by_period counts units, entries, exits and gaps, unknown at the edges", {
  p <- describe_panel(panel, cpr, year)
  expect_equal(p$by_period$period, c(2020, 2021, 2022))
  expect_equal(p$by_period$units, c(3, 2, 4))
  expect_equal(p$by_period$entries, c(NA, 0, 1))
  expect_equal(p$by_period$exits, c(0, 0, NA))
  expect_equal(p$by_period$gaps, c(0, 1, 0))
})

test_that("patterns and runs follow xtdescribe", {
  p <- describe_panel(panel, cpr, year)
  expect_equal(p$patterns$pattern, c("111", "1.1", "..1"))
  expect_equal(p$patterns$units, c(2, 1, 1))
  expect_equal(p$runs$runs, c(1, 2))
  expect_equal(p$runs$units, c(3, 1))
  expect_equal(nrow(describe_panel(panel, cpr, year, patterns = 1)$patterns), 1)
  expect_equal(nrow(describe_panel(panel, cpr, year, patterns = 0)$patterns), 0)
})

test_that("explicit periods show a period without units, and rows outside", {
  p <- describe_panel(panel, cpr, year, periods = 2019:2021)
  expect_equal(p$by_period$units, c(0, 3, 2))
  expect_equal(p$n_outside, 5)      # the rows in 2022
  expect_output(print(p), "Periods without units: 2019")
})

test_that("missing ids and periods are counted", {
  df <- data.frame(id = c("a", NA, "a", "b"), t = c(1, 1, NA, 2))
  p <- describe_panel(df, id, t)
  expect_equal(p$n_missing_id, 1)
  expect_equal(p$n_missing_time, 1)
  expect_equal(p$n_units, 3)
})

test_that("gap counts agree with ensure_balanced()", {
  set.seed(4)
  df <- data.frame(id = rep(1:300, each = 8), t = rep(1:8, 300))
  df <- df[-sample.int(nrow(df), 200), ]
  p <- describe_panel(df, id, t)
  cnd <- rlang::catch_cnd(ensure_balanced(df, id, t, gaps_only = TRUE),
                          classes = "lustrum_failure")
  expect_equal(nrow(cnd$violations), p$n_gap_cells)
  expect_equal(length(unique(cnd$violations$id)), p$n_with_gaps)
})

test_that("very long panels leave out the patterns", {
  withr::local_options(lustrum.bits = FALSE)
  p <- describe_panel(panel, cpr, year)
  expect_equal(nrow(p$patterns), 0)
  expect_equal(p$n_gap_cells, 1)
})

test_that("an empty panel is described without errors", {
  p <- describe_panel(panel[0, ], cpr, year)
  expect_equal(p$n_units, 0)
  expect_equal(nrow(p$by_period), 0)
  expect_output(print(p), "0 units")
})

test_that("the summary prints the counts", {
  expect_snapshot(print(describe_panel(panel, cpr, year)))
})

test_that("arguments are validated", {
  expect_error(describe_panel(panel, c(), year), "at least one column")
  expect_error(describe_panel(panel, cpr, c(cpr, year)), "exactly one column")
  expect_error(describe_panel(panel, cpr, year, patterns = -1), "non-negative")
  expect_error(describe_panel(list(), cpr, year), "data frame")
})
