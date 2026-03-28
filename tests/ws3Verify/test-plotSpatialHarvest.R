library(testthat)
library(terra)

.testDir <- normalizePath(".")
.srcFile <- normalizePath(
  file.path(.testDir, "../../modules/ws3Verify/R/plotSpatialHarvest.R"),
  mustWork = FALSE
)
if (!file.exists(.srcFile)) .srcFile <- "modules/ws3Verify/R/plotSpatialHarvest.R"
source(.srcFile)

# Tiny 4-cell raster for testing
.make_rast <- function(vals = c(1, 0, 1, 0)) {
  r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2)
  terra::values(r) <- vals
  r
}

test_that("plotSpatialHarvest returns named list with annual and cumulative ggplots", {
  result <- plotSpatialHarvest(.make_rast(), .make_rast(c(2,0,3,1)), simYear = 2011)
  expect_type(result, "list")
  expect_named(result, c("annual", "cumulative"))
  expect_s3_class(result$annual, "ggplot")
  expect_s3_class(result$cumulative, "ggplot")
})

test_that("plotSpatialHarvest returns NULL annual when annualHarvestRast is NULL", {
  result <- plotSpatialHarvest(NULL, .make_rast(), simYear = 2011)
  expect_null(result$annual)
  expect_s3_class(result$cumulative, "ggplot")
})
