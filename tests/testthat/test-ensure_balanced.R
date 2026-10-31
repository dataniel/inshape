panel <- data.frame(
  cpr  = c("a", "a", "a", "b", "b", "c"),
  year = c(2020, 2021, 2022, 2020, 2022, 2022),
  inc  = 1:6
)

violations <- function(...) {
  rlang::catch_cnd(ensure_balanced(...), classes = "lustrum_failure")$violations
}

test_that("ensure_balanced() lists every missing unit-period", {
  v <- violations(panel, cpr, year)
  expect_equal(v, tibble::tibble(cpr = c("b", "c", "c"), year = c(2021, 2020, 2021)))
})

test_that("gaps_only ignores late entry and early exit", {
  v <- violations(panel, cpr, year, gaps_only = TRUE)
  expect_equal(v, tibble::tibble(cpr = "b", year = 2021))
})

test_that("explicit periods find a period missing for everyone", {
  no_2021 <- panel[panel$year != 2021, ]
  expect_message(ensure_balanced(no_2021[no_2021$cpr == "a", ], cpr, year), "Balanced panel")
  v <- violations(no_2021[no_2021$cpr == "a", ], cpr, year, periods = 2020:2022)
  expect_equal(v$year, 2021)
})

test_that("observations outside periods and missing periods are ignored", {
  extra <- rbind(panel, data.frame(cpr = "c", year = c(NA, 1999), inc = 0))
  v <- violations(extra, cpr, year, periods = 2020:2022, gaps_only = TRUE)
  expect_equal(v$cpr, "b")
})

test_that("duplicated unit-periods do not count as observations twice", {
  dup <- rbind(panel, panel[panel$cpr == "b" & panel$year == 2020, ])
  v <- violations(dup, cpr, year, gaps_only = TRUE)
  expect_equal(v, tibble::tibble(cpr = "b", year = 2021))
})

test_that("several id columns are supported", {
  firms <- data.frame(cvr = c(1, 1, 1), lbnr = c(1, 2, 1), year = c(2020, 2020, 2021))
  v <- violations(firms, c(cvr, lbnr), year)
  expect_equal(v, tibble::tibble(cvr = 1, lbnr = 2, year = 2021))
})

test_that("a balanced panel passes and returns the data", {
  ok <- panel[panel$cpr == "a", ]
  expect_message(out <- ensure_balanced(ok, cpr, year), "Balanced panel: cpr by year")
  expect_equal(out, ok)
  expect_message(ensure_balanced(ok, cpr, year, gaps_only = TRUE), "No gaps in year")
})

test_that("abort_msg aborts and arguments are validated", {
  expect_error(ensure_balanced(panel, cpr, year, abort_msg = "Unbalanced"), "Unbalanced")
  expect_error(ensure_balanced(panel, cpr, c(year, inc)), "exactly one column")
})
