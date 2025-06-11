
[![GitHub
Release](https://img.shields.io/github/v/release/sustainable-fsa/fsa-lfp-eligibility?label=GitHub%20Release&color=%239c27b0)](https://github.com/sustainable-fsa/fsa-lfp-eligibility)
[![DOI](https://zenodo.org/badge/587852382.svg)](https://zenodo.org/badge/latestdoi/587852382)

# FSA Annual County Eligibility Data from the Livestock Forage Disaster Program, 2008–2024

This repository is an archive of the annual county-level eligibility
data for the [Livestock Forage Disaster Program
(LFP)](https://www.fsa.usda.gov/resources/programs/livestock-forage-disaster-program-lfp).

The data in this repository were acquired via FOIA request
**2025-FSA-04690-F** by R. Kyle Bocinsky (Montana Climate Office) and
fulfilled on April 15, 2025. This replaces a previously filed and
fulfilled FOIA response covering 2012–2022 (2023-FSA-00937-F). Both FOIA
responses, including the original Excel workbooks, are archived in the
[`foia`](./foia) directory.

## 🗂️ Contents

- [`foia/2025-FSA-04690-F Bocinsky.zip`](./foia/2025-FSA-04690-F%20Bocinsky.zip)
  — FOIA data and correspondence
- [`foia/2023-FSA-00937-F Bocinsky.zip`](./foia/2023-FSA-00937-F%20Bocinsky.zip)
  — previous FOIA data and correspondence (archived)
- [`fsa-lfp-eligibility.csv`](./fsa-lfp-eligibility.csv) — cleaned and
  consolidated data
- [`fsa-lfp-eligibility.R`](./fsa-lfp-eligibility.R) — processing script
- [`fsa-lfp-eligibility.qmd`](./fsa-lfp-eligibility.qmd) — Quarto
  dashboard source
- [`fsa-lfp-eligibility.html`](./fsa-lfp-eligibility.html) — interactive
  summary dashboard

------------------------------------------------------------------------

## 📥 Input Data: FOIA Excel Workbook

The FOIA response contains LFP eligibility data from **2008 through
2024** for each pasture type, county, and program year.

### Key Variables

program_year state_fsa_code county_fsa_code state_name county_name
disaster_type payment_type note_text disaster_start_date pasture_type

| Variable Name       | Description                                     |
|---------------------|-------------------------------------------------|
| program_year        | Year the data applies to                        |
| state_fsa_code      | FSA-assigned state code (not always ANSI/FIPS)  |
| county_fsa_code     | FSA-assigned county code (not always ANSI/FIPS) |
| state_name          | U.S. state                                      |
| county_name         | County or county-equivalent name                |
| disaster_type       | Type of disaster (e.g., Drought, Fire)          |
| payment_type        | Number of Monthly Payments                      |
| note_text           | Qualifying drought status                       |
| disaster_start_date | Start date of qualifying disaster               |
| pasture_type        | Pasture classification (e.g., Native, Improved) |

------------------------------------------------------------------------

## 🧹 Processing Workflow

The processing script
[`fsa-lfp-eligibility.R`](./fsa-lfp-eligibility.R):

1.  **Unzips and reads** the Excel workbook.
2.  **Filters records** with missing dates.
3.  **Constructs an `FSA Code`** by concatenating state and county FSA
    codes.
4.  **Cleans and standardizes** pasture type names.
5.  **Removes invalid or duplicate entries**.
6.  **Exports** the cleaned data to
    [`fsa-lfp-eligibility.csv`](./fsa-lfp-eligibility.csv).
7.  **Renders** an interactive Quarto dashboard.

------------------------------------------------------------------------

## 📤 Output Data: Cleaned CSV

The file [`fsa-lfp-eligibility.csv`](./fsa-lfp-eligibility.csv) is a
tidy dataset for analysis and visualization.

### Variables in Output

| Variable Name | Description |
|----|----|
| `Program Year` | Year the data applies to |
| `State Name` | U.S. state |
| `County Name` | County or county-equivalent name |
| `State FSA Code` | FSA state code (not always ANSI/FIPS) |
| `County FSA Code` | FSA county code (not always ANSI/FIPS) |
| `FSA Code` | Combined `State FSA Code` + `County FSA Code` |
| `Pasture Grazing Type` | Pasture classification (e.g., Native, Improved) |
| `Disaster Type` | Type of disaster (e.g., Drought, Fire) |
| `Disaster Start Date` | Start date of qualifying disaster |
| `Qualifying Drought Event` | US Drought Monitor drought class |
| `Payment Type` | Number of Monthly Payments |

------------------------------------------------------------------------

## 📊 Demonstration Dashboard

The Quarto dashboard
[`fsa-lfp-eligibility.qmd`](./fsa-lfp-eligibility.qmd) provides:

- An **interactive viewer** to explore LFP Eligibility by county, year,
  disaster, and pasture type
- A **tool for researchers and policymakers** to assess temporal trends

<iframe src="fsa-lfp-eligibility.html" frameborder="0" allowfullscreen style="width:100%;height:40vw;">

</iframe>

Access a full-screen version of the dashboard at:  
<https://sustainable-fsa.github.io/fsa-lfp-eligibility/fsa-lfp-eligibility.html>

------------------------------------------------------------------------

## 📍 Quick Start: Visualize a FSA LFP Eligibility Map in R

This snippet shows how to load the FSA LFP Eligibility file from the
archive and create a simple map using `sf` and `ggplot2`.

``` r
# Load required libraries
library(sf)
library(ggplot2) # For plotting
library(tigris)  # For state boundaries
library(rmapshaper) # For innerlines function

## Get the LFP Eligibility data
eligibility <- 
  readr::read_csv("fsa-lfp-eligibility.csv")

## The LFP Eligibility data files use FSA county definitions
## Download from the FSA_Counties_dd17 archive
counties <- 
  sf::read_sf("https://sustainable-fsa.github.io/fsa-counties-dd17/fsa-counties-dd17.topojson",
              layer = "counties") |>
  sf::st_set_crs("EPSG:4326") |>
  sf::st_transform("EPSG:5070")

## Calculate the 2024 LFP Eligibility for Native Pasture, and
## combine with the county data
eligibility_counties <-
  eligibility |>
  dplyr::filter(`Pasture Type` == "Native Pasture",
                `Program Year` == 2024) |>
  dplyr::transmute(
    id = paste0(`State FSA Code`,`County FSA Code`),
    `Payment Type` = factor(`Payment Type`,
                            levels = paste0(1:5, " Month"),
                            ordered = TRUE)
  ) |>
  dplyr::left_join(counties) |>
  sf::st_as_sf()

# Plot the map
ggplot(counties) +
  geom_sf(data = sf::st_union(counties),
          fill = "grey80",
          color = NA) +
  geom_sf(data = eligibility_counties,
          aes(fill = `Payment Type`), 
          color = NA,
          show.legend = TRUE) +
  geom_sf(data = rmapshaper::ms_innerlines(counties),
          fill = NA,
          color = "white",
          linewidth = 0.1) +
  geom_sf(data = counties |>
            dplyr::group_by(state) |>
            dplyr::summarise() |>
            rmapshaper::ms_innerlines(),
          fill = NA,
          color = "white",
          linewidth = 0.2) +
  # Use the same color scale used by the LFP (yuck)
  # https://www.fsa.usda.gov/documents/native-pasture-2024-lfp-01-23-25
  scale_fill_manual(
    values = c("1 Month" = "#E0E436", 
               "2 Month" = "#DF9114", 
               "3 Month" = "#DD2313", 
               "4 Month" = "#850014", 
               "5 Month" = "#3B003C"),
    drop = FALSE,
    name = "Eligible\nPayments") +
  labs(title = "FSA LFP Eligibility",
       subtitle = "Native Pasture — 2024") +
  theme_void()
```

<img src="./example-1.png" style="display: block; margin: auto;" />

------------------------------------------------------------------------

## 🧭 About FSA County Codes

The USDA FSA uses custom county definitions that differ from standard
ANSI/FIPS codes used by the U.S. Census. To align the LFP Eligibility
data with geographic boundaries, we use the FSA-specific geospatial
dataset archived in the companion repository:

🔗
[**sustainable-fsa/fsa-counties-dd17**](https://sustainable-fsa.github.io/fsa-counties-dd17/)

FSA county codes are documented in [FSA Handbook 1-CM, Exhibit
101](https://www.fsa.usda.gov/Internet/FSA_File/1-cm_r03_a80.pdf).

------------------------------------------------------------------------

## 📜 Citation

If using this data in published work, please cite:

> USDA Farm Service Agency. *Livestock Forage Disaster Program
> Eligibility, 2008–2024*. FOIA request 2025-FSA-04690-F by R. Kyle
> Bocinsky. Accessed via GitHub archive, YYYY.
> <https://sustainable-fsa.github.io/fsa-lfp-eligibility/>

------------------------------------------------------------------------

## 📄 License

- **Raw FOIA data** (USDA): Public Domain (17 USC § 105)
- **Processed data & scripts**: © R. Kyle Bocinsky, released under
  [CC0](https://creativecommons.org/publicdomain/zero/1.0/) and [MIT
  License](./LICENSE) as applicable

------------------------------------------------------------------------

## ⚠️ Disclaimer

This dataset is archived for research and educational use only. It may
not reflect current USDA administrative boundaries or official LFP
policy. Always consult your **local FSA office** for the latest program
guidance.

To locate your nearest USDA Farm Service Agency office, use the USDA
Service Center Locator:

🔗 [**USDA Service Center
Locator**](https://offices.sc.egov.usda.gov/locator/app)

------------------------------------------------------------------------

## 👏 Acknowledgment

This project is part of:

**[*Enhancing Sustainable Disaster Relief in FSA
Programs*](https://www.ars.usda.gov/research/project/?accnNo=444612)**  
Supported by USDA OCE/OEEP and USDA Climate Hubs  
Prepared by the [Montana Climate Office](https://climate.umt.edu)

------------------------------------------------------------------------

## ✉️ Contact

Questions? Contact Kyle Bocinsky: <kyle.bocinsky@umontana.edu>
