library(testthat)
library(data.table)

# Source from the project root
source("modules/biomass_yieldTablesWS3/R/siteQuality.R")

test_that("binSiteQuality assigns low/med/high based on maxANPP ratio", {
  speciesEcoregion <- data.table(
    speciesCode = c("Pice_mar", "Pice_mar", "Pinu_ban"),
    ecoregionGroup = c("eco1", "eco2", "eco1"),
    maxANPP = c(300, 600, 400)
  )
  speciesMaxANPP <- data.table(
    speciesCode = c("Pice_mar", "Pinu_ban"),
    globalMaxANPP = c(900, 800)
  )
  cohortData <- data.table(
    pixelGroup = 1:3,
    speciesCode = c("Pice_mar", "Pice_mar", "Pinu_ban"),
    ecoregionGroup = c("eco1", "eco2", "eco1"),
    age = c(50, 50, 50),
    B = c(10000, 10000, 10000)
  )
  result <- binSiteQuality(cohortData, speciesEcoregion, speciesMaxANPP, bins = c(0.33, 0.67))
  expect_true("site_quality" %in% names(result))
  expect_true(all(result$site_quality %in% c("low", "med", "high")))
  # 400/800 = 0.50 → med
  expect_equal(result[speciesCode == "Pinu_ban"]$site_quality, "med")
})

test_that("binSiteQuality handles missing ecoregion gracefully", {
  speciesEcoregion <- data.table(
    speciesCode = "Pice_mar", ecoregionGroup = "eco1", maxANPP = 300
  )
  speciesMaxANPP <- data.table(speciesCode = "Pice_mar", globalMaxANPP = 900)
  cohortData <- data.table(
    pixelGroup = 1, speciesCode = "Pice_mar",
    ecoregionGroup = "eco_MISSING", age = 50, B = 10000
  )
  expect_warning(
    result <- binSiteQuality(cohortData, speciesEcoregion, speciesMaxANPP),
    regexp = "ecoregion"
  )
  expect_true("site_quality" %in% names(result))
  expect_equal(result$site_quality, "low")   # missing ecoregion always bins as "low"
})

test_that("binSiteQuality does not modify the input cohortData", {
  speciesEcoregion <- data.table(
    speciesCode = "Pice_mar", ecoregionGroup = "eco1", maxANPP = 300
  )
  speciesMaxANPP <- data.table(speciesCode = "Pice_mar", globalMaxANPP = 900)
  cohortData <- data.table(
    pixelGroup = 1L, speciesCode = "Pice_mar",
    ecoregionGroup = "eco1", age = 50L, B = 10000L
  )
  original_cols <- copy(names(cohortData))
  binSiteQuality(cohortData, speciesEcoregion, speciesMaxANPP)
  expect_equal(names(cohortData), original_cols)
})
