# modules/biomass_yieldTablesWS3/biomass_yieldTablesWS3.R
defineModule(sim, list(
  name        = "biomass_yieldTablesWS3",
  description = "Generate and cache WS3-compatible m3/ha yield curves per LandR development type",
  keywords    = c("LandR", "WS3", "yield curves", "Boudewyn"),
  authors     = person("Allen", "Larocque"),
  childModules = character(0),
  version     = list(biomass_yieldTablesWS3 = "0.1.0"),
  timeframe   = as.POSIXlt(c(NA, NA)),
  timeunit    = "year",
  citation    = list(),
  documentation = list(),
  reqdPkgs    = list("data.table", "terra"),
  parameters  = bindrows(
    defineParameter("ws3PeriodLength", "integer", 10L, 1L, 100L,
                    "Years between WS3 planning solves"),
    defineParameter("maxSimAge", "integer", 300L, 50L, 500L,
                    "Maximum stand age for yield curve simulation"),
    defineParameter("siteQualityBins", "numeric", c(0.33, 0.67), 0, 1,
                    "Thresholds for low/med/high site quality bins")
  ),
  inputObjects = bindrows(
    expectsInput("cohortData",       "data.table", "LandR cohort data",         "Biomass_core"),
    expectsInput("species",          "data.table", "LandR species parameters",  "Biomass_borealDataPrep"),
    expectsInput("speciesEcoregion", "data.table", "Species x ecoregion params","Biomass_borealDataPrep"),
    expectsInput("pixelGroupMap",    "SpatRaster", "Pixel group raster",        "Biomass_core")
  ),
  outputObjects = bindrows(
    createsOutput("ws3YieldCurves", "list",
                  "Named list of yield curves keyed by dev type tuple string")
  )
))

doEvent.biomass_yieldTablesWS3 <- function(sim, eventTime, eventType) {
  switch(eventType,
    init = {
      # source helper files
      .sourceHelper <- function(f) source(file.path(dirname(currentModule(sim)), "R", f))
      .sourceHelper("siteQuality.R")
      .sourceHelper("curveCache.R")
      .sourceHelper("boudewynConvert.R")
      .sourceHelper("simStand.R")

      cachePath <- file.path(outputPath(sim), "ws3YieldCurves.rds")
      sim$ws3YieldCurves <- loadCurveCache(cachePath)

      sim <- scheduleEvent(sim, start(sim), "biomass_yieldTablesWS3", "updateCurves",
                           eventPriority = 1)   # priority 1 = runs before ws3Plan (priority 2)
    },
    updateCurves = {
      sim <- .updateCurves(sim)
      sim <- scheduleEvent(sim, time(sim) + P(sim)$ws3PeriodLength,
                           "biomass_yieldTablesWS3", "updateCurves", eventPriority = 1)
    }
  )
  invisible(sim)
}

.updateCurves <- function(sim) {
  # 1. Derive species-level max ANPP ceiling
  speciesMaxANPP <- sim$speciesEcoregion[, .(globalMaxANPP = max(maxANPP)),
                                          by = speciesCode]

  # 2. Bin site quality
  cd <- binSiteQuality(sim$cohortData, sim$speciesEcoregion, speciesMaxANPP,
                       bins = P(sim)$siteQualityBins)

  # 3. Extract unique dev type tuples
  devTypes <- unique(cd[, .(speciesCode, site_quality, ecoregionGroup)])
  currentKeys <- devTypes[, devTypeTupleKey(speciesCode, site_quality, ecoregionGroup),
                           by = seq_len(nrow(devTypes))]$V1

  # 4. Diff against cache
  newKeys <- diffDevTypes(currentKeys, names(sim$ws3YieldCurves))
  newDevTypes <- devTypes[currentKeys %in% newKeys]

  if (nrow(newDevTypes) > 0) {
    message("biomass_yieldTablesWS3: simulating yield curves for ",
            nrow(newDevTypes), " new development type(s)")

    for (i in seq_len(nrow(newDevTypes))) {
      dt <- newDevTypes[i]
      key <- devTypeTupleKey(dt$speciesCode, dt$site_quality, dt$ecoregionGroup)

      ageB <- simulateStand(
        speciesCode      = dt$speciesCode,
        site_quality     = dt$site_quality,
        ecoregion        = dt$ecoregionGroup,
        species          = sim$species,
        speciesEcoregion = sim$speciesEcoregion,
        maxAge           = P(sim)$maxSimAge,
        modulePath       = modulePath(sim)
      )

      boudKeys <- lookupBoudewynKeys(dt$speciesCode, juris_id = "BC")
      curve <- boudewynBiomassToVol(ageB,
        canfi_species = boudKeys$canfi_species,
        juris_id      = boudKeys$juris_id,
        ecozone       = boudKeys$ecozone
      )
      sim$ws3YieldCurves[[key]] <- curve
    }

    cachePath <- file.path(outputPath(sim), "ws3YieldCurves.rds")
    saveCurveCache(sim$ws3YieldCurves, cachePath)
  } else {
    message("biomass_yieldTablesWS3: all dev type curves already cached")
  }
  sim
}
