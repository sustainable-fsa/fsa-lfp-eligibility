library(tidyverse)
library(magrittr)

conus <- 
  tigris::counties(cb = TRUE, refresh = TRUE) %>%
  dplyr::filter(!(STUSPS %in% c("PR", "AK", "VI", "HI", "MP", "AS", "GU"))) %>%
  rmapshaper::ms_simplify() %>%
  sf::st_transform("EPSG:5070")

lfp_eligibility <-
  unzip("foia/2023-FSA-00937-F Bocinsky.zip", list = TRUE) %$%
  Name %>%
  purrr::map_dfr(
    ~readxl::read_excel(unzip("foia/2023-FSA-00937-F Bocinsky.zip", .x, 
                              exdir = tempdir()), 
                        col_types = "text")) %>%
  dplyr::select(-`...25`,
                -`...26`) %>%
  dplyr::mutate(dplyr::across(c(D2_START_DATE:D4B_END), 
                              lubridate::as_date),
                dplyr::across(c(START,END),
                              lubridate::as_date,
                              format = "mdy",
                              .names = "GROWING_SEASON_{.col}"),
                PROGRAM_YEAR = ifelse(is.na(PROGRAM_YEAR), `PROGRAM YEAR`, PROGRAM_YEAR),
                PROGRAM_YEAR = as.integer(PROGRAM_YEAR),
                PASTURE_TYPE = ifelse(is.na(PASTURE_TYPE), `PASTURE TYPE`, PASTURE_TYPE),
                FSA_CODE = ifelse(is.na(FSA_CODE), `FSA State/County CODE`, FSA_CODE),
                # FACTOR = ifelse(is.na(FACTOR), DROUGHT_FACTOR, FACTOR),
                FACTOR = ifelse(is.na(FACTOR), PAYMENT_FACTOR, FACTOR),
                FACTOR = ifelse(is.na(FACTOR), `Eligible Payment Months`, FACTOR),
                FACTOR = ifelse(is.na(FACTOR), `PAYMENT FACTOR`, FACTOR),
                FACTOR = factor(FACTOR,
                                levels = 0:5,
                                ordered = TRUE),
                FSA_STATE = ifelse(is.na(FSA_STATE), `FSA STATE`, FSA_STATE),
                FSA_COUNTY_NAME = ifelse(is.na(FSA_COUNTY_NAME), `FSA COUNTY NAME`, FSA_COUNTY_NAME),
                FSA_COUNTY_NAME = stringr::str_to_upper(FSA_COUNTY_NAME),
                GROWING_SEASON_START = ifelse(is.na(GROWING_SEASON_START), 
                                              lubridate::as_date(as.numeric(START), 
                                                                 origin = "1900-01-01"), 
                                              GROWING_SEASON_START) %>%
                  lubridate::as_date(),
                GROWING_SEASON_END = ifelse(is.na(GROWING_SEASON_END), 
                                            lubridate::as_date(as.numeric(END), 
                                                               origin = "1900-01-01"), 
                                            GROWING_SEASON_END) %>%
                  lubridate::as_date()
  )%>%
  dplyr::select(-`FSA State/County CODE`,
                -`PROGRAM YEAR`,
                -`PASTURE TYPE`,
                # -DROUGHT_FACTOR,
                -PAYMENT_FACTOR,
                -`Eligible Payment Months`,
                -`PAYMENT FACTOR`,
                -`FSA STATE`,
                -`FSA COUNTY NAME`,
                -FSA_ST_CODE,
                -FSA_CNTY_CODE,
                -START,
                -END
  ) %>%
  dplyr::select(PROGRAM_YEAR, 
                FSA_CODE, 
                FSA_STATE, 
                FSA_COUNTY_NAME,
                PASTURE_TYPE, 
                dplyr::everything()) %>%
  dplyr::mutate(FSA_CODE = ifelse(FSA_CODE == "12025", "12086", FSA_CODE), # "DADE" presumed to be Miami-Dade
                FSA_CODE = ifelse(FSA_CODE == "19156", "19155", FSA_CODE), # FSA split Pottawattamie, IA into E and W in some years. Re-joining.
                FSA_CODE = ifelse(FSA_CODE == "27120", "27119", FSA_CODE), # FSA split Polk, MN into E and W in some years. Re-joining.
                FSA_CODE = ifelse(FSA_CODE == "32035", "32023", FSA_CODE), # FSA split Nye, NV into E and W in some years. Re-joining.
                FSA_CODE = ifelse(FSA_CODE == "29193", "29186", FSA_CODE), # FSA mis-labeled Ste. Genevieve, MO in some years. Re-labeling.
                FSA_CODE = ifelse(FSA_CODE == "46113", "46102", FSA_CODE), # FSA mis-labeled Oglala Lakota, SD (Formerly Shannon, SD) in some years. Re-labeling.
                FSA_CODE = ifelse(FSA_CODE == "27112", "27111", FSA_CODE), # FSA mis-labeled Otter Tail, MN in some years. Re-labeling.
  ) %>%
  dplyr::filter(FSA_CODE != "27138") %>% # This seems to have been an error. No other crops have the same start date
  dplyr::mutate(
    FSA_CODE = stringr::str_pad(FSA_CODE, 5, pad = "0"),
    PASTURE_TYPE = 
      ifelse(PASTURE_TYPE == "SHRT SEASON SMALL GRAIN 1",
             "SHORT SEASON SMALL GRAINS",
             PASTURE_TYPE),
    PASTURE_TYPE = 
      ifelse(PASTURE_TYPE == "FULL SEASON IMPROVE MIXED",
             "FULL SEASON IMPROVED (MIXED)",
             PASTURE_TYPE),
    PASTURE_TYPE = 
      ifelse(PASTURE_TYPE == "SHORT SSN SPRING SML GRN",
             "SHORT SEASON SMALL GRAINS (SPRING)",
             PASTURE_TYPE),
    PASTURE_TYPE = 
      ifelse(PASTURE_TYPE == "SHRT SSN FALL_WTR SML GRN",
             "SHORT SEASON SMALL GRAINS (FALL–WINTER)",
             PASTURE_TYPE),
    PASTURE_TYPE = stringr::str_to_title(PASTURE_TYPE),
    FSA_COUNTY_NAME = stringr::str_to_title(FSA_COUNTY_NAME)
  ) %>%
  dplyr::arrange(PROGRAM_YEAR, FSA_CODE, PASTURE_TYPE) %T>%
  readr::write_csv("fsa-lfp-eligibility.csv")

