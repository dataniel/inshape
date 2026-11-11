skip_if_not_installed("duckdb")
skip_if_not_installed("dbplyr")

# An in-memory DuckDB table holding `df`, closed when the test ends
local_duck <- function(df, env = parent.frame()) {
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  dplyr::copy_to(con, df, "t")
  dplyr::tbl(con, "t")
}

# The violations of a failing check, fetched into R
violations_of <- function(expr) {
  cnd <- rlang::catch_cnd(expr, classes = "inshape_failure")
  expect_false(is.null(cnd))
  v <- cnd$violations
  if (!is.data.frame(v)) v <- dplyr::collect(v)
  tibble::as_tibble(v)
}

df <- data.frame(
  id     = c("a", "a", "b", NA, NA, "c"),
  year   = c(2020L, 2020L, 2021L, 2020L, 2020L, 2022L),
  amount = c(1, -2, 3, NA, -5, 6)
)

test_that("a checkpoint returns the database table unchanged, violations as a query", {
  tbl <- local_duck(df)
  expect_message(out <- ensure_unique(tbl, id, year, amount), "Unique on")
  expect_s3_class(out, "tbl_lazy")

  cnd <- rlang::catch_cnd(ensure_unique(tbl, id, year), classes = "inshape_failure")
  expect_match(conditionMessage(cnd), "4 rows in 2 groups")
  expect_s3_class(cnd$violations, "tbl_lazy")
})

test_that("ensure_unique() finds the same duplicates as in memory", {
  tbl <- local_duck(df)
  remote <- violations_of(ensure_unique(tbl, id, year))
  local  <- violations_of(ensure_unique(df, id, year))

  expect_equal(names(remote), c("dupid", "id", "year", "amount"))
  key <- function(v) dplyr::arrange(v, id, amount)
  expect_equal(key(remote)$amount, key(local)$amount)
  # NULL keys form one group, as NA keys do in memory
  expect_equal(dplyr::n_distinct(remote$dupid), 2)
  expect_message(ensure_unique(tbl, id, year, amount), "Unique on id, year, amount")
})

test_that("ensure_balanced() finds the same missing unit-periods as in memory", {
  panel <- data.frame(
    cpr  = c("a", "a", "a", "b", "b", "c", NA, NA),
    year = c(2020L, 2021L, 2022L, 2020L, 2022L, 2022L, 2020L, 2022L)
  )
  tbl <- local_duck(panel)
  for (gaps in c(FALSE, TRUE)) {
    for (periods in list(NULL, 2019:2022)) {
      remote <- violations_of(ensure_balanced(tbl, cpr, year, periods = periods, gaps_only = gaps))
      local  <- violations_of(ensure_balanced(panel, cpr, year, periods = periods, gaps_only = gaps))
      expect_equal(remote, local, info = paste("gaps_only =", gaps, "periods =", toString(periods)))
    }
  }
  expect_message(ensure_balanced(tbl, cpr, year, periods = 2022L), "Balanced panel")
})

test_that("ensure_no_overlap() finds the same overlaps as in memory", {
  spells <- data.frame(
    cpr   = c("a", "a", "b", "b", "c", "c", "c", "d", "d"),
    start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-06-01",
                      "2020-01-01", "2020-03-01", "2020-05-01", "2010-01-01", "2015-01-01")),
    end   = as.Date(c("2020-12-31", NA, "2020-06-30", "2021-12-31",
                      "2020-04-01", "2020-05-01", "2020-12-31", NA, "2016-01-01"))
  )
  tbl <- local_duck(spells)
  remote <- violations_of(ensure_no_overlap(tbl, cpr, start, end))
  local  <- violations_of(ensure_no_overlap(spells, cpr, start, end))
  expect_equal(remote, local)
  expect_equal(remote$overlap_id, c(1, 1, 2, 2, 2, 3, 3))
})

test_that("ensure_constant() finds the same units as in memory", {
  persons <- data.frame(
    cpr = c("a", "a", "b", "b", "c", "c", NA, NA),
    sex = c("F", "F", "M", "F", "M", NA, "F", "M")
  )
  tbl <- local_duck(persons)
  remote <- violations_of(ensure_constant(tbl, cpr, sex))
  local  <- violations_of(ensure_constant(persons, cpr, sex))
  key <- function(v) dplyr::arrange(v, cpr, sex)
  expect_equal(key(remote), key(local))
  expect_equal(unique(local$cpr), c(NA, "b"))
  expect_message(ensure_constant(local_duck(persons[3:6, ][-1, ]), cpr, sex), "Constant")
})

test_that("ensure_within() finds the same rows as in memory", {
  panel <- data.frame(
    cpr   = c("a", "a", "a", "b", "b", "c"),
    year  = c(2022L, 2023L, 2024L, 2022L, 2023L, NA),
    day   = as.Date(c("2022-06-01", "2023-06-01", "2024-06-01", "2022-06-01", "2023-06-01", NA)),
    born  = as.Date(c("1950-04-01", "1950-04-01", "1950-04-01", "2023-01-10", "2023-01-10", NA)),
    death = as.Date(c("2023-05-01", "2023-05-01", "2023-05-01", NA, NA, "2020-01-01"))
  )
  tbl <- local_duck(panel)
  key <- function(v) dplyr::arrange(v, cpr, year)
  for (time in c("year", "day")) {
    remote <- violations_of(ensure_within(tbl, dplyr::all_of(time), from = born, to = death))
    local  <- violations_of(ensure_within(panel, dplyr::all_of(time), from = born, to = death))
    expect_equal(key(remote), key(local), info = time)
  }
  remote <- violations_of(ensure_within(tbl, year, to = death))
  expect_equal(remote$outside, "after death")
  expect_message(ensure_within(local_duck(panel[4:5, ]), year, to = death),
                 "All rows: year until death")
})

