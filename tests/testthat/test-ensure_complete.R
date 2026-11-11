persons <- data.frame(
  cpr  = c("a", "b", NA, "d"),
  born = as.Date(c("1980-05-01", NA, NA, "1975-02-11")),
  sex  = c("F", "M", "F", NA)
)

# The rows a failing check reports
incomplete <- function(...) {
  rlang::catch_cnd(ensure_complete(...), classes = "inshape_failure")$violations
}

test_that("complete columns pass and the data is returned unchanged", {
  expect_message(out <- ensure_complete(persons[1:3, ], sex), "Complete: sex")
  expect_identical(out, persons[1:3, ])
  expect_message(ensure_complete(persons[1, ]), "Complete: all columns")
  expect_message(ensure_complete(persons[0, ]), "Complete: all columns")
  expect_message(ensure_complete(persons[1, ], cpr, warn_msg = "No cpr"), "Check passed: No cpr")
})

test_that("rows with a missing value are reported with the columns missing", {
  v <- incomplete(persons, cpr, born)
  expect_equal(names(v), c("missing", "cpr", "born", "sex"))
  expect_equal(v$missing, c("born", "cpr, born"))
  expect_equal(v$cpr, c("b", NA))
  expect_equal(v$sex, c("M", "F"))

  # The columns are named in the order they were selected
  expect_equal(incomplete(persons, born, cpr)$missing, c("born", "born, cpr"))
  expect_equal(incomplete(persons, sex)$missing, "sex")
})

test_that("without columns, all of them are checked", {
  v <- incomplete(persons)
  expect_equal(v$missing, c("born", "cpr, born", "sex"))
  expect_equal(v$cpr, c("b", NA, "d"))
})

test_that("the messages name the columns and count rows and combinations", {
  expect_warning(ensure_complete(persons, cpr, born), "Missing values in: cpr, born",
                 class = "inshape_failure")
  expect_warning(ensure_complete(persons, cpr, born), "2 rows in 2 groups")
  expect_warning(ensure_complete(persons), "Missing values in: all columns")
  expect_warning(ensure_complete(persons, sex, warn_msg = "Sex unknown"), "Sex unknown")
  expect_error(ensure_complete(persons, cpr, abort_msg = "Persons without cpr"),
               "Persons without cpr", class = "inshape_failure")
})

test_that("NaN is missing, an empty string and a list column are not", {
  df <- data.frame(row = 1:4, x = c(1, NaN, NA, 4), s = c("", "a", "b", NA),
                   f = factor(c("u", NA, "v", "w")))
  df$l <- list(1, NULL, NA, 4)
  expect_equal(incomplete(df, x)$row, 2:3)
  expect_equal(incomplete(df, s)$row, 4L)
  expect_equal(incomplete(df, f)$row, 2L)
  expect_message(ensure_complete(df, l), "Complete: l")
  expect_equal(incomplete(df)$missing, c("x, f", "x", "s"))
})

test_that("a column named missing keeps its name and values", {
  df <- data.frame(id = c(1, NA, 3), missing = c("no", "yes", NA))
  v <- incomplete(df)
  expect_equal(names(v), c("missing.1", "id", "missing"))
  expect_equal(v$missing.1, c("id", "missing"))
  expect_equal(v$missing, c("yes", NA))
})

test_that("grouped data is checked on the selected columns only", {
  grouped <- dplyr::group_by(persons, sex)
  v <- incomplete(grouped, cpr)
  expect_equal(v$missing, "cpr")
  expect_equal(nrow(v), 1L)
  expect_message(out <- ensure_complete(grouped[1:2, ], cpr), "Complete: cpr")
  expect_identical(out, grouped[1:2, ])
})

test_that("violations() returns the incomplete rows", {
  expect_equal(violations(ensure_complete(persons, sex))$cpr, "d")
  expect_message(none <- violations(ensure_complete(persons[1, ])), "Complete")
  expect_equal(dim(none), c(0L, 3L))
})

test_that("an empty selection and other objects are refused", {
  expect_error(ensure_complete(persons, dplyr::starts_with("zzz")), "no columns")
  expect_error(ensure_complete(persons, absent))
  expect_error(ensure_complete(list(x = 1)), "database table or an Arrow table")
})
