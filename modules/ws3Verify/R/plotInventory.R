# plotInventory(): bar chart of area (ha) by age class from WS3 inventory table
# Arguments:
#   ws3Inventory  data.table(devTypeKey, age_class, area_ha, harvestable, site_quality)
#                 built by the event handler via binSiteQuality + buildWs3Inventory
#   simYear       numeric, used in plot title
# Returns: ggplot object

plotInventory <- function(ws3Inventory, simYear) {
  if (is.null(ws3Inventory) || nrow(ws3Inventory) == 0L) {
    return(ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5,
                        label = "No inventory data available") +
      ggplot2::theme_bw())
  }

  ggplot2::ggplot(ws3Inventory,
                  ggplot2::aes(x = age_class, y = area_ha,
                               fill = as.factor(age_class))) +
    ggplot2::geom_col(show.legend = FALSE) +
    viridis::scale_fill_viridis(discrete = TRUE) +
    ggplot2::facet_wrap(~ site_quality) +
    ggplot2::labs(
      title = paste0("WS3 Inventory — year ", simYear),
      x     = "Age Class (period units)",
      y     = "Area (ha)"
    ) +
    ggplot2::theme_bw()
}
