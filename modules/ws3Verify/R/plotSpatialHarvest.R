# plotSpatialHarvest(): annual and cumulative harvest raster maps
# Mirrors plot_harvestMap() from simpleHarvestTesting.
#
# Arguments:
#   annualHarvestRast      SpatRaster (or NULL) — current year's harvest raster
#   cumulativeHarvestRast  SpatRaster — running sum of harvested pixels across years
#   simYear                numeric, used in plot titles
#
# Returns: named list(annual = <ggplot or NULL>, cumulative = <ggplot>)

plotSpatialHarvest <- function(annualHarvestRast, cumulativeHarvestRast, simYear) {
  .harvest_map_plot <- function(x, title) {
    ggplot2::ggplot() +
      tidyterra::geom_spatraster(data = x) +
      viridis::scale_fill_viridis(na.value = "transparent") +
      ggplot2::coord_equal() +
      ggplot2::labs(title = title) +
      ggplot2::theme_bw()
  }

  if (is.null(cumulativeHarvestRast))
    stop("plotSpatialHarvest: cumulativeHarvestRast must not be NULL")

  annual_plot <- if (!is.null(annualHarvestRast)) {
    .harvest_map_plot(annualHarvestRast,
                      paste0("Annual Harvest — year ", simYear))
  } else {
    NULL
  }

  cumulative_plot <- .harvest_map_plot(cumulativeHarvestRast,
                                       paste0("Cumulative Harvest — year ", simYear))

  list(annual = annual_plot, cumulative = cumulative_plot)
}
