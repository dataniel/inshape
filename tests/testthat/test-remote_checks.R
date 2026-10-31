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
  cnd <- rlang::catch_cnd(expr, classes = "lustrum_failure")
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

  cnd <- rlang::catch_cnd(ensure_unique(tbl, id, year), classes = "lustrum_failure")
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

test_that("a failed check on a database table can be dumped", {
  tbl <- local_duck(df)
  dir <- withr::local_tempdir()
  expect_warning(ensure_unique(tbl, id, year, warn_msg = "Duplicates", dump = dir),
                 "All rows written to")
  expect_equal(nrow(utils::read.csv(list.files(dir, full.names = TRUE))), 4)
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
