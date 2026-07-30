library(tidyverse)
library(magrittr)
library(quarto)
library(archive)
library(tigris)

source("R/s3-archive.R")
s3_preflight()

s3_bucket <- Sys.getenv("S3_BUCKET", unset = "sustainable-fsa")
s3_prefix <- Sys.getenv("S3_PREFIX", unset = "fsa-lfp-eligibility")

# The 2014 Census boundary files return accented names as latin1 bytes declared
# UTF-8, so "Doña Ana" arrives as "Do\xf1a Ana". Encoding() already reports UTF-8,
# so the declaration must be reset before re-encoding; iconv(from = "latin1") alone
# is a no-op.
repair_latin1 <- function(x) {
  Encoding(x) <- "latin1"
  enc2utf8(x)
}

# Census county names, current vintage plus 2014 for counties since retired or
# renamed. One row per FIPS key, so the join below can assert many-to-one.
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
      # 2014 vintage only; the current one is already valid UTF-8.
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
  # One name per FIPS key, preferring the current vintage.
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
      # (23002), and Fort Kent (23004). Only the first shares the county's code.
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
  # dated file's version of each determination. The key includes the FSA county:
  # FSA administers some Census counties as two offices, each with its own
  # determination, so a FIPS-only key drops one of every such pair.
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
    # many-to-one makes dplyr error if `census` ever carries more than one row per
    # FIPS key.
    relationship = "many-to-one"
  ) %>%
  dplyr::select(
    `FIPS State Code`,
    `FIPS County Code`,
    `FIPS State Name`,
    `FIPS County Name`,
    dplyr::everything()
  )

# Records whose FIPS county is absent from the Census vintages cannot be placed and
# are dropped.
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
  # Mirrored CSV and Parquet, identical records. CSV carries no types, so codes
  # like "01" read back as 1; Parquet keeps them character and dates as dates.
  readr::write_excel_csv("fsa-lfp-eligibility.csv") %T>%
  arrow::write_parquet(sink = "fsa-lfp-eligibility.parquet",
                       version = "latest",
                       compression = "zstd",
                       compression_level = 13,
                       use_dictionary = TRUE)


## ---------------------------------------------------------------------------
## Event grain
##
## The archive above is wide: one record per determination, carrying a column pair
## per drought tier. fsa-lfp-eligibility-reanalysis publishes the same information
## long — one row per qualifying drought event — so comparing the two means
## reshaping this one. This section publishes the reshape rather than leaving every
## consumer to rediscover it.
##
## Which date qualifies a tier is not uniform. D2, D3B and D4B are multi-week
## tiers and their END is the day the requirement is met; D3A and D4A trigger "at
## any time", have no END column at all (0 non-NA of 36,041 and 14,053), and are
## satisfied on their START. FSA's own `Date of Qualifying Drought` is the earliest
## of exactly those five dates in 22,222 of 22,222 records, which is what
## establishes the mapping.
##
## Do not pivot on the START columns: `D3B START DATE` is a copy of
## `D3A START DATE` in all 24,054 rows carrying both, and `D4B START DATE` of
## `D4A START DATE` in all 10,431, so a START-keyed pivot double-counts D3 and D4.
##
## Program years 2008-2011 came from a different FOIA response and carry no tier
## columns, no grazing dates and no `Maximum Eligible Payment Months`. Their tier
## survives only in `Note`, which does not distinguish the A and B sub-tiers — but
## `Payment Factor` does, because the 2008 Farm Bill ladder pays 2 for D3 "at any
## time" and 3 for D3 "for at least 4 weeks". There is no D4b tier in that era; the
## 5-payment D4-for-4-weeks tier arrives with the 2014 Farm Bill.
## ---------------------------------------------------------------------------

