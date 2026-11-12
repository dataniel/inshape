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
  expect_match(conditionMessage(cnd), "For all rows: violations(check_rows(big))", fixed = TRUE)

  # A call too long to read on one line is not repeated
  long <- rlang::catch_cnd(check_rows(data.frame(x = 1:12, a_long_column_name = 1, another_long_column_name = 2)))
  expect_match(conditionMessage(long), "Wrap the check in violations() to get all rows.", fixed = TRUE)

  # All rows are shown, so there is nothing to point to
  few <- rlang::catch_cnd(check_rows(data.frame(x = 1:3), warn_msg = "Few"))
  expect_no_match(conditionMessage(few), "violations()", fixed = TRUE)
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

test_that("a check writes nothing to disk, passed or failed", {
  dir <- withr::local_tempdir()
  df <- data.frame(cpr = c("0101011234", "0101011234"), year = 2020)
  withr::with_dir(dir, {
    expect_message(ensure_unique(df[1, ], cpr), "Unique on cpr")
    expect_warning(ensure_unique(df, cpr, year))
    try(ensure_unique(df, cpr, year, abort_msg = "Duplicates"), silent = TRUE)
  })
  expect_length(list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE), 0)
})

test_that("the checkpoints take no path to write to", {
  for (f in grep("^ensure_", getNamespaceExports("inshape"), value = TRUE)) {
    args <- names(formals(getExportedValue("inshape", f)))
    expect_false(any(c("log", "dump") %in% args), info = f)
  }
})

test_that("an aborting check keeps the preview aligned, as a warning does", {
  df <- data.frame(id = c(1, 22222), name = c("a", "bbbbbbbb"))
  lines <- function(cnd) strsplit(cli::ansi_strip(conditionMessage(cnd)), "\n")[[1]]
  warned  <- rlang::catch_cnd(check_rows(df), classes = "inshape_failure")
  aborted <- rlang::catch_cnd(check_rows(df, abort_msg = "Bad rows"),
                              classes = "inshape_failure")
  expect_s3_class(aborted, "error")
  expect_equal(lines(aborted), lines(warned))

  rows <- grep("^\\s+[12]\\s", lines(aborted), value = TRUE)
  expect_equal(regexpr("a", rows[1]), regexpr("bbbbbbbb", rows[2]),
               ignore_attr = TRUE)
})

test_that("the user's messages replace the descriptions of the check", {
  bad <- data.frame(x = 1)
  expect_message(check_rows(data.frame(), success_msg = NULL, warn_msg = NULL), "^.*OK")
  expect_message(check_rows(data.frame(), success_msg = NULL, warn_msg = "No x"),
                 "Check passed: No x", fixed = TRUE)
  expect_message(check_rows(data.frame(), success_msg = "Fine", abort_msg = "No x"),
                 "Fine", fixed = TRUE)
  expect_warning(check_rows(bad, warn_msg = NULL), "Bad rows")
  expect_error(check_rows(bad, warn_msg = "warned", abort_msg = "aborted"), "aborted")
})

test_that("large counts are written with thousands separators", {
  cnd <- rlang::catch_cnd(check_rows(data.frame(x = seq_len(12345))))
  expect_match(conditionMessage(cnd), "12,345 rows found", fixed = TRUE)
})
