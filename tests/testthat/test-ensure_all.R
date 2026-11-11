df <- data.frame(id = c(1, NA, 3), amount = c(10, -5, NA))

test_that("ensure_all() returns the full data, not the violations", {
  out <- suppressWarnings(ensure_all(df, amount >= 0))
  expect_equal(out, df)
  expect_invisible(ensure_all(df, is.na(id) | id > 0))
})

test_that("a missing value is a violation, unlike in ensure_none()", {
  cnd <- rlang::catch_cnd(ensure_all(df, amount >= 0), classes = "inshape_failure")
  expect_equal(cnd$violations$amount, c(-5, NA))

  none <- rlang::catch_cnd(ensure_none(df, amount < 0), classes = "inshape_failure")
  expect_equal(none$violations$amount, -5)
})

test_that("ensure_all() derives messages from the condition", {
  expect_message(ensure_all(df, amount < 100 | is.na(amount)),
                 "All rows meet amount < 100 | is.na(amount)", fixed = TRUE)
  expect_warning(ensure_all(df, amount >= 0),
                 "Found rows that do not meet amount >= 0", fixed = TRUE)
})

test_that("user messages and abort work as in ensure_empty()", {
  expect_message(ensure_all(df, is.na(id) | id > 0, warn_msg = "Ids"), "Check passed: Ids")
  expect_error(ensure_all(df, !is.na(id), abort_msg = "NA ids"), "NA ids",
               class = "inshape_failure")
})

test_that("several conditions must all hold", {
  d <- data.frame(a = c(1, 1, 1, NA), b = c(1, 0, NA, 0))
  cnd <- rlang::catch_cnd(ensure_all(d, a == 1, b == 1), classes = "inshape_failure")
  expect_equal(nrow(cnd$violations), 3)
  expect_match(conditionMessage(cnd), "a == 1 & b == 1", fixed = TRUE)
})

test_that("ensure_all() requires unnamed conditions and a table", {
  expect_error(ensure_all(df), "at least one condition")
  expect_error(ensure_all(df, amount = 0), "must not be named")
  expect_error(ensure_all(list(), x > 1), "must be a data frame")
})

test_that("errors name ensure_all() and the condition as written", {
  cnd <- rlang::catch_cnd(ensure_all(df, !is.na(id), abort_msg = "NA ids"))
  expect_equal(rlang::call_name(cnd$call), "ensure_all")

  typo <- rlang::catch_cnd(ensure_all(df, amuont >= 0))
  expect_equal(rlang::call_name(typo$call), "ensure_all")
  expect_match(conditionMessage(typo), "amuont >= 0", fixed = TRUE)
  expect_no_match(conditionMessage(typo), "if_else")
})

test_that("a condition that is not logical is refused, also for missing values", {
  expect_error(ensure_all(df, amount * 2), "could not be evaluated")
})

test_that("ensure_all() checks a database table where it lives", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  dplyr::copy_to(con, df, "t")
  tbl <- dplyr::tbl(con, "t")

  expect_message(out <- ensure_all(tbl, is.na(id) | id > 0), "All rows meet")
  expect_s3_class(out, "tbl_lazy")

  cnd <- rlang::catch_cnd(ensure_all(tbl, amount >= 0), classes = "inshape_failure")
  expect_match(conditionMessage(cnd), "2 rows found")
  expect_setequal(dplyr::collect(cnd$violations)$amount, c(-5, NA))

  expect_error(ensure_all(tbl, amount * 2), "must give a logical")
  expect_error(ensure_none(tbl, amount * 2), "Condition \"amount \\* 2\" must give a logical")
  expect_error(ensure_none(tbl, amuont < 0), "could not be evaluated")
  expect_no_warning(ensure_none(dplyr::group_by(tbl, id), amount > mean(amount, na.rm = TRUE) + 100))
})
