# Annual County Eligibility Data from the Livestock Forage Disaster Program, 2012–2022

This repository is an archive of the annual county-level eligibility data for the Livestock Forage Disaster Program. These data were acquired via Freedom of Information Act (FOIA) request 2023-FSA-00937-F made by R. Kyle Bocinsky, Director of Climate Extension for the Montana Climate Office, to the US Department of Agriculture (USDA) Farm Production and Conservation Business Center (FPAC-BC). The request was submitted on December 5, 2022, and was fulfilled on January 6, 2023.

The original FOIA request and data as received are in the [`foia`](/foia) directory. Data were ingested into the [R statistical framework](https://www.r-project.org), were cleaned to a common set of fields and filtered to only include counties in the contiguous United States, and then were written to a consolidated CSV file ([`fsa-lfp-eligibility.csv`](/fsa-lfp-eligibility.csv)) and mapped in a series of PDFs available in the [`maps`](/maps) directory. [`fsa-lfp-eligibility.R`](/fsa-lfp-eligibility.R) is the R script that cleans the data and produces the maps.

Data in the [`foia/2023-FSA-00937-F Bocinsky.zip`](/foia/2023-FSA-00937-F Bocinsky.zip) archive were produced by the USDA Farm Service Agency and are in the Public Domain. All other data, including the processed data and maps are copyright R. Kyle Bocinsky and are released under the [Creative Commons CCZero license](https://creativecommons.org/publicdomain/zero/1.0/). The [`fsa-lfp-eligibility.R`](/fsa-lfp-eligibility.R) script is copyright R. Kyle Bocinsky, and is released under the [MIT License](/LICENSE.md).

This work was supported by a grant from the National Oceanic and Atmospheric Administration, [National Integrated Drought Information System](https://www.drought.gov) (University Corporation for Atmospheric Research subaward SUBAWD000858). We also acknowledge and appreciate the prompt and professional FOIA response we received from the USDA Farm Production and Conservation Business Center.

Please contact Kyle Bocinsky ([kyle.bocinsky@umt.edu](mailto:kyle.bocinsky@umt.edu)) with any questions.

<br>
<p align="center">
<a href="https://climate.umt.edu" target="_blank">
<img src="https://climate.umt.edu/imx/MCO_logo.svg" width="350" alt="The Montana Climate Office logo.">
</a>
</p>
