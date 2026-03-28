# global.R — LandR × WS3 coupled simulation
# Run with: source("global.R")
#
# Prerequisites:
#   R packages: SpaDES.project, SpaDES.core, terra, data.table, reticulate, bcdata, sf, dplyr
#   Python:     pip install ws3

# install.packages('filelock')
# install.packages('magrittr')
# install.packages('magick')
# install.packages('jsonlite')
# png *for reticulate; rlang;RCurl;qs
# Note: the above actually had to be installed into a different libpaths like so:
# install.packages("magick", lib = "/home/allarocq/.local/share/R/allarocq/packages/x86_64-pc-linux-gnu/4.5")

#install.packages("devtools")
#library("devtools")
#install_github("achubaty/amc")

# Run this in linux: sudo apt-get install r-base-dev build-essential
# In windows, you'll need Rtools

Require::setupOff()

repos <- c("https://predictiveecology.r-universe.dev", getOption("repos"))     # Define a list of repos; add r-universe to the beginning of the repo list
source("https://raw.githubusercontent.com/PredictiveEcology/pemisc/refs/heads/development/R/getOrUpdatePkg.R")   # Source the getOrUpdatePkg function
getOrUpdatePkg(c("Require", "SpaDES.project","reticulate"),
               c("1.0.1.9003", "0.1.1.9037","1.43.0")) # This checks if the version is newer than the one defined in the list, and only installs/updates if it is not

# Install SpaDES.project if needed and related packages:
if (!require("SpaDES.project")){
  Require::Require(c("SpaDES.project", "SpaDES.core", "reproducible"),
                   repos = repos,
                   dependencies = TRUE)
}

Require::setLinuxBinaryRepo()  # Use pre-compiled binary packages for Linux instead of compiling from source. This should be faster, be more stable, and work better without root access.

# studyArea = {
#   if (!require("bcdata")) remotes::install_github("bcgov/bcdata")
#   tsa41 <- Cache(
#     function() {
#       bcdata::bcdc_query_geodata("8daa29da-d7f4-401c-83ae-d962e3a28980") |>
#         dplyr::filter(TSA_NUMBER == "41") |>
#         dplyr::collect() |>
#         sf::st_union() |>
#         sf::st_as_sf()
#     }
#   )
#   sf::st_transform(tsa41,
#                    crs = "+proj=lcc +lat_1=49 +lat_2=77 +lat_0=0 +lon_0=-95 +datum=NAD83 +units=m")
# }

# ── Project-level parameters ─────────────────────────────────────────────────
ws3PeriodLength <- 10L   # years between WS3 solves (1 = annual, 10 = default)
ws3Horizon      <- 10L   # number of WS3 planning periods
ws3BaseYear     <- 2011L

options(gargle_oauth_cache = path.expand("~/.gargle-oauth-cache"))
googledrive::drive_auth(email = "allen.larocque.work@gmail.com")  # token cached at ~/.gargle-oauth-cache; run drive_auth() interactively once to populate

# ── Python / reticulate setup ──────────────────────────────────────────────────
# Use the project venv that has ws3 installed.
# Create it with: uv venv ~/.venvs/ws3 && uv pip install ws3 --python ~/.venvs/ws3/bin/python
reticulate::use_virtualenv("~/.venvs/ws3", required = TRUE)

out <- SpaDES.project::setupProject(
  require=c("terra", "data.table", "reticulate", "bcdata", "sf", "dplyr"),
  paths = list(
    projectPath = getwd(),
    modulePath  = "modules",
    inputPath   = "inputs",
    outputPath  = "outputs",
    cachePath   = "cache"
  ),

  times = list(
    start = ws3BaseYear,
    end   = ws3BaseYear + ws3PeriodLength * ws3Horizon
  ),

  modules = c(
    "PredictiveEcology/Biomass_borealDataPrep@development",
    "PredictiveEcology/Biomass_core@development",
    "AllenLarocque/biomass_yieldTablesWS3@main",
    "AllenLarocque/biomass_ws3Harvest@main",
    "ws3Verify"
    # add fire / disturbance modules here as needed, e.g.:
    # "PredictiveEcology/scfm@development"
  ),

  params = list(
    .globals = list(
      ws3PeriodLength = ws3PeriodLength
    ),
    biomass_yieldTablesWS3 = list(
      maxSimAge       = 300L,
      siteQualityBins = c(0.33, 0.67)
    ),
    biomass_ws3Harvest = list(
      ws3Horizon       = ws3Horizon,
      ws3BaseYear      = ws3BaseYear,
      ws3MinHarvestAge = 40L,
      ws3Solver        = "highs"
    )
  ),

  # Default study area: TSA41 — Dawson Creek TSA, northeastern BC
  # To use a different area, replace this block with your own polygon
  #studyArea = studyArea,

  #studyAreaLarge = {
  #  sf::st_buffer(studyArea, dist = 20000)
  #},
  
  # This is from Dom:
  functions = "R/getRIA.R",
  # Study area is within RIA (RIA buffered 150km inward)
  studyArea = {
    reproducible::prepInputs(
      url = "https://drive.google.com/file/d/1LxacDOobTrRUppamkGgVAUFIxNT4iiHU/view?usp=sharing",
      destinationPath = "inputs",
      fun = getRIA,
      overwrite = TRUE
    ) |> sf::st_buffer(dist = -150000)
  },
  studyAreaLarge = sf::st_buffer(studyArea, dist = 20000),
  rasterToMatchLarge = {
    sal <- terra::vect(studyAreaLarge)
    targetCRS <- terra::crs(sal)
    rtmL <- terra::rast(sal, res = c(250, 250), crs = targetCRS)
    rtmL[] <- 1
    terra::mask(rtmL, sal)
  },

  standAgeMap = {
    sam <- reproducible::prepInputs(
      url = paste0("http://ftp.maps.canada.ca/pub/nrcan_rncan/Forests_Foret/",
                   "canada-forests-attributes_attributs-forests-canada/",
                   "2001-attributes_attributs-2001/",
                   "NFI_MODIS250m_2001_kNN_Structure_Stand_Age_v1.tif"),
      destinationPath = "inputs",
      to = rasterToMatchLarge  # project + resample to exactly match rasterToMatchLarge grid
    )
    attr(sam, "imputedPixID") <- integer(0)
    sam
  },

  rasterToMatch = {
    sa <- terra::vect(studyArea)
    targetCRS <- terra::crs(sa)
    rtm <- terra::rast(sa, res = c(250, 250), crs = targetCRS)
    rtm[] <- 1
    rtm <- terra::mask(rtm, sa)
    rtm
  },

  packages = c("qs","RCurl","terra", "data.table", "reticulate", "bcdata", "sf", "dplyr",
              "gert", "PredictiveEcology/LandR@development",
              "PredictiveEcology/pemisc@development",
                            "reticulate", "httr", "XML","bcdata",
                            "PredictiveEcology/SpaDES.core@development (>= 3.0.3.9003)",
                            "PredictiveEcology/reproducible (>= 3.0.0)"),

  options = list(
    spades.allowInitDuringSimInit = TRUE,
    reproducible.useCache         = TRUE
  )
)

