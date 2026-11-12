panel <- data.frame(
  cpr  = c("a", "a", "a", "b", "b", "c", "c"),
  year = c(2020, 2021, 2022, 2020, 2022, 2022, 2022)
)
spells <- data.frame(
  cpr   = c("a", "a", "b", "b"),
  start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-06-01")),
  end   = as.Date(c("2020-12-31", NA, "2020-06-30", "2021-12-31"))
)

overview <- function(expr) {
  cnd <- rlang::catch_cnd(expr, classes = "inshape_failure")
  strsplit(cli::ansi_strip(conditionMessage(cnd)), "\n", fixed = TRUE)[[1]]
}

test_that("ensure_panel() passes in one line and returns the data", {
  expect_message(out <- ensure_panel(panel[1:3, ], cpr, year),
                 "Panel cpr by year: 3 checks passed")
  expect_identical(out, panel[1:3, ])
  expect_message(ensure_panel(panel[1:3, ], cpr, year, success_msg = "Fine"), "Fine")
})

test_that("ensure_panel() runs every check and shows one overview", {
  lines <- overview(ensure_panel(panel, cpr, year))
  expect_equal(lines[1], "Panel cpr by year: 2 of 3 checks failed")
  expect_match(lines[2], "Complete: cpr, year")
  expect_match(lines[3], "Duplicate rows on cpr, year (2 rows in 1 group)", fixed = TRUE)
  expect_true(any(grepl("Gaps in panel: missing cpr-year combinations (1 row)", lines, fixed = TRUE)))
  expect_true(any(grepl("By year: 2021 (1)", lines, fixed = TRUE)))
  expect_equal(sub("^\\S+ ", "", utils::tail(lines, 2)), c(
    "For the rows: violations(ensure_unique(panel, cpr, year))",
    "For the rows: violations(ensure_balanced(panel, cpr, year, gaps_only = TRUE))"
  ))
  # The single checks' own messages are not shown on top
  expect_no_message(expect_warning(ensure_panel(panel, cpr, year)))
})

test_that("the wrappers take the messages of the checkpoints", {
  expect_error(ensure_panel(panel, cpr, year, abort_msg = "Broken panel"),
               "^Broken panel", class = "inshape_failure")
  expect_warning(ensure_panel(panel, cpr, year, warn_msg = "Odd panel"), "^Odd panel")
  lines <- overview(ensure_panel(panel, cpr, year, gaps_only = FALSE))
  expect_true(any(grepl("Panel is not balanced", lines)))
  expect_true(any(grepl("ensure_balanced(panel, cpr, year))", lines, fixed = TRUE)))
})

test_that("ensure_spells() does not check overlaps until the spells are valid", {
  bad <- rbind(spells, data.frame(cpr = "c", start = as.Date("2020-02-01"),
                                  end = as.Date("2020-01-01")))
  lines <- overview(ensure_spells(bad, cpr, start, end, no_gaps = TRUE))
  expect_equal(lines[1], "Spells per cpr: 1 of 4 checks failed")
  expect_true(any(grepl("Invalid spells: start to end (1 row in 1 group)", lines, fixed = TRUE)))
  expect_true(any(grepl("Not checked until the spells are valid: overlapping spells per cpr", lines)))
  expect_true(any(grepl("Not checked until the spells are valid: gaps between spells per cpr", lines)))

  lines <- overview(ensure_spells(spells, cpr, start, end))
  expect_equal(lines[1], "Spells per cpr: 1 of 3 checks failed")
  expect_true(any(grepl("violations(ensure_no_overlap(spells, cpr, start, end))", lines, fixed = TRUE)))
  expect_message(ensure_spells(spells[1:3, ], cpr, start, end), "Spells per cpr: 3 checks passed")
})

test_that("ensure_lookup() checks the reference key and the match", {
  codes <- data.frame(code = c("955", "956", "956"), name = c("A", "B", "B"))
  persons <- data.frame(cpr = c("a", "b"), kom = c("955", "957"))
  lines <- overview(ensure_lookup(persons, codes, by = c(kom = "code")))
  expect_equal(lines[1], "Lookup on kom: 2 of 2 checks failed")
  expect_true(any(grepl("Duplicate keys in codes: code (2 rows in 1 group)", lines, fixed = TRUE)))
  expect_true(any(grepl("Keys missing from the reference: kom (1 row)", lines, fixed = TRUE)))
  expect_true(any(grepl("violations(ensure_matched(persons, codes, by = c(kom = \"code\")))",
                        lines, fixed = TRUE)))
  expect_message(ensure_lookup(persons[1, ], codes[1:2, ], by = c(kom = "code")),
                 "Lookup on kom: 2 checks passed")
})

test_that("violations() on a wrapper names the checks to wrap instead", {
  expect_error(violations(ensure_panel(panel, cpr, year)),
               "ensure_balanced\\(panel, cpr, year, gaps_only = TRUE\\)")
  expect_equal(nrow(violations(ensure_panel(panel[1:3, ], cpr, year))), 0)
})

test_that("the wrappers check database tables where they live", {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  dplyr::copy_to(con, panel, "panel")
  tbl <- dplyr::tbl(con, "panel")
  remote <- overview(ensure_panel(tbl, cpr, year))
  local  <- overview(ensure_panel(panel, cpr, year))
  # The same overview, except that the hints name the data `data`
  expect_length(remote, length(local))
  expect_equal(remote[1:7], local[1:7])
  expect_s3_class(suppressWarnings(ensure_panel(tbl, cpr, year)), "tbl_lazy")
})
