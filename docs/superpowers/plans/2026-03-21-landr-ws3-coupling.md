# LandR–WS3 Coupling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two new SpaDES modules (`biomass_yieldTablesWS3` and `Biomass_ws3Harvest`) and a `global.R` that couple LandR forest succession with WS3 wood supply optimization over a configurable planning period.

**Architecture:** `biomass_yieldTablesWS3` runs before each WS3 planning cycle, simulating Biomass_core for representative stands to generate and cache m³/ha yield curves per development type via the Boudewyn pipeline. `Biomass_ws3Harvest` translates LandR inventory into WS3 development type areas, triggers a WS3 solve via reticulate, and applies the resulting harvest schedule back to LandR cohorts. Both modules are orchestrated by a single `global.R` using `SpaDES.project::setupProject()` with TSA41 (Dawson Creek, BC) as the default study area.

**Tech Stack:** R, SpaDES.core, SpaDES.project, data.table, terra, reticulate, sf, bcdata, CBMutils (PredictiveEcology), ws3 (Python, UBC-FRESH)

**Spec:** `docs/superpowers/specs/2026-03-21-landr-ws3-coupling-design.md`

---

## File Map

```
WS3_LandR/
├── global.R
├── modules/
│   ├── biomass_yieldTablesWS3/
│   │   ├── biomass_yieldTablesWS3.R      # SpaDES module definition + doEvent dispatcher
│   │   └── R/
│   │       ├── siteQuality.R             # binSiteQuality() — pure function
│   │       ├── curveCache.R              # loadCurveCache(), saveCurveCache(), diffDevTypes()
│   │       ├── boudewynConvert.R         # boudewynBiomassToVol() — Boudewyn pipeline
│   │       └── simStand.R               # simulateStand() — Biomass_core sim per dev type
│   └── Biomass_ws3Harvest/
│       ├── Biomass_ws3Harvest.R          # SpaDES module definition + doEvent dispatcher
│       └── R/
│           ├── inventoryBridge.R         # buildWs3Inventory() — cohortData → WS3 areas
│           ├── actionDispatch.R          # applyHarvestAction() — extensible dispatch table
│           └── harvestBridge.R           # applyHarvestSchedule() — WS3 schedule → LandR
└── tests/
    ├── biomass_yieldTablesWS3/
    │   ├── test-siteQuality.R
    │   ├── test-curveCache.R
    │   ├── test-boudewynConvert.R
    │   └── test-simStand.R
    └── Biomass_ws3Harvest/
        ├── test-inventoryBridge.R
        ├── test-actionDispatch.R
        └── test-harvestBridge.R
```

---

## Task 1: Project Scaffold

**Files:**
- Create: `modules/biomass_yieldTablesWS3/biomass_yieldTablesWS3.R`
- Create: `modules/biomass_yieldTablesWS3/R/siteQuality.R`
- Create: `modules/biomass_yieldTablesWS3/R/curveCache.R`
- Create: `modules/biomass_yieldTablesWS3/R/boudewynConvert.R`
- Create: `modules/biomass_yieldTablesWS3/R/simStand.R`
- Create: `modules/Biomass_ws3Harvest/Biomass_ws3Harvest.R`
- Create: `modules/Biomass_ws3Harvest/R/inventoryBridge.R`
- Create: `modules/Biomass_ws3Harvest/R/actionDispatch.R`
- Create: `modules/Biomass_ws3Harvest/R/harvestBridge.R`
- Create: `tests/biomass_yieldTablesWS3/` (directory)
- Create: `tests/Biomass_ws3Harvest/` (directory)

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p modules/biomass_yieldTablesWS3/R
mkdir -p modules/Biomass_ws3Harvest/R
mkdir -p tests/biomass_yieldTablesWS3
mkdir -p tests/Biomass_ws3Harvest
```

- [ ] **Step 2: Install required R packages**

```r
# Run in R console
if (!require("Require")) install.packages("Require")
Require::Require(c(
  "PredictiveEcology/SpaDES.core@development",
  "PredictiveEcology/SpaDES.project@transition",
  "PredictiveEcology/reproducible@development",
  "PredictiveEcology/CBMutils@main",
  "data.table", "terra", "sf", "reticulate", "testthat", "bcdata"
))
```

- [ ] **Step 3: Install WS3 Python package**

```bash
pip install ws3
# verify
python -c "import ws3; print('ws3 OK')"
```

- [ ] **Step 4: Create stub R files (empty, just the file header comment)**

Each file gets a one-line comment describing its purpose. No code yet — TDD means tests first.

```r
# modules/biomass_yieldTablesWS3/R/siteQuality.R
# binSiteQuality(): bin cohort maxANPP ratio into low/med/high site quality classes
```

```r
# modules/biomass_yieldTablesWS3/R/curveCache.R
# loadCurveCache(), saveCurveCache(), diffDevTypes(): yield curve cache management
```

```r
# modules/biomass_yieldTablesWS3/R/boudewynConvert.R
# boudewynBiomassToVol(): convert biomass (g/m2) trajectory to m3/ha yield curve
```

```r
# modules/biomass_yieldTablesWS3/R/simStand.R
# simulateStand(): run Biomass_core for a single-cohort stand, return age-biomass trajectory
```

```r
# modules/Biomass_ws3Harvest/R/inventoryBridge.R
# buildWs3Inventory(): translate cohortData into WS3 dev type area table
```

```r
# modules/Biomass_ws3Harvest/R/actionDispatch.R
# applyHarvestAction(): dispatch harvest action by action code (clearcut now, extensible)
```

```r
# modules/Biomass_ws3Harvest/R/harvestBridge.R
# applyHarvestSchedule(): apply WS3 harvest schedule to LandR cohortData and pixelGroupMap
```

- [ ] **Step 5: Commit scaffold**

```bash
git add modules/ tests/
git commit -m "chore: scaffold biomass_yieldTablesWS3 and Biomass_ws3Harvest modules"
```

---

## Task 2: `siteQuality.R` — Site Quality Binning

**Files:**
- Implement: `modules/biomass_yieldTablesWS3/R/siteQuality.R`
- Test: `tests/biomass_yieldTablesWS3/test-siteQuality.R`

- [ ] **Step 1: Write the failing tests**

```r
# tests/biomass_yieldTablesWS3/test-siteQuality.R
library(testthat)
library(data.table)
source("modules/biomass_yieldTablesWS3/R/siteQuality.R")

test_that("binSiteQuality assigns low/med/high based on maxANPP ratio", {
  species <- data.table(
    speciesCode = c("Pice_mar", "Pice_mar", "Pinu_ban"),
    ecoregionGroup = c("eco1", "eco2", "eco1"),
    maxANPP = c(300, 600, 400)
  )
  speciesMaxANPP <- data.table(
    speciesCode = c("Pice_mar", "Pinu_ban"),
    globalMaxANPP = c(900, 800)
  )
  cohortData <- data.table(
    pixelGroup = 1:3,
    speciesCode = c("Pice_mar", "Pice_mar", "Pinu_ban"),
    ecoregionGroup = c("eco1", "eco2", "eco1"),
    age = c(50, 50, 50),
    B = c(10000, 10000, 10000)
  )
  result <- binSiteQuality(cohortData, species, speciesMaxANPP, bins = c(0.33, 0.67))
  expect_true("site_quality" %in% names(result))
  # 300/900 = 0.33 → boundary, 600/900 = 0.67 → boundary, 400/800 = 0.50 → med
  expect_true(all(result$site_quality %in% c("low", "med", "high")))
  expect_equal(result[speciesCode == "Pinu_ban"]$site_quality, "med")
})

