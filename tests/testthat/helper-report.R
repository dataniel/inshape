# A minimal checkpoint over report_check(), for testing the shared engine
# without the rule of any particular ensure_*() function
check_rows <- function(data, success_msg = "OK", warn_msg = "Bad rows",
                       abort_msg = NULL) {
  report_check(data, pass = "OK", fail = "Bad rows",
               success_msg, warn_msg, abort_msg)
  invisible(data)
}
