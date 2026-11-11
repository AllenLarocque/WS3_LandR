# Handoff: WS3_LandR (updated 2026-11-10)

WS3-LandR is the LandR-forward stack. LandR grows the forest, `biomass_yieldTablesWS3` turns LandR
growth into merchantable-volume yield curves, ws3 (Python, via reticulate) solves the harvest
schedule, `biomass_ws3Harvest` applies the cuts to LandR, and `ws3Verify` draws diagnostics.
Assembled spring 2026; brought back to life 2026-11-10.

## State (2026-11-10)

`Rscript global.R` runs end to end and harvests (2011-2111, ~5 min once inputs are cached; the
first simInit took 1.7 h of downloads). Harvested 84,000-186,000 ha per decade out of 1.03 M ha of
forest; the first plan is 15-16.6 M m3 per decade under the 5% even-flow limit. Cut cells were
checked in LandR for 2011 and 2021: all hold only young cohorts or none.

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
| biomass_ws3Harvest | `fix/ws3-inventory-handoff` | the four ws3 hand-off faults below (fast-forwarded into the feature branch) |
| biomass_ws3Harvest | `fix/ws3-integer-age-class` | `age_class` integer (merged into the feature branch) |
| biomass_yieldTablesWS3 | `fix/pice-eng-canfi-code` | Pice_eng was mapped to Boudewyn 106 (Sitka); now 104 |
| biomass_yieldTablesWS3 | `feature/pice-eng-gla-lookup` | adds LandR's merged `Pice_eng_gla` -> 105 (white spruce); stacked on the fix |

## ws3 hand-off faults (fixed 2026-11-10)

ws3 ages are in **years** (it adds `period_length` per period). The module gave it periods. Also:
- each pixel's area went to every species on it (2.51 M ha on a 1.39 M ha study area); the
  dominant cohort now holds the pixel, in both the inventory and the raster;
- inventory was loaded to a period `reset()` discards, so every replan reused the 2011 forest;
- the solved schedule was never applied: `applied_actions` held the last tree `add_problem` built;
- the even-flow settings passed through R, whose string keys made ws3 build no flow constraint.

Python objects that ws3 reads must not round-trip through R (`convert = FALSE`, or keep it in Python).

## Open issues in the harvest model

- A pixel's whole area and yield come from its dominant cohort's single-species curve.
- All ten years of a period's cuts reach LandR at once, at the start of the period.
- `applyClearcut` removes a whole pixel group when any of its pixels is cut. Pixel groups are not
  contiguous, so blocks are scattered, and a split block is cut in full.
- Harvested area climbs from 84,000 to 186,000 ha per decade: not investigated.
- Two `test-spatialBridge.R` tests fail, before these fixes too (lines ~80, ~165): they read
  the inventory with terra, which returns the written 0 as NA. ws3 reads the raw 0.

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
