test_that("ensure_empty() succeeds on an empty data frame", {
  expect_message(ensure_empty(data.frame()), "The dataset is empty.")
})

test_that("ensure_empty() returns data invisibly and unchanged", {
  df <- data.frame(x = integer())
  expect_invisible(ensure_empty(df))
  expect_identical(suppressMessages(ensure_empty(df)), df)

  full <- data.frame(x = 1:2)
  expect_identical(suppressWarnings(ensure_empty(full)), full)
})

test_that("ensure_empty() warns when data has rows", {
  expect_warning(ensure_empty(data.frame(x = 1)), "The dataset is not empty.")
  expect_warning(ensure_empty(data.frame(x = 1), warn_msg = "not empty"), "not empty")
})

test_that("ensure_empty() aborts when abort_msg is set and data has rows", {
  expect_error(
    ensure_empty(data.frame(x = 1), abort_msg = "must be empty"),
    "must be empty",
    class = "inshape_failure"
  )
})

test_that("ensure_empty() refuses input that is not a table", {
  expect_error(ensure_empty(list()), "must be a data frame")
  expect_error(ensure_empty("text"), "must be a data frame")
})

test_that("the failure message reports the row count and preview rows", {
  df <- data.frame(id = c(NA, 2, 3), name = c("a", "b", NA))
  cnd <- rlang::catch_cnd(ensure_empty(df, warn_msg = "Bad rows"))
  msg <- cli::ansi_strip(conditionMessage(cnd))
  expect_match(msg, "^Bad rows")
  expect_match(msg, "3 rows found:")
  expect_match(msg, "id name")

  big <- rlang::catch_cnd(ensure_empty(data.frame(x = 1:12), warn_msg = "Many"))
  expect_match(conditionMessage(big), "12 rows found")
  expect_match(conditionMessage(big), "violations()", fixed = TRUE)
})

test_that("messages are shown literally, braces included", {
  expect_warning(
    ensure_empty(data.frame(cvr = "{oops}"), warn_msg = "CVR must match ^\\d{8}$"),
    "^\\d{8}$", fixed = TRUE
  )
  expect_message(
    ensure_empty(data.frame(), success_msg = "No {cvr} problems"),
    "No {cvr} problems", fixed = TRUE
  )
})

test_that("the success message names the check when a message is given", {
  expect_message(ensure_empty(data.frame(), warn_msg = "NA ids"), "Check passed: NA ids")
  expect_message(ensure_empty(data.frame(), abort_msg = "NA ids"), "Check passed: NA ids")
})

test_that("failures carry the violations in a classed condition", {
  df <- data.frame(x = 1:2)
  w <- rlang::catch_cnd(ensure_empty(df), classes = "inshape_failure")
  expect_s3_class(w, "warning")
  expect_equal(w$violations, tibble::as_tibble(df))
  expect_equal(rlang::call_name(w$call), "ensure_empty")

  e <- rlang::catch_cnd(ensure_empty(df, abort_msg = "stop"), classes = "inshape_failure")
  expect_s3_class(e, "error")
  expect_equal(e$violations, tibble::as_tibble(df))
})

test_that("violations() returns all rows of a failed ensure_empty()", {
  df <- data.frame(x = 1:12)
  expect_equal(violations(ensure_empty(df)), tibble::as_tibble(df))
})

test_that("ensure_empty() has no log or dump argument", {
  expect_error(ensure_empty(data.frame(x = 1), dump = tempdir()), "unused argument")
  expect_error(ensure_empty(data.frame(x = 1), log = tempfile()), "unused argument")
})
