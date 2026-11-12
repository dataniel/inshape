education <- data.frame(
  cpr    = c("a", "a", "a", "b", "b", "b", "c"),
  year   = c(2019, 2021, 2020, 2019, 2020, 2021, 2020),
  status = c("enrolled", "enrolled", "completed",
             "not started", "enrolled", NA, "completed")
)

test_that("a final status holds in every later observation, in a new column", {
  expect_message(out <- carry_status(education, cpr, year, status, final = "completed"),
                 "Changed 1 row in 1 unit")
  # rows keep their order; a's 2021 is after its 2020 completion
  expect_equal(out$status_carried,
               c("enrolled", "completed", "completed", "not started", "enrolled", NA, "completed"))
  expect_equal(out$status, education$status)
  expect_message(carry_status(education, cpr, year, status, final = "completed"),
                 "enrolled -> completed: 1 row in 1 unit")
})

test_that("order keeps the highest status so far, and fills a later missing one", {
  levels <- data.frame(cpr = c("a", "a", "a", "a", "b"), year = c(2019:2022, 2019),
                       level = c(1, 3, 2, NA, NA))
  out <- suppressMessages(carry_status(levels, cpr, year, level, order = 1:4, name = "level"))
  expect_equal(out$level, c(1, 3, 3, 3, NA))
  expect_error(carry_status(levels, cpr, year, level, order = 1:2), "Not in it")
})

test_that("the rule is required once, and nothing to change is said", {
  expect_error(carry_status(education, cpr, year, status), "either")
  expect_error(carry_status(education, cpr, year, status, final = "x", order = "y"), "either")
  expect_error(carry_status(education, cpr, year, status, final = "completed", name = "year"),
               "new column")
  expect_message(carry_status(education[4:5, ], cpr, year, status, final = "completed"),
                 "Nothing to change")
})

test_that("a carried status passes the transition check", {
  out <- suppressMessages(carry_status(education, cpr, year, status, final = "completed",
                                       name = "status"))
  expect_message(ensure_transitions(out, cpr, year, status, final = "completed"),
                 "No forbidden transitions")
})

test_that("carry_status() gives the same result in DuckDB", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  dplyr::copy_to(con, education, "education")
  tbl <- dplyr::tbl(con, "education")
  expect_message(out <- carry_status(tbl, cpr, year, status, final = "completed"),
                 "enrolled -> completed: 1 row in 1 unit")
  expect_s3_class(out, "tbl_lazy")
  remote <- dplyr::arrange(dplyr::collect(out), cpr, year)
  local  <- dplyr::arrange(suppressMessages(carry_status(education, cpr, year, status,
                                                         final = "completed")), cpr, year)
  expect_equal(remote$status_carried, local$status_carried)

  levels <- data.frame(cpr = c("a", "a", "a", "a"), year = 2019:2022, level = c(1, 3, 2, NA))
  dplyr::copy_to(con, levels, "levels")
  out <- suppressMessages(carry_status(dplyr::tbl(con, "levels"), cpr, year, level,
                                       order = 1:4, name = "level"))
  expect_equal(dplyr::arrange(dplyr::collect(out), year)$level, c(1, 3, 3, 3))
})
