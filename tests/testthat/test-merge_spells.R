d <- function(x) as.Date(x)
admissions <- data.frame(
  cpr   = c("a", "a", "a", "b", "b", "c", "c"),
  start = d(c("2020-01-01", "2020-01-11", "2020-03-01", "2020-01-01", "2020-01-05",
              "2021-06-01", "2021-07-01")),
  end   = d(c("2020-01-10", "2020-01-20", "2020-03-05", "2020-01-31", "2020-01-10",
              NA, "2021-07-10")),
  ward  = c("A", "B", "A", "A", "C", "A", "A")
)

test_that("adjacent, nested and ongoing spells are merged by default", {
  m <- merge_spells(admissions, cpr, start, end)
  expect_s3_class(m, "tbl_df")
  expect_named(m, c("cpr", "start", "end", "n_spells"))
  expect_equal(m$cpr, c("a", "a", "b", "c"))
  expect_equal(m$start, d(c("2020-01-01", "2020-03-01", "2020-01-01", "2021-06-01")))
  # a's transfer on 11 January, b's nested stay, c's ongoing spell
  expect_equal(m$end, d(c("2020-01-20", "2020-03-05", "2020-01-31", NA)))
  expect_equal(m$n_spells, c(2L, 1L, 2L, 2L))
})

test_that("units keep the order of the data, and spells are sorted by start", {
  m <- merge_spells(admissions[7:1, ], cpr, start, end)
  expect_equal(m$cpr, c("c", "b", "a", "a"))
  expect_equal(m$start[m$cpr == "a"], d(c("2020-01-01", "2020-03-01")))
})

test_that("max_gap decides how far apart spells may be", {
  only_shared <- merge_spells(admissions, cpr, start, end, max_gap = -1)
  expect_equal(sum(only_shared$cpr == "a"), 3)   # the transfer is kept apart
  expect_equal(sum(only_shared$cpr == "b"), 1)

  wide <- merge_spells(admissions, cpr, start, end, max_gap = 40)
  expect_equal(wide$n_spells[wide$cpr == "a"], 3L)
  expect_equal(wide$end[wide$cpr == "a"], d("2020-03-05"))
})

test_that("by keeps spells with different values apart", {
  m <- merge_spells(admissions, cpr, start, end, by = ward)
  expect_named(m, c("cpr", "ward", "start", "end", "n_spells"))
  expect_equal(nrow(m[m$cpr == "a", ]), 3)        # ward A, B, A
  expect_equal(nrow(m[m$cpr == "b", ]), 2)        # ward A and C
  expect_equal(m$n_spells[m$cpr == "c"], 2L)      # both in ward A
})

test_that("bad rows are dropped with a message, and numbers keep their type", {
  df <- data.frame(id = c(1, 1, 1, 2), start = c(2015, 2017, NA, 2020),
                   end = c(2016, 2018, 2019, 2019))
  expect_message(m <- merge_spells(df, id, start, end), "missing")
  expect_equal(m$start, 2015)
  expect_equal(m$end, 2018)
  expect_type(m$start, "double")
  expect_equal(nrow(merge_spells(df[0, ], id, start, end)), 0)
})

test_that("a data.table stays a data.table", {
  dt <- data.table::as.data.table(admissions)
  expect_true(data.table::is.data.table(merge_spells(dt, cpr, start, end)))
})

test_that("merged spells agree with a spell-by-spell reference", {
  set.seed(7)
  n <- 3000
  df <- data.frame(id = sample(c(letters, NA), n, TRUE),
                   start = sample.int(2000, n, TRUE))
  df$end <- df$start + sample(0:60, n, TRUE)
  df$end[sample.int(n, 30)] <- NA
  reference <- function(df, max_gap) {
    df <- df[order(df$id, df$start, -ifelse(is.na(df$end), Inf, df$end), na.last = FALSE), ]
    out <- list()
    # drop = TRUE would rebuild the factor and lose the missing id
    for (u in split(df, factor(df$id, exclude = NULL))) {
      cover <- -Inf
      for (i in seq_len(nrow(u))) {
        e <- if (is.na(u$end[i])) Inf else u$end[i]
        if (u$start[i] - cover - 1 > max_gap) {
          out[[length(out) + 1]] <- c(u$start[i], e, 1)
        } else {
          k <- length(out)
          out[[k]][2] <- max(out[[k]][2], e)
          out[[k]][3] <- out[[k]][3] + 1
        }
        cover <- max(cover, e)
      }
    }
    m <- do.call(rbind, out)
    m[order(m[, 1], m[, 2], m[, 3]), , drop = FALSE]
  }
  for (gap in c(-1, 0, 5)) {
    got <- merge_spells(df, id, start, end, max_gap = gap)
    got <- cbind(got$start, ifelse(is.na(got$end), Inf, got$end), got$n_spells)
    got <- got[order(got[, 1], got[, 2], got[, 3]), , drop = FALSE]
    expect_equal(unname(got), unname(reference(df, gap)))
  }
})

test_that("arguments are validated", {
  expect_error(merge_spells(admissions, c(), start, end), "at least one column")
  expect_error(merge_spells(admissions, cpr, start, end, max_gap = -2), "max_gap")
  expect_error(merge_spells(admissions, cpr, start, end, max_gap = 1.5), "max_gap")
  expect_error(merge_spells(admissions, cpr, start, end, by = start), "must not include")
})
