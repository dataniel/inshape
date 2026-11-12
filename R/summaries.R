# Summaries and hints in failure messages ---------------------------------
#
# Five rows of a violation set do not show its pattern: 40,000 duplicates
# may all be in one year, or spread over the whole table. Each checkpoint
# therefore hands report_check() a summary, computed only when the check
# fails: a function of the violation set that returns lines to show above
# the preview, and hints, the next step written as code to copy. Counts
# show fewer personal data than rows do.
#
# Everything here works on a data frame and on a lazy table. On a lazy
# table each count is one more query, run only on failure.

# The k most frequent values of `col` in `v`, with their counts and the
# number of distinct values. Ties are ordered by value.
top_values <- function(v, col, k = 5) {
  if (is_remote(v)) {
    counts <- dplyr::count(dplyr::ungroup(v), !!rlang::sym(col), name = ".inshape_n")
    top <- counts |>
      dplyr::arrange(dplyr::desc(.data$.inshape_n), !!rlang::sym(col)) |>
      utils::head(k) |>
      dplyr::collect()
    return(list(value = top[[col]], n = as.numeric(top$.inshape_n),
                distinct = remote_nrow(counts)))
  }
  x <- v[[col]]
  if (!is.atomic(x) || !is.null(dim(x))) return(NULL)
  id <- dense_codes(x)
  n_ids <- attr(id, "n")
  counts <- tabulate(id, n_ids)
  first <- first_row_by(id, n_ids)
  values <- x[first]
  o <- utils::head(order(-counts, xtfrm(values), method = "radix"), k)
  list(value = values[o], n = counts[o], distinct = length(counts))
}

# Values as they read in a message: dates as dates, numbers without
# scientific notation, missing as NA.
fmt_values <- function(x) {
  out <- if (is.numeric(x) && !is.object(x)) {
    vapply(x, function(v) format(v, scientific = FALSE, trim = TRUE), character(1))
  } else {
    as.character(x)
  }
  out[is.na(x)] <- "NA"
  out
}

# "label: a (3), b (2) and 4 more"
tally_line <- function(label, tv) {
  if (is.null(tv) || length(tv$n) == 0) return(character())
  more <- tv$distinct - length(tv$n)
  paste0(label, ": ",
         paste0(fmt_values(tv$value), " (", big(tv$n), ")", collapse = ", "),
         if (more > 0) paste0(" and ", big(more), " more"))
}

# "By year: 2019 (388), 2021 (24)" for the columns where the rows gather on
# a few values, or half of them on one: that is where a pattern is. A
# column where the rows spread over many values, such as cpr, says nothing
# and is left out; so does one with two rows to a value, as a duplicated
# key has. With `groups`, the number of groups of rows (duplicated keys,
# say), a column with a value per group only repeats the group and is left
# out too.
pattern_lines <- function(v, cols, n, groups = n) {
  out <- character()
  for (col in cols) {
    tv <- top_values(v, col)
    if (is.null(tv) || length(tv$n) == 0 || tv$distinct >= groups) next
    if ((tv$distinct <= 10 && tv$distinct < n / 2) || tv$n[1] >= n / 2) {
      out <- c(out, tally_line(paste("By", col), tv))
    }
  }
  out
}

# Number of distinct combinations of `cols` in `v`
n_distinct_rows <- function(v, cols) {
  if (is_remote(v)) {
    return(remote_nrow(dplyr::distinct(dplyr::select(dplyr::ungroup(v), dplyr::all_of(cols)))))
  }
  if (nrow(v) == 0) return(0)
  id <- group_ids(v, cols)
  sum(tabulate(id, attr(id, "n")) > 0L)
}

# The data as a hint names it: the variable the user passed, or `data` for
# an expression such as a pipeline.
data_label <- function(arg) {
  if (length(arg) == 1 && nchar(arg) <= 30 && identical(make.names(arg), arg)) arg else "data"
}

# A column name as it is written in code
code_name <- function(x) {
  ifelse(make.names(x) == x, x, paste0("`", x, "`"))
}

# `c(cpr, year)`, or `cpr` alone, as code
code_cols <- function(x) {
  if (length(x) == 1) code_name(x) else paste0("c(", paste(code_name(x), collapse = ", "), ")")
}

# The checkpoint call as the user can paste it into violations(): taken
# from the frame of the checkpoint, without the message arguments, which do
# not change the rows. NULL when it is too long to read on one line.
check_call_text <- function(call) {
  if (!is.environment(call)) return(NULL)
  cl <- tryCatch(rlang::frame_call(call), error = function(e) NULL)
  if (!is.call(cl)) return(NULL)
  if (!is.null(names(cl))) cl <- cl[!names(cl) %in% c("success_msg", "warn_msg", "abort_msg")]
  txt <- deparse(cl, width.cutoff = 500L)
  if (length(txt) != 1 || nchar(txt) > 80) return(NULL)
  txt
}
