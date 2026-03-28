# ws3Verify Module — Design Spec

**Date:** 2026-03-27
**Branch:** feature/verification-plots
**Status:** Approved for implementation

---

## Overview

`ws3Verify` is a new SpaDES module that produces verification plots during the WS3-LandR simulation. It runs as a near-read-only observer — it never modifies public `sim` objects — and fires after every planning period via two scheduled events.

The module is designed to be easy to extend and tune: each plot function is a pure R function in its own file, taking plain R objects and returning a `ggplot`. Individual plots can be iterated on by sourcing a single file and calling the function directly with test data, with no SpaDES required.

---

## Module Structure

```
modules/ws3Verify/
├── ws3Verify.R                  # module definition + event dispatch
└── R/
    ├── plotYieldCurves.R        # A — vol_m³/ha vs age, one line per dev type
    ├── plotStandGrowth.R        # B — B_gm² vs age from simulateStand()
    ├── plotInventory.R          # C — area (ha) by age class bar chart
    ├── plotHarvestSchedule.R    # D — WS3 LP solution volume per period
    ├── plotSpatialHarvest.R     # E — annual + cumulative harvest rasters
    └── plotAgeMap.R             # F — stand age raster derived from cohortData
```

---

## Event Scheduling

Both events are scheduled at `eventPriority = 3` so they always fire *after* `updateCurves` (priority 1) and `ws3Plan` (priority 2) at each period boundary. Within priority 3, `plotYieldCurves` must be scheduled before `plotHarvest` in the `init` block (SpaDES fires same-priority events in scheduling order). This ordering does not affect correctness since the two event groups are independent, but it should be maintained for clarity.

| Event | Priority | Fires every | Calls |
|---|---|---|---|
| `plotYieldCurves` | 3 | `ws3PeriodLength` years | A, B |
| `plotHarvest` | 3 | `ws3PeriodLength` years | C, D, E, F |

---

## Module Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `.plots` | character | `"png"` | Output format passed to `Plots()`. Set to `NA` to disable all plots. |
| `ws3MinHarvestAge` | integer | `40L` | Minimum operability age — must match the value used in `biomass_ws3Harvest`. Used in `buildWs3Inventory()` call inside `plotHarvest` event handler. |

`ws3PeriodLength` is read from `params(sim)$.globals$ws3PeriodLength` (a global parameter, not a module-level parameter) inside the event handler — same pattern used by `biomass_ws3Harvest`.

---

## Required Packages (`reqdPkgs` in `defineModule`)

```r
reqdPkgs = list("ggplot2", "data.table", "terra", "tidyterra", "viridis")
```

`tidyterra` and `viridis` are not standard LandR dependencies and must be explicitly declared.

---

## Inputs

Declared via `expectsInput` in `defineModule`. The module declares no `outputObjects` and does not modify any public `sim` object. It uses one private `sim` slot (`sim$.ws3VerifyCumHarvest`) for internal state — see Plot E.

| Object | Class | Source |
|---|---|---|
| `ws3YieldCurves` | `list` | `biomass_yieldTablesWS3` |
| `cohortData` | `data.table` | `Biomass_core` |
| `speciesEcoregion` | `data.table` | `Biomass_borealDataPrep` |
| `species` | `data.table` | `Biomass_borealDataPrep` |
| `ws3HarvestSchedule` | `data.table` | `biomass_ws3Harvest` |
| `pixelGroupMap` | `SpatRaster` | `Biomass_core` |
| `rstCurrentHarvest` | `SpatRaster` | `biomass_ws3Harvest` |

---

## Plot Functions

Each function lives in its own file, takes only plain R objects (no `sim$`), returns a `ggplot`, and has no side effects. The event handlers in `ws3Verify.R` own all `sim$` access, helper calls, and `Plots()` calls.

### A — `plotYieldCurves(ws3YieldCurves, simYear)`
- **File:** `R/plotYieldCurves.R`
- **What:** Line plot, x = age (years), y = vol_m³/ha. One line per dev type key.
- **Style:** Coloured by `speciesCode`, faceted by `site_quality`, `theme_bw()`.
- **Title:** `"Yield Curves — year {simYear}"`
- **Data prep:** Iterates over `ws3YieldCurves` list; each element is a `data.table(age, vol_m3ha, B_gm2)`. Binds all elements into a single long `data.table`, parses the dev type key string (split on `|`) to extract `speciesCode`, `site_quality`, `ecoregionGroup` columns.

### B — `plotStandGrowth(ws3YieldCurves, simYear)`
- **File:** `R/plotStandGrowth.R`
- **What:** Line plot, x = age (years), y = B_gm². Same iteration as plot A but reads the `B_gm2` column.
- **Style:** Coloured by `speciesCode`, faceted by `site_quality`, `theme_bw()`.
- **Title:** `"Stand Growth Trajectories — year {simYear}"`
- **Data prep:** Identical to plot A except the y aesthetic is `B_gm2`.

