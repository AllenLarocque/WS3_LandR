#' Prepare RIA layer from BC_TSA layer
#'
#' @param x BC_TSA layer
#'
#' @return a single terra Polygon
getRIA <- function(x) {
  x <- sf::st_read(x) 
  ria <- x[x$TSA_NUMBER %in% c('08', '16', '24', '40', '41'),]
  ria <- sf::st_union(ria)|> sf::st_as_sf()
  return(ria)
}