test_that("report_check() succeeds silently on empty data frame", {
  expect_no_warning(expect_no_error(
    check_rows(data.frame())
  ))
})

test_that("report_check() returns data invisibly", {
  df <- data.frame()
  expect_invisible(check_rows(df))
  expect_equal(check_rows(df), df)
})

test_that("report_check() warns when data has rows", {
  expect_warning(
    check_rows(data.frame(x = 1), warn_msg = "not empty"),
    "not empty"
  )
})

test_that("report_check() aborts when abort_msg is set and data has rows", {
  expect_error(
    check_rows(data.frame(x = 1), abort_msg = "must be empty"),
    "must be empty"
  )
})

test_that("failure messages report the row count and preview rows", {
  df <- data.frame(id = c(NA, 2, 3), name = c("a", "b", NA))
  expect_snapshot(check_rows(df, warn_msg = "Bad rows"))

  big <- data.frame(x = 1:12)
  cnd <- rlang::catch_cnd(check_rows(big, warn_msg = "Many"))
  expect_match(conditionMessage(cnd), "12 rows found")
  expect_match(conditionMessage(cnd), "7 more rows")
  expect_match(conditionMessage(cnd), "Catch the <inshape_failure> condition", fixed = TRUE)

  # All rows are shown, so there is nothing to point to
  few <- rlang::catch_cnd(check_rows(data.frame(x = 1:3), warn_msg = "Few"))
  expect_no_match(conditionMessage(few), "Catch the", fixed = TRUE)
})

test_that("inshape.preview sets the rows shown, and 0 shows none", {
  df <- data.frame(cpr = c("0101011234", "0202022345", "0303033456"))

  withr::local_options(inshape.preview = 1)
  msg <- conditionMessage(rlang::catch_cnd(check_rows(df, warn_msg = "Bad")))
  expect_match(msg, "3 rows found:", fixed = TRUE)
  expect_match(msg, "0101011234", fixed = TRUE)
  expect_no_match(msg, "0202022345", fixed = TRUE)

  withr::local_options(inshape.preview = 0)
  cnd <- rlang::catch_cnd(check_rows(df, warn_msg = "Bad"))
  msg <- cli::ansi_strip(conditionMessage(cnd))
  expect_match(msg, "3 rows found.", fixed = TRUE)
  expect_no_match(msg, "[0-9]{10}")
  expect_no_match(msg, "cpr", fixed = TRUE)
  expect_match(msg, "Catch the <inshape_failure> condition", fixed = TRUE)
  # The rows are still on the condition, for the script to keep or drop
  expect_equal(cnd$violations, tibble::as_tibble(df))
})

test_that("a group count is shown without rows too", {
  withr::local_options(inshape.preview = 0)
  df <- data.frame(cpr = c("a", "a", "b", "b"), year = 2020)
  msg <- conditionMessage(rlang::catch_cnd(ensure_unique(df, cpr, year)))
  expect_match(msg, "4 rows in 2 groups.", fixed = TRUE)
})

test_that("a bad inshape.preview is refused", {
  for (bad in list(-1, 1.5, NA, "5", c(1, 2))) {
    withr::local_options(inshape.preview = bad)
    expect_error(check_rows(data.frame(x = 1)), "whole number of rows")
  }
})

test_that("the preview keeps columns aligned and drops the tibble header", {
  df <- data.frame(id = c(1, 22222), name = c("a", "bbbbbbbb"))
  cnd <- rlang::catch_cnd(check_rows(df, warn_msg = "Bad rows"))
  msg <- cli::ansi_strip(conditionMessage(cnd))
  expect_no_match(msg, "A tibble")
  expect_no_match(msg, "print(n = ", fixed = TRUE)

  rows <- grep("^\\s+[12]\\s", strsplit(msg, "\n")[[1]], value = TRUE)
  expect_length(rows, 2)
  expect_equal(regexpr("a", rows[1]), regexpr("bbbbbbbb", rows[2]),
               ignore_attr = TRUE)
})

test_that("messages are shown literally, braces included", {
  expect_warning(
    check_rows(data.frame(cvr = "{oops}"), warn_msg = "CVR must match ^\\d{8}$"),
    "^\\d{8}$", fixed = TRUE
  )
  expect_message(
    check_rows(data.frame(), success_msg = "No {cvr} problems"),
    "No {cvr} problems", fixed = TRUE
  )
})

test_that("failures carry the violations in a classed condition", {
  df <- data.frame(x = 1:2)
  w <- rlang::catch_cnd(check_rows(df), classes = "inshape_failure")
  expect_s3_class(w, "warning")
  expect_equal(w$violations, tibble::as_tibble(df))

  e <- rlang::catch_cnd(check_rows(df, abort_msg = "stop"), classes = "inshape_failure")
  expect_s3_class(e, "error")
  expect_equal(e$violations, tibble::as_tibble(df))
})

test_that("report_check() logs success, warning and abort", {
  log <- withr::local_tempfile(fileext = ".log")
  check_rows(data.frame(), success_msg = "OK", log = log)
  suppressWarnings(check_rows(data.frame(x = 1:2), warn_msg = "Warned", log = log))
  try(check_rows(data.frame(x = 1), abort_msg = "Aborted", log = log), silent = TRUE)

  lines <- readLines(log, encoding = "UTF-8")
  expect_length(lines, 3)
  expect_match(lines[1], "| ✔ | OK | 0 rows", fixed = TRUE)
  expect_match(lines[2], "| ! | Warned | 2 rows", fixed = TRUE)
  expect_match(lines[3], "| ✖ | Aborted | 1 row", fixed = TRUE)
})

test_that("log path is taken from the inshape.log option", {
  log <- withr::local_tempfile(fileext = ".log")
  withr::local_options(inshape.log = log)
  check_rows(data.frame(), success_msg = "From option")
  expect_match(readLines(log, encoding = "UTF-8"), "From option")
})

test_that("a failed check writes no rows to disk, only a count to the log", {
  dir <- withr::local_tempdir()
  log <- file.path(dir, "checks.log")
  df <- data.frame(cpr = c("0101011234", "0202022345"), amount = c(-1, -2))

  withr::with_dir(dir, expect_warning(
    check_rows(df, warn_msg = "Negative amounts", log = log)
  ))
  expect_equal(list.files(dir, recursive = TRUE, all.files = TRUE), "checks.log")
  line <- readLines(log, encoding = "UTF-8")
  expect_true(endsWith(line, "| ! | Negative amounts | 2 rows"))
  expect_no_match(line, "[0-9]{10}")
})

test_that("the checkpoints have no dump argument", {
  for (f in grep("^ensure_", getNamespaceExports("inshape"), value = TRUE)) {
    expect_false("dump" %in% names(formals(getExportedValue("inshape", f))), info = f)
  }
})
