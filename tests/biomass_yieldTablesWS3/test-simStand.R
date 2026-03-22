library(testthat)
library(data.table)
library(mockery)

# testthat::test_file() sets cwd to the test file's directory.
# Navigate up two levels to the project root for the source() call.
.testDir <- normalizePath(".")   # will be tests/biomass_yieldTablesWS3/ under test_file()
.srcFile <- normalizePath(
  file.path(.testDir, "../../modules/biomass_yieldTablesWS3/R/simStand.R"),
  mustWork = FALSE
)
if (!file.exists(.srcFile)) {
  # fallback for interactive use from project root
  .srcFile <- "modules/biomass_yieldTablesWS3/R/simStand.R"
}
source(.srcFile)

# ── Helper: build a fake cohortData qs2 file for a given age ─────────────────

make_fake_qs_file <- function(age, B_value, path) {
  cd <- data.table(
    pixelGroup     = 1L,
    speciesCode    = "Pice_mar",
    age            = as.integer(age),
    B              = as.integer(B_value),
    ecoregionGroup = "eco1"
  )
  qs2::qs_save(cd, path)
  path
}

# ── Shared setup helper for simulateStand mock tests ─────────────────────────

make_simulateStand_inputs <- function() {
  list(
    species_dt = data.table(
      speciesCode    = "Pice_mar",
      maxB           = 35000L,
      maxANPP        = 700L,
      longevity      = 300L,
      mortalityshape = 25L,
      growthcurve    = 0.25,
      seeddispDist   = 100L,
      postfireregen  = "serotiny"
    ),
    speciesEcoregion_dt = data.table(
      speciesCode    = "Pice_mar",
      ecoregionGroup = "eco1",
      maxANPP        = 700L,
      maxB           = 35000L,
      establishprob  = 0.5
    )
  )
}

# ── Test 1: extractBByAge correctly reads B values from qs2 files ────────────

