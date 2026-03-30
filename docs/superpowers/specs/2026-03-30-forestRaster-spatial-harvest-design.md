# ForestRaster Spatial Harvest Allocation — Design Spec

**Date:** 2026-03-30
**Branch:** feature/verification-plots
**Status:** Approved for implementation

---

## Problem

`ws3Verify` Plot E (spatial harvest map) requires `rstCurrentHarvest` — a binary raster of pixels cleared each year. `rstCurrentHarvest` is never set because `sim$.ws3fr` is `NULL`: `ForestRaster.allocate_schedule` never runs, so no clearcut GeoTIFFs are written and step 8 of `.ws3Plan` silently skips all years.

---

## Approach

**Option B — Full ForestRaster wiring, per-period inventory rebuild.**

Each `ws3Plan` event: build a fresh 3-band inventory GeoTIFF from the current `cohortData` + `pixelGroupMap`, initialize `ForestRaster(horizon=1)`, call `allocate_schedule`, and let step 8 consume the per-year GeoTIFFs as before. The ForestRaster is not persisted on `sim` — a new instance is created every planning period from the true Biomass_core forest state.

This matches the pattern in the reference implementation (`AllenLarocque/spades_ws3`) and avoids a separate age-tracking copy of the inventory.

---

## Components

### New file: `modules/biomass_ws3Harvest/R/spatialBridge.R`

Contains one function: `buildInventoryRaster()`.

### Modified: `modules/biomass_ws3Harvest/biomass_ws3Harvest.R`

- `init` block: remove `sim$.ws3fr <- NULL` placeholder and its TODO comment; add `"spatialBridge.R"` to the `lapply` that sources helper files.
- `.ws3Plan` step 6: replace the null-guard + warning with `buildInventoryRaster()` call + Python ForestRaster initialization + `allocate_schedule`.

---

## Data Flow (per `ws3Plan`)

```
cohortData (with site_quality) + pixelGroupMap
        |
        v
buildInventoryRaster()
        |
        +-- inventory_{base_year}.tif   (3-band INT4S GeoTIFF, LZW)
        +-- hdt_table                   data.table(hash_val, speciesCode, site_quality, ecoregionGroup)
        |
        v (Python py_run_string)
hdt_map = {int(hash_val): (sp, sq, eco), ...}
ForestRaster(hdt_map, ws3.common.hash_dt, src_path, snk_path,
             acode_map={'clearcut':'clearcut'}, forestmodel=fm,
             base_year=time(sim), period_length, horizon=1)
fr.allocate_schedule(mask=('?','?','?'), sda_mode='randblk', nthresh=1)
        |
        v
clearcut_{year}.tif  (one per year in period, in outDir)
        |
        v
step 8 (unchanged): terra::rast → applyClearcut → rstCurrentHarvest
```

---

## `buildInventoryRaster()` Specification

```r
buildInventoryRaster(cohortData, pixelGroupMap, period_length, base_year, out_dir)
```

**Inputs:**
| Arg | Type | Description |
|-----|------|-------------|
| `cohortData` | data.table | Must have columns: `pixelGroup`, `speciesCode`, `site_quality`, `ecoregionGroup`, `age`, `B`. `site_quality` already binned by caller. |
| `pixelGroupMap` | SpatRaster | Pixel group integer raster from Biomass_core. |
| `period_length` | integer | Years per WS3 period (from `params(sim)$.globals$ws3PeriodLength`). |
| `base_year` | integer | Current calendar year (`time(sim)`). |
| `out_dir` | character | Output directory (same `outDir` used by step 8). |

**Steps:**

1. **Dominant cohort per pixel group** — `cohortData[, .SD[which.max(B)], by=pixelGroup, .SDcols=c("speciesCode","site_quality","ecoregionGroup","age","B")]`. One row per pixel group; groups absent from cohortData are not in the lookup and will be set to NA by `terra::classify` (the default `others=NA` behaviour — do not pass any `others` override).

2. **Hash dev type tuples** — import `ws3.common` once at the top of the function body via `ws3_common <- reticulate::import("ws3.common")` (ws3 is a proper Python package; the dotted submodule path is importable). Then for each unique `(speciesCode, site_quality, ecoregionGroup)` combination call `ws3_common$hash_dt(reticulate::tuple(sp, sq, eco))`. Pass a `reticulate::tuple()` — NOT an R vector — because `hash_dt` joins elements with `.` before MD5-hashing, and an R vector would be passed as a Python list (different byte string → wrong hash). Wrap the return value with `as.integer(reticulate::py_to_r(...))`: `py_to_r` on a numpy int32 returns an R numeric (double) by default; the explicit `as.integer()` is required so the `hash_val` column is R integer for correct INT4S rasterization. Store as R integer column named exactly **`hash_val`** (the Python `iterrows()` step accesses it by this name).

3. **Age in periods** — `as.integer(ceiling(age / period_length))`. Matches band 2 convention used by ForestRaster (reference: `ceil(fp[age_col] / age_divisor)`).

4. **Block ID** — `as.integer(pixelGroup)`. Each pixel group is its own block. Consistent with `applyClearcut` which operates whole-pixel-group.

