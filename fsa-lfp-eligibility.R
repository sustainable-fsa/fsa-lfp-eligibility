library(tidyverse)
library(magrittr)
library(quarto)
library(archive)
library(tigris)

source("R/s3-archive.R")
s3_preflight()

s3_bucket <- Sys.getenv("S3_BUCKET", unset = "sustainable-fsa")
s3_prefix <- Sys.getenv("S3_PREFIX", unset = "fsa-lfp-eligibility")

# The 2014 Census cartographic boundary files return accented place names as raw
# latin1 bytes while declaring them UTF-8, so "Doña Ana" arrives as "Do\xf1a Ana".
# Because Encoding() already reports "UTF-8", iconv(from = "latin1") is a no-op —
# the declaration has to be reset before re-encoding.
#
# Left unrepaired, the two vintages contribute two spellings of the same county,
# `distinct()` keeps both, and the join below fans out: 29 duplicated records in
# Doña Ana NM, Comerío PR, and Mayagüez PR.
repair_latin1 <- function(x) {
  Encoding(x) <- "latin1"
  enc2utf8(x)
}

# Census county names, from the current vintage plus 2014 for counties since
# retired or renamed. Exactly one row per FIPS key, so the join below can assert
# many-to-one.
census <-
  dplyr::bind_rows(
    tigris::counties(cb = TRUE) %>%
      sf::st_drop_geometry() %>%
      dplyr::mutate(VINTAGE = 1L),
    tigris::counties(cb = TRUE, year = 2014) %>%
      sf::st_drop_geometry() %>%
      dplyr::left_join(
        tigris::states(cb = TRUE, year = 2014) %>%
          dplyr::transmute(STATEFP, STATE_NAME = NAME) %>%
          sf::st_drop_geometry()
      ) %>%
      # The 2014 vintage only — the current one is already correct UTF-8 and
      # re-encoding it would corrupt it.
      dplyr::mutate(
        dplyr::across(c(NAME, STATE_NAME), repair_latin1),
        VINTAGE = 2L
      )
  ) %>%
  dplyr::transmute(`FIPS State Code` = STATEFP,
                   `FIPS County Code` = COUNTYFP,
                   `FIPS County Name` = NAME,
                   `FIPS State Name` = STATE_NAME,
                   VINTAGE) %>%
  tibble::as_tibble() %>%
  dplyr::distinct() %>%
  # Guarantee one name per FIPS key, preferring the current vintage, so the join
  # stays many-to-one even if a future vintage introduces another spelling.
  dplyr::arrange(`FIPS State Code`, `FIPS County Code`, VINTAGE) %>%
  dplyr::distinct(`FIPS State Code`, `FIPS County Code`, .keep_all = TRUE) %>%
  dplyr::select(-VINTAGE)

## FOIA 2026-FSA-02433-F Bocinsky includes all of 2025
archive::archive_extract(
  archive = "foia/2026-FSA-02433-F Bocinsky.zip",
  dir = tempdir()
)

## FOIA 2025-FSA-08422-F Bocinsky includes 2012--July 2025
archive::archive_extract(
  archive = "foia/2025-FSA-08422-F Bocinsky.zip",
  dir = tempdir()
)

## FOIA 2025-FSA-04690-F Bocinsky includes earlier years, but with less detail
archive::archive_extract(
  archive = "foia/2025-FSA-04690-F Bocinsky.zip",
  dir = tempdir()
)

