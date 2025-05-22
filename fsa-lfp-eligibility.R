library(tidyverse)
library(magrittr)
library(quarto)


fsa_lfp_eligibility <-
  unzip(zipfile = "foia/2025-FSA-04690-F Bocinsky.zip",
        files = "LFP_Pasture_Grazing_Report.xlsx",
        exdir = tempdir()) %>%
  readxl::read_excel() %>%
  # Some start and end dates are NA — remove
  dplyr::filter(payment_type != "Not Eligible") %>%
  dplyr::rename_with(.fn = \(x){
    stringr::str_replace_all(x, "_", " ") %>%
      stringr::str_to_title() %>%
      stringr::str_replace("Fsa", "FSA")
  }) %>%
  dplyr::mutate(`State FSA Code` = stringr::str_pad(`State FSA Code`, width = 2, pad = "0"),
                `County FSA Code` = stringr::str_pad(`County FSA Code`, width = 3, pad = "0")) %>%
  tidyr::unite(col = "FSA Code",
               c(`State FSA Code`, `County FSA Code`), 
               sep = "", 
               remove = FALSE) %>%
  dplyr::arrange(`FSA Code`, `Pasture Type`, `Program Year`, `Disaster Type`) %>%
  dplyr::mutate(`Disaster Start Date` = 
                  as.integer(`Disaster Start Date`) %>%
                  as.Date(origin = "1899-12-30")
                ) %>%
  dplyr::distinct() %>%
  dplyr::select(`Program Year`,
                `State Name`,
                `County Name`,
                `State FSA Code`,
                `County FSA Code`,
                `FSA Code`,
                `Pasture Type`,
                `Disaster Type`,
                `Disaster Start Date`,
                `Qualifying Drought Event` = `Note Text`,
                `Payment Type`) %T>%
  readr::write_excel_csv("fsa-lfp-eligibility.csv")

## Render the interactive dashboard
quarto::quarto_render("fsa-lfp-eligibility.qmd")