# ── Patch LandR::makeEcoregionMap ─────────────────────────────────────────────
# Bug: the function copies ecoregionFiles$ecoregionMap (non-NA for all study-area
# pixels), then only updates active-group pixels, leaving inactive-group and
# filtered-out pixels with their original non-NA values.  This causes the
# Biomass_core assertion  is.na(ecoregionMap) == is.na(pixelGroupMap)  to fail.
#
# Fix: (1) filter truePixelData by pixelIndex so only cohortData pixels remain,
#       (2) initialise the output raster to all-NA before assigning values.
local({
  fixed_fn <- function(ecoregionFiles, pixelCohortData) {
    truePixelData <- as.data.table(ecoregionFiles$ecoregionMap, cells = TRUE)
    setnames(truePixelData, old = "cell", new = "pixelIndex")
    truePixelData[, `:=`(mapcode, as.integer(mapcode))]
    truePixelData <- truePixelData[ecoregionFiles$ecoregion, on = c("mapcode")]
    # original filter: by group only → includes pixels removed from cohortData
    # fixed filter:    by group AND pixelIndex → exact match with pixelGroupMap
    truePixelData <- truePixelData[
      ecoregionGroup %in% pixelCohortData$ecoregionGroup &
      pixelIndex     %in% pixelCohortData$pixelIndex
    ]
    # Some cohortData pixels (e.g. fire/LCC34-36) may have ecoregionGroups but
    # are not in the ecoregion raster → NA in ecoregionMap but non-NA in pixelGroupMap.
    # Borrow group metadata from any existing pixel in the same group.
    allCohortPix <- unique(pixelCohortData[, .(pixelIndex, ecoregionGroup)])
    missingPix   <- allCohortPix[!pixelIndex %in% truePixelData$pixelIndex]
    if (nrow(missingPix) > 0) {
      groupMeta <- unique(truePixelData[, .(ecoregionGroup, landcover, ecoregionName)])
      missingPix <- groupMeta[missingPix, on = "ecoregionGroup", nomatch = NA]
      # fallback: use first available row for any groups with no representative
      if (anyNA(missingPix$landcover)) {
        fb <- groupMeta[1L]
        missingPix[is.na(landcover), `:=`(landcover     = fb$landcover,
                                           ecoregionName = fb$ecoregionName)]
      }
      truePixelData <- rbindlist(list(truePixelData, missingPix), use.names = TRUE, fill = TRUE)
    }
    message("makeEcoregionMap [patched]: final truePixelData pixels: ", nrow(truePixelData),
            " | cohortData unique pixels: ", nrow(allCohortPix),
            " | added missing: ", nrow(missingPix))
    truePixelData[, `:=`(ecoregionGroup, factor(as.character(ecoregionGroup)))]
    ecoregionMap <- rasterRead(ecoregionFiles$ecoregionMap)
    ecoregionMap[] <- NA_integer_   # initialise to NA so inactive pixels stay NA
    suppressWarnings(ecoregionMap[truePixelData$pixelIndex] <-
                       as.integer(truePixelData$ecoregionGroup))
    factorDT <- unique(truePixelData[, .(ecoregionGroup, landcover, ecoregionName)])
    factorDT[, `:=`(ID, seq(levels(ecoregionGroup)))]
    factorDT[, `:=`(ecoregion, gsub("_.*", "", ecoregionGroup))]
    setcolorder(factorDT, c("ID", "ecoregionGroup", "ecoregionName",
                             "ecoregion", "landcover"))
    levels(ecoregionMap) <- factorDT
    return(ecoregionMap)
  }
  environment(fixed_fn) <- asNamespace("LandR")
  utils::assignInNamespace("makeEcoregionMap", fixed_fn, ns = "LandR")
  message("LandR::makeEcoregionMap patched: pixelIndex filter + NA initialisation")
})

sim <- SpaDES.core::simInit2(out)
sim <- SpaDES.core::spades(sim)
