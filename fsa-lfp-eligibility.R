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
  dplyr::left_join(
    tigris::counties(cb = TRUE) %>%
      sf::st_drop_geometry() %>%
      dplyr::select(`FSA ST CODE` = STATEFP,
                    `FSA CNTY CODE` = COUNTYFP,
                    `County Name` = NAME)
  ) %>%
  dplyr::left_join(
    tigris::states(cb = TRUE) %>%
      sf::st_drop_geometry() %>%
      dplyr::select(`FSA ST CODE` = STATEFP,
                    `State Name` = NAME)
  ) %>%
  dplyr::select(
    `State` = `FSA ST CODE`,
    `County` = `FSA CNTY CODE`,
    `State Name`,
    `County Name`,
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
        State = stringr::str_pad(state_fsa_code, width = 2, pad = "0"),
        County = stringr::str_pad(county_fsa_code, width = 3, pad = "0"),
        `State Name` = state_name,
        `County Name` = county_name,
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
                    !(`County Name` %in% c("Kootenai, North Shoshone",
                                           "Benewah, South Shoshone")))
  ) %>%
  dplyr::select(
    `State`,
    `County`,
    `State Name`,
    `County Name`,
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
    `State`,
    `County`,
    `State Name`,
    `County Name`,
    `Program Year`,
    `Pasture Type`,
    `Disaster Type`,
    .keep_all = TRUE
  ) %>%
  dplyr::arrange(`Program Year`,
                 `State`,
                 `County`,
                 `State Name`,
                 `County Name`,
                 `Disaster Type`,
                 `Pasture Type`
                 ) %T>%
  readr::write_excel_csv("fsa-lfp-eligibility.csv")

## Render the interactive dashboard
quarto::quarto_render("fsa-lfp-eligibility.qmd")

## Render the readme
rmarkdown::render("README.Rmd")