test_that("binSiteQuality handles missing ecoregion gracefully", {
  species <- data.table(
    speciesCode = "Pice_mar", ecoregionGroup = "eco1", maxANPP = 300
  )
  speciesMaxANPP <- data.table(speciesCode = "Pice_mar", globalMaxANPP = 900)
  cohortData <- data.table(
    pixelGroup = 1, speciesCode = "Pice_mar",
    ecoregionGroup = "eco_MISSING", age = 50, B = 10000
  )
  expect_warning(
    result <- binSiteQuality(cohortData, species, speciesMaxANPP),
    regexp = "ecoregion"
  )
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
Rscript -e "testthat::test_file('tests/biomass_yieldTablesWS3/test-siteQuality.R')"
```

Expected: FAIL — `binSiteQuality` not found.

- [ ] **Step 3: Implement `binSiteQuality()`**

```r
# modules/biomass_yieldTablesWS3/R/siteQuality.R
binSiteQuality <- function(cohortData, speciesEcoregion, speciesMaxANPP,
                           bins = c(0.33, 0.67)) {
  cd <- copy(cohortData)

  # join local maxANPP from speciesEcoregion
  cd <- merge(cd, speciesEcoregion[, .(speciesCode, ecoregionGroup, maxANPP)],
              by = c("speciesCode", "ecoregionGroup"), all.x = TRUE)

  # warn on unmatched rows
  unmatched <- cd[is.na(maxANPP)]
  if (nrow(unmatched) > 0) {
    warning("binSiteQuality: ", nrow(unmatched),
            " cohorts have unrecognised ecoregion — assigned 'med'")
    cd[is.na(maxANPP), maxANPP := 0]
  }

  # join species-level ceiling maxANPP
  cd <- merge(cd, speciesMaxANPP[, .(speciesCode, globalMaxANPP)],
              by = "speciesCode", all.x = TRUE)
  cd[is.na(globalMaxANPP), globalMaxANPP := 1]   # safety: avoid div/0

  cd[, ratio := maxANPP / globalMaxANPP]
  cd[, site_quality := fcase(
    ratio < bins[1], "low",
    ratio < bins[2], "med",
    default        = "high"
  )]
  cd[, c("maxANPP", "globalMaxANPP", "ratio") := NULL]
  cd[]
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
Rscript -e "testthat::test_file('tests/biomass_yieldTablesWS3/test-siteQuality.R')"
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/biomass_yieldTablesWS3/R/siteQuality.R tests/biomass_yieldTablesWS3/test-siteQuality.R
git commit -m "feat: implement binSiteQuality for dev type classification"
```

---

## Task 3: `curveCache.R` — Yield Curve Cache

**Files:**
- Implement: `modules/biomass_yieldTablesWS3/R/curveCache.R`
- Test: `tests/biomass_yieldTablesWS3/test-curveCache.R`

- [ ] **Step 1: Write the failing tests**

```r
# tests/biomass_yieldTablesWS3/test-curveCache.R
library(testthat)
library(data.table)
source("modules/biomass_yieldTablesWS3/R/curveCache.R")

test_that("diffDevTypes returns only new tuples", {
  cached <- c("Pice_mar|low|eco1", "Pinu_ban|med|eco1")
  current <- c("Pice_mar|low|eco1", "Pinu_ban|med|eco1", "Abie_bal|high|eco2")
  result <- diffDevTypes(current, cached)
  expect_equal(result, "Abie_bal|high|eco2")
})

test_that("diffDevTypes returns all tuples when cache is empty", {
  current <- c("Pice_mar|low|eco1", "Pinu_ban|med|eco1")
  result <- diffDevTypes(current, character(0))
  expect_equal(sort(result), sort(current))
})

test_that("saveCurveCache and loadCurveCache roundtrip correctly", {
  tmp <- tempfile(fileext = ".rds")
  curves <- list(
    "Pice_mar|low|eco1" = data.frame(age = 0:5, vol_m3ha = c(0,1,3,6,10,15))
  )
  saveCurveCache(curves, tmp)
  loaded <- loadCurveCache(tmp)
  expect_equal(loaded, curves)
  unlink(tmp)
})

test_that("loadCurveCache returns empty list when file does not exist", {
  result <- loadCurveCache("/nonexistent/path/curves.rds")
  expect_equal(result, list())
})

test_that("devTypeTupleKey produces consistent string key from components", {
  key <- devTypeTupleKey("Pice_mar", "low", "eco1")
  expect_equal(key, "Pice_mar|low|eco1")
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
Rscript -e "testthat::test_file('tests/biomass_yieldTablesWS3/test-curveCache.R')"
```

Expected: FAIL.

- [ ] **Step 3: Implement cache functions**

```r
# modules/biomass_yieldTablesWS3/R/curveCache.R

devTypeTupleKey <- function(speciesCode, site_quality, ecoregion) {
  paste(speciesCode, site_quality, ecoregion, sep = "|")
}

diffDevTypes <- function(currentTuples, cachedKeys) {
  currentTuples[!currentTuples %in% cachedKeys]
}

loadCurveCache <- function(cachePath) {
  if (!file.exists(cachePath)) return(list())
  readRDS(cachePath)
}

saveCurveCache <- function(ws3YieldCurves, cachePath) {
  saveRDS(ws3YieldCurves, cachePath)
  invisible(cachePath)
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
Rscript -e "testthat::test_file('tests/biomass_yieldTablesWS3/test-curveCache.R')"
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/biomass_yieldTablesWS3/R/curveCache.R tests/biomass_yieldTablesWS3/test-curveCache.R
git commit -m "feat: implement yield curve cache (load/save/diff)"
```

---

## Task 4: Species Lookup Table — `speciesCode` → Boudewyn Keys

**Files:**
- Create: `modules/biomass_yieldTablesWS3/data/species_boudewyn_lookup.csv`
- Implement: `modules/biomass_yieldTablesWS3/R/boudewynConvert.R` (lookup load only)
- Test: `tests/biomass_yieldTablesWS3/test-boudewynConvert.R` (lookup test only)

**Context:** The Boudewyn pipeline in CBMutils requires `canfi_species`, `juris_id`, and `ecozone` to look up Table 3 and Table 6_tb parameters. LandR uses `speciesCode` (e.g., `"Pice_mar"`) and `ecoregionGroup`. A lookup table bridges these.

- [ ] **Step 1: Check if CBMutils ships a species mapping**

```r
# Run in R console — check if CBMutils has a species crosswalk
library(CBMutils)
ls("package:CBMutils")         # look for anything like speciesTable, canfiCodes, etc.
data(package = "CBMutils")     # list bundled datasets
```

If a crosswalk exists in CBMutils (e.g., a `sppEquiv`-style table linking speciesCode to canfi_species), use it directly. If not, proceed to Step 2.

- [ ] **Step 2: Create the lookup CSV**

Create `modules/biomass_yieldTablesWS3/data/species_boudewyn_lookup.csv` with at minimum these columns:

```
speciesCode,canfi_species,juris_id,ecozone_default
Pice_mar,101,BC,9
Pice_gla,105,BC,9
Pinu_ban,203,BC,9
Abie_bal,302,BC,9
Popu_tre,1201,BC,9
Betu_pap,1303,BC,9
```

Populate using:
- `canfi_species`: from the CBM_vol2biomass `userGcMeta` test data pattern (see `https://github.com/PredictiveEcology/CBM_vol2biomass`)
- `juris_id`: province abbreviation matching the study area (BC for TSA41)
- `ecozone_default`: default ecozone for the jurisdiction; can be overridden per ecoregion at runtime

Add species for all LandR species used in the boreal test case. The `LandR` package's `sppEquiv` table (column `LandR` → column `CASFRI` or `NFI`) is a useful crosswalk source.

- [ ] **Step 3: Write lookup test**

```r
# tests/biomass_yieldTablesWS3/test-boudewynConvert.R
library(testthat)
source("modules/biomass_yieldTablesWS3/R/boudewynConvert.R")

test_that("loadSpeciesLookup returns a data.frame with required columns", {
  lut <- loadSpeciesLookup()
  expect_true(all(c("speciesCode","canfi_species","juris_id","ecozone_default") %in% names(lut)))
  expect_gt(nrow(lut), 0)
})

test_that("lookupBoudewynKeys returns correct keys for known species", {
  keys <- lookupBoudewynKeys("Pice_mar", "BC", ecozone = 9)
  expect_equal(keys$canfi_species, 101)
  expect_equal(keys$juris_id, "BC")
})
```

- [ ] **Step 4: Run tests — verify they fail**

```bash
Rscript -e "testthat::test_file('tests/biomass_yieldTablesWS3/test-boudewynConvert.R')"
```

- [ ] **Step 5: Implement lookup functions**

```r
# modules/biomass_yieldTablesWS3/R/boudewynConvert.R

.pkgEnv <- new.env(parent = emptyenv())

loadSpeciesLookup <- function(path = system.file(
    "data/species_boudewyn_lookup.csv",
    package = "biomass_yieldTablesWS3",
    mustWork = FALSE
  )) {
  # fallback for non-installed module
  if (!nzchar(path)) {
    path <- file.path(
      dirname(dirname(sys.frame(1)$ofile)),
      "data", "species_boudewyn_lookup.csv"
    )
  }
  data.table::fread(path)
}

lookupBoudewynKeys <- function(speciesCode, juris_id, ecozone = NULL) {
  lut <- loadSpeciesLookup()
  row <- lut[lut$speciesCode == speciesCode & lut$juris_id == juris_id, ]
  if (nrow(row) == 0) stop("No Boudewyn lookup entry for species '", speciesCode,
                           "' in jurisdiction '", juris_id, "'")
  if (is.null(ecozone)) ecozone <- row$ecozone_default[1]
  list(canfi_species = row$canfi_species[1], juris_id = juris_id, ecozone = ecozone)
}
```

- [ ] **Step 6: Run tests — verify they pass**

```bash
Rscript -e "testthat::test_file('tests/biomass_yieldTablesWS3/test-boudewynConvert.R')"
```

- [ ] **Step 7: Commit**

```bash
git add modules/biomass_yieldTablesWS3/data/species_boudewyn_lookup.csv \
        modules/biomass_yieldTablesWS3/R/boudewynConvert.R \
        tests/biomass_yieldTablesWS3/test-boudewynConvert.R
git commit -m "feat: add species→Boudewyn lookup table and lookup functions"
```

---

## Task 5: `boudewynConvert.R` — Biomass to Volume

**Files:**
- Implement: `modules/biomass_yieldTablesWS3/R/boudewynConvert.R` (add conversion function)
- Test: `tests/biomass_yieldTablesWS3/test-boudewynConvert.R` (add conversion tests)

**Context:** `CBMutils::convertM3biom()` converts volume → biomass. We need the inverse. The pipeline: B (g/m²) ÷ 100 → tonnes/ha → Table 6_tb multinomial logistic (get merchantable stemwood fraction) → inverse Table 3 (`vol = (b_m / a)^(1/b)`).

- [ ] **Step 1: Explore CBMutils for available functions**

```r
library(CBMutils)
# key functions to find:
# - cumPoolsCreateAGB() or similar for Table 6_tb pool splitting
# - convertM3biom() for Table 3 — we need its inverse
?CBMutils::convertM3biom
getAnywhere("convertM3biom")   # read source to understand Table 3 param access
```

Note the parameter tables used and how to access them. The Boudewyn tables are downloaded from NFIS URLs inside CBMutils — find where they're cached and how to access `table3` and `table6_tb` data.frames directly.

- [ ] **Step 2: Add conversion tests**

```r
# Append to tests/biomass_yieldTablesWS3/test-boudewynConvert.R

test_that("boudewynBiomassToVol returns non-decreasing volume curve", {
  # synthetic age-biomass trajectory: monotone increasing
  ageB <- data.frame(
    age    = seq(0, 100, by = 10),
    B_gm2  = c(0, 500, 1200, 2500, 4000, 5500, 7000, 8000, 8500, 8700, 8800)
  )
  result <- boudewynBiomassToVol(ageB,
    canfi_species = 101, juris_id = "BC", ecozone = 9)
  expect_true(is.data.frame(result))
  expect_true(all(c("age", "vol_m3ha") %in% names(result)))
  expect_true(all(result$vol_m3ha >= 0))
  # volume should generally increase with age (allow small fluctuations at tail)
  diffs <- diff(result$vol_m3ha)
  expect_gt(sum(diffs >= 0), sum(diffs < 0))
})

test_that("boudewynBiomassToVol returns zero volume at age 0", {
  ageB <- data.frame(age = 0, B_gm2 = 0)
  result <- boudewynBiomassToVol(ageB, canfi_species = 101, juris_id = "BC", ecozone = 9)
  expect_equal(result$vol_m3ha, 0)
})
```

- [ ] **Step 3: Run tests — verify they fail**

```bash
Rscript -e "testthat::test_file('tests/biomass_yieldTablesWS3/test-boudewynConvert.R')"
```

- [ ] **Step 4: Implement `boudewynBiomassToVol()`**

```r
# Append to modules/biomass_yieldTablesWS3/R/boudewynConvert.R

boudewynBiomassToVol <- function(ageB, canfi_species, juris_id, ecozone) {
  # Step 1: g/m2 → tonnes/ha
  B_tha <- ageB$B_gm2 / 100

  # Step 2: Table 6_tb — get merchantable stemwood fraction (pstem)
  # CBMutils stores these parameters internally; access via the package's
  # internal table loading mechanism (adjust if CBMutils API differs)
  table6 <- CBMutils:::.getTable6tb()   # internal helper — verify name in CBMutils source
  t6 <- table6[table6$canfi_species == canfi_species &
               table6$juris_id == juris_id &
               table6$ecozone == ecozone, ]
  if (nrow(t6) == 0) stop("No Table 6_tb params for canfi_species=", canfi_species)

  pstem <- 1 / (1 +
    exp(t6$a1 + t6$a2 * B_tha + t6$a3 * log(B_tha + 5)) +
    exp(t6$b1 + t6$b2 * B_tha + t6$b3 * log(B_tha + 5)) +
    exp(t6$c1 + t6$c2 * B_tha + t6$c3 * log(B_tha + 5))
  )
  b_m <- B_tha * pstem   # merchantable stemwood biomass (tonnes/ha)

  # Step 3: Inverse Table 3 — vol = (b_m / a)^(1/b)
  table3 <- CBMutils:::.getTable3()    # internal helper — verify name in CBMutils source
  t3 <- table3[table3$canfi_species == canfi_species &
               table3$juris_id == juris_id &
               table3$ecozone == ecozone, ]
  if (nrow(t3) == 0) stop("No Table 3 params for canfi_species=", canfi_species)

  vol <- ifelse(b_m <= 0, 0, (b_m / t3$a) ^ (1 / t3$b))

  data.frame(age = ageB$age, vol_m3ha = pmax(0, vol))
}
```

**Note:** The exact names of CBMutils internal table-loading helpers (e.g., `.getTable6tb()`, `.getTable3()`) must be confirmed by reading the CBMutils source in Step 1. Adjust accordingly. If CBMutils does not expose these as accessible functions, download the NFIS CSVs directly:

```r
# Alternative: download tables directly
table3_url <- "https://nfi.nfis.org/resources/biomass_models/appendix2_table3.csv"
table6_url <- "https://nfi.nfis.org/resources/biomass_models/appendix2_table6_tb.csv"
table3 <- data.table::fread(table3_url)
table6 <- data.table::fread(table6_url)
```

Cache these in `inputs/` via `reproducible::prepInputs()`.

- [ ] **Step 5: Run tests — verify they pass**

```bash
Rscript -e "testthat::test_file('tests/biomass_yieldTablesWS3/test-boudewynConvert.R')"
```

- [ ] **Step 6: Commit**

```bash
git add modules/biomass_yieldTablesWS3/R/boudewynConvert.R \
        tests/biomass_yieldTablesWS3/test-boudewynConvert.R
git commit -m "feat: implement Boudewyn biomass→volume pipeline"
```

---

## Task 6: `simStand.R` — Stand Simulation

**Files:**
- Implement: `modules/biomass_yieldTablesWS3/R/simStand.R`
- Test: `tests/biomass_yieldTablesWS3/test-simStand.R`

**Context:** For each new development type, `simulateStand()` runs a minimal SpaDES sim using only `Biomass_core` (no dispersal, no fire, no seed rain) from age 0 to `maxAge`. Returns a `data.frame(age, B_gm2)`.

- [ ] **Step 1: Read how Biomass_yieldTables does this**

Fetch and read `https://github.com/DominiqueCaron/Biomass_yieldTables` — specifically how it constructs a minimal `simInit` call with only `Biomass_core`, how it seeds the initial `cohortData` for a representative stand, and how it extracts the biomass-by-age output. Mirror that approach exactly.

```bash
# clone to a tmp location to read
git clone https://github.com/DominiqueCaron/Biomass_yieldTables /tmp/Biomass_yieldTables
```

- [ ] **Step 2: Write the failing test**

```r
# tests/biomass_yieldTablesWS3/test-simStand.R
library(testthat)
library(data.table)
source("modules/biomass_yieldTablesWS3/R/simStand.R")

test_that("simulateStand returns data.frame with age and B_gm2 columns", {
  # minimal species and speciesEcoregion tables matching Biomass_core expectations
  species <- data.table(
    speciesCode   = "Pice_mar",
    maxB          = 35000L,
    maxANPP       = 700L,
    longevity     = 250L,
    mortalityshape = 10,
    growthcurve   = 0.25,
    seeddispDist  = 100,
    postfireregen = "serotiny"
  )
  speciesEcoregion <- data.table(
    speciesCode    = "Pice_mar",
    ecoregionGroup = "eco1",
    maxANPP        = 500L,
    maxB           = 28000L,
    establishprob  = 0.5
  )
  result <- simulateStand(
    speciesCode    = "Pice_mar",
    site_quality   = "med",
    ecoregion      = "eco1",
    species        = species,
    speciesEcoregion = speciesEcoregion,
    maxAge         = 50
  )
  expect_true(is.data.frame(result))
  expect_true(all(c("age", "B_gm2") %in% names(result)))
  expect_equal(nrow(result), 51)   # ages 0:50
  expect_equal(result$B_gm2[1], 0) # age 0 = no biomass
  expect_gt(max(result$B_gm2), 0)  # should grow
})
```

- [ ] **Step 3: Run test — verify it fails**

```bash
Rscript -e "testthat::test_file('tests/biomass_yieldTablesWS3/test-simStand.R')"
```

- [ ] **Step 4: Implement `simulateStand()`**

Model the implementation on `Biomass_yieldTables`. The key elements:
- Use `SpaDES.core::simInitAndSpades()` with `modules = list("Biomass_core")`
- Provide minimal `objects`: `cohortData`, `species`, `speciesEcoregion`, `ecoregionMap`, `pixelGroupMap`
- Set `times = list(start = 0, end = maxAge)`
- Suppress plots: `params = list(Biomass_core = list(.plotInitialTime = NA, .saveInitialTime = NA))`
- Extract `cohortData` from result and pivot to `(age, B_gm2)`

```r
# modules/biomass_yieldTablesWS3/R/simStand.R
simulateStand <- function(speciesCode, site_quality, ecoregion,
                          species, speciesEcoregion, maxAge = 300,
                          modulePath = file.path(.moduleDir(), "..")) {
  # Build minimal single-pixel cohortData
  initCohort <- data.table::data.table(
    pixelGroup   = 1L,
    speciesCode  = speciesCode,
    age          = 0L,
    B            = 0L,
    mortality    = 0L,
    aNPPAct      = 0L
  )
  pixelGroupMap <- terra::rast(nrows = 1, ncols = 1, vals = 1L)

  mySim <- SpaDES.core::simInitAndSpades(
    times   = list(start = 0, end = maxAge),
    modules = list("Biomass_core"),
    paths   = list(modulePath = modulePath),
    params  = list(Biomass_core = list(
      .plotInitialTime = NA,
      .saveInitialTime = NA
    )),
    objects = list(
      cohortData       = initCohort,
      pixelGroupMap    = pixelGroupMap,
      species          = species[speciesCode == ..speciesCode],
      speciesEcoregion = speciesEcoregion[speciesCode == ..speciesCode &
                                          ecoregionGroup == ..ecoregion]
    )
  )

  cd <- SpaDES.core::outputs(mySim)  # or sim$cohortData — check Biomass_core output
  # Extract age-B trajectory: cohortData logged each year
  # (Mirror exactly what Biomass_yieldTables does here)
  data.frame(age = 0:maxAge, B_gm2 = cd$B_by_age)
}

.moduleDir <- function() {
  # returns the directory of the calling module
  dirname(dirname(sys.frame(1)$ofile))
}
```

**Important:** The exact mechanism for extracting annual B values from a Biomass_core run must be confirmed from reading Biomass_yieldTables (Step 1). Update the extraction logic to match.

- [ ] **Step 5: Run test — verify it passes**

```bash
Rscript -e "testthat::test_file('tests/biomass_yieldTablesWS3/test-simStand.R')"
```

- [ ] **Step 6: Commit**

```bash
git add modules/biomass_yieldTablesWS3/R/simStand.R \
        tests/biomass_yieldTablesWS3/test-simStand.R
git commit -m "feat: implement simulateStand via minimal Biomass_core sim"
```

---

## Task 7: `biomass_yieldTablesWS3` SpaDES Module

**Files:**
- Implement: `modules/biomass_yieldTablesWS3/biomass_yieldTablesWS3.R`

- [ ] **Step 1: Write the module**

```r
# modules/biomass_yieldTablesWS3/biomass_yieldTablesWS3.R
defineModule(sim, list(
  name        = "biomass_yieldTablesWS3",
  description = "Generate and cache WS3-compatible m3/ha yield curves per LandR development type",
  keywords    = c("LandR", "WS3", "yield curves", "Boudewyn"),
  authors     = person("Allen", "Larocque"),
  childModules = character(0),
  version     = list(biomass_yieldTablesWS3 = "0.1.0"),
  timeframe   = as.POSIXlt(c(NA, NA)),
  timeunit    = "year",
  citation    = list(),
  documentation = list(),
  reqdPkgs    = list("data.table", "terra", "PredictiveEcology/CBMutils@main"),
  parameters  = bindrows(
    defineParameter("ws3PeriodLength", "integer", 10L, 1L, 100L,
                    "Years between WS3 planning solves"),
    defineParameter("maxSimAge", "integer", 300L, 50L, 500L,
                    "Maximum stand age for yield curve simulation"),
    defineParameter("siteQualityBins", "numeric", c(0.33, 0.67), 0, 1,
                    "Thresholds for low/med/high site quality bins")
  ),
  inputObjects = bindrows(
    expectsInput("cohortData",       "data.table", "LandR cohort data",         "Biomass_core"),
    expectsInput("species",          "data.table", "LandR species parameters",  "Biomass_borealDataPrep"),
    expectsInput("speciesEcoregion", "data.table", "Species x ecoregion params","Biomass_borealDataPrep"),
    expectsInput("pixelGroupMap",    "SpatRaster", "Pixel group raster",        "Biomass_core")
  ),
  outputObjects = bindrows(
    createsOutput("ws3YieldCurves", "list",
                  "Named list of yield curves keyed by dev type tuple string")
  )
))

doEvent.biomass_yieldTablesWS3 <- function(sim, eventTime, eventType) {
  switch(eventType,
    init = {
      # source helper files
      sourceHelper <- function(f) source(file.path(dirname(currentModule(sim)), "R", f))
      sourceHelper("siteQuality.R")
      sourceHelper("curveCache.R")
      sourceHelper("boudewynConvert.R")
      sourceHelper("simStand.R")

      cachePath <- file.path(outputPath(sim), "ws3YieldCurves.rds")
      sim$ws3YieldCurves <- loadCurveCache(cachePath)

      sim <- scheduleEvent(sim, start(sim), "biomass_yieldTablesWS3", "updateCurves",
                           eventPriority = 1)   # priority 1 = runs before ws3Plan (priority 2)
    },
    updateCurves = {
      sim <- .updateCurves(sim)
      sim <- scheduleEvent(sim, time(sim) + P(sim)$ws3PeriodLength,
                           "biomass_yieldTablesWS3", "updateCurves", eventPriority = 1)
    }
  )
  invisible(sim)
}

.updateCurves <- function(sim) {
  # 1. Derive species-level max ANPP ceiling
  speciesMaxANPP <- sim$speciesEcoregion[, .(globalMaxANPP = max(maxANPP)),
                                          by = speciesCode]

  # 2. Bin site quality
  cd <- binSiteQuality(sim$cohortData, sim$speciesEcoregion, speciesMaxANPP,
                       bins = P(sim)$siteQualityBins)

  # 3. Extract unique dev type tuples
  devTypes <- unique(cd[, .(speciesCode, site_quality, ecoregionGroup)])
  currentKeys <- devTypes[, devTypeTupleKey(speciesCode, site_quality, ecoregionGroup)]

  # 4. Diff against cache
  newKeys <- diffDevTypes(currentKeys, names(sim$ws3YieldCurves))
  newDevTypes <- devTypes[currentKeys %in% newKeys]

  if (nrow(newDevTypes) > 0) {
    message("biomass_yieldTablesWS3: simulating yield curves for ",
            nrow(newDevTypes), " new development type(s)")

    for (i in seq_len(nrow(newDevTypes))) {
      dt <- newDevTypes[i]
      key <- devTypeTupleKey(dt$speciesCode, dt$site_quality, dt$ecoregionGroup)

      ageB <- simulateStand(
        speciesCode      = dt$speciesCode,
        site_quality     = dt$site_quality,
        ecoregion        = dt$ecoregionGroup,
        species          = sim$species,
        speciesEcoregion = sim$speciesEcoregion,
        maxAge           = P(sim)$maxSimAge,
        modulePath       = modulePath(sim)
      )

      boudKeys <- lookupBoudewynKeys(dt$speciesCode, juris_id = "BC")
      curve <- boudewynBiomassToVol(ageB,
        canfi_species = boudKeys$canfi_species,
        juris_id      = boudKeys$juris_id,
        ecozone       = boudKeys$ecozone
      )
      sim$ws3YieldCurves[[key]] <- curve
    }

    cachePath <- file.path(outputPath(sim), "ws3YieldCurves.rds")
    saveCurveCache(sim$ws3YieldCurves, cachePath)
  } else {
    message("biomass_yieldTablesWS3: all dev type curves already cached")
  }
  sim
}
```

- [ ] **Step 2: Smoke test — verify module loads**

```r
library(SpaDES.core)
parseModule("modules/biomass_yieldTablesWS3")
# should return module metadata without errors
```

- [ ] **Step 3: Commit**

```bash
git add modules/biomass_yieldTablesWS3/biomass_yieldTablesWS3.R
git commit -m "feat: implement biomass_yieldTablesWS3 SpaDES module"
```

---

## Task 8: `inventoryBridge.R` — LandR → WS3 Inventory

**Files:**
- Implement: `modules/Biomass_ws3Harvest/R/inventoryBridge.R`
- Test: `tests/Biomass_ws3Harvest/test-inventoryBridge.R`

- [ ] **Step 1: Write failing tests**

```r
# tests/Biomass_ws3Harvest/test-inventoryBridge.R
library(testthat)
library(data.table)
source("modules/biomass_yieldTablesWS3/R/siteQuality.R")  # shared dependency
source("modules/Biomass_ws3Harvest/R/inventoryBridge.R")

test_that("buildWs3Inventory returns correct area by dev type and age class", {
  cohortData <- data.table(
    pixelGroup    = c(1L, 1L, 2L),
    speciesCode   = c("Pice_mar", "Pinu_ban", "Pice_mar"),
    ecoregionGroup = "eco1",
    age           = c(80L, 80L, 40L),
    B             = c(15000L, 8000L, 5000L),
    site_quality  = c("med", "med", "low")
  )
  # pixel areas: pixelGroup 1 = 2 ha, pixelGroup 2 = 1 ha
  pixelArea <- data.table(pixelGroup = c(1L, 2L), area_ha = c(2.0, 1.0))

  result <- buildWs3Inventory(cohortData, pixelArea, periodLength = 10L)

  expect_true(is.data.table(result))
  expect_true(all(c("devTypeKey", "age_class", "area_ha") %in% names(result)))
  # Pice_mar|med|eco1, age_class 8 (age 80 / 10) should have area 2
  pice_med <- result[devTypeKey == "Pice_mar|med|eco1" & age_class == 8L]
  expect_equal(pice_med$area_ha, 2.0)
})

test_that("buildWs3Inventory filters out cohorts below minHarvestAge", {
  cohortData <- data.table(
    pixelGroup = 1L, speciesCode = "Pice_mar",
    ecoregionGroup = "eco1", age = 20L, B = 2000L, site_quality = "med"
  )
  pixelArea <- data.table(pixelGroup = 1L, area_ha = 5.0)
  result <- buildWs3Inventory(cohortData, pixelArea, periodLength = 10L,
                               minHarvestAge = 40L)
  # age 20 < 40 → still in inventory (WS3 handles eligibility separately)
  # but flag should be set
  expect_true("harvestable" %in% names(result))
  expect_false(result$harvestable[1])
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
Rscript -e "testthat::test_file('tests/Biomass_ws3Harvest/test-inventoryBridge.R')"
```

- [ ] **Step 3: Implement `buildWs3Inventory()`**

```r
# modules/Biomass_ws3Harvest/R/inventoryBridge.R
source(file.path(dirname(dirname(sys.frame(1)$ofile)),
                 "..", "biomass_yieldTablesWS3", "R", "curveCache.R"))

buildWs3Inventory <- function(cohortData, pixelArea, periodLength,
                               minHarvestAge = 40L) {
  cd <- copy(cohortData)
  cd[, devTypeKey := devTypeTupleKey(speciesCode, site_quality, ecoregionGroup)]
  cd[, age_class  := floor(age / periodLength)]
  cd[, harvestable := age >= minHarvestAge]

  # join pixel areas
  cd <- merge(cd, pixelArea, by = "pixelGroup", all.x = TRUE)

  # aggregate area by dev type x age class
  inv <- cd[, .(area_ha = sum(area_ha, na.rm = TRUE),
                harvestable = any(harvestable)),
            by = .(devTypeKey, age_class)]
  inv[]
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
Rscript -e "testthat::test_file('tests/Biomass_ws3Harvest/test-inventoryBridge.R')"
```

- [ ] **Step 5: Commit**

```bash
git add modules/Biomass_ws3Harvest/R/inventoryBridge.R \
        tests/Biomass_ws3Harvest/test-inventoryBridge.R
git commit -m "feat: implement LandR→WS3 inventory bridge"
```

---

## Task 9: `actionDispatch.R` + `harvestBridge.R`

**Files:**
- Implement: `modules/Biomass_ws3Harvest/R/actionDispatch.R`
- Implement: `modules/Biomass_ws3Harvest/R/harvestBridge.R`
- Test: `tests/Biomass_ws3Harvest/test-harvestBridge.R`

- [ ] **Step 1: Write failing tests**

```r
# tests/Biomass_ws3Harvest/test-harvestBridge.R
library(testthat)
library(data.table)
library(terra)
source("modules/Biomass_ws3Harvest/R/actionDispatch.R")
source("modules/Biomass_ws3Harvest/R/harvestBridge.R")

test_that("applyClearcut zeros B for pixels in harvest raster", {
  cohortData <- data.table(
    pixelGroup = c(1L, 2L, 3L),
    speciesCode = "Pice_mar",
    age = c(80L, 60L, 40L),
    B   = c(15000L, 10000L, 5000L),
    mortality = 0L, aNPPAct = 0L
  )
  pixelGroupMap <- terra::rast(nrows = 3, ncols = 1,
                                vals = c(1L, 2L, 3L))

  # harvest raster: pixels 1 and 2 harvested, pixel 3 not
  harvestRast <- terra::rast(nrows = 3, ncols = 1,
                              vals = c(1L, 1L, 0L))

  result <- applyHarvestAction("clearcut", harvestRast, cohortData, pixelGroupMap)
  expect_equal(result[pixelGroup == 1L]$B, 0L)
  expect_equal(result[pixelGroup == 2L]$B, 0L)
  expect_equal(result[pixelGroup == 3L]$B, 5000L)  # unchanged
})

test_that("applyHarvestAction warns on unknown action code", {
  expect_warning(
    applyHarvestAction("selection_cut", terra::rast(), data.table(), terra::rast()),
    regexp = "unknown action"
  )
})
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
Rscript -e "testthat::test_file('tests/Biomass_ws3Harvest/test-harvestBridge.R')"
```

- [ ] **Step 3: Implement action dispatch and harvest bridge**

```r
# modules/Biomass_ws3Harvest/R/actionDispatch.R

# Action dispatch table — add new actions here (e.g., "partial_cut")
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
```

```r
# modules/Biomass_ws3Harvest/R/harvestBridge.R
source(file.path(dirname(sys.frame(1)$ofile), "actionDispatch.R"))

applyClearcut <- function(harvestRast, cohortData, pixelGroupMap) {
  # find pixel groups where any harvested pixel exists
  harvestVals  <- terra::values(harvestRast, mat = FALSE)
  pgVals       <- terra::values(pixelGroupMap, mat = FALSE)
  harvestedPGs <- unique(pgVals[harvestVals == 1L & !is.na(harvestVals)])

  cd <- copy(cohortData)
  # save original B before zeroing (data.table := evaluates left-to-right)
  cd[pixelGroup %in% harvestedPGs, mortality := B]
  cd[pixelGroup %in% harvestedPGs, `:=`(B = 0L, aNPPAct = 0L)]
  cd[]
}

applyHarvestSchedule <- function(schedule, ws3FR, cohortData, pixelGroupMap,
                                  outputPath, baseYear) {
  # schedule: data.table with columns year, acode, area
  # ws3FR: Python ForestRaster object (reticulate)
  for (yr in unique(schedule$year)) {
    yearSchedule <- schedule[year == yr]
    for (ac in unique(yearSchedule$acode)) {
      # ForestRaster.allocate_schedule() writes GeoTIFF per action per year
      tifPath <- file.path(outputPath, sprintf("%s_%d.tif", ac, yr))
      if (!file.exists(tifPath)) next

      harvestRast <- terra::rast(tifPath)
      cohortData  <- applyHarvestAction(ac, harvestRast, cohortData, pixelGroupMap)
    }
  }
  cohortData
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
Rscript -e "testthat::test_file('tests/Biomass_ws3Harvest/test-harvestBridge.R')"
```

- [ ] **Step 5: Commit**

```bash
git add modules/Biomass_ws3Harvest/R/actionDispatch.R \
        modules/Biomass_ws3Harvest/R/harvestBridge.R \
        tests/Biomass_ws3Harvest/test-harvestBridge.R
git commit -m "feat: implement harvest bridge and extensible action dispatch"
```

---

## Task 10: `Biomass_ws3Harvest` SpaDES Module

**Files:**
- Implement: `modules/Biomass_ws3Harvest/Biomass_ws3Harvest.R`

- [ ] **Step 1: Write the module**

```r
# modules/Biomass_ws3Harvest/Biomass_ws3Harvest.R
defineModule(sim, list(
  name        = "Biomass_ws3Harvest",
  description = "Couple LandR with WS3: inventory bridge, WS3 solve, harvest application",
  keywords    = c("LandR", "WS3", "harvest", "wood supply"),
  authors     = person("Allen", "Larocque"),
  childModules = character(0),
  version     = list(Biomass_ws3Harvest = "0.1.0"),
  timeframe   = as.POSIXlt(c(NA, NA)),
  timeunit    = "year",
  citation    = list(),
  documentation = list(),
  reqdPkgs    = list("data.table", "terra", "reticulate"),
  parameters  = bindrows(
    defineParameter("ws3PeriodLength",  "integer", 10L,   1L, 100L,
                    "Years between WS3 solves (shared with biomass_yieldTablesWS3)"),
    defineParameter("ws3Horizon",       "integer", 10L,   1L, 50L,
                    "Number of WS3 planning periods"),
    defineParameter("ws3BaseYear",      "integer", 2011L, 1900L, 2100L,
                    "Calendar year for WS3 period 0"),
    defineParameter("ws3MinHarvestAge", "integer", 40L,   0L, 300L,
                    "Minimum stand age eligible for harvest"),
    defineParameter("ws3Solver",        "character", "highs", NA, NA,
                    "WS3 solver backend: highs, gurobi, or pulp")
  ),
  inputObjects = bindrows(
    expectsInput("cohortData",       "data.table", "LandR cohort data",          "Biomass_core"),
    expectsInput("pixelGroupMap",    "SpatRaster", "Pixel group raster",         "Biomass_core"),
    expectsInput("biomassMap",       "SpatRaster", "Total biomass raster",       "Biomass_core"),
    expectsInput("species",          "data.table", "Species parameters",         "Biomass_borealDataPrep"),
    expectsInput("speciesEcoregion", "data.table", "Species x ecoregion params", "Biomass_borealDataPrep"),
    expectsInput("ws3YieldCurves",   "list",       "Yield curves per dev type",  "biomass_yieldTablesWS3")
  ),
  outputObjects = bindrows(
    createsOutput("rstCurrentHarvest",  "SpatRaster", "Harvest disturbance raster"),
    createsOutput("ws3HarvestSchedule", "data.table", "WS3 harvest schedule for reporting")
  )
))

doEvent.Biomass_ws3Harvest <- function(sim, eventTime, eventType) {
  switch(eventType,
    init = {
      # source helper files
      lapply(c("inventoryBridge.R","actionDispatch.R","harvestBridge.R"), function(f)
        source(file.path(dirname(currentModule(sim)), "R", f)))

      # verify Python env
      tryCatch(
        reticulate::import("ws3"),
        error = function(e) stop(
          "Biomass_ws3Harvest: cannot import Python 'ws3'. ",
          "Run: pip install ws3\nOriginal error: ", e$message
        )
      )
      ws3 <- reticulate::import("ws3")

      # initialise ForestModel
      sim$.ws3fm <- ws3$forest$ForestModel(
        model_name    = "LandR_WS3",
        base_year     = as.integer(P(sim)$ws3BaseYear),
        horizon       = as.integer(P(sim)$ws3Horizon),
        period_length = as.integer(P(sim)$ws3PeriodLength)
      )
      sim$.ws3fm$add_action("clearcut", reticulate::py_eval("lambda *a, **kw: None"))

      # initialise ForestRaster for spatial allocation
      # NOTE: confirm ForestRaster constructor API from WS3 docs before implementing
      # https://ws3.readthedocs.io/en/dev/
      # sim$.ws3fr <- ws3$spatial$ForestRaster(sim$.ws3fm, ...)

      sim <- scheduleEvent(sim, start(sim), "Biomass_ws3Harvest", "ws3Plan",
                           eventPriority = 2)   # after updateCurves (priority 1)
    },
    ws3Plan = {
      sim <- .ws3Plan(sim)
      sim <- scheduleEvent(sim, time(sim) + P(sim)$ws3PeriodLength,
                           "Biomass_ws3Harvest", "ws3Plan", eventPriority = 2)
    }
  )
  invisible(sim)
}

.ws3Plan <- function(sim) {
  ws3 <- reticulate::import("ws3")
  fm  <- sim$.ws3fm

  # derive pixel areas from pixelGroupMap
  cellArea_ha <- terra::cellSize(sim$pixelGroupMap, unit = "ha")
  pgVals      <- terra::values(sim$pixelGroupMap, mat = FALSE)
  areaVals    <- terra::values(cellArea_ha, mat = FALSE)
  pixelArea   <- data.table::data.table(pixelGroup = pgVals, area_ha = areaVals)
  pixelArea   <- pixelArea[!is.na(pixelGroup),
                            .(area_ha = sum(area_ha)), by = pixelGroup]

  # site quality bins
  speciesMaxANPP <- sim$speciesEcoregion[, .(globalMaxANPP = max(maxANPP)),
                                          by = speciesCode]
  cd <- binSiteQuality(sim$cohortData, sim$speciesEcoregion, speciesMaxANPP,
                       bins = c(0.33, 0.67))

  # build inventory
  inv <- buildWs3Inventory(cd, pixelArea,
    periodLength  = P(sim)$ws3PeriodLength,
    minHarvestAge = P(sim)$ws3MinHarvestAge
  )

  # load inventory and yield curves into WS3
  for (key in names(sim$ws3YieldCurves)) {
    curve <- sim$ws3YieldCurves[[key]]
    dt    <- fm$dtypes[[key]]
    if (is.null(dt)) fm$create_dtype(key)
    invRows <- inv[devTypeKey == key]
    for (i in seq_len(nrow(invRows))) {
      fm$dtypes[[key]]$area(invRows$age_class[i], 0L, invRows$area_ha[i])
    }
    fm$dtypes[[key]]$add_ycomp("vol",
      reticulate::r_to_py(data.frame(
        x = curve$age, y = curve$vol_m3ha
      ))
    )
  }

  # solve
  p <- fm$add_problem(
    T = as.integer(P(sim)$ws3Horizon),
    coeff_funcs = list(vol = reticulate::py_eval(
      "lambda fm, path: fm.dtypes[path[0]].ycomp('vol')(path[1])"
    ))
  )
  p$solve(P(sim)$ws3Solver)

  if (p$status() != "optimal") {
    warning("Biomass_ws3Harvest: WS3 solve status '", p$status(),
            "' at year ", time(sim), " — skipping harvest this period")
    return(sim)
  }

  # allocate spatial harvest schedule
  outDir <- file.path(outputPath(sim), "harvest")
  dir.create(outDir, showWarnings = FALSE)
  sim$.ws3fr$allocate_schedule(outDir)   # writes clearcut_YYYY.tif per year

  # build schedule table for harvest bridge
  sol     <- p$solution()
  solDT   <- data.table::as.data.table(sol)
  sim$ws3HarvestSchedule <- solDT

  # apply harvest to cohortData year by year
  period  <- seq(time(sim), time(sim) + P(sim)$ws3PeriodLength - 1)
  for (yr in period) {
    tifPath <- file.path(outDir, sprintf("clearcut_%d.tif", yr))
    if (!file.exists(tifPath)) next
    hrast   <- terra::rast(tifPath)
    sim$cohortData <- applyHarvestAction("clearcut", hrast,
                                          sim$cohortData, sim$pixelGroupMap)
    sim$rstCurrentHarvest <- hrast
  }
  sim
}
```

- [ ] **Step 2: Smoke test — verify module loads**

```r
library(SpaDES.core)
parseModule("modules/Biomass_ws3Harvest")
```

- [ ] **Step 3: Commit**

```bash
git add modules/Biomass_ws3Harvest/Biomass_ws3Harvest.R
git commit -m "feat: implement Biomass_ws3Harvest SpaDES module"
```

---

## Task 11: `global.R`

**Files:**
- Create: `global.R`

- [ ] **Step 1: Write `global.R`**

```r
# global.R — LandR × WS3 coupled simulation
# Run with: source("global.R")

if (!require("SpaDES.project")) {
  Require::Install("PredictiveEcology/SpaDES.project@transition")
}

# ── Project-level parameters ────────────────────────────────────────────────
ws3PeriodLength <- 10L   # years between WS3 solves (1 = annual, 10 = default)
ws3Horizon      <- 10L   # number of WS3 planning periods
ws3BaseYear     <- 2011L

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
    # add fire / disturbance modules here as needed, e.g.:
    # "PredictiveEcology/scfm@development"
  ),

  params = list(
    .globals = list(
      ws3PeriodLength = ws3PeriodLength
    ),
    biomass_yieldTablesWS3 = list(
      maxSimAge       = 300L,
      siteQualityBins = c(0.33, 0.67)
    ),
    Biomass_ws3Harvest = list(
      ws3Horizon       = ws3Horizon,
      ws3BaseYear      = ws3BaseYear,
      ws3MinHarvestAge = 40L,
      ws3Solver        = "highs"
    )
  ),

  # Default study area: TSA41 — Dawson Creek TSA, northeastern BC
  # To use a different area, replace this block with your own polygon
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
    sf::st_transform(tsa41,
      crs = "+proj=lcc +lat_1=49 +lat_2=77 +lat_0=0 +lon_0=-95 +datum=NAD83 +units=m")
  },

  studyAreaLarge = {
    sf::st_buffer(studyArea, dist = 20000)
  },

  packages = c("terra", "data.table", "reticulate", "bcdata", "sf", "dplyr"),

  options = list(
    spades.allowInitDuringSimInit = TRUE,
    reproducible.useCache         = TRUE
  )
)

mySim <- do.call(SpaDES.core::simInitAndSpades, out)
```

- [ ] **Step 2: Verify `global.R` parses without error**

```r
# Don't source fully yet — just parse
parse("global.R")
```

Expected: no parse errors.

- [ ] **Step 3: Commit**

```bash
git add global.R
git commit -m "feat: add global.R with setupProject, TSA41 default study area"
```

---

## Task 12: End-to-End Test

**Goal:** Run `global.R` with a short 1-period sim and verify the coupling produces a non-empty harvest raster and updated `cohortData`.

- [ ] **Step 1: Create a short test run script**

```r
# tests/test-endToEnd.R
# Quick smoke test: 1 WS3 period, minimal sim
source("global.R")   # runs the sim

# Assertions
library(testthat)
test_that("end-to-end: harvest raster is non-empty", {
  hrast <- mySim$rstCurrentHarvest
  expect_false(is.null(hrast))
  expect_gt(sum(terra::values(hrast) == 1L, na.rm = TRUE), 0)
})

test_that("end-to-end: cohortData B values changed after harvest", {
  expect_true(any(mySim$cohortData$B == 0L))
})

test_that("end-to-end: ws3YieldCurves produced for at least one dev type", {
  expect_gt(length(mySim$ws3YieldCurves), 0)
})
```

Temporarily set `ws3PeriodLength <- 1L` and `ws3Horizon <- 1L` in `global.R` for this test run.

- [ ] **Step 2: Run the end-to-end test**

```r
source("tests/test-endToEnd.R")
```

Diagnose any failures by checking:
- Python `ws3` import: `reticulate::import("ws3")`
- WS3 solve status: `mySim$.ws3fm$...`
- Yield curve cache: `mySim$ws3YieldCurves`

- [ ] **Step 3: Restore `global.R` to default parameters**

```r
ws3PeriodLength <- 10L
ws3Horizon      <- 10L
```

- [ ] **Step 4: Final commit**

```bash
git add tests/test-endToEnd.R
git commit -m "test: add end-to-end smoke test for LandR-WS3 coupling"
```

---

## Advisory Notes (from spec review)

These are not blocking but should be resolved during implementation:

1. **Harvest timing within a period:** Each year's `rstCurrentHarvest` is applied at the start of the `ws3Plan` event for that year. If Biomass_core needs the raster at a specific sub-annual timing, adjust event priority or scheduling accordingly.

2. **`ForestRaster` vs `ForestModel`:** Task 10 uses `sim$.ws3fr` — this object must be initialised from `ForestModel` during `init`. Confirm the WS3 API for constructing a `ForestRaster` from an existing `ForestModel` by reading [WS3 docs](https://ws3.readthedocs.io/en/dev/).

3. **`rstCurrentHarvest` format:** Confirm the binary mask format (1 = harvested, 0/NA = not) matches what Biomass_core expects for `rstCurrentBurn`-style inputs. Read `Biomass_core` source to verify.

4. **Species lookup table:** If `CBMutils` ships a crosswalk, use it in Task 4 Step 1 rather than the hand-built CSV.
