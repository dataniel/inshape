#' Check a panel, spells or a lookup table in one call
#'
#' The checks that register data of a common shape nearly always needs, run
#' together and reported in one overview: what passed, what failed with its
#' counts, and the call that gives the rows. Each returns `data`, so it can
#' sit in the middle of a pipeline.
#'
#' * `ensure_panel()`, one row per unit and period: the key is complete
#'   ([ensure_complete()]), unique ([ensure_unique()]) and has no gaps
#'   ([ensure_balanced()]).
#' * `ensure_spells()`, a start and an end per spell: the unit is complete,
#'   the spells are valid ([ensure_valid_spells()]) and do not overlap
#'   ([ensure_no_overlap()]), and, with `no_gaps = TRUE`, leave no gaps
#'   ([ensure_no_gaps()]).
#' * `ensure_lookup()`, a table to join on: its key is unique, so the join
#'   does not multiply rows, and every key of `data` is in it
#'   ([ensure_matched()]).
#'
#' All checks run, also after one has failed, so the overview shows every
#' problem at once. The exception is a check that assumes another: overlaps
#' and gaps mean nothing until the spells are valid, and are shown as not
#' checked until then.
#'
#' The choices are fixed where a register nearly always needs the same: a
#' panel may have units that enter late and leave early (`gaps_only = TRUE`,
#' unlike [ensure_balanced()]), and a spell without an end is ongoing. For
#' other choices, run the single checks; the overview names them.
#'
#' A failure is one condition of class `inshape_failure` for the whole
#' overview, and carries no rows. To get the rows of one check, wrap that
#' check in [violations()], as the overview shows.
#'
#' @inheritParams ensure_balanced
#' @param start,end Columns with the first and last period of each spell.
#' @param no_gaps If `TRUE`, the spells must also cover each unit from its
#'   first start to its last end, see [ensure_no_gaps()]. Default `FALSE`.
#' @param gaps_only If `TRUE` (default), a unit may enter late and leave
#'   early, but must not skip a period in between. If `FALSE`, every unit
#'   must be observed in every period.
#' @param reference The lookup table, for `ensure_lookup()`.
#' @param by Key columns, as in [ensure_matched()]: a character vector,
#'   optionally named to map names in `data` to names in `reference`.
#' @inheritParams checkpoints
#' @param warn_msg Message shown when a check fails and no `abort_msg` is
#'   set. Defaults to a line naming the data and how many checks failed.
#'
#' @return `data` invisibly, unchanged.
#'
#' @examples
#' panel <- data.frame(
#'   cpr  = c("a", "a", "a", "b", "b", "c"),
#'   year = c(2020, 2021, 2022, 2020, 2022, 2022)
#' )
#' # b lacks 2021
#' ensure_panel(panel, cpr, year)
#'
#' addresses <- data.frame(
#'   cpr   = c("a", "a", "b", "b"),
#'   start = as.Date(c("2020-01-01", "2021-01-01", "2020-01-01", "2020-06-01")),
#'   end   = as.Date(c("2020-12-31", NA,           "2020-06-30", "2021-12-31"))
#' )
#' # b has two addresses in June 2020
#' ensure_spells(addresses, cpr, start, end)
#'
#' codes <- data.frame(kom = c("955", "956", "956"), name = c("A", "B", "B"))
#' persons <- data.frame(cpr = c("a", "b"), kom = c("955", "957"))
#' # 956 is in the code list twice, and 957 not at all
#' ensure_lookup(persons, codes, by = "kom")
#'
#' @seealso [describe_panel()], [describe_spells()] and [describe_match()]
#'   to look at the same data without a rule, [checkpoints].
#'
#' @name ensure_panel
NULL

