# modules/biomass_ws3Harvest/biomass_ws3Harvest.R
defineModule(sim, list(
  name        = "biomass_ws3Harvest",
  description = "Couple LandR with WS3: inventory bridge, WS3 solve, harvest application",
  keywords    = c("LandR", "WS3", "harvest", "wood supply"),
  authors     = person("Allen", "Larocque"),
  childModules = character(0),
  version     = list(biomass_ws3Harvest = "0.1.0"),
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

doEvent.biomass_ws3Harvest <- function(sim, eventTime, eventType) {
  switch(eventType,
    init = {
      # source helper files (harvestBridge before actionDispatch — applyClearcut needed in registry)
      lapply(c("inventoryBridge.R", "harvestBridge.R", "actionDispatch.R"), function(f)
        source(file.path(modulePath(sim), currentModule(sim), "R", f)))

      # also source siteQuality from biomass_yieldTablesWS3
      source(file.path(modulePath(sim), "biomass_yieldTablesWS3", "R", "siteQuality.R"))
      source(file.path(modulePath(sim), "biomass_yieldTablesWS3", "R", "curveCache.R"))

      # verify Python ws3 is importable
      tryCatch(
        reticulate::import("ws3"),
        error = function(e) stop(
          "biomass_ws3Harvest: cannot import Python 'ws3'. ",
          "Run: pip install ws3\nOriginal error: ", e$message
        )
      )
      ws3 <- reticulate::import("ws3")

      # initialise ForestModel
      ws3ModelPath <- file.path(outputPath(sim), "ws3")
      if (!dir.exists(ws3ModelPath)) dir.create(ws3ModelPath, recursive = TRUE)
      sim$.ws3fm <- ws3$forest$ForestModel(
        model_name    = "LandR_WS3",
        model_path    = ws3ModelPath,
        base_year     = as.integer(P(sim)$ws3BaseYear),
        horizon       = as.integer(P(sim)$ws3Horizon),
        period_length = as.integer(params(sim)$.globals$ws3PeriodLength)
      )
      # Register 3 placeholder themes (speciesCode, site_quality, ecoregion) before
      # adding any actions. nthemes() must equal len(dtype_key) = 3 or ws3 will
      # raise IndexError: tuple index out of range when applying actions.
      sim$.ws3fm$`_themes` <- reticulate::py_eval("[{}, {}, {}]")

      # Register "clearcut" as a harvest action (is_harvest=True) with a minimum
      # age operability constraint, following the spades_ws3 bootstrap_actions pattern.
      # Also register "null" as the grow-in-place action via add_null_action().
      # acodes passed to add_problem must include both.
      py_main <- reticulate::import_main()
      py_main$`_ws3fm_init`          <- sim$.ws3fm
      py_main$`_ws3_min_harvest_age` <- as.integer(P(sim)$ws3MinHarvestAge)
      reticulate::py_run_string("
import ws3.forest as _ws3f_mod
_fm   = _ws3fm_init
_mask = tuple(['?'] * _fm.nthemes())
_oe   = '_age >= %d and _age <= %d' % (_ws3_min_harvest_age, _fm.max_age)
_tgt  = [(_mask, 1.0, None, None, None, None, None)]
_fm.actions['clearcut']     = _ws3f_mod.Action('clearcut', targetage=0, is_harvest=True)
_fm.oper_expr['clearcut']   = {_mask: _oe}
_fm.transitions['clearcut'] = {_mask: {'': _tgt}}
_fm.add_null_action()   # registers 'null' grow-in-place action
del _fm, _ws3fm_init
")

      # ── ForestRaster (spatial harvest allocator) ─────────────────────────────
      # TODO: initialise ws3$spatial$ForestRaster here once the rasterized
      # inventory GeoTIFF (3-layer: theme hash, age, block ID) is available.
      #
      # ForestRaster requires:
      #   hdt_map      — dict mapping raster hash values → dev type tuples
      #   hdt_func     — hash function encoding dev type tuples → integer
      #   src_path     — path to 3-layer input inventory GeoTIFF
      #   snk_path     — output directory for disturbance GeoTIFFs
      #   acode_map    — dict of disturbance codes → output filename prefixes
      #   forestmodel  — the ForestModel instance (sim$.ws3fm)
      #   base_year, period_length, horizon
      #
      # See: https://github.com/UBC-FRESH/ws3/blob/main/ws3/spatial.py
      #
      # Until ForestRaster is wired up, ws3Plan will skip spatial allocation
      # and log a warning per period.
      sim$.ws3fr <- NULL

      sim <- scheduleEvent(sim, start(sim), "biomass_ws3Harvest", "ws3Plan",
                           eventPriority = 2)   # after updateCurves (priority 1)
    },
    ws3Plan = {
      sim <- .ws3Plan(sim)
      sim <- scheduleEvent(sim, time(sim) + params(sim)$.globals$ws3PeriodLength,
                           "biomass_ws3Harvest", "ws3Plan", eventPriority = 2)
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

  # ── 2. Bin site quality (use max maxANPP across ecoregions per species as ceiling) ──
  speciesMaxANPP <- sim$speciesEcoregion[, .(globalMaxANPP = max(maxANPP, na.rm = TRUE)),
                                          by = speciesCode]
  cd <- binSiteQuality(sim$cohortData, sim$speciesEcoregion, speciesMaxANPP,
                       bins = c(0.33, 0.67))

  # ── 3. Build inventory table ────────────────────────────────────────────────
  inv <- buildWs3Inventory(cd, pixelArea,
    periodLength  = params(sim)$.globals$ws3PeriodLength,
    minHarvestAge = P(sim)$ws3MinHarvestAge
  )

  # ── 4. Load inventory and yield curves into WS3 ─────────────────────────────
  core      <- reticulate::import("ws3.core")
  zip_lists <- reticulate::py_eval("lambda a, v: list(zip(a, v))")
  # ws3 dtype keys are tuples of theme strings, not flat pipe-joined strings.
  # match_mask() uses key[ti] integer indexing, which requires a tuple.
  # reticulate::tuple(...) requires individual args, not a vector — use do.call
  to_dtkey <- function(key) do.call(reticulate::tuple, as.list(strsplit(key, "|", fixed = TRUE)[[1]]))

  # Python-side dtype guard: keeps the 'key in dict' check entirely in Python to
  # avoid reticulate bool-conversion issues. Returns True only for newly created
  # dtypes so the caller knows whether to attach a yield curve.
  reticulate::py_run_string("
def _ws3_ensure_dtype(fm, dtkey):
    if dtkey not in fm.dtypes:
        fm.create_dtype_fromkey(dtkey)
        return True   # newly created — caller should add ycomp
    return False      # already existed
")
  ensure_dtype <- reticulate::py_eval("_ws3_ensure_dtype")

  currentPeriod <- as.integer(
    (time(sim) - P(sim)$ws3BaseYear) / params(sim)$.globals$ws3PeriodLength
  )

  for (key in names(sim$ws3YieldCurves)) {
    curve_data <- sim$ws3YieldCurves[[key]]
    dtkey      <- to_dtkey(key)   # Python tuple e.g. ('Pice_mar', 'med', 'ECO_1')

    # Create dtype and attach yield curve on first encounter only
    if (reticulate::py_to_r(ensure_dtype(fm, dtkey))) {
      ages     <- as.integer(curve_data$age)
      vols     <- as.numeric(curve_data$vol_m3ha)
      pts      <- zip_lists(reticulate::r_to_py(ages), reticulate::r_to_py(vols))
      ws3_curve <- core$Curve(key,
        points        = pts,
        type          = "a",
        period_length = fm$period_length,
        xmax          = fm$max_age)
      fm$dt(dtkey)$add_ycomp("a", "vol", ws3_curve)
    }

    # Load current-period inventory areas (always, even for existing dtypes)
    invRows <- inv[devTypeKey == key]
    for (i in seq_len(nrow(invRows))) {
      fm$dt(dtkey)$area(currentPeriod, invRows$age_class[i], invRows$area_ha[i])
    }
  }

  # Register 'vol' in fm$ynames so compile_product() can substitute it.
  # add_ycomp() on a dtype does NOT update fm$ynames; compile_product() checks
  # fm$ynames before doing the token substitution, so without this line it
  # eval()s the literal string 'vol' and raises NameError.
  fm$ynames$add("vol")

  # Propagate actions/transitions to all dtypes, then reset simulation state
  # so initialize_areas() builds the period-0 area accounting from current inventory.
  # Both steps mirror the spades_ws3 bootstrap_forestmodel + simulate_harvest pattern.
  fm$compile_actions()
  fm$reset()

  # ── 5. Solve ────────────────────────────────────────────────────────────────
  ws3solver <- tolower(P(sim)$ws3Solver)

  # Objective (z): maximise total harvested volume using fm.is_harvest() so the
  # check respects ws3's action registry (is_harvest=True on 'clearcut').
  # fm.compile_product() evaluates the named ycomp expression at the correct age,
  # matching the spades_ws3 cmp_c_z pattern.
  reticulate::py_run_string("
from functools import partial as _partial

def _lndr_z(fm, path, expr='vol'):
    result = 0.
    for t, n in enumerate(path, start=1):
        d = n.data()
        if fm.is_harvest(d['acode']):
            result += fm.compile_product(t, expr, d['acode'], [d['dtk']], d['age'], coeff=False)
    return result

def _lndr_cflw(fm, path, expr='vol', mask=None):
    result = {}
    for t, n in enumerate(path, start=1):
        d = n.data()
        if mask and not fm.match_mask(mask, d['dtk']): continue
        if fm.is_harvest(d['acode']):
            result[t] = fm.compile_product(t, expr, d['acode'], [d['dtk']], d['age'], coeff=False)
    return result
")
  z_fn    <- reticulate::py_eval("_partial(_lndr_z,    expr='vol')")
  cflw_fn <- reticulate::py_eval("_partial(_lndr_cflw, expr='vol')")

  # Even-flow constraint: allow up to 5% deviation between adjacent periods.
  # Built in Python to ensure integer period keys and tuple (epsilon_dict, lag)
  # format that ws3.forest.ForestModel.add_problem() expects.
  py_main <- reticulate::import_main()
  py_main$`_ws3_horizon` <- as.integer(P(sim)$ws3Horizon)
  reticulate::py_run_string("
_cflw_e  = {'cflw_vol': ({t: 0.05 for t in range(1, _ws3_horizon + 1)}, 1)}
_acodes  = ['null', 'clearcut']
")
  cflw_e_py <- reticulate::py_eval("_cflw_e")
  acodes_py <- reticulate::py_eval("_acodes")
  ws3opt    <- reticulate::import("ws3.opt")

  ws3LogPath <- file.path(outputPath(sim), "ws3_python_error.log")
  p <- tryCatch(
    fm$add_problem(
      name        = "harvest",
      coeff_funcs = reticulate::r_to_py(list(z = z_fn, cflw_vol = cflw_fn)),
      cflw_e      = cflw_e_py,
      acodes      = acodes_py,
      sense       = ws3opt$SENSE_MAXIMIZE,
      solver      = ws3solver,
      verbose     = TRUE
    ),
    error = function(e) {
      reticulate::py_run_string(sprintf("
import traceback as _tb, os
_ws3_tb = ''.join(_tb.format_exc())
os.makedirs('%s', exist_ok=True)
with open('%s', 'w') as _f:
    _f.write('add_problem error\\n' + _ws3_tb)
", outputPath(sim), ws3LogPath))
      message("Python traceback from add_problem:\n",
              reticulate::py_eval("_ws3_tb"))
      stop(e)
    }
  )
  tryCatch(
    p$solve(),
    error = function(e) {
      reticulate::py_run_string(sprintf("
import traceback as _tb, os
_ws3_tb = ''.join(_tb.format_exc())
os.makedirs('%s', exist_ok=True)
with open('%s', 'w') as _f:
    _f.write('solve error\\n' + _ws3_tb)
", outputPath(sim), ws3LogPath))
      message("Python traceback from solve:\n",
              reticulate::py_eval("_ws3_tb"))
      stop(e)
    }
  )

  if (p$status() != "optimal") {
    warning("biomass_ws3Harvest: WS3 solve status '", p$status(),
            "' at year ", time(sim), " — skipping harvest this period")
    return(sim)
  }

  # ── 6. Allocate spatial harvest schedule ────────────────────────────────────
  outDir <- file.path(outputPath(sim), "harvest")
  dir.create(outDir, showWarnings = FALSE, recursive = TRUE)

  # ForestRaster.allocate_schedule writes one GeoTIFF per action per year.
  # ForestRaster requires a pre-built rasterized inventory and hdt_map/hdt_func
  # (see TODO in init block). Until those are wired up, spatial allocation is skipped.
  if (!is.null(sim$.ws3fr)) {
    sim$.ws3fr$allocate_schedule(outDir)
  } else {
    warning("biomass_ws3Harvest: ForestRaster not initialised — spatial harvest allocation ",
            "skipped for period at year ", time(sim), ". See TODO in init block.")
  }

  # ── 7. Record schedule for reporting ────────────────────────────────────────
  sim$ws3HarvestSchedule <- data.table::as.data.table(p$solution())

  # ── 8. Apply harvest to cohortData year by year ─────────────────────────────
  period <- seq(time(sim), time(sim) + params(sim)$.globals$ws3PeriodLength - 1)
  for (yr in period) {
    tifPath <- file.path(outDir, sprintf("clearcut_%d.tif", yr))
    if (!file.exists(tifPath)) {
      message("biomass_ws3Harvest: no clearcut GeoTIFF for year ", yr, " — skipping")
      next
    }
    hrast            <- terra::rast(tifPath)
    sim$cohortData   <- applyHarvestAction("clearcut", hrast,
                                            sim$cohortData, sim$pixelGroupMap)
    sim$rstCurrentHarvest <- hrast
  }
  sim
}
