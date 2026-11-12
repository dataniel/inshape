d <- function(x) as.Date(x)

spells <- data.frame(
  cpr   = c("a", "a", "b", "b", "c", "c", "c", "d", "d"),
  start = d(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-07-04",
              "2020-01-01", "2020-02-01", "2020-06-01", "2010-01-01", "2015-01-01")),
  end   = d(c("2020-12-31", NA,           "2020-06-30", "2021-12-31",
              "2020-04-30", "2020-02-10", "2020-12-31", NA,           "2016-01-01"))
)

gaps <- function(...) {
  rlang::catch_cnd(ensure_no_gaps(...), classes = "inshape_failure")$violations
}

test_that("the spell after each gap is reported with the length of the gap", {
  v <- gaps(spells, cpr, start, end)
  # a is adjacent; c's gap is counted from the latest end (30 April), not
  # from the nested spell above; d is covered by an ongoing spell
  expect_equal(v$cpr, c("b", "c"))
  expect_equal(v$start, d(c("2020-07-04", "2020-06-01")))
  expect_equal(v$gap, c(3L, 31L))
  expect_equal(names(v), c("gap", "cpr", "start", "end"))
})

test_that("max_gap accepts gaps up to that length", {
  expect_equal(gaps(spells, cpr, start, end, max_gap = 3)$cpr, "c")
  expect_message(out <- ensure_no_gaps(spells, cpr, start, end, max_gap = 31),
                 "No gaps between spells longer than 31 days per cpr")
  expect_identical(out, spells)
  expect_error(ensure_no_gaps(spells, cpr, start, end, max_gap = -1), "max_gap")
  expect_error(ensure_no_gaps(spells, cpr, start, end, max_gap = 1.5), "max_gap")
})

test_that("the message names the unit of the gaps", {
  cnd <- rlang::catch_cnd(ensure_no_gaps(spells, cpr, start, end, max_gap = 1),
                          classes = "inshape_failure")
  expect_match(conditionMessage(cnd), "longer than 1 day per cpr", fixed = TRUE)
  expect_match(conditionMessage(cnd), "Gap length in days: shortest 3", fixed = TRUE)

  years <- data.frame(id = c(1, 1), from = c(2015, 2020), to = c(2016, 2021))
  cnd <- rlang::catch_cnd(ensure_no_gaps(years, id, from, to, max_gap = 2),
                          classes = "inshape_failure")
  expect_match(conditionMessage(cnd), "longer than 2 periods per id", fixed = TRUE)
  expect_match(conditionMessage(cnd), "Gap length in periods: shortest 3", fixed = TRUE)
})

test_that("the message counts the rows, and abort_msg aborts", {
  expect_warning(ensure_no_gaps(spells, cpr, start, end),
                 "Gaps between spells per cpr\n.*2 rows\n")
  expect_error(ensure_no_gaps(spells, cpr, start, end, abort_msg = "Holes"),
               "Holes", class = "inshape_failure")
})

test_that("unusable spells are ignored and row order does not matter", {
  messy <- rbind(
    spells,
    data.frame(cpr = c("b", "b"), start = d(c(NA, "2020-07-02")),
               end = d(c("2020-07-03", "2020-07-01")))
  )
  set.seed(1)
  v <- gaps(messy[sample(nrow(messy)), ], cpr, start, end)
  expect_equal(v$gap, c(3L, 31L))
})

test_that("whole numbers, several id columns and an existing gap column work", {
  jobs <- data.frame(
    cvr  = c(1, 1, 1, 2, 2),
    unit = c("x", "x", "y", "x", "x"),
    from = c(2010, 2013, 2011, 2010, 2011),
    to   = c(2011, 2015, 2012, 2010, 2012),
    gap  = "kept"
  )
  v <- gaps(jobs, c(cvr, unit), from, to)
  expect_equal(names(v), c("gap.1", "cvr", "unit", "from", "to", "gap"))
  expect_equal(v$gap.1, 1L)
  expect_equal(v$from, 2013)
  expect_equal(v$gap, "kept")
})

test_that("no rows and no gaps pass", {
  expect_message(ensure_no_gaps(spells[0, ], cpr, start, end), "No gaps between spells per cpr")
  expect_message(ensure_no_gaps(spells[spells$cpr %in% c("a", "d"), ], cpr, start, end),
                 "No gaps")
})
