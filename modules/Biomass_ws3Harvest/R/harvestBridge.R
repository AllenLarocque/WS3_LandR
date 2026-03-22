# applyHarvestSchedule(): apply WS3 harvest schedule to LandR cohortData and pixelGroupMap

applyClearcut <- function(harvestRast, cohortData, pixelGroupMap) {
  # Identify pixel groups where any pixel was harvested
  harvestVals  <- terra::values(harvestRast, mat = FALSE)
  pgVals       <- terra::values(pixelGroupMap, mat = FALSE)
  harvestedPGs <- unique(pgVals[!is.na(harvestVals) & harvestVals == 1L])

  cd <- copy(cohortData)
  # Set mortality = B before zeroing (two separate := calls — data.table evaluates left-to-right)
  cd[pixelGroup %in% harvestedPGs, mortality := B]
  cd[pixelGroup %in% harvestedPGs, `:=`(B = 0L, aNPPAct = 0L)]
  cd[]
}

applyHarvestSchedule <- function(schedule, cohortData, pixelGroupMap,
                                  outputPath, baseYear) {
  # schedule: data.table with columns year, acode, area (from WS3 solution)
  # Reads GeoTIFFs written by ForestRaster.allocate_schedule()
  for (yr in unique(schedule$year)) {
    yearSchedule <- schedule[year == yr]
    for (ac in unique(yearSchedule$acode)) {
      tifPath <- file.path(outputPath, sprintf("%s_%d.tif", ac, yr))
      if (!file.exists(tifPath)) next
      harvestRast <- terra::rast(tifPath)
      cohortData  <- applyHarvestAction(ac, harvestRast, cohortData, pixelGroupMap)
    }
  }
  cohortData
}
