# modules/Biomass_ws3Harvest/Biomass_ws3Harvest.R
defineModule(sim, list(
  name        = "Biomass_ws3Harvest",
  description = "Couple LandR with WS3: inventory bridge, WS3 solve, harvest application",
  keywords    = c("LandR", "WS3", "harvest", "wood supply"),
  authors     = person("Allen", "Larocque"),
  childModules = character(0),
  version     = list(Biomass_ws3Harvest = "0.1.0"),
  timeframe   = as.POSIXlt(c(NA, NA)),
  timeunit    = "year",
  citation    = list(),
  documentation = list(),
  reqdPkgs    = list("data.table", "terra", "reticulate"),
  parameters  = bindrows(
    defineParameter("ws3Horizon",       "integer", 10L,   1L, 50L,
                    "Number of WS3 planning periods"),
    defineParameter("ws3BaseYear",      "integer", 2011L, 1900L, 2100L,
                    "Calendar year for WS3 period 0"),
    defineParameter("ws3MinHarvestAge", "integer", 40L,   0L, 300L,
                    "Minimum stand age eligible for harvest"),
    defineParameter("ws3Solver",        "character", "highs", NA, NA,
                    "WS3 solver backend: highs, gurobi, or pulp")
  ),
  inputObjects = bindrows(
    expectsInput("cohortData",       "data.table", "LandR cohort data",          "Biomass_core"),
    expectsInput("pixelGroupMap",    "SpatRaster", "Pixel group raster",         "Biomass_core"),
    expectsInput("biomassMap",       "SpatRaster", "Total biomass raster",       "Biomass_core"),
    expectsInput("species",          "data.table", "Species parameters",         "Biomass_borealDataPrep"),
    expectsInput("speciesEcoregion", "data.table", "Species x ecoregion params", "Biomass_borealDataPrep"),
    expectsInput("ws3YieldCurves",   "list",       "Yield curves per dev type",  "biomass_yieldTablesWS3")
  ),
  outputObjects = bindrows(
    createsOutput("rstCurrentHarvest",  "SpatRaster", "Harvest disturbance raster (consumed by Biomass_core)"),
    createsOutput("cohortData",         "data.table", "Modified in-place: harvested cohorts zeroed"),
    createsOutput("ws3HarvestSchedule", "data.table", "WS3 harvest schedule for reporting")
  )
))

doEvent.Biomass_ws3Harvest <- function(sim, eventTime, eventType) {
  switch(eventType,
    init = {
      # source helper files (harvestBridge before actionDispatch — applyClearcut needed in registry)
      lapply(c("inventoryBridge.R", "harvestBridge.R", "actionDispatch.R"), function(f)
        source(file.path(dirname(currentModule(sim)), "R", f)))

      # also source siteQuality from biomass_yieldTablesWS3
      source(file.path(dirname(currentModule(sim)), "..", "biomass_yieldTablesWS3",
                       "R", "siteQuality.R"))
      source(file.path(dirname(currentModule(sim)), "..", "biomass_yieldTablesWS3",
                       "R", "curveCache.R"))

      # verify Python ws3 is importable
      tryCatch(
        reticulate::import("ws3"),
        error = function(e) stop(
          "Biomass_ws3Harvest: cannot import Python 'ws3'. ",
          "Run: pip install ws3\nOriginal error: ", e$message
        )
      )
      ws3 <- reticulate::import("ws3")

      # initialise ForestModel
      sim$.ws3fm <- ws3$forest$ForestModel(
        model_name    = "LandR_WS3",
        base_year     = as.integer(P(sim)$ws3BaseYear),
        horizon       = as.integer(P(sim)$ws3Horizon),
        period_length = as.integer(params(sim)$.globals$ws3PeriodLength)
      )
      sim$.ws3fm$add_action("clearcut", reticulate::py_eval("lambda *a, **kw: None"))

      # ForestRaster for spatial allocation (initialised in ws3Plan once we have full inventory)
      sim$.ws3fr <- NULL

      sim <- scheduleEvent(sim, start(sim), "Biomass_ws3Harvest", "ws3Plan",
                           eventPriority = 2)   # after updateCurves (priority 1)
    },
    ws3Plan = {
      sim <- .ws3Plan(sim)
      sim <- scheduleEvent(sim, time(sim) + params(sim)$.globals$ws3PeriodLength,
                           "Biomass_ws3Harvest", "ws3Plan", eventPriority = 2)
    }
  )
  invisible(sim)
}

