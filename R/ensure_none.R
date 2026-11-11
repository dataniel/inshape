#' Assert that no rows match a condition
#'
#' The in-pipeline form of [ensure_empty()]. Instead of filtering for the
#' violations and piping *them* in, pass the condition directly. The check is
#' the same, but `data` itself is returned, so the pipeline continues with
#' all rows:
#'
#' ```r
#' df |>
#'   ensure_none(is.na(id), abort_msg = "Rows without an id") |>
#'   ensure_none(amount < 0) |>
#'   mutate(...)
#' ```
#'
#' Conditions follow [dplyr::filter()] semantics: several conditions are
#' combined with `&`, and a row where a condition is `NA` does not count as a
#' violation. Test for missing values explicitly with `is.na()` when they
#' matter, or state the rule positively with [ensure_all()], where a missing
#' value is a violation.
#'
#' Without a message, the condition itself becomes the message
#' (`"Found rows where amount < 0"`), which is often clear enough during
#' exploration. Write your own message for checks that stay in production.
#'
#' @param ... Conditions that describe a violating row, as in
#'   [dplyr::filter()].
#' @inheritParams checkpoints
#' @param warn_msg Message shown when rows match and no `abort_msg` is set.
#'   Defaults to a description of the condition.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' mtcars |>
#'   ensure_none(cyl < 4) |>
#'   ensure_none(mpg > 40, warn_msg = "Implausibly efficient cars") |>
#'   nrow()
#'
#' # The rows of a failed check, all of them
#' violations(ensure_none(mtcars, mpg > 30))
#'
#' \dontrun{
#' dplyr::starwars |>
#'   ensure_none(is.na(species), abort_msg = "Characters without a species")
#' }
#'
#' @seealso [ensure_all()] for the rule stated positively, where a missing
#'   value is a violation; [ensure_empty()], [tally_violations()],
#'   [checkpoints].
#'
#' @export
ensure_none <- function(data, ...,
                        success_msg = NULL,
                        warn_msg    = NULL,
                        abort_msg   = NULL) {

  tbl <- check_table(data)
  conditions <- rlang::enquos(...)
  if (length(conditions) == 0) {
    cli::cli_abort("Supply at least one condition in {.arg ...}.")
  }
  rule <- paste(vapply(conditions, rlang::as_label, character(1)), collapse = " & ")

  violations <- filter_violations(tbl, conditions, rule, rlang::current_env())

  report_check(
    violations,
    pass = paste0("No rows where ", rule),
    fail = paste0("Found rows where ", rule),
    success_msg, warn_msg, abort_msg
  )
  invisible(data)
}

# The violation set of ensure_none() and ensure_all(). An error names the
# checkpoint and the condition as the user wrote it, not the filter() the
# checkpoint is built on.
#
# ensure_all() filters on a rewritten condition. `as_written` holds the
# conditions before the rewrite: when the filter fails, they are tried
# alone, so the cause quotes the user's code rather than the rewrite.
filter_violations <- function(tbl, violating, rule, call, as_written = NULL) {
  if (is_remote(tbl)) {
    written <- as_written %||% violating
    names(written) <- paste0(".inshape_c", seq_along(written))
    labels <- vapply(written, rlang::as_label, character(1))
    check_remote_logical(tbl, written, labels, call, what = "Condition")
  }
  tryCatch(
    dplyr::filter(tbl, !!!violating),
    error = function(e) {
      if (!is.null(as_written)) {
        e <- tryCatch(
          { dplyr::filter(tbl, !!!as_written); e },
          error = function(plain) plain
        )
      }
      cli::cli_abort("The condition {.code {rule}} could not be evaluated.",
                     parent = e, call = call)
    }
  )
}