fsa_lfp_eligibility <-
  c(
    file.path(tempdir(),
              "2026-FSA-02433-F Bocinsky",
              "Final Data") %>%
      list.files(full.names = TRUE,
                 pattern = "xlsx"),
    file.path(tempdir(),
              "2025-FSA-08422-F Bocinsky",
              "Final Data") %>%
      list.files(full.names = TRUE,
                 pattern = "xlsx")
  ) %>%
  {
    tibble::tibble(
      file = ., 
      file_datestamp = stringr::str_extract(.,"\\d{8}") %>%
        lubridate::as_date()
    )
  } %>%
  dplyr::mutate(
    data = purrr::map(file, \(x){
      readxl::read_excel(x, 
                         col_types = "text") %>%
        rename_with(~ gsub("_", " ", .))
    }),
    file = stringr::str_remove(file, paste0(tempdir(), "/"))
  ) %>%
  tidyr::unnest(data) %>%
  dplyr::mutate(`FSA ST CODE` = ifelse(is.na(`FSA ST CODE`), stringr::str_trunc(`FSA STATE`, 2, side = "right", ellipsis = ""), `FSA ST CODE`),
                `FSA CNTY CODE` = ifelse(is.na(`FSA CNTY CODE`), stringr::str_trunc(`FSA State/County CODE`, 3, side = "left", ellipsis = ""), `FSA CNTY CODE`),
                `FSA CNTY CODE` = ifelse(is.na(`FSA CNTY CODE`), stringr::str_trunc(`FSA CODE`, 3, side = "left", ellipsis = ""), `FSA CNTY CODE`),
                `DROUGHT FACTOR` = ifelse(is.na(`DROUGHT FACTOR`), FACTOR, `DROUGHT FACTOR`),
                `PAYMENT FACTOR` = ifelse(is.na(`PAYMENT FACTOR`), `Eligible Payment Months`, `PAYMENT FACTOR`),
                `PAYMENT FACTOR` = ifelse(is.na(`PAYMENT FACTOR`), `LOWEST`, `PAYMENT FACTOR`)) %>%
  dplyr::select(
    file,
    file_datestamp,
    `FSA State Code` = `FSA ST CODE`,
    `FSA County Code` = `FSA CNTY CODE`,
    `FSA County Name` = `FSA COUNTY NAME`,
    `Program Year` = `PROGRAM YEAR`,
    `Pasture Type` = `PASTURE TYPE`,
    `D2 START DATE`:`D4B END`,
    `Date of Qualifying Drought` = `DATE OF QUALIFYING DROUGHT`,
    `Drought Factor` = `DROUGHT FACTOR`,
    `Grazing Period Start Date` = START,
    `Grazing Period End Date` = END,
    `Maximum Eligible Payment Months` = MONTHS,
    `Payment Factor` = `PAYMENT FACTOR`
  ) %>%
  dplyr::mutate(
    `Disaster Type` = "Drought",
    dplyr::across(`D2 START DATE`:`D4B END`, lubridate::as_date),
    `Grazing Period Start Date` =
      dplyr::case_when(
        stringr::str_detect(`Grazing Period Start Date`, "/") ~ lubridate::mdy(`Grazing Period Start Date`),
        .default = as.numeric(`Grazing Period Start Date`) %>%
          lubridate::as_date(origin = "1899-12-30")
      ),
    `Grazing Period End Date` =
      dplyr::case_when(
        stringr::str_detect(`Grazing Period End Date`, "/") ~ lubridate::mdy(`Grazing Period End Date`),
        .default = as.numeric(`Grazing Period End Date`) %>%
          lubridate::as_date(origin = "1899-12-30")
      ),
    `Date of Qualifying Drought` =
      dplyr::case_when(
        stringr::str_detect(`Date of Qualifying Drought`, "/") ~ lubridate::mdy(`Date of Qualifying Drought`),
        .default = as.numeric(`Date of Qualifying Drought`) %>%
          lubridate::as_date(origin = "1899-12-30")
      ),
    dplyr::across(
      c(`Program Year`, `Drought Factor`, `Maximum Eligible Payment Months`, `Payment Factor`),
      as.integer),
    `Pasture Type` = 
      `Pasture Type` %>%
      stringr::str_to_title() %>%
      factor() %>%
      forcats::fct_collapse(
        `Annual Crabgrass` = "Annual Crabgrass",
        `Annual Ryegrass` = "Annual Ryegrass",
        `Cool Season Improved Pasture` = "Cool Season Improved",
        `Forage Sorghum` = "Forage Sorghum",
        `Full Season Improved Mixed Pasture` = "Full Season Improve Mixed",
        `Full Season Improved Pasture` = "Full Season Improved",
        `Improved Pasture` = "Improved Pasture",
        `Long Season Small Grains` = "Long Season Small Grains",
        `Native Pasture` = "Native Pasture",
        `Rangeland` = "Rangeland",
        `Short Season Fall/Winter Small Grains` = "Shrt Ssn Fall_wtr Sml Grn",
        `Short Season Small Grains` = "Short Season Small Grains",
        `Short Season Small Grains (1)` = "Shrt Season Small Grain 1",
        `Short Season Spring Small Grains` = "Short Ssn Spring Sml Grn",
        `Small Grains` = "Small Grains",
        `Warm Season Improved Pasture` = "Warm Season Improved"
      ) %>%
      forcats::fct_expand(
        c(
          "Annual Crabgrass",
          "Annual Ryegrass",
          "Cool Season Improved Pasture",
          "Forage Sorghum",
          "Full Season Improve Mixed Pasture",
          "Full Season Improved Pasture",
          "Improved Pasture",
          "Long Season Small Grains",
          "Native Pasture",
          "Rangeland",
          "Short Season Fall/Winter Small Grains",
          "Short Season Small Grains",
          "Short Season Small Grains (1)",
          "Short Season Spring Small Grains",
          "Small Grains",
          "Warm Season Improved Pasture"
        )
      )
  ) %>%
  dplyr::bind_rows(
    
    readxl::read_excel(
      file.path(
        tempdir(),
        "2025-FSA-04690-F Bocinsky",
        "Final Data",
        "LFP_Pasture_Grazing_Report.xlsx"
      ),
      col_types = "text"
    ) %>%
      dplyr::mutate(
        file = file.path(
          "2025-FSA-04690-F Bocinsky",
          "Final Data",
          "LFP_Pasture_Grazing_Report.xlsx"
        ),
        `FSA State Code` = stringr::str_pad(state_fsa_code, width = 2, pad = "0"),
        `FSA County Code` = stringr::str_pad(county_fsa_code, width = 3, pad = "0"),
        `FSA County Name` = county_name,
        `Program Year` = as.integer(program_year),
        `Pasture Type` = pasture_type,
        `Disaster Type` = disaster_type,
        `Date of Qualifying Drought` =
          dplyr::case_when(
            stringr::str_detect(disaster_start_date, "/") ~ lubridate::mdy(disaster_start_date),
            .default = as.numeric(disaster_start_date) %>%
              lubridate::as_date(origin = "1899-12-30")
          ),
        `Payment Factor` = stringr::str_remove(payment_type, " Month") %>% 
          as.integer(),
        `Note (FOIA 2025-FSA-04690-F Bocinsky)` = note_text,
        .keep = "none"
      ) %>%
      dplyr::filter(`Note (FOIA 2025-FSA-04690-F Bocinsky)` != "Not Eligible",
                    !(`FSA County Name` %in% c("Kootenai, North Shoshone",
                                               "Benewah, South Shoshone")))
    
  ) %>%
  dplyr::mutate(
    # Recode weird FIPS codes
    `FIPS State Code` = dplyr::case_match(`FSA State Code`,
                                          "03" ~ "60", # American Samoa
                                          "14" ~ "66", # Guam
                                          "43" ~ "72", # Puerto Rico
                                          "52" ~ "78", # US Virgin Islands
                                          .default = `FSA State Code`
    ),
    `FIPS County Code` = dplyr::case_when(
      `FIPS State Code` == "66" & `FSA County Code` == "001" ~ "010", # Guam
      `FIPS State Code` == "78" & `FSA County Code` == "001" ~ "010", # St. Croix, USVI
      `FIPS State Code` == "78" & `FSA County Code` == "003" ~ "020", # St. John, USVI
      `FIPS State Code` == "78" & `FSA County Code` == "005" ~ "030", # St. Thomas, USVI
      `FIPS State Code` == "46" & `FSA County Code` == "113" & `Program Year` > 2015 ~ "102", # Shannon, SD to Oglala Lakota, SD
      `FIPS State Code` == "32" & `FSA County Code` == "035" ~ "023", # Nye, NV
      `FIPS State Code` == "29" & `FSA County Code` == "193" ~ "186", # Ste. Genevieve, Missouri
      `FIPS State Code` == "27" & `FSA County Code` == "138" ~ "137", # St. Louis, MN
      `FIPS State Code` == "27" & `FSA County Code` == "120" ~ "119", # Polk, MN
      `FIPS State Code` == "27" & `FSA County Code` == "112" ~ "111", # Otter Rail, MN
      `FIPS State Code` == "19" & `FSA County Code` == "156" ~ "155", # Pottawattamie, IA
      # FSA runs three offices over Aroostook County: Aroostook (23003), Houlton
      # (23002), and Fort Kent (23004). Only the first shares its code with the
      # county, so without these the other two carried FIPS county codes 002 and
      # 004, which Maine does not use, and were dropped for having no Census county.
      `FIPS State Code` == "23" & `FSA County Code` == "002" ~ "003", # Houlton, ME
      `FIPS State Code` == "23" & `FSA County Code` == "004" ~ "003", # Fort Kent, ME
      `FIPS State Code` == "12" & `FSA County Code` == "025" ~ "086", # Dade, FL to Miami-Dade, FL
      .default = `FSA County Code`
    ),
    `FSA County Name` = stringr::str_to_upper(`FSA County Name`)
  ) %>%
  dplyr::select(
    file,
    file_datestamp,
    `FIPS State Code`,
    `FIPS County Code`,
    `FSA State Code`,
    `FSA County Code`,
    `FSA County Name`,
    `Program Year`,
    `Pasture Type`,
    `Disaster Type`,
    `D2 START DATE`:`D4B END`,
    `Date of Qualifying Drought`,
    `Drought Factor`,
    `Grazing Period Start Date`,
    `Grazing Period End Date`,
    `Maximum Eligible Payment Months`,
    `Payment Factor`,
    `Note (FOIA 2025-FSA-04690-F Bocinsky)`
  ) %>%
  dplyr::arrange(`FSA State Code`,
                 `FSA County Code`,
                 dplyr::desc(`Program Year`),
                 dplyr::desc(file_datestamp),
                 `Pasture Type`,
                 `Disaster Type`
                 ) %>%
  # De-duplicate across the overlapping FOIA responses, keeping the most recently
  # dated file's version of each determination.
  #
  # The key includes the FSA county, not just the FIPS county it falls in. FSA
  # administers some counties as two offices and issues each its own eligibility
  # determination, so keying on FIPS alone discarded one of every such pair: the
  # west or south half of Pottawattamie IA, Nye NV, St. Louis MN, Polk MN, and
  # Otter Tail MN, 72 determinations in total. They are not redundant — of the
  # keys where both halves report, Pottawattamie disagrees on Payment Factor and
  # Polk and St. Louis on the qualifying drought date.
  dplyr::distinct(
    `FSA State Code`,
    `FSA County Code`,
    `FIPS State Code`,
    `FIPS County Code`,
    `Program Year`,
    `Pasture Type`,
    `Disaster Type`,
    .keep_all = TRUE
  ) %>%
  dplyr::arrange(dplyr::desc(`Program Year`),
                 `FIPS State Code`,
                 `FIPS County Code`,
                 `FSA County Name`,
                 `Disaster Type`,
                 `Pasture Type`
  ) %>%
  dplyr::left_join(
    census,
    by = c("FIPS State Code", "FIPS County Code"),
    # "many-to-one" is an assertion, not a hint: dplyr errors if `census` ever
    # carries more than one row per FIPS key, which is how duplicate records
    # reach the archive unnoticed.
    relationship = "many-to-one"
  ) %>%
  dplyr::select(
    `FIPS State Code`,
    `FIPS County Code`,
    `FIPS State Name`,
    `FIPS County Name`,
    dplyr::everything()
  )

