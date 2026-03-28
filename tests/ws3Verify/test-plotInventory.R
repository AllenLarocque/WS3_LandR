library(testthat)
library(data.table)

.testDir <- normalizePath(".")
.srcFile <- normalizePath(
  file.path(.testDir, "../../modules/ws3Verify/R/plotInventory.R"),
  mustWork = FALSE
)
if (!file.exists(.srcFile)) .srcFile <- "modules/ws3Verify/R/plotInventory.R"
source(.srcFile)

.make_inventory <- function() {
  data.table(
    devTypeKey   = c("Pice_mar|med|ECO_1", "Pice_mar|high|ECO_1", "Pinu_ban|low|ECO_2"),
    age_class    = c(8L, 5L, 10L),
    area_ha      = c(250.0, 180.0, 95.0),
    harvestable  = c(TRUE, TRUE, FALSE),
    site_quality = c("med", "high", "low")
  )
}

test_that("plotInventory returns a ggplot", {
  result <- plotInventory(.make_inventory(), simYear = 2021)
  expect_s3_class(result, "ggplot")
})

test_that("plotInventory returns annotated ggplot for zero-row inventory", {
  empty <- .make_inventory()[0]
  result <- plotInventory(empty, simYear = 2021)
  expect_s3_class(result, "ggplot")
})

test_that("plotInventory returns annotated ggplot for NULL inventory", {
  result <- plotInventory(NULL, simYear = 2021)
  expect_s3_class(result, "ggplot")
})
