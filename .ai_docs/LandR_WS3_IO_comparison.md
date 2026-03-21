# LandR Biomass_core ↔ WS3 Inputs & Outputs Comparison

Goal: understand where data aligns and where bridging is needed to run WS3 alongside LandR for spatially-coupled forest succession and harvest planning.

---

## 1. Forest State Representation

| Dimension | LandR Biomass_core | WS3 |
|---|---|---|
| **Unit** | Pixel group (aggregate of similar pixels) | Development type (stratum: species × site quality × zone) |
| **Spatial resolution** | Pixel-level raster (`pixelGroupMap`) | Optional raster via `ForestRaster` |
| **Age tracking** | Integer `age` per cohort per pixel group | Area distribution across age classes per development type |
| **Species** | Factor `speciesCode` per cohort | Encoded in development type theme tuple |
| **Time step** | Annual (1-year events) | Periodic (default 10-year periods) |
| **State container** | `sim$cohortData` (data.table) | `fm.dtypes` dict of `DevelopmentType` objects |

---

## 2. LandR Biomass_core — Inputs

### Required `sim$` Objects

| Object | Class | Source Module | Key Columns / Bands |
|---|---|---|---|
| `sim$cohortData` | `data.table` | `Biomass_borealDataPrep` | `pixelGroup`, `speciesCode`, `age`, `B` (g/m²), `mortality`, `aNPPAct` |
| `sim$pixelGroupMap` | `SpatRaster` | `Biomass_borealDataPrep` | 1 band: integer pixel group IDs |
| `sim$species` | `data.table` | `Biomass_speciesParameters` | `speciesCode`, `maxB`, `maxANPP`, `longevity`, `mortalityshape`, `growthcurve` |
| `sim$speciesEcoregion` | `data.table` | `Biomass_borealDataPrep` | Ecoregion × species parameter overrides |
| `sim$rstCurrentBurn` | `SpatRaster` (optional) | Disturbance modules | 1 band: 1 = burned, NA = unburned |

### `sim$cohortData` Column Detail

| Column | Type | Description |
|---|---|---|
| `pixelGroup` | integer | Foreign key to `pixelGroupMap` raster values |
| `speciesCode` | factor | Species identifier; links to `sim$species` |
| `age` | integer | Years since recruitment |
| `B` | integer | Aboveground biomass (g/m²) |
| `mortality` | integer | Cohort mortality this timestep |
| `aNPPAct` | integer | Actual ANPP this timestep (g/m²/yr) |

### `sim$species` Column Detail

| Column | Type | Role |
|---|---|---|
| `speciesCode` | factor | Unique species identifier |
| `maxB` | numeric | Asymptotic biomass ceiling (g/m²) |
| `maxANPP` | numeric | Maximum annual net productivity (g/m²/yr) |
| `longevity` | integer | Species lifespan (years) |
| `mortalityshape` | numeric | Mortality curve shape parameter |
| `growthcurve` | numeric | Growth curve exponent |

---

## 3. LandR Biomass_core — Outputs

| Object | Class | Update Timing | Content |
|---|---|---|---|
| `sim$cohortData` | `data.table` | Annual | Updated `age`, `B`, `mortality`, `aNPPAct` per cohort |
| `sim$pixelGroupMap` | `SpatRaster` | As needed | Reassigned when cohort composition changes |
| `sim$biomassMap` | `SpatRaster` | Annual snapshot | Total aboveground biomass per pixel (g/m²) |

---

## 4. WS3 — Inputs

### ForestModel Constructor Parameters

| Parameter | Type | Description |
|---|---|---|
| `model_name` | string | Model identifier |
| `base_year` | integer | Calendar year for period 0 |
| `horizon` | integer | Number of planning periods |
| `period_length` | integer | Years per period (default 10) |
| `max_age` | integer | Maximum stand age tracked |

### Forest Inventory Inputs

| Data | Format | Description |
|---|---|---|
| Development types | Python tuples, Woodstock files, or libCBM data | Forest strata keyed by `('species', 'site_quality', 'zone')` tuples |
| Area by age class | `dt.area(age, period=0, area)` setter | Hectares per age class for period 0 |
| Yield curves | `dt.add_ycomp('vol', curve)` | Age → volume/carbon/biomass mappings via `Curve` objects |
| Silvicultural actions | `fm.add_action(acode, ...)` | Eligibility rules and treatment definitions |
| Transitions | `fm.transitions` | `(development_type, action)` → new development type rules |

### Spatial Inputs (ForestRaster)

| Input | Format | Bands / Content |
|---|---|---|
| Forest inventory raster | 3-band GeoTIFF | Band 1: theme hash (dtype), Band 2: stand age, Band 3: block ID |
| Stand shapefiles | Vector | Source for rasterizing via `ws3.common.rasterize_stands()` |
| Theme hash mapping | `hdt_map` dict + `hdt_func` callable | Links dtype tuples ↔ raster hash values |

### Optimization Inputs (Problem)