# Records whose FIPS county is absent from the Census vintages above cannot be
# placed and are dropped. Report them rather than dropping silently: a mapping gap
# in the FSA-to-FIPS recoding shows up here and nowhere else.
unmapped <-
  fsa_lfp_eligibility %>%
  dplyr::filter(is.na(`FIPS County Name`)) %>%
  dplyr::count(`FIPS State Code`, `FIPS County Code`, `FSA State Code`,
               `FSA County Code`, `FSA County Name`, name = "records")

if (nrow(unmapped) > 0L) {
  warning(sum(unmapped$records), " record(s) across ", nrow(unmapped),
          " FSA county/ies have no Census county and are dropped:\n",
          paste(utils::capture.output(print(unmapped, n = Inf, width = 200)),
                collapse = "\n"),
          call. = FALSE)
}

fsa_lfp_eligibility <-
  fsa_lfp_eligibility %>%
  dplyr::filter(!is.na(`FIPS County Name`)) %T>%
  readr::write_excel_csv("fsa-lfp-eligibility.csv")


## ---------------------------------------------------------------------------
## Cross-reference against FSA's own county definitions
##
## Reported, never enforced. FSA issues LFP eligibility determinations at county
## grain, while fsa-counties-dd17 and dd22 describe its *office* grain — so FSA
## legitimately names counties those archives do not define. Puerto Rico is the
## clearest case: the 2025-FSA-04690 response reports at municipio level (Aibonito,
## Cayey, Cidra, …) where dd22 knows only the consolidated offices. FSA's codes also
## evolve, so both vintages are read: 46113 (Shannon, SD) resolves only against
## dd17 and 46102 (Oglala Lakota) only against dd22.
##
## A hard gate here would flag correct data as broken. The value is visibility.
## ---------------------------------------------------------------------------

