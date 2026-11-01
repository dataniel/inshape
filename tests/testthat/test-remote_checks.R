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

test_that("with no preview, a database check reports counts and keeps the query", {
  withr::local_options(inshape.preview = 0)
  tbl <- local_duck(df)
  cnd <- rlang::catch_cnd(ensure_unique(tbl, id, year), classes = "inshape_failure")
  msg <- cli::ansi_strip(conditionMessage(cnd))
  expect_match(msg, "4 rows in 2 groups.", fixed = TRUE)
  expect_no_match(msg, "dupid", fixed = TRUE)
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
