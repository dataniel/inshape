df <- data.frame(id = c(1, NA, 3), amount = c(10, -5, NA))

test_that("ensure_none() returns the full data, not the violations", {
  out <- suppressWarnings(ensure_none(df, amount < 0))
  expect_equal(out, df)
  expect_invisible(ensure_none(df, amount > 100))
})

test_that("ensure_none() can be chained in a pipeline", {
  out <- df |>
    ensure_none(amount > 100) |>
    ensure_none(id > 10)
  expect_equal(out, df)
})

test_that("ensure_none() derives messages from the condition", {
  expect_message(ensure_none(df, amount > 100), "No rows where amount > 100")
  expect_warning(ensure_none(df, amount < 0), "Found rows where amount < 0")
})

test_that("user messages and abort work as in ensure_empty()", {
  expect_message(ensure_none(df, amount > 100, warn_msg = "Big"), "Check passed: Big")
  expect_error(ensure_none(df, is.na(id), abort_msg = "NA ids"), "NA ids",
               class = "inshape_failure")
})

test_that("NA in a condition is not a violation, as in filter()", {
  expect_no_warning(ensure_none(df, amount > 50))
})

test_that("several conditions are combined with &", {
  cnd <- rlang::catch_cnd(ensure_none(df, amount < 20, id > 0),
                          classes = "inshape_failure")
  expect_equal(nrow(cnd$violations), 1)
  expect_match(conditionMessage(cnd), "amount < 20 & id > 0", fixed = TRUE)
})

test_that("ensure_none() requires a condition and a data frame", {
  expect_error(ensure_none(df), "at least one condition")
  expect_error(ensure_none(list(), x > 1), "must be a data frame")
})

test_that("errors name ensure_none() as the caller", {
  cnd <- rlang::catch_cnd(ensure_none(df, is.na(id), abort_msg = "NA ids"))
  expect_equal(rlang::call_name(cnd$call), "ensure_none")

  typo <- rlang::catch_cnd(ensure_none(df, amuont < 0))
  expect_equal(rlang::call_name(typo$call), "ensure_none")
  expect_match(conditionMessage(typo), "amuont < 0", fixed = TRUE)
  expect_match(conditionMessage(typo), "could not be evaluated")
})

test_that("violations() returns the rows of a failed ensure_none()", {
  v <- violations(ensure_none(df, amount < 20))
  expect_equal(v$amount, c(10, -5))
  expect_equal(nrow(suppressMessages(violations(ensure_none(df, amount > 100)))), 0)
})

test_that("ensure_none() returns grouped data unchanged", {
  g <- dplyr::group_by(df, id)
  expect_identical(suppressWarnings(ensure_none(g, amount < 0)), g)
})
