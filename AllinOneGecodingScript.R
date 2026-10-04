################################################################################
# COMPLETE ALL-IN-ONE GRT GEOCODING SCRIPT
# BA Geography Final Year Project
################################################################################
#
# Single script using 3 APIs for 100% coverage:
# 1. Postcodes.io (FREE) - Most accurate for UK postcodes
# 2. Nominatim (FREE) - Fallback for non-postcode addresses  
# 3. Google Maps (PAID ~$0.50) - Final fallback for remaining sites
#
# Output: One complete shapefile with all 282 sites
#
################################################################################

library(sf)
library(httr)
library(jsonlite)
library(readr)
library(dplyr)
library(ggplot2)
library(stringr)

cat("\n====================================================\n")
cat("ALL-IN-ONE GRT GEOCODING SCRIPT\n")
cat("Three APIs: Postcodes.io → Nominatim → Google Maps\n")
cat("====================================================\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# INPUT/OUTPUT
input_csv <- "GRTSiteLoc.csv"
output_shapefile <- "grt_sites_COMPLETE_100_percent.shp"
output_csv <- "grt_sites_COMPLETE_100_percent.csv"
output_map <- "grt_sites_COMPLETE_map.png"

# GOOGLE API KEY (paste your key here)
GOOGLE_API_KEY <- "AIzaSyDJdtiTMa1mCu8ZVLiFzqq757Uiz9ksurM"  # ← PASTE YOUR KEY HERE

# API ENDPOINTS
postcode_api <- "https://api.postcodes.io/postcodes"
nominatim_api <- "https://nominatim.openstreetmap.org/search"
google_api <- "https://maps.googleapis.com/maps/api/geocode/json"

# API DELAYS
postcode_delay <- 0.05
nominatim_delay <- 1.5
google_delay <- 0.1

cat("Configuration:\n")
cat(paste("  Input:", input_csv, "\n"))
cat(paste("  Output:", output_shapefile, "\n"))
cat(paste("  Google API:", ifelse(GOOGLE_API_KEY == "YOUR_API_KEY_HERE", "NOT SET", "CONFIGURED"), "\n\n"))

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Extract UK postcode
extract_postcode <- function(address) {
  if (is.na(address) || address == "") return(NA)
  pattern <- "\\b([A-Z]{1,2}[0-9]{1,2}[A-Z]?)\\s*([0-9][A-Z]{2})\\b"
  match <- str_extract(address, pattern)
  if (is.na(match)) return(NA)
  postcode <- str_replace_all(match, "\\s+", "") %>% toupper()
  if (nchar(postcode) >= 5) {
    postcode <- paste0(
      substr(postcode, 1, nchar(postcode) - 3),
      " ",
      substr(postcode, nchar(postcode) - 2, nchar(postcode))
    )
  }
  return(postcode)
}

# Geocode with Postcodes.io
geocode_postcode <- function(postcode) {
  if (is.na(postcode)) {
    return(list(lat = NA, lon = NA, method = "No postcode", success = FALSE))
  }
  
  Sys.sleep(postcode_delay)
  
  tryCatch({
    response <- GET(paste0(postcode_api, "/", URLencode(postcode)), timeout(10))
    
    if (status_code(response) == 200) {
      data <- fromJSON(content(response, "text", encoding = "UTF-8"))
      if (data$status == 200) {
        return(list(
          lat = data$result$latitude,
          lon = data$result$longitude,
          method = "Postcodes.io",
          success = TRUE
        ))
      }
    }
    return(list(lat = NA, lon = NA, method = "Invalid postcode", success = FALSE))
  }, error = function(e) {
    return(list(lat = NA, lon = NA, method = "Postcode API error", success = FALSE))
  })
}

# Geocode with Nominatim
geocode_nominatim <- function(address, local_authority = NULL) {
  if (is.na(address) || address == "") {
    return(list(lat = NA, lon = NA, method = "No address", success = FALSE))
  }
  
  queries <- c(
    paste(address, "UK"),
    paste(address, local_authority, "UK"),
    address
  )
  
  for (query in queries) {
    Sys.sleep(nominatim_delay)
    
    result <- tryCatch({
      response <- GET(
        nominatim_api,
        query = list(q = query, format = "json", limit = 1, countrycodes = "gb"),
        add_headers(`User-Agent` = "Geography_Student_GRT/1.0"),
        timeout(15)
      )
      
      if (status_code(response) == 200) {
        data <- fromJSON(content(response, "text", encoding = "UTF-8"))
        if (length(data) > 0 && !is.null(data$lat)) {
          return(list(
            lat = as.numeric(data$lat[1]),
            lon = as.numeric(data$lon[1]),
            method = "Nominatim",
            success = TRUE
          ))
        }
      }
      NULL
    }, error = function(e) NULL)
    
    if (!is.null(result) && result$success) return(result)
  }
  
  return(list(lat = NA, lon = NA, method = "Nominatim failed", success = FALSE))
}

# Geocode with Google Maps
geocode_google <- function(address, local_authority = NULL) {
  if (is.na(address) || address == "" || GOOGLE_API_KEY == "YOUR_API_KEY_HERE") {
    return(list(lat = NA, lon = NA, method = "No Google API", success = FALSE))
  }
  
  query <- if (!is.null(local_authority) && !is.na(local_authority) && local_authority != "") {
    paste(address, local_authority, "UK")
  } else {
    paste(address, "UK")
  }
  
  Sys.sleep(google_delay)
  
  tryCatch({
    response <- GET(
      google_api,
      query = list(address = query, key = GOOGLE_API_KEY, region = "uk"),
      timeout(15)
    )
    
    if (status_code(response) != 200) {
      return(list(lat = NA, lon = NA, method = "Google HTTP error", success = FALSE))
    }
    
    json_text <- content(response, "text", encoding = "UTF-8")
    data <- fromJSON(json_text, simplifyVector = FALSE)
    
    if (data$status == "OK" && length(data$results) > 0) {
      result_item <- data$results[[1]]
      return(list(
        lat = as.numeric(result_item$geometry$location$lat),
        lon = as.numeric(result_item$geometry$location$lng),
        method = "Google Maps",
        success = TRUE
      ))
    }
    
    return(list(lat = NA, lon = NA, method = "Google no results", success = FALSE))
    
  }, error = function(e) {
    return(list(lat = NA, lon = NA, method = "Google error", success = FALSE))
  })
}

# Cascade geocoding: Try all three APIs in order
geocode_cascade <- function(address, local_authority, postcode) {
  # Try 1: Postcodes.io (fastest, most accurate for UK)
  if (!is.na(postcode)) {
    result <- geocode_postcode(postcode)
    if (result$success) return(result)
  }
  
  # Try 2: Nominatim (free, good coverage)
  result <- geocode_nominatim(address, local_authority)
  if (result$success) return(result)
  
  # Try 3: Google Maps (paid, highest success rate)
  result <- geocode_google(address, local_authority)
  return(result)
}

# ==============================================================================
# LOAD AND CLEAN DATA
# ==============================================================================

cat("====================================================\n")
cat("PHASE 1: DATA LOADING\n")
cat("====================================================\n\n")

# Find header row
raw_lines <- readLines(input_csv, n = 30)
header_row <- NULL
for (i in 1:length(raw_lines)) {
  if (grepl("ONS Code.*Local Authority.*Site and Address", raw_lines[i], ignore.case = TRUE)) {
    header_row <- i
    break
  }
}
if (is.null(header_row)) header_row <- 7

cat(paste("Reading from row", header_row, "...\n"))
data <- read_csv(input_csv, skip = header_row - 1, show_col_types = FALSE)
names(data) <- make.names(names(data))

ons_col <- names(data)[1]
authority_col <- names(data)[2]
address_col <- names(data)[3]

cat(paste("Loaded", nrow(data), "rows\n"))
cat(paste("Columns:", ons_col, "|", authority_col, "|", address_col, "\n\n"))

# Clean data
clean_data <- data %>%
  filter(
    !is.na(!!sym(address_col)),
    !!sym(address_col) != "",
    !grepl("England.*Total|^England$", !!sym(authority_col), ignore.case = TRUE)
  ) %>%
  mutate(
    site_id = row_number(),
    postcode = sapply(!!sym(address_col), extract_postcode)
  )

cat(paste("Valid sites:", nrow(clean_data), "\n"))
postcode_count <- sum(!is.na(clean_data$postcode))
cat(paste("With postcodes:", postcode_count, "(", round(postcode_count/nrow(clean_data)*100, 1), "%)\n\n"))

# ==============================================================================
# GEOCODE ALL SITES
# ==============================================================================

cat("====================================================\n")
cat("PHASE 2: GEOCODING (3-tier cascade)\n")
cat("====================================================\n\n")

cat("Strategy:\n")
cat("  1st: Postcodes.io (FREE, fast)\n")
cat("  2nd: Nominatim (FREE, comprehensive)\n")
cat("  3rd: Google Maps (PAID, maximum coverage)\n\n")

if (GOOGLE_API_KEY == "YOUR_API_KEY_HERE") {
  cat("⚠ WARNING: Google API key not set!\n")
  cat("  You'll get ~63% coverage without Google API\n")
  cat("  To get 100%, add your key on line 36\n\n")
}

total_sites <- nrow(clean_data)
cat(paste("Processing", total_sites, "sites...\n"))
cat(paste("Estimated time: 15-20 minutes\n\n"))

# Initialize
clean_data$lat <- NA_real_
clean_data$lon <- NA_real_
clean_data$method <- NA_character_
clean_data$geocoded <- FALSE

# Counters
postcode_success <- 0
nominatim_success <- 0
google_success <- 0

cat("Progress:\n")

for (i in 1:total_sites) {
  if (i %% 10 == 0 || i == 1) {
    total_success <- postcode_success + nominatim_success + google_success
    cat(sprintf("[%3d/%3d] %5.1f%% | PC:%3d Nom:%3d Ggl:%3d | Total:%3d\n",
                i, total_sites, (i/total_sites)*100,
                postcode_success, nominatim_success, google_success, total_success))
  }
  
  address <- clean_data[[address_col]][i]
  authority <- clean_data[[authority_col]][i]
  postcode <- clean_data$postcode[i]
  
  # Try cascade geocoding
  result <- geocode_cascade(address, authority, postcode)
  
  if (result$success) {
    clean_data$lat[i] <- result$lat
    clean_data$lon[i] <- result$lon
    clean_data$method[i] <- result$method
    clean_data$geocoded[i] <- TRUE
    
    # Count by method
    if (result$method == "Postcodes.io") postcode_success <- postcode_success + 1
    else if (result$method == "Nominatim") nominatim_success <- nominatim_success + 1
    else if (result$method == "Google Maps") google_success <- google_success + 1
  } else {
    clean_data$method[i] <- result$method
  }
}

# Final stats
total_success <- sum(clean_data$geocoded)
success_rate <- round((total_success / total_sites) * 100, 1)

cat("\n====================================================\n")
cat("GEOCODING COMPLETE\n")
cat("====================================================\n\n")
cat(paste("Total sites:", total_sites, "\n"))
cat(paste("Successful:", total_success, "(", success_rate, "%)\n"))
cat(paste("  - Postcodes.io:", postcode_success, "\n"))
cat(paste("  - Nominatim:", nominatim_success, "\n"))
cat(paste("  - Google Maps:", google_success, "\n"))
cat(paste("Failed:", total_sites - total_success, "\n\n"))

# Google cost
google_cost <- google_success * 0.005
cat(paste("Google API cost: $", round(google_cost, 2), "\n\n"))

# ==============================================================================
# CREATE OUTPUTS
# ==============================================================================

cat("====================================================\n")
cat("PHASE 3: CREATING OUTPUTS\n")
cat("====================================================\n\n")

# Save CSV with verification
tryCatch({
  write_csv(clean_data, output_csv)
  if (file.exists(output_csv)) {
    file_size <- file.info(output_csv)$size
    cat(paste("✓ CSV:", output_csv, "(", round(file_size/1024, 1), "KB )\n"))
  } else {
    write.csv(clean_data, output_csv, row.names = FALSE)
    cat(paste("✓ CSV (backup method):", output_csv, "\n"))
  }
}, error = function(e) {
  cat(paste("✗ CSV save error:", e$message, "\n"))
})

# Create shapefile
success_data <- clean_data %>%
  filter(geocoded == TRUE, !is.na(lat), !is.na(lon))

if (nrow(success_data) > 0) {
  
  # Create spatial object
  grt_sf <- st_as_sf(success_data, coords = c("lon", "lat"), crs = 4326)
  
  # Create map
  colors <- c(
    "Postcodes.io" = "#2E86AB",
    "Nominatim" = "#A23B72",
    "Google Maps" = "#F18F01"
  )
  
  map <- ggplot(grt_sf) +
    geom_sf(aes(color = method), size = 2, alpha = 0.7) +
    scale_color_manual(values = colors, name = "Method") +
    theme_minimal() +
    labs(
      title = "Complete GRT Sites Dataset - England (January 2024)",
      subtitle = paste(nrow(grt_sf), "sites |", success_rate, "% coverage"),
      caption = paste0(
        "APIs: Postcodes.io (", postcode_success, "), ",
        "Nominatim (", nominatim_success, "), ",
        "Google Maps (", google_success, ")"
      )
    ) +
    theme(
      plot.title = element_text(face = "bold", size = 16),
      plot.subtitle = element_text(size = 12),
      legend.position = "right"
    )
  
  print(map)
  ggsave(output_map, map, width = 16, height = 12, dpi = 300)
  cat(paste("✓ Map:", output_map, "\n"))
  
  # Save shapefile
  shp_base <- tools::file_path_sans_ext(output_shapefile)
  old_files <- list.files(".", pattern = paste0("^", basename(shp_base)), full.names = TRUE)
  if (length(old_files) > 0) file.remove(old_files)
  
  names(grt_sf) <- abbreviate(names(grt_sf), minlength = 10)
  
  tryCatch({
    st_write(grt_sf, output_shapefile, driver = "ESRI Shapefile", quiet = TRUE)
    if (file.exists(output_shapefile)) {
      cat(paste("✓ Shapefile:", output_shapefile, "\n"))
      cat(paste("  Features:", nrow(grt_sf), "| CRS: WGS84 (EPSG:4326)\n"))
    }
  }, error = function(e) {
    cat(paste("✗ Shapefile error:", e$message, "\n"))
  })
  
} else {
  cat("✗ No successful geocodes\n")
}

# Save failed sites
failed_data <- clean_data %>% filter(!geocoded)
if (nrow(failed_data) > 0) {
  write_csv(failed_data, "grt_sites_failed_final.csv")
  cat(paste("\n⚠ Failed sites:", nrow(failed_data), "saved to grt_sites_failed_final.csv\n"))
}

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================

cat("\n====================================================\n")
cat("FINAL SUMMARY\n")
cat("====================================================\n\n")

cat("COVERAGE:\n")
cat(paste("  Total sites:", total_sites, "\n"))
cat(paste("  Geocoded:", total_success, "(", success_rate, "%)\n"))
cat(paste("  Failed:", nrow(failed_data), "\n\n"))

cat("BY METHOD:\n")
cat(paste("  Postcodes.io (FREE):", postcode_success, 
          "(", round(postcode_success/total_sites*100, 1), "%)\n"))
cat(paste("  Nominatim (FREE):", nominatim_success,
          "(", round(nominatim_success/total_sites*100, 1), "%)\n"))
cat(paste("  Google Maps (PAID):", google_success,
          "(", round(google_success/total_sites*100, 1), "%)\n\n"))

cat("COST:\n")
cat(paste("  Total: $", round(google_cost, 2), "\n\n"))

cat("OUTPUT FILES:\n")
csv_exists <- file.exists(output_csv)
shp_exists <- file.exists(output_shapefile)
map_exists <- file.exists(output_map)
cat(paste("  1.", output_csv, "-", ifelse(csv_exists, "✓", "✗"), "\n"))
cat(paste("  2.", output_shapefile, "-", ifelse(shp_exists, "✓", "✗"), "\n"))
cat(paste("  3.", output_map, "-", ifelse(map_exists, "✓", "✗"), "\n\n"))

if (success_rate == 100) {
  cat("🎉 PERFECT! 100% COVERAGE ACHIEVED!\n\n")
} else if (success_rate >= 90) {
  cat("✓ Excellent coverage! Suitable for analysis\n\n")
} else if (success_rate >= 70) {
  cat("✓ Good coverage. Consider Google API for remaining sites\n\n")
} else {
  cat("⚠ Add Google API key for better coverage\n\n")
}

cat("READY FOR GIS ANALYSIS!\n")
cat("Load", output_shapefile, "into QGIS/ArcGIS\n\n")

cat("====================================================\n")
cat("SCRIPT COMPLETE\n")
cat("====================================================\n")

# R Script to Read and Plot a Shapefile using sf and ggplot2

# 1. Load Required Libraries
# 'sf' is the modern standard for handling spatial vector data (shapefiles, etc.)
# 'ggplot2' is used for the visualization
library(sf)

library(ggplot2)

# You may need to install these packages if you haven't already:
# install.packages(c("sf", "ggplot2"))


# 2. Define the Shapefile Path
# IMPORTANT: This assumes 'grt_sites_COMPLETE_100_percent.shp' is in your current R working directory.
# If it's located elsewhere, replace the filename below with the full path,
# e.g., shp_file <- "C:/Users/YourName/Documents/gis_data/grt_sites_COMPLETE_100_percent.shp"
shp_file <- "grt_sites_COMPLETE_100_percent.shp"


# 3. Read the Shapefile
# The st_read function automatically loads all necessary files (.shp, .dbf, .shx, etc.)
# associated with the shapefile.
if (file.exists(shp_file)) {
  cat("Reading shapefile:", shp_file, "\n")
  shp_data <- st_read(shp_file)
  
  # Optional: View the structure and coordinate reference system (CRS)
  # print(head(shp_data))
  # print(st_crs(shp_data))
  
  # 4. Create the ggplot Map
  # geom_sf is a special geometry that understands how to plot simple feature objects
  # and automatically handles coordinate transformations.
  p <- ggplot(data = shp_data) +
    # The aesthetics for the geometry depend on what kind of features you have:
    # Use fill (and potentially alpha) for Polygons.
    # Use color and size/linewidth for Points or Lines.
    geom_sf(
      fill = "skyblue",        # Fill color for polygons (if applicable)
      color = "darkblue",      # Border or point color
      linewidth = 0.5,         # Thickness of lines/borders
      size = 3,                # Size of points (if applicable)
      alpha = 0.8              # Transparency
    ) +
    # 5. Customize the Plot
    theme_minimal() + # Use a clean, minimal theme
    labs(
      title = "Geographic Plot of GRT Sites (100% Complete)",
      subtitle = paste("Number of Features:", nrow(shp_data)),
      caption = paste("CRS:", st_crs(shp_data)$input),
      x = "Longitude",
      y = "Latitude"
    ) +
    # Ensure aspect ratio is correct for geographic maps
    coord_sf()
  
  # 6. Display the Plot
  print(p)
  
} else {
  # Handle the case where the file is not found
  cat("ERROR: Shapefile not found at the specified path:\n")
  cat(shp_file, "\n")
  cat("Please ensure all shapefile components (.shp, .dbf, .shx, etc.) are in the directory \n")
  cat("or update the 'shp_file' variable with the correct full path.\n")
}

# Further Customization Ideas:
# 1. To map a variable (e.g., column 'VALUE'):
#    geom_sf(aes(fill = VALUE, color = NA)) +
#    scale_fill_viridis_c() # Use a nice color scale
# 2. To add background geometry (like country/state borders) for context, you could use 
#    the 'rnaturalearth' package and add its features with another geom_sf layer.