test_that("a failed database check keeps all rows as a query on the condition", {
  tbl <- local_duck(df)
  cnd <- rlang::catch_cnd(ensure_unique(tbl, id, year), classes = "inshape_failure")
  expect_s3_class(cnd$violations, "tbl_lazy")
  expect_equal(nrow(dplyr::collect(cnd$violations)), 4)
})

test_that("Arrow tables are checked through DuckDB", {
  skip_if_not_installed("arrow")
  tbl <- arrow::arrow_table(df)
  expect_message(out <- ensure_unique(tbl, id, year, amount), "Unique on")
  expect_identical(out, tbl)
  expect_equal(nrow(violations_of(ensure_unique(tbl, id, year))), 4)
})

test_that("other objects are refused with a clear message", {
  expect_error(ensure_unique(list(x = 1), x), "database table or an Arrow table")
})

test_that("ensure_no_gaps() finds the same gaps as in memory", {
  spells <- data.frame(
    cpr   = c("a", "a", "b", "b", "c", "c", "c", "d", "d", NA, NA, "b", "b"),
    start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-07-04",
                      "2020-01-01", "2020-02-01", "2020-06-01", "2010-01-01", "2015-01-01",
                      "2020-01-01", "2020-03-01", NA, "2020-07-02")),
    end   = as.Date(c("2020-12-31", NA, "2020-06-30", "2021-12-31",
                      "2020-04-30", "2020-02-10", "2020-12-31", NA, "2016-01-01",
                      "2020-01-31", "2020-03-31", "2020-07-03", "2020-07-01")),
    gap   = "kept"
  )
  tbl <- local_duck(spells)
  for (max_gap in c(0, 3, 40)) {
    cnd <- rlang::catch_cnd(ensure_no_gaps(tbl, cpr, start, end, max_gap = max_gap),
                            classes = "inshape_failure")
    local <- rlang::catch_cnd(ensure_no_gaps(spells, cpr, start, end, max_gap = max_gap),
                              classes = "inshape_failure")
    if (is.null(local)) {
      expect_null(cnd)
      next
    }
    remote <- cnd$violations |>
      dplyr::arrange(!!!attr(cnd$violations, "inshape_order")) |>
      dplyr::collect()
    expect_equal(remote, local$violations, info = paste("max_gap =", max_gap))
  }
  expect_equal(nrow(violations_of(ensure_no_gaps(tbl, cpr, start, end))), 3L)

  years <- data.frame(id = c(1, 1, 2, 2), from = c(2010L, 2013L, 2010L, 2011L),
                      to = c(2011L, 2015L, 2010L, 2012L))
  expect_equal(violations_of(ensure_no_gaps(local_duck(years), id, from, to))$gap, 1L)
})

test_that("ensure_complete() finds the same rows as in memory", {
  register <- data.frame(
    row     = 1:8,
    cpr     = c("a", NA, "c", NA, "e", "f", NA, "h"),
    born    = as.Date(c("1980-05-01", NA, NA, "1975-02-11", "1990-01-01", NA, NA, "2001-07-07")),
    amount  = c(1, 2, NA, 4, 5, 6, NA, 8),
    missing = "kept"
  )
  tbl <- local_duck(register)
  same <- function(...) {
    remote <- dplyr::arrange(violations_of(ensure_complete(tbl, ...)), row)
    local  <- violations_of(ensure_complete(register, ...))
    expect_equal(remote, local)
    remote
  }
  expect_equal(same(cpr, born)$missing.1, c("cpr, born", "born", "cpr", "born", "cpr, born"))
  expect_equal(same(amount)$row, c(3L, 7L))
  all <- same()
  expect_equal(all$missing.1[all$row == 7], "cpr, born, amount")
  expect_equal(all$missing, rep("kept", 5))

  # Sorted by the columns missing, so the same combination sits together
  cnd <- rlang::catch_cnd(ensure_complete(tbl, cpr, born), classes = "inshape_failure")
  expect_match(conditionMessage(cnd), "5 rows in 3 groups")
  expect_s3_class(cnd$violations, "tbl_lazy")

  expect_message(out <- ensure_complete(tbl, row, missing), "Complete: row, missing")
  expect_s3_class(out, "tbl_lazy")
})

test_that("ensure_complete() takes an Arrow table", {
  skip_if_not_installed("arrow")
  tbl <- arrow::arrow_table(df)
  expect_equal(nrow(violations_of(ensure_complete(tbl, id))), 2)
  expect_equal(sort(violations_of(ensure_complete(tbl))$missing), c("id", "id, amount"))
  expect_message(out <- ensure_complete(tbl, year), "Complete: year")
  expect_identical(out, tbl)
})

test_that("ensure_none() checks a database table and returns it unchanged", {
  tbl <- local_duck(df)
  expect_message(out <- ensure_none(tbl, amount > 100), "No rows where amount > 100")
  expect_s3_class(out, "tbl_lazy")

  cnd <- rlang::catch_cnd(ensure_none(tbl, amount < 0), classes = "inshape_failure")
  expect_match(conditionMessage(cnd), "2 rows found")
  expect_s3_class(cnd$violations, "tbl_lazy")
  expect_equal(sort(dplyr::collect(cnd$violations)$amount), c(-5, -2))

  passed <- suppressMessages(violations(ensure_none(tbl, amount > 100)))
  expect_equal(nrow(dplyr::collect(passed)), 0)
})

test_that("ensure_none() refuses a condition that is not logical in a database", {
  tbl <- local_duck(df)
  expect_error(ensure_none(tbl, amount * 2), "must give a logical vector")
})
