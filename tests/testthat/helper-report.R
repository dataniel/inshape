# A minimal checkpoint over report_check(), for testing the shared engine
# without the rule of any particular ensure_*() function
check_rows <- function(data, success_msg = "OK", warn_msg = "Bad rows",
                       abort_msg = NULL,
                       log  = getOption("lustrum.log"),
                       dump = getOption("lustrum.dump")) {
  report_check(data, success_msg = success_msg,
               fail_msg = if (is.null(abort_msg)) warn_msg else abort_msg,
               abort = !is.null(abort_msg), log = log, dump = dump)
  invisible(data)
}