#' @rdname ensure_panel
#' @export
ensure_panel <- function(data, id, time,
                         periods     = NULL,
                         gaps_only   = TRUE,
                         success_msg = NULL,
                         warn_msg    = NULL,
                         abort_msg   = NULL) {
  tbl      <- check_table(data)
  ids      <- select_names(tbl, {{ id }})
  time_col <- select_names(tbl, {{ time }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(time_col) != 1) cli::cli_abort("{.arg time} must select exactly one column.")
  if (!rlang::is_bool(gaps_only)) cli::cli_abort("{.arg gaps_only} must be TRUE or FALSE.")
  name <- data_label(rlang::caller_arg(data))
  key  <- c(ids, time_col)
  args <- paste(code_name(key), collapse = ", ")
  balanced_args <- paste0(code_cols(ids), ", ", code_name(time_col),
                          if (!is.null(periods)) paste0(", periods = ", rlang::caller_arg(periods)),
                          if (gaps_only) ", gaps_only = TRUE")

  run_checks(
    paste0("Panel ", toString(ids), " by ", time_col),
    list(
      list(run  = function() ensure_complete(tbl, dplyr::all_of(key)),
           call = paste0("ensure_complete(", name, ", ", args, ")")),
      list(run  = function() ensure_unique(tbl, dplyr::all_of(key)),
           call = paste0("ensure_unique(", name, ", ", args, ")")),
      list(run  = function() ensure_balanced(tbl, dplyr::all_of(ids), dplyr::all_of(time_col),
                                             periods = periods, gaps_only = gaps_only),
           call = paste0("ensure_balanced(", name, ", ", balanced_args, ")"))
    ),
    success_msg, warn_msg, abort_msg
  )
  invisible(data)
}

#' @rdname ensure_panel
#' @export
ensure_spells <- function(data, id, start, end,
                          no_gaps     = FALSE,
                          success_msg = NULL,
                          warn_msg    = NULL,
                          abort_msg   = NULL) {
  tbl       <- check_table(data)
  ids       <- select_names(tbl, {{ id }})
  start_col <- select_names(tbl, {{ start }})
  end_col   <- select_names(tbl, {{ end }})
  if (length(ids) == 0) cli::cli_abort("{.arg id} must select at least one column.")
  if (length(start_col) != 1 || length(end_col) != 1) {
    cli::cli_abort("{.arg start} and {.arg end} must each select exactly one column.")
  }
  if (!rlang::is_bool(no_gaps)) cli::cli_abort("{.arg no_gaps} must be TRUE or FALSE.")
  name  <- data_label(rlang::caller_arg(data))
  span  <- paste0(code_name(start_col), ", ", code_name(end_col))
  whole <- paste0(name, ", ", code_cols(ids), ", ", span)

  checks <- list(
    list(run  = function() ensure_complete(tbl, dplyr::all_of(ids)),
         call = paste0("ensure_complete(", name, ", ", paste(code_name(ids), collapse = ", "), ")")),
    list(run  = function() ensure_valid_spells(tbl, dplyr::all_of(start_col), dplyr::all_of(end_col)),
         call = paste0("ensure_valid_spells(", name, ", ", span, ")")),
    list(run  = function() ensure_no_overlap(tbl, dplyr::all_of(ids), dplyr::all_of(start_col),
                                             dplyr::all_of(end_col)),
         call = paste0("ensure_no_overlap(", whole, ")"),
         label = paste0("Overlapping spells per ", toString(ids)),
         after = 2L)
  )
  if (no_gaps) {
    checks <- c(checks, list(list(
      run  = function() ensure_no_gaps(tbl, dplyr::all_of(ids), dplyr::all_of(start_col),
                                       dplyr::all_of(end_col)),
      call = paste0("ensure_no_gaps(", whole, ")"),
      label = paste0("Gaps between spells per ", toString(ids)),
      after = 2L)))
  }
  run_checks(paste0("Spells per ", toString(ids)), checks,
             success_msg, warn_msg, abort_msg)
  invisible(data)
}

#' @rdname ensure_panel
#' @export
ensure_lookup <- function(data, reference, by,
                          success_msg = NULL,
                          warn_msg    = NULL,
                          abort_msg   = NULL) {
  if (missing(by)) by <- NULL
  by_text  <- rlang::caller_arg(by)
  name     <- data_label(rlang::caller_arg(data))
  ref_name <- data_label(rlang::caller_arg(reference))
  if (identical(ref_name, "data")) ref_name <- "reference"
  tbl <- check_table(data)
  ref <- check_table(reference)
  by  <- match_by(by, tbl, ref)

  run_checks(
    paste0("Lookup on ", toString(names(by))),
    list(
      list(run  = function() ensure_unique(ref, dplyr::all_of(unname(by)),
                                           success_msg = paste0("Unique keys in ", ref_name, ": ",
                                                                toString(unname(by))),
                                           warn_msg = paste0("Duplicate keys in ", ref_name, ": ",
                                                             toString(unname(by)))),
           call = paste0("ensure_unique(", ref_name, ", ",
                         paste(code_name(unname(by)), collapse = ", "), ")")),
      list(run  = function() ensure_matched(tbl, ref, by = by),
           call = paste0("ensure_matched(", name, ", ", ref_name, ", by = ", by_text, ")"))
    ),
    success_msg, warn_msg, abort_msg
  )
  invisible(data)
}

# Runs `checks` and reports them in one overview. Each check is a list with
# `run`, a function calling one checkpoint; `call`, that call as the user
# would write it, for the overview to point to; and, for a check that
# assumes another, `after`, the index of that check, and `label`, what to
# call it when it is not run.
#
# The checkpoints' own alerts are muffled, and their failures caught: the
# overview takes their place. It carries no rows, only the calls that give
# them, so a wrapper with three failed checks does not hold three sets of
# personal data.
run_checks <- function(title, checks, success_msg, warn_msg, abort_msg,
                       call = rlang::caller_env()) {
  results <- vector("list", length(checks))
  for (i in seq_along(checks)) {
    chk <- checks[[i]]
    if (!is.null(chk$after) && !identical(results[[chk$after]]$status, "pass")) {
      results[[i]] <- list(status = "skip", text = chk$label)
      next
    }
    passed <- NULL
    failure <- tryCatch(
      withCallingHandlers(
        {
          chk$run()
          NULL
        },
        inshape_pass = function(cnd) passed <<- cnd$text,
        message = function(cnd) invokeRestart("muffleMessage")
      ),
      inshape_failure = function(cnd) cnd
    )
    results[[i]] <- if (is.null(failure)) {
      list(status = "pass", text = passed)
    } else {
      list(status = "fail",
           text = strsplit(conditionMessage(failure), "\n", fixed = TRUE)[[1]][1],
           counted = paste0(count(failure$n, "row"),
                            if (!is.null(failure$n_groups)) paste0(" in ", count(failure$n_groups, "group"))),
           summary = failure$summary,
           call = chk$call)
    }
  }

  status <- vapply(results, `[[`, character(1), "status")
  label  <- abort_msg %||% warn_msg
  if (all(status == "pass")) {
    success_msg <- success_msg %||%
      if (is.null(label)) paste0(title, ": ", count(length(checks), "check"), " passed")
      else paste0("Check passed: ", label)
    rlang::signal("", class = "inshape_pass", text = success_msg)
    cli::cli_alert_success("{success_msg}")
    return(invisible(TRUE))
  }

  failed <- results[status == "fail"]
  info <- cli::col_cyan(cli::symbol$info)
  lines <- c(
    label %||% paste0(title, ": ", length(failed), " of ", count(length(checks), "check"), " failed"),
    unlist(lapply(results, function(r) {
      switch(r$status,
        pass = paste0(cli::col_green(cli::symbol$tick), " ", r$text),
        fail = c(paste0(cli::col_red(cli::symbol$cross), " ", r$text, " (", r$counted, ")"),
                 if (length(r$summary)) paste0("  ", r$summary)),
        skip = paste0(cli::col_grey("-"), " Not checked until the spells are valid: ",
                      sub("^(.)", "\\L\\1", r$text, perl = TRUE))
      )
    })),
    paste0(info, " For the rows: violations(", vapply(failed, `[[`, character(1), "call"), ")")
  )

  signal <- if (is.null(abort_msg)) rlang::warn else rlang::abort
  signal(paste(lines, collapse = "\n"), class = c("inshape_overview", "inshape_failure"),
         violations = NULL, checks = vapply(failed, `[[`, character(1), "call"),
         call = call, use_cli_format = FALSE)
  invisible(FALSE)
}