5. **Rasterize** — three `terra::classify(pixelGroupMap, cbind(from, to))` calls, one per band, in this exact order:
   - **Band 1**: `from = dom$pixelGroup` (integer), `to = dom$hash_val` (integer) → dev type hash
   - **Band 2**: `from = dom$pixelGroup` (integer), `to = dom$age_periods` (integer) → age in periods
   - **Band 3**: `from = dom$pixelGroup` (integer), `to = dom$block_id` (integer) → block ID

   All rely on default `others=NA`. After stacking with `c(band1, band2, band3)`, replace NA cells with 0 before writing: `inv_rast[is.na(inv_rast)] <- 0L`. Then write as `INT4S` + LZW with `NAflag=0` to `{out_dir}/inventory_{base_year}.tif` with `overwrite=TRUE`.

   **Why 0 for nodata:** `ForestRaster.__init__` identifies non-forested pixels as `self._x[0] == 0` (band 1 value equals zero). If non-forest pixels are written with terra's default INT4S nodata sentinel (`-2147483648`), rasterio reads them back as non-zero and `ForestRaster` misidentifies them as forested. Setting them to 0 and using `NAflag=0` in `writeRaster` ensures correct round-trip.

6. **Return** — `list(path = as.character(inv_path), hdt_table = data.table(hash_val, speciesCode, site_quality, ecoregionGroup))`. `path` must be a length-1 character scalar (use `as.character()`) — reticulate passes R character vectors as Python lists, which would break `ForestRaster`'s `src_path` argument.

---

## `.ws3Plan` Step 6 Rewrite

**Preconditions:** Step 6 executes after step 5 (`p$solve()`) completes. `fm.applied_actions[1]` is populated by `p.solve()` and must exist before `allocate_schedule` is called — if step 6 runs before step 5, `allocate_schedule` will find an empty schedule and write zero-area harvests. The R variable `fm` is `sim$.ws3fm`, set at the top of `.ws3Plan` (`fm <- sim$.ws3fm`) and remains in scope through step 8.

```r
# ── 6. Build inventory raster and allocate spatial harvest ───────────────────
outDir <- file.path(outputPath(sim), "harvest")
dir.create(outDir, showWarnings = FALSE, recursive = TRUE)

inv <- buildInventoryRaster(
  cohortData    = cd,
  pixelGroupMap = sim$pixelGroupMap,
  period_length = as.integer(params(sim)$.globals$ws3PeriodLength),
  base_year     = as.integer(time(sim)),
  out_dir       = outDir
)

py_main <- reticulate::import_main()
py_main$`_ws3fm`             <- fm
py_main$`_ws3_hdt_table`     <- inv$hdt_table
py_main$`_ws3_inv_path`      <- as.character(inv$path)   # scalar string, not list
py_main$`_ws3_snk_path`      <- as.character(outDir)     # scalar string, not list
py_main$`_ws3_base_year`     <- as.integer(time(sim))
py_main$`_ws3_period_length` <- as.integer(params(sim)$.globals$ws3PeriodLength)

reticulate::py_run_string("
import ws3.common as _ws3c, ws3.spatial as _ws3s
_hdt_map = {
    int(row['hash_val']): (row['speciesCode'], row['site_quality'], row['ecoregionGroup'])
    for _, row in _ws3_hdt_table.iterrows()
}
_fr = _ws3s.ForestRaster(
    hdt_map          = _hdt_map,
    hdt_func         = _ws3c.hash_dt,
    src_path         = _ws3_inv_path,
    snk_path         = _ws3_snk_path,
    acode_map        = {'clearcut': 'clearcut'},
    forestmodel      = _ws3fm,
    base_year        = _ws3_base_year,
    period_length    = _ws3_period_length,
    horizon          = 1,
    piggyback_acodes = {}
)
_fr.allocate_schedule(mask=('?', '?', '?'), sda_mode='randblk', nthresh=1)
")
```

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Rebuild inventory GeoTIFF every period | Always reflects true Biomass_core forest state; avoids age-sync complexity |
| `horizon=1` | Matches reference; allocates only the current period each solve cycle |
| `nthresh=1` | Safe for any landscape size; `nthresh=10` risks under-allocation on sparse landscapes |
| pixelGroup as block ID | Consistent with `applyClearcut` whole-pixel-group semantics |
| `hdt_func = ws3.common.hash_dt` | Same function ForestRaster uses internally to decode band 1; guarantees round-trip |
| `acode_map = {'clearcut': 'clearcut'}` | ForestRaster filename template (from ws3/spatial.py): `snk_path + '/%s_%i.tif' % (acode_map[acode], base_year + (p-1)*period_length + dy)`. With `acode_map={'clearcut':'clearcut'}`, `base_year=time(sim)`, `p=1`, `dy=0..period_length-1` this produces `clearcut_{time(sim)}.tif` … `clearcut_{time(sim)+period_length-1}.tif` — exactly matching step 8's `sprintf("clearcut_%d.tif", yr)` loop. |
| `base_year = time(sim)` | Period 1, dy=0 → year = `base_year + 0 + 0 = time(sim)`; first file matches step 8 |
| No persistent `sim$.ws3fr` | ForestRaster is a per-period tool; fresh state each period is correct |
| `piggyback_acodes={}` | `ForestRaster.allocate_schedule` line 254 evaluates `acode in self._piggyback_acodes`; with `None` (default) this raises `TypeError: argument of type 'NoneType' is not iterable` |
| Nodata=0 in inventory GeoTIFF | `ForestRaster.__init__` identifies non-forest as `band1 == 0`; terra's INT4S NA sentinel (`-2147483648`) would be misread as a valid hash, treating every non-forest pixel as forested |

---

## Files Changed

| File | Change |
|------|--------|
| `modules/biomass_ws3Harvest/R/spatialBridge.R` | New — `buildInventoryRaster()` |
| `modules/biomass_ws3Harvest/biomass_ws3Harvest.R` | Remove `sim$.ws3fr` placeholder; source `spatialBridge.R`; rewrite step 6 |

No changes to `ws3Verify.R`, `plotSpatialHarvest.R`, step 7, or step 8.
