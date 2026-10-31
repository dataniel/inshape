d <- function(x) as.Date(x)

education <- data.frame(
  cpr    = c("a", "a", "b"),
  start  = d(c("2018-08-15", "2021-08-15", "2019-08-15")),
  end    = d(c("2021-06-20", NA,           "2020-03-01")),
  status = c("passed", "in progress", "dropped out")
)

test_that("outcome mode is ongoing during a spell and carries the outcome after", {
  p <- spells_to_panel(education, cpr, start, end, status, from = 2018, to = 2022,
                       status_is = "outcome", ongoing = "in progress")
  a <- p[p$cpr == "a", ]
  expect_equal(a$year, 2018:2022)
  expect_equal(a$primo,  c(NA, "in progress", "in progress", "in progress", "in progress"))
  expect_equal(a$ultimo, c("in progress", "in progress", "in progress", "in progress", "in progress"))
  b <- p[p$cpr == "b", ]
  expect_equal(b$primo,  c(NA, NA, "in progress", "dropped out", "dropped out"))
  expect_equal(b$ultimo, c(NA, "in progress", "dropped out", "dropped out", "dropped out"))
})

test_that("the outcome applies from the end date, and a gap carries it", {
  x <- data.frame(id = 1, start = d(c("2019-01-01", "2022-03-01")),
                  end = d(c("2020-12-31", "2023-06-30")), s = c("passed", "dropped"))
  p <- spells_to_panel(x, id, start, end, s, status_is = "outcome")
  expect_equal(p$year, 2019:2023)
  expect_equal(p$ultimo, c("ongoing", "passed", "passed", "ongoing", "dropped"))
  # primo is the previous ultimo
  expect_equal(p$primo[-1], p$ultimo[-5])
})

test_that("state mode looks up the covering spell, closed intervals", {
  x <- data.frame(id = "a", start = d(c("2020-01-01", "2020-09-01")),
                  end = d(c("2020-08-31", "2021-03-31")),
                  s = c("enrolled", "leave"))
  p <- spells_to_panel(x, id, start, end, s, by = "quarter")
  expect_equal(p$quarter, c(1:4, 1L))
  expect_equal(p$primo,  c(NA, "enrolled", "enrolled", "leave", "leave"))
  expect_equal(p$ultimo, c("enrolled", "enrolled", "leave", "leave", "leave"))

  first <- spells_to_panel(x, id, start, end, s, by = "quarter", primo = "first_day")
  expect_equal(first$primo, c("enrolled", "enrolled", "enrolled", "leave", "leave"))
})

test_that("state mode gives NA in gaps and after the last spell", {
  x <- data.frame(id = "a", start = d(c("2018-01-01", "2020-06-01")),
                  end = d(c("2018-12-30", "2020-12-31")), s = c("x", "y"))
  p <- spells_to_panel(x, id, start, end, s, to = 2021)
  expect_equal(p$ultimo, c(NA, NA, "y", NA))
})

test_that("overlapping spells: latest start wins, with a message", {
  x <- data.frame(id = "a", start = d(c("2020-01-01", "2020-03-01")),
                  end = d(c("2021-12-31", "2020-12-31")), s = c("long", "short"))
  expect_message(p <- spells_to_panel(x, id, start, end, s), "overlapping")
  expect_equal(p$ultimo, c("short", "long"))

  # a nested earlier spell still covers after the later one ends
  p2 <- suppressMessages(spells_to_panel(x, id, start, end, s, by = "month"))
  expect_equal(p2$ultimo[p2$year == 2021 & p2$month == 1], "long")
})

test_that("from/to give every unit the same window", {
  p <- spells_to_panel(education, cpr, start, end, status, from = 2015, to = 2016)
  expect_equal(nrow(p), 4)
  expect_true(all(is.na(p$ultimo)))
  expect_equal(p$year, c(2015L, 2016L, 2015L, 2016L))
})

test_that("ongoing spells run to the latest date in the data without `to`", {
  p <- spells_to_panel(education, cpr, start, end, status)
  expect_equal(max(p$year[p$cpr == "a"]), 2021L)
  expect_equal(range(p$year[p$cpr == "b"]), c(2019L, 2020L))
})

test_that("multiple id columns, factors and data.table output", {
  x <- data.frame(kom = 1, cpr = "a", start = d("2020-02-01"), end = d(NA),
                  s = factor("passed"))
  p <- spells_to_panel(x, c(kom, cpr), start, end, s, to = 2021,
                       status_is = "outcome", ongoing = "i gang")
  expect_named(p, c("kom", "cpr", "year", "primo", "ultimo"))
  expect_true(is.factor(p$ultimo))
  expect_equal(as.character(p$ultimo), c("i gang", "i gang"))

  dt <- spells_to_panel(data.table::as.data.table(x), cpr, start, end, s)
  expect_true(data.table::is.data.table(dt))
})

test_that("bad rows are dropped with a message", {
  x <- data.frame(id = "a", start = d(c("2020-01-01", NA, "2020-05-01")),
                  end = d(c("2020-12-31", "2020-01-01", "2020-04-01")), s = "x")
  expect_message(expect_message(p <- spells_to_panel(x, id, start, end, s),
                                "missing"), "before")
  expect_equal(p$ultimo, "x")
})

test_that("errors speak the user's language", {
  x <- education
  x$start <- as.character(x$start)
  expect_error(spells_to_panel(x, cpr, start, end, status), "must be a Date column")
  expect_error(spells_to_panel(education, cpr, start, end, status, from = 2020, to = 2019),
               "must not be after")
  expect_error(spells_to_panel(education, cpr, start, end, status, from = "2020"),
               "single year")
  names(x)[1] <- "year"
  expect_error(spells_to_panel(x, year, start, end, status), "clash")
})

test_that("empty data gives an empty panel", {
  p <- spells_to_panel(education[0, ], cpr, start, end, status)
  expect_equal(nrow(p), 0)
  expect_named(p, c("cpr", "year", "primo", "ultimo"))
})
