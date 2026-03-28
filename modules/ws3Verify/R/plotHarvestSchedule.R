# plotHarvestSchedule(): bar chart of harvested volume per period from WS3 LP solution
# Arguments:
#   ws3HarvestSchedule  data.table with columns: period, vol_harvested
#                       (NULL or zero rows if solve was non-optimal)
#                       NOTE: column names (period, vol_harvested) are placeholders —
#                       verify against actual p$solution() output before production use.
#   simYear             numeric, used in plot title
# Returns: ggplot object

plotHarvestSchedule <- function(ws3HarvestSchedule, simYear) {
  if (is.null(ws3HarvestSchedule) || nrow(ws3HarvestSchedule) == 0L) {
    return(ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5,
                        label = "No harvest schedule available (non-optimal solve)") +
      ggplot2::theme_bw())
  }

  # Reference line at period-1 harvest volume to visualise even-flow
  ref_vol <- ws3HarvestSchedule$vol_harvested[1]

  ggplot2::ggplot(ws3HarvestSchedule,
                  ggplot2::aes(x = period, y = vol_harvested,
                               fill = as.factor(period))) +
    ggplot2::geom_col(show.legend = FALSE) +
    viridis::scale_fill_viridis(discrete = TRUE) +
    ggplot2::geom_hline(yintercept = ref_vol, linetype = "dashed", colour = "grey40") +
    ggplot2::labs(
      title    = paste0("Harvest Schedule \u2014 year ", simYear),
      subtitle = paste0("Dashed line = period-1 reference (", round(ref_vol), " m\u00b3)"),
      x        = "Planning Period",
      y        = "Harvested Volume (m\u00b3)"
    ) +
    ggplot2::theme_bw()
}
