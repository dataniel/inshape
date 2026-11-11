skip_if_not_installed("duckdb")
skip_if_not_installed("dbplyr")

local_duck <- function(..., env = parent.frame()) {
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  tables <- list(...)
  out <- lapply(names(tables), function(nm) {
    dplyr::copy_to(con, tables[[nm]], nm)
    dplyr::tbl(con, nm)
  })
  if (length(out) == 1) out[[1]] else out
}

# The summaries as plain lists, with tibbles as data frames of doubles, so
# integer and double counts compare equal
plain <- function(x) {
  lapply(unclass(x), function(v) {
    if (is.data.frame(v)) as.data.frame(lapply(v, function(c) if (is.numeric(c)) as.double(c) else c))
    else if (is.numeric(v)) as.double(v) else v
  })
}

set.seed(9)
n <- 400
panel <- data.frame(
  cpr  = sample(c(sprintf("p%02d", 1:60), NA), n, TRUE),
  year = sample(c(2018:2022, NA), n, TRUE, prob = c(rep(.19, 5), .05)),
  sex  = sample(c("F", "M", NA), n, TRUE, prob = c(.48, .48, .04)),
  kom  = sample(c("955", "956", "957", "960", NA), n, TRUE)
)
panel$kom[panel$year == 2018 & panel$kom %in% "960"] <- "955"

test_that("describe_key() on DuckDB equals the summary in memory", {
  tbl <- local_duck(t = panel)
  expect_equal(plain(describe_key(tbl, cpr, year)), plain(describe_key(panel, cpr, year)))
  expect_equal(plain(describe_key(tbl, cpr)), plain(describe_key(panel, cpr)))
})

test_that("describe_panel() on DuckDB equals the summary in memory", {
  tbl <- local_duck(t = panel)
  for (periods in list(NULL, 2017:2022)) {
    # All patterns: at the cut of the top ten, ties may be kept differently
    remote <- plain(describe_panel(tbl, cpr, year, periods = periods, patterns = 1000))
    local  <- plain(describe_panel(panel, cpr, year, periods = periods, patterns = 1000))
    # Patterns with the same count may come in another order
    key <- function(p) p[order(-p$units, p$pattern), ]
    expect_equal(key(remote$patterns), key(local$patterns), ignore_attr = TRUE)
    remote$patterns <- local$patterns <- NULL
    expect_equal(remote, local)
  }
})

test_that("describe_varying() on DuckDB equals the summary in memory", {
  tbl <- local_duck(t = panel)
  expect_equal(plain(describe_varying(tbl, cpr)), plain(describe_varying(panel, cpr)),
               ignore_attr = TRUE)
})

test_that("describe_codes() on DuckDB equals the summary in memory", {
  tbl <- local_duck(t = panel)
  expect_equal(plain(describe_codes(tbl, kom, year)), plain(describe_codes(panel, kom, year)),
               ignore_attr = TRUE)
})

test_that("describe_spells() on DuckDB equals the summary in memory", {
  set.seed(10)
  m <- 300
  spells <- data.frame(cpr = sample(c(letters, NA), m, TRUE),
                       start = as.Date("2015-01-01") + sample.int(2000, m, TRUE))
  spells$end <- spells$start + sample(c(-3, 0:120), m, TRUE)
  spells$end[sample.int(m, 10)] <- NA
  spells$start[sample.int(m, 5)] <- NA
  spells <- rbind(spells, spells[1:3, ])
  spells$end[4] <- spells$start[5] - 1
  tbl <- local_duck(t = spells)
  expect_equal(plain(describe_spells(tbl, cpr, start, end)),
               plain(describe_spells(spells, cpr, start, end)), ignore_attr = TRUE)

  years <- data.frame(id = c(1, 1, 1, 2), start = c(2010L, 2013L, 2014L, 2011L),
                      end = c(2012L, 2013L, NA, 2015L))
  expect_equal(plain(describe_spells(local_duck(y = years), id, start, end)),
               plain(describe_spells(years, id, start, end)), ignore_attr = TRUE)
})

test_that("describe_changes() on DuckDB equals the comparison in memory", {
  old <- data.frame(cpr = c("a", "b", "c", "d", NA), year = 2023,
                    sex = c("F", "M", "F", NA, "M"), born = c(1950, 1960, NA, 1970, 1980),
                    kom = c("1", "2", "3", "4", "5"))
  new <- data.frame(cpr = c("b", "a", "d", "e", NA), year = 2023,
                    sex = c("F", "F", "M", "F", "M"), born = c(1960L, 1950L, NA, 1990L, 1981L),
                    kom = c(2, 1, 4, 5, 5))
  tbls <- local_duck(o = old, n = new)
  remote <- describe_changes(tbls[[1]], tbls[[2]], cpr, year)
  local  <- describe_changes(old, new, cpr, year)
  for (part in c("added", "removed", "changed")) {
    r <- dplyr::arrange(dplyr::collect(remote[[part]]), cpr)
    l <- dplyr::arrange(local[[part]], cpr)
    expect_equal(as.data.frame(r), as.data.frame(l), ignore_attr = TRUE, info = part)
    remote[[part]] <- local[[part]] <- NULL
  }
  expect_equal(plain(remote), plain(local), ignore_attr = TRUE)
  expect_error(describe_changes(tbls[[1]], new, cpr), "both be data frames")
})

test_that("ensure_codes() on DuckDB finds the same rows as in memory", {
  tbl <- local_duck(t = panel)
  valid <- c("955", "956", "957")
  for (na_ok in c(TRUE, FALSE)) {
    remote <- rlang::catch_cnd(ensure_codes(tbl, kom, valid, na_ok = na_ok), "inshape_failure")
    local  <- rlang::catch_cnd(ensure_codes(panel, kom, valid, na_ok = na_ok), "inshape_failure")
    key <- function(v) dplyr::arrange(tibble::as_tibble(v), cpr, year, sex, kom)
    expect_equal(key(dplyr::collect(remote$violations)), key(local$violations))
  }
})

test_that("describe_match() on DuckDB equals the summary in memory", {
  set.seed(11)
  ref <- data.frame(person = sample(c(sprintf("p%02d", 40:75), NA), 80, TRUE),
                    year   = sample(c(2019:2023, NA), 80, TRUE))
  tbls <- local_duck(t = panel, r = ref)
  by <- c(cpr = "person", "year")
  local <- plain(describe_match(panel, ref, by = by))
  expect_gt(local$n_join_rows, nrow(panel))
  expect_equal(plain(describe_match(tbls[[1]], tbls[[2]], by = by)), local)
  # A local reference travels to the database as an inline query
  expect_equal(plain(describe_match(tbls[[1]], ref, by = by)), local)
  expect_equal(plain(describe_match(tbls[[1]], tbls[[2]], by = c(cpr = "person"))),
               plain(describe_match(panel, ref, by = c(cpr = "person"))))
  # An integer key against a double one
  ref$year <- as.double(ref$year)
  expect_equal(plain(describe_match(tbls[[1]], ref, by = by)), local)
  expect_equal(plain(describe_match(tbls[[1]], ref[0, ], by = by)),
               plain(describe_match(panel, ref[0, ], by = by)))
  expect_error(describe_match(panel, tbls[[2]], by = by), "local")
})
