#' Assert that a set of violations is empty
#'
#' The most general checkpoint. Express a rule as "the set of violations
#' must be empty", build that set with an ordinary [dplyr::filter()] or an
#' anti-join, and pipe it in. A rule that dplyr can express is a rule
#' `ensure_empty()` can check, also one no other checkpoint covers:
#'
#' ```r
#' income |>
#'   dplyr::anti_join(population, by = "cpr") |>
#'   ensure_empty(abort_msg = "Income for persons outside the population")
#' ```
#'
#' When the data has no rows, a success line is printed. Otherwise
#' `ensure_empty()` warns, or aborts with `abort_msg`, and shows the number
#' of rows and the first few of them. Wrap the check in [violations()] to
#' get all of them.
#'
#' Unlike the other checkpoints, `ensure_empty()` returns the violation set
#' it was given, not the data the rule is about, so it usually ends a
#' pipeline. Use [ensure_none()] or [ensure_all()] to check a condition and
#' carry on with all rows.
#'
#' @inheritParams checkpoints
#' @param data The violation set: a data frame or tibble, a database table
#'   (dbplyr, e.g. DuckDB) or an Arrow table or dataset; see *Database and
#'   Arrow tables* in [checkpoints].
#' @param warn_msg Message shown when `data` has rows and no `abort_msg` is
#'   set. Defaults to `"The dataset is not empty."`.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' # Success: no rows
#' ensure_empty(data.frame())
#'
#' # Warning: unexpected rows
#' mtcars |>
#'   dplyr::filter(cyl > 6) |>
#'   ensure_empty(warn_msg = "Eight-cylinder cars found")
#'
#' # Many rules at once, then one judgement
#' mtcars |>
#'   tally_violations(
#'     "Few cylinders" = cyl < 4,
#'     "High mileage"  = mpg > 30
#'   ) |>
#'   dplyr::filter(n > 0) |>
#'   ensure_empty(warn_msg = "Rules with violations")
#'
#' \dontrun{
#' # Abort: treat unexpected rows as a hard error
#' dplyr::starwars |>
#'   dplyr::filter(height < 0) |>
#'   ensure_empty(abort_msg = "Impossible: negative height")
#' }
#'
#' @seealso [ensure_none()] and [ensure_all()] to check a condition without
#'   leaving the pipeline, [tally_violations()] to count many rules at once,
#'   [violations()] for all rows of a failed check, [checkpoints].
#'
#' @export
ensure_empty <- function(data,
                         success_msg = NULL,
                         warn_msg    = NULL,
                         abort_msg   = NULL) {
  tbl <- check_table(data)
  report_check(
    tbl,
    pass = "The dataset is empty.",
    fail = "The dataset is not empty.",
    success_msg, warn_msg, abort_msg
  )
  invisible(data)
}
