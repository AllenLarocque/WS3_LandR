# helper-fixtures.R — shared mock data and setup for biomass_ws3Harvest tests
#
# testthat always evaluates helper files with wd = the test directory
# (modules/biomass_ws3Harvest/tests/testthat/).  All source() calls below
# are relative to that directory.
#
# Usage:
#   testthat::test_local("modules/biomass_ws3Harvest")   # from project root
#   devtools::test()                                      # from module root

library(data.table)
library(terra)

# devTypeTupleKey lives in the sibling module.
# ../../../biomass_yieldTablesWS3/R/ resolves correctly from tests/testthat/
source("../../../biomass_yieldTablesWS3/R/curveCache.R")

# Source this module's helpers — ../../R/ = modules/biomass_ws3Harvest/R/
source("../../R/inventoryBridge.R")
source("../../R/harvestBridge.R")
source("../../R/actionDispatch.R")
source("../../R/spatialBridge.R")

# TESTTHAT_WD — absolute path to the project root (4 levels up from tests/testthat/).
if (nchar(Sys.getenv("TESTTHAT_WD")) == 0L)
  Sys.setenv(TESTTHAT_WD = normalizePath(file.path(getwd(), "..", "..", "..", "..")))

# ── Mock data factories ──────────────────────────────────────────────────────

#' cohortData with site_quality column (post-binSiteQuality).
#' Columns match what buildWs3Inventory and applyClearcut expect.
mock_cohortData_binned <- function() {
  data.table(
    pixelGroup     = c(1L,         1L,         2L,         3L),
    speciesCode    = c("Pice_mar", "Pice_gla", "Pice_mar", "Pice_gla"),
    ecoregionGroup = c("ECO_1",    "ECO_1",    "ECO_2",    "ECO_1"),
    age            = c(50L,        30L,         80L,        10L),
    B              = c(5000L,      3000L,       8000L,      500L),
    aNPPAct        = c(100L,       80L,         120L,       20L),
    mortality      = c(50L,        30L,         60L,        5L),
    site_quality   = c("med",      "med",       "high",     "low")
  )
}

#' pixelArea: 250 m × 250 m cells = 6.25 ha each
mock_pixelArea <- function() {
  data.table(
    pixelGroup = c(1L, 2L, 3L),
    area_ha    = c(6.25, 6.25, 6.25)
  )
}

#' 3×3 SpatRaster for pixelGroupMap.
#' Cells 1–2 → pixelGroup 1, cells 3–4 → pixelGroup 2, cells 5–6 → pixelGroup 3, cells 7–9 → NA.
mock_pixelGroupMap <- function() {
  r <- terra::rast(nrows = 3L, ncols = 3L,
                   xmin = 0, xmax = 3, ymin = 0, ymax = 3,
                   crs = "EPSG:4326")
  terra::values(r) <- c(1L, 1L, 2L, 2L, 3L, 3L, NA_integer_, NA_integer_, NA_integer_)
  r
}

#' Harvest raster: listed cells set to 1L, rest NA.
mock_harvest_raster <- function(harvested_cells = 1L) {
  r <- terra::rast(nrows = 3L, ncols = 3L,
                   xmin = 0, xmax = 3, ymin = 0, ymax = 3,
                   crs = "EPSG:4326")
  vals <- rep(NA_integer_, 9L)
  vals[harvested_cells] <- 1L
  terra::values(r) <- vals
  r
}
