# Keep helpers local to this file; existing remote test files define their own.
addition_violations <- function(expr) {
  cnd <- rlang::catch_cnd(expr, classes = "inshape_failure")
  expect_false(is.null(cnd))
  rows <- cnd$violations
  if (!is.data.frame(rows)) rows <- dplyr::collect(rows)
  tibble::as_tibble(rows)
}

addition_duck <- function(df, env = parent.frame()) {
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  dplyr::copy_to(con, df, "input")
}

test_that("diagnostics preserve all original columns, including keys", {
  df <- data.frame(dupid = c(7, 7), dupid.1 = c("a", "b"),
                   outside = c(2020, 2021), last = c(2019, 2019),
                   overlap_id = c(3, 3), start = c(1, 2), end = c(4, 5),
                   .inshape_prev_end = c(8, 9), .inshape_note = c("x", "y"))
  for (remote in c(FALSE, TRUE)) {
    x <- if (remote) addition_duck(df) else df
    dup <- addition_violations(ensure_unique(x, dupid))
    expect_equal(dup$dupid, df$dupid)
    expect_equal(dup$dupid.1, df$dupid.1)
    expect_equal(dup$dupid.2, c(1, 1))
    out <- addition_violations(ensure_within(x, outside, to = last))
    expect_equal(out$outside, df$outside)
    expect_equal(out$outside.1, rep("after last", 2))
    over <- addition_violations(ensure_no_overlap(x, overlap_id, start, end))
    expect_equal(over$overlap_id, df$overlap_id)
    expect_equal(over$overlap_id.1, c(1, 1))
    expect_equal(over$.inshape_prev_end, df$.inshape_prev_end)
    expect_equal(over$.inshape_note, df$.inshape_note)
    expect_equal(as.data.frame(over[names(df)]), df)
  }
})

test_that("changes explicitly identify skipped list and matrix columns", {
  old <- tibble::tibble(id = 1:2, value = c(1, 2), details = list(1, 2),
                        matrix = matrix(1:4, nrow = 2))
  new <- old
  new$details <- list(3, 4)
  new$matrix[,] <- 0
  out <- describe_changes(old, new, id)
  expect_equal(out$columns_skipped, c("details", "matrix"))
  expect_equal(out$n_changed, 0)
  expect_output(print(out), "Columns not compared: details, matrix")
  new$details <- 1:2
  expect_equal(describe_changes(old, new, id)$columns_skipped, c("details", "matrix"))
  expect_equal(describe_changes(old["id"], new["id"], id)$columns_skipped, character())
})

test_that("valid spell checks handle boundaries, missing values and collisions", {
  df <- data.frame(row = 1:6, start = c(1, NA, 4, 2, 2, NA),
                   end = c(1, 3, 3, NA, 3, NA), reason = letters[1:6])
  for (remote in c(FALSE, TRUE)) {
    x <- if (remote) addition_duck(df) else df
    for (open in c(TRUE, FALSE)) {
      v <- addition_violations(ensure_valid_spells(x, start, end, open_end = open))
      v <- v[order(v$row), ]
      expected <- if (open) c(2, 3, 6) else c(2, 3, 4, 6)
      expect_equal(v$row, expected)
      expect_equal(v$reason, df$reason[expected])
      expect_equal(v$reason.1, if (open) c("missing start", "end before start", "missing start")
                   else c("missing start", "end before start", "missing end", "missing start"))
    }
  }
  expect_error(ensure_valid_spells(df, start, end, abort_msg = "Bad spells"),
                "Bad spells", class = "inshape_failure")
  expect_error(ensure_valid_spells(df, start, end, open_end = NA), "TRUE or FALSE")
  expect_error(ensure_valid_spells(df, c(start, end), end), "exactly one")
  good <- df[c(1, 4, 5), ]
  expect_message(out <- ensure_valid_spells(good, start, end), "Valid spell")
  expect_identical(out, good)
  expect_message(ensure_valid_spells(df[0, ], start, end), "Valid spell")
  dates <- data.frame(start = as.Date("2024-01-01"), end = as.Date("2024-01-01"))
  expect_message(ensure_valid_spells(dates, start, end), "Valid spell")
  dates$end <- 2024
  expect_error(ensure_valid_spells(dates, start, end), "same scale")
})

test_that("matching handles mapped composite keys and explicit missing-key policy", {
  df <- data.frame(id = c("a", "a", "b", NA, "c", "a"),
                   year = c(2020L, 2021L, 2020L, 2020L, NA, 2020L), row = 1:6)
  ref <- data.frame(person = c("a", "a", NA, "c"), year = c(2020L, 2020L, 2020L, NA))
  for (remote in c(FALSE, TRUE)) {
    x <- if (remote) addition_duck(df) else df
    for (na in c("never", "na")) {
      v <- addition_violations(ensure_matched(x, ref, by = c(id = "person", "year"), na_matches = na))
      expect_equal(sort(v$row), if (na == "never") 2:5 else 2:3)
    }
    if (remote) {
      r <- dplyr::copy_to(dbplyr::remote_con(x), ref, "reference")
      v <- addition_violations(ensure_matched(x, r, by = c(id = "person", "year")))
      expect_equal(sort(v$row), 2:5)
    }
    v <- addition_violations(ensure_matched(x, ref[0, ], by = c(id = "person", "year")))
    expect_equal(sort(v$row), 1:6)
  }
  expect_message(out <- ensure_matched(df, df, by = c("id", "year"), na_matches = "na"), "Matched in the reference")
  expect_identical(out, df)
  expect_error(ensure_matched(df, ref), "non-empty character")
  expect_error(ensure_matched(df, ref, by = "absent"), "must exist")
  expect_error(ensure_matched(df, ref, by = c(id = "person", id = "person")), "repeat")
  expect_error(ensure_matched(df, ref, by = c(id = "person"), abort_msg = "Missing persons"),
                "Missing persons", class = "inshape_failure")
})

