# biomass_ws3Harvest

A [SpaDES](https://spades.predictiveecology.org/) module that couples [LandR](https://github.com/PredictiveEcology/Biomass_core) forest succession with [WS3](https://github.com/UBC-FRESH/ws3) wood supply optimization. At each planning event it translates the LandR forest inventory into WS3 development type areas, solves an optimal harvest schedule, and applies the resulting disturbance back to LandR cohorts.

Designed to be paired with [`biomass_yieldTablesWS3`](https://github.com/AllenLarocque/biomass_yieldTablesWS3), which generates the m³/ha yield curves that WS3 requires.

## Overview

At each `ws3Plan` event (every `ws3PeriodLength` years):

1. **Inventory bridge** — bins cohort site quality, maps cohorts to `(speciesCode, site_quality, ecoregion)` development type tuples, and aggregates pixel area by dev type × age class
2. **Load into WS3** — pushes area and yield curve data into the `ForestModel` via `reticulate`
3. **Solve** — calls `p.solve()` with the configured solver (default: HiGHS); if the solution is non-optimal, logs a warning and skips harvest for the period
4. **Allocate** — writes per-year clearcut GeoTIFFs via `ForestRaster.allocate_schedule()` (requires ForestRaster initialization — see [open work](#open-work))
5. **Apply harvest** — reads each year's GeoTIFF, identifies harvested pixel groups via `pixelGroupMap`, zeros `B` and sets `mortality` in `cohortData`

## SpaDES Metadata

### Input Objects

| Object | Class | Source |
|---|---|---|
| `cohortData` | `data.table` | `Biomass_core` |
| `pixelGroupMap` | `SpatRaster` | `Biomass_core` |
| `biomassMap` | `SpatRaster` | `Biomass_core` |
| `species` | `data.table` | `Biomass_borealDataPrep` |
| `speciesEcoregion` | `data.table` | `Biomass_borealDataPrep` |
| `ws3YieldCurves` | named list | `biomass_yieldTablesWS3` |

### Output Objects

| Object | Class | Description |
|---|---|---|
| `rstCurrentHarvest` | `SpatRaster` | Harvest disturbance raster (consumed by `Biomass_core`) |
| `cohortData` | `data.table` | Harvested cohorts zeroed (`B = 0`, `mortality = original B`) |
| `ws3HarvestSchedule` | `data.table` | Full WS3 solution for the period (for reporting) |

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `ws3PeriodLength` | from `.globals` | Years between WS3 planning solves |
| `ws3Horizon` | `10` | Number of WS3 planning periods |
| `ws3BaseYear` | `2011` | Calendar year for WS3 period 0 |
| `ws3MinHarvestAge` | `40` | Minimum stand age eligible for harvest |
| `ws3Solver` | `"highs"` | WS3 solver backend (`"highs"`, `"gurobi"`, or `"pulp"`) |

### Events

| Event | Priority | Timing |
|---|---|---|
| `init` | — | Once at sim start — import ws3, initialise ForestModel |
| `ws3Plan` | 2 | Every `ws3PeriodLength` years (after `updateCurves` at priority 1) |

## File Structure

```
biomass_ws3Harvest/
├── biomass_ws3Harvest.R     # SpaDES module definition + doEvent dispatcher
└── R/
    ├── inventoryBridge.R    # buildWs3Inventory(): cohortData → WS3 area table
    ├── harvestBridge.R      # applyClearcut(), applyHarvestSchedule()
    └── actionDispatch.R     # extensible action registry (clearcut; partial cut slot ready)
```

## Usage

Use as part of the LandR–WS3 coupled system. See [`global.R`](https://github.com/AllenLarocque/WS3_LandR) for a complete setup using `SpaDES.project::setupProject()`.

```r
modules = c(
  "PredictiveEcology/Biomass_borealDataPrep@main",
  "PredictiveEcology/Biomass_core@main",
  "AllenLarocque/biomass_yieldTablesWS3@main",
  "AllenLarocque/biomass_ws3Harvest@main"
)

params = list(
  .globals = list(ws3PeriodLength = 10L),
  biomass_ws3Harvest = list(
    ws3Horizon       = 10L,
    ws3BaseYear      = 2011L,
    ws3MinHarvestAge = 40L,
    ws3Solver        = "highs"
  )
)
```

## Dependencies

- R: `SpaDES.core`, `data.table`, `terra`, `reticulate`
- Python: `ws3` — install with `pip install ws3`
- [`biomass_yieldTablesWS3`](https://github.com/AllenLarocque/biomass_yieldTablesWS3) — must run before this module each period (ensured by event priority)

## Extensibility

Harvest actions are registered in `R/actionDispatch.R` via a named list (`.ACTION_REGISTRY`). A clearcut handler is implemented; a slot for `partial_cut` is present and ready for integration with a `partialDisturbance` module:

```r
.ACTION_REGISTRY <- list(
  clearcut   = function(harvestRast, cohortData, pixelGroupMap) { ... },
  partial_cut = function(...) { ... }   # plug in your partialDisturbance module here
)
```

## Open Work

**ForestRaster spatial allocation** — `ws3$spatial$ForestRaster` requires a 3-layer rasterized inventory GeoTIFF (theme hash / age / block ID) plus `hdt_map` and `hdt_func` encoding dev type tuples as integer hash values. Building this rasterized inventory from LandR's `pixelGroupMap` + `cohortData` is the primary remaining integration step. Until it is wired up, the module solves the WS3 problem aspatially and logs a warning; harvest is applied if GeoTIFFs are provided externally.

## Related Modules

- [`biomass_yieldTablesWS3`](https://github.com/AllenLarocque/biomass_yieldTablesWS3) — generates `ws3YieldCurves` consumed by this module
- [`Biomass_core`](https://github.com/PredictiveEcology/Biomass_core) — provides `cohortData` and `pixelGroupMap`
- [`Biomass_borealDataPrep`](https://github.com/PredictiveEcology/Biomass_borealDataPrep) — provides species and ecoregion parameters

## References

- Nelson, J. (2003). *Forest-level models and challenging policy.* UBC Faculty of Forestry. (WS3)
- Scheller, R. M., & Mladenoff, D. J. (2004). LANDIS-II / LandR Biomass model.
- [WS3 source](https://github.com/UBC-FRESH/ws3) — UBC FRESH
