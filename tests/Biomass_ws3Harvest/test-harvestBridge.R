library(testthat)
library(data.table)
library(terra)

# testthat::test_file() sets cwd to the test file's directory.
# Navigate up two levels to the project root for the source() calls.
.testDir <- normalizePath(".")   # will be tests/Biomass_ws3Harvest/ under test_file()
.harvestBridge <- normalizePath(
  file.path(.testDir, "../../modules/Biomass_ws3Harvest/R/harvestBridge.R"),
  mustWork = FALSE
)
.actionDispatch <- normalizePath(
  file.path(.testDir, "../../modules/Biomass_ws3Harvest/R/actionDispatch.R"),
  mustWork = FALSE
)
if (!file.exists(.harvestBridge)) {
  # fallback for interactive use from project root
  .harvestBridge  <- "modules/Biomass_ws3Harvest/R/harvestBridge.R"
  .actionDispatch <- "modules/Biomass_ws3Harvest/R/actionDispatch.R"
}
# harvestBridge must be sourced before actionDispatch so applyClearcut is defined
source(.harvestBridge)
source(.actionDispatch)

test_that("applyClearcut zeros B for pixels in harvest raster", {
  cohortData <- data.table(
    pixelGroup = c(1L, 2L, 3L),
    speciesCode = "Pice_mar",
    age = c(80L, 60L, 40L),
    B   = c(15000L, 10000L, 5000L),
    mortality = 0L, aNPPAct = 0L
  )
  pixelGroupMap <- terra::rast(nrows = 3, ncols = 1, vals = c(1L, 2L, 3L))
  harvestRast   <- terra::rast(nrows = 3, ncols = 1, vals = c(1L, 1L, 0L))

  result <- applyHarvestAction("clearcut", harvestRast, cohortData, pixelGroupMap)
  expect_equal(result[pixelGroup == 1L]$B, 0L)
  expect_equal(result[pixelGroup == 2L]$B, 0L)
  expect_equal(result[pixelGroup == 3L]$B, 5000L)
})

test_that("applyClearcut sets mortality = original B before zeroing", {
  cohortData <- data.table(
    pixelGroup = 1L, speciesCode = "Pice_mar",
    age = 80L, B = 12000L, mortality = 0L, aNPPAct = 500L
  )
  pixelGroupMap <- terra::rast(nrows = 1, ncols = 1, vals = 1L)
  harvestRast   <- terra::rast(nrows = 1, ncols = 1, vals = 1L)

  result <- applyHarvestAction("clearcut", harvestRast, cohortData, pixelGroupMap)
  expect_equal(result$B, 0L)
  expect_equal(result$mortality, 12000L)  # mortality = original B
  expect_equal(result$aNPPAct, 0L)
})

test_that("applyClearcut does not modify cohortData in-place", {
  cohortData <- data.table(
    pixelGroup = 1L, speciesCode = "Pice_mar",
    age = 80L, B = 12000L, mortality = 0L, aNPPAct = 0L
  )
  pixelGroupMap <- terra::rast(nrows = 1, ncols = 1, vals = 1L)
  harvestRast   <- terra::rast(nrows = 1, ncols = 1, vals = 1L)

  result <- applyHarvestAction("clearcut", harvestRast, cohortData, pixelGroupMap)
  expect_equal(cohortData$B, 12000L)  # original unchanged
})

test_that("applyHarvestAction warns on unknown action code", {
  cohortData <- data.table(pixelGroup = 1L, B = 1000L)
  expect_warning(
    applyHarvestAction("selection_cut", terra::rast(), cohortData, terra::rast()),
    regexp = "unknown action"
  )
})

test_that("applyHarvestAction returns cohortData unchanged for unknown action", {
  cohortData <- data.table(pixelGroup = 1L, B = 1000L)
  result <- suppressWarnings(
    applyHarvestAction("selection_cut", terra::rast(), cohortData, terra::rast())
  )
  expect_equal(result$B, 1000L)
})

test_that("applyClearcut stops on invalid inputs", {
  expect_error(
    applyClearcut("not_a_raster", data.table(), terra::rast())
  )
})
