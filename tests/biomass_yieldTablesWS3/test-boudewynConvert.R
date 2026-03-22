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

test_that("boudewynBiomassToVol returns data.frame with age and vol_m3ha", {
  # Black spruce (Pice_mar, canfi=101, BC, ecozone=9) — synthetic biomass trajectory
  ageB <- data.frame(
    age   = seq(0, 100, by = 10),
    B_gm2 = c(0, 200, 800, 2000, 4000, 6000, 8000, 10000, 12000, 13000, 13500)
  )
  result <- boudewynBiomassToVol(ageB, canfi_species = 101L, juris_id = "BC", ecozone = 9L)
  expect_true(is.data.frame(result))
  expect_true(all(c("age", "vol_m3ha") %in% names(result)))
  expect_equal(nrow(result), nrow(ageB))
  expect_equal(result$vol_m3ha[1], 0)   # age 0, B=0 → vol=0
  expect_true(all(result$vol_m3ha >= 0))
})

test_that("boudewynBiomassToVol volume generally increases with biomass", {
  ageB <- data.frame(
    age   = 0:5,
    B_gm2 = c(0, 1000, 3000, 6000, 9000, 12000)
  )
  result <- boudewynBiomassToVol(ageB, canfi_species = 101L, juris_id = "BC", ecozone = 9L)
  # more biomass should generally produce more volume
  expect_gt(result$vol_m3ha[6], result$vol_m3ha[3])
})

test_that("boudewynBiomassToVol errors on unknown canfi_species", {
  ageB <- data.frame(age = 0:2, B_gm2 = c(0, 1000, 5000))
  expect_error(
    boudewynBiomassToVol(ageB, canfi_species = 9999L, juris_id = "BC", ecozone = 9L),
    regexp = "No Boudewyn"
  )
})
