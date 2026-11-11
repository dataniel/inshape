df <- data.frame(id = c(1, NA, 3, 4), amount = c(10, -5, NA, -1))

test_that("tally_violations() counts every rule", {
  out <- tally_violations(df,
    "Missing id" = is.na(id),
    "Negative"   = amount < 0,
    "Huge"       = amount > 1e6
  )
  expect_s3_class(out, "tbl_df")
  expect_equal(out$rule, c("Missing id", "Negative", "Huge"))
  expect_equal(out$n, c(1L, 2L, 0L))
  expect_equal(out$total, c(4L, 4L, 4L))
  expect_equal(out$rows, list(2L, c(2L, 4L), integer()))
})

test_that("unnamed rules are named after their expression", {
  out <- tally_violations(df, amount < 0)
  expect_equal(out$rule, "amount < 0")
})

test_that("rules can use if_any() and grouped data", {
  out <- tally_violations(df, "Any NA" = dplyr::if_any(c(id, amount), is.na))
  expect_equal(out$rows[[1]], c(2L, 3L))

  grouped <- dplyr::group_by(data.frame(g = c(1, 1, 2), x = c(1, 5, 2)), g)
  out <- tally_violations(grouped, "Above group mean" = x > mean(x))
  expect_equal(out$rows[[1]], 2L)
})

test_that("the result feeds ensure_empty()", {
  expect_error(
    tally_violations(df, "Negative" = amount < 0) |>
      dplyr::filter(n > 0) |>
      ensure_empty(abort_msg = "Validation failed"),
    "Validation failed"
  )
})

test_that("total makes a threshold on the share of violations", {
  tally <- tally_violations(df, "Missing id" = is.na(id), "Negative" = amount < 0)
  over <- dplyr::filter(tally, n / total > 0.3)
  expect_equal(over$rule, "Negative")
})

test_that("bad rules give an error naming the rule", {
  expect_error(tally_violations(df, "Not logical" = amount * 2), "must give a logical")
  expect_error(tally_violations(df, "Typo" = amuont < 0), "could not be evaluated")
  expect_error(tally_violations(df), "at least one rule")
})

test_that("a tally with one broken rule previews in ensure_empty()", {
  t <- tally_violations(df, "Neg" = amount < 0, "Big" = amount > 100) |>
    dplyr::filter(n > 0)
  cnd <- rlang::catch_cnd(ensure_empty(t, warn_msg = "Rules broken"),
                          classes = "inshape_failure")
  expect_match(conditionMessage(cnd), "1 row found")
  expect_match(conditionMessage(cnd), "Neg")
})
