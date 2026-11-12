panel <- data.frame(
  cpr    = c("a", "a", "a", "b", "b", "c"),
  year   = c(2020, 2021, 2022, 2020, 2022, 2022),
  income = c(100, 110, 120, 90, 95, 50)
)

test_that("fill_panel() adds the gaps as rows of missing values, and says so", {
  expect_message(out <- fill_panel(panel, cpr, year), "Added 1 row for 1 unit")
  expect_equal(nrow(out), 7)
  expect_equal(out$cpr, c("a", "a", "a", "b", "b", "b", "c"))
  expect_equal(out$year, c(2020, 2021, 2022, 2020, 2021, 2022, 2022))
  expect_true(is.na(out$income[5]))
  # the filled panel passes the check that found the gap
  expect_message(ensure_balanced(out, cpr, year, gaps_only = TRUE), "No gaps")
})

test_that("gaps_only = FALSE gives every unit every period", {
  expect_message(out <- fill_panel(panel, cpr, year, gaps_only = FALSE),
                 "Added 3 rows for 2 units")
  expect_equal(nrow(out), 9)
  expect_message(ensure_balanced(out, cpr, year), "Balanced")
})

test_that("flag marks the added rows, and a full panel is left as it is", {
  out <- suppressMessages(fill_panel(panel, cpr, year, flag = "filled"))
  expect_equal(out$filled, c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE))
  expect_message(same <- fill_panel(panel[1:3, ], cpr, year), "Nothing to fill")
  expect_equal(same, tibble::as_tibble(panel[1:3, ]))
  expect_error(fill_panel(panel, cpr, year, flag = "income"), "new column")
})

test_that("the hint of ensure_balanced() points to fill_panel()", {
  msg <- conditionMessage(rlang::catch_cnd(ensure_balanced(panel, cpr, year)))
  expect_match(msg, "fill_panel(panel, cpr, year, gaps_only = FALSE)", fixed = TRUE)
})

test_that("fill_panel() returns a query for a database table", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  dplyr::copy_to(con, panel, "panel")
  expect_message(out <- fill_panel(dplyr::tbl(con, "panel"), cpr, year, flag = "filled"),
                 "Added 1 row for 1 unit")
  expect_s3_class(out, "tbl_lazy")
  local <- dplyr::arrange(dplyr::collect(out), cpr, year)
  expect_equal(local$year, c(2020, 2021, 2022, 2020, 2021, 2022, 2022))
  expect_equal(sum(local$filled), 1)
  expect_true(is.na(local$income[local$filled]))
})
