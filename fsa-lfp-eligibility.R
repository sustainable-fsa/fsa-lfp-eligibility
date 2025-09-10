library(tidyverse)
library(magrittr)
library(quarto)
library(archive)
library(tigris)

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
  file.path(tempdir(),
            "2025-FSA-08422-F Bocinsky",
            "Final Data") %>%
  list.files(full.names = TRUE,
             pattern = "xlsx") %>%
  purrr::map(\(x){
    readxl::read_excel(x, 
                       col_types = "text") %>%
      rename_with(~ gsub("_", " ", .))
  }) %>%
  dplyr::bind_rows() %>%
  dplyr::mutate(`FSA ST CODE` = ifelse(is.na(`FSA ST CODE`), stringr::str_trunc(`FSA STATE`, 2, side = "right", ellipsis = ""), `FSA ST CODE`),
                `FSA CNTY CODE` = ifelse(is.na(`FSA CNTY CODE`), stringr::str_trunc(`FSA State/County CODE`, 3, side = "left", ellipsis = ""), `FSA CNTY CODE`),
                `FSA CNTY CODE` = ifelse(is.na(`FSA CNTY CODE`), stringr::str_trunc(`FSA CODE`, 3, side = "left", ellipsis = ""), `FSA CNTY CODE`),
                `DROUGHT FACTOR` = ifelse(is.na(`DROUGHT FACTOR`), FACTOR, `DROUGHT FACTOR`),
                `PAYMENT FACTOR` = ifelse(is.na(`PAYMENT FACTOR`), `Eligible Payment Months`, `PAYMENT FACTOR`),
                `PAYMENT FACTOR` = ifelse(is.na(`PAYMENT FACTOR`), `LOWEST`, `PAYMENT FACTOR`)) %>%
  dplyr::select(
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
      ifelse(stringr::str_detect(`Grazing Period Start Date`, "/"),
             lubridate::mdy(`Grazing Period Start Date`),
             as.Date(as.numeric(`Grazing Period Start Date`), origin = "1899-12-30")) %>%
      lubridate::as_date(),
    `Grazing Period End Date` =
      ifelse(stringr::str_detect(`Grazing Period End Date`, "/"),
             lubridate::mdy(`Grazing Period End Date`),
             as.Date(as.numeric(`Grazing Period End Date`), origin = "1899-12-30")) %>%
      lubridate::as_date(),
    `Date of Qualifying Drought` =
      ifelse(stringr::str_detect(`Date of Qualifying Drought`, "/"),
             lubridate::mdy(`Date of Qualifying Drought`),
             as.Date(as.numeric(`Date of Qualifying Drought`), origin = "1899-12-30")) %>%
      lubridate::as_date(),
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
        "LFP_Pasture_Grazing_Report.xlsx"
      ),
      col_types = "text"
    ) %>%
      dplyr::mutate(
        `FSA State Code` = stringr::str_pad(state_fsa_code, width = 2, pad = "0"),
        `FSA County Code` = stringr::str_pad(county_fsa_code, width = 3, pad = "0"),
        `FSA County Name` = county_name,
        `Program Year` = as.integer(program_year),
        `Pasture Type` = pasture_type,
        `Disaster Type` = disaster_type,
        `Date of Qualifying Drought` = ifelse(stringr::str_detect(disaster_start_date, "/"),
                                              lubridate::mdy(disaster_start_date),
                                              as.Date(as.numeric(disaster_start_date), origin = "1899-12-30")) %>%
          lubridate::as_date(),
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
      `FIPS State Code` == "12" & `FSA County Code` == "025" ~ "086", # Dade, FL to Miami-Dade, FL
      .default = `FSA County Code`
    ),
    `FSA County Name` = stringr::str_to_upper(`FSA County Name`)
  ) %>%
  dplyr::select(
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
  dplyr::distinct(
    `FIPS State Code`,
    `FIPS County Code`,
    `Program Year`,
    `Pasture Type`,
    `Disaster Type`,
    .keep_all = TRUE
  ) %>%
  dplyr::arrange(`Program Year`,
                 `FIPS State Code`,
                 `FIPS County Code`,
                 `FSA County Name`,
                 `Disaster Type`,
                 `Pasture Type`
                 ) %>%
  dplyr::left_join(
    dplyr::bind_rows(
      tigris::counties(cb = TRUE) %>%
        sf::st_drop_geometry(),
      tigris::counties(cb = TRUE, year = 2014) %>%
        sf::st_drop_geometry() %>%
        dplyr::left_join(
          tigris::states(cb = TRUE, year = 2014) %>%
            dplyr::transmute(STATEFP, STATE_NAME = NAME)
          ) %>%
        dplyr::arrange(STATEFP, COUNTYFP)
    ) %>%
      dplyr::transmute(`FIPS State Code` = STATEFP,
                       `FIPS County Code` = COUNTYFP,
                       `FIPS County Name` = NAME,
                       `FIPS State Name` = STATE_NAME) %>%
      tibble::as_tibble() %>%
      dplyr::distinct() %>%
      dplyr::arrange(`FIPS State Code`, `FIPS County Code`)
  ) %>%
  dplyr::select(
    `FIPS State Code`,
    `FIPS County Code`,
    `FIPS State Name`,
    `FIPS County Name`,
    dplyr::everything()
  ) %>%
  dplyr::filter(!is.na(`FIPS County Name`)) %T>%
  readr::write_excel_csv("fsa-lfp-eligibility.csv")

## Render the interactive dashboard
quarto::quarto_render("fsa-lfp-eligibility.qmd")

## Render the readme
rmarkdown::render("README.Rmd")
