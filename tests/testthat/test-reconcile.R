persons <- data.frame(
  cpr    = c("a", "b", "c", "d", "e", "f"),
  year   = c(2023, 2023, 2024, 2024, 2024, 2024),
  sex    = c("F", "M", "F", "F", "M", "X"),
  income = c(10, 20, 30, 40, 50, 60)
)
published <- data.frame(
  tid = c("2023", "2023", "2024", "2024", "2025"),
  sex = c("F", "M", "F", "M", "F"),
  n   = c(1, 1, 3, NA, 2)
)

test_that("ensure_reconciled() reports the cells that differ, both ways", {
  cnd <- rlang::catch_cnd(ensure_reconciled(persons, published, by = c(year = "tid", "sex")),
                          classes = "inshape_failure")
  v <- cnd$violations
  # 2024 F differs, 2024 X is not in the table, 2025 F is not in the data;
  # 2024 M is suppressed and not compared
  expect_equal(v$year, c(2024, 2024, 2025))
  expect_equal(v$sex, c("F", "X", "F"))
  expect_equal(v$data, c(2, 1, 0))
  expect_equal(v$published, c(3, NA, 2))
  expect_equal(v$difference, c(-1, NA, -2))
  msg <- cli::ansi_strip(conditionMessage(cnd))
  expect_match(msg, "Of 4 cells compared; 1 missing in the table, not compared", fixed = TRUE)
  expect_match(msg, "1 cell in the data but not in the table", fixed = TRUE)
  expect_match(msg, "tolerance = <largest accepted difference>", fixed = TRUE)
})

test_that("a matching table passes, and sum and tolerance work", {
  ok <- published[1:4, ]
  ok$n[3:4] <- c(2, 1)
  expect_message(ensure_reconciled(persons[persons$sex != "X", ], ok, by = c(year = "tid", "sex")),
                 "matches the table in 4 cells")
  sums <- data.frame(year = c(2023, 2024), total = c(30, 182))
  expect_warning(ensure_reconciled(persons, sums, by = "year", value = "total", sum = income),
                 "sum of income differs")
  expect_message(ensure_reconciled(persons, sums, by = "year", value = "total", sum = income,
                                   tolerance = 2), "matches")
  expect_error(ensure_reconciled(persons, rbind(ok, ok), by = c(year = "tid", "sex")),
               "more than one row")
})

test_that("ensure_reconciled() counts a database table where it lives", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  dplyr::copy_to(con, persons, "persons")
  remote <- violations(ensure_reconciled(dplyr::tbl(con, "persons"), published,
                                         by = c(year = "tid", "sex")))
  local <- violations(ensure_reconciled(persons, published, by = c(year = "tid", "sex")))
  expect_equal(remote, local)
})

account <- data.frame(
  year       = 2021:2024,
  population = c(56000, 56100, 56210, 56300),
  born       = c(800, 820, 790, 810),
  immigrated = c(2000, 2100, 2050, 2200),
  dead       = c(500, 520, 510, 530),
  emigrated  = c(2200, 2300, 2280, 2330)
)

test_that("ensure_stock_flow() finds the periods that do not add up", {
  cnd <- rlang::catch_cnd(
    ensure_stock_flow(account, year, population, inflow = c(born, immigrated),
                      outflow = c(dead, emigrated)),
    classes = "inshape_failure")
  v <- cnd$violations
  expect_equal(v$year, c(2023L, 2024L))
  expect_equal(v$expected, c(56150, 56360))
  expect_equal(v$difference, c(60, -60))
  expect_match(conditionMessage(cnd), "Difference: total 0, largest 60", fixed = TRUE)

  fixed <- account
  fixed$population[3] <- 56150
  expect_message(ensure_stock_flow(fixed, year, population, inflow = c(born, immigrated),
                                   outflow = c(dead, emigrated)), "adds up")
})

test_that("a stock at the start takes the flows of the period before, per group", {
  start <- data.frame(sex = rep(c("F", "M"), each = 3), year = rep(1:3, 2),
                      stock = c(10, 12, 13, 5, 5, 9), born = c(2, 1, 0, 0, 4, 0))
  expect_message(ensure_stock_flow(start, year, stock, inflow = born, by = sex,
                                   stock_at = "start"), "adds up")
  # counted as stocks at the end, none of the later periods adds up
  v <- violations(ensure_stock_flow(start, year, stock, inflow = born, by = sex))
  expect_equal(nrow(v), 4)
  expect_error(ensure_stock_flow(rbind(start, start), year, stock, inflow = born, by = sex),
               "more than one row")
})
