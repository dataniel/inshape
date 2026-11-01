old <- data.frame(
  cpr  = c("a", "b", "c", "d", "e"),
  year = 2023,
  sex  = c("F", "M", "F", "M", NA),
  born = c(1950, 1960, NA, 1970, 1980),
  kom  = c("N", "N", "S", "S", "S")
)
new <- data.frame(
  cpr  = c("b", "a", "d", "e", "f"),
  year = 2023,
  sex  = c("F", "F", "M", "M", "F"),
  born = c(1960L, 1950L, NA, 1980L, 1990L),
  inc  = 1:5
)

test_that("keys that came and went and values that changed are counted", {
  ch <- describe_changes(old, new, cpr, year)
  expect_s3_class(ch, "inshape_changes")
  expect_equal(c(ch$n_old, ch$n_new, ch$n_kept, ch$n_added, ch$n_removed), c(5, 5, 4, 1, 1))
  expect_equal(ch$added$cpr, "f")
  expect_equal(ch$removed$cpr, "c")
  expect_equal(ch$columns_added, "inc")
  expect_equal(ch$columns_removed, "kom")
  expect_equal(ch$type_changed, "born")

  sex <- ch$columns[ch$columns$column == "sex", ]
  expect_equal(sex$changed, 1)        # b: M to F
  expect_equal(sex$filled_in, 1)      # e: NA to M
  born <- ch$columns[ch$columns$column == "born", ]
  expect_equal(born$went_missing, 1)  # d
  expect_equal(born$changed, 0)       # 1960 and 1960L are equal
  expect_equal(ch$changed$cpr, c("b", "d", "e"))
  expect_equal(ch$changed$n_columns, c(1L, 1L, 1L))
  expect_equal(ch$n_changed, 3)
})

test_that("identical extracts in another row order show no changes", {
  ch <- describe_changes(old, old[5:1, ], cpr, year)
  expect_equal(ch$n_changed, 0)
  expect_equal(ch$n_added + ch$n_removed, 0)
  expect_true(all(ch$columns$share == 0))
})

test_that("factors compare by label, dates by day, and other types as text", {
  a <- data.frame(id = 1:3, f = factor(c("x", "y", "z")), d = as.Date("2020-01-01") + 0:2,
                  t = c("1", "2", "3"))
  b <- data.frame(id = 1:3, f = c("x", "y", "w"), d = as.Date("2020-01-01") + c(0, 1, 5),
                  t = 1:3)
  ch <- describe_changes(a, b, id)
  cols <- stats::setNames(ch$columns$changed, ch$columns$column)
  expect_equal(cols[["f"]], 1)
  expect_equal(cols[["d"]], 1)
  expect_equal(cols[["t"]], 0)
  expect_setequal(ch$type_changed, c("f", "t"))
})

test_that("the compiled comparison agrees with R for every type", {
  set.seed(8)
  n <- 2000
  for (make in list(function() sample(c("a", "b", NA), n, TRUE),
                    function() sample(c(1L, 2L, NA), n, TRUE),
                    function() sample(c(1.5, -0, 0, NA, NaN), n, TRUE),
                    function() sample(c(TRUE, FALSE, NA), n, TRUE))) {
    x <- make(); y <- make()
    ia <- sample.int(n); ib <- sample.int(n)
    expected <- ifelse(is.na(x[ia]) & is.na(y[ib]), 0L,
                ifelse(is.na(x[ia]), 3L, ifelse(is.na(y[ib]), 2L,
                ifelse(x[ia] != y[ib], 1L, 0L))))
    expect_equal(pair_changes(x, y, ia, ib), expected)
  }
})

test_that("a key that is not unique, or missing in new, is refused", {
  expect_error(describe_changes(rbind(old, old[1, ]), new, cpr, year), "not unique in `old`")
  expect_error(describe_changes(old, new, kom), "not in `new`")
})

test_that("the summary prints", {
  expect_snapshot(print(describe_changes(old, new, cpr, year)))
})
