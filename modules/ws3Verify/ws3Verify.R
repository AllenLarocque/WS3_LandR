# modules/ws3Verify/ws3Verify.R
# Read-only verification module — fires six verification plots each planning period.
# See docs/superpowers/specs/2026-03-27-ws3verify-design.md for full design.

defineModule(sim, list(
  name        = "ws3Verify",
  description = "Verification plots for WS3-LandR: yield curves, stand growth, inventory, harvest schedule, spatial harvest maps, stand age map",
  keywords    = c("LandR", "WS3", "verification", "plots"),
  authors     = person("Allen", "Larocque"),
  childModules = character(0),
  version     = list(ws3Verify = "0.1.0"),
  timeframe   = as.POSIXlt(c(NA, NA)),
  timeunit    = "year",
  citation    = list(),
  documentation = list(),
  reqdPkgs    = list("ggplot2", "data.table", "terra", "tidyterra", "viridis"),
  parameters  = bindrows(
    defineParameter(".plots", "character", "png", NA, NA,
                    "Output format for Plots(). Set to NA to disable all plots."),
    defineParameter("ws3MinHarvestAge", "integer", 40L, 0L, 300L,
                    "Minimum operability age — must match biomass_ws3Harvest.")
  ),
  inputObjects = bindrows(
    expectsInput("ws3YieldCurves",     "list",       "Yield curves per dev type",           "biomass_yieldTablesWS3"),
    expectsInput("cohortData",         "data.table", "LandR cohort data",                   "Biomass_core"),
    expectsInput("speciesEcoregion",   "data.table", "Species x ecoregion parameters",      "Biomass_borealDataPrep"),
    expectsInput("species",            "data.table", "Species parameters",                  "Biomass_borealDataPrep"),
    expectsInput("ws3HarvestSchedule", "data.table", "WS3 harvest schedule (may be NULL)",  "biomass_ws3Harvest"),
    expectsInput("pixelGroupMap",      "SpatRaster", "Pixel group raster",                  "Biomass_core"),
    expectsInput("rstCurrentHarvest",  "SpatRaster", "Current harvest disturbance raster",  "biomass_ws3Harvest")
  ),
  outputObjects = bindrows()
))

