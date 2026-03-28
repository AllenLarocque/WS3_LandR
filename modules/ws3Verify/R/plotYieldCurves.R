# plotYieldCurves(): line plot of vol_m3ha vs age per development type
# Arguments:
#   ws3YieldCurves  named list, each element is data.frame(age, vol_m3ha, B_gm2)
#   simYear         numeric, used in plot title
# Returns: ggplot object

plotYieldCurves <- function(ws3YieldCurves, simYear) {
  if (length(ws3YieldCurves) == 0L) {
    return(ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5,
                        label = "No yield curves available") +
      ggplot2::theme_bw())
  }

  n_parts <- lengths(strsplit(names(ws3YieldCurves), "|", fixed = TRUE))
  if (any(n_parts != 3L))
    warning("plotYieldCurves: some keys do not have 3 '|'-separated parts; check ws3YieldCurves names")

  dt <- data.table::rbindlist(lapply(names(ws3YieldCurves), function(key) {
    parts <- strsplit(key, "|", fixed = TRUE)[[1]]
    d <- data.table::as.data.table(ws3YieldCurves[[key]])
    d[, `:=`(speciesCode   = parts[1],
             site_quality  = parts[2],
             ecoregionGroup = parts[3],
             devTypeKey    = key)]
    d
  }))

  ggplot2::ggplot(dt, ggplot2::aes(x = age, y = vol_m3ha,
                                    colour = speciesCode,
                                    group  = devTypeKey)) +
    ggplot2::geom_line() +
    ggplot2::facet_wrap(~ site_quality) +
    ggplot2::labs(
      title  = paste0("Yield Curves \u2014 year ", simYear),
      x      = "Age (years)",
      y      = "Volume (m\u00b3/ha)",
      colour = "Species"
    ) +
    ggplot2::theme_bw()
}
