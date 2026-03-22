# boudewynBiomassToVol(): convert biomass (g/m2) trajectory to m3/ha yield curve
# loadSpeciesLookup(), lookupBoudewynKeys(): species -> Boudewyn parameter keys

.pkgEnv <- new.env(parent = emptyenv())

# Capture the absolute path of this script at source() time, so CSV lookup works
# regardless of the working directory when tests or the SpaDES module call these functions.
.boudewynScriptDir <- tryCatch(
  normalizePath(dirname(sys.frame(1)$ofile), mustWork = FALSE),
  error = function(e) NULL
)

loadSpeciesLookup <- function() {
  if (!is.null(.pkgEnv$speciesLookup)) return(.pkgEnv$speciesLookup)

  csvPath <- if (!is.null(.boudewynScriptDir)) {
    # Path relative to this script's location (absolute, captured at source time)
    normalizePath(
      file.path(.boudewynScriptDir, "..", "data", "species_boudewyn_lookup.csv"),
      mustWork = FALSE
    )
  } else {
    # Fallback 1: testthat sets TESTTHAT_WD to the original project root
    testhatWd <- Sys.getenv("TESTTHAT_WD", unset = "")
    if (nzchar(testhatWd)) {
      file.path(testhatWd, "modules/biomass_yieldTablesWS3/data/species_boudewyn_lookup.csv")
    } else {
      # Fallback 2: relative to current working directory (project root)
      "modules/biomass_yieldTablesWS3/data/species_boudewyn_lookup.csv"
    }
  }

  lut <- utils::read.csv(csvPath, stringsAsFactors = FALSE)
  .pkgEnv$speciesLookup <- lut
  lut
}

lookupBoudewynKeys <- function(speciesCode, juris_id, ecozone = NULL) {
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
