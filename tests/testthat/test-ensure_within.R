panel <- data.frame(
  cpr   = c("a", "a", "a", "b", "b", "c", "d"),
  year  = c(2022, 2023, 2024, 2022, 2023, 2020, NA),
  born  = as.Date(c("1950-04-01", "1950-04-01", "1950-04-01", "2023-01-10",
                    "2023-01-10", NA, "2000-01-01")),
  death = as.Date(c("2023-05-01", "2023-05-01", "2023-05-01", NA, NA, NA, "2001-01-01"))
)

test_that("years after the year of death and before the year of birth are reported", {
  cnd <- rlang::catch_cnd(ensure_within(panel, year, from = born, to = death),
                          classes = "inshape_failure")
  v <- cnd$violations
  expect_equal(v$cpr, c("a", "b"))
  expect_equal(v$year, c(2024, 2022))
  expect_equal(v$outside, c("after death", "before born"))
  expect_equal(names(v)[1:4], c("outside", "year", "born", "death"))
  expect_match(conditionMessage(cnd), "Rows outside: year within born to death")
  expect_match(conditionMessage(cnd), "2 rows in 2 groups")
})

test_that("the year of death itself is within, and missing bounds are open", {
  expect_message(ensure_within(panel[c(1, 2, 6, 7), ], year, from = born, to = death),
                 "All rows: year within born to death")
})

test_that("dates are compared by day, and a year bound by year", {
  visits <- data.frame(
    day   = as.Date(c("2023-05-01", "2023-05-02", "2019-12-31")),
    death = as.Date("2023-05-01"),
    since = 2020
  )
  cnd <- rlang::catch_cnd(ensure_within(visits, day, from = since, to = death),
                          classes = "inshape_failure")
  expect_equal(cnd$violations$day, as.Date(c("2023-05-02", "2019-12-31")))
  expect_equal(cnd$violations$outside, c("after death", "before since"))

  years <- data.frame(year = 2010:2012, first = 2011L)
  cnd <- rlang::catch_cnd(ensure_within(years, year, from = first), classes = "inshape_failure")
  expect_equal(cnd$violations$year, 2010L)
  expect_match(conditionMessage(cnd), "year from first")
})

test_that("a single bound, a custom message and abort work", {
  expect_warning(ensure_within(panel, year, to = death, warn_msg = "Dead persons"),
                 "Dead persons")
  expect_error(ensure_within(panel, year, to = death, abort_msg = "Dead persons"),
               "Dead persons")
  expect_equal(suppressWarnings(ensure_within(panel, year, to = death)), panel)
})

test_that("arguments are validated", {
  expect_error(ensure_within(panel, year), "from.*to")
  expect_error(ensure_within(panel, c(year, cpr), to = death), "exactly one")
  expect_error(ensure_within(panel, cpr, to = death), "Date column or whole numbers")
})

test_that("years become their first or last day, leap years included", {
  y <- c(1900, 2000, NA, 1902)
  expect_equal(year_days(y, 1899, last = FALSE),
               as.double(as.Date(paste0(1899:2000, "-01-01"))))
  expect_equal(year_days(y, 1899, last = TRUE),
               as.double(as.Date(paste0(1899:2000, "-12-31"))))
})

test_that("a year compared with a date must be whole", {
  d <- data.frame(year = c(2020, 2020.5), death = as.Date("2021-01-01"))
  expect_error(ensure_within(d, year, to = death), "whole years")
})

test_that("a date bound by year counts the whole year as within", {
  d <- data.frame(day = as.Date(c("2019-12-31", "2020-01-01", "2024-12-31", "2025-01-01")),
                  from = 2020L, to = 2024L)
  cnd <- rlang::catch_cnd(ensure_within(d, day, from = from, to = to), classes = "inshape_failure")
  expect_equal(cnd$violations$day, as.Date(c("2019-12-31", "2025-01-01")))
})
