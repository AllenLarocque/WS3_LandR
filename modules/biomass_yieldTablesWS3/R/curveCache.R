# loadCurveCache(), saveCurveCache(), diffDevTypes(): yield curve cache management

devTypeTupleKey <- function(speciesCode, site_quality, ecoregion) {
  paste(speciesCode, site_quality, ecoregion, sep = "|")
}

diffDevTypes <- function(currentTuples, cachedKeys) {
  currentTuples[!currentTuples %in% cachedKeys]
}

loadCurveCache <- function(cachePath) {
  if (!file.exists(cachePath)) return(list())
  readRDS(cachePath)
}

saveCurveCache <- function(ws3YieldCurves, cachePath) {
  saveRDS(ws3YieldCurves, cachePath)
  invisible(cachePath)
}