dir.create("maps",
           showWarnings = FALSE)

lfp_eligibility_graphs <- 
  lfp_eligibility %>%
  dplyr::group_by(PROGRAM_YEAR, PASTURE_TYPE) %>%
  tidyr::nest() %>%
  dplyr::arrange(PROGRAM_YEAR, PASTURE_TYPE) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    graph = list(
      (
        dplyr::left_join(conus, data,
                         by = c("GEOID" = "FSA_CODE")) %>%
          ggplot2::ggplot() +
          geom_sf(aes(fill = FACTOR),
                  col = "white") +
          geom_sf(data = conus %>%
                    dplyr::group_by(STATEFP) %>%
                    dplyr::summarise(),
                  col = "white",
                  fill = NA,
                  linewidth = 0.5) +
          scale_fill_manual(values = c("1" = "#FFFF54",
                                       "2" = "#F3AE3D",
                                       "3" =  "#6D4E16",
                                       "4" = "#EA3323",
                                       "5" =  "#7316A2"),
                            drop = FALSE,
                            name = paste0("Eligible County Payment Months\n", PROGRAM_YEAR, ", ", PASTURE_TYPE),
                            guide = guide_legend(direction = "horizontal",
                                                 title.position = "top"),
                            na.value = "grey80") +
          theme_void(base_size = 24) +
          theme(legend.position = c(0.225,0.125),
                # legend.key.width = unit(0.1, "npc"),
                legend.title = element_text(size = 14),
                legend.text = element_text(size = 12),
                strip.text.x = element_text(margin = margin(b = 5)))
      ) %T>%
        ggsave(filename = paste0("maps/", PROGRAM_YEAR, "-", PASTURE_TYPE,".png"),
               device = png,
               width = 11,
               height = 8.5,
               bg = "white",
               dpi = 600)
    )
  )

unlink("fsa-lfp-eligibility.pdf")

cairo_pdf(filename = "fsa-lfp-eligibility.pdf",
          width = 10,
          height = 6.86,
          bg = "white",
          onefile = TRUE)

lfp_eligibility_graphs$graph

dev.off()
