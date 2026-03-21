# LandR–WS3 Coupling Design Spec

**Date:** 2026-03-21
**Project:** WS3_LandR
**Status:** Draft — awaiting implementation plan

---

## Overview

Couple the LandR suite of SpaDES modules (forest succession) with WS3 (wood supply optimization) into a spatially explicit, adaptive forest simulation and harvest planning system. LandR drives annual succession; WS3 optimizes harvest schedules over configurable planning periods; the two are bridged by two new SpaDES modules.

**Out of scope:** WS3 carbon outputs / CBM linkage — carbon accounting handled separately by LandRCBM.

---

## Goals

- LandR defines the study area, ecolocations, and provides forest inventory to WS3 at each planning event
- WS3 ingests inventory and growth curves, solves an optimal harvest schedule, and returns disturbance rasters that LandR applies as cohort removals
- Growth curves are generated from LandR's own parameterization (not external yield tables) via a new standalone module
- The coupling frequency is a single configurable parameter — default 10-year periods, but any value including annual is supported
- The system is designed for Canada-wide use; TSA41 (Dawson Creek, BC) is the default test area
- Harvest action handling is extensible: clearcut only at first, architecture ready for a team-supplied `partialDisturbance` module

---

## Architecture

**Approach:** Two new SpaDES modules plus an orchestrating `global.R`. All bridging logic is encapsulated in modules with well-defined `inputObjects` / `outputObjects`. WS3 (Python) is called via `reticulate`.

### Modules

| Module | Type | Role |
|---|---|---|
| `Biomass_borealDataPrep` | existing | Prepares forest inventory, species parameters, pixelGroupMap |
| `Biomass_core` | existing | Annual succession — growth, mortality, ANPP |
| `biomass_yieldTablesWS3` | **new** | Generates and caches WS3-compatible yield curves per development type |
| `Biomass_ws3Harvest` | **new** | Bridges LandR↔WS3: inventory in, WS3 solve, harvest schedule out |
| Fire / disturbance modules | existing (optional) | Independent disturbance channels — slot into `modules` list in `global.R` |

### Event Schedule

| Module | Event | Timing |
|---|---|---|
| `biomass_yieldTablesWS3` | `init` | Once at sim start — initialise cache |
| `biomass_yieldTablesWS3` | `updateCurves` | Every `ws3PeriodLength` years |
| `Biomass_ws3Harvest` | `init` | Once at sim start — initialise WS3 ForestModel |
| `Biomass_ws3Harvest` | `ws3Plan` | Every `ws3PeriodLength` years, after `updateCurves` |
| `Biomass_core` | (all existing events) | Annual |

`updateCurves` is scheduled at higher priority than `ws3Plan` within the same timestep to guarantee curves are ready before the solve.

---

## Development Types

WS3 development types are defined as tuples:

```
(speciesCode, site_quality, ecoregion)
```

- **`speciesCode`** — from LandR `cohortData$speciesCode`
- **`site_quality`** — binned from `maxANPP / species$maxANPP` ratio into `low / med / high` using `siteQualityBins` parameter (default thresholds: `c(0.33, 0.67)`)
- **`ecoregion`** — from `speciesEcoregion`

Each unique tuple is one WS3 development type. Ecolocations in LandR correspond directly to WS3 development types.

---

## Module: `biomass_yieldTablesWS3`

### Purpose
Generate m³/ha yield curves for WS3, one per development type, before each planning cycle. Cache curves across periods — only simulate new development types.

### File Structure
```
modules/biomass_yieldTablesWS3/
├── biomass_yieldTablesWS3.R
└── R/
    ├── simStand.R          # SpaDES sim per dev type (Biomass_core only, no dispersal)
    ├── boudewynConvert.R   # biomass → m³/ha via CBMutils Boudewyn pipeline
    └── curveCache.R        # cache read / write / diff logic
```

### SpaDES Metadata

**inputObjects:**