test_that("temporal code lists respect open bounds, gaps, endpoints and NA policy", {
  codes <- data.frame(code = c("a", "a", "b", "c", "d", "a"),
                      valid_from = c(2020, 2024, NA, 2022, NA, 2020),
                      valid_to = c(2021, 2025, 2020, NA, NA, 2021))
  df <- data.frame(row = 1:13,
                   code = c("a", "a", "a", "a", "a", "b", "b", "c", "d", "d", NA, "z", "c"),
                   year = c(2020, 2021, 2022, 2024, 2025, 2019, 2021, 2022, 1900, NA, NA, 2020, 2021))
  for (remote in c(FALSE, TRUE)) {
    x <- if (remote) addition_duck(df) else df
    for (na_ok in c(TRUE, FALSE)) {
      v <- addition_violations(ensure_codes(x, code, codes, time = year, na_ok = na_ok))
      expect_equal(sort(v$row), if (na_ok) c(3, 7, 10, 12, 13) else c(3, 7, 10, 11, 12, 13))
    }
    v <- addition_violations(ensure_codes(x, code, codes[0, ], time = year))
    expect_equal(sort(v$row), setdiff(1:13, 11))
  }
  good <- df[c(1, 2, 4, 5, 6, 8, 9, 11), ]
  expect_message(out <- ensure_codes(good, code, codes, time = year), "Valid codes")
  expect_identical(out, good)
  expect_error(ensure_codes(df, code, codes), "time")
  expect_error(ensure_codes(df, code, "a", time = year), "temporal code list")
  expect_error(ensure_codes(df, code, codes["code"], time = year), "valid_from")
  bad <- codes
  bad$valid_to[1] <- 2019
  expect_error(ensure_codes(df, code, bad, time = year), "before")
  bad <- codes
  bad$code[1] <- NA
  expect_error(ensure_codes(df, code, bad, time = year), "non-missing")
  bad <- codes
  bad$valid_from <- as.Date("2020-01-01") + seq_len(nrow(bad))
  expect_error(ensure_codes(df, code, bad, time = year), "same scale")
})

test_that("temporal Date codes preserve leading zeros and compare exact days", {
  codes <- data.frame(code = "0955", valid_from = as.Date("2020-01-01"), valid_to = as.Date("2020-01-31"))
  df <- data.frame(row = 1:4, code = c("0955", "0955", "0955", "955"),
                   day = as.Date(c("2020-01-01", "2020-01-31", "2020-02-01", "2020-01-15")))
  for (remote in c(FALSE, TRUE)) {
    x <- if (remote) addition_duck(df) else df
    expect_equal(sort(addition_violations(ensure_codes(x, code, codes, time = day))$row), 3:4)
  }
  df$code <- factor(df$code)
  expect_equal(addition_violations(ensure_codes(df, code, codes, time = day))$row, 3:4)
})

test_that("Arrow inputs support the new checks and return unchanged", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("dbplyr")
  x <- arrow::arrow_table(data.frame(id = c("a", "b"), start = c(1L, 3L), end = c(2L, 2L)))
  expect_equal(addition_violations(ensure_valid_spells(x, start, end))$id, "b")
  expect_equal(addition_violations(ensure_matched(x, data.frame(id = "a"), by = "id"))$id, "b")
  codes <- data.frame(code = c("a", "b"), valid_from = c(1L, 1L), valid_to = c(2L, 2L))
  expect_equal(addition_violations(ensure_codes(x, id, codes, time = start))$id, "b")
  expect_message(out <- ensure_matched(x, data.frame(id = c("a", "b")), by = "id"), "Matched in the reference")
  expect_identical(out, x)
})

test_that("database changes report skipped lists even when no columns are compared", {
  tbl <- addition_duck(data.frame(id = 1L))
  con <- dbplyr::remote_con(tbl)
  DBI::dbExecute(con, "CREATE TABLE old_list AS SELECT 1 AS id, [1,2] AS details")
  DBI::dbExecute(con, "CREATE TABLE new_list AS SELECT 1 AS id, [3,4] AS details")
  out <- describe_changes(dplyr::tbl(con, "old_list"), dplyr::tbl(con, "new_list"), id)
  expect_equal(out$columns_skipped, "details")
  expect_equal(out$n_changed, 0)
  expect_equal(out$n_kept, 1)
  expect_equal(nrow(out$columns), 0)
  expect_equal(nrow(dplyr::collect(out$changed)), 0)
  expect_output(print(out), "Columns not compared: details")
  expect_equal(describe_changes(tbl, tbl, id)$columns_skipped, character())
})
