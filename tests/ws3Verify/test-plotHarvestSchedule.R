library(testthat)
library(data.table)

.testDir <- normalizePath(".")
.srcFile <- normalizePath(
  file.path(.testDir, "../../modules/ws3Verify/R/plotHarvestSchedule.R"),
  mustWork = FALSE
)
if (!file.exists(.srcFile)) .srcFile <- "modules/ws3Verify/R/plotHarvestSchedule.R"
source(.srcFile)

.make_schedule <- function() {
  data.table(
    period        = 1:5,
    vol_harvested = c(45000, 46200, 44800, 45500, 45100)
  )
}

test_that("plotHarvestSchedule returns a ggplot for valid schedule", {
  result <- plotHarvestSchedule(.make_schedule(), simYear = 2021)
  expect_s3_class(result, "ggplot")
})

test_that("plotHarvestSchedule returns annotated ggplot for NULL schedule", {
  result <- plotHarvestSchedule(NULL, simYear = 2021)
  expect_s3_class(result, "ggplot")
})

test_that("plotHarvestSchedule returns annotated ggplot for zero-row schedule", {
  result <- plotHarvestSchedule(.make_schedule()[0], simYear = 2021)
  expect_s3_class(result, "ggplot")
})
