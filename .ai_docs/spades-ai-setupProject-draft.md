# global.R and setupProject() — SpaDES Project Entry Point

`global.R` is the single control script for a SpaDES project. It is sourced from the terminal:

```r
source("global.R")
```

All simulation configuration lives here: paths, module references, parameters, and shared objects. `SpaDES.project::setupProject()` is the standard way to build this configuration — it returns a named list that is passed directly to `simInitAndSpades()` (or `simInit2()` + `spades()`).

---

## Minimal Pattern

```r
# ── Bootstrap ─────────────────────────────────────────────────────────────────
if (!require("SpaDES.project")) {
  Require::Install("PredictiveEcology/SpaDES.project@transition")
}

# ── Top-level variables ────────────────────────────────────────────────────────
# Define scalars here. They can be referenced inside setupProject() arguments,
# including inside curly-brace expressions (evaluated in order, in scope).
startYear  <- 2011
endYear    <- 2111
myParam    <- 42

out <- SpaDES.project::setupProject(

  # ── Paths ──────────────────────────────────────────────────────────────────
  paths = list(
    projectPath = getwd(),
    modulePath  = "modules",
    inputPath   = "inputs",
    outputPath  = "outputs",
    cachePath   = "cache"
  ),

  # ── Simulation time ────────────────────────────────────────────────────────
  times = list(start = startYear, end = endYear),

  # ── Modules (GitHub references) ────────────────────────────────────────────
  # Format: "org/repo@branch"
  # Sub-modules: file.path("org/repo@branch/modules", c("mod1", "mod2"))
  modules = c(
    "PredictiveEcology/Biomass_borealDataPrep@main",
    "PredictiveEcology/Biomass_core@main"
  ),

  # ── Parameters ─────────────────────────────────────────────────────────────
  # .globals are accessible to all modules via P(sim)$.globals$<name>
  params = list(
    .globals = list(
      sharedParam = myParam
    ),
    Biomass_core = list(
      .plotInitialTime = NA
    )
  ),

  # ── Shared objects (passed into sim$) ─────────────────────────────────────
  # Curly-brace expressions are evaluated in order and in scope —
  # later ones can reference earlier ones.
  studyArea = {
    terra::vect("inputs/studyArea.shp")
  },
  rasterToMatch = {
    terra::rast("inputs/rtm.tif")
  },

  # ── Packages ───────────────────────────────────────────────────────────────
  packages = c("terra", "data.table"),

  # ── Options ────────────────────────────────────────────────────────────────
  options = list(
    spades.allowInitDuringSimInit = TRUE,
    reproducible.useCache         = TRUE
  ),

  # ── Functions ──────────────────────────────────────────────────────────────
  # Sources helper R files before sim runs
  functions = "R/helpers.R"
)

# ── Run ────────────────────────────────────────────────────────────────────────
do.call(SpaDES.core::simInitAndSpades, out)
```

---

## Key Concepts

### Top-level variables as arguments
Any named scalar defined before `setupProject()` can be referenced inside its arguments, including inside `{}` expressions. This is the standard way to define project-level parameters that multiple modules share:

```r
periodLength <- 10
horizon      <- 10

out <- SpaDES.project::setupProject(
  times = list(start = 2011, end = 2011 + periodLength * horizon),
  params = list(
    .globals = list(periodLength = periodLength)
  )
)
```

### Curly-brace expressions (inline code blocks)
Named arguments whose value is a `{}` block are evaluated in order within `setupProject()`. Later blocks can reference objects created in earlier blocks:

```r
out <- SpaDES.project::setupProject(
  studyArea = {
    terra::vect("inputs/studyArea.shp")
  },
  rasterToMatch = {
    # can reference studyArea because it was defined above
    terra::project(terra::rast(nrows=100, ncols=100), studyArea)
  }
)
```

The resulting objects are injected into `sim$` at init.

### Module references
Modules are referenced as `"org/repo@branch"` strings. `setupProject()` handles downloading, installation, and path setup automatically.

For repos containing multiple sub-modules in a `modules/` directory:
```r
modules = c(
  "PredictiveEcology/Biomass_core@main",
  file.path("PredictiveEcology/scfm@development/modules",
            c("scfmDataPrep", "scfmLandcoverInit", "scfmDriver"))
)
```

### `.globals` parameters
Parameters in `.globals` are accessible to all modules. Use for shared scalars that multiple modules need (e.g., a period length that drives both a yield-table module and a harvest module):

```r
params = list(
  .globals = list(ws3PeriodLength = 10),
  MyModule  = list(localParam = 5)
)
```

Inside a module, access globals via `P(sim)$.globals$ws3PeriodLength` (or `params(sim)$.globals$ws3PeriodLength`).

### Post-processing `out`
After `setupProject()` returns, you can modify `out` before running:

```r
out <- SpaDES.project::setupProject(...)

# Override load order
out$loadOrder <- unlist(out$modules)

# Add a locally-cloned module not on GitHub
out$paths$modulePath <- c(out$paths$modulePath, "local_modules")

do.call(SpaDES.core::simInitAndSpades, out)
```

### Two-step execution (alternative to simInitAndSpades)
```r
initOut <- do.call(SpaDES.core::simInit2, out)
sim     <- SpaDES.core::spades(initOut)
```
Use this when you need to inspect or modify the initialized `simList` before running.

---

## What NOT to do in global.R

- **No `library()` calls** — use `packages` argument in `setupProject()` instead
- **No hardcoded absolute paths** — use `paths$projectPath` + relative refs
- **No module logic** — global.R sets up the sim, modules do the work
- **No `setwd()`** — `setupProject()` handles paths; `setwd()` breaks reproducibility

---

## Reference Examples

- Simple LandR + WS3 coupling: `WS3_LandR/global.R` (this project)
- LandR + SCFM fire: [DominiqueCaron/LandRCBM — global_scfm.R](https://github.com/DominiqueCaron/LandRCBM/blob/main/global_scfm.R)
- WS3 harvest demo: [cccandies-demo-202503B — global.R](https://github.com/AllenLarocque/cccandies-demo-202503B/blob/master/global.R)
