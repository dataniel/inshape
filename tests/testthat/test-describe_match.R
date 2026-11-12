income <- data.frame(
  cpr    = c("a", "a", "b", "c", NA),
  year   = c(2023, 2024, 2024, 2024, 2024),
  income = c(10, 12, 7, 9, 3)
)
persons <- data.frame(
  person_id = c("a", "b", "b", "d"),
  kommune   = c("955", "956", "957", "960")
)

test_that("keys are counted in both tables, with the rows they stand for", {
  m <- describe_match(income, persons, by = c(cpr = "person_id"))
  expect_s3_class(m, "inshape_match")
  expect_equal(m$by, c(cpr = "person_id"))
  expect_equal(m$n_rows, 5)
  expect_equal(m$n_ref_rows, 4)
  expect_equal(m$keys$found, c("in both", "only in data", "only in reference"))
  expect_equal(m$keys$keys, c(2, 1, 1))        # a and b; c; d
  expect_equal(m$keys$rows, c(3, 1, 0))
  expect_equal(m$keys$ref_rows, c(3, 0, 1))
})

test_that("missing keys match nothing and are counted on their own", {
  m <- describe_match(income, persons, by = c(cpr = "person_id"))
  expect_equal(m$n_missing, 1)
  expect_equal(m$n_ref_missing, 0)

  # A missing key in the reference does not make the missing key of data match
  ref <- rbind(persons, data.frame(person_id = NA, kommune = "961"))
  m <- describe_match(income, ref, by = c(cpr = "person_id"))
  expect_equal(m$n_ref_missing, 1)
  expect_equal(m$keys$keys, c(2, 1, 1))
  expect_equal(m$n_join_rows, 6)
})

test_that("a repeated reference key multiplies the rows of a left join", {
  m <- describe_match(income, persons, by = c(cpr = "person_id"))
  expect_equal(m$n_ref_dup_keys, 1)            # b
  expect_equal(m$n_join_rows, 6)               # b's row twice
  expect_type(m$n_join_rows, "double")

  once <- describe_match(income, persons[-3, ], by = c(cpr = "person_id"))
  expect_equal(once$n_ref_dup_keys, 0)
  expect_equal(once$n_join_rows, 5)
})

test_that("the counts are those of dplyr's joins, on composite keys with missing values", {
  set.seed(3)
  keys <- function(n) {
    data.frame(id   = sample(c(letters[1:8], NA), n, TRUE),
               year = sample(c(2020:2023, NA), n, TRUE))
  }
  data <- cbind(keys(300), value = 1)
  ref  <- stats::setNames(keys(60), c("person", "year"))
  by   <- c(id = "person", "year")
  m <- describe_match(data, ref, by = by)

  joined <- dplyr::left_join(data, ref, by = by, na_matches = "never",
                             relationship = "many-to-many")
  expect_equal(m$n_join_rows, nrow(joined))

  whole   <- stats::complete.cases(data[c("id", "year")])
  matched <- dplyr::semi_join(data[whole, ], ref, by = by, na_matches = "never")
  alone   <- dplyr::anti_join(data[whole, ], ref, by = by, na_matches = "never")
  expect_equal(m$n_missing, sum(!whole))
  expect_equal(m$keys$rows, c(nrow(matched), nrow(alone), 0))
  expect_equal(m$keys$keys[1:2], c(nrow(unique(matched[c("id", "year")])),
                                   nrow(unique(alone[c("id", "year")]))))

  ref_whole <- ref[stats::complete.cases(ref), ]
  expect_equal(m$n_ref_missing, nrow(ref) - nrow(ref_whole))
  expect_equal(m$n_ref_dup_keys, sum(table(paste(ref_whole$person, ref_whole$year)) > 1))

  # Seen from the reference, the two sides trade places
  back <- describe_match(ref, data, by = c(person = "id", "year"))
  expect_equal(back$keys$keys, m$keys$keys[c(1, 3, 2)])
  expect_equal(back$keys$rows, m$keys$ref_rows[c(1, 3, 2)])
  expect_equal(back$keys$ref_rows, m$keys$rows[c(1, 3, 2)])
  expect_equal(back$n_missing, m$n_ref_missing)
  expect_equal(back$n_ref_missing, m$n_missing)
})

