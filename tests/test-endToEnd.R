# tests/test-endToEnd.R
# End-to-end smoke test: 1 WS3 period, minimal sim
#
# Prerequisites:
#   - All R packages installed (SpaDES.core, SpaDES.project, terra, data.table, reticulate, ...)
#   - Python ws3 installed: pip install ws3
#   - TSA41 or a small studyArea accessible (requires bcdata + internet)
#
# To run a quick smoke test, set ws3PeriodLength and ws3Horizon to 1 in global.R first:
#   ws3PeriodLength <- 1L
#   ws3Horizon      <- 1L
#
# Then: source("tests/test-endToEnd.R")

source("global.R")   # runs the simulation

library(testthat)

test_that("end-to-end: ws3YieldCurves produced for at least one dev type", {
  expect_gt(length(mySim$ws3YieldCurves), 0)
  # Each curve must be a data.frame with age and vol_m3ha columns
  first_curve <- mySim$ws3YieldCurves[[1]]
  expect_true(all(c("age", "vol_m3ha") %in% names(first_curve)))
  expect_gt(nrow(first_curve), 0)
})

test_that("end-to-end: ws3HarvestSchedule was produced", {
  expect_false(is.null(mySim$ws3HarvestSchedule))
  expect_true(is.data.frame(mySim$ws3HarvestSchedule))
})

test_that("end-to-end: harvest raster is non-empty", {
  hrast <- mySim$rstCurrentHarvest
  if (is.null(hrast)) {
    skip("rstCurrentHarvest is NULL — ForestRaster spatial allocation not yet wired up")
  }
  expect_gt(sum(terra::values(hrast) == 1L, na.rm = TRUE), 0)
})

test_that("end-to-end: cohortData B values changed after harvest", {
  if (is.null(mySim$rstCurrentHarvest)) {
    skip("No harvest raster — skipping cohortData B check")
  }
  expect_true(any(mySim$cohortData$B == 0L))
})
