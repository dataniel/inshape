df <- data.frame(
  cvr  = c("1", "2", "1", "3"),
  year = c(2024, 2024, 2024, 2025)
)

test_that("ensure_unique() passes on a unique key and returns data", {
  expect_message(ensure_unique(df[-3, ], cvr), "Unique on cvr")
  expect_equal(ensure_unique(df[-3, ], cvr), df[-3, ])
})

test_that("ensure_unique() reports duplicated rows grouped by dupid", {
  cnd <- rlang::catch_cnd(ensure_unique(df, cvr, year), classes = "lustrum_failure")
  expect_match(conditionMessage(cnd), "Duplicate rows on cvr, year")
  expect_equal(nrow(cnd$violations), 2)
  expect_true("dupid" %in% names(cnd$violations))
  expect_false("isdup" %in% names(cnd$violations))
  expect_match(conditionMessage(cnd), "2 rows in 1 group:")
})

test_that("ensure_unique() puts dupid and the key columns first", {
  cnd <- rlang::catch_cnd(ensure_unique(df, year, cvr), classes = "lustrum_failure")
  expect_equal(names(cnd$violations), c("dupid", "year", "cvr"))
})

test_that("ensure_unique() without columns checks full rows", {
  expect_message(ensure_unique(df[-3, ]), "Unique on all columns")
  expect_warning(ensure_unique(df), "Duplicate rows on all columns")
})

test_that("ensure_unique() orders the duplicates by group of first appearance", {
  df <- data.frame(id = c("b", "a", "b", "c", "a"), row = 1:5)
  cnd <- rlang::catch_cnd(ensure_unique(df, id), classes = "lustrum_failure")
  expect_equal(cnd$violations$row, c(1L, 3L, 2L, 5L))
  expect_equal(cnd$violations$dupid, c(1L, 1L, 2L, 2L))
})

test_that("ensure_unique() works on a data.table and leaves it untouched", {
  dt <- data.table::data.table(id = c(2, 1, 2), y = 1:3)
  before <- data.table::copy(dt)
  expect_warning(ensure_unique(dt, id), "Duplicate rows on id")
  expect_identical(dt, before)
})

test_that("ensure_unique() aborts with abort_msg", {
  expect_error(ensure_unique(df, cvr, abort_msg = "Dup cvr"), "Dup cvr")
})