# The tier each event belongs to, and the date that satisfied it.
#
# Program year 2026 splits D2 in two — four consecutive weeks earns one payment,
# seven earns two — so a 2026 file needs a D2A/D2B pair where earlier years carry a
# single D2. Both are duration tiers, unlike the D3A/D3B and D4A/D4B pairs where
# only the B half is, so both are satisfied on their END.
#
# FSA has published no 2026 file yet, so those two column names are a projection of
# its own D3A/D3B naming rather than something observed. `any_of()` below reads them
# only once they appear, and `assert_empty()` refuses to publish if a 2026 file
# arrives shaped differently — an unrecognised tier must stop the run, not vanish.
event_dates <- c(
  D2       = "D2 END",
  D2a_2026 = "D2A END",
  D2b_2026 = "D2B END",
  D3a      = "D3A START DATE",
  D3b      = "D3B END",
  D4a      = "D4A START DATE",
  D4b      = "D4B END"
)

# Tier columns the events file deliberately does not read: the START of a duration
# tier, whose END is the satisfaction date, and the empty END of an "at any time"
# tier. Listed so the assertion below can tell a column we ignore on purpose from
# one FSA has newly introduced.
event_dates_unused <- c(
  "D2 START DATE", "D2A START DATE", "D2B START DATE",
  "D3A END", "D3B START DATE",
  "D4A END", "D4B START DATE"
)

# 2012 onward: one event per populated tier column.
events_tiers <-
  fsa_lfp_eligibility %>%
  dplyr::filter(`Program Year` >= 2012L) %>%
  dplyr::select(
    `FIPS State Code`, `FIPS County Code`, `FSA State Code`, `FSA County Code`,
    `Program Year`, `Pasture Type`,
    dplyr::any_of(event_dates),
    `Maximum Eligible Payment Months`, `Payment Factor`
  ) %>%
  tidyr::pivot_longer(
    dplyr::any_of(names(event_dates)),
    names_to = "Qualifying Drought Event",
    values_to = "Qualifying Date"
  ) %>%
  dplyr::filter(!is.na(`Qualifying Date`))

# 2008-2011: the tier comes from `Note`, disambiguated by `Payment Factor`. Rows
# noted "Eligible" are the fire determinations and carry no drought tier.
events_note <-
  fsa_lfp_eligibility %>%
  dplyr::filter(`Program Year` <= 2011L,
                `Note (FOIA 2025-FSA-04690-F Bocinsky)` %in% c("D2", "D3", "D4")) %>%
  dplyr::mutate(
    `Qualifying Drought Event` =
      dplyr::case_when(
        `Note (FOIA 2025-FSA-04690-F Bocinsky)` == "D2" ~ "D2",
        `Note (FOIA 2025-FSA-04690-F Bocinsky)` == "D3" &
          `Payment Factor` == 2L ~ "D3a",
        `Note (FOIA 2025-FSA-04690-F Bocinsky)` == "D3" &
          `Payment Factor` == 3L ~ "D3b",
        `Note (FOIA 2025-FSA-04690-F Bocinsky)` == "D4" ~ "D4a"
      ),
    # `Date of Qualifying Drought` is the only date reported for this era, and it
    # is what its name says: when the qualifying drought began. Checked against
    # the sustainable-fsa/fsa-lfp-eligibility-web archive, which does carry the
    # 2008-2011 tier dates, it equals a tier START on 5,893 of 6,613 shared
    # records and a tier END on none.
    #
    # For the "at any time" tiers that is exactly the satisfaction date -- D3A and
    # D4A are satisfied the day the drought reaches that class. For the duration
    # tiers it is not: D2 needs eight consecutive weeks and D3B four, so the
    # requirement is met 55-plus days later. Rather than record a start date in a
    # column that means "the date the tier was satisfied" everywhere else, leave it
    # unknown and say so. The web archive reports these directly; prefer it before
    # 2012.
    `Qualifying Date` =
      dplyr::if_else(`Qualifying Drought Event` %in% c("D3a", "D4a"),
                     `Date of Qualifying Drought`,
                     as.Date(NA))
  ) %>%
  dplyr::select(
    `FIPS State Code`, `FIPS County Code`, `FSA State Code`, `FSA County Code`,
    `Program Year`, `Pasture Type`,
    `Qualifying Drought Event`, `Qualifying Date`,
    `Maximum Eligible Payment Months`, `Payment Factor`
  )

