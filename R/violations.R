#' The rows that break a check
#'
#' A failed checkpoint shows the number of offending rows and the first few
#' of them. `violations()` returns all of them, to filter, count and look at
#' in the session: wrap the check in it.
#'
#' ```r
#' dups <- violations(ensure_unique(persons, cpr, year))
#' ```
#'
#' It exists so the rows can be had without knowing about conditions. A
#' failed check signals a condition of class `inshape_failure` that carries
#' the rows (see [checkpoints]), and catching it by hand has a trap: a
#' `tryCatch()` around a check that *passes* returns the whole data, since
#' that is what a checkpoint returns. `violations()` returns no rows then.
#'
#' Nothing is printed for a failed check, whether it warns or aborts: the
#' rows are the answer. A check that passes still says so.
#'
#' The rows are personal data, as they are in the message. They are kept
#' only where you assign them; see *Personal data* in [checkpoints].
#'
#' @param check A call to an `ensure_*()` checkpoint, or a pipeline of them.
#'   In a pipeline the rows of the first check that fails are returned, and
#'   the checks after it do not run.
#'
#' @return A tibble with the offending rows, key columns first, and the
#'   diagnostic column of the check (`dupid`, `overlap_id`, `gap`, `outside`,
#'   `reason`) where it has one. When every check passes, the data with no
#'   rows, and so without a diagnostic column. For a database or Arrow table
#'   both are queries: `collect()` them to get the rows.
#'
#' @examples
#' persons <- data.frame(
#'   cpr  = c("a", "b", "b", "c"),
#'   year = c(2024, 2024, 2024, 2024)
#' )
#' violations(ensure_unique(persons, cpr, year))
#'
#' # No rows when the check passes
#' violations(ensure_unique(persons, cpr))
#'
#' @seealso [checkpoints] for the condition and for personal data.
#'
#' @export
violations <- function(check) {
  rows <- NULL
  data <- tryCatch(check, inshape_failure = function(cnd) {
    rows <<- cnd$violations
    NULL
  })
  if (!is.null(rows)) return(rows)
  if (is.data.frame(data)) return(tibble::as_tibble(utils::head(data, 0L)))
  if (inherits(data, c("tbl_lazy", "ArrowTabular", "Dataset", "arrow_dplyr_query"))) {
    return(utils::head(check_table(data), 0L))
  }
  cli::cli_abort(c(
    "{.arg check} must be a call to an {.code ensure_*()} checkpoint.",
    "x" = "It returned {.obj_type_friendly {data}}, not the data that was checked."
  ))
}
