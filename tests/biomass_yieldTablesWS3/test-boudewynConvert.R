library(testthat)

# testthat::test_file() sets cwd to the test file's directory.
# Navigate up two levels to the project root for the source() call.
.testDir <- normalizePath(".")   # will be tests/biomass_yieldTablesWS3/ under test_file()
.srcFile <- normalizePath(
  file.path(.testDir, "../../modules/biomass_yieldTablesWS3/R/boudewynConvert.R"),
  mustWork = FALSE
)
if (!file.exists(.srcFile)) {
  # fallback for interactive use from project root
  .srcFile <- "modules/biomass_yieldTablesWS3/R/boudewynConvert.R"
}
source(.srcFile)

test_that("loadSpeciesLookup returns data.frame with required columns", {
  lut <- loadSpeciesLookup()
  expect_true(all(c("speciesCode", "canfi_species", "juris_id", "ecozone_default") %in% names(lut)))
  expect_gt(nrow(lut), 0)
})

test_that("lookupBoudewynKeys returns correct keys for known species", {
  keys <- lookupBoudewynKeys("Pice_mar", juris_id = "BC", ecozone = 9)
  expect_equal(keys$canfi_species, 101)
  expect_equal(keys$juris_id, "BC")
  expect_equal(keys$ecozone, 9)
})

test_that("lookupBoudewynKeys uses ecozone_default when ecozone not supplied", {
  keys <- lookupBoudewynKeys("Pice_mar", juris_id = "BC")
  expect_equal(keys$ecozone, 9)   # ecozone_default for Pice_mar BC
})

test_that("lookupBoudewynKeys errors on unknown species", {
  expect_error(lookupBoudewynKeys("Unknown_spp", juris_id = "BC"), regexp = "No Boudewyn")
})
