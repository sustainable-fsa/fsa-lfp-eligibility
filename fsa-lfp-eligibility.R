library(tidyverse)
library(magrittr)

conus <- 
  tigris::counties(cb = TRUE, refresh = TRUE) %>%
  dplyr::filter(!(STUSPS %in% c("PR", "AK", "VI", "HI", "MP", "AS", "GU")))

conus %<>%
  rmapshaper::ms_simplify() %>%
  sf::st_transform("EPSG:5070")

lfp_eligibility <-
  list.files("foia/2023-FSA-00937-F Bocinsky/",
           full.names = TRUE) %>%
  purrr::map_dfr(readxl::read_excel,
                 col_types = "text") %>%
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
                PASTURE_CODE, 
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
  dplyr::mutate(FSA_CODE = stringr::str_pad(FSA_CODE, 5, pad = "0"))

lfp_eligibility %>%
  dplyr::arrange(PROGRAM_YEAR, FSA_CODE, PASTURE_TYPE) %>%
  readr::write_csv("fsa-lfp-eligibility.csv")

dir.create("figures",
           showWarnings = FALSE)

lfp_eligibility_graphs <- 
  lfp_eligibility %>%
  dplyr::group_by(PROGRAM_YEAR, PASTURE_TYPE) %>%
  tidyr::nest() %>%
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
                        name = paste0("Eligible County Payment Months\n", PROGRAM_YEAR, ", ", stringr::str_to_title(PASTURE_TYPE)),
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
      ggsave(filename = paste0("figures/", PROGRAM_YEAR, "-", stringr::str_to_title(PASTURE_TYPE),".png"),
             device = png,
             width = 10,
             height = 6.86,
             bg = "white",
             dpi = 600)
    )
  )

lfp_eligibility %>%
  dplyr::select(PROGRAM_YEAR, 
                FSA_STATE,
                FSA_CODE,
                PASTURE_TYPE, 
                GROWING_SEASON_START, 
                GROWING_SEASON_END) %>%
  dplyr::filter(!(lubridate::day(GROWING_SEASON_START) %in% c(1,15))) %>%
  dplyr::mutate(GROWING_SEASON_START = format(GROWING_SEASON_START, "%m-%d"),
                GROWING_SEASON_END = format(GROWING_SEASON_END, "%m-%d")) %>%
  dplyr::arrange(
    PROGRAM_YEAR,
    FSA_STATE,
    FSA_CODE,
                 PASTURE_TYPE
    ) %>%

  dplyr::group_by(FSA_STATE, PASTURE_TYPE, GROWING_SEASON_START, GROWING_SEASON_END) %>%
  dplyr::summarise(PROGRAM_YEAR = paste(sort(unique(PROGRAM_YEAR)), collapse = ", ")) %>%
  readr::write_csv("lfp_crop_start_dates_weird.csv")
  dplyr::distinct() %>%
  dplyr::arrange(
    PROGRAM_YEAR,
    FSA_STATE,
    PASTURE_TYPE
  )

  dplyr::distinct()
  dplyr::group_by(PROGRAM_YEAR, FSA_CODE, FACTOR) %>%
  dplyr::summarise(PASTURE_TYPE = paste(PASTURE_TYPE, collapse = ", "))





lfp_eligibility %>%
  dplyr::select(PROGRAM_YEAR, PASTURE_TYPE, FSA_CODE, FACTOR) %>%
  dplyr::group_by(PROGRAM_YEAR, FSA_CODE, FACTOR) %>%
  dplyr::summarise(PASTURE_TYPE = paste(PASTURE_TYPE, collapse = ", "))
  dplyr::filter(PROGRAM_YEAR == 2012,
                PASTURE_TYPE == "LONG SEASON SMALL GRAINS") %>%
  
  
  
  dplyr::left_join(conus, .,
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
                    name = paste0("Eligible County Payment Months\n2012, LONG SEASON SMALL GRAINS"),
                    guide = guide_legend(direction = "horizontal",
                                         title.position = "top"),
                    na.value = "grey80") +
  theme_void(base_size = 24) +
  theme(legend.position = c(0.225,0.125),
        # legend.key.width = unit(0.1, "npc"),
        legend.title = element_text(size = 16),
        legend.text = element_text(size = 14),
        strip.text.x = element_text(margin = margin(b = 5)))

ggsave(filename = "figures/2012-LONG SEASON SMALL GRAINS.png",
       device = png,
       width = 10,
       height = 6.86,
       bg = "white",
       dpi = 600)

