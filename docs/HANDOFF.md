# Handoff: WS3_LandR (updated 2026-11-18)

WS3-LandR is the LandR-forward stack. LandR grows the forest, `biomass_yieldTablesWS3` turns LandR
growth into merchantable-volume yield curves, ws3 (Python, via reticulate) solves the harvest
schedule, `biomass_ws3Harvest` applies the cuts to LandR, and `ws3Verify` draws diagnostics.
Assembled spring 2026; brought back to life 2026-11-10.

## State (2026-11-18): working standalone; next is stage 2 (interchangeable harvest modules)

`Rscript global.R` runs 2011-2111 cleanly in ~5-6 min once inputs are cached (the first simInit
took 1.7 h of downloads). Per decade, from logs/decades3.log (one plan per decade):

| | 2011 | 2041 | 2071 | 2101 |
|---|---|---|---|---|
| planned cut (ha) | 106,069 | 87,052 | 108,559 | 200,069 |
| cut cells allocated (ha) | 105,625 | 86,594 | 103,038 | 193,725 |
| planned volume (M m3 / decade) | 15.8 | 14.7 | 16.1 | 17.8 |
| m3/ha cut | 149 | 169 | 148 | 89 |

Checked: the plan holds within the 5% even-flow limit; LandR empties exactly the allocated cells
in the allocated year; no forest is lost (cut cells sit at pixelGroup 0 until Biomass_core's next
10-year seeding step, which refills ~92%). All module unit tests pass. Codex reviewed the stack
(2026-11-18); its fixable findings are in `fix/ws3-allocation-checks`.

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
| biomass_ws3Harvest | `fix/ws3-inventory-handoff` | the five ws3 hand-off faults below (fast-forwarded into the feature branch) |
| biomass_ws3Harvest | `fix/ws3-harvest-application` | cut only the allocated cells, each in its own year; two raster tests fixed |
| biomass_ws3Harvest | `fix/ws3-allocation-checks` | Codex review: exact-age allocation, grid/cell-area check, empty-plan guard, stale outputs |
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

## Harvest application faults (fixed 2026-11-18)

- A clearcut removed every pixel group with a cut cell. Pixel groups are not contiguous and
  regenerated stands share one across thousands of pixels: LandR lost 0.1% (2011) to 54% (2101)
  more forest than ws3 allocated. Cut cells now get pixelGroup 0 (LandR's treed-but-empty code).
- A period's ten annual rasters were applied at its start; a yearly `harvest` event applies each.
- ws3's raster allocation took cells one age class off the scheduled age (below the minimum).

## Open issues in the harvest model

- The allocated area falls 0.4-5% short of the plan (ws3 rounds each year's target separately and
  now finds only exact-age cells). The reported schedule is the plan, not the allocation.
- The harvest rises from ~85,000 to ~200,000 ha and 13.4 to 18.8 M m3 per decade: each replan
  re-optimises with no ending-inventory or cross-plan flow constraint, so it keeps raising the
  target while m3/ha falls. A modelling choice to make, not a bug.
- Each plan is made before that decade's cut cells are reseeded, so they are left out of it.
- A pixel's area and yield come from its dominant cohort's single-species curve.
- A cell marked for year t+9 is cut even if its stand died and regrew since the plan.
- `ws3MinHarvestAge` should be a multiple of the period length: ages are floored to 10-year
  classes, so a 45-year minimum excludes 45-49-year stands.
- `ws3Verify`'s cumulative harvest map samples `rstCurrentHarvest` once per decade, missing 9 years.
- No integration test runs a real solve through allocation and the harvest event.

## Upstream bugs to report (not fixed upstream)

- **ws3** (`UBC-FRESH/ws3`, <= 1.0.5 and main 2026-08): `ForestRaster.allocate_schedule()` looks
  transitions up by exact age, with no fallback to age -1 (unconditioned transitions) as
  `ForestModel.apply_action()` has. Worked around in biomass_ws3Harvest.
- **ws3** `ForestRaster._transition_cells()` accepts cells within one period length of the
  scheduled age (`age_tolerance`), and rounds each year's target separately. Worked around
  (exact age) in biomass_ws3Harvest `ws3ExactAgeAllocation()`.
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