| Object | Class | Source |
|---|---|---|
| `cohortData` | `data.table` | `Biomass_core` |
| `species` | `data.table` | `Biomass_borealDataPrep` |
| `speciesEcoregion` | `data.table` | `Biomass_borealDataPrep` |
| `pixelGroupMap` | `SpatRaster` | `Biomass_borealDataPrep` |

**outputObjects:**

| Object | Class | Description |
|---|---|---|
| `ws3YieldCurves` | named list | Keyed by dev type tuple string; each element is `data.frame(age, vol_m3ha)` |

**Parameters:**

| Parameter | Default | Description |
|---|---|---|
| `ws3PeriodLength` | from `.globals` | Years between WS3 solves |
| `maxSimAge` | `300` | Maximum stand age simulated for yield curves |
| `siteQualityBins` | `c(0.33, 0.67)` | Thresholds for low/med/high site quality bins |

### `updateCurves` Event Logic

1. **Scan** — extract unique `(speciesCode, site_quality, ecoregion)` tuples from current `cohortData` + `speciesEcoregion`. Site quality binned using `maxANPP / species$maxANPP` against `siteQualityBins`.
2. **Diff** — compare observed tuples against keys in `ws3YieldCurves` cache. Identify new tuples only.
3. **Simulate** — for each new tuple: spin up a lightweight `simInitAndSpades()` with only `Biomass_core` loaded (no dispersal, no seed rain, no fire). Initialise a single-cohort stand at age 0 with parameters matching the dev type's `speciesCode` and site quality. Run to `maxSimAge`. Extract `B` (g/m²) by age. This approach mirrors `Biomass_yieldTables` — growth/mortality/ANPP are handled natively by Biomass_core.
4. **Convert** — for each age step:
   - `B (g/m²) → tonnes/ha` (divide by 100)
   - Apply Boudewyn Table 6_tb (from `LandRCBM_split3pools`) multinomial logistic → merchantable stemwood fraction
   - Inverse Boudewyn Table 3 (from `CBM_vol2biomass`): `vol = (b_m / a)^(1/b)` → m³/ha
   - Keyed by `canfi_species × juris_id × ecozone` (derived from ecoregion via bundled lookup table)
   - Uses `CBMutils` functions throughout
5. **Cache** — merge new curves into `ws3YieldCurves`. Write cache to `outputs/ws3YieldCurves.rds` for recovery across sessions.

---

## Module: `Biomass_ws3Harvest`

### Purpose
The coupling workhorse: initialises WS3, translates LandR inventory into WS3 development type areas, triggers the WS3 solve, and applies the resulting harvest schedule back to LandR as cohort removals.

### File Structure
```
modules/Biomass_ws3Harvest/
├── Biomass_ws3Harvest.R
└── R/
    ├── inventoryBridge.R   # cohortData → WS3 dev type areas
    ├── harvestBridge.R     # WS3 schedule → rstCurrentHarvest + cohortData edits
    ├── siteQuality.R       # maxANPP/maxB → low/med/high bins
    └── actionDispatch.R    # extensible action handler (clearcut now, partial cut later)
```

### SpaDES Metadata

**inputObjects:**

| Object | Class | Source |
|---|---|---|
| `cohortData` | `data.table` | `Biomass_core` |
| `pixelGroupMap` | `SpatRaster` | `Biomass_core` |
| `biomassMap` | `SpatRaster` | `Biomass_core` |
| `species` | `data.table` | `Biomass_borealDataPrep` |
| `speciesEcoregion` | `data.table` | `Biomass_borealDataPrep` |
| `ws3YieldCurves` | named list | `biomass_yieldTablesWS3` |

**outputObjects:**

| Object | Class | Description |
|---|---|---|
| `rstCurrentHarvest` | `SpatRaster` | Harvest disturbance raster (consumed by Biomass_core) |
| `cohortData` | `data.table` | Modified in-place: harvested cohorts zeroed |
| `ws3HarvestSchedule` | `data.table` | Full WS3 solution for the period (for reporting) |

**Parameters:**