| Input | Description |
|---|---|
| `coeff_funcs` | Functions mapping forest paths to objective/constraint values |
| `cflw_e` | Even-flow constraints (integer sense: 1 = upper, -1 = lower) |
| `cgen_data` | General constraints with string operators (`'>='`, `'<='`) |
| Solver choice | HiGHS (default), Gurobi, or PuLP |

---

## 5. WS3 — Outputs

### Aspatial Harvest Schedule

| Output | Access | Description |
|---|---|---|
| Decision variable values | `p.solution()` → `{var_name: float}` | Optimal area harvested per (dtype, age, period, action) |
| Solver status | `p.status()` | Must equal `'optimal'` before reading results |
| Inventory report | `fm.inventory(period, yname)` | Aggregate area or yield across development types |

### Spatial Outputs (ForestRaster)

| Output | Format | Description |
|---|---|---|
| Disturbance maps | GeoTIFF per action per year | Pixels allocated to each disturbance type (e.g., `clearcut_2025.tif`) |
| Filename convention | `acode_map` prefix + year | Configurable via constructor |

### Carbon Accounting Outputs (libCBM via `to_cbm_sit()`)

| DataFrame | Content |
|---|---|
| `classifiers` | Stand classifier definitions |
| `disturbance_types` | CBM disturbance type definitions |
| `age_classes` | Age class breakdowns |
| `inventory` | Initial forest inventory in SIT format |
| `yield` | Yield curves formatted for CBM |
| `disturbance_events` | Disturbance event schedule from solved plan |
| `transition_rules` | Post-disturbance state transitions |

---

## 6. Alignment & Bridging Gaps

### Concepts That Map Across Both Systems

| Concept | LandR | WS3 | Notes |
|---|---|---|---|
| Forest stratum | Pixel group (species × ecoregion) | Development type (tuple key) | Both aggregate similar stands; keys differ |
| Stand age | `age` column in `cohortData` | Age class in `dt.area(age, period)` | LandR is annual; WS3 is period-based |
| Species | `speciesCode` factor | Theme value in dtype tuple | Direct mapping possible |
| Growth | ANPP-based biomass accumulation | Yield curves (age → volume) | Different currencies: g/m² vs m³/ha |
| Disturbance | `sim$rstCurrentBurn` (raster) | `fm.actions` + disturbance GeoTIFFs | WS3 produces rasters LandR can consume |
| Biomass/volume | `B` (g/m²), `biomassMap` | Yield curve component (m³/ha or Mg/ha) | Unit conversion required |

### Key Bridging Requirements

| Direction | Data Needed | Transform Required |
|---|---|---|
| **WS3 → LandR** | Annual harvest disturbance rasters | `ForestRaster.allocate_schedule()` → GeoTIFF → `sim$rstCurrentBurn` equivalent |
| **WS3 → LandR** | Harvest age/area by species | Aggregate from `p.solution()` → `cohortData` cohort removal |
| **LandR → WS3** | Updated biomass/age after succession | `sim$biomassMap` + `sim$cohortData` → reclassify to dtype age classes |
| **LandR → WS3** | Standing volume by stratum | Biomass (g/m²) → volume (m³/ha) via species-specific wood density |
| **Time** | Year ↔ period conversion | `period = (year - base_year) // period_length` |

### Unresolved Mismatches

| Issue | LandR Side | WS3 Side | Resolution Needed |
|---|---|---|---|
| Time granularity | Annual succession | 10-year periods | Decide coupling frequency (annual vs end-of-period) |
| Biomass vs volume | g/m² | m³/ha or Mg/ha | Wood density lookup per species |
| Cohort vs age class | Multiple cohorts per pixel group | Single area per age class | Aggregate multi-cohort pixels or track dominant cohort |
| Spatial unit | Pixel / pixel group | Block / development type | Align CRS and cell size; use block IDs |
| Harvest removal | Kill cohorts in `cohortData` | Area deducted from `dt.area()` | Need bidirectional update protocol |

---

## 7. Integration Data Flow (Target Architecture)

```
WS3 Optimization                     LandR Biomass_core
─────────────────                     ──────────────────
Forest inventory                      sim$cohortData
Yield curves                          sim$species / speciesEcoregion
  │                                         │
  ▼                                         ▼
fm.add_problem() → p.solve()         Annual succession (grow, mortality, ANPP)
  │                                         │
  ▼                                         ▼
ForestRaster.allocate_schedule()     sim$biomassMap (annual raster)
  → clearcut_YYYY.tif ──────────────→ sim$rstCurrentHarvest (new input)
                                      → kill harvested cohorts
                                         │
                                         ▼
                                      Updated sim$cohortData
                                      → reclassify to dtype age classes
                                      → fm.initialize_areas() for next period
```

---

## 8. Reference Links

- [spades.ai repo](https://github.com/AllenLarocque/spades.ai) — AI context for SpaDES/LandR
- [ws3.ai repo](https://github.com/AllenLarocque/ws3.ai) — AI context for WS3
- [WS3 source](https://github.com/UBC-FRESH/ws3) — UBC FRESH WS3 library
- [WS3 documentation](https://ws3.readthedocs.io/en/dev/) — ReadTheDocs reference
- [LandR Biomass_core](https://github.com/PredictiveEcology/Biomass_core) — SpaDES module
