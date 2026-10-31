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
  expect_match(conditionMessage(cnd), "lustrum.dump", fixed = TRUE)

  # All rows are shown, so there is nothing to point to
  few <- rlang::catch_cnd(check_rows(data.frame(x = 1:3), warn_msg = "Few"))
  expect_no_match(conditionMessage(few), "lustrum.dump", fixed = TRUE)
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
  w <- rlang::catch_cnd(check_rows(df), classes = "lustrum_failure")
  expect_s3_class(w, "warning")
  expect_equal(w$violations, tibble::as_tibble(df))

  e <- rlang::catch_cnd(check_rows(df, abort_msg = "stop"), classes = "lustrum_failure")
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

test_that("log path is taken from the lustrum.log option", {
  log <- withr::local_tempfile(fileext = ".log")
  withr::local_options(lustrum.log = log)
  check_rows(data.frame(), success_msg = "From option")
  expect_match(readLines(log, encoding = "UTF-8"), "From option")
})

test_that("dump writes the violations to a CSV and names it in log and message", {
  dir <- withr::local_tempdir()
  log <- file.path(dir, "checks.log")
  df <- data.frame(id = 1:3, amount = c(-1, -2, -3))

  expect_warning(
    check_rows(df, warn_msg = "Negative amounts", log = log, dump = file.path(dir, "v")),
    "All rows written to"
  )
  files <- list.files(file.path(dir, "v"), full.names = TRUE)
  expect_length(files, 1)
  expect_match(basename(files), "_Negative_amounts\\.csv$")
  expect_equal(nrow(utils::read.csv(files)), 3)
  expect_match(readLines(log, encoding = "UTF-8"), basename(files), fixed = TRUE)
})

test_that("nothing is dumped when the check passes", {
  dir <- withr::local_tempdir()
  check_rows(data.frame(), dump = dir)
  expect_length(list.files(dir), 0)
})
