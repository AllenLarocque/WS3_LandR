# plotAgeMap(): stand age raster — biomass-weighted dominant age per pixel group
# Mirrors plot_simpleHarvestageMap() from simpleHarvestTesting.
#
# Arguments:
#   cohortData    data.table with columns: pixelGroup, age, B
#   pixelGroupMap SpatRaster of pixel group IDs
#   simYear       numeric, used in plot title
#   maxAge        numeric, cap for display (default 300)
#
# Returns: ggplot object

plotAgeMap <- function(cohortData, pixelGroupMap, simYear, maxAge = 300) {
  if (nrow(cohortData) == 0L) {
    return(ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5,
                        label = "No cohort data available") +
      ggplot2::theme_bw())
  }

  # Biomass-weighted age per pixel group
  pgAge <- cohortData[, .(BweightedAge = sum(B * age, na.rm = TRUE) /
                                          pmax(1, sum(B, na.rm = TRUE))),
                      by = pixelGroup]

  # Reclassify pixelGroupMap: replace pixel group ID with its B-weighted age
  pgVals  <- terra::values(pixelGroupMap, mat = FALSE)
  ageVals <- pgAge$BweightedAge[match(pgVals, pgAge$pixelGroup)]
  ageVals <- pmin(ageVals, maxAge)

  ageRast <- terra::rast(pixelGroupMap)
  terra::values(ageRast) <- ageVals

  ggplot2::ggplot() +
    tidyterra::geom_spatraster(data = ageRast) +
    ggplot2::scale_fill_viridis_c(na.value = "transparent",
                                   name     = "Age (years)",
                                   limits   = c(0, maxAge)) +
    ggplot2::coord_equal() +
    ggplot2::labs(title = paste0("Stand Age Map \u2014 year ", simYear)) +
    ggplot2::theme_bw()
}
