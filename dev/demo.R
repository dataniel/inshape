# Rundtur i inshape med opdigtede registerdata
#
# Kør afsnit for afsnit (Ctrl+Enter i RStudio/Positron). Data er tilfældige,
# men fejlene er lagt ind med vilje, så hver funktion har noget at finde.
# Kommentaren over hvert kald siger, hvad du bør se.

# Indlæs pakken: installeret, ellers direkte fra mappen
if (requireNamespace("inshape", quietly = TRUE)) {
  library(inshape)
} else {
  pkgload::load_all("C:/Users/danie/projekter/inshape")
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

# Mangler der værdier? 30 rækker mangler fødselsdato
ensure_complete(panel, cpr, foedt)

# Panelets tjek på én gang med én samlet oversigt. Fejlen bærer ingen
# rækker; violations() på den peger på de enkelte tjek.
ensure_panel(panel, cpr, aar)

# I en pipeline med egne beskeder: første fejl stopper scriptet
ryddet <- panel |>
  distinct() |>                                        # fjern eksakte kopier
  slice_max(indkomst, n = 1, by = c(cpr, aar), with_ties = FALSE)  # en regel for konflikter

ryddet |>
  ensure_unique(cpr, aar, abort_msg = "Dublerede personår") |>
  ensure_balanced(cpr, aar, periods = 2019:2023, gaps_only = TRUE,
                  warn_msg = "Huller i befolkningspanelet") |>
  invisible()

# Hullerne er der stadig efter oprydningen. fill_panel() indsætter de
# manglende personår med NA i de øvrige kolonner, og flag markerer dem.
udfyldt <- fill_panel(ryddet, cpr, aar, flag = "udfyldt")
udfyldt |> count(udfyldt)

# Alle rækkerne bag en fejl, til at se på i sessionen
fejl <- violations(ensure_unique(panel, cpr, aar))
fejl


# Ingen observationer efter død/udvandring eller før fødsel. Datoerne kommer
# typisk fra befolkningsregistret og joines på. Her dør/udvandrer dem, der
# forsvinder før 2023, i deres sidste år; 6 af dem har fået en række for
# meget, som når en død registreres efter udtrækket.
afgang <- personer |>
  filter(sidste < 2023) |>
  transmute(cpr, udgaaet = as.Date(paste0(sidste, "-06-30")))
efter_doed <- slice_sample(afgang, n = 6)
med_afgang <- ryddet |>
  bind_rows(semi_join(ryddet, efter_doed, by = "cpr") |>
              slice_max(aar, n = 1, by = cpr) |>
              mutate(aar = aar + 1L)) |>
  left_join(afgang, by = "cpr")

# Året for død tæller med (personen levede en del af det); året efter ikke
ensure_within(med_afgang, aar, from = foedt, to = udgaaet)


# Kommunekoder over tid: i 2021 får Qeqqata en ny kode, og to rækker har en
# tastefejl. describe_codes() viser hvornår hver kode findes;
# ensure_codes() kræver koder fra kodelisten.
koder <- c(Kujalleq = "955", Sermersooq = "956", Qeqqata = "957",
           Avannaata = "960", Qeqertalik = "961")
med_koder <- ryddet |>
  mutate(kode = unname(koder[kommune]),
         kode = if_else(kommune == "Qeqqata" & aar >= 2021, "959", kode))
med_koder$kode[c(10, 20)] <- "95"
describe_codes(med_koder, kode, aar)
ensure_codes(med_koder, kode, c(koder, "959"))

# Kodelisten som tabel: findes hver kode præcis én gang, og findes alle
# rækkernes koder i listen? De to tastefejl "95" gør ikke.
kodeliste <- tibble(kode = c(unname(koder), "959"),
                    navn = c(names(koder), "Qeqqata"))
ensure_lookup(med_koder, kodeliste, by = "kode")


# Stemmer mikrodata med den offentliggjorte tabel? Her er tabellen lavet ud
# fra data, men med 3 kvinder for meget i 2022.
offentliggjort <- ryddet |>
  count(tid = aar, koen) |>
  mutate(n = if_else(tid == 2022 & koen == "K", n + 3L, n))
ensure_reconciled(ryddet, offentliggjort, by = c(aar = "tid", "koen"))

# Befolkningsregnskab: bestand ultimo = året før + tilgang - afgang. I 2022
# er bestanden talt 40 for højt, så 2023 ser ud til at mangle 40.
regnskab <- tibble(
  aar         = 2019:2023,
  bestand     = c(56200, 56350, 56420, 56590, 56640),
  foedte      = c(780, 800, 760, 790, 770),
  indvandrede = c(2000, 2050, 2100, 2080, 2150),
  doede       = c(500, 520, 540, 510, 530),
  udvandrede  = c(2150, 2180, 2250, 2230, 2300)
)
ensure_stock_flow(regnskab, aar, bestand,
                  inflow = c(foedte, indvandrede), outflow = c(doede, udvandrede))


# 3b. Et nyt udtræk: hvad er ændret siden sidst? ----------------------------
#
# Et nyt udtræk af samme register: 20 personer er rettet i køn, 15 har fået
# rettet fødselsdato, 10 er forsvundet og 2023 har fået 5 nye personer.
gammelt <- ryddet
nyt <- ryddet |>
  mutate(koen = if_else(cpr %in% sample(unique(cpr), 20),
                        if_else(koen == "K", "M", "K"), koen),
         foedt = if_else(cpr %in% sample(unique(cpr), 15), foedt + 365, foedt)) |>
  filter(!cpr %in% sample(unique(cpr), 10)) |>
  bind_rows(tibble(cpr = sprintf("999999-%04d", 1:5), koen = "K",
                   foedt = as.Date("2023-03-01"), kommune = "Sermersooq",
                   aar = 2023L, indkomst = 0))
aendringer <- describe_changes(gammelt, nyt, cpr, aar)
aendringer
aendringer$changed        # personår med mindst én ændret kolonne

# Kan det nye udtræk kobles til personregistret? De 5 nye personer findes
# ikke i personer, så koblingen mister rækker.
describe_match(nyt, personer, by = "cpr")
ensure_matched(nyt, personer, by = "cpr")


# 3c. Status over tid: overgange og en rettelse ------------------------------
#
# Uddannelsesstatus pr. personår. 12 personer går fra afsluttet tilbage til
# ikke startet i 2023, som når et register mangler uddannelsen et år.
uddannelse <- ryddet |>
  select(cpr, aar) |>
  mutate(start = sample(2018:2024, 1), slut = start + sample(1:3, 1), .by = cpr) |>
  mutate(status = case_when(aar < start ~ "ikke startet",
                            aar < slut  ~ "i gang",
                            TRUE        ~ "afsluttet")) |>
  select(cpr, aar, status)
tilbage <- uddannelse |>
  filter(aar %in% 2022:2023, status == "afsluttet") |>
  count(cpr) |>
  filter(n == 2) |>
  slice_sample(n = 12) |>
  pull(cpr)
uddannelse <- uddannelse |>
  mutate(status = if_else(cpr %in% tilbage & aar == 2023, "ikke startet", status))

# Hvilke overgange findes, og hvor tit? afsluttet -> ikke startet bør stå ud
describe_transitions(uddannelse, cpr, aar, status)

# Kræv at afsluttet er en endestation, eller forbyd bestemte overgange.
# Her finder de to kald de samme 12 personer.
ensure_transitions(uddannelse, cpr, aar, status, final = "afsluttet")
ensure_transitions(uddannelse, cpr, aar, status,
                   forbid = c("afsluttet -> ikke startet", "i gang -> ikke startet"))

# Ret det: afsluttet bliver ved med at gælde. Resultatet kommer i en ny
# kolonne, status_carried, og funktionen melder hver ændring.
rettet <- carry_status(uddannelse, cpr, aar, status, final = "afsluttet")
rettet |> filter(status != status_carried)


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

# Er hvert forløb gyldigt i sig selv? Ét slutter før det starter; slut = NA
# er et igangværende forløb og er tilladt.
ensure_valid_spells(forloeb, start, slut)

# Hvordan hænger hver persons forløb sammen? Omkring en femtedel starter
# dagen efter det forrige slutter (adjacent): ofte samme forløb registreret
# to gange, som skal lægges sammen før man tæller forløb.
describe_spells(forloeb, cpr, start, slut)

# Læg overførslerne sammen: forløb, der overlapper eller starter dagen
# efter, bliver ét. n_spells tæller, hvor mange der blev lagt sammen.
samlet <- merge_spells(forloeb, cpr, start, slut)
samlet |> count(n_spells)

# Kun forløb med samme status, og med op til 14 dages pause imellem
merge_spells(forloeb, cpr, start, slut, by = status, max_gap = 14)

# Efter sammenlægningen er der ingen overførsler eller overlap tilbage
describe_spells(samlet, cpr, start, slut)$relations

# Kræv at forløb ikke overlapper: overlappende forløb deler et overlap_id.
# Det igangværende forløb (slut = NA) overlapper alt, der starter efter det.
ensure_no_overlap(forloeb, cpr, start, slut)

# Dækker forløbene personen uden pauser? Pauser er normale her, så tillad
# op til 30 dage; de længere pauser vises.
ensure_no_gaps(samlet, cpr, start, slut, max_gap = 30)

# Forløbenes tjek på én gang. Overlap tjekkes først, når forløbene er gyldige.
ensure_spells(forloeb, cpr, start, slut)


# 4b. Hændelser: én række pr. hændelse med en dato ---------------------------
#
# Indskrivning og eksamen. 6 tager eksamen før de er indskrevet, og 4 tager
# eksamen uden at være indskrevet.
indskrevne <- personer |>
  slice_head(n = 300) |>
  transmute(cpr, dato = as.Date("2020-08-15") + sample.int(700, n(), TRUE),
            haendelse = "indskrevet")
eksamener <- indskrevne |>
  mutate(dato = dato + sample(200:900, n(), TRUE), haendelse = "eksamen")
eksamener$dato[1:6] <- indskrevne$dato[1:6] - 30
haendelser <- bind_rows(indskrevne[-(7:10), ], eksamener) |> arrange(cpr, dato)

describe_events(haendelser, cpr, dato, haendelse)
ensure_sequence(haendelser, cpr, dato, haendelse,
                first = "indskrevet", then = "eksamen")


# 4c. Familier: grupper og henvisninger mellem rækker ------------------------
#
# Én række pr. person med familie, rolle og ægtefælle. Fejlene: 3 familier
# mangler referenceperson, 2 har to, og 4 partnere peger på en tilfældig
# person i stedet for referencepersonen.
familier <- personer |>
  slice_head(n = 1200) |>
  select(cpr) |>
  mutate(familie = sample.int(400, n(), TRUE)) |>
  arrange(familie) |>
  mutate(rolle = c("reference", "partner", rep("barn", n()))[seq_len(n())],
         .by = familie) |>
  mutate(aegtefaelle = case_when(
           rolle == "reference" ~ cpr[rolle == "partner"][1],
           rolle == "partner"   ~ cpr[rolle == "reference"][1]),
         .by = familie)
forkert <- sample(which(familier$rolle == "partner"), 4)
familier$aegtefaelle[forkert] <- sample(familier$cpr, 4)
fejlfam <- sample(unique(familier$familie[familier$rolle == "partner"]), 5)
familier <- familier |>
  mutate(rolle = case_when(
    familie %in% fejlfam[1:3] & rolle == "reference" ~ "barn",
    familie %in% fejlfam[4:5] & rolle == "partner"   ~ "reference",
    TRUE ~ rolle))

# Hvordan ser familierne ud: størrelser og antal pr. rolle
describe_groups(familier, familie, rolle)

# Præcis én referenceperson og højst én partner pr. familie
ensure_counts(familier, familie, rolle,
              limits = list(reference = 1, partner = c(0, 1)))

# Findes ægtefællen, hører de til samme familie, og peger ægtefællen tilbage?
ensure_references(familier, cpr, aegtefaelle, same = familie, mutual = TRUE)


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


# 6. Samme tjek i DuckDB, uden at hente data ind i R ------------------------

if (requireNamespace("duckdb", quietly = TRUE) && requireNamespace("dbplyr", quietly = TRUE)) {
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "panel", panel)
  db <- tbl(con, "panel")

  # Kun antallet og de første rækker hentes; tabellen returneres uberørt
  ensure_unique(db, cpr, aar)
  ensure_balanced(db, cpr, aar, gaps_only = TRUE)
  ensure_constant(db, cpr, koen)
  ensure_panel(db, cpr, aar)

  # Beskrivelserne regnes også i databasen; kun optællingerne hentes
  print(describe_panel(db, cpr, aar))
  print(describe_varying(db, cpr))

  DBI::dbDisconnect(con, shutdown = TRUE)
}


# 7. Hastighed på et register i fuld størrelse (valgfrit) -------------------
#
# Sæt stor <- TRUE for 25 mio. personår (5 mio. personer i 5 år). Kræver
# omkring 4 GB fri hukommelse.

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