| Parameter | Default | Description |
|---|---|---|
| `ws3PeriodLength` | from `.globals` | Years between WS3 solves |
| `ws3Horizon` | `10` | Number of WS3 planning periods |
| `ws3BaseYear` | `2011` | Calendar year for WS3 period 0 |
| `ws3MinHarvestAge` | `40` | Minimum stand age eligible for harvest |
| `ws3Solver` | `"highs"` | WS3 solver backend (`"highs"`, `"gurobi"`, or `"pulp"`) |

### `init` Event

- Verify Python environment; stop with informative message if `ws3` is not importable
- Import `ws3` via `reticulate`
- Construct `ForestModel` with `base_year = ws3BaseYear`, `horizon = ws3Horizon`, `period_length = ws3PeriodLength`
- Register action `"clearcut"` with full cohort removal semantics
- Set up `hdt_map` linking dev type tuples ↔ raster hash values

### `ws3Plan` Event

**Step 1 — Inventory bridge (`inventoryBridge.R`):**
1. Join `cohortData` → `speciesEcoregion` → bin `maxANPP / species$maxANPP` into site quality classes
2. Map each cohort to dev type tuple `(speciesCode, site_quality, ecoregion)`
3. Aggregate pixel area by dev type × age class: `age_class = floor(age / ws3PeriodLength)`
4. Call `fm.initialize_areas()` and load yield curves from `ws3YieldCurves`
5. Apply minimum harvest age filter via WS3 eligibility rules

**Step 2 — WS3 solve:**
1. `fm.add_problem()` with even-flow harvest constraints
2. `p.solve()` using configured solver
3. Assert `p.status() == "optimal"` — if not, log warning and skip harvest for this period

**Step 3 — Harvest bridge (`harvestBridge.R`):**
1. `ForestRaster.allocate_schedule()` → clearcut GeoTIFFs, one per year in the upcoming period
2. Load each GeoTIFF as `rstCurrentHarvest`
3. Identify harvested pixels → look up cohorts via `pixelGroupMap` → zero `B`, flag for mortality
4. `actionDispatch.R` routes by action code — `"clearcut"` removes cohort fully; partial cut slot present but empty, ready for integration with team's `partialDisturbance` module

---

## `global.R`

Single entry point — source from terminal. All simulation parameters set here.

```r
if (!require("SpaDES.project")) {
  Require::Install("PredictiveEcology/SpaDES.project@transition")
}

# ── Project-level parameters ──────────────────────────────────────────────────
ws3PeriodLength <- 10    # years between WS3 solves (1 = annual, 10 = default)
ws3Horizon      <- 10    # number of WS3 planning periods
ws3BaseYear     <- 2011

out <- SpaDES.project::setupProject(

  paths = list(
    projectPath = getwd(),
    modulePath  = "modules",
    inputPath   = "inputs",
    outputPath  = "outputs",
    cachePath   = "cache"
  ),

  times = list(
    start = ws3BaseYear,
    end   = ws3BaseYear + ws3PeriodLength * ws3Horizon
  ),

  modules = c(
    "PredictiveEcology/Biomass_borealDataPrep@main",
    "PredictiveEcology/Biomass_core@main",
    "AllenLarocque/biomass_yieldTablesWS3@main",
    "AllenLarocque/Biomass_ws3Harvest@main"
    # add fire/disturbance modules here as needed
  ),

  params = list(
    .globals = list(
      ws3PeriodLength = ws3PeriodLength
    ),
    biomass_yieldTablesWS3 = list(
      maxSimAge       = 300,
      siteQualityBins = c(0.33, 0.67)
    ),
    Biomass_ws3Harvest = list(
      ws3Horizon       = ws3Horizon,
      ws3BaseYear      = ws3BaseYear,
      ws3MinHarvestAge = 40,
      ws3Solver        = "highs"
    )
  ),

  # Default study area: TSA41 (Dawson Creek TSA, northeastern BC)
  # Swap for any Canadian polygon to change study area
  studyArea = {
    if (!require("bcdata")) Require::Install("bcdata")
    tsa41 <- Cache(
      function() {
        bcdata::bcdc_query_geodata("8daa29da-d7f4-401c-83ae-d962e3a28980") |>
          dplyr::filter(TSA_NUMBER == "41") |>
          dplyr::collect() |>
          sf::st_union() |>
          sf::st_as_sf()
      }
    )
    sf::st_transform(tsa41, crs = "+proj=lcc +lat_1=49 +lat_2=77 +lat_0=0
                                    +lon_0=-95 +datum=NAD83 +units=m")
  },

  studyAreaLarge = {
    sf::st_buffer(studyArea, dist = 20000)
  },

  packages = c("terra", "data.table", "reticulate", "bcdata", "sf"),

  options = list(
    spades.allowInitDuringSimInit = TRUE,
    reproducible.useCache         = TRUE
  )
)

do.call(SpaDES.core::simInitAndSpades, out)
```

