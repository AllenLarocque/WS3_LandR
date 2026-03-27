# WS3-LandR

NOTE: AI EXPERIMENTAL REPO. TECHNICALLY RUNS BUT STRONG POSSIBILITY IT IS SLOP AND/OR BROKEN

A coupled forest simulation framework integrating **LandR** (landscape-level forest succession) with **WS3** (wood supply optimization). The system simulates boreal forest growth over a 100-year horizon, generates merchantable volume yield curves, solves harvest schedules using linear programming, and feeds harvests back into the succession model.

**Study area**: Resource Inventory Area (RIA), British Columbia — TSA 08, 16, 24, 40, 41
**Temporal resolution**: Annual growth, 10-year harvest planning periods
**Spatial resolution**: 250 m pixels, Lambert Conformal Conic (NAD83)

---

## Simulation Schematic

```mermaid
flowchart TD
    subgraph INPUTS["Input Data"]
        A1[NFI kNN 2001/2011\nSpecies cover · Stand age · Biomass]
        A2[NTEMS Land Cover]
        A3[LANDIS-II Species Traits\n& Ecoregion Parameters]
        A4[RIA Study Area Polygon\nTSA 08, 16, 24, 40, 41]
    end

    subgraph INIT["Initialization  t = 2011"]
        B1["Biomass_borealDataPrep\n─────────────────────\nFit biomass/cover models from NFI\nEstimate maxB, maxANPP per species × ecoregion\nGenerate initial cohortData & pixelGroupMap"]
        B2["Biomass_core\n─────────────────────\nValidate ecoregion & cohort maps\nSchedule succession events"]
        B3["biomass_yieldTablesWS3\n─────────────────────\nInitialize yield curve cache"]
        B4["biomass_ws3Harvest\n─────────────────────\nImport ws3 Python module\nInitialize ForestModel\nRegister clearcut + grow-in-place actions"]
    end

    subgraph PERIOD["Planning Period Loop  — repeats for t = 2011, 2021, ..., 2101"]

        subgraph ANNUAL["Annual Growth  Biomass_core"]
            C1["For each year in period:\n· Seed dispersal & regeneration\n· ANPP production\n· Growth & mortality (age + competition)\n· Update cohortData → biomassMap"]
        end

        subgraph YC["Yield Curve Update  biomass_yieldTablesWS3  priority 1"]
            D1["Bin site quality:\nmaxANPP ÷ global_maxANPP → low / med / high"]
            D2["Scan cohortData for unique\n(species, site_quality, ecoregion)\ndevelopment types"]
            D3["For each new dev type:\nsimulateStand() age 0–300\n(single-cohort LANDIS-II, no fire)"]
            D4["boudewynBiomassToVol()\nLandR B → AGB fraction → vol m³/ha\n(Boudewyn et al. 2007)"]
            D5["Cache curve\nage → vol_m3ha\nOutputs: ws3YieldCurves.rds"]
            D1 --> D2 --> D3 --> D4 --> D5
        end

        subgraph WS3["Harvest Planning & Application  biomass_ws3Harvest  priority 2"]
            E1["Inventory Bridge:\nbinSiteQuality → devType tuples\nAggregate area_ha by\n(devType, age_class)"]
            E2["Load WS3 ForestModel:\nCreate dtypes · Attach yield curves\nLoad inventory areas"]
            E3["Solve Harvest Problem:\nObjective: maximize harvested volume\nConstraint: even-flow ≤ 5% per period\nSolver: HiGHS"]
            E4["Apply Harvest per year:\nRead clearcut GeoTIFF\nIdentify harvested pixel groups\nSet cohortData B = 0\nStore rstCurrentHarvest"]
            E1 --> E2 --> E3 --> E4
        end

        subgraph REGEN["End-of-Period Regeneration  Biomass_core"]
            F1["Process rstCurrentHarvest:\nClear harvested cohorts\nSchedule year-1 regeneration"]
        end

        ANNUAL --> YC
        YC --> WS3
        WS3 --> REGEN
        REGEN -->|"next period"| ANNUAL
    end

    subgraph OUTPUTS["Outputs"]
        G1[cohortData — forest inventory\nwith full harvest history]
        G2[biomassMap — total biomass\nper pixel per year]
        G3[ws3YieldCurves.rds\nPersistent curve cache]
        G4["harvest/*.tif\nSpatial disturbance rasters"]
        G5[ws3HarvestSchedule\nPeriod × action × area table]
    end

    INPUTS --> INIT
    INIT --> PERIOD
    PERIOD --> OUTPUTS
```

---

## Module Overview

| Module | Role | Key Inputs | Key Outputs |
|---|---|---|---|
| **Biomass_borealDataPrep** | Parameterize succession from open Canadian data | NFI, NTEMS, study area | `species`, `speciesEcoregion`, `cohortData`, `pixelGroupMap` |
| **Biomass_core** | Simulate annual forest growth, mortality, and regeneration | `cohortData`, `pixelGroupMap`, `rstCurrentHarvest` | `cohortData`, `biomassMap`, `pixelGroupMap` |
| **biomass_yieldTablesWS3** | Generate merchantable volume yield curves per development type | `cohortData`, `speciesEcoregion` | `ws3YieldCurves` |
| **biomass_ws3Harvest** | Build forest inventory, solve harvest schedule, apply disturbance | `cohortData`, `ws3YieldCurves` | `cohortData`, `rstCurrentHarvest`, `ws3HarvestSchedule` |

---

## Key Parameters

| Parameter | Default | Description |
|---|---|---|
| `ws3BaseYear` | 2011 | Calendar year of period 0 |
| `ws3PeriodLength` | 10 | Years per planning period |
| `ws3Horizon` | 10 | Number of planning periods (100-year sim) |
| `ws3MinHarvestAge` | 40 | Minimum operability age for harvest |
| `ws3Solver` | `"highs"` | LP solver (`"highs"`, `"gurobi"`, `"pulp"`) |
| `maxSimAge` | 300 | Maximum age for yield curve simulation |
| `siteQualityBins` | `[0.33, 0.67]` | Thresholds for low / med / high site quality |

---

## Running the Simulation

```r
source("global.R")
```

`global.R` handles package installation, Python venv configuration (`~/.venvs/ws3`), study area setup, and launches the coupled SpaDES simulation via `simInit2()` + `spades()`.

---

## Dependencies

- **R**: `SpaDES.project`, `SpaDES.core`, `LandR`, `data.table`, `terra`, `reticulate`
- **Python**: `ws3` (wood supply model), `highspy` (HiGHS solver)
- **Data**: Canadian NFI kNN layers, NTEMS land cover, BC TSA boundaries