test_that("integer and double keys match, and factor and character keys", {
  data <- data.frame(n = c(1L, 2L, 3L, NA), f = factor(c("a", "b", "c", NA)))
  ref  <- data.frame(n = c(1, 2, 4), f = c("a", "b", "z"))
  expect_equal(describe_match(data, ref, by = "n")$keys$keys, c(2, 1, 1))
  expect_equal(describe_match(data, ref, by = "f")$keys$keys, c(2, 1, 1))
  expect_equal(describe_match(ref, data, by = "f")$keys$keys, c(2, 1, 1))
  ref$f <- factor(ref$f, levels = c("z", "b", "a"))
  expect_equal(describe_match(data, ref, by = "f")$keys$keys, c(2, 1, 1))
  expect_equal(describe_match(data, ref, by = c("n", "f"))$keys$keys, c(2, 1, 1))

  days <- data.frame(day = as.Date("2024-01-01") + 0:2)
  expect_equal(describe_match(days, days[2:3, , drop = FALSE], by = "day")$keys$keys, c(2, 1, 0))
})

test_that("keys of different types are refused, naming the columns", {
  data <- data.frame(cpr = c("1", "2"), day = as.Date("2024-01-01"))
  ref  <- data.frame(id = c(1, 2), day = c(19723, 19724))
  expect_error(describe_match(data, ref, by = c(cpr = "id")), "same type")
  expect_error(describe_match(data, ref, by = c(cpr = "id")), "cpr.*character.*id.*numeric")
  expect_error(describe_match(data, ref, by = "day"), "same type")
  expect_error(describe_match(ref, data, by = c(id = "cpr")), "same type")
  # The error is that of describe_match(), not of a helper inside it
  cnd <- rlang::catch_cnd(describe_match(data, ref, by = "day"), classes = "error")
  expect_equal(cnd$call[[1]], quote(describe_match))
})

test_that("an empty table on either side is counted as such", {
  m <- describe_match(income, persons[0, ], by = c(cpr = "person_id"))
  expect_equal(m$keys$keys, c(0, 3, 0))
  expect_equal(m$keys$rows, c(0, 4, 0))
  expect_equal(m$n_join_rows, 5)

  m <- describe_match(income[0, ], persons, by = c(cpr = "person_id"))
  expect_equal(m$keys$keys, c(0, 0, 3))
  expect_equal(m$keys$ref_rows, c(0, 0, 4))
  expect_equal(m$n_ref_missing, 0)
  expect_equal(m$n_ref_dup_keys, 1)
  expect_equal(m$n_join_rows, 0)

  m <- describe_match(income[0, ], persons[0, ], by = c(cpr = "person_id"))
  expect_equal(m$keys$keys, c(0, 0, 0))
  expect_output(print(m), "Every row of data has a match")
})

test_that("the key must be stated and exist in both tables", {
  expect_error(describe_match(income, persons), "non-empty character")
  expect_error(describe_match(income, persons, by = "cpr"), "must exist")
  expect_error(describe_match(income, persons, by = c(cpr = "person_id", cpr = "kommune")), "repeat")
  expect_error(describe_match(income, list(person_id = "a"), by = c(cpr = "person_id")),
               "database table or an Arrow table")
})

test_that("the summary prints the counts", {
  expect_snapshot(print(describe_match(income, persons, by = c(cpr = "person_id"))))
  expect_snapshot(print(describe_match(income[1:3, ], persons[-3, ], by = c(cpr = "person_id"))))
  expect_output(print(describe_match(persons, persons, by = "person_id")), "Match: person_id")
})
