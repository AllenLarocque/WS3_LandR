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

# ── Boudewyn Table Loading ──────────────────────────────────────────────────

loadBoudewynTable <- function(table_name) {
  # table_name: "table3" or "table6_tb"
  cached_key <- paste0(".boudewyn_", table_name)
  if (!is.null(.pkgEnv[[cached_key]])) return(.pkgEnv[[cached_key]])

  urls <- list(
    table3    = "https://nfi.nfis.org/resources/biomass_models/appendix2_table3.csv",
    table6_tb = "https://nfi.nfis.org/resources/biomass_models/appendix2_table6_tb.csv"
  )
  url <- urls[[table_name]]
  if (is.null(url)) stop("Unknown Boudewyn table: '", table_name, "'")

  fname <- paste0("boudewyn_", table_name, ".csv")

  # Search for pre-downloaded CSV in candidate locations (project root → TESTTHAT_WD root)
  candidates <- c(
    file.path("inputs", fname),
    file.path(Sys.getenv("TESTTHAT_WD"), "inputs", fname)
  )
  localPath <- candidates[file.exists(candidates)][1]

  if (is.na(localPath) || !file.exists(localPath)) {
    # Fall back: download to inputs/ relative to cwd
    dir.create("inputs", showWarnings = FALSE, recursive = TRUE)
    localPath <- file.path("inputs", fname)
    tryCatch(
      utils::download.file(url, localPath, quiet = TRUE),
      error = function(e) stop("Failed to download Boudewyn ", table_name,
                               " from NFIS. Check internet connection.\nURL: ", url)
    )
  }

  tbl <- utils::read.csv(localPath, stringsAsFactors = FALSE)
  .pkgEnv[[cached_key]] <- tbl
  tbl
}

# ── Biomass → Volume Conversion ─────────────────────────────────────────────

boudewynBiomassToVol <- function(ageB, canfi_species, juris_id, ecozone) {
  # Input:  ageB — data.frame(age, B_gm2)  where B_gm2 is total AGB in g/m²
  # Output: data.frame(age, vol_m3ha)

  B_tha <- ageB$B_gm2 / 100   # g/m² → tonnes/ha

  # ── Step 1: Table 6_tb — merchantable stemwood fraction (pstem) ──────────
  # Column names in NFIS appendix2_table6_tb.csv:
  #   juris_id, ecozone, canfi_spec, genus, species, variety,
  #   a1, a2, a3, b1, b2, b3, c1, c2, c3, count
  t6 <- loadBoudewynTable("table6_tb")

  t6_row <- t6[t6$canfi_spec == canfi_species &
               t6$juris_id   == juris_id      &
               t6$ecozone    == ecozone, ]

  if (nrow(t6_row) == 0) {
    stop("No Boudewyn Table 6_tb params for canfi_species=", canfi_species,
         ", juris_id=", juris_id, ", ecozone=", ecozone)
  }
  r <- t6_row[1, ]

  # Multinomial logistic model — proportion of total AGB that is merchantable stemwood
  lB5   <- log(B_tha + 5)
  denom <- 1 +
    exp(r$a1 + r$a2 * B_tha + r$a3 * lB5) +
    exp(r$b1 + r$b2 * B_tha + r$b3 * lB5) +
    exp(r$c1 + r$c2 * B_tha + r$c3 * lB5)
  pstem <- 1 / denom
  b_m   <- B_tha * pstem   # merchantable stemwood biomass (tonnes/ha)

  # ── Step 2: Inverse Table 3 — merchantable volume ───────────────────────
  # Column names in NFIS appendix2_table3.csv:
  #   juris_id, ecozone, canfi_species, genus, species, variety, a, b, volm, count, rmse
  t3 <- loadBoudewynTable("table3")

  t3_row <- t3[t3$canfi_species == canfi_species &
               t3$juris_id      == juris_id       &
               t3$ecozone       == ecozone, ]

  if (nrow(t3_row) == 0) {
    stop("No Boudewyn Table 3 params for canfi_species=", canfi_species,
         ", juris_id=", juris_id, ", ecozone=", ecozone)
  }
  r3 <- t3_row[1, ]

  # Inverse power equation: vol = (b_m / a)^(1/b)
  # Guard against b_m <= 0 or a <= 0 (yields 0 volume)
  vol <- ifelse(b_m > 0 & r3$a > 0,
                (b_m / r3$a) ^ (1 / r3$b),
                0)

  data.frame(age = ageB$age, vol_m3ha = pmax(0, vol))
}
