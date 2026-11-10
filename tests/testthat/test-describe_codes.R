persons <- data.frame(
  year = rep(2018:2021, each = 4),
  kom  = c("955", "956", "957", NA,    "955", "956", "957", "957",
           "960", "956", "957", "95",  "960", "965", "957", "956")
)

test_that("each code's first and last period and skipped periods are counted", {
  cd <- describe_codes(persons, kom, year)
  expect_s3_class(cd, "inshape_codes")
  expect_equal(cd$n_codes, 6)
  codes <- cd$codes
  expect_equal(codes$code, c("95", "955", "956", "957", "960", "965"))
  expect_equal(codes$first, c(2020, 2018, 2018, 2018, 2020, 2021))
  expect_equal(codes$last, c(2020, 2019, 2021, 2021, 2021, 2021))
  expect_equal(codes$rows, c(1, 2, 4, 5, 2, 1))
  expect_equal(cd$n_every_period, 2)          # 956, 957
  expect_equal(cd$n_with_gaps, 0)
  expect_equal(cd$n_missing, 1)
})

test_that("codes per period, new and gone codes are counted", {
  bp <- describe_codes(persons, kom, year)$by_period
  expect_equal(bp$codes, c(3, 3, 4, 4))
  expect_equal(bp$new, c(NA, 0, 2, 1))        # 960 and 95 in 2020, 965 in 2021
  expect_equal(bp$gone, c(NA, 0, 1, 1))       # 955 after 2019, 95 after 2020
  expect_equal(bp$missing, c(1, 0, 0, 0))
})

test_that("a code skipping a period has a gap, and expected periods count", {
  df <- data.frame(year = c(2018, 2019, 2020, 2018, 2020), kom = c("a", "a", "a", "b", "b"))
  cd <- describe_codes(df, kom, year, periods = 2017:2020)
  expect_equal(cd$codes$gaps, c(0, 1))
  expect_equal(cd$n_with_gaps, 1)
  expect_equal(cd$by_period$codes, c(0, 2, 1, 2))
})

test_that("the summary prints", {
  expect_snapshot(print(describe_codes(persons, kom, year)))
})

test_that("ensure_codes() reports values outside the code list", {
  valid <- c("955", "956", "957", "960", "965")
  cnd <- rlang::catch_cnd(ensure_codes(persons, kom, valid), "inshape_failure")
  expect_equal(cnd$violations$kom, "95")
  expect_match(conditionMessage(cnd), "Codes not in the code list: kom")

  cnd <- rlang::catch_cnd(ensure_codes(persons, kom, valid, na_ok = FALSE), "inshape_failure")
  expect_equal(cnd$violations$kom, c(NA, "95"))
  expect_match(conditionMessage(cnd), "2 rows in 2 groups")

  expect_message(ensure_codes(persons[persons$kom %in% valid, ], kom, valid), "Valid codes: kom")
})

test_that("ensure_codes() compares text as text and takes factors and numbers", {
  df <- data.frame(kom = c("0955", "955"), n = c(1, 2), f = factor(c("x", "y")))
  cnd <- rlang::catch_cnd(ensure_codes(df, kom, 955), "inshape_failure")
  expect_equal(cnd$violations$kom, "0955")
  expect_message(ensure_codes(df, n, 1:2), "Valid codes")
  expect_warning(ensure_codes(df, f, "x"), "Codes not in")
})

test_that("ensure_codes() validates its arguments", {
  expect_error(ensure_codes(persons, kom, data.frame(code = "955")), "time.*column")
  expect_error(ensure_codes(persons, kom, character()), "non-empty")
  expect_error(ensure_codes(persons, c(kom, year), "955"), "exactly one")
  expect_error(ensure_codes(persons, kom, "955", na_ok = NA), "TRUE or FALSE")
})
