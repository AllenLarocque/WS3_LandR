library(testthat)
library(data.table)

# testthat::test_file() sets cwd to the test file's directory.
# Navigate up two levels to the project root for the source() calls.
.testDir <- normalizePath(".")   # will be tests/Biomass_ws3Harvest/ under test_file()
.curveCache <- normalizePath(
  file.path(.testDir, "../../modules/biomass_yieldTablesWS3/R/curveCache.R"),
  mustWork = FALSE
)
.invBridge <- normalizePath(
  file.path(.testDir, "../../modules/Biomass_ws3Harvest/R/inventoryBridge.R"),
  mustWork = FALSE
)
if (!file.exists(.curveCache)) {
  # fallback for interactive use from project root
  .curveCache <- "modules/biomass_yieldTablesWS3/R/curveCache.R"
  .invBridge  <- "modules/Biomass_ws3Harvest/R/inventoryBridge.R"
}
source(.curveCache)   # for devTypeTupleKey
source(.invBridge)

test_that("buildWs3Inventory returns correct area by dev type and age class", {
  cohortData <- data.table(
    pixelGroup    = c(1L, 1L, 2L),
    speciesCode   = c("Pice_mar", "Pinu_ban", "Pice_mar"),
    ecoregionGroup = "eco1",
    age           = c(80L, 80L, 40L),
    B             = c(15000L, 8000L, 5000L),
    site_quality  = c("med", "med", "low")
  )
  pixelArea <- data.table(pixelGroup = c(1L, 2L), area_ha = c(2.0, 1.0))

  result <- buildWs3Inventory(cohortData, pixelArea, periodLength = 10L)

  expect_true(is.data.table(result))
  expect_true(all(c("devTypeKey", "age_class", "area_ha") %in% names(result)))
  # Pice_mar|med|eco1, age_class 8 (age 80 / 10) should have area 2
  pice_med <- result[devTypeKey == "Pice_mar|med|eco1" & age_class == 8L]
  expect_equal(pice_med$area_ha, 2.0)
})

test_that("buildWs3Inventory sets harvestable flag correctly", {
  cohortData <- data.table(
    pixelGroup = c(1L, 2L), speciesCode = "Pice_mar",
    ecoregionGroup = "eco1", age = c(20L, 80L), B = c(2000L, 15000L),
    site_quality = "med"
  )
  pixelArea <- data.table(pixelGroup = c(1L, 2L), area_ha = c(5.0, 5.0))
  result <- buildWs3Inventory(cohortData, pixelArea, periodLength = 10L,
                               minHarvestAge = 40L)
  expect_true("harvestable" %in% names(result))
  # age 20 < 40 -> harvestable = FALSE
  expect_false(result[age_class == 2L]$harvestable)
  # age 80 >= 40 -> harvestable = TRUE
  expect_true(result[age_class == 8L]$harvestable)
})

test_that("buildWs3Inventory does not double-count area for multiple cohorts in same pixelGroup+devType", {
  # Two cohorts in the same pixel group with the same devTypeKey should contribute
  # area only once (via unique() deduplication), not twice.
  cohortData <- data.table(
    pixelGroup    = c(1L, 1L),  # same pixel group, two cohorts
    speciesCode   = "Pice_mar",
    ecoregionGroup = "eco1",
    age           = c(80L, 80L),
    B             = c(10000L, 5000L),
    site_quality  = "med"
  )
  pixelArea <- data.table(pixelGroup = 1L, area_ha = 3.0)
  result <- buildWs3Inventory(cohortData, pixelArea, periodLength = 10L)
  # Correct: area = 3.0 (unique deduplication prevents double-counting)
  expect_equal(result$area_ha[1], 3.0)
})
