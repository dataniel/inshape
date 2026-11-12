moves <- data.frame(
  cpr  = c("a", "a", "a", "b", "c", "c"),
  date = as.Date(c("2020-03-01", "2021-06-15", "2021-06-15",
                   "2022-01-10", "2020-08-01", "2023-02-01")),
  type = c("in", "out", "out", "in", "in", "out")
)

test_that("describe_events() counts per unit, per period, per event and the time between", {
  d <- describe_events(moves, cpr, date, type)
  expect_s3_class(d, "inshape_events")
  expect_equal(d$n_events, 6)
  expect_equal(d$n_units, 3)
  expect_equal(d$per_unit$events, c(1, 2, 3))
  expect_equal(d$per_unit$units, c(1, 1, 1))
  expect_equal(d$by_period$period, 2020:2023)
  expect_equal(d$by_period$events, c(2, 2, 1, 1))
  expect_equal(d$by_event$event, c("in", "out"))
  expect_equal(d$between$n, 3)
  expect_equal(d$between$min, 0)
  expect_output(print(d), "Time between a unit's consecutive events, in days")
})

events <- data.frame(
  cpr   = c("a", "a", "b", "b", "c", "d", "d"),
  date  = as.Date(c("2020-08-15", "2021-06-01", "2021-06-01", "2021-08-15",
                    "2021-06-01", "2021-06-01", "2021-06-01")),
  event = c("enrolled", "exam", "exam", "enrolled", "exam", "enrolled", "exam")
)

test_that("ensure_sequence() reports events before their first, or without one", {
  cnd <- rlang::catch_cnd(ensure_sequence(events, cpr, date, event, first = "enrolled", then = "exam"),
                          classes = "inshape_failure")
  v <- cnd$violations
  # d enrols and takes the exam on the same day: in order
  expect_equal(v$cpr, c("b", "c"))
  expect_equal(v$reason, c("before enrolled", "no enrolled"))
  expect_match(conditionMessage(cnd), "exam before enrolled per cpr", fixed = TRUE)
  expect_message(ensure_sequence(events[events$cpr %in% c("a", "d"), ], cpr, date, event,
                                 first = "enrolled", then = "exam"),
                 "Every exam on or after enrolled")
  expect_error(ensure_sequence(events, cpr, date, event, first = c("a", "b"), then = "exam"),
               "one event")
})

test_that("the event functions give the same answers in DuckDB", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  dplyr::copy_to(con, moves, "moves")
  dplyr::copy_to(con, events, "events")
  remote <- describe_events(dplyr::tbl(con, "moves"), cpr, date, type)
  local  <- describe_events(moves, cpr, date, type)
  expect_equal(remote$per_unit, local$per_unit)
  expect_equal(as.numeric(remote$by_period$period), as.numeric(local$by_period$period))
  expect_equal(remote$by_period$events, local$by_period$events)
  expect_equal(remote$by_event, local$by_event)
  expect_equal(remote$between, local$between)

  v <- dplyr::collect(violations(ensure_sequence(dplyr::tbl(con, "events"), cpr, date, event,
                                                 first = "enrolled", then = "exam")))
  expect_equal(v$reason[order(v$cpr)], c("before enrolled", "no enrolled"))
})
