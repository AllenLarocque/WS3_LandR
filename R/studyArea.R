#' Shrink a polygon inward by a distance, on a raster
#'
#' A GEOS negative buffer (`sf::st_buffer(x, -dist)`) of a large, detailed outline can run for
#' tens of minutes and use tens of GB (the five RIA TSAs, ~455,000 vertices, -150 km). This does
#' it on a raster instead: cells farther than `dist` from the outline are kept and turned back
#' into a polygon. The result follows the `res` grid, which is the model grid anyway.
#'
#' @param x `SpatVector` or `sf` polygon(s), in a projected CRS with metres.
#' @param dist Distance in metres. 0 returns `x` dissolved.
#' @param res Cell size in metres.
#'
#' @return `sf` polygon in the CRS of `x`.
inwardBuffer <- function(x, dist, res) {
  if (!inherits(x, "SpatVector")) x <- terra::vect(x)
  v <- terra::aggregate(x)
  if (dist <= 0) return(sf::st_as_sf(v))
  r <- terra::rasterize(v, terra::extend(terra::rast(v, res = res), 1L), background = 0)
  outside <- terra::classify(r, cbind(1, NA))   # outside = 0, inside = NA
  d <- terra::distance(outside)                 # inside cells: distance to the outline
  core <- terra::classify(d, cbind(-Inf, dist, NA), right = TRUE)
  if (all(is.na(terra::values(core)))) stop("inwardBuffer: nothing is left after shrinking by ", dist, " m")
  sf::st_as_sf(terra::as.polygons(core > 0, dissolve = TRUE))
}
