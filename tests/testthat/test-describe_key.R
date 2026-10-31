firms <- data.frame(
  cvr      = c("1", "1", "2", "2", "3", "4", "4", "4"),
  year     = 2024,
  industry = c("A", "A", "B", "C", "A", "D", "D", "D"),
  income   = c(10, 10, 5, 5, 7, 1, 2, NA)
)

test_that("duplicated keys are counted with their copies", {
  k <- describe_key(firms, cvr, year)
  expect_s3_class(k, "lustrum_key")
  expect_equal(k$key, c("cvr", "year"))
  expect_equal(k$n_rows, 8)
  expect_equal(k$n_keys, 4)
  expect_equal(k$n_dup_keys, 3)
  expect_equal(k$n_dup_rows, 7)
  expect_equal(k$copies$copies, c(2, 3))
  expect_equal(k$copies$keys, c(2, 1))
})

test_that("exact copies are told apart from conflicts, by column", {
  k <- describe_key(firms, cvr, year)
  expect_equal(k$n_exact, 1)                    # cvr 1
  expect_equal(k$conflicts$column, c("industry", "income"))
  expect_equal(k$conflicts$keys, c(1, 1))       # cvr 2; cvr 4 (NA differs)
})

test_that("a unique key reports no duplicates", {
  k <- describe_key(firms[c(1, 3, 5, 6), ], cvr, year)
  expect_equal(k$n_dup_keys, 0)
  expect_equal(nrow(k$conflicts), 0)
  expect_output(print(k), "Unique")
})

test_that("without columns, fully duplicated rows are counted", {
  k <- describe_key(firms)
  expect_equal(k$n_dup_keys, 1)
  expect_equal(k$n_exact, 1)
})

test_that("missing values in the key are counted", {
  k <- describe_key(data.frame(a = c(1, NA, NA), b = 1:3), a)
  expect_equal(k$missing$rows, 2)
  expect_output(print(k), "Missing values in the key: a \\(2\\)")
})

test_that("the summary prints the counts", {
  expect_snapshot(print(describe_key(firms, cvr, year)))
})

test_that("non-atomic key columns are refused", {
  df <- data.frame(id = 1:2)
  df$l <- list(1, 2)
  expect_error(describe_key(df, l), "atomic")
})