fsa_counties <-
  purrr::map(
    c("dd17", "dd22"),
    \(vintage) arrow::read_parquet(
      paste0("https://data.sustainable-fsa.com/fsa-counties-", vintage,
             "/fsa-counties-", vintage, ".parquet"),
      col_select = c("FSA_ST", "FSA_STCOU")
    )
  ) %>%
  dplyr::bind_rows() %>%
  dplyr::transmute(
    `FSA State Code` = FSA_ST,
    `FSA County Code` = stringr::str_trunc(FSA_STCOU, 3, side = "left", ellipsis = "")
  ) %>%
  dplyr::distinct()

qa_unknown_to_fsa_counties <-
  fsa_lfp_eligibility %>%
  dplyr::count(`FSA State Code`, `FSA County Code`, `FSA County Name`,
               name = "records") %>%
  dplyr::anti_join(fsa_counties, by = c("FSA State Code", "FSA County Code")) %>%
  dplyr::arrange(`FSA State Code`, `FSA County Code`)

# FSA leaves the county name blank as "???" in some records.
qa_unnamed_counties <-
  fsa_lfp_eligibility %>%
  dplyr::filter(`FSA County Name` == "???") %>%
  dplyr::count(`FSA State Code`, `FSA County Code`, `Program Year`,
               name = "records")

