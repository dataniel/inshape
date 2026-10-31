persons <- data.frame(
  cpr    = c("a", "a", "b", "b", "c", "c", "d", "d"),
  year   = c(2020, 2021, 2020, 2021, 2020, 2021, 2020, 2021),
  sex    = c("F", "F", "M", "F", "M", NA, NA, NA),
  income = c(100, 120, 90, 95, 80, 85, 70, 70),
  region = factor(c("N", "N", "S", "S", "S", "S", "N", "N"))
)

test_that("columns are counted by units that vary, partly or wholly missing", {
  v <- describe_varying(persons, cpr)
  expect_s3_class(v, "lustrum_varying")
  expect_equal(v$n_units, 4)
  cols <- v$columns
  sex <- cols[cols$column == "sex", ]
  expect_equal(sex$varying, 1)          # b
  expect_equal(sex$partly_missing, 1)   # c
  expect_equal(sex$all_missing, 1)      # d
  expect_equal(sex$share, 1 / 3)
  expect_equal(cols$varying[cols$column == "income"], 3)
  expect_equal(cols$varying[cols$column == "region"], 0)
})

test_that("columns are sorted from constant to varying", {
  v <- describe_varying(persons, cpr)
  expect_equal(v$columns$column, c("region", "sex", "income", "year"))
})

test_that("the columns can be chosen, and the id is never described", {
  v <- describe_varying(persons, cpr, sex, cpr)
  expect_equal(v$columns$column, "sex")
})

test_that("varying units agree with a grouped count of distinct values", {
  set.seed(5)
  df <- data.frame(id = sample.int(500, 5000, TRUE),
                   x  = sample(c(1:3, NA), 5000, TRUE, prob = c(.9, .03, .03, .04)))
  v <- describe_varying(df, id, x)$columns
  distinct <- tapply(df$x, df$id, function(x) length(unique(x[!is.na(x)])))
  expect_equal(v$varying, sum(distinct > 1))
})

test_that("the compiled pass agrees with R's comparison for every type", {
  set.seed(6)
  n <- 3000
  unit <- sample.int(300, n, TRUE)
  reference <- function(x) {
    by_unit <- split(x, factor(unit, levels = 1:300))
    list(
      varying        = vapply(by_unit, function(v) length(unique(v[!is.na(v)])) > 1, logical(1)),
      partly_missing = vapply(by_unit, function(v) any(is.na(v)) && !all(is.na(v)), logical(1)),
      all_missing    = vapply(by_unit, function(v) length(v) > 0 && all(is.na(v)), logical(1))
    )
  }
  columns <- list(
    chr  = sample(c("a", "b", NA), n, TRUE, prob = c(.95, .02, .03)),
    int  = sample(c(1L, 2L, NA), n, TRUE, prob = c(.95, .02, .03)),
    lgl  = sample(c(TRUE, FALSE, NA), n, TRUE, prob = c(.95, .02, .03)),
    dbl  = sample(c(0, -0, 1.5, NA, NaN), n, TRUE, prob = c(.5, .45, .02, .02, .01)),
    date = as.Date("2020-01-01") + sample(c(0, 1, NA), n, TRUE, prob = c(.95, .02, .03))
  )
  for (x in columns) {
    expect_equal(lapply(varying_units(x, unit, 300L), unname), lapply(reference(x), unname))
  }
})

test_that("a string equals itself in another encoding", {
  utf8   <- "æbler"
  latin1 <- iconv(utf8, "UTF-8", "latin1")
  v <- varying_units(c(utf8, latin1, "b", "b"), c(1L, 1L, 2L, 2L), 2L)
  expect_equal(v$varying, c(FALSE, FALSE))
})

test_that("the summary prints", {
  expect_snapshot(print(describe_varying(persons, cpr)))
})

test_that("ensure_constant() reports every row of the units that vary", {
  cnd <- rlang::catch_cnd(ensure_constant(persons, cpr, sex),
                          classes = "lustrum_failure")
  expect_equal(cnd$violations$cpr, c("b", "b"))
  expect_equal(names(cnd$violations)[1:2], c("cpr", "sex"))
  expect_match(conditionMessage(cnd), "Varies within units: sex per cpr")
})

test_that("ensure_constant() passes when only missing values differ", {
  expect_message(out <- ensure_constant(persons[persons$cpr != "b", ], cpr, sex),
                 "Constant: sex per cpr")
  expect_equal(out, persons[persons$cpr != "b", ])
})

test_that("ensure_constant() checks several columns, and aborts on request", {
  cnd <- rlang::catch_cnd(ensure_constant(persons, cpr, sex, income),
                          classes = "lustrum_failure")
  expect_equal(unique(cnd$violations$cpr), c("a", "b", "c"))
  expect_error(ensure_constant(persons, cpr, sex, abort_msg = "Sex changes"),
               "Sex changes")
})

test_that("ensure_constant() validates its arguments", {
  expect_error(ensure_constant(persons, c(), sex), "at least one column")
  expect_error(ensure_constant(persons, cpr), "constant")
})
