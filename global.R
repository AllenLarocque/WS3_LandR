# global.R — LandR × WS3 coupled simulation
# Run with: source("global.R")
#
# Prerequisites:
#   R packages: SpaDES.project, SpaDES.core, terra, data.table, reticulate, bcdata, sf, dplyr
#   Python:     pip install ws3

if (!require("SpaDES.project")) {
  remotes::install_github("PredictiveEcology/SpaDES.project@transition")
}

# ── Project-level parameters ─────────────────────────────────────────────────
ws3PeriodLength <- 10L   # years between WS3 solves (1 = annual, 10 = default)
ws3Horizon      <- 10L   # number of WS3 planning periods
ws3BaseYear     <- 2011L

out <- SpaDES.project::setupProject(

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
    "PredictiveEcology/Biomass_borealDataPrep@main",
    "PredictiveEcology/Biomass_core@main",
    "AllenLarocque/biomass_yieldTablesWS3@main",
    "AllenLarocque/Biomass_ws3Harvest@main"
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
    Biomass_ws3Harvest = list(
      ws3Horizon       = ws3Horizon,
      ws3BaseYear      = ws3BaseYear,
      ws3MinHarvestAge = 40L,
      ws3Solver        = "highs"
    )
  ),

  # Default study area: TSA41 — Dawson Creek TSA, northeastern BC
  # To use a different area, replace this block with your own polygon
  studyArea = {
    if (!require("bcdata")) remotes::install_github("bcgov/bcdata")
    tsa41 <- Cache(
      function() {
        bcdata::bcdc_query_geodata("8daa29da-d7f4-401c-83ae-d962e3a28980") |>
          dplyr::filter(TSA_NUMBER == "41") |>
          dplyr::collect() |>
          sf::st_union() |>
          sf::st_as_sf()
      }
    )
    sf::st_transform(tsa41,
      crs = "+proj=lcc +lat_1=49 +lat_2=77 +lat_0=0 +lon_0=-95 +datum=NAD83 +units=m")
  },

  studyAreaLarge = {
    sf::st_buffer(studyArea, dist = 20000)
  },

  packages = c("terra", "data.table", "reticulate", "bcdata", "sf", "dplyr"),

  options = list(
    spades.allowInitDuringSimInit = TRUE,
    reproducible.useCache         = TRUE
  )
)

mySim <- do.call(SpaDES.core::simInitAndSpades, out)