# Puerto Rico is reported at two grains across the FOIA responses: municipio level
# in 2025-FSA-04690, consolidated FSA offices in the later files. Anyone
# aggregating Puerto Rico needs to know which years carry which.
qa_puerto_rico_grain <-
  fsa_lfp_eligibility %>%
  dplyr::filter(`FSA State Code` == "72") %>%
  dplyr::count(
    `Program Year`,
    grain = dplyr::if_else(stringr::str_detect(file, "04690"),
                           "municipio", "FSA office"),
    name = "records"
  ) %>%
  tidyr::pivot_wider(names_from = grain, values_from = records,
                     values_fill = 0) %>%
  dplyr::arrange(`Program Year`)

# Census counties FSA administers as more than one office. A consumer joining on
# FIPS receives several rows for these, so quantify it rather than leaving them to
# discover it.
qa_split_counties <-
  fsa_lfp_eligibility %>%
  dplyr::summarise(
    `FSA Counties` = dplyr::n_distinct(`FSA State Code`, `FSA County Code`),
    # Codes, not names: FSA spells the same code several ways across its files
    # ("E POTTAWATTAMIE", "EAST POTTAWATTAMIE", "???"), so names would misrepresent
    # how many distinct offices there are.
    `FSA Codes` = paste(sort(unique(paste0(`FSA State Code`, `FSA County Code`))),
                        collapse = " "),
    Records = dplyr::n(),
    .by = c(`FIPS State Code`, `FIPS County Code`, `FIPS State Name`,
            `FIPS County Name`)
  ) %>%
  dplyr::filter(`FSA Counties` > 1L) %>%
  dplyr::arrange(dplyr::desc(`FSA Counties`), `FIPS State Code`,
                 `FIPS County Code`)

