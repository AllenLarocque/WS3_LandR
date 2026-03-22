# simulateStand(): run Biomass_core for a single-cohort stand, return age-biomass trajectory
# extractBByAge(): parse saved cohortData outputs to a data.frame(age, B_gm2)

# ── extractBByAge ─────────────────────────────────────────────────────────────
#
# Reads the qs2-saved cohortData files produced by a SpaDES sim and extracts
# total stand biomass (summed across all cohorts in pixelGroup 1) at each year.
#
# Arguments:
#   outputFiles  data.frame with columns: saveTime (integer/numeric), file (character)
#   maxAge       integer — the simulation end time
#
# Returns: data.frame(age = 0:maxAge, B_gm2 = numeric) where B_gm2 is NA for
#          years whose output file is missing.
#
extractBByAge <- function(outputFiles, maxAge) {
  ages <- seq(0L, as.integer(maxAge), by = 1L)

  B_vals <- vapply(ages, function(yr) {
    row <- outputFiles[outputFiles$saveTime == yr, , drop = FALSE]
    if (nrow(row) == 0L || !file.exists(row$file[1])) {
      return(NA_real_)
    }
    cd <- qs2::qs_read(row$file[1])
    # sum B across all cohorts in pixelGroup 1
    sum(cd$B[cd$pixelGroup == 1L], na.rm = FALSE)
  }, numeric(1))

  data.frame(age = ages, B_gm2 = B_vals, stringsAsFactors = FALSE)
}

# ── simulateStand ─────────────────────────────────────────────────────────────
#
# Runs a minimal SpaDES simulation using only Biomass_core (no dispersal, no
# fire, no seed rain) for a single cohort from age 0 to maxAge (or species
# longevity, whichever is smaller).
#
# Arguments:
#   speciesCode       character(1)   — e.g. "Pice_mar"
#   site_quality      character(1)   — "low", "med", or "high" (informational;
#                                      ecologically captured via speciesEcoregion)
#   ecoregion         character(1)   — ecoregionGroup label, e.g. "eco1"
#   species           data.table     — Biomass_core species table (one row per spp)
#   speciesEcoregion  data.table     — Biomass_core speciesEcoregion table
#   maxAge            integer        — maximum simulation age (default 300)
#   modulePath        character(1)   — directory where SpaDES modules live
#                                      (Biomass_core will be downloaded here if absent)
#   outputPath        character(1)   — directory for sim output files
#
# Returns: data.frame(age, B_gm2) — one row per year from 0 to effective maxAge.
#
simulateStand <- function(speciesCode, site_quality, ecoregion,
                          species, speciesEcoregion,
                          maxAge = 300L,
                          modulePath  = file.path(tempdir(), "spades_modules"),
                          outputPath  = file.path(tempdir(), "simStand_outputs")) {

  # ── resolve effective simulation end time ──────────────────────────────────
  spp_row    <- species[species$speciesCode == speciesCode, ]
  longevity  <- if (nrow(spp_row) > 0) spp_row$longevity[1] else maxAge
  end_time   <- min(as.integer(maxAge), as.integer(longevity))

  # ── ensure Biomass_core is present ────────────────────────────────────────
  if (!dir.exists(file.path(modulePath, "Biomass_core"))) {
    message("simulateStand: downloading Biomass_core to ", modulePath)
    dir.create(modulePath, showWarnings = FALSE, recursive = TRUE)
    SpaDES.core::downloadModule(
      name = "Biomass_core",
      path = modulePath,
      repo = "PredictiveEcology/Biomass_core@main"
    )
  }

  # ── output directory ───────────────────────────────────────────────────────
  dir.create(outputPath, showWarnings = FALSE, recursive = TRUE)

  # ── build single-pixel spatial objects ────────────────────────────────────
  ecoregionMap <- terra::rast(nrows = 1, ncols = 1, vals = 1L)
  terra::crs(ecoregionMap) <- "EPSG:4326"

  pixelGroupMap <- terra::rast(nrows = 1, ncols = 1, vals = 1L)
  terra::crs(pixelGroupMap) <- "EPSG:4326"

  # ── build minimal data.tables ──────────────────────────────────────────────
  ecoregion_dt <- data.table::data.table(
    ecoregionGroup = ecoregion,
    active         = "yes"
  )

  cohortData <- data.table::data.table(
    pixelGroup     = 1L,
    ecoregionGroup = ecoregion,
    speciesCode    = speciesCode,
    age            = 0L,
    B              = 1L,            # must be >= 1 for Biomass_core growth
    mortality      = 0L,
    aNPPAct        = 0L
  )

  # Filter speciesEcoregion to the relevant ecoregion
  secoregion_sub <- speciesEcoregion[
    speciesEcoregion$speciesCode    == speciesCode &
    speciesEcoregion$ecoregionGroup == ecoregion, ]

  # ── outputs spec: save cohortData at every year ────────────────────────────
  save_times <- seq(0L, end_time, by = 1L)
  sim_outputs <- expand.grid(
    objectName    = "cohortData",
    saveTime      = save_times,
    eventPriority = 1,
    fun           = "qs2::qs_save",
    stringsAsFactors = FALSE
  )
  sim_outputs$file <- file.path(
    outputPath,
    sprintf("cohortData_%04d.qs2", as.integer(sim_outputs$saveTime))
  )

  # ── SpaDES parameters ──────────────────────────────────────────────────────
  parameters <- list(
    .globals = list(
      sppEquivCol = "LandR"
    ),
    Biomass_core = list(
      ".plotInitialTime"  = NA,
      ".plots"            = NULL,
      ".saveInitialTime"  = NULL,
      ".useCache"         = FALSE,
      ".useParallel"      = 1L,
      "vegLeadingProportion" = 0,
      "calcSummaryBGM"    = NULL,
      "seedingAlgorithm"  = "noSeeding",
      "minCohortBiomass"  = 1L
    )
  )

  paths <- list(
    modulePath = modulePath,
    outputPath = outputPath,
    inputPath  = outputPath,
    cachePath  = file.path(outputPath, "cache")
  )

  objects <- list(
    cohortData    = cohortData,
    pixelGroupMap = pixelGroupMap,
    ecoregionMap  = ecoregionMap,
    ecoregion     = ecoregion_dt,
    species       = species,
    speciesEcoregion = secoregion_sub
  )

  times <- list(start = 0, end = end_time)

  # ── run Biomass_core ───────────────────────────────────────────────────────
  sim_result <- simInitAndSpades(
    times   = times,
    params  = parameters,
    modules = "Biomass_core",
    objects = objects,
    paths   = paths,
    outputs = sim_outputs
  )

  # ── extract biomass trajectory ─────────────────────────────────────────────
  # sim_result$outputs is a data.frame with columns: objectName, saveTime, file, ...
  out_files <- sim_result$outputs
  out_files  <- out_files[out_files$objectName == "cohortData", ]

  extractBByAge(out_files, maxAge = end_time)
}
