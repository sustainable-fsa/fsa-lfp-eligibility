# Annual County Eligibility Data from the Livestock Forage Disaster Program, 2012–2022

This repository is an archive of the annual county-level eligibility data for the [Livestock Forage Disaster Program](https://www.fsa.usda.gov/programs-and-services/disaster-assistance-program/livestock-forage/index). These data were acquired via Freedom of Information Act (FOIA) request 2023-FSA-00937-F made by R. Kyle Bocinsky, Director of Climate Extension for the [Montana Climate Office](https://climate.umt.edu), to the US Department of Agriculture (USDA) [Farm Production and Conservation Business Center (FPAC-BC)](https://www.fpacbc.usda.gov). The request was submitted on December 5, 2022, and was fulfilled on January 6, 2023.

The original FOIA request and data as received are in the [`foia`](/foia) directory. Data were ingested into the [R statistical framework](https://www.r-project.org), were cleaned to a common set of fields and filtered to only include counties in the contiguous United States, and then were written to a consolidated CSV file ([`fsa-lfp-eligibility.csv`](/fsa-lfp-eligibility.csv)) and mapped in multi-page PDF ([`fsa-lfp-eligibility.pdf`](/fsa-lfp-eligibility.pdf)). [`fsa-lfp-eligibility.R`](/fsa-lfp-eligibility.R) is the R script that cleans the data and produces the maps. The FSA uses slightly different county or county equivalent definitions for their service areas than the standard ANSI FIPS areas used by the US Census. The FSA counties are included in the [`fsa-counties`](/fsa-counties) directory; FSA county codes are detailed in [FSA Handbook 1-CM](https://www.fsa.usda.gov/Internet/FSA_File/1-cm_r03_a80.pdf), Exhibit 101. For completeness, [`fsa-lfp-eligibility-published-20230119.pdf`](/fsa-lfp-eligibility-published-20230119.pdf) contains the eligibility maps as published on the LFP website as of January 19, 2023.

Data in the [`foia/2023-FSA-00937-F Bocinsky.zip`](/foia/2023-FSA-00937-F%20Bocinsky.zip) archive were produced by the USDA Farm Service Agency and are in the Public Domain. All other data, including the processed data and maps were created by R. Kyle Bocinsky and are released under the [Creative Commons CCZero license](https://creativecommons.org/publicdomain/zero/1.0/). The [`fsa-lfp-eligibility.R`](/fsa-lfp-eligibility.R) script is copyright R. Kyle Bocinsky, and is released under the [MIT License](/LICENSE.md).

This work was supported by a grant from the National Oceanic and Atmospheric Administration, [National Integrated Drought Information System](https://www.drought.gov) (University Corporation for Atmospheric Research subaward SUBAWD000858). We also acknowledge and appreciate the prompt and professional FOIA response we received from the USDA Farm Production and Conservation Business Center.

Please contact Kyle Bocinsky ([kyle.bocinsky@umontana.edu](mailto:kyle.bocinsky@umontana.edu)) with any questions.

<br>
<p align="center">
<a href="https://climate.umt.edu" target="_blank">
<img src="https://climate.umt.edu/assets/images/MCO_logo_icon_only.png" width="350" alt="The Montana Climate Office logo.">
</a>
</p>
