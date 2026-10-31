# Rundtur i lustrum med opdigtede registerdata
#
# Kør afsnit for afsnit (Ctrl+Enter i RStudio/Positron). Data er tilfældige,
# men fejlene er lagt ind med vilje, så hver funktion har noget at finde.
# Kommentaren over hvert kald siger, hvad du bør se.

# Indlæs pakken: installeret, ellers direkte fra mappen
if (requireNamespace("lustrum", quietly = TRUE)) {
  library(lustrum)
} else {
  pkgload::load_all("C:/Users/danie/projekter/strukt")
}
library(dplyr)
set.seed(2026)


# 1. Et befolkningspanel: én række pr. person og år -------------------------

n <- 2000
personer <- tibble(
  cpr       = sprintf("%06d-%04d", sample.int(311299, n), sample.int(9999, n)),
  koen      = sample(c("K", "M"), n, replace = TRUE),
  foedt     = as.Date("1940-01-01") + sample.int(25000, n, replace = TRUE),
  kommune   = sample(c("Kujalleq", "Sermersooq", "Qeqqata", "Avannaata", "Qeqertalik"),
                     n, replace = TRUE),
  foerste   = sample(2019:2023, n, replace = TRUE, prob = c(.8, .05, .05, .05, .05)),
  sidste    = pmax(foerste, sample(2019:2023, n, replace = TRUE, prob = c(.05, .05, .05, .05, .8)))
)

panel <- personer |>
  rowwise() |>
  reframe(cpr, koen, foedt, kommune, aar = foerste:sidste) |>
  mutate(indkomst = round(rlnorm(n(), log(250000), 0.6), -2))

# Fejlene, som et rigtigt udtræk kunne have dem:
# - 15 personer mangler et år midt i forløbet (huller)
huller <- panel |>
  filter(aar > 2019, aar < 2023) |>
  slice_sample(n = 15)
panel <- anti_join(panel, huller, by = c("cpr", "aar"))
# - 10 rækker er indlæst to gange (eksakte kopier)
panel <- bind_rows(panel, slice_sample(panel, n = 10))
# - 5 personer har to rækker samme år med forskellig indkomst (konflikter)
panel <- bind_rows(panel, slice_sample(panel, n = 5) |> mutate(indkomst = indkomst + 1000))
# - 8 personer skifter køn et enkelt år (typisk en rettelse kun i nogle år)
skift <- panel |> distinct(cpr) |> slice_sample(n = 8) |> pull(cpr)
panel <- panel |>
  mutate(koen = if_else(cpr %in% skift & aar == 2021,
                        if_else(koen == "K", "M", "K"), koen))
# - fødselsdato mangler i 30 rækker (ufuldstændigt, ikke modstridende)
panel$foedt[sample.int(nrow(panel), 30)] <- NA

panel


# 2. Se først: describe_*() dømmer ikke, de beskriver -----------------------

# Er cpr + år en nøgle? Du bør se 15 dublerede nøgler: 10 eksakte kopier
# (kan bare fjernes) og 5 konflikter, der er uenige i kolonnen indkomst.
describe_key(panel, cpr, aar)

# Panelets form: hvor mange er med hele vejen, hvem kommer til og går, hvor
# er hullerne, og hvilke deltagelsesmønstre er almindelige (som xtdescribe).
describe_panel(panel, cpr, aar)

# Tallene kan også bruges direkte
describe_panel(panel, cpr, aar)$by_period

# Hvilke kolonner varierer inden for en person? koen bør ligge næsten på
# nul (de 8 skift), foedt er konstant men delvist manglende, og indkomst
# og aar varierer for næsten alle.
describe_varying(panel, cpr)


# 3. Kræv så: ensure_*() er checkpoints ------------------------------------
#
# Hver advarer med de rækker, der bryder reglen, og returnerer data, så de
# kan stå i en pipeline. Med abort_msg stopper de i stedet.

# Nøglen er ikke unik: rækkerne vises med et dupid pr. gruppe
ensure_unique(panel, cpr, aar)

# Køn skal være konstant pr. person; en manglende værdi tæller ikke som et skift
ensure_constant(panel, cpr, koen, foedt)

# Ingen huller: at komme til eller forsvinde er fint, at springe et år over er ikke
ensure_balanced(panel, cpr, aar, gaps_only = TRUE)

# Helt balanceret (alle personer alle år) er sjældent sandt for en befolkning
ensure_balanced(panel, cpr, aar)

# I en pipeline med egne beskeder: første fejl stopper scriptet
ryddet <- panel |>
  distinct() |>                                        # fjern eksakte kopier
  slice_max(indkomst, n = 1, by = c(cpr, aar), with_ties = FALSE)  # en regel for konflikter

ryddet |>
  ensure_unique(cpr, aar, abort_msg = "Dublerede personår") |>
  ensure_balanced(cpr, aar, periods = 2019:2023, gaps_only = TRUE,
                  warn_msg = "Huller i befolkningspanelet") |>
  invisible()

# En fejl som betingelse: rækkerne kan gemmes i et planlagt job
fejl <- tryCatch(
  ensure_unique(panel, cpr, aar, abort_msg = "Dublerede personår"),
  lustrum_failure = function(e) e$violations
)
fejl


# 4. Forløb: én række pr. forløb med start og slut --------------------------

