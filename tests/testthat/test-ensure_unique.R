df <- data.frame(
  cvr  = c("1", "2", "1", "3"),
  year = c(2024, 2024, 2024, 2025)
)

test_that("ensure_unique() passes on a unique key and returns data", {
  expect_message(ensure_unique(df[-3, ], cvr), "Unique on cvr")
  expect_equal(ensure_unique(df[-3, ], cvr), df[-3, ])
})

test_that("ensure_unique() reports duplicated rows grouped by dupid", {
  cnd <- rlang::catch_cnd(ensure_unique(df, cvr, year), classes = "inshape_failure")
  expect_match(conditionMessage(cnd), "Duplicate rows on cvr, year")
  expect_equal(nrow(cnd$violations), 2)
  expect_true("dupid" %in% names(cnd$violations))
  expect_false("isdup" %in% names(cnd$violations))
  expect_match(conditionMessage(cnd), "2 rows in 1 group\n")
})

test_that("the message separates exact copies from copies that differ", {
  df <- data.frame(
    cpr  = c("a", "a", "b", "b", "c", "c", "d"),
    year = c(2019, 2019, 2019, 2019, 2021, 2021, 2021),
    kom  = c("955", "955", "955", "956", "957", "957", "955"),
    sex  = c("F", "F", NA, "M", "M", "M", "F")
  )
  msg <- cli::ansi_strip(conditionMessage(
    rlang::catch_cnd(ensure_unique(df, cpr, year), classes = "inshape_failure")
  ))
  expect_match(msg, "6 rows in 3 groups\n", fixed = TRUE)
  expect_match(msg, "2 groups are exact copies", fixed = TRUE)
  # a missing and a present value differ
  expect_match(msg, "1 group differs in: kom (1), sex (1)", fixed = TRUE)
  expect_match(msg, "By year: 2019 (4), 2021 (2)", fixed = TRUE)
  # cpr has a value per group and shows no pattern
  expect_no_match(msg, "By cpr")
  expect_match(msg, "To drop the exact copies: dplyr::distinct(df)", fixed = TRUE)
  expect_match(msg, "dplyr::slice_max(df, <column>, by = c(cpr, year))", fixed = TRUE)
})

test_that("one group of identical copies reads as such, with no rule to pick", {
  msg <- conditionMessage(rlang::catch_cnd(ensure_unique(df, cvr, year)))
  expect_match(msg, "The copies are identical in every column", fixed = TRUE)
  expect_no_match(msg, "slice_max", fixed = TRUE)
})

test_that("a narrow console keeps the key and the columns that differ", {
  wide <- data.frame(cpr = c("x", "x", "y"), year = 2020, kom = c("955", "956", "955"))
  for (i in 1:20) wide[[paste0("variable_", i)]] <- 1.123456
  msg <- cli::ansi_strip(conditionMessage(rlang::catch_cnd(
    withr::with_options(list(width = 80), ensure_unique(wide, cpr, year))
  )))
  expect_match(msg, "dupid cpr    year kom", fixed = TRUE)
  expect_match(msg, "20 more columns not shown: variable_1, variable_2", fixed = TRUE)
  expect_match(msg, "For all rows and columns: violations(ensure_unique(wide, cpr, year))",
               fixed = TRUE)

  # When everything fits, nothing is left out
  msg <- conditionMessage(rlang::catch_cnd(ensure_unique(wide[1:4], cpr, year)))
  expect_no_match(msg, "not shown")
})

test_that("ensure_unique() puts dupid and the key columns first", {
  cnd <- rlang::catch_cnd(ensure_unique(df, year, cvr), classes = "inshape_failure")
  expect_equal(names(cnd$violations), c("dupid", "year", "cvr"))
})

test_that("ensure_unique() without columns checks full rows", {
  expect_message(ensure_unique(df[-3, ]), "Unique on all columns")
  expect_warning(ensure_unique(df), "Duplicate rows on all columns")
})

test_that("ensure_unique() orders the duplicates by group of first appearance", {
  df <- data.frame(id = c("b", "a", "b", "c", "a"), row = 1:5)
  cnd <- rlang::catch_cnd(ensure_unique(df, id), classes = "inshape_failure")
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

test_that("a key that selects no columns is an error, not a pass", {
  df <- data.frame(cpr = c("a", "a"), year = 2020)
  expect_error(ensure_unique(df, dplyr::starts_with("zzz")), "selects no columns")
  expect_error(describe_key(df, dplyr::starts_with("zzz")), "selects no columns")
  expect_error(ensure_unique(df[, 0]), "selects no columns")
})

test_that("grouping of the data does not add columns to the key", {
  df <- data.frame(cpr = c("a", "a", "b"), year = c(2020, 2021, 2020))
  grouped <- dplyr::group_by(df, year)
  # cpr is duplicated; cpr and year together are not
  expect_warning(out <- ensure_unique(grouped, cpr), "Duplicate rows on cpr$|Duplicate rows on cpr\n")
  expect_identical(out, grouped)
  expect_equal(describe_key(grouped, cpr)$key, "cpr")
  expect_no_message(
    expect_warning(ensure_balanced(grouped, cpr, year), "not balanced"),
    message = "grouping variables"
  )
})
