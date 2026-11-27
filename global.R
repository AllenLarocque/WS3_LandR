## WS3_LandR: LandR grows the forest, biomass_yieldTablesWS3 turns LandR growth into
## merchantable-volume yield curves, ws3 (Python, through reticulate) solves the harvest schedule,
## and biomass_ws3Harvest applies the cuts back to LandR's cohorts. ws3Verify draws diagnostics.
##
## Run from this folder: Rscript global.R. Set `doRun <- FALSE` first to stop after setupProject().
## The settings are the `defaultDots` below. To change one for a run, define it before sourcing
## this file, e.g.  .units <- "TSA41"; .inwardBuffer <- 0; source("global.R").
if (!exists("doRun")) doRun <- TRUE

repos <- c(PE = "https://predictiveecology.r-universe.dev", getOption("repos"))
if (!requireNamespace("SpaDES.project", quietly = TRUE)) {
  install.packages("SpaDES.project", repos = repos)
}
options(SpaDES.project.strict = TRUE) # stop on errors rather than continue unevaluated

out <- SpaDES.project::setupProject(
  name = "WS3_LandR",
  useGit = "sub",  # modules become git submodules of this repo, so they can be branched and committed in
  .units = .units,
  .inwardBuffer = .inwardBuffer,
  .res = .res,
  .baseYear = .baseYear,
  .periodLength = .periodLength,
  .horizon = .horizon,
  ## Defaults reproduce the spring-2026 study area: the RIA (BC TSAs 08, 16, 24, 40, 41)
  ## shrunk 150 km inward
  defaultDots = list(.units = c("TSA08", "TSA16", "TSA24", "TSA40", "TSA41"),
                     .inwardBuffer = 150000,  # m; the study area is the union of .units shrunk by this
                     .res = 250,              # m; resolution of rasterToMatch(Large)
                     .baseYear = 2011L,
                     .periodLength = 10L,     # years between ws3 solves
                     .horizon = 10L),         # ws3 planning periods
  paths = list(
    projectPath = getwd(),
    ## the project's own library (house rule; the container's home is not the place for it)
    packagePath = file.path(getwd(), "packages"),
    modulePath  = file.path(getwd(), "modules"),
    inputPath   = file.path(getwd(), "inputs"),
    outputPath  = file.path(getwd(), "outputs"),
    cachePath   = file.path(getwd(), "cache")
  ),
  modules = c("PredictiveEcology/Biomass_borealDataPrep@development",
              ## fit growthcurve, mortalityshape and maxANPP to permanent sample plots, as in FIIS;
              ## without them the spruces keep the raw LANDIS growthcurve = 1 and barely regrow
              "PredictiveEcology/Biomass_speciesFactorial@development",
              "PredictiveEcology/Biomass_speciesParameters@development",
              "PredictiveEcology/Biomass_core@development",
              "AllenLarocque/biomass_yieldTablesWS3@main",
              "AllenLarocque/biomass_ws3Harvest@main",
              "AllenLarocque/ws3Verify@main"),
  times = list(start = .baseYear, end = .baseYear + .periodLength * .horizon),
  packages = c("PredictiveEcology/SpaDES.core@development (>= 3.2.1.9053)",
               "PredictiveEcology/reproducible@development (>= 3.2.1.9085)", # Drive login from $GOOGLEDRIVE_AUTH, else anonymous
               "PredictiveEcology/LandR@development",
               "PredictiveEcology/timberSupply@development (>= 0.0.0.9004)", # bcManagementUnit(), for the study area
               "reticulate (>= 1.41)",  # py_require()
               ## qs2 (Biomass_speciesFactorial) >= 0.4.0 links RcppParallel >= 6.1.1 (oneTBB). Upgrading
               ## RcppParallel 5 -> 6 in place breaks packages compiled against the old TBB (stringfish,
               ## older qs2: "undefined symbol ... tbb8internal"); rebuild them from source if that happens.
               "RcppParallel (>= 6.1.1)", "qs2 (>= 0.4.0)",
               "googledrive", "bcdata", "terra", "sf", "data.table",
               "testthat"),  # to run the module tests
  options = list(
    repos = repos,
    reproducible.destinationPath = paths$inputPath,
    spades.allowInitDuringSimInit = TRUE,
    reproducible.useCache = TRUE
  ),
  params = list(
    .globals = list(ws3PeriodLength = .periodLength),
    ## FIIS settings (Dominique Caron, 2026-10-02); balanceGrowth lets spruce, fir and pine grow side by side
    Biomass_speciesParameters = list(.plots = "png", standAgesForFitting = c(0L, 100L),
                                     balanceGrowth = TRUE),
    biomass_yieldTablesWS3 = list(maxSimAge = 300L, siteQualityBins = c(0.33, 0.67)),
    biomass_ws3Harvest = list(ws3Horizon = .horizon, ws3BaseYear = .baseYear,
                              ws3MinHarvestAge = 40L, ws3Solver = "highs")
  ),
  ## objects; each may use the ones above it
  studyArea = {
    sa <- lapply(.units, function(u) reproducible::Cache(timberSupply::bcManagementUnit, u))
    inwardBuffer(do.call(rbind, sa), dist = .inwardBuffer, res = .res)
  },
  studyAreaLarge = sf::st_buffer(studyArea, dist = 20000),
  rasterToMatchLarge = {
    v <- terra::vect(studyAreaLarge)
    terra::rasterize(v, terra::rast(v, res = .res), field = 1)
  },
  rasterToMatch = {
    v <- terra::vect(studyArea)
    terra::crop(rasterToMatchLarge, v) |> terra::mask(v)
  },
  ## NFI 2001 kNN stand age, on the rasterToMatch grid: Biomass_borealDataPrep works on
  ## rasterToMatch (its rasterToMatch_biomassParam), and its own reprojection of a mismatched
  ## standAgeMap never runs, because LandR::.compareRas() errors on a mismatch by default
  standAgeMap = {
    sam <- reproducible::prepInputs(
      url = paste0("http://ftp.maps.canada.ca/pub/nrcan_rncan/Forests_Foret/",
                   "canada-forests-attributes_attributs-forests-canada/",
                   "2001-attributes_attributs-2001/",
                   "NFI_MODIS250m_2001_kNN_Structure_Stand_Age_v1.tif"),
      destinationPath = paths$inputPath,
      to = rasterToMatch)
    attr(sam, "imputedPixID") <- integer(0)
    sam
  },
  functions = "R/studyArea.R"
)

## ws3 runs in a Python environment that reticulate builds with uv on first use
reticulate::py_require("ws3")

## Temporary workaround for a LandR::makeEcoregionMap bug, see R/patchLandR.R
source("R/patchLandR.R")
patchMakeEcoregionMap()

if (isTRUE(doRun)) {
  sim <- SpaDES.core::simInitAndSpades2(out)
}
