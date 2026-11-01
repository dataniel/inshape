# Run: Rscript benchmarks/benchmark-checkpoints.R
# Or select the number of persons (five years each):
#      Rscript benchmarks/benchmark-checkpoints.R 200000
# Synthetic inputs only. Compares the key-based checkpoints before the
# speed-up (baseline-checkpoints.R, a frozen reference) with the current
# code, in memory.
pkgload::load_all(quiet = TRUE)
baseline <- new.env(parent = asNamespace("inshape"))
sys.source("benchmarks/baseline-checkpoints.R", baseline)
# The frozen code predates the ensure_ names
for (nm in c("unique", "balanced", "no_overlap")) {
  baseline[[paste0("ensure_", nm)]] <- baseline[[paste0("expect_", nm)]]
}
options(cli.default_handler = function(...) invisible())
set.seed(42)

persons <- as.integer(commandArgs(trailingOnly = TRUE))
if (!length(persons)) persons <- 1000000L
years <- 2016:2020
n <- persons * length(years)

# Shuffled, as register extracts rarely arrive sorted. Ten numeric columns
# make the rows as wide as a typical extract.
o <- sample.int(n)
df <- data.frame(
  cpr  = rep(sprintf("%010d", seq_len(persons)), each = length(years))[o],
  year = rep(years, persons)[o]
)
for (i in 1:10) df[[paste0("x", i)]] <- runif(n)
# Parse the five dates once: as.Date() on millions of strings is slow
df$start <- as.Date(paste0(years, "-01-01"))[match(df$year, years)]
df$end   <- as.Date(paste0(years, "-12-31"))[match(df$year, years)]
# The variants are built per case and dropped after it, which keeps the
# peak memory near two copies of the data. Built column by column, since
# subsetting rows of a large data.frame with `[` is slow.
rows_of <- function(i) tibble::as_tibble(lapply(df, `[`, i))
inputs <- list(
  df   = function() df,
  dup  = function() rows_of(c(seq_len(n), sample.int(n, 1e4))),  # 10,000 duplicated keys
  gaps = function() rows_of(-sample.int(n, 1e4))                 # 10,000 missing person-years
)

violations <- function(expr) {
  cnd <- rlang::catch_cnd(expr, classes = "inshape_failure")
  if (is.null(cnd)) return(NULL)
  tibble::as_tibble(cnd$violations)
}
# dupid now numbers groups by first appearance; compare the grouping itself
same <- function(a, b) {
  if ("dupid" %in% names(a)) {
    a$dupid <- match(a$dupid, unique(a$dupid))
    b$dupid <- match(b$dupid, unique(b$dupid))
  }
  isTRUE(all.equal(a, b))
}

cases <- list(
  unique_pass     = list(function(api, x) api$ensure_unique(x, cpr, year), "df"),
  unique_10k_dups = list(function(api, x) api$ensure_unique(x, cpr, year), "dup"),
  balanced_10k    = list(function(api, x) api$ensure_balanced(x, cpr, year), "gaps"),
  gaps_only_10k   = list(function(api, x) api$ensure_balanced(x, cpr, year, gaps_only = TRUE), "gaps"),
  no_overlap_pass = list(function(api, x) api$ensure_no_overlap(x, cpr, start, end), "df")
)

rows <- list()
current <- asNamespace("inshape")
for (case in names(cases)) {
  f <- cases[[case]][[1]]
  x <- inputs[[cases[[case]][[2]]]]()
  stopifnot(same(violations(f(baseline, x)), violations(f(current, x))))

  # Cold: the content cache of dense ids is off, so every repetition
  # groups the key from scratch, as the first check on new data does
  options(inshape.cache = FALSE)
  times <- matrix(NA_real_, 3L, 2L)
  for (rep in 1:3) {
    for (impl in if (rep %% 2) 1:2 else 2:1) {
      gc()
      api <- if (impl == 1) baseline else current
      times[rep, impl] <- system.time(suppressWarnings(f(api, x)))[["elapsed"]]
    }
  }
  # Warm: a later check on the same, unchanged columns
  options(inshape.cache = TRUE)
  suppressWarnings(f(current, x))
  warm <- vapply(1:3, function(i) {
    gc()
    system.time(suppressWarnings(f(current, x)))[["elapsed"]]
  }, numeric(1))
  options(inshape.cache = FALSE)

  row <- data.frame(rows = nrow(x), case = case,
                    before = median(times[, 1]), after = median(times[, 2]),
                    warm = median(warm))
  row$speedup <- row$before / row$after
  rows[[length(rows) + 1L]] <- row
  print(row, row.names = FALSE)
  flush.console()
  write.csv(do.call(rbind, rows), "benchmarks/checkpoints-results.csv", row.names = FALSE)
  rm(x)
}
writeLines(c("Median of 3 repetitions in alternating order, cache off;",
             "warm = median of 3 with the content cache filled.",
             "Violations checked against the frozen snapshot before timing.",
             capture.output(sessionInfo())), "benchmarks/checkpoints-session.txt")