# Render a detail table as indented CSV. A tibble's own print wraps wide frames
# across several blocks, which makes the report unreadable and ungreppable.
qa_detail <- function(x) {
  if (nrow(x) == 0L) {
    return(character(0))
  }
  paste0("  ", strsplit(readr::format_csv(x), "\n", fixed = TRUE)[[1]])
}

qa_report <- c(
  "FSA LFP Eligibility archive — QA report",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  "",
  "Grain: one record per FSA county, program year, pasture type, and disaster",
  "type. FSA administers some Census counties as several offices and determines",
  "eligibility for each separately, so a Census county may carry several records.",
  "",
  paste0("Records published: ", nrow(fsa_lfp_eligibility)),
  paste0("FSA counties: ", dplyr::n_distinct(fsa_lfp_eligibility$`FSA State Code`,
                                             fsa_lfp_eligibility$`FSA County Code`)),
  paste0("Census counties: ", dplyr::n_distinct(fsa_lfp_eligibility$`FIPS State Code`,
                                                fsa_lfp_eligibility$`FIPS County Code`)),
  paste0("Program years: ", paste(range(fsa_lfp_eligibility$`Program Year`),
                                  collapse = "-")),
  "",
  "Everything below is reported, not enforced.",
  "",
  paste0("FSA counties not defined in fsa-counties-dd17/dd22: ",
         nrow(qa_unknown_to_fsa_counties), " (",
         sum(qa_unknown_to_fsa_counties$records), " records)"),
  "  Expected, not an error. FSA determines eligibility at county grain while those",
  "  archives describe its office grain, so FSA names counties they do not define —",
  "  Puerto Rico municipios, Alaska boroughs, and counties administered from a",
  "  neighbouring office. FSA's codes also change: 46113 (Shannon, SD) resolves only",
  "  against dd17 and 46102 (Oglala Lakota) only against dd22.",
  qa_detail(qa_unknown_to_fsa_counties),
  "",
  paste0("Records with no FSA county name, reported as \"???\": ",
         sum(qa_unnamed_counties$records), " across ",
         nrow(dplyr::distinct(qa_unnamed_counties, `FSA State Code`,
                              `FSA County Code`)), " FSA counties"),
  qa_detail(qa_unnamed_counties),
  "",
  "Puerto Rico reporting grain by program year:",
  "  The 2025-FSA-04690 response reports at municipio level; the later files report",
  "  consolidated FSA offices. Anyone aggregating Puerto Rico needs to know which.",
  qa_detail(qa_puerto_rico_grain),
  "",
  paste0("Census counties carrying several FSA counties: ",
         nrow(qa_split_counties)),
  "  A join on FIPS returns several rows for these; decide how to combine them.",
  qa_detail(qa_split_counties)
)

writeLines(qa_report, "qa-report.txt")

message(paste(qa_report, collapse = "\n"))

## Render the interactive dashboard
quarto::quarto_render("fsa-lfp-eligibility.qmd")

## Render the readme
rmarkdown::render("README.Rmd")

## Publish the archive to S3 (dual-write alongside the git mirror)
s3_put(bucket = s3_bucket,
       key = paste0(s3_prefix, "/fsa-lfp-eligibility.csv"),
       file = "fsa-lfp-eligibility.csv",
       content_type = "text/csv")

s3_put(bucket = s3_bucket,
       key = paste0(s3_prefix, "/qa-report.txt"),
       file = "qa-report.txt",
       content_type = "text/plain")

s3_push(bucket = s3_bucket,
        prefix = paste0(s3_prefix, "/assets"),
        local_dir = "assets",
        delete = TRUE)

s3_push(bucket = s3_bucket,
        prefix = paste0(s3_prefix, "/foia"),
        local_dir = "foia",
        delete = TRUE)

s3_write_manifest(bucket = s3_bucket,
                  prefix = s3_prefix)

cf_invalidate(
  paths = c(
    paste0("/", s3_prefix, "/fsa-lfp-eligibility.csv"),
    paste0("/", s3_prefix, "/qa-report.txt"),
    paste0("/", s3_prefix, "/_manifest.txt")
  )
)
