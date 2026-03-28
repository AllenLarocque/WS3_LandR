# simulateStand(): simulate single-cohort stand biomass growth using the
# LANDIS-II Biomass Succession equations (Scheller & Miranda 2015).
#
# For a SINGLE cohort the competition simplifies:
#   sumB = B (only one cohort)
#   bPot = max(1, maxB)
#   bAP  = B / bPot
#   bPM  = 1  (cMultiplier / cMultTotal = 1 when there is only one cohort)
#
# This allows us to inline the equations without sourcing Biomass_core helpers,
# keeping the function self-contained and fast (no SpaDES sub-simulation).
#
# Arguments:
#   speciesCode       character(1)   e.g. "Pice_mar"
#   site_quality      character(1)   "low", "med", or "high" (informational)
#   ecoregion         character(1)   ecoregionGroup label
#   species           data.table     LandR species table (one row per spp)
#   speciesEcoregion  data.table     LandR speciesEcoregion table
#   maxAge            integer        maximum simulation age
#   modulePath        (unused, kept for signature compatibility)
#   outputPath        (unused, kept for signature compatibility)
#
# Returns: data.table(age, B_gm2) — one row per year from 0 to longevity/maxAge.

simulateStand <- function(speciesCode, site_quality, ecoregion,
                          species, speciesEcoregion,
                          maxAge     = 300L,
                          modulePath = NULL,
                          outputPath = NULL) {

  speciesCode <- as.character(speciesCode)
  ecoregion   <- as.character(ecoregion)

  stopifnot(
    length(speciesCode) == 1L, !is.na(speciesCode), nchar(speciesCode) > 0L,
    length(ecoregion)   == 1L, !is.na(ecoregion),
    maxAge > 0
  )

  # ── species parameters ───────────────────────────────────────────────────
  if (!is.data.frame(species))
    stop("simulateStand: 'species' must be a data.frame/data.table; got ",
         class(species), " (value: ", paste(head(species), collapse=", "), ")")
  # Compute masks outside data.table `[` to avoid column-name scoping:
  # inside dt[i], bare names resolve to dt columns, so `speciesCode` would
  # refer to the column rather than the function argument.
  spp_mask <- as.character(species$speciesCode) == speciesCode
  spp_row  <- species[spp_mask]
  if (nrow(spp_row) == 0)
    stop("simulateStand: speciesCode '", speciesCode, "' not found in species table")
  longevity      <- as.integer(spp_row$longevity[1])
  mortalityshape <- as.numeric(spp_row$mortalityshape[1])
  growthcurve    <- as.numeric(spp_row$growthcurve[1])
  end_time       <- min(as.integer(maxAge), longevity)

  # ── ecoregion parameters ─────────────────────────────────────────────────
  se_mask <- as.character(speciesEcoregion$speciesCode)   == speciesCode &
             as.character(speciesEcoregion$ecoregionGroup) == ecoregion
  se_row  <- speciesEcoregion[se_mask]
  if (nrow(se_row) == 0)
    stop("simulateStand: no speciesEcoregion row for speciesCode='", speciesCode,
         "', ecoregion='", ecoregion, "'")
  maxANPP <- as.numeric(se_row$maxANPP[1])
  maxB    <- as.numeric(se_row$maxB[1])

  # ── inline LANDIS-II growth loop ─────────────────────────────────────────
  bPot <- max(1.0, maxB)          # constant for single cohort
  ages   <- integer(end_time + 1L)
  B_vals <- numeric(end_time + 1L)
  ages[1]   <- 0L
  B_vals[1] <- 0

  B   <- 1.0    # seed biomass (g/m2)
  age <- 1L

  for (yr in seq_len(end_time)) {
    # Competition (single-cohort simplification: bPM = 1)
    bAP <- B / bPot

    # ANPP
    bAPgc <- bAP^growthcurve
    aNPP  <- pmin(maxANPP, maxANPP * exp(1) * bAPgc * exp(-bAPgc))

    # Growth mortality
    if (bAP > 1.0) {
      mBio <- maxANPP
    } else {
      mBio <- maxANPP * (2 * bAP) / (1 + bAP)
    }
    mBio <- pmin(B, pmin(maxANPP, mBio))

    # Age mortality
    mAge <- B * exp((age / longevity) * mortalityshape) / exp(mortalityshape)
    mAge <- pmin(B, mAge)

    # Update biomass and age
    B   <- pmax(0, B + aNPP - mBio - mAge)
    ages[yr + 1L]   <- age
    B_vals[yr + 1L] <- B
    age <- age + 1L

    if (B <= 0) {
      ages   <- ages[seq_len(yr + 1L)]
      B_vals <- B_vals[seq_len(yr + 1L)]
      break
    }
  }

  data.table::data.table(age = ages, B_gm2 = B_vals)
}