fsa_lfp_eligibility_events <-
  dplyr::bind_rows(events_tiers, events_note) %>%
  dplyr::transmute(
    FIPS = stringr::str_c(`FIPS State Code`, `FIPS County Code`),
    `FSA County` = stringr::str_c(`FSA State Code`, `FSA County Code`),
    `Program Year`,
    `Pasture Type`,
    `Qualifying Drought Event`,
    `Qualifying Date`,
    # Derived from the ladder in force, not copied from FSA's record-level
    # `Drought Factor`: that column names the tier that set the award, so copying
    # it onto every event would overstate the lower ones. The derivation
    # reproduces it on all 29,893 records where FSA states it, and fills program
    # years 2022-2024, where FSA left it blank on all 14,203 tier-bearing records.
    # No `.default`: an event the ladder does not recognise is a defect, not a
    # non-qualifying event to drop, so it becomes NA here and the assertion below
    # stops the run. The eras are bounded at both ends for the same reason — an
    # open-ended `>= 2012` would quietly price a 2026 D2 on the 2014 Farm Bill
    # ladder instead of failing.
    `Drought Factor` =
      dplyr::case_when(
        # 2008 Farm Bill
        `Program Year` <= 2011L & `Qualifying Drought Event` == "D2"  ~ 1L,
        `Program Year` <= 2011L & `Qualifying Drought Event` == "D3a" ~ 2L,
        `Program Year` <= 2011L & `Qualifying Drought Event` %in%
          c("D3b", "D4a", "D4b") ~ 3L,

        # 2014 Farm Bill, from Program Year 2012: the ceiling rises from 3 to 5
        `Program Year` %in% 2012:2025 & `Qualifying Drought Event` == "D2"  ~ 1L,
        `Program Year` %in% 2012:2025 & `Qualifying Drought Event` == "D3a" ~ 3L,
        `Program Year` %in% 2012:2025 & `Qualifying Drought Event` %in%
          c("D3b", "D4a") ~ 4L,
        `Program Year` %in% 2012:2025 & `Qualifying Drought Event` == "D4b" ~ 5L,

        # From Program Year 2026: D2 splits at four and seven consecutive weeks,
        # reinstating a 2-payment tier. D3 and D4 are unchanged.
        `Program Year` >= 2026L & `Qualifying Drought Event` == "D2a_2026" ~ 1L,
        `Program Year` >= 2026L & `Qualifying Drought Event` == "D2b_2026" ~ 2L,
        `Program Year` >= 2026L & `Qualifying Drought Event` == "D3a"      ~ 3L,
        `Program Year` >= 2026L & `Qualifying Drought Event` %in%
          c("D3b", "D4a") ~ 4L,
        `Program Year` >= 2026L & `Qualifying Drought Event` == "D4b"      ~ 5L
      ),
    `Maximum Eligible Payment Months`,
    `Payment Factor`
  ) %>%
  dplyr::arrange(dplyr::desc(`Program Year`), FIPS, `FSA County`,
                 `Pasture Type`, `Qualifying Date`, `Qualifying Drought Event`)

# Fail with the count and a sample, so a CI log alone identifies the cause.
assert_empty <- function(offenders, what) {
  if (nrow(offenders) == 0L) {
    return(invisible(NULL))
  }
  stop("Validation failed — ", what, ": ", nrow(offenders), " record(s).\n",
       paste(
         utils::capture.output(print(utils::head(offenders, 10L), width = 200)),
         collapse = "\n"
       ),
       call. = FALSE)
}

# Both assertions exist to make the 2026 rule change impossible to publish through
# by accident. Unlike the qa_* tables below, which report what FSA reported, an
# unscored event or an unrecognised tier column means this script no longer
# describes the program, so the run stops before anything is written.

assert_empty(
  fsa_lfp_eligibility_events %>%
    dplyr::filter(is.na(`Drought Factor`)) %>%
    dplyr::distinct(`Program Year`, `Qualifying Drought Event`),
  "qualifying drought events the payment ladder does not score"
)

