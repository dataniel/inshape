d <- function(x) as.Date(x)

spells <- data.frame(
  cpr   = c("a", "a", "b", "b", "c", "c", "c"),
  start = d(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-06-01",
              "2020-01-01", "2020-03-01", "2020-05-01")),
  end   = d(c("2020-12-31", NA,           "2020-06-30", "2021-12-31",
              "2020-04-01", "2020-05-01", "2020-12-31"))
)

overlaps <- function(...) {
  rlang::catch_cnd(ensure_no_overlap(...), classes = "lustrum_failure")$violations
}

test_that("overlapping spells are reported with a shared overlap_id", {
  v <- overlaps(spells, cpr, start, end)
  expect_equal(v$cpr, c("b", "b", "c", "c", "c"))
  # c's three spells overlap through a chain, so they form one group
  expect_equal(v$overlap_id, c(1L, 1L, 2L, 2L, 2L))
  expect_equal(names(v)[1], "overlap_id")
})

test_that("the rule's columns come first and groups are counted", {
  wide <- cbind(note = "x", spells, kom = 101L)
  cnd <- rlang::catch_cnd(ensure_no_overlap(wide, cpr, start, end),
                          classes = "lustrum_failure")
  expect_equal(names(cnd$violations),
               c("overlap_id", "cpr", "start", "end", "note", "kom"))
  expect_match(conditionMessage(cnd), "5 rows in 2 groups")
})

test_that("adjacent spells do not overlap, shared days do", {
  adjacent <- data.frame(cpr = "a", start = d(c("2020-01-01", "2020-02-01")),
                         end = d(c("2020-01-31", "2020-02-28")))
  expect_message(ensure_no_overlap(adjacent, cpr, start, end), "No overlapping spells")

  touching <- data.frame(cpr = "a", start = d(c("2020-01-01", "2020-01-31")),
                         end = d(c("2020-01-31", "2020-02-28")))
  expect_equal(nrow(overlaps(touching, cpr, start, end)), 2)
})

test_that("a missing end is an ongoing spell", {
  ongoing <- data.frame(cpr = "a", start = c(2010, 2015), end = c(NA, 2016))
  expect_equal(nrow(overlaps(ongoing, cpr, start, end)), 2)
})

test_that("an earlier long spell overlaps a later one through a short one", {
  nested <- data.frame(cpr = "a", start = c(1, 2, 5), end = c(10, 3, 6))
  expect_equal(overlaps(nested, cpr, start, end)$overlap_id, c(1L, 1L, 1L))
})

test_that("rows with a missing start are ignored and data is returned", {
  ok <- data.frame(cpr = c("a", "a"), start = c(NA, 2020), end = c(2025, 2021))
  expect_message(out <- ensure_no_overlap(ok, cpr, start, end), "No overlapping")
  expect_equal(out, ok)
})

test_that("a long spell of one unit does not carry over to the next unit", {
  ok <- data.frame(cpr = c("a", "b", "b"), start = c(1, 2, 5), end = c(NA, 3, 6))
  expect_no_warning(ensure_no_overlap(ok, cpr, start, end))
})

test_that("cummax_by() matches a grouped cummax()", {
  set.seed(1)
  unit <- sort(sample(1:30, 300, TRUE))
  unit <- match(unit, unique(unit))
  x <- sample(c(-5:20, Inf), 300, TRUE)
  expect_identical(cummax_by(x, unit), ave(x, unit, FUN = cummax))
  expect_identical(cummax_by(numeric(), integer()), numeric())
})

test_that("spells of different units never overlap", {
  ok <- data.frame(cpr = c("a", "b"), start = c(2020, 2020), end = c(2021, 2021))
  expect_no_warning(ensure_no_overlap(ok, cpr, start, end))
})