forloeb <- personer |>
  slice_head(n = 500) |>
  select(cpr) |>
  rowwise() |>
  reframe(cpr, nr = 1:sample(1:4, 1)) |>
  mutate(
    laengde = sample.int(300, n(), replace = TRUE),
    # pause 0: næste forløb starter dagen efter (en overførsel)
    pause   = sample(0:200, n(), replace = TRUE, prob = c(.2, rep(.8 / 200, 200)))
  ) |>
  group_by(cpr) |>
  mutate(start = as.Date("2019-01-01") + sample.int(1500, 1) +   # personens første start
                 cumsum(lag(laengde + pause, default = 0)),
         slut  = start + laengde - 1) |>
  ungroup() |>
  mutate(status = sample(c("ansat", "ledig", "uddannelse"), n(), replace = TRUE)) |>
  select(cpr, start, slut, status)

# Fejlene: overlap, et forløb inde i et andet, en dublet, et igangværende
# forløb, og et der slutter før det starter
forloeb <- bind_rows(
  forloeb,
  forloeb |> slice(3)  |> mutate(start = start + 10, slut = slut + 40),  # overlap
  forloeb |> slice(8)  |> mutate(start = start + 5, slut = start + 10),  # nested
  forloeb |> slice(12),                                                   # dublet
  forloeb |> slice(20) |> mutate(start = slut + 1, slut = NA),           # igangværende
  forloeb |> slice(25) |> mutate(slut = start - 3)                       # slut før start
)

# Hvordan hænger hver persons forløb sammen? Omkring en femtedel starter
# dagen efter det forrige slutter (adjacent): ofte samme forløb registreret
# to gange, som skal lægges sammen før man tæller forløb.
describe_spells(forloeb, cpr, start, slut)

# Kræv at forløb ikke overlapper: overlappende forløb deler et overlap_id.
# Det igangværende forløb (slut = NA) overlapper alt, der starter efter det.
ensure_no_overlap(forloeb, cpr, start, slut)


# 5. Fra forløb til panel ---------------------------------------------------

# Status primo og ultimo hvert år; primo er som standard ultimo året før
# (overlappene er ikke ryddet op, så den nævner, hvor den måtte vælge)
forloeb_ok <- forloeb |> filter(is.na(slut) | slut >= start) |> distinct()
aarspanel <- spells_to_panel(forloeb_ok, cpr, start, slut, status, from = 2019, to = 2023)
aarspanel |> filter(cpr == first(cpr[!is.na(ultimo)]))
aarspanel |> count(year, ultimo)

# Med status_is = "outcome" er status udfaldet af forløbet, fx bestået,
# og gælder fra slutdatoen til næste forløb starter
spells_to_panel(forloeb_ok, cpr, start, slut, status, from = 2019, to = 2023,
                status_is = "outcome") |>
  count(year, ultimo)

# Har du allerede panelet, så sæt status på det uden at ændre rækkerne
ryddet |>
  filter(cpr %in% forloeb_ok$cpr) |>
  add_spell_status(forloeb_ok, cpr, aar, start, slut, status)


# 6. Log og dump til uovervågede kørsler ------------------------------------

mappe <- file.path(tempdir(), "lustrum-demo")
options(
  lustrum.log  = file.path(mappe, "tjek.log"),
  lustrum.dump = file.path(mappe, "fejl")
)
suppressWarnings({
  ensure_unique(panel, cpr, aar, warn_msg = "Dublerede personår")
  ensure_constant(panel, cpr, koen, warn_msg = "Køn skifter")
  ensure_unique(ryddet, cpr, aar)
})
cat(readLines(file.path(mappe, "tjek.log")), sep = "\n")
list.files(file.path(mappe, "fejl"))
options(lustrum.log = NULL, lustrum.dump = NULL)


# 7. Samme tjek i DuckDB, uden at hente data ind i R ------------------------

if (requireNamespace("duckdb", quietly = TRUE) && requireNamespace("dbplyr", quietly = TRUE)) {
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "panel", panel)
  db <- tbl(con, "panel")

  # Kun antallet og de første rækker hentes; tabellen returneres uberørt
  ensure_unique(db, cpr, aar)
  ensure_balanced(db, cpr, aar, gaps_only = TRUE)
  ensure_constant(db, cpr, koen)

  DBI::dbDisconnect(con, shutdown = TRUE)
}


# 8. Hastighed på et register i fuld størrelse (valgfrit) -------------------
#
# Sæt stor <- TRUE for 25 mio. personår (5 mio. personer i 5 år). Kræver
# omkring 4 GB fri hukommelse. Andet tjek af samme cpr-kolonne genbruger
# de komprimerede id'er (options(lustrum.cache = FALSE) slår det fra).

stor <- FALSE
if (stor) {
  m <- 5e6
  cpr_stor <- sprintf("%010d", sample.int(1e9, m))
  register <- data.frame(cpr  = rep(cpr_stor, each = 5),
                         aar  = rep(2019:2023, m),
                         koen = rep(sample(c("K", "M"), m, TRUE), each = 5))
  print(system.time(ensure_unique(register, cpr, aar)))
  print(system.time(ensure_balanced(register, cpr, aar, gaps_only = TRUE)))
  print(system.time(describe_panel(register, cpr, aar)))
  print(system.time(ensure_constant(register, cpr, koen)))
  rm(register, cpr_stor)
}
