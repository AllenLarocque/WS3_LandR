# devTypeTupleKey(), loadCurveCache(), saveCurveCache(), diffDevTypes(): yield curve cache management

devTypeTupleKey <- function(speciesCode, site_quality, ecoregion) {
  stopifnot(
    length(speciesCode) == 1L, !is.na(speciesCode),
    length(site_quality) == 1L, !is.na(site_quality),
    length(ecoregion) == 1L, !is.na(ecoregion)
  )
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
  dir.create(dirname(cachePath), recursive = TRUE, showWarnings = FALSE)
  saveRDS(ws3YieldCurves, cachePath)
  invisible(cachePath)
}
