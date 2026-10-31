#' Assert that columns are constant within each unit
#'
#' A checkpoint for attributes that belong to the unit, not to the row: sex
#' and birth date per person, the founding year per company. In a panel or a
#' set of spells they are repeated on every row, and a unit with two values
#' is an error, usually of linkage or of a register correction applied to
#' some years only. On failure, every row of the units that vary is
#' reported, so the conflicting values sit together. Returns `data`, so it
#' can sit in the middle of a pipeline.
#'
#' A missing value does not break the rule: a sex that is missing in one
#' year and known in another is incomplete, not contradictory. Find such
#' units with [describe_varying()], which counts them as partly missing.
#'
#' @param id Column(s) identifying the unit (tidy-select), e.g. `cpr`.
#' @param ... Columns that must be constant within a unit (tidy-select),
#'   e.g. `sex, birth_date`.
#' @inheritParams checkpoints
#' @param warn_msg Message shown (and logged) when a column varies and no
#'   `abort_msg` is set. Defaults to a description of the check.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' persons <- data.frame(
#'   cpr  = c("a", "a", "b", "b", "c", "c"),
#'   year = c(2020, 2021, 2020, 2021, 2020, 2021),
#'   sex  = c("F", "F", "M", "F", "M", NA)
#' )
#' # b changes sex; c is only missing in 2021
#' ensure_constant(persons, cpr, sex)
#'
#' @seealso [describe_varying()] to see which columns vary, and how much.
#'
#' @export
ensure_constant <- function(data, id, ...,
                            success_msg = NULL,
                            warn_msg    = NULL,
                            abort_msg   = NULL,
                            log         = getOption("lustrum.log"),
                            dump        = getOption("lustrum.dump")) {

  tbl  <- check_table(data)
  ids  <- select_names(tbl, {{ id }})
  cols <- setdiff(select_names(tbl, ...), ids)
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(cols) == 0) cli::cli_abort("Select at least one column that must be constant.")

  rows <- if (is_remote(tbl)) {
    remote_varying(tbl, ids, cols)
  } else {
    unit <- group_ids(data, ids)
    n_units <- attr(unit, "n")
    bad <- Reduce(`|`, lapply(cols, function(col) {
      varying_units(data[[col]], unit, n_units)$varying
    }))
    hit <- which(bad[unit])
    out <- tibble::as_tibble(data)[hit, ]
    # Missing ids first, as data.table sorts them and the database query does
    o <- do.call(order, c(unname(as.list(out[ids])),
                          list(method = "radix", na.last = FALSE)))
    out[o, ]
  }

  label <- abort_msg %||% warn_msg
  what  <- paste0(toString(cols), " per ", toString(ids))
  report_check(
    violations  = rows,
    success_msg = success_msg %||%
      if (is.null(label)) paste0("Constant: ", what) else paste0("Check passed: ", label),
    fail_msg    = label %||% paste0("Varies within units: ", what),
    abort       = !is.null(abort_msg),
    log         = log,
    dump        = dump,
    key         = c(ids, cols)
  )
  invisible(data)
}
