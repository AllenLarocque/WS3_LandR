library(testthat)
library(data.table)

.testDir <- normalizePath(".")
.srcFile <- normalizePath(
  file.path(.testDir, "../../modules/ws3Verify/R/plotYieldCurves.R"),
  mustWork = FALSE
)
if (!file.exists(.srcFile)) .srcFile <- "modules/ws3Verify/R/plotYieldCurves.R"
source(.srcFile)

# Minimal ws3YieldCurves fixture: two dev types
.make_curves <- function() {
  list(
    "Pice_mar|med|ECO_1" = data.frame(
      age      = 0:10,
      vol_m3ha = c(0, 0, 1, 5, 15, 30, 55, 80, 100, 115, 125),
      B_gm2    = c(0, 100, 500, 2000, 5000, 8000, 10000, 11500, 12500, 13000, 13200)
    ),
    "Pice_mar|high|ECO_1" = data.frame(
      age      = 0:10,
      vol_m3ha = c(0, 0, 2, 8, 22, 45, 75, 105, 130, 148, 160),
      B_gm2    = c(0, 150, 700, 2800, 6500, 10000, 12500, 14000, 15000, 15500, 15700)
    )
  )
}

test_that("plotYieldCurves returns a ggplot", {
  result <- plotYieldCurves(.make_curves(), simYear = 2011)
  expect_s3_class(result, "ggplot")
})

test_that("plotYieldCurves works with a single dev type", {
  single <- .make_curves()[1]
  result <- plotYieldCurves(single, simYear = 2011)
  expect_s3_class(result, "ggplot")
})

test_that("plotYieldCurves returns ggplot when ws3YieldCurves is empty list", {
  result <- plotYieldCurves(list(), simYear = 2011)
  expect_s3_class(result, "ggplot")
  expect_length(result$layers, 1L)
  expect_s3_class(result$layers[[1]]$geom, "GeomText")
})
