persons <- data.frame(
  cpr  = c("a", "b", "b", "c"),
  year = c(2024, 2024, 2024, 2025),
  sex  = c("F", "M", "F", "M")
)

test_that("violations() returns the rows of a failed check, without a message", {
  expect_silent(dups <- violations(ensure_unique(persons, cpr)))
  expect_s3_class(dups, "tbl_df")
  expect_equal(dups$cpr, c("b", "b"))
  expect_equal(dups$dupid, c(1L, 1L))
  expect_named(dups, c("dupid", "cpr", "year", "sex"))
})

test_that("violations() returns the rows of a check that aborts", {
  expect_silent(
    dups <- violations(ensure_unique(persons, cpr, abort_msg = "Duplicates"))
  )
  expect_equal(nrow(dups), 2)
})

test_that("violations() returns no rows, not the data, when the check passes", {
  expect_message(none <- violations(ensure_unique(persons, cpr, year, sex)), "Unique on")
  expect_s3_class(none, "tbl_df")
  expect_equal(nrow(none), 0)
  expect_named(none, names(persons))

  dt <- data.table::as.data.table(persons)
  expect_message(none <- violations(ensure_unique(dt, cpr, year, sex)))
  expect_equal(nrow(none), 0)
})

test_that("violations() returns the first failure of a pipeline", {
  expect_message(
    rows <- violations(
      persons |>
        ensure_unique(cpr, year, sex) |>
        ensure_constant(cpr, sex) |>
        ensure_unique(cpr)
    ),
    "Unique on cpr, year, sex"
  )
  expect_equal(rows$cpr, c("b", "b"))
  expect_false("dupid" %in% names(rows))
})

test_that("violations() rejects what is not a checkpoint", {
  expect_error(violations(1 + 1), "ensure_")
  expect_error(violations(nrow(persons)), "ensure_")
  expect_error(violations(stop("other error")), "other error")
})

test_that("violations() returns queries for a database table", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbWriteTable(con, "persons", persons)
  tbl <- dplyr::tbl(con, "persons")

  dups <- violations(ensure_unique(tbl, cpr))
  expect_s3_class(dups, "tbl_lazy")
  expect_equal(dplyr::collect(dups)$cpr, c("b", "b"))

  expect_message(none <- violations(ensure_unique(tbl, cpr, year, sex)))
  expect_s3_class(none, "tbl_lazy")
  expect_equal(nrow(dplyr::collect(none)), 0)
})
