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
  expect_length(result$layers, 1L)
  expect_s3_class(result$layers[[1]]$geom, "GeomText")
})

test_that("plotHarvestSchedule returns annotated ggplot for zero-row schedule", {
  result <- plotHarvestSchedule(.make_schedule()[0], simYear = 2021)
  expect_s3_class(result, "ggplot")
  expect_length(result$layers, 1L)
  expect_s3_class(result$layers[[1]]$geom, "GeomText")
})

test_that("plotHarvestSchedule omits reference line when vol_harvested[1] is NA", {
  sched_na <- .make_schedule()
  sched_na$vol_harvested[1L] <- NA_real_
  expect_warning(result <- plotHarvestSchedule(sched_na, simYear = 2021), NA)
  expect_s3_class(result, "ggplot")
  # No geom_hline layer when ref_vol is NA
  layer_classes <- vapply(result$layers, function(l) class(l$geom)[1], character(1))
  expect_false("GeomHline" %in% layer_classes)
})
