d <- function(x) as.Date(x)

education <- data.frame(
  cpr    = c("a", "a", "b"),
  start  = d(c("2018-08-15", "2021-08-15", "2019-08-15")),
  end    = d(c("2021-06-20", NA,           "2020-03-01")),
  status = c("passed", "in progress", "dropped out")
)

test_that("a yearly panel gets the same status as spells_to_panel()", {
  for (mode in c("state", "outcome")) {
    for (pr in c("previous_ultimo", "first_day")) {
      p <- spells_to_panel(education, cpr, start, end, status, from = 2017, to = 2023,
                           status_is = mode, primo = pr)
      panel <- p[, c("cpr", "year")]
      panel <- panel[sample(nrow(panel)), ]  # row order must not matter
      got <- add_spell_status(panel, education, cpr, year, start, end, status,
                              status_is = mode, primo = pr)
      want <- dplyr::left_join(panel, p, by = c("cpr", "year"))
      expect_equal(got$status_primo, want$primo)
      expect_equal(got$status_ultimo, want$ultimo)
    }
  }
})

test_that("quarters and months agree with spells_to_panel() too", {
  x <- data.frame(id = "a", start = d(c("2020-01-01", "2020-09-01")),
                  end = d(c("2020-08-31", "2021-03-31")), s = c("enrolled", "leave"))
  for (b in c("quarter", "month")) {
    p <- spells_to_panel(x, id, start, end, s, by = b)
    got <- add_spell_status(p[, c("id", "year", b)], x, id, c(year, !!rlang::sym(b)),
                            start, end, s, by = b)
    expect_equal(got$s_primo, p$primo)
    expect_equal(got$s_ultimo, p$ultimo)
  }
})

test_that("a Date column gives the status on that day", {
  events <- data.frame(cpr = c("a", "a", "b", "b"),
                       date = d(c("2019-05-01", "2021-07-01", "2020-02-29", "2020-03-01")))
  # the outcome applies from the end date on
  got <- add_spell_status(events, education, cpr, date, start, end, status,
                          status_is = "outcome", ongoing = "i gang")
  expect_named(got, c("cpr", "date", "status"))
  expect_equal(got$status, c("i gang", "passed", "i gang", "dropped out"))

  # closed intervals: the end date is still covered
  state <- add_spell_status(events, education, cpr, date, start, end, status, name = "edu")
  expect_equal(state$edu, c("passed", NA, "dropped out", "dropped out"))
})

test_that("rows are never added, dropped or reordered", {
  x <- data.frame(id = "a", start = d(c("2020-01-01", "2020-03-01")),
                  end = d(c("2021-12-31", "2020-12-31")), s = c("long", "short"))
  panel <- data.frame(id = c("z", "a", NA, "a"), year = c(2020, 2021, 2020, NA))
  got <- suppressMessages(add_spell_status(panel, x, id, year, start, end, s, when = "ultimo"))
  expect_equal(nrow(got), 4)
  expect_equal(got$id, panel$id)
  expect_equal(got$s_ultimo, c(NA, "long", NA, NA))
})

test_that("several id columns, and ids of different classes, find their spells", {
  jobs <- data.frame(cvr = c(1, 1, 2), lbnr = c("x", "y", "x"),
                     start = d(c("2020-01-01", "2020-01-01", "2019-01-01")),
                     end = d(c("2020-12-31", NA, "2019-12-31")), s = c("a", "b", "c"))
  panel <- data.frame(cvr = c(2, 1, 1, 3, NA), lbnr = c("x", "y", "x", "x", "x"),
                      year = c(2019, 2021, 2020, 2020, 2020))
  got <- add_spell_status(panel, jobs, c(cvr, lbnr), year, start, end, s, when = "ultimo")
  expect_equal(got$s_ultimo, c("c", "b", "a", NA, NA))

  # a factor id in data against a character id in spells goes through a join
  panel$lbnr <- factor(panel$lbnr)
  expect_equal(add_spell_status(panel, jobs, c(cvr, lbnr), year, start, end, s,
                                when = "ultimo")$s_ultimo,
               got$s_ultimo)
})

test_that("overlaps: latest start with a message, or an error", {
  x <- data.frame(id = "a", start = d(c("2020-01-01", "2020-03-01")),
                  end = d(c("2021-12-31", "2020-12-31")), s = c("long", "short"))
  panel <- data.frame(id = "a", year = 2020)
  expect_message(got <- add_spell_status(panel, x, id, year, start, end, s, when = "ultimo"),
                 "overlapping")
  expect_equal(got$s_ultimo, "short")
  expect_error(add_spell_status(panel, x, id, year, start, end, s, overlap = "error"),
               "ensure_no_overlap")
})

test_that("names: when, name as prefix, and clashes", {
  panel <- data.frame(cpr = "a", year = 2020)
  expect_named(add_spell_status(panel, education, cpr, year, start, end, status, when = "primo"),
               c("cpr", "year", "status_primo"))
  expect_named(add_spell_status(panel, education, cpr, year, start, end, status, name = "udd"),
               c("cpr", "year", "udd_primo", "udd_ultimo"))
  expect_named(add_spell_status(panel, education, cpr, year, start, end, status,
                                when = "ultimo", name = "udd"),
               c("cpr", "year", "udd"))
  panel$status_ultimo <- 1
  expect_error(add_spell_status(panel, education, cpr, year, start, end, status), "already exist")
})

test_that("factors and data.table input are kept", {
  x <- education
  x$status <- factor(x$status)
  panel <- data.table::data.table(cpr = c("a", "b"), year = 2020)
  got <- add_spell_status(panel, x, cpr, year, start, end, status,
                          status_is = "outcome", ongoing = "i gang")
  expect_true(data.table::is.data.table(got))
  expect_true(is.factor(got$status_ultimo))
  expect_equal(as.character(got$status_ultimo), c("i gang", "dropped out"))
  expect_false("status_ultimo" %in% names(panel))
})

test_that("errors speak the user's language", {
  panel <- data.frame(cpr = "a", year = 2020, quarter = 5)
  expect_error(add_spell_status(panel, education, cpr, year, start, end, status, by = "quarter"),
               "Select the year and the quarter")
  expect_error(add_spell_status(panel, education, cpr, c(year, quarter), start, end, status,
                                by = "quarter"), "from 1 to 4")
  expect_error(add_spell_status(panel, education, cpr, c(year, quarter), start, end, status),
               "Date column")
  names(panel)[1] <- "pnr"
  expect_error(add_spell_status(panel, education, pnr, year, start, end, status),
               "no column `pnr`")
})

test_that("empty data and empty spells", {
  panel <- data.frame(cpr = "a", year = 2020)
  got <- add_spell_status(panel, education[0, ], cpr, year, start, end, status)
  expect_equal(got$status_ultimo, NA_character_)
  got0 <- add_spell_status(panel[0, ], education, cpr, year, start, end, status)
  expect_equal(nrow(got0), 0)
  expect_named(got0, c("cpr", "year", "status_primo", "status_ultimo"))
})