# A tier column FSA has introduced and this script neither reads nor knowingly
# ignores. Catches a 2026 file that names the split D2 tiers something other than
# D2A/D2B, or adds a tier we have not accounted for at all.
assert_empty(
  tibble::tibble(
    column = stringr::str_subset(
      names(fsa_lfp_eligibility),
      "^D[0-9][A-Z]? (START DATE|END)$"
    )
  ) %>%
    dplyr::filter(!(column %in% c(event_dates, event_dates_unused))),
  "drought tier columns the events projection does not account for"
)

# Mirrored CSV and Parquet, identical records. CSV carries no types, so codes
# like "01" read back as 1; Parquet keeps them character and dates as dates.
readr::write_excel_csv(fsa_lfp_eligibility_events,
                       "fsa-lfp-eligibility-events.csv")
arrow::write_parquet(fsa_lfp_eligibility_events,
                     sink = "fsa-lfp-eligibility-events.parquet",
                     version = "latest",
                     compression = "zstd",
                     compression_level = 13,
                     use_dictionary = TRUE)


## ---------------------------------------------------------------------------
## Cross-reference against FSA's own county definitions
##
## Reported, never enforced. FSA determines eligibility at county grain while
## fsa-counties-dd17 and dd22 describe office grain, so FSA names counties those
## archives do not define. Both vintages are read because FSA's codes change:
## 46113 (Shannon, SD) resolves only against dd17, 46102 only against dd22.
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

# Puerto Rico is reported at two grains: municipio level in 2025-FSA-04690,
# consolidated FSA offices in the later files.
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

# Census counties FSA administers as more than one office; a join on FIPS returns
# several rows for these.
qa_split_counties <-
  fsa_lfp_eligibility %>%
  dplyr::summarise(
    `FSA Counties` = dplyr::n_distinct(`FSA State Code`, `FSA County Code`),
    # Codes, not names: FSA spells the same code several ways ("E POTTAWATTAMIE",
    # "EAST POTTAWATTAMIE", "???").
    `FSA Codes` = paste(sort(unique(paste0(`FSA State Code`, `FSA County Code`))),
                        collapse = " "),
    Records = dplyr::n(),
    .by = c(`FIPS State Code`, `FIPS County Code`, `FIPS State Name`,
            `FIPS County Name`)
  ) %>%
  dplyr::filter(`FSA Counties` > 1L) %>%
  dplyr::arrange(dplyr::desc(`FSA Counties`), `FIPS State Code`,
                 `FIPS County Code`)

# Determinations that yield no event. The predicate is the complement of the two
# event paths above, era by era, so it cannot drift from them: a 2012-onward
# determination yields an event for each populated tier column, and a 2008-2011 one
# for its `Note` tier.
qa_no_event <-
  fsa_lfp_eligibility %>%
  dplyr::filter(
    (`Program Year` >= 2012L &
       dplyr::if_all(dplyr::any_of(unname(event_dates)), is.na)) |
      (`Program Year` <= 2011L &
         !(`Note (FOIA 2025-FSA-04690-F Bocinsky)` %in% c("D2", "D3", "D4")))
  ) %>%
  dplyr::count(`Program Year`, `Disaster Type`, name = "records") %>%
  dplyr::arrange(`Program Year`, `Disaster Type`)

# Events whose tier is known but whose date was never reported. Confined to
# 2008-2011, where `Date of Qualifying Drought` is the only date published.
qa_undated_events <-
  fsa_lfp_eligibility_events %>%
  dplyr::filter(is.na(`Qualifying Date`)) %>%
  dplyr::count(`Program Year`, `Qualifying Drought Event`, name = "events") %>%
  dplyr::arrange(`Program Year`, `Qualifying Drought Event`)

# Program years where FSA left `Drought Factor` blank on every record, so every
# event's factor in the events file is derived rather than transcribed.
qa_derived_factor <-
  fsa_lfp_eligibility %>%
  dplyr::filter(`Disaster Type` == "Drought") %>%
  dplyr::summarise(
    records = dplyr::n(),
    `Drought Factor stated` = sum(!is.na(`Drought Factor`)),
    .by = `Program Year`
  ) %>%
  dplyr::filter(`Drought Factor stated` == 0L) %>%
  dplyr::arrange(`Program Year`)

