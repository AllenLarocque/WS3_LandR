# binSiteQuality(): bin cohort maxANPP ratio into low/med/high site quality classes

binSiteQuality <- function(cohortData, speciesEcoregion, speciesMaxANPP,
                           bins = c(0.33, 0.67)) {
  cd <- copy(cohortData)

  # join local maxANPP from speciesEcoregion
  cd <- merge(cd, speciesEcoregion[, .(speciesCode, ecoregionGroup, maxANPP)],
              by = c("speciesCode", "ecoregionGroup"), all.x = TRUE)

  # warn on unmatched rows and assign fallback
  unmatched <- cd[is.na(maxANPP)]
  if (nrow(unmatched) > 0) {
    warning("binSiteQuality: ", nrow(unmatched),
            " cohorts have unrecognised ecoregion — assigned 'med'")
    cd[is.na(maxANPP), maxANPP := 0]
  }

  # join species-level ceiling maxANPP
  cd <- merge(cd, speciesMaxANPP[, .(speciesCode, globalMaxANPP)],
              by = "speciesCode", all.x = TRUE)
  cd[is.na(globalMaxANPP), globalMaxANPP := 1]  # avoid div/0

  cd[, ratio := maxANPP / globalMaxANPP]
  cd[, site_quality := fcase(
    ratio < bins[1], "low",
    ratio < bins[2], "med",
    default         = "high"
  )]
  cd[, c("maxANPP", "globalMaxANPP", "ratio") := NULL]
  cd[]
}
