d <- function(x) as.Date(x)
admissions <- data.frame(
  cpr   = c("a", "a", "a", "b", "b", "c", "d", "d", "e", "f", "f"),
  start = d(c("2020-01-01", "2020-01-11", "2020-03-01", "2020-01-01", "2020-01-05",
              "2021-06-01", "2020-05-01", "2020-05-01", NA, "2020-02-01", "2020-01-31")),
  end   = d(c("2020-01-10", "2020-01-20", "2020-03-05", "2020-01-31", "2020-01-10",
              NA, "2020-05-03", "2020-05-03", "2020-01-01", "2020-01-31", "2020-02-10"))
)

relations <- function(x) stats::setNames(x$relations$spells, x$relations$relation)

test_that("each spell is related to the unit's earlier spells", {
  s <- describe_spells(admissions, cpr, start, end)
  expect_s3_class(s, "lustrum_spells")
  r <- relations(s)
  expect_equal(r[["adjacent"]], 1)    # a: 11 January after 10 January
  expect_equal(r[["gap"]], 1)         # a: March
  expect_equal(r[["nested"]], 1)      # b
  expect_equal(r[["duplicate"]], 1)   # d
  expect_equal(r[["touching"]], 0)
  expect_equal(r[["overlapping"]], 0)
})

test_that("bad and ongoing spells are counted and left out", {
  s <- describe_spells(admissions, cpr, start, end)
  expect_equal(s$n_rows, 11)
  expect_equal(s$n_missing_start, 1)       # e
  expect_equal(s$n_end_before_start, 1)    # f, first row
  expect_equal(s$n_spells, 9)
  expect_equal(s$n_ongoing, 1)             # c
  expect_equal(s$n_units, 5)
  expect_equal(s$n_units_overlapping, 2)   # b and d
})

test_that("touching and overlapping spells are told apart", {
  df <- data.frame(id = 1, start = c(1, 10, 15), end = c(10, 20, 30))
  r <- relations(describe_spells(df, id, start, end))
  expect_equal(r[["touching"]], 1)
  expect_equal(r[["overlapping"]], 1)
})

test_that("equal starts are taken longest first, and ongoing spells cover the rest", {
  df <- data.frame(id = 1, start = c(5, 5, 8), end = c(6, NA, 9))
  r <- relations(describe_spells(df, id, start, end))
  expect_equal(r[["nested"]], 2)
})

test_that("gap and length summaries are exact type 1 quantiles", {
  set.seed(6)
  df <- data.frame(id = rep(1:200, each = 5), start = 0, end = 0)
  df$start <- ave(rep(0, nrow(df)), df$id, FUN = function(x) cumsum(sample(5:40, length(x), TRUE)))
  df$end <- df$start + sample(0:3, nrow(df), TRUE)
  s <- describe_spells(df, id, start, end)
  len <- df$end - df$start + 1
  expect_equal(s$lengths$median, unname(quantile(len, .5, type = 1)))
  expect_equal(s$lengths$q25, unname(quantile(len, .25, type = 1)))
  expect_equal(s$lengths$mean, mean(len))
  expect_equal(s$lengths$max, max(len))
})

test_that("relations agree with a direct comparison on random spells", {
  set.seed(7)
  df <- data.frame(id = sample.int(50, 600, TRUE), start = sample.int(300, 600, TRUE))
  df$end <- df$start + sample(c(0:20, NA), 600, TRUE)
  s <- describe_spells(df, id, start, end)

  # Reference: sort, then compare each spell with the running maximum end
  o <- order(df$id, df$start, -ifelse(is.na(df$end), Inf, df$end))
  x <- df[o, ]
  x$end[is.na(x$end)] <- Inf
  rel <- character(nrow(x))
  for (i in seq_len(nrow(x))) {
    if (i == 1 || x$id[i] != x$id[i - 1]) { rel[i] <- "first"; cover <- x$end[i]; next }
    rel[i] <- if (x$start[i] == x$start[i - 1] && x$end[i] == x$end[i - 1]) "duplicate"
      else if (x$end[i] <= cover) "nested"
      else if (x$start[i] < cover) "overlapping"
      else if (x$start[i] == cover) "touching"
      else if (x$start[i] == cover + 1) "adjacent"
      else "gap"
    cover <- max(cover, x$end[i])
  }
  want <- table(factor(rel, s$relations$relation))
  expect_equal(relations(s), c(want), ignore_attr = TRUE)
})

test_that("years count starts and ends per calendar year", {
  s <- describe_spells(admissions, cpr, start, end)
  expect_equal(s$by_year$year, c(2020, 2021))
  expect_equal(s$by_year$starts, c(8, 1))
  expect_equal(s$by_year$ends, c(8, 0))
})

test_that("whole numbers are spells too, and other types are refused", {
  df <- data.frame(id = 1, start = c(2010, 2012), end = c(2011, 2015))
  s <- describe_spells(df, id, start, end)
  expect_equal(relations(s)[["adjacent"]], 1)
  expect_equal(s$by_year$year, c(2010, 2011, 2012, 2015))
  expect_error(describe_spells(data.frame(id = 1, start = "a", end = "b"), id, start, end),
               "Date column or whole numbers")
})

test_that("the summary prints", {
  expect_snapshot(print(describe_spells(admissions, cpr, start, end)))
})
