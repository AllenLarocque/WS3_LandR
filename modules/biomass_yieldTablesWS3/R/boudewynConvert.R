# boudewynBiomassToVol(): convert biomass (g/m2) trajectory to m3/ha yield curve
# loadSpeciesLookup(), lookupBoudewynKeys(): species -> Boudewyn parameter keys

.pkgEnv <- new.env(parent = emptyenv())

loadSpeciesLookup <- function(csvPath = NULL) {
  if (!is.null(.pkgEnv$speciesLookup)) return(.pkgEnv$speciesLookup)

  if (is.null(csvPath)) {
    # Try paths in order from most to least specific
    candidates <- c(
      file.path(Sys.getenv("TESTTHAT_WD"), "modules/biomass_yieldTablesWS3/data/species_boudewyn_lookup.csv"),
      "modules/biomass_yieldTablesWS3/data/species_boudewyn_lookup.csv"
    )
    csvPath <- candidates[file.exists(candidates)][1]
  }

  if (is.na(csvPath) || !file.exists(csvPath)) {
    stop("loadSpeciesLookup: cannot find species_boudewyn_lookup.csv. ",
         "Set csvPath explicitly or run from the project root directory.")
  }

  lut <- utils::read.csv(csvPath, stringsAsFactors = FALSE)
  .pkgEnv$speciesLookup <- lut
  lut
}

lookupBoudewynKeys <- function(speciesCode, juris_id, ecozone = NULL) {
  stopifnot(length(speciesCode) == 1L, !is.na(speciesCode),
            length(juris_id) == 1L, !is.na(juris_id))
  lut <- loadSpeciesLookup()
  row <- lut[lut$speciesCode == speciesCode & lut$juris_id == juris_id, ]
  if (nrow(row) == 0) {
    stop("No Boudewyn lookup entry for species '", speciesCode,
         "' in jurisdiction '", juris_id, "'")
  }
  if (is.null(ecozone)) ecozone <- row$ecozone_default[1]
  list(
    canfi_species = row$canfi_species[1],
    juris_id      = juris_id,
    ecozone       = as.integer(ecozone)
  )
}
