# GRT Sites Geocoding Script

R script for geocoding Gypsy, Roma and Traveller (GRT) sites in England using a three-tier API cascade. Developed for BA Geography final year project at the University of Liverpool.

## Overview

This script takes a CSV of GRT site addresses and produces a complete, analysis-ready shapefile using three geocoding APIs in sequence:

1. **Postcodes.io** (free) — Primary method for UK postcodes
2. **Nominatim / OpenStreetMap** (free) — Fallback for addresses without postcodes
3. **Google Maps Geocoding API** (paid, ~$0.005/request) — Final fallback for remaining sites

**Target:** 100% coverage of ~282 local authority GRT sites across England.

## Requirements

- R ≥ 4.0
- Packages: `sf`, `httr`, `jsonlite`, `readr`, `dplyr`, `ggplot2`, `stringr`

```r
install.packages(c("sf", "httr", "jsonlite", "readr", "dplyr", "ggplot2", "stringr"))
```

## Input Data

Place a CSV named `GRTSiteLoc.csv` in the working directory with at least three columns:

| Column | Description |
|--------|-------------|
| 1 | ONS Code |
| 2 | Local Authority name |
| 3 | Site address |

The script auto-detects the header row (looks for "ONS Code", "Local Authority", "Site and Address").

## Setup

1. Clone or copy the script to your working directory
2. Add your **Google Maps Geocoding API key** on line 39:

```r
GOOGLE_API_KEY <- "YOUR_API_KEY_HERE"
```

> **Without a Google API key** you'll achieve ~63% coverage (Postcodes.io + Nominatim only).  
> **With a key** the script typically reaches 100% for ~$1.40 total cost (282 sites × $0.005).

## Usage

```r
source("AllinOneGecodingScript.R")
```

Or run line-by-line in RStudio. The script prints progress every 10 sites and a full summary at the end.

## Outputs

| File | Description |
|------|-------------|
| `grt_sites_COMPLETE_100_percent.shp` | ESRI Shapefile (EPSG:4326) — all successfully geocoded sites with method attribute |
| `grt_sites_COMPLETE_100_percent.csv` | Full CSV with lat/lon, geocoding method, success flag |
| `grt_sites_COMPLETE_map.png` | 300 DPI map coloured by geocoding method |
| `grt_sites_failed_final.csv` | Any sites that couldn't be geocoded (for manual review) |

## How It Works

```
For each site:
  1. Extract UK postcode from address → try Postcodes.io
  2. If failed → try Nominatim with address + local authority + "UK"
  3. If failed → try Google Maps Geocoding API
  4. Record method used, lat/lon, success flag
```

Rate limits respected:
- Postcodes.io: 50 ms delay
- Nominatim: 1.5 s delay (per usage policy)
- Google Maps: 100 ms delay

## Map Output

The generated map shows all sites coloured by geocoding method:
- **Blue** — Postcodes.io
- **Magenta** — Nominatim
- **Orange** — Google Maps

Use this to visually verify spatial distribution and method balance.

## Loading the Shapefile

```r
library(sf)
library(ggplot2)

shp <- st_read("grt_sites_COMPLETE_100_percent.shp")
ggplot(shp) + geom_sf(aes(color = method), size = 2) + theme_minimal() + coord_sf()
```

## Notes

- **API key security**: Never commit your Google API key to version control. Use `.gitignore` or environment variables.
- **Nominatim policy**: The script sets a descriptive User-Agent (`Geography_Student_GRT/1.0`) and respects the 1 req/s limit.
- **Coordinate reference system**: All outputs use WGS84 (EPSG:4326).
- **Column names**: Shapefile columns are abbreviated to 10 characters (ESRI Shapefile limit).

## License

Academic use. Attribution appreciated if you adapt this for your own work.

## Contact

Evie Hassan — BA Geography, University of Liverpool  
[LinkedIn](https://www.linkedin.com/in/evie-hassan-4bab432a1/)