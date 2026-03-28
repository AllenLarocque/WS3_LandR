# plotStandGrowth(): line plot of B_gm2 vs age per development type
# Arguments:
#   ws3YieldCurves  named list, each element is data.frame(age, vol_m3ha, B_gm2)
#   simYear         numeric, used in plot title
# Returns: ggplot object

plotStandGrowth <- function(ws3YieldCurves, simYear) {
  if (length(ws3YieldCurves) == 0L) {
    return(ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5,
                        label = "No yield curves available") +
      ggplot2::theme_bw())
  }

  # Check for stale cache missing B_gm2
  has_bgm2 <- all(vapply(ws3YieldCurves, function(x) "B_gm2" %in% names(x), logical(1)))
  if (!has_bgm2) {
    return(ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5,
                        label = "B_gm2 not available in cache — re-run to regenerate curves") +
      ggplot2::theme_bw())
  }

  dt <- data.table::rbindlist(lapply(names(ws3YieldCurves), function(key) {
    parts <- strsplit(key, "|", fixed = TRUE)[[1]]
    d <- data.table::as.data.table(ws3YieldCurves[[key]])
    d[, `:=`(speciesCode    = parts[1],
             site_quality   = parts[2],
             ecoregionGroup = parts[3],
             devTypeKey     = key)]
    d
  }))

  ggplot2::ggplot(dt, ggplot2::aes(x = age, y = B_gm2,
                                    colour = speciesCode,
                                    group  = devTypeKey)) +
    ggplot2::geom_line() +
    ggplot2::facet_wrap(~ site_quality) +
    ggplot2::labs(
      title  = paste0("Stand Growth Trajectories — year ", simYear),
      x      = "Age (years)",
      y      = "Biomass (g/m²)",
      colour = "Species"
    ) +
    ggplot2::theme_bw()
}