# Detail tables as indented CSV; a tibble's print wraps wide frames across
# several blocks.
qa_detail <- function(x) {
  if (nrow(x) == 0L) {
    return(character(0))
  }
  paste0("  ", strsplit(readr::format_csv(x), "\n", fixed = TRUE)[[1]])
}

qa_report <- c(
  "FSA LFP Eligibility archive — QA report",
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
  paste0("Events published: ", nrow(fsa_lfp_eligibility_events)),
  "  fsa-lfp-eligibility-events.csv holds the same determinations at event grain —",
  "  one row per qualifying drought tier, matching the shape of the",
  "  fsa-lfp-eligibility-reanalysis archive. It does not round-trip to the record",
  "  count above; the reconciliation is the two tables below.",
  "",
  "Everything below is reported, not enforced.",
  "",
  paste0("Determinations yielding no event: ", sum(qa_no_event$records)),
  "  A determination with no qualifying drought tier has nothing to reshape. Fire",
  "  determinations never carry one. The rest are drought determinations from the",
  "  2025-FSA-04690 response, which reports eligibility without the tier dates. 157",
  "  of those do name a tier in `Note`, but only for program years the tier columns",
  "  already cover, so the events file reads the columns and ignores the note.",
  qa_detail(qa_no_event),
  "",
  paste0("Events with no qualifying date: ", sum(qa_undated_events$events)),
  "  Kept, not dropped: the tier is known and the date is not. All are 2008-2011,",
  "  which carries no tier date columns -- only `Date of Qualifying Drought`, the",
  "  day the drought began. That is the satisfaction date for the at-any-time tiers",
  "  (D3a, D4a) and is used for them; for the duration tiers (D2 eight consecutive",
  "  weeks, D3b four) the requirement is met 55-plus days later, so no satisfaction",
  "  date can be recovered and none is asserted. The fsa-lfp-eligibility-web archive",
  "  reports these directly -- prefer it before 2012.",
  qa_detail(qa_undated_events),
  "",
  paste0("Program years whose event drought factors are wholly derived: ",
         nrow(qa_derived_factor)),
  "  FSA states `Drought Factor` on no record in these years, so the events file",
  "  derives every one from the tier and the ladder in force. The derivation",
  "  reproduces FSA's own value on all 29,893 records where FSA does state it, and",
  "  `Payment Factor` equals min(drought factor, Maximum Eligible Payment Months) on",
  "  all 44,096 records carrying both, so the ladder is not in doubt.",
  qa_detail(qa_derived_factor),
  "",
  "The 2008-2011 A/B sub-tier split assumes `Payment Factor` is uncapped:",
  "  Those years carry no tier columns, so the events file reads the tier from",
  "  `Note` and splits D3 on `Payment Factor` — 2 for D3 at any time, 3 for D3 over",
  "  at least 4 weeks. `Maximum Eligible Payment Months` and both grazing dates are",
  "  absent for the era, so the cap cannot be recomputed to check. No record shows",
  "  it binding: D2 is always 1, D4 always 3, and D3 is never 1.",
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
       key = paste0(s3_prefix, "/fsa-lfp-eligibility.parquet"),
       file = "fsa-lfp-eligibility.parquet",
       content_type = "application/vnd.apache.parquet")

s3_put(bucket = s3_bucket,
       key = paste0(s3_prefix, "/fsa-lfp-eligibility-events.csv"),
       file = "fsa-lfp-eligibility-events.csv",
       content_type = "text/csv")

s3_put(bucket = s3_bucket,
       key = paste0(s3_prefix, "/fsa-lfp-eligibility-events.parquet"),
       file = "fsa-lfp-eligibility-events.parquet",
       content_type = "application/vnd.apache.parquet")

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
    paste0("/", s3_prefix, "/fsa-lfp-eligibility.parquet"),
    paste0("/", s3_prefix, "/fsa-lfp-eligibility-events.csv"),
    paste0("/", s3_prefix, "/fsa-lfp-eligibility-events.parquet"),
    paste0("/", s3_prefix, "/qa-report.txt"),
    paste0("/", s3_prefix, "/_manifest.txt")
  )
)
