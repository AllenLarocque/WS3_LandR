# binSiteQuality(): bin cohort maxANPP ratio into low/med/high site quality classes

binSiteQuality <- function(cohortData, speciesEcoregion, speciesMaxANPP,
                           bins = c(0.33, 0.67)) {
  cd <- copy(cohortData)

  # join local maxANPP from speciesEcoregion
  cd <- merge(cd, speciesEcoregion[, .(speciesCode, ecoregionGroup, maxANPP)],
              by = c("speciesCode", "ecoregionGroup"), all.x = TRUE)

  # identify unmatched rows before any imputation
  cd[, .missing_eco := is.na(maxANPP)]

  # warn on unmatched rows and assign fallback for ratio computation
  n_missing <- sum(cd$.missing_eco)
  if (n_missing > 0) {
    warning("binSiteQuality: ", n_missing,
            " cohorts have unrecognised ecoregion — assigned 'low'")
    cd[(.missing_eco), maxANPP := 0]
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

  # overwrite with "low" for missing-ecoregion rows regardless of bins
  cd[(.missing_eco), site_quality := "low"]

  cd[, c("maxANPP", "globalMaxANPP", "ratio", ".missing_eco") := NULL]
  cd[]
}
