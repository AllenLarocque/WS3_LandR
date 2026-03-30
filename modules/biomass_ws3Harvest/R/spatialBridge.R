# buildInventoryRaster(): convert cohortData + pixelGroupMap to a 3-band inventory GeoTIFF
# for ws3.spatial.ForestRaster.
#
# Arguments:
#   cohortData    data.table — must have: pixelGroup, speciesCode, site_quality,
#                              ecoregionGroup, age, B (site_quality pre-binned by caller)
#   pixelGroupMap SpatRaster — integer pixel group IDs; NA where no forest
#   period_length integer    — years per WS3 period (for age → age-in-periods)
#   base_year     integer    — current calendar year (= time(sim)); used in filename
#   out_dir       character  — output directory (same dir step 8 reads from)
#
# Returns: list(path = character scalar, hdt_table = data.table(hash_val, speciesCode,
#                                                                site_quality, ecoregionGroup))
#
# GeoTIFF band layout (INT4S, nodata=0):
#   Band 1: ws3.common.hash_dt((speciesCode, site_quality, ecoregionGroup)) for dominant cohort
#   Band 2: ceiling(age / period_length) for dominant cohort
#   Band 3: pixelGroup ID (block ID for ForestRaster randblk allocation)
#
# Non-forest pixels (NA in pixelGroupMap) are written as 0 in all bands.
# ForestRaster.__init__ identifies non-forest as band1 == 0.

buildInventoryRaster <- function(cohortData, pixelGroupMap, period_length, base_year, out_dir) {
  stopifnot(
    data.table::is.data.table(cohortData),
    inherits(pixelGroupMap, "SpatRaster"),
    all(c("pixelGroup", "speciesCode", "site_quality", "ecoregionGroup", "age", "B")
        %in% names(cohortData)),
    length(period_length) == 1L, period_length > 0L,
    length(base_year) == 1L,
    length(out_dir) == 1L
  )

  # ── 1. Dominant cohort per pixelGroup (max B) ─────────────────────────────
  dom <- cohortData[, .SD[which.max(B)], by = pixelGroup,
                    .SDcols = c("speciesCode", "site_quality", "ecoregionGroup", "age")]

  # ── 2. Hash unique dev type tuples via ws3.common.hash_dt ─────────────────
  # Import once; hash_dt(tuple) → numpy int32. py_to_r returns R numeric (double),
  # so as.integer() is required for correct INT4S rasterization.
  ws3_common    <- reticulate::import("ws3.common")
  unique_dtypes <- unique(dom[, .(speciesCode, site_quality, ecoregionGroup)])
  unique_dtypes[, hash_val := vapply(seq_len(.N), function(i) {
    as.integer(reticulate::py_to_r(
      ws3_common$hash_dt(reticulate::tuple(speciesCode[i], site_quality[i], ecoregionGroup[i]))
    ))
  }, integer(1L))]

  if (any(unique_dtypes$hash_val == 0L))
    stop("buildInventoryRaster: hash_dt returned 0 for dev-type tuple(s) ",
         paste(unique_dtypes[hash_val == 0L, paste(speciesCode, site_quality, ecoregionGroup)],
               collapse = ", "),
         " — 0 is reserved as the non-forest sentinel in the inventory GeoTIFF")

  dom <- merge(dom, unique_dtypes, by = c("speciesCode", "site_quality", "ecoregionGroup"),
               all.x = TRUE)

  # ── 3. Age in periods and block ID ────────────────────────────────────────
  dom[, age_periods := as.integer(ceiling(age / period_length))]
  dom[, block_id    := as.integer(pixelGroup)]

  # ── 4. Rasterize: one classify() call per band ───────────────────────────
  # cbind(from, to): pixelGroup IDs → band values.
  # others=NA ensures pixel groups absent from dom (no cohortData entry) become NA → 0.
  # Without others=NA, terra::classify keeps the original integer, bypassing the NA→0 step.
  pg <- as.integer(dom$pixelGroup)

  band1 <- terra::classify(pixelGroupMap, cbind(pg, dom$hash_val),    others = NA)
  band2 <- terra::classify(pixelGroupMap, cbind(pg, dom$age_periods),  others = NA)
  band3 <- terra::classify(pixelGroupMap, cbind(pg, dom$block_id),     others = NA)

  inv_rast <- c(band1, band2, band3)

  # Replace NA (non-forest) with 0: ForestRaster identifies non-forest as band1 == 0.
  # If terra's INT4S NA sentinel (-2147483648) were written, rasterio would read it
  # as a large negative hash, misidentifying non-forest pixels as forested.
  inv_rast[is.na(inv_rast)] <- 0L

  inv_path <- file.path(out_dir, sprintf("inventory_%d.tif", as.integer(base_year)))
  terra::writeRaster(inv_rast, inv_path, datatype = "INT4S",
                     gdal = "COMPRESS=LZW", NAflag = 0L, overwrite = TRUE)

  # ── 5. Return path (scalar string) + hdt_table ────────────────────────────
  list(
    path      = as.character(inv_path),
    hdt_table = unique_dtypes[, .(hash_val, speciesCode, site_quality, ecoregionGroup)]
  )
}
