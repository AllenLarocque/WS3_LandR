# applyHarvestAction(): dispatch harvest action by action code (clearcut now, extensible)

# Action dispatch table — add new actions here (e.g., "partial_cut")
# Each handler signature: function(harvestRast, cohortData, pixelGroupMap) -> cohortData
.ACTION_REGISTRY <- list(
  clearcut = function(harvestRast, cohortData, pixelGroupMap) {
    applyClearcut(harvestRast, cohortData, pixelGroupMap)
  }
  # partial_cut = function(...) { ... }   # slot for future partialDisturbance module
)

applyHarvestAction <- function(actionCode, harvestRast, cohortData, pixelGroupMap) {
  handler <- .ACTION_REGISTRY[[actionCode]]
  if (is.null(handler)) {
    warning("applyHarvestAction: unknown action '", actionCode,
            "' — skipping. Register handler in actionDispatch.R")
    return(cohortData)
  }
  handler(harvestRast, cohortData, pixelGroupMap)
}