.ws3Plan <- function(sim) {
  ws3 <- reticulate::import("ws3")
  fm  <- sim$.ws3fm

  # ── 1. Derive pixel areas ───────────────────────────────────────────────────
  cellArea_ha <- terra::cellSize(sim$pixelGroupMap, unit = "ha")
  pgVals      <- terra::values(sim$pixelGroupMap, mat = FALSE)
  areaVals    <- terra::values(cellArea_ha, mat = FALSE)
  pixelArea   <- data.table::data.table(pixelGroup = pgVals, area_ha = areaVals)
  pixelArea   <- pixelArea[!is.na(pixelGroup), .(area_ha = sum(area_ha)), by = pixelGroup]

  # ── 2. Bin site quality (use species$maxANPP as denominator) ────────────────
  speciesMaxANPP <- sim$species[, .(speciesCode, globalMaxANPP = maxANPP)]
  cd <- binSiteQuality(sim$cohortData, sim$speciesEcoregion, speciesMaxANPP,
                       bins = c(0.33, 0.67))

  # ── 3. Build inventory table ────────────────────────────────────────────────
  inv <- buildWs3Inventory(cd, pixelArea,
    periodLength  = params(sim)$.globals$ws3PeriodLength,
    minHarvestAge = P(sim)$ws3MinHarvestAge
  )

  # ── 4. Load inventory and yield curves into WS3 ─────────────────────────────
  for (key in names(sim$ws3YieldCurves)) {
    curve <- sim$ws3YieldCurves[[key]]
    if (is.null(fm$dtypes[[key]])) fm$create_dtype(key)
    invRows <- inv[devTypeKey == key]
    for (i in seq_len(nrow(invRows))) {
      fm$dtypes[[key]]$area(invRows$age_class[i], 0L, invRows$area_ha[i])
    }
    fm$dtypes[[key]]$add_ycomp("vol",
      reticulate::r_to_py(data.frame(
        x = curve$age, y = curve$vol_m3ha
      ))
    )
  }

  # ── 5. Solve ────────────────────────────────────────────────────────────────
  p <- fm$add_problem(
    T = as.integer(P(sim)$ws3Horizon),
    coeff_funcs = list(vol = reticulate::py_eval(
      "lambda fm, path: fm.dtypes[path[0]].ycomp('vol')(path[1])"
    ))
  )
  p$solve(P(sim)$ws3Solver)

  if (p$status() != "optimal") {
    warning("Biomass_ws3Harvest: WS3 solve status '", p$status(),
            "' at year ", time(sim), " — skipping harvest this period")
    return(sim)
  }

  # ── 6. Allocate spatial harvest schedule ────────────────────────────────────
  outDir <- file.path(outputPath(sim), "harvest")
  dir.create(outDir, showWarnings = FALSE, recursive = TRUE)

  # ForestRaster.allocate_schedule writes one GeoTIFF per action per year
  if (!is.null(sim$.ws3fr)) {
    sim$.ws3fr$allocate_schedule(outDir)
  } else {
    message("Biomass_ws3Harvest: ForestRaster not initialised — skipping spatial allocation")
  }

  # ── 7. Record schedule for reporting ────────────────────────────────────────
  sim$ws3HarvestSchedule <- data.table::as.data.table(p$solution())

  # ── 8. Apply harvest to cohortData year by year ─────────────────────────────
  period <- seq(time(sim), time(sim) + params(sim)$.globals$ws3PeriodLength - 1)
  for (yr in period) {
    tifPath <- file.path(outDir, sprintf("clearcut_%d.tif", yr))
    if (!file.exists(tifPath)) {
      message("Biomass_ws3Harvest: no clearcut GeoTIFF for year ", yr, " — skipping")
      next
    }
    hrast            <- terra::rast(tifPath)
    sim$cohortData   <- applyHarvestAction("clearcut", hrast,
                                            sim$cohortData, sim$pixelGroupMap)
    sim$rstCurrentHarvest <- hrast
  }
  sim
}
