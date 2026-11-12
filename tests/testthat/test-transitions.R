education <- data.frame(
  cpr    = c("a", "a", "a", "b", "b", "c", "c", "d", "d"),
  year   = c(2019, 2020, 2021, 2019, 2020, 2021, 2019, 2019, 2020),
  status = c("not started", "enrolled", "completed",
             "enrolled", "completed", "not started", "completed",
             "completed", NA)
)

test_that("describe_transitions() counts units per pair of consecutive statuses", {
  d <- describe_transitions(education, cpr, year, status)
  expect_s3_class(d, "inshape_transitions")
  expect_equal(d$n_units, 4)
  # c is completed in 2019 and not started in 2021: rows are taken in time
  # order, not data order; d's missing status is left out
  expect_equal(d$n_transitions, 4)
  tab <- d$transitions
  expect_equal(tab$units[tab$from == "completed" & tab$to == "not started"], 1)
  expect_equal(tab$units[tab$from == "enrolled" & tab$to == "completed"], 2)
  expect_output(print(d), "Units per transition")
  expect_output(print(d), "Changing status: 4 of 4 pairs")
})

test_that("ensure_transitions() reports the forbidden transitions with the time they come from", {
  cnd <- rlang::catch_cnd(ensure_transitions(education, cpr, year, status, final = "completed"),
                          classes = "inshape_failure")
  v <- cnd$violations
  expect_equal(v$cpr, "c")
  expect_equal(v$transition, "completed -> not started")
  expect_equal(v$previous, 2019)
  msg <- cli::ansi_strip(conditionMessage(cnd))
  expect_match(msg, "By transition: completed -> not started (1)", fixed = TRUE)
  expect_match(msg, "carry_status(education, cpr, year, status, final = \"completed\")", fixed = TRUE)

  expect_message(ensure_transitions(education, cpr, year, status, forbid = "enrolled -> not started"),
                 "No forbidden transitions")
  expect_warning(ensure_transitions(education, cpr, year, status,
                                    forbid = "completed->not started"),
                 "Forbidden transitions")
})

test_that("the rule must be given and well written", {
  expect_error(ensure_transitions(education, cpr, year, status), "forbid")
  expect_error(ensure_transitions(education, cpr, year, status, forbid = "completed"),
               "from -> to")
  expect_error(describe_transitions(education, cpr, c(year, status), status), "exactly one")
})

test_that("a numeric status is compared as its number", {
  df <- data.frame(id = c(1, 1, 2, 2), t = c(1, 2, 1, 2), s = c(3L, 1L, 1L, 3L))
  v <- violations(ensure_transitions(df, id, t, s, forbid = "3 -> 1"))
  expect_equal(v$id, 1)
})

test_that("the transitions are the same in DuckDB as in memory", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  dplyr::copy_to(con, education, "education")
  tbl <- dplyr::tbl(con, "education")
  remote <- describe_transitions(tbl, cpr, year, status)
  local  <- describe_transitions(education, cpr, year, status)
  expect_equal(remote$transitions, local$transitions)
  expect_equal(remote$n_units, local$n_units)
  expect_equal(remote$n_transitions, local$n_transitions)

  v <- dplyr::collect(violations(ensure_transitions(tbl, cpr, year, status, final = "completed")))
  expect_equal(v$cpr, "c")
  expect_equal(v$transition, "completed -> not started")
  expect_equal(v$previous, 2019)

  # A numeric status is labelled as in memory, not as SQL casts it
  df <- data.frame(id = c(1, 1, 2, 2), t = c(1, 2, 1, 2), s = c(3, 1, 1, 3))
  dplyr::copy_to(con, df, "df")
  v <- dplyr::collect(violations(ensure_transitions(dplyr::tbl(con, "df"), id, t, s,
                                                    forbid = "3 -> 1")))
  expect_equal(v$transition, "3 -> 1")
})