### C — `plotInventory(ws3Inventory, simYear)`
- **File:** `R/plotInventory.R`
- **What:** Bar chart, x = age class, y = area (ha).
- **Style:** Faceted by `site_quality`, `theme_bw()`, viridis fill.
- **Title:** `"WS3 Inventory — year {simYear}"`
- **Data prep:** Accepts a pre-built `ws3Inventory` data.table (columns: `devTypeKey`, `age_class`, `area_ha`, `harvestable`, `site_quality`). The event handler in `ws3Verify.R` is responsible for building this table by calling `binSiteQuality()` and `buildWs3Inventory()` before calling `plotInventory()`. The plot function itself is pure — it only does display logic.

### D — `plotHarvestSchedule(ws3HarvestSchedule, simYear)`
- **File:** `R/plotHarvestSchedule.R`
- **What:** Bar chart, x = period, y = harvested volume (m³). Horizontal reference line at period-1 value to visualise even-flow.
- **Style:** `theme_bw()`, viridis fill.
- **Title:** `"Harvest Schedule — year {simYear}"`
- **Graceful degradation:** If `ws3HarvestSchedule` is `NULL` or has zero rows (e.g., because `ws3Plan` returned early due to a non-optimal solve), return a `ggplot()` with `annotate("text", ...)` displaying `"No harvest schedule available (non-optimal solve)"`.

### E — `plotSpatialHarvest(annualHarvestRast, cumulativeHarvestRast, simYear)`
- **File:** `R/plotSpatialHarvest.R`
- **What:** Two plots per call — annual harvest raster and cumulative harvest raster.
- **Annual:** `annualHarvestRast` is the `clearcut_{simYear}.tif` raster read by the event handler (or `NULL` if not found). If `NULL`, skips this plot silently.
- **Cumulative:** `cumulativeHarvestRast` is a running sum accumulated by the event handler, passed in as a plain `SpatRaster`.
- **Style:** `tidyterra::geom_spatraster` + `viridis::scale_fill_viridis`, `coord_equal()`, `theme_bw()`, `na.value = "transparent"`. Mirrors `plot_harvestMap()` from `simpleHarvestTesting` exactly.
- **Return value:** A named list: `list(annual = <ggplot or NULL>, cumulative = <ggplot>)`. The event handler calls `Plots()` on each element separately:
```r
plots <- plotSpatialHarvest(annualRast, sim$.ws3VerifyCumHarvest, time(sim))
if (!is.null(plots$annual))
  Plots(plots$annual, fn = identity, type = P(sim)$.plots, filename = paste0("annualHarvest_year_", time(sim)))
Plots(plots$cumulative, fn = identity, type = P(sim)$.plots, filename = paste0("cumulativeHarvest_year_", time(sim)))
```

**Titles:** `"Annual Harvest — year {simYear}"`, `"Cumulative Harvest — year {simYear}"`

**Event handler responsibility for cumulative raster:**
The `plotHarvest` event handler maintains cumulative state via a private `sim` slot:
```r
# In plotHarvest event:
if (is.null(sim$.ws3VerifyCumHarvest)) {
  sim$.ws3VerifyCumHarvest <- sim$rstCurrentHarvest
} else {
  sim$.ws3VerifyCumHarvest <- sim$.ws3VerifyCumHarvest + (sim$rstCurrentHarvest > 0)
}
plotSpatialHarvest(annualHarvestRast, sim$.ws3VerifyCumHarvest, time(sim))
```
`sim$.ws3VerifyCumHarvest` is the one private slot this module writes to. It is initialised to `NULL` in the `init` event.

`outputPath(sim)` must be resolved in the event handler and passed to the function as a plain character string for reading the annual GeoTIFF.

### F — `plotAgeMap(cohortData, pixelGroupMap, simYear)`
- **File:** `R/plotAgeMap.R`
- **What:** Stand age raster — biomass-weighted dominant age per pixel group, painted onto `pixelGroupMap`.
- **Style:** `tidyterra::geom_spatraster` + `scale_fill_viridis_c`, ages capped at 300, `na.value = "transparent"`, `theme_bw()`. Mirrors `plot_simpleHarvestageMap()` from `simpleHarvestTesting` exactly.
- **Title:** `"Stand Age Map — year {simYear}"`
- **Data prep:** Compute `BweightedAge = sum(B * age) / sum(B)` per `pixelGroup` from `cohortData`. Then reclassify `pixelGroupMap` using the resulting lookup.

---

## Key Design Principles

1. **Pure functions.** Each plot function takes plain R objects and returns a `ggplot`. No `sim$` access inside plot files. This allows any function to be developed and debugged standalone by sourcing its file and calling it directly with test data.

2. **One file per function.** Each plot lives in its own file. Adding, removing, or tweaking a plot means touching exactly one file.

