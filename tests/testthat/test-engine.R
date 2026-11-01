# The grouping engine must group exactly as match() does; only the
# numbering of the groups may differ. Two id vectors describe the same
# grouping when the first row of each row's group is the same.
same_groups <- function(a, b) identical(match(a, a), match(b, b))

dense <- function(x, threads = 2L) {
  old <- data.table::setDTthreads(threads)
  withr::defer(data.table::setDTthreads(old))
  dense_codes(x)
}

test_that("ids are dense and count the distinct values", {
  x <- c("b", "a", "b", NA, "c", NA)
  id <- dense(x)
  expect_true(same_groups(id, x))
  expect_equal(attr(id, "n"), 4L)
  expect_setequal(unique(as.vector(id)), 1:4)
})

test_that("missing values, NaN and signed zero group as in match()", {
  x <- c(0, -0, NA, NaN, NA, NaN, Inf, -Inf, 1.5, 1.5)
  expect_true(same_groups(dense(x), x))
  expect_equal(attr(dense(x), "n"), 6L)

  i <- c(5L, NA, 5L, .Machine$integer.max, -.Machine$integer.max, NA)
  expect_true(same_groups(dense(i), i))
  expect_true(same_groups(dense(c(TRUE, NA, FALSE, TRUE)), c(TRUE, NA, FALSE, TRUE)))
})

test_that("factors, dates and wide integer ranges are grouped", {
  f <- factor(c("x", "y", NA, "x"), levels = c("y", "x", "unused"))
  expect_true(same_groups(dense(f), as.integer(f)))
  d <- as.Date(c("2020-01-01", NA, "2020-01-01", "1970-01-01"))
  expect_true(same_groups(dense(d), d))
  # Too wide for the direct array: the hash path
  w <- c(1L, 1e9L, -1e9L, 1L, NA)
  expect_true(same_groups(dense(w), w))
})

test_that("latin1 strings fall back to match(), which equals encodings", {
  utf8   <- "æbler"
  latin1 <- iconv(utf8, "UTF-8", "latin1")
  expect_equal(Encoding(latin1), "latin1")
  x <- c(utf8, latin1, "p\u00e6re")
  expect_equal(attr(dense(x), "n"), 2L)
})

test_that("large vectors take the partitioned path, the same for any threads", {
  set.seed(1)
  n <- 3e5
  values <- sprintf("%010d", sample.int(1e9, 5e4))
  x <- sample(c(values, NA), n, replace = TRUE)
  one  <- dense(x, threads = 1L)
  four <- dense(x, threads = 4L)
  expect_true(same_groups(one, x))
  expect_identical(one, four)
  expect_equal(attr(one, "n"), length(unique(x)))

  r <- sample(c(runif(1e4), NA, NaN, 0, -0), n, replace = TRUE)
  expect_true(same_groups(dense(r), r))
})

test_that("a column changed in place, as data.table does, is grouped anew", {
  set.seed(3)
  n <- 2e5
  df <- data.frame(cpr = sprintf("%010d", sample.int(1e9, n, TRUE)))
  first <- dense_codes(df$cpr)
  data.table::set(df, i = 2L, j = "cpr", value = df$cpr[1])
  again <- dense_codes(df$cpr)
  expect_true(same_groups(again, df$cpr))
  expect_equal(attr(again, "n"), attr(first, "n") - 1L)
})

test_that("nothing is kept in the package between calls", {
  ns <- asNamespace("inshape")
  before <- lapply(mget(ls(ns, all.names = TRUE), envir = ns), \(x) if (is.environment(x)) as.list(x))
  ensure_unique(data.frame(cpr = sprintf("%010d", 1:2e5)), cpr)
  after <- lapply(mget(ls(ns, all.names = TRUE), envir = ns), \(x) if (is.environment(x)) as.list(x))
  expect_identical(after, before)
})

test_that("several columns group by their combination", {
  set.seed(2)
  df <- data.frame(a = sample(letters, 2e5, TRUE), b = sample(1:1e6, 2e5, TRUE),
                   c = sample(c(1.5, NA), 2e5, TRUE))
  id <- group_ids(df, c("a", "b", "c"))
  expect_true(same_groups(id, paste(df$a, df$b, df$c)))

  # Two keys with 100,000 values each: the product passes the integer range
  wide <- data.frame(a = sample.int(1e5), b = sample.int(1e5))
  expect_true(same_groups(group_ids(wide, c("a", "b")), paste(wide$a, wide$b)))
})

test_that("the bit matrix and the sorted path summarise a panel alike", {
  set.seed(3)
  for (n_per in c(3L, 64L, 70L)) {
    units <- 400
    panel <- data.frame(id = sample.int(units, 5000, TRUE),
                        t  = sample.int(n_per, 5000, TRUE))
    ix <- panel_index(panel, "id", "t", NULL)
    bits <- panel_cells(ix)
    local({
      local_mocked_bindings(panel_fits_bits = function(...) FALSE)
      sorted <<- panel_cells(ix)
    })
    for (part in c("n_seen", "lo", "hi", "runs")) {
      expect_identical(bits[[part]], sorted[[part]], info = paste(part, n_per))
    }
    # Threads decide which row of a repeated unit-period counts as the
    # repeat; the repeated unit-periods themselves must agree
    cell <- function(r) sort((ix$unit[r] - 1) * n_per + ix$pos[r])
    expect_identical(cell(bits$dup_rows), cell(sorted$dup_rows), info = paste(n_per))
    u <- which(bits$n_seen > 0)[1:3]
    for (i in u) expect_identical(bits$bits_of(i), sorted$bits_of(i))
    lo <- rep(1L, 3)
    hi <- rep(length(ix$periods), 3)
    expect_identical(lapply(bits$missing(u, lo, hi), as.integer),
                     lapply(sorted$missing(u, lo, hi), as.integer))
  }
})

test_that("pattern ids group units with the same periods", {
  for (n_per in c(5L, 70L)) {
    panel <- data.frame(id = rep(1:4, each = n_per), t = rep(seq_len(n_per), 4))
    panel <- panel[!(panel$id %in% c(2, 3) & panel$t == 2), ]
    cells <- panel_cells(panel_index(panel, "id", "t", NULL))
    expect_equal(cells$n_patterns, 2L)
    expect_equal(cells$pattern[1], cells$pattern[4])
    expect_equal(cells$pattern[2], cells$pattern[3])
    expect_false(cells$pattern[1] == cells$pattern[2])
  }
})
