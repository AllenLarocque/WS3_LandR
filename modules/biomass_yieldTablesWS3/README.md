# biomass_yieldTablesWS3

A [SpaDES](https://spades.predictiveecology.org/) module that generates and caches WS3-compatible m³/ha yield curves for each development type present in a LandR simulation. Designed to be used alongside [`biomass_ws3Harvest`](https://github.com/AllenLarocque/biomass_ws3Harvest) to couple LandR forest succession with WS3 wood supply optimization.

## Overview

Before each WS3 planning cycle, this module:

1. Scans the current `cohortData` for unique **development types** — `(speciesCode, site_quality, ecoregion)` tuples
2. Checks a persistent curve cache and identifies only **new** development types
3. Simulates each new development type using a minimal `Biomass_core`-only SpaDES run (no dispersal, no fire, no seed rain) from age 0 to `maxSimAge`
4. Converts simulated biomass (g/m²) to merchantable stem volume (m³/ha) using the [Boudewyn et al. (2007)](https://cfs.nrcan.gc.ca/publications?id=27392) allometric pipeline
5. Merges new curves into the cache and saves to disk

Yield curves are keyed by pipe-delimited tuple string (e.g. `"Pice_mar|med|eco1"`) and passed to `biomass_ws3Harvest` via the shared `ws3YieldCurves` sim object.

## Development Types

Development types are defined as tuples:

```
(speciesCode, site_quality, ecoregion)
```

- **`speciesCode`** — from `cohortData$speciesCode` (LandR species codes, e.g. `Pice_mar`)
- **`site_quality`** — `"low"`, `"med"`, or `"high"`, binned from the ratio `maxANPP / species$maxANPP` using `siteQualityBins` thresholds
- **`ecoregion`** — from `speciesEcoregion$ecoregionGroup`

## Biomass → Volume Conversion

Uses the Boudewyn et al. (2007) framework implemented directly from NFIS tables:

```
LandR B (g/m²)
  ÷ 100 → tonnes/ha
  → Table 6_tb (multinomial logistic): AGB → merchantable stemwood fraction
  → inverse Table 3: vol = (b_m / a)^(1/b) → m³/ha
```

Parameters are stratified by `canfi_species × juris_id × ecozone`. A bundled lookup table (`data/species_boudewyn_lookup.csv`) maps LandR `speciesCode` → Boudewyn keys for 11 common boreal BC species.

## SpaDES Metadata

### Input Objects

| Object | Class | Source |
|---|---|---|
| `cohortData` | `data.table` | `Biomass_core` |
| `species` | `data.table` | `Biomass_borealDataPrep` |
| `speciesEcoregion` | `data.table` | `Biomass_borealDataPrep` |
| `pixelGroupMap` | `SpatRaster` | `Biomass_borealDataPrep` |

### Output Objects

| Object | Class | Description |
|---|---|---|
| `ws3YieldCurves` | named list | Keyed by dev type tuple string; each element is `data.frame(age, vol_m3ha)` |

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `ws3PeriodLength` | from `.globals` | Years between WS3 planning solves |
| `maxSimAge` | `300` | Maximum stand age simulated for yield curves |
| `siteQualityBins` | `c(0.33, 0.67)` | Thresholds for low/med/high site quality bins |

### Events

| Event | Priority | Timing |
|---|---|---|
| `init` | — | Once at sim start — load cache |
| `updateCurves` | 1 | Every `ws3PeriodLength` years (before `ws3Plan` at priority 2) |

## File Structure

```
biomass_yieldTablesWS3/
├── biomass_yieldTablesWS3.R   # SpaDES module definition + doEvent dispatcher
├── R/
│   ├── siteQuality.R          # binSiteQuality(): low/med/high classification
│   ├── curveCache.R           # loadCurveCache(), saveCurveCache(), diffDevTypes()
│   ├── simStand.R             # simulateStand(): minimal Biomass_core sim per dev type
│   └── boudewynConvert.R      # boudewynBiomassToVol(): B → m³/ha via NFIS tables
└── data/
    └── species_boudewyn_lookup.csv   # speciesCode → canfi_species / juris_id / ecozone
```

## Usage

This module is meant to be used as part of the LandR–WS3 coupled system. See [`global.R`](https://github.com/AllenLarocque/WS3_LandR) for a complete setup example using `SpaDES.project::setupProject()`.

```r
modules = c(
  "PredictiveEcology/Biomass_borealDataPrep@main",
  "PredictiveEcology/Biomass_core@main",
  "AllenLarocque/biomass_yieldTablesWS3@main",
  "AllenLarocque/biomass_ws3Harvest@main"
)
```

## Dependencies

- R: `SpaDES.core`, `data.table`, `terra`, `qs2`
- Biomass_core (downloaded automatically if not present in `modulePath`)
- NFIS Boudewyn tables: downloaded automatically on first run to `inputs/`

## Related Modules

- [`biomass_ws3Harvest`](https://github.com/AllenLarocque/biomass_ws3Harvest) — consumes `ws3YieldCurves`; runs the WS3 solve and applies harvest
- [`Biomass_core`](https://github.com/PredictiveEcology/Biomass_core) — used internally to simulate stand growth
- [`Biomass_borealDataPrep`](https://github.com/PredictiveEcology/Biomass_borealDataPrep) — provides species and ecoregion parameters

## References

- Boudewyn, P., Song, X., Magnussen, S., & Gillis, M. D. (2007). *Model-based, volume-to-biomass conversion for forested and vegetated land in Canada*. Natural Resources Canada, Canadian Forest Service.
- Scheller, R. M., & Mladenoff, D. J. (2004). LANDIS-II / LandR Biomass model.
- Nelson, J. (2003). *Forest-level models and challenging policy: a case study.* UBC Faculty of Forestry. (WS3)
