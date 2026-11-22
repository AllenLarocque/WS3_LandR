## Temporary workaround for a LandR::makeEcoregionMap bug (spring 2026), carried over unchanged
## from the original global.R. It overwrites the function inside the LandR namespace, so it
## changes results relative to unpatched LandR. The fix belongs in LandR as its own PR; drop this
## file once that is merged.
##
## Bug: the function copies ecoregionFiles$ecoregionMap (non-NA for all study-area pixels), then
## only updates active-group pixels, leaving inactive-group and filtered-out pixels with their
## original non-NA values. This makes the Biomass_core assertion
## is.na(ecoregionMap) == is.na(pixelGroupMap) fail.
## Fix: (1) filter truePixelData by pixelIndex so only cohortData pixels remain,
##      (2) initialise the output raster to all-NA before assigning values.
patchMakeEcoregionMap <- function() {
  fixed_fn <- function(ecoregionFiles, pixelCohortData) {
    truePixelData <- as.data.table(ecoregionFiles$ecoregionMap, cells = TRUE)
    setnames(truePixelData, old = "cell", new = "pixelIndex")
    truePixelData[, `:=`(mapcode, as.integer(mapcode))]
    truePixelData <- truePixelData[ecoregionFiles$ecoregion, on = c("mapcode")]
    # original filter: by group only → includes pixels removed from cohortData
    # fixed filter:    by group AND pixelIndex → exact match with pixelGroupMap
    truePixelData <- truePixelData[
      ecoregionGroup %in% pixelCohortData$ecoregionGroup &
      pixelIndex     %in% pixelCohortData$pixelIndex
    ]
    # Some cohortData pixels (e.g. fire/LCC34-36) may have ecoregionGroups but
    # are not in the ecoregion raster → NA in ecoregionMap but non-NA in pixelGroupMap.
    # Borrow group metadata from any existing pixel in the same group.
    allCohortPix <- unique(pixelCohortData[, .(pixelIndex, ecoregionGroup)])
    missingPix   <- allCohortPix[!pixelIndex %in% truePixelData$pixelIndex]
    if (nrow(missingPix) > 0) {
      groupMeta <- unique(truePixelData[, .(ecoregionGroup, landcover, ecoregionName)])
      missingPix <- groupMeta[missingPix, on = "ecoregionGroup", nomatch = NA]
      # fallback: use first available row for any groups with no representative
      if (anyNA(missingPix$landcover)) {
        fb <- groupMeta[1L]
        missingPix[is.na(landcover), `:=`(landcover     = fb$landcover,
                                           ecoregionName = fb$ecoregionName)]
      }
      truePixelData <- rbindlist(list(truePixelData, missingPix), use.names = TRUE, fill = TRUE)
    }
    message("makeEcoregionMap [patched]: final truePixelData pixels: ", nrow(truePixelData),
            " | cohortData unique pixels: ", nrow(allCohortPix),
            " | added missing: ", nrow(missingPix))
    truePixelData[, `:=`(ecoregionGroup, factor(as.character(ecoregionGroup)))]
    ecoregionMap <- rasterRead(ecoregionFiles$ecoregionMap)
    ecoregionMap[] <- NA_integer_   # initialise to NA so inactive pixels stay NA
    suppressWarnings(ecoregionMap[truePixelData$pixelIndex] <-
                       as.integer(truePixelData$ecoregionGroup))
    factorDT <- unique(truePixelData[, .(ecoregionGroup, landcover, ecoregionName)])
    factorDT[, `:=`(ID, seq(levels(ecoregionGroup)))]
    factorDT[, `:=`(ecoregion, gsub("_.*", "", ecoregionGroup))]
    setcolorder(factorDT, c("ID", "ecoregionGroup", "ecoregionName",
                             "ecoregion", "landcover"))
    levels(ecoregionMap) <- factorDT
    return(ecoregionMap)
  }
  environment(fixed_fn) <- asNamespace("LandR")
  utils::assignInNamespace("makeEcoregionMap", fixed_fn, ns = "LandR")
  message("LandR::makeEcoregionMap patched: pixelIndex filter + NA initialisation")
}