3. **Event handlers own `sim$` access.** All `sim$` reads, helper function calls (e.g., `binSiteQuality`, `buildWs3Inventory`), and `Plots()` calls live in `ws3Verify.R`. Plot functions never see the sim list.

4. **Near-read-only module.** `ws3Verify` declares no `outputObjects` and never modifies public `sim` objects. The sole exception is `sim$.ws3VerifyCumHarvest` (private slot, prefixed with `.`) used to accumulate the cumulative harvest raster across periods.

5. **SpaDES `Plots()` wrapper.** All `ggplot` objects are passed to `Plots()` in the event handlers, not in the plot functions.

6. **Graceful skipping.** Plot E skips the annual plot silently if the expected GeoTIFF does not exist. Plot D returns an annotated empty plot if `ws3HarvestSchedule` is NULL or empty.

---

## Upstream Change Required: `ws3YieldCurves` Schema

Plots A and B both read from `ws3YieldCurves`. Currently each element stores only `data.frame(age, vol_m3ha)`. To support plot B, a `B_gm2` column must be added.

**Required change in `biomass_yieldTablesWS3/.updateCurves`:**

Before (current):
```r
sim$ws3YieldCurves[[key]] <- curve   # data.frame(age, vol_m3ha)
```

After:
```r
curve$B_gm2 <- ageB$B_gm2[match(curve$age, ageB$age)]
sim$ws3YieldCurves[[key]] <- curve   # data.frame(age, vol_m3ha, B_gm2)
```

The stored element remains a flat `data.table`/`data.frame` with three columns: `age`, `vol_m3ha`, `B_gm2`. No structural change to the list — only an additional column. Both plot A (`vol_m3ha`) and plot B (`B_gm2`) iterate the same list and read their respective column.

**Edge case:** If `ws3YieldCurves` is loaded from a cache that predates this schema change (missing `B_gm2`), plot B should check for column existence and return an annotated empty plot with a message: `"B_gm2 not available in cache — re-run to regenerate curves"`.

---

## Event Handler Pseudocode (`ws3Verify.R`)

This is a sketch to make the implementation unambiguous:

```r
# plotYieldCurves event handler:
sim <- scheduleEvent(sim, time(sim) + ws3PeriodLength, "ws3Verify", "plotYieldCurves", 3)
Plots(plotYieldCurves(sim$ws3YieldCurves, time(sim)),
      fn = identity, type = P(sim)$.plots,
      filename = paste0("yieldCurves_year_", time(sim)))
Plots(plotStandGrowth(sim$ws3YieldCurves, time(sim)),
      fn = identity, type = P(sim)$.plots,
      filename = paste0("standGrowth_year_", time(sim)))

# plotHarvest event handler:
sim <- scheduleEvent(sim, time(sim) + ws3PeriodLength, "ws3Verify", "plotHarvest", 3)

# Build inventory (event handler owns this, not the plot function)
speciesMaxANPP <- sim$speciesEcoregion[, .(globalMaxANPP = max(maxANPP, na.rm=TRUE)), by=speciesCode]
cd <- binSiteQuality(sim$cohortData, sim$speciesEcoregion, speciesMaxANPP, bins=c(0.33,0.67))
cellArea_ha <- terra::cellSize(sim$pixelGroupMap, unit="ha")
pixelArea   <- # ... same as biomass_ws3Harvest
ws3Inventory <- buildWs3Inventory(cd, pixelArea, ws3PeriodLength, ws3MinHarvestAge)
ws3Inventory[, site_quality := sub(".*\\|(.*)\\|.*", "\\1", devTypeKey)]

Plots(plotInventory(ws3Inventory, time(sim)), ...)
Plots(plotHarvestSchedule(sim$ws3HarvestSchedule, time(sim)), ...)

# Cumulative harvest accumulation
if (is.null(sim$.ws3VerifyCumHarvest)) {
  sim$.ws3VerifyCumHarvest <- sim$rstCurrentHarvest
} else {
  sim$.ws3VerifyCumHarvest <- sim$.ws3VerifyCumHarvest + (sim$rstCurrentHarvest > 0)
}
tifPath <- file.path(outputPath(sim), "harvest", paste0("clearcut_", time(sim), ".tif"))
annualRast <- if (file.exists(tifPath)) terra::rast(tifPath) else NULL
Plots(plotSpatialHarvest(annualRast, sim$.ws3VerifyCumHarvest, time(sim)), ...)
Plots(plotAgeMap(sim$cohortData, sim$pixelGroupMap, time(sim)), ...)
```

---

## Out of Scope

- Species-level harvest maps — `ws3Harvest` does not currently produce per-species spatial outputs.
- Harvest performance observed-vs-expected table — not currently tracked in a comparable summary table.
- Interactive or HTML output — all outputs are static PNGs via `Plots()`.
