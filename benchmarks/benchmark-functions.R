# Run: Rscript benchmarks/benchmark-functions.R
# Or select the number of persons:
#      Rscript benchmarks/benchmark-functions.R 200000
# Synthetic inputs only. Times every exported function on population-sized
# data shaped like a register, in memory. Nothing is kept between calls,
# so each call is a first look at the data. There is no baseline; the point is
# what a full-population check costs.
pkgload::load_all(quiet = TRUE)
options(cli.default_handler = function(...) invisible())
set.seed(42)

persons <- as.integer(commandArgs(trailingOnly = TRUE))
if (!length(persons)) persons <- 1000000L
years <- 2016:2020

# ---- Panel: one row per person-year, shuffled ---------------------------
# Most persons are present all five years; some enter or leave, as through
# birth, death and migration. A few errors are planted: 0.1% of persons
# skip a year, 0.05% of person-years are loaded twice, 0.01% of persons
# change sex in one year.
cpr   <- sprintf("%010d", sample.int(1e9, persons))
first <- sample(years, persons, TRUE, prob = c(.9, .025, .025, .025, .025))
last  <- pmax(first, sample(years, persons, TRUE, prob = c(.025, .025, .025, .025, .9)))
span  <- last - first + 1L
pid   <- rep(seq_len(persons), span)
year  <- sequence(span, from = first)
skip  <- which(span >= 3)[seq_len(persons / 1000)]
drop  <- match(skip, pid) + 1L                          # their second year
keep  <- setdiff(seq_along(pid), drop)
pid   <- pid[keep]; year <- year[keep]
twice <- sample.int(length(pid), length(pid) / 2000)
o     <- sample(c(seq_along(pid), twice))
pid   <- pid[o]; year <- year[o]

sex <- sample(c("K", "M"), persons, TRUE)
panel <- data.frame(
  cpr     = cpr[pid],
  year    = year,
  sex     = sex[pid],
  born    = as.Date("1930-01-01") + sample.int(32000, persons, TRUE)[pid],
  left    = as.Date(ifelse(last < 2020, paste0(last, "-06-30"), NA))[pid],
  kommune = sample(c("955", "956", "957", "960", "961"), persons, TRUE)[pid],
  income  = round(rlnorm(length(pid), log(250000), 0.6), -2)
)
flip <- which(pid %in% sample.int(persons, persons / 10000) & year == 2018)
panel$sex[flip] <- ifelse(panel$sex[flip] == "K", "M", "K")
rm(pid, year, o, keep)

# Two extracts of the same register, compared on a unique key (the copies
# loaded twice are the business of ensure_unique()): in the later one 1% of
# incomes are corrected and 0.1% of person-years are gone
old <- panel[!duplicated(data.table::as.data.table(panel[c("cpr", "year")])), ]
new <- old
fix <- sample.int(nrow(new), nrow(new) / 100)
new$income[fix] <- new$income[fix] + 100
new <- new[-sample.int(nrow(new), nrow(new) / 1000), ]

# ---- Spells: one row per spell, shuffled ---------------------------------
# One to four spells per person; a fifth start the day after the previous
# spell ends (a transfer), the rest after a pause. 0.1% overlap.
k      <- sample(1:4, persons, TRUE)
sid    <- rep(seq_len(persons), k)
len    <- sample.int(400, length(sid), TRUE)
pause  <- ifelse(runif(length(sid)) < .2, 0L, sample.int(200, length(sid), TRUE))
offset <- ave(len + pause, sid, FUN = function(x) cumsum(c(0, x[-length(x)])))
begin  <- as.Date("2015-01-01") + sample.int(1500, persons, TRUE)[sid] + offset
spells <- data.frame(
  cpr    = cpr[sid],
  start  = begin,
  end    = begin + len - 1L,
  status = sample(c("employed", "unemployed", "education"), length(sid), TRUE)
)
bad <- sample.int(nrow(spells), nrow(spells) / 1000)
spells$end[bad] <- spells$end[bad] + 500L
spells <- spells[sample.int(nrow(spells)), ]
rm(sid, len, pause, offset, begin, k)

# ---- Cases ----------------------------------------------------------------
codes <- c("955", "956", "957", "960", "961")
cases <- list(
  describe_key      = function() describe_key(panel, cpr, year),
  describe_panel    = function() describe_panel(panel, cpr, year),
  describe_varying  = function() describe_varying(panel, cpr),
  describe_codes    = function() describe_codes(panel, kommune, year),
  describe_changes  = function() describe_changes(old, new, cpr, year),
  describe_spells   = function() describe_spells(spells, cpr, start, end),
  ensure_unique     = function() ensure_unique(panel, cpr, year),
  ensure_balanced   = function() ensure_balanced(panel, cpr, year, gaps_only = TRUE),
  ensure_constant   = function() ensure_constant(panel, cpr, sex, born),
  ensure_within     = function() ensure_within(panel, year, from = born, to = left),
  ensure_codes      = function() ensure_codes(panel, kommune, codes),
  ensure_no_overlap = function() ensure_no_overlap(spells, cpr, start, end),
  merge_spells      = function() merge_spells(spells, cpr, start, end),
  spells_to_panel   = function() spells_to_panel(spells, cpr, start, end, status,
                                                 from = 2016, to = 2020),
  add_spell_status  = function() add_spell_status(panel, spells, cpr, year,
                                                  start, end, status)
)

rows <- list()
for (case in names(cases)) {
  f <- cases[[case]]
  n_in <- if (grepl("spell|overlap", case) && case != "add_spell_status") nrow(spells) else nrow(panel)
  times <- vapply(1:3, function(i) {
    gc()
    system.time(suppressWarnings(f()))[["elapsed"]]
  }, numeric(1))
  row <- data.frame(case = case, rows = n_in, seconds = median(times))
  rows[[length(rows) + 1L]] <- row
  print(row, row.names = FALSE)
  flush.console()
  write.csv(do.call(rbind, rows), "benchmarks/functions-results.csv", row.names = FALSE)
}
writeLines(c(sprintf("%d persons: %d person-years, %d spells.",
                     persons, nrow(panel), nrow(spells)),
             "Median of 3 repetitions.",
             paste("Threads:", inshape_threads()),
             capture.output(sessionInfo())), "benchmarks/functions-session.txt")