doEvent.ws3Verify <- function(sim, eventTime, eventType) {
  switch(eventType,
    init = {
      lapply(c("plotYieldCurves.R", "plotStandGrowth.R",
               "plotInventory.R",   "plotHarvestSchedule.R",
               "plotSpatialHarvest.R", "plotAgeMap.R"), function(f)
        source(file.path(modulePath(sim), currentModule(sim), "R", f)))

      # Source helpers from sibling modules (inventory bridge needs binSiteQuality + buildWs3Inventory)
      source(file.path(modulePath(sim), "biomass_yieldTablesWS3", "R", "siteQuality.R"))
      source(file.path(modulePath(sim), "biomass_yieldTablesWS3", "R", "curveCache.R"))
      source(file.path(modulePath(sim), "biomass_ws3Harvest",     "R", "inventoryBridge.R"))

      sim$.ws3VerifyCumHarvest <- NULL

      # Schedule plotYieldCurves first (same priority as plotHarvest; order matters)
      sim <- scheduleEvent(sim, start(sim), "ws3Verify", "plotYieldCurves", eventPriority = 3)
      sim <- scheduleEvent(sim, start(sim), "ws3Verify", "plotHarvest",     eventPriority = 3)
    },

    plotYieldCurves = {
      sim <- scheduleEvent(sim,
        time(sim) + params(sim)$.globals$ws3PeriodLength,
        "ws3Verify", "plotYieldCurves", eventPriority = 3)

      if (!is.na(P(sim)$.plots)) {
        Plots(plotYieldCurves(sim$ws3YieldCurves, time(sim)),
              fn       = identity,
              type     = P(sim)$.plots,
              filename = paste0("yieldCurves_year_", time(sim)))
        Plots(plotStandGrowth(sim$ws3YieldCurves, time(sim)),
              fn       = identity,
              type     = P(sim)$.plots,
              filename = paste0("standGrowth_year_", time(sim)))
      }
    },

    plotHarvest = {
      sim <- scheduleEvent(sim,
        time(sim) + params(sim)$.globals$ws3PeriodLength,
        "ws3Verify", "plotHarvest", eventPriority = 3)

      if (!is.na(P(sim)$.plots)) {
        # ── Build inventory table (event handler owns sim$ access) ──────────────
        speciesMaxANPP <- sim$speciesEcoregion[,
          .(globalMaxANPP = max(maxANPP, na.rm = TRUE)), by = speciesCode]
        cd <- binSiteQuality(sim$cohortData, sim$speciesEcoregion, speciesMaxANPP,
                             bins = c(0.33, 0.67))
        cellArea_ha <- terra::cellSize(sim$pixelGroupMap, unit = "ha")
        pgVals      <- terra::values(sim$pixelGroupMap, mat = FALSE)
        areaVals    <- terra::values(cellArea_ha,       mat = FALSE)
        pixelArea   <- data.table::data.table(pixelGroup = pgVals, area_ha = areaVals)
        pixelArea   <- pixelArea[!is.na(pixelGroup),
                                 .(area_ha = sum(area_ha)), by = pixelGroup]

        ws3Inventory <- buildWs3Inventory(
          cd, pixelArea,
          periodLength  = params(sim)$.globals$ws3PeriodLength,
          minHarvestAge = P(sim)$ws3MinHarvestAge
        )
        ws3Inventory[, site_quality := sub(".*\\|(.*)\\|.*", "\\1", devTypeKey)]

        # ── Plot C — Inventory ───────────────────────────────────────────────────
        Plots(plotInventory(ws3Inventory, time(sim)),
              fn = identity, type = P(sim)$.plots,
              filename = paste0("inventory_year_", time(sim)))

        # ── Plot D — Harvest Schedule ────────────────────────────────────────────
        Plots(plotHarvestSchedule(sim$ws3HarvestSchedule, time(sim)),
              fn = identity, type = P(sim)$.plots,
              filename = paste0("harvestSchedule_year_", time(sim)))

        # ── Plot E — Spatial Harvest ─────────────────────────────────────────────
        if (!is.null(sim$rstCurrentHarvest)) {
          if (is.null(sim$.ws3VerifyCumHarvest)) {
            sim$.ws3VerifyCumHarvest <- sim$rstCurrentHarvest
          } else {
            sim$.ws3VerifyCumHarvest <- sim$.ws3VerifyCumHarvest +
                                        (sim$rstCurrentHarvest > 0)
          }
        }
        tifPath    <- file.path(outputPath(sim), "harvest",
                                paste0("clearcut_", time(sim), ".tif"))
        annualRast <- if (file.exists(tifPath)) terra::rast(tifPath) else NULL

        if (!is.null(sim$.ws3VerifyCumHarvest)) {
          harvestPlots <- plotSpatialHarvest(annualRast, sim$.ws3VerifyCumHarvest, time(sim))
          if (!is.null(harvestPlots$annual))
            Plots(harvestPlots$annual, fn = identity, type = P(sim)$.plots,
                  filename = paste0("annualHarvest_year_", time(sim)))
          Plots(harvestPlots$cumulative, fn = identity, type = P(sim)$.plots,
                filename = paste0("cumulativeHarvest_year_", time(sim)))
        }

        # ── Plot F — Age Map ─────────────────────────────────────────────────────
        Plots(plotAgeMap(sim$cohortData, sim$pixelGroupMap, time(sim)),
              fn = identity, type = P(sim)$.plots,
              filename = paste0("ageMap_year_", time(sim)))
      }
    }
  )
  invisible(sim)
}
