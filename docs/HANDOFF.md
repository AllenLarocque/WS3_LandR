# Handoff: WS3_LandR (updated 2026-11-10)

WS3-LandR is the LandR-forward stack. LandR grows the forest, `biomass_yieldTablesWS3` turns LandR
growth into merchantable-volume yield curves, ws3 (Python, via reticulate) solves the harvest
schedule, `biomass_ws3Harvest` applies the cuts to LandR, and `ws3Verify` draws diagnostics.
Assembled spring 2026; brought back to life 2026-11-10.

## State (2026-11-10)

`Rscript global.R` runs end to end (2011-2111, ~7 min once inputs are cached; the first
simInit took 1.7 h of downloads). **But it harvests nothing**: see "Harvest planning is broken".

Project branch `feature/setupproject-baseline`:
- `global.R` on the FIIS pattern: `useGit = "sub"` (modules are git submodules), packages only
  via `setupProject(packages =)` into `packages/`, `SpaDES.project.strict`, `defaultDots` for the
  settings, ws3 from `reticulate::py_require("ws3")` (builds `~/.virtualenvs/r-reticulate`).
- Study area: `.units` (BC TSAs via `timberSupply::bcManagementUnit()`), shrunk `.inwardBuffer`
  m. Defaults reproduce spring's RIA (TSAs 08, 16, 24, 40, 41) minus 150 km = 1.39 M ha.
  `R/studyArea.R::inwardBuffer()` does the shrink on a raster: a GEOS negative buffer of that
  outline ran out of memory (>30 GB).
- `standAgeMap` is built on `rasterToMatch` (Biomass_borealDataPrep's working grid).
- The LandR `makeEcoregionMap` monkey-patch moved unchanged to `R/patchLandR.R`.
- The vendored `modules/biomass_ws3Harvest` copy is gone; its 2026-03-30 ForestRaster commits are
  on the module fork.

Module branches (all on Allen's forks, pinned by `global.R` / the submodules):

| Repo | Branch | What |
|---|---|---|
| biomass_ws3Harvest | `feature/forestraster-spatial-allocation` | spring ForestRaster work + fixes below |
| biomass_ws3Harvest | `fix/ws3-integer-age-class` | `age_class` integer (merged into the feature branch) |
| biomass_yieldTablesWS3 | `fix/pice-eng-canfi-code` | Pice_eng was mapped to Boudewyn 106 (Sitka); now 104 |
| biomass_yieldTablesWS3 | `feature/pice-eng-gla-lookup` | adds LandR's merged `Pice_eng_gla` -> 105 (white spruce); stacked on the fix |

## Harvest planning is broken (found 2026-11-10; next to fix)

1. **Age units mixed.** `buildWs3Inventory()` gives ws3 ages in periods (`floor(age / 10)`), but
   the clearcut operability (`_age >= ws3MinHarvestAge` = 40) and the yield curves are in years.
   A 100-year stand is age 10 to ws3, so almost nothing is operable.
2. **Area counted more than once.** ws3 inventory = 2.51 M ha vs 1.39 M ha study area:
   each pixel's area goes to every species dev type on it (~2.7 cohorts per pixel group).
3. Consequently the problem covers ~3,300 ha per period; the solution is all `null` except
   periods 5 and 9; the spatial allocation finds almost no cells.
4. `ForestModel` keeps the default `max_age` 1000 (periods).

## Upstream bugs to report (not fixed upstream)

- **ws3** (`UBC-FRESH/ws3`, <= 1.0.5 and main 2026-08): `ForestRaster.allocate_schedule()` looks
  transitions up by exact age, with no fallback to age -1 (unconditioned transitions) as
  `ForestModel.apply_action()` has. Worked around in biomass_ws3Harvest.
- **Biomass_borealDataPrep**: calls `LandR::.compareRas()` without `stopOnError = FALSE`, so its
  reprojection of a mismatched `standAgeMap`/`rstLCC`/... never runs; it errors instead.
- **LandR** `makeEcoregionMap`: the bug patched in `R/patchLandR.R` (needs its own PR; check
  whether current LandR still needs it).

## Coupling problems for interchangeable harvest modules (second stage)

- `biomass_ws3Harvest` `source()`s `siteQuality.R`/`curveCache.R` out of the
  `biomass_yieldTablesWS3` module folder.
- It hard-codes site-quality bins `c(0.33, 0.67)` instead of `siteQualityBins`.
- `biomass_yieldTablesWS3`: Boudewyn lookup has ecozone 9 for every species and `juris_id = "BC"`
  in code; both should be inputs for a study-area-agnostic module.
- Compare with cccandies (`spades_ws3*`) and FIIS (`simpleHarvestPlanning`, `Biomass_yieldTables`).

Background: `/workspace/SpaDES_harvesting/docs/BRIEF-phase1-inventory.md` (convergence plan) and
`docs/project-history/2025-2026/Allen's WS3 Exit Document.md` there.
