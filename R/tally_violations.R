#' Count violations for several rules at once
#'
#' Evaluates a set of named rules and returns one row per rule with the
#' number of violating rows. Where a chain of [ensure_none()] calls stops at
#' the first abort, `tally_violations()` evaluates every rule, so a delivery
#' with five problems is reported as five problems in one go.
#'
#' ## Why "tally"
#'
#' To tally is to keep count, as with tally marks or [dplyr::tally()]. The
#' name marks the difference from the checkpoints: those *judge* (a
#' check passes, warns or aborts), while `tally_violations()` only *counts*
#' and never warns or stops. Severity stays a separate, explicit decision,
#' made afterwards by piping the tally into [ensure_empty()]. The same tally
#' therefore serves both as a hard gate in production and as a report you
#' read or send on.
#'
#' The result is itself a violation set once filtered, which closes the loop
#' back to [ensure_empty()]:
#'
#' ```r
#' df |>
#'   tally_violations(
#'     "Missing id"       = is.na(id),
#'     "Negative amount"  = amount < 0,
#'     "Unknown industry" = !branche %in% codebook$branche
#'   ) |>
#'   dplyr::filter(n > 0) |>
#'   ensure_empty(abort_msg = "The delivery failed validation")
#' ```
#'
#' ## Thresholds
#'
#' `total` is the number of rows checked, so a rule can be allowed a few
#' violations, by count or by share, before it becomes a problem:
#'
#' ```r
#' tally <- tally_violations(df,
#'   "Missing id"      = is.na(id),
#'   "Negative amount" = amount < 0
#' )
#'
#' tally |>
#'   dplyr::filter(n > 0) |>
#'   ensure_empty(warn_msg = "Rules with violations")
#'
#' tally |>
#'   dplyr::filter(n / total > 0.001) |>
#'   ensure_empty(abort_msg = "Rules broken by more than 0.1 % of the rows")
#' ```
#'
#' Kept unfiltered, it is a validation report: send it back to whoever made
#' the data, e.g. with `lazer::write_excel()` after dropping the `rows` column.
#'
#' Rules follow [dplyr::filter()] semantics: each must give `TRUE` for a
#' violating row, and `NA` counts as no violation. Rules are evaluated with
#' [dplyr::mutate()], so `if_any()`, `across()` and grouped data work.
#'
#' A database or Arrow table (see [checkpoints]) is tallied in a single
#' query for all rules. Rows in a database have no numbers, so the result
#' then has no `rows` column.
#'
#' @inheritParams checkpoints
#' @param ... Rules that describe a violating row. Name them; an unnamed rule
#'   is named after its expression.
#'
#' @return A tibble with one row per rule and the columns `rule` (name),
#'   `n` (number of violating rows), `total` (number of rows checked, the
#'   same for every rule) and, for a data frame, `rows` (list of the
#'   violating rows' numbers in `data`, for `data[rows[[i]], ]`).
#'
#' @examples
#' tally_violations(mtcars,
#'   "Few cylinders"  = cyl < 4,
#'   "High mileage"   = mpg > 30,
#'   "Missing weight" = is.na(wt)
#' )
#'
#' @seealso [ensure_empty()], [ensure_none()], [ensure_all()]
#'
#' @export
tally_violations <- function(data, ...) {
  tbl <- check_table(data)
  rules <- rlang::enquos(..., .named = TRUE)
  if (length(rules) == 0) {
    cli::cli_abort("Supply at least one rule in {.arg ...}.")
  }

  call <- rlang::current_env()
  if (is_remote(tbl)) return(remote_tally(tbl, rules, call))
  rows <- lapply(names(rules), function(name) {
    hit <- tryCatch(
      dplyr::mutate(data, .inshape_rule = !!rules[[name]], .keep = "none")$.inshape_rule,
      error = function(e) {
        cli::cli_abort("Rule {.val {name}} could not be evaluated.",
                       parent = e, call = call)
      }
    )
    if (!is.logical(hit)) {
      cli::cli_abort(
        "Rule {.val {name}} must give a logical vector, not {.cls {class(hit)}}.",
        call = call
      )
    }
    which(hit)
  })

  tibble::tibble(
    rule  = names(rules),
    n     = lengths(rows),
    total = nrow(data),
    rows  = rows
  )
}