---

## Biomass → Volume Conversion Pipeline

Uses the Boudewyn et al. (2007) framework already established in the PredictiveEcology stack:

```
LandR B (g/m²)
  ÷ 100 → tonnes/ha
  → Table 6_tb (LandRCBM_split3pools): multinomial logistic → merchantable stemwood fraction
  → inverse Table 3 (CBM_vol2biomass): vol = (b_m / a)^(1/b) → m³/ha
```

All Boudewyn parameters stratified by `canfi_species × juris_id × ecozone`. A bundled lookup table maps LandR `speciesCode × ecoregion` → `canfi_species × juris_id × ecozone`. `CBMutils` functions used throughout — consistent with LandRCBM and CBM_vol2biomass.

---

## Error Handling

| Failure | Response |
|---|---|
| WS3 solve infeasible / non-optimal | `warning()` with status code; skip harvest for period; continue sim |
| Dev type in inventory with no yield curve | `warning()`; drop dev type from WS3 inventory for that period |
| Python / reticulate / ws3 import failure | `stop()` at `init` with setup instructions |
| `studyAreaLarge` missing or not enclosing `studyArea` | Caught by `Biomass_borealDataPrep` — fix in `global.R` |

---

## Testing

| Test | Location | Assertion |
|---|---|---|
| Yield curve for single dev type | `biomass_yieldTablesWS3/tests/` | Valid `(age, vol_m3ha)`, non-decreasing, no NAs |
| Cache diff — new dev type only simulated | `biomass_yieldTablesWS3/tests/` | Only new tuple triggers simulation |
| Inventory bridge — known cohortData | `Biomass_ws3Harvest/tests/` | Dev type area totals match expected |
| Harvest bridge — known schedule | `Biomass_ws3Harvest/tests/` | Correct cohorts zeroed in `cohortData` |
| End-to-end — TSA41, 1 period | `global.R` short run | `rstCurrentHarvest` non-empty; `cohortData` B values updated |

---

## Key References

- [spades.ai](https://github.com/AllenLarocque/spades.ai) — SpaDES AI context docs
- [ws3.ai](https://github.com/AllenLarocque/ws3.ai) — WS3 AI context docs
- [WS3 source](https://github.com/UBC-FRESH/ws3) — UBC FRESH WS3 library
- [WS3 documentation](https://ws3.readthedocs.io/en/dev/)
- [Biomass_borealDataPrep](https://github.com/PredictiveEcology/Biomass_borealDataPrep)
- [Biomass_core](https://github.com/PredictiveEcology/Biomass_core)
- [Biomass_yieldTables](https://github.com/DominiqueCaron/Biomass_yieldTables) — pattern for `biomass_yieldTablesWS3`
- [LandRCBM_split3pools](https://github.com/PredictiveEcology/LandRCBM_split3pools) — Boudewyn Table 6_tb
- [CBM_vol2biomass](https://github.com/PredictiveEcology/CBM_vol2biomass) — Boudewyn Table 3 inverse
- [simpleHarvest](https://github.com/pkalanta/simpleHarvest/tree/parvintesting) — netdown pattern reference
- [LandR_WS3_IO_comparison.md](.ai_docs/LandR_WS3_IO_comparison.md) — full I/O mapping
