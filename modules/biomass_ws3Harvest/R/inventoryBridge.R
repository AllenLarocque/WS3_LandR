# buildWs3Inventory(): translate cohortData into WS3 dev type area table
#
# Note: site quality binning (maxANPP/species$maxANPP → low/med/high) is performed
# by the calling module event (via binSiteQuality() from siteQuality.R) BEFORE
# this function is called. cohortData must already have a `site_quality` column.
# This separation keeps the pure-R aggregation logic unit-testable without SpaDES.

buildWs3Inventory <- function(cohortData, pixelArea, periodLength,
                               minHarvestAge = 40L) {
  # cohortData must have columns: pixelGroup, speciesCode, ecoregionGroup,
  #   age, B, site_quality (pre-binned by binSiteQuality)
  # pixelArea: data.table(pixelGroup, area_ha)
  # periodLength: integer, years per WS3 period (for age class binning)
  # minHarvestAge: minimum age for harvestable flag

  stopifnot(
    is.data.table(cohortData),
    is.data.table(pixelArea),
    all(c("pixelGroup", "speciesCode", "ecoregionGroup", "age", "site_quality") %in% names(cohortData)),
    all(c("pixelGroup", "area_ha") %in% names(pixelArea)),
    length(periodLength) == 1L, periodLength > 0,
    length(minHarvestAge) == 1L, minHarvestAge >= 0
  )

  cd <- copy(cohortData)

  # Build dev type key for each cohort (scalar devTypeTupleKey called row-by-row)
  cd[, devTypeKey  := mapply(devTypeTupleKey, speciesCode, site_quality, ecoregionGroup)]
  cd[, age_class   := floor(age / periodLength)]
  cd[, harvestable := age >= minHarvestAge]

  # join pixel areas once per pixel
  cd <- merge(cd, pixelArea, by = "pixelGroup", all.x = TRUE)

  n_missing_area <- sum(is.na(cd$area_ha))
  if (n_missing_area > 0) {
    warning("buildWs3Inventory: ", n_missing_area,
            " cohort(s) have no matching pixelArea entry — area will be treated as NA")
  }

  # One area entry per (pixelGroup, devTypeKey, age_class) — avoids double-counting
  # when cohorts in the same pixel have mixed harvestable status within an age class
  px_area <- unique(cd[, .(pixelGroup, devTypeKey, age_class, area_ha)])
  px_harv <- cd[, .(harvestable = any(harvestable)), by = .(pixelGroup, devTypeKey, age_class)]
  px_dt   <- merge(px_area, px_harv, by = c("pixelGroup", "devTypeKey", "age_class"), all.x = TRUE)

  inv <- px_dt[, .(area_ha = sum(area_ha, na.rm = TRUE),
                   harvestable = any(harvestable)),
               by = .(devTypeKey, age_class)]
  inv[]
}
