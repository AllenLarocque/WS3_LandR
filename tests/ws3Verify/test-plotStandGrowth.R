library(testthat)
library(data.table)

.testDir <- normalizePath(".")
.srcFile <- normalizePath(
  file.path(.testDir, "../../modules/ws3Verify/R/plotStandGrowth.R"),
  mustWork = FALSE
)
if (!file.exists(.srcFile)) .srcFile <- "modules/ws3Verify/R/plotStandGrowth.R"
source(.srcFile)

.make_curves <- function() {
  list(
    "Pice_mar|med|ECO_1" = data.frame(
      age      = 0:5,
      vol_m3ha = c(0, 0, 1, 5, 15, 30),
      B_gm2    = c(0, 100, 500, 2000, 5000, 8000)
    )
  )
}

test_that("plotStandGrowth returns a ggplot", {
  result <- plotStandGrowth(.make_curves(), simYear = 2011)
  expect_s3_class(result, "ggplot")
})

test_that("plotStandGrowth returns annotated ggplot when curves list is empty", {
  result <- plotStandGrowth(list(), simYear = 2011)
  expect_s3_class(result, "ggplot")
})

test_that("plotStandGrowth returns annotated ggplot when B_gm2 column is absent (stale cache)", {
  stale <- list(
    "Pice_mar|med|ECO_1" = data.frame(age = 0:5, vol_m3ha = c(0,0,1,5,15,30))
  )
  result <- plotStandGrowth(stale, simYear = 2011)
  expect_s3_class(result, "ggplot")
})
