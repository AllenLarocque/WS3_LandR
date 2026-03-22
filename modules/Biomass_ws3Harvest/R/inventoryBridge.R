# buildWs3Inventory(): translate cohortData into WS3 dev type area table

buildWs3Inventory <- function(cohortData, pixelArea, periodLength,
                               minHarvestAge = 40L) {
  # cohortData must have columns: pixelGroup, speciesCode, ecoregionGroup,
  #   age, B, site_quality
  # pixelArea: data.table(pixelGroup, area_ha)
  # periodLength: integer, years per WS3 period (for age class binning)
  # minHarvestAge: minimum age for harvestable flag

  cd <- copy(cohortData)

  # Build dev type key for each cohort (scalar devTypeTupleKey called row-by-row)
  cd[, devTypeKey  := mapply(devTypeTupleKey, speciesCode, site_quality, ecoregionGroup)]
  cd[, age_class   := floor(age / periodLength)]
  cd[, harvestable := age >= minHarvestAge]

  # join pixel areas once per pixel
  cd <- merge(cd, pixelArea, by = "pixelGroup", all.x = TRUE)

  # get distinct (pixelGroup, devTypeKey, age_class) combinations — one area per pixel per dev type
  px_dt <- unique(cd[, .(pixelGroup, devTypeKey, age_class, area_ha, harvestable)])

  # aggregate area by dev type x age class
  inv <- px_dt[, .(area_ha = sum(area_ha, na.rm = TRUE),
                   harvestable = any(harvestable)),
               by = .(devTypeKey, age_class)]
  inv[]
}
