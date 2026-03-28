library(testthat)
library(data.table)
library(terra)

.testDir <- normalizePath(".")
.srcFile <- normalizePath(
  file.path(.testDir, "../../modules/ws3Verify/R/plotAgeMap.R"),
  mustWork = FALSE
)
if (!file.exists(.srcFile)) .srcFile <- "modules/ws3Verify/R/plotAgeMap.R"
source(.srcFile)

# pixelGroupMap: 4 pixels, two pixel groups
.make_pgmap <- function() {
  r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2)
  terra::values(r) <- c(1L, 1L, 2L, NA_integer_)
  r
}

# cohortData: two pixel groups, multiple cohorts with B-weighted ages
.make_cohorts <- function() {
  data.table(
    pixelGroup = c(1L, 1L, 2L),
    age        = c(80L, 60L, 30L),
    B          = c(10000L, 4000L, 5000L)
  )
}

test_that("plotAgeMap returns a ggplot", {
  result <- plotAgeMap(.make_cohorts(), .make_pgmap(), simYear = 2021)
  expect_s3_class(result, "ggplot")
})

test_that("plotAgeMap returns annotated ggplot when cohortData is empty", {
  result <- plotAgeMap(.make_cohorts()[0], .make_pgmap(), simYear = 2021)
  expect_s3_class(result, "ggplot")
  expect_length(result$layers, 1L)
  expect_s3_class(result$layers[[1]]$geom, "GeomText")
})

test_that("plotAgeMap respects maxAge cap", {
  # cohorts have ages 80 and 60; cap at 50 should clip the 80
  result <- plotAgeMap(.make_cohorts(), .make_pgmap(), simYear = 2021, maxAge = 50)
  expect_s3_class(result, "ggplot")
  built <- ggplot2::ggplot_build(result)
  age_vals <- built$data[[1]]$lyr1
  expect_lte(max(age_vals, na.rm = TRUE), 50)
})
