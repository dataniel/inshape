families <- data.frame(
  family = c(1, 1, 1, 2, 2, 3, 4, 4, 5, 5, 5),
  role   = c("reference", "partner", "child", "reference", "child",
             "child", "reference", "reference", "reference", "partner", "child")
)

test_that("describe_groups() counts the groups per composition", {
  d <- describe_groups(families, family, role)
  expect_s3_class(d, "inshape_groups")
  expect_equal(d$n_groups, 5)
  expect_equal(d$roles, c("child", "partner", "reference"))
  comp <- d$compositions
  expect_equal(comp$composition[1], "1 child + 1 partner + 1 reference")
  expect_equal(comp$groups[1], 2)
  expect_true("1 child" %in% comp$composition)
  expect_true("2 reference" %in% comp$composition)
  expect_output(print(d), "Most common compositions")
})

test_that("ensure_counts() reports every row of the groups that break a limit", {
  cnd <- rlang::catch_cnd(
    ensure_counts(families, family, role, limits = list(reference = 1, partner = c(0, 1))),
    classes = "inshape_failure")
  v <- cnd$violations
  expect_equal(unique(v$family), c(3, 4))
  expect_equal(unique(v$broken), c("reference: 0 (needs 1)", "reference: 2 (needs 1)"))
  msg <- conditionMessage(cnd)
  expect_match(msg, "3 rows\n", fixed = TRUE)
  expect_match(msg, "In 2 groups", fixed = TRUE)
  expect_match(msg, "reference: 2 (needs 1) in 1 group", fixed = TRUE)

  expect_message(ensure_counts(families[families$family %in% c(1, 2, 5), ], family, role,
                               limits = list(reference = 1, child = c(1, Inf))),
                 "Within the limits")
})

test_that("without a role, ensure_counts() counts rows per group", {
  parents <- data.frame(child = c("a", "a", "b", "b", "b"), parent = c("m", "f", "m", "f", "x"))
  v <- violations(ensure_counts(parents, child, limits = c(0, 2)))
  expect_equal(v$child, c("b", "b", "b"))
  expect_equal(v$broken[1], "rows: 3 (needs at most 2)")
  expect_error(ensure_counts(parents, child, limits = list(a = 1)), "one count or range")
  expect_error(ensure_counts(families, family, role, limits = 1), "named list")
  expect_error(ensure_counts(families, family, role, limits = list(reference = c(2, 1))), "least and the most")
})

persons <- data.frame(
  cpr    = c("a", "b", "c", "d", "e", "f"),
  spouse = c("b", "a", "d", "e", "x", "f"),
  family = c(1, 1, 2, 3, 3, 4)
)

test_that("ensure_references() finds missing, one-sided, misplaced and self references", {
  v <- violations(ensure_references(persons, cpr, spouse, same = family, mutual = TRUE))
  expect_equal(v$cpr, c("c", "d", "e", "f"))
  expect_equal(v$problem, c("in another family", "does not point back", "not found",
                            "points to itself"))
  expect_message(ensure_references(persons[1:2, ], cpr, spouse, mutual = TRUE), "found and mutual")
})

test_that("within looks the reference up in the same period", {
  panel <- data.frame(cpr = c("a", "b", "a", "b"), year = c(1, 1, 2, 2),
                      spouse = c("b", "a", "b", NA))
  v <- violations(ensure_references(panel, cpr, spouse, within = year, mutual = TRUE))
  expect_equal(v$cpr, "a")
  expect_equal(v$year, 2)
  expect_equal(v$problem, "does not point back")
  expect_error(ensure_references(rbind(panel, panel), cpr, spouse, within = year), "not unique")
})

test_that("the group checks give the same answers in DuckDB", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  dplyr::copy_to(con, families, "families")
  dplyr::copy_to(con, persons, "persons")
  fam <- dplyr::tbl(con, "families")

  remote <- describe_groups(fam, family, role)
  local  <- describe_groups(families, family, role)
  expect_equal(remote$compositions, local$compositions)

  v <- dplyr::collect(violations(ensure_counts(fam, family, role,
                                               limits = list(reference = 1, partner = c(0, 1)))))
  expect_equal(sort(unique(v$broken)), c("reference: 0 (needs 1)", "reference: 2 (needs 1)"))

  v <- dplyr::collect(violations(ensure_references(dplyr::tbl(con, "persons"), cpr, spouse,
                                                   same = family, mutual = TRUE)))
  v <- v[order(v$cpr), ]
  expect_equal(v$problem, c("in another family", "does not point back", "not found",
                            "points to itself"))
})