test_that("extractBByAge extracts correct B values from qs2 files", {
  tmp_dir <- tempfile("simStand_test_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  # Create fake output files: saveTime 0, 1, 2
  files <- vapply(0:2, function(yr) {
    p <- file.path(tmp_dir, sprintf("cohortData_year%d.qs2", yr))
    make_fake_qs_file(age = yr, B_value = yr * 100L, path = p)
  }, character(1))

  output_df <- data.frame(
    saveTime = 0:2,
    file     = files,
    stringsAsFactors = FALSE
  )

  result <- extractBByAge(output_df, maxAge = 2)

  expect_s3_class(result, "data.frame")
  expect_true(all(c("age", "B_gm2") %in% names(result)))
  expect_equal(nrow(result), 3)  # ages 0, 1, 2
  expect_equal(result$age, 0:2)
  expect_equal(result$B_gm2, c(0, 100, 200))
})

test_that("extractBByAge returns NA B_gm2 when a file is missing for a year", {
  tmp_dir <- tempfile("simStand_test_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  # Only create files for years 0 and 2 (skip year 1)
  p0 <- file.path(tmp_dir, "cohortData_year0.qs2")
  p2 <- file.path(tmp_dir, "cohortData_year2.qs2")
  make_fake_qs_file(age = 0L, B_value = 0L,   path = p0)
  make_fake_qs_file(age = 2L, B_value = 200L, path = p2)

  output_df <- data.frame(
    saveTime = c(0L, 2L),
    file     = c(p0, p2),
    stringsAsFactors = FALSE
  )

  result <- extractBByAge(output_df, maxAge = 2)

  expect_equal(nrow(result), 3)            # ages 0, 1, 2 always returned
  expect_true(is.na(result$B_gm2[result$age == 1]))
})

test_that("extractBByAge sums B across multiple cohorts in same pixelGroup", {
  tmp_dir <- tempfile("simStand_test_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  # Two cohorts at age 5 in same pixelGroup 1
  cd <- data.table(
    pixelGroup     = c(1L, 1L),
    speciesCode    = c("Pice_mar", "Pinu_ban"),
    age            = c(5L, 5L),
    B              = c(300L, 200L),
    ecoregionGroup = "eco1"
  )
  p5 <- file.path(tmp_dir, "cohortData_year5.qs2")
  qs2::qs_save(cd, p5)

  output_df <- data.frame(
    saveTime = 5L,
    file     = p5,
    stringsAsFactors = FALSE
  )

  result <- extractBByAge(output_df, maxAge = 5)

  # sum of B for ages 0..4 is NA, age 5 = 500
  expect_equal(result$B_gm2[result$age == 5], 500)
})

# ── Test 2: simulateStand return structure (using mock) ──────────────────────

test_that("simulateStand returns data.frame with age and B_gm2 columns (mocked)", {
  inputs <- make_simulateStand_inputs()
  maxAge <- 5L

  tmp_dir <- tempfile("simStand_mock_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  # Pre-create fake output files that extractBByAge will read
  # B values follow the formula: yr * 50L + 1L
  expected_B <- as.numeric(0:maxAge * 50L + 1L)
  fake_files <- vapply(0:maxAge, function(yr) {
    p <- file.path(tmp_dir, sprintf("cohortData_%04d.qs2", yr))
    cd <- data.table(
      pixelGroup     = 1L,
      speciesCode    = "Pice_mar",
      age            = as.integer(yr),
      B              = as.integer(yr * 50L + 1L),
      ecoregionGroup = "eco1"
    )
    qs2::qs_save(cd, p)
    p
  }, character(1))

  fake_outputs_df <- data.frame(
    objectName = "cohortData",
    saveTime   = 0:maxAge,
    file       = fake_files,
    stringsAsFactors = FALSE
  )

  # Create a fake SpaDES sim result
  fake_sim <- list(outputs = fake_outputs_df)

  # Create a fake Biomass_core directory so the download is skipped
  dir.create(file.path(tmp_dir, "Biomass_core"), showWarnings = FALSE)

  # Mock simInitAndSpades to avoid running a real SpaDES sim
  stub(simulateStand, "simInitAndSpades", function(...) fake_sim)

  result <- simulateStand(
    speciesCode      = "Pice_mar",
    site_quality     = "med",
    ecoregion        = "eco1",
    species          = inputs$species_dt,
    speciesEcoregion = inputs$speciesEcoregion_dt,
    maxAge           = maxAge,
    modulePath       = tmp_dir,
    outputPath       = tmp_dir
  )

  expect_s3_class(result, "data.frame")
  expect_true(all(c("age", "B_gm2") %in% names(result)))
  expect_equal(nrow(result), maxAge + 1L)  # ages 0..maxAge inclusive
  expect_equal(result$age, 0:maxAge)
  # verify exact B values match the mock data (also implicitly checks non-negativity)
  expect_equal(result$B_gm2, expected_B)
})

# ── Test 3: simulateStand clips maxAge to species longevity ─────────────────

test_that("simulateStand uses species longevity when maxAge > longevity (mocked)", {
  inputs <- make_simulateStand_inputs()
  # Override longevity to be short for this test
  inputs$species_dt[, longevity := 10L]

  tmp_dir <- tempfile("simStand_longevity_")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE))

  effective_max <- 10L  # min(300, 10) = 10

  fake_files <- vapply(0:effective_max, function(yr) {
    p <- file.path(tmp_dir, sprintf("cohortData_%04d.qs2", yr))
    cd <- data.table(
      pixelGroup     = 1L,
      speciesCode    = "Pice_mar",
      age            = as.integer(yr),
      B              = 1L,
      ecoregionGroup = "eco1"
    )
    qs2::qs_save(cd, p)
    p
  }, character(1))

  fake_outputs_df <- data.frame(
    objectName = "cohortData",
    saveTime   = 0:effective_max,
    file       = fake_files,
    stringsAsFactors = FALSE
  )
  fake_sim <- list(outputs = fake_outputs_df)

  # Create a fake Biomass_core directory so the download is skipped
  dir.create(file.path(tmp_dir, "Biomass_core"), showWarnings = FALSE)

  stub(simulateStand, "simInitAndSpades", function(...) fake_sim)

  result <- simulateStand(
    speciesCode      = "Pice_mar",
    site_quality     = "med",
    ecoregion        = "eco1",
    species          = inputs$species_dt,
    speciesEcoregion = inputs$speciesEcoregion_dt,
    maxAge           = 300L,       # > longevity
    modulePath       = tmp_dir,
    outputPath       = tmp_dir
  )

  # Should be clipped to longevity (10), so 11 rows: ages 0..10
  expect_equal(nrow(result), 11L)
  expect_equal(max(result$age), 10L)
})
