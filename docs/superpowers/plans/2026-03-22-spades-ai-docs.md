# SpaDES AI Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write four reference documents for the `AllenLarocque/spades.ai` GitHub repo, update the repo's entry-point index, and push all changes via the GitHub API.

**Architecture:** Files are written locally to `.ai_docs/spades-ai-staging/` in the `WS3_LandR` project, then pushed one-by-one to the `AllenLarocque/spades.ai` repo via `gh api PUT`. The existing `spades-ai-setupProject-draft.md` is the source for the finalized `core/setup-project.md`. No git clone of the target repo is needed.

**Tech Stack:** Markdown, `gh` CLI (GitHub API), `base64` encoding for file content upload.

---

## File Map

| Local staging path | Destination in spades.ai repo | Action |
|---|---|---|
| `.ai_docs/spades-ai-staging/setup-project.md` | `core/setup-project.md` | Create (new) |
| `.ai_docs/spades-ai-staging/global-construction.md` | `workflows/global-construction.md` | Create (new) |
| `.ai_docs/spades-ai-staging/development-workflow.md` | `workflows/development-workflow.md` | Create (new) |
| `.ai_docs/spades-ai-staging/iterative-run.md` | `workflows/iterative-run.md` | Create (new) |
| (in-memory patch) | `SPADES-AI.md` | Update file map table |

---

## Pre-flight: Read source material

Before writing anything, read these files to have the content fresh:

- `/home/allarocq/projects/WS3_LandR/.ai_docs/spades-ai-setupProject-draft.md` — source for Task 1
- `/home/allarocq/projects/WS3_LandR/global.R` — real-world example to draw patterns from
- `/home/allarocq/projects/WS3_LandR/docs/superpowers/specs/2026-03-22-spades-ai-docs-design.md` — the approved spec

---

## Task 1: Write `core/setup-project.md`

**Files:**
- Create: `.ai_docs/spades-ai-staging/setup-project.md`
- Source: `.ai_docs/spades-ai-setupProject-draft.md`

This is a finalized and expanded version of the existing draft. Retain all existing content from the draft, then add/change the following:

- [ ] **Step 1: Create staging directory and write the file**

Write `.ai_docs/spades-ai-staging/setup-project.md` with the following structure and content:

```markdown
# global.R and setupProject() — SpaDES Project Entry Point

`global.R` is the single control script for a SpaDES project. It is sourced from the terminal:

```r
source("global.R")
```

All simulation configuration lives here. `SpaDES.project::setupProject()` builds this configuration —
it returns a named list passed directly to `SpaDES.core::simInit2()` and `SpaDES.core::spades()`.

---

## Bootstrap Block

Every `global.R` starts with a bootstrap block that installs core packages before `setupProject()`
runs. The pattern used in production:

```r
Require::setupOff()   # Disable Require's auto-management during the sim run

repos <- c("https://predictiveecology.r-universe.dev", getOption("repos"))
source("https://raw.githubusercontent.com/PredictiveEcology/pemisc/refs/heads/development/R/getOrUpdatePkg.R")
getOrUpdatePkg(
  c("Require", "SpaDES.project", "reticulate"),
  c("1.0.1.9003",  "0.1.1.9037",  "1.43.0")
)

if (!require("SpaDES.project")) {
  Require::Require(c("SpaDES.project", "SpaDES.core", "reproducible"),
                   repos = repos, dependencies = TRUE)
}

Require::setLinuxBinaryRepo()  # Linux only: use pre-compiled binaries
```

**Network failure fallback:** If the raw GitHub `source()` line fails (network unavailable, URL
moved), comment it out and run `install.packages("Require")` manually before continuing.

---

## `require` vs `packages` — Important Distinction

`setupProject()` has two package arguments with different timing:

| Argument | When it runs | Use for |
|---|---|---|
| `require` | Bootstrap phase — before modules download | `Require`, `SpaDES.project`, `reticulate`, other bootstrap deps |
| `packages` | After modules are resolved | Packages modules depend on (including GitHub packages) |

**Do not** put a GitHub package in `require` — it runs before the r-universe repo is configured,
breaking install order.

---

## Minimal Pattern

```r
# ── Top-level variables ────────────────────────────────────────────────────────
startYear  <- 2011
endYear    <- 2111

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
  modules = c(
    "PredictiveEcology/Biomass_borealDataPrep@main",
    "PredictiveEcology/Biomass_core@main"
  ),

  # ── Parameters ─────────────────────────────────────────────────────────────
  params = list(
    .globals = list(sharedParam = 42),
    Biomass_core = list(.plotInitialTime = NA)
  ),

  # ── Shared objects ─────────────────────────────────────────────────────────
  studyArea = {
    terra::vect("inputs/studyArea.shp")
  },

  # ── Packages ───────────────────────────────────────────────────────────────
  packages = c("terra", "data.table"),

  # ── Options ────────────────────────────────────────────────────────────────
  options = list(
    spades.allowInitDuringSimInit = TRUE,
    reproducible.useCache         = TRUE
  )
)

# ── Run (three-step pattern — preferred) ──────────────────────────────────────
sim <- SpaDES.core::simInit2(out)
sim <- SpaDES.core::spades(sim)
```

---

## Key Concepts

### Top-level variables as arguments
Scalars defined before `setupProject()` can be referenced inside its arguments, including in `{}`
expressions:

```r
periodLength <- 10
horizon      <- 10

out <- SpaDES.project::setupProject(
  times = list(start = 2011, end = 2011 + periodLength * horizon),
  params = list(.globals = list(periodLength = periodLength))
)
```

### Curly-brace expressions
Named arguments whose value is a `{}` block are evaluated in order. Later blocks can reference
earlier ones:

```r
out <- SpaDES.project::setupProject(
  studyArea = {
    terra::vect("inputs/studyArea.shp")
  },
  rasterToMatch = {
    terra::project(terra::rast(nrows = 100, ncols = 100), studyArea)
  }
)
```

Objects created here are injected into `sim$` at init.

### Module references
Modules are referenced as `"org/repo@branch"` strings. `setupProject()` handles downloading and
installation automatically.

For repos with multiple sub-modules in a `modules/` subdirectory:
```r
modules = c(
  "PredictiveEcology/Biomass_core@main",
  file.path("PredictiveEcology/scfm@development/modules",
            c("scfmDataPrep", "scfmLandcoverInit", "scfmDriver"))
)
```

Local modules (not on GitHub): add their parent directory to `modulePath` as a vector:
```r
paths = list(
  modulePath = c("modules", "local_modules")
)
```

### `.globals` parameters
Parameters in `.globals` are accessible to all modules:

```r
params = list(
  .globals = list(ws3PeriodLength = 10),
  MyModule  = list(localParam = 5)
)
```

Inside a module, access via `P(sim)$.globals$ws3PeriodLength`.

### Post-processing `out`
After `setupProject()` returns, you can modify `out` before running:

```r
# Enforce explicit module load order (fixes dependency errors)
out$loadOrder <- unlist(out$modules)

# Add a local module path
out$paths$modulePath <- c(out$paths$modulePath, "local_modules")
```

### Three-step execution (preferred)
```r
sim <- SpaDES.core::simInit2(out)   # download, init, validate
sim <- SpaDES.core::spades(sim)      # run event queue
```

Use this during development — the intermediate `sim` object allows inspection with
`inputs(sim)`, `outputs(sim)`, `events(sim)`.

`simInitAndSpades(out)` is a one-liner shortcut acceptable only in finalized production scripts
where the run is known to succeed.

### `Require::setupOff()`
Calling this at the top of `global.R` disables Require's automatic package-management sweep
during the simulation run. Omitting it can cause unexpected package installs mid-sim.

---

## What NOT to do in global.R

- **No `library()` calls** — use `packages` argument instead
- **No hardcoded absolute paths** — use `paths$projectPath` + relative refs
- **No module logic** — `global.R` sets up the sim; modules do the work
- **No `setwd()`** — breaks reproducibility

---

## Reference Examples

- WS3 × LandR coupling: `WS3_LandR/global.R`
- LandR + SCFM fire: [DominiqueCaron/LandRCBM — global_scfm.R](https://github.com/DominiqueCaron/LandRCBM/blob/main/global_scfm.R)
```

- [ ] **Step 2: Verify the file covers every bullet from the spec**

Check against `docs/superpowers/specs/2026-03-22-spades-ai-docs-design.md` → "Document: `spades-ai-setupProject.md`" section. Confirm all 6 improvement bullets are addressed.

- [ ] **Step 3: Commit staging file**

```bash
git add .ai_docs/spades-ai-staging/setup-project.md
git commit -m "docs(staging): add finalized setup-project.md for spades.ai"
```

---

## Task 2: Write `workflows/global-construction.md`

**Files:**
- Create: `.ai_docs/spades-ai-staging/global-construction.md`

- [ ] **Step 1: Write the file**

Write `.ai_docs/spades-ai-staging/global-construction.md`:

```markdown
# Writing a global.R From Scratch

This document covers how to write a `global.R` for a SpaDES project before the first run.
At this stage, modules are not yet downloaded — write defensively and annotate unknowns with
`# TODO:` comments. The first `source("global.R")` will download modules and reveal correct
parameter names and input/output contracts.

See `core/setup-project.md` for the full `setupProject()` syntax reference.

---

## Which path applies?

| Scenario | Path |
|---|---|
| User provides the module list | **Path A — Application** |
| User describes a goal; you must choose modules | **Path B — Development** |

---

## Path A: Application (modules known)

The user provides a list of SpaDES module GitHub references. Your job is to wire them correctly.

### Step-by-step

**1. Write the bootstrap block**

```r
Require::setupOff()

repos <- c("https://predictiveecology.r-universe.dev", getOption("repos"))
source("https://raw.githubusercontent.com/PredictiveEcology/pemisc/refs/heads/development/R/getOrUpdatePkg.R")
getOrUpdatePkg(c("Require", "SpaDES.project"), c("1.0.1.9003", "0.1.1.9037"))

if (!require("SpaDES.project")) {
  Require::Require(c("SpaDES.project", "SpaDES.core", "reproducible"),
                   repos = repos, dependencies = TRUE)
}
Require::setLinuxBinaryRepo()
```

**2. Define project-level scalars** — anything used in more than one place:

```r
startYear       <- 2011
periodLength    <- 10L
horizon         <- 10L
```

**3. Call `setupProject()`** — fill in `paths`, `times`, `modules`, `params`, and shared objects:

```r
out <- SpaDES.project::setupProject(
  paths = list(
    projectPath = getwd(),
    modulePath  = "modules",
    inputPath   = "inputs",
    outputPath  = "outputs",
    cachePath   = "cache"
  ),
  times = list(
    start = startYear,
    end   = startYear + periodLength * horizon
  ),
  modules = c(
    "PredictiveEcology/Biomass_borealDataPrep@main",
    "PredictiveEcology/Biomass_core@main"
    # add other modules here
  ),
  params = list(
    .globals = list(
      periodLength = periodLength   # shared across modules
    ),
    Biomass_core = list(
      .plotInitialTime = NA         # TODO: verify param names after first run
    )
  ),
  studyArea = {
    # TODO: replace with actual study area
    terra::vect("inputs/studyArea.shp")
  },
  studyAreaLarge = {
    sf::st_buffer(studyArea, dist = 20000)  # 20 km buffer — required by Biomass_borealDataPrep
  },
  packages = c("terra", "data.table", "sf"),
  options = list(
    spades.allowInitDuringSimInit = TRUE,
    reproducible.useCache         = TRUE
  )
)
```

**4. Ensure `.globals` carries shared parameters** — any scalar that two or more modules read
should live in `params$.globals`, not in a module-specific params block.

**5. Use curly-brace expressions for spatial objects** — `studyArea`, `studyAreaLarge`, and any
derived rasters. Objects defined in earlier `{}` blocks are available to later ones.

**6. End with the three-step execution block:**

```r
sim <- SpaDES.core::simInit2(out)
sim <- SpaDES.core::spades(sim)
```

---

## Path B: Development (goal known, modules unknown)

The user describes a modelling goal. You must select the right modules from the LandR stack.

### Module selection guide

| Domain | Module(s) | GitHub reference |
|---|---|---|
| Forest inventory / data prep | `Biomass_borealDataPrep` | `PredictiveEcology/Biomass_borealDataPrep@main` |
| Annual succession (growth, mortality) | `Biomass_core` | `PredictiveEcology/Biomass_core@main` |
| Fire disturbance | `scfm` suite | `PredictiveEcology/scfm@development/modules/{scfmDataPrep,scfmLandcoverInit,scfmDriver,scfmEscape,scfmSpread,scfmRegime}` |
| Harvest (WS3) | `biomass_ws3Harvest` | local / project-specific |
| Carbon accounting | `LandRCBM` suite | `PredictiveEcology/LandRCBM@main` |
| Yield tables for WS3 | `biomass_yieldTablesWS3` | local / project-specific |

### Step-by-step

1. Identify the domain(s) from the user's goal
2. Select the appropriate module(s) from the table above
3. For new/custom modules being developed locally: add their parent directory to `modulePath` as a vector rather than a GitHub reference
4. Write `global.R` following Path A steps, annotating uncertain parameter names with `# TODO:`
5. The first run will reveal correct parameter names from each module's `defineModule()` metadata

### Example — local + GitHub modules together

```r
out <- SpaDES.project::setupProject(
  paths = list(
    modulePath = c("modules", "local_modules")  # local_modules/ holds in-development modules
  ),
  modules = c(
    "PredictiveEcology/Biomass_borealDataPrep@main",
    "PredictiveEcology/Biomass_core@main",
    "myNewHarvestModule"   # lives in local_modules/myNewHarvestModule/
  ),
  ...
)
```

---

## Common Patterns (both paths)

| Rule | Why |
|---|---|
| Never use `library()` — use `packages` in `setupProject()` | `library()` breaks module isolation |
| Never use `setwd()` | `setupProject()` manages paths; `setwd()` breaks reproducibility |
| Always define `studyAreaLarge` (typically a 20 km buffer) | `Biomass_borealDataPrep` downloads climate/inventory data for the surrounding region; the buffer size is functional |
| Annotate unknowns with `# TODO:` | The first run reveals correct parameter names; leave placeholders rather than guessing |
| Put shared scalars in `.globals` | Any parameter read by two or more modules must be in `params$.globals` |
```

- [ ] **Step 2: Verify coverage against spec**

Check against spec section "Document: `spades-ai-global-construction.md`". Confirm Path A steps, Path B module table, and all common-patterns rows are present.

- [ ] **Step 3: Commit**

```bash
git add .ai_docs/spades-ai-staging/global-construction.md
git commit -m "docs(staging): add global-construction.md for spades.ai"
```

---

## Task 3: Write `workflows/development-workflow.md`

**Files:**
- Create: `.ai_docs/spades-ai-staging/development-workflow.md`

- [ ] **Step 1: Write the file**

Write `.ai_docs/spades-ai-staging/development-workflow.md`:

```markdown
# SpaDES Development Workflow

This document describes the step-by-step workflow for building and running a SpaDES project.
Follow these steps in order. Each step produces something the next step depends on.

The core insight: **before the first `source("global.R")`, modules are not yet downloaded and
the AI has limited context.** The first run is a bootstrapping step — it downloads modules,
installs packages, and creates the project structure. After that, the AI reads the downloaded
module files to build context before initializing the simulation.

---

## Step 1: Write `global.R`

Follow `workflows/global-construction.md`.

At this point:
- Modules are not yet downloaded
- Parameter names are not yet known
- Write defensively; annotate unknowns with `# TODO:`

---

## Step 2: Run `setupProject()`

Run this block alone (not the full `global.R`) or `source("global.R")` up to the `setupProject()` call:

```r
out <- SpaDES.project::setupProject(...)
```

**What happens:** `Require` downloads and installs all referenced modules and their package
dependencies. This may take several minutes on first run. On subsequent runs, cached packages
are reused.

**If it succeeds:** `out` is a named list. Module files are now in `modules/` (or the path
specified in `modulePath`).

**What to anticipate:**
- Package installation errors (version conflicts, missing system libraries)
- GitHub 404 errors (wrong `"org/repo@branch"` string)
- Network errors on the bootstrap `source()` line

**On error:** see `workflows/iterative-run.md` → `setupProject()` errors table.

---

## Step 3: Read Downloaded Modules

**Before** running `simInit2`, read the main `.R` file of each downloaded module.

Location pattern: `modules/<ModuleName>/<ModuleName>.R`

What to look for in `defineModule()`:

### `inputObjects` table
```r
inputObjects = bindrows(
  expectsInput("cohortData", "data.table", "...", sourceModuleSelect = "Biomass_core"),
  expectsInput("studyArea",  "SpatVector", "...", sourceModuleSelect = NA)
)
```

| Field | What it tells you |
|---|---|
| `objectClass` | The R class `sim$X` must be when this module reads it |
| `sourceModuleSelect` | Which module in the stack produces this object. If set, a "missing object" error means that module is absent — not that you need to supply the object manually. If `NA`, you must supply it. |

### `outputObjects` table
```r
outputObjects = bindrows(
  createsOutput("cohortData", "data.table", "Updated cohort table")
)
```
This tells you what the module writes to `sim$` and when. Trace the event schedule
(`doEvent.*` functions) to understand at which time step each output is produced.

### Event schedule
Look at `scheduleEvent()` calls inside `doEvent.*` functions. This tells you:
- Which events fire and when
- Whether an event reschedules itself (recurring) or fires once
- Inter-module timing dependencies

This context is critical for diagnosing errors in Steps 4 and 5.

---

## Step 4: Run `simInit2()`

```r
sim <- SpaDES.core::simInit2(out)
```

**What happens:** Validates module metadata, checks that required `inputObjects` are present
(or will be produced by another module), runs `init` events, and sets up the event queue.

**Important:** When `spades.allowInitDuringSimInit = TRUE` (the default in this project), `init`
events run during `simInit2`. Errors that look like `spades()` errors may surface here — check
the traceback for the event name.

**If it succeeds:** Inspect the sim:
```r
inputs(sim)    # declared inputs and their sources
outputs(sim)   # declared outputs
events(sim)    # scheduled event queue
```

**On error:** Re-read the relevant module's `inputObjects` definition. Error messages usually
name the missing object or mismatched parameter.

**On error:** see `workflows/iterative-run.md` → `simInit2()` errors table.

---

## Step 5: Run `spades()`

```r
sim <- SpaDES.core::spades(sim)
```

**What happens:** Executes the event queue in time order.

**If it succeeds:** Outputs are in `sim$` and in `paths$outputPath`.

**On error:** The traceback names the module and event. Read that event handler function.

**On error:** see `workflows/iterative-run.md` → `spades()` errors table.

---

## General Principles

**Never skip `simInit2`** — use the three-step pattern (`setupProject` → `simInit2` → `spades`)
during all development. `simInitAndSpades()` is a shortcut acceptable only in finalized production
scripts where the run is known to succeed.

**Restart from the failing step** — after a fix, do not re-run from `setupProject()` unless `out`
itself changed:
- Fix is in `global.R` params or modules list → re-run `setupProject()` then continue
- Fix is in a module file only → re-run from `simInit2(out)` directly

**Cache is your friend** — `reproducible.useCache = TRUE` skips expensive data downloads on
re-runs. Do not clear cache unless a data input genuinely changed.

**`loadOrder` matters** — if `simInit2` throws a dependency error naming two modules, add this
post-processing step before retrying:
```r
out$loadOrder <- unlist(out$modules)
```

---

## Quick Reference

```
source("global.R")  →  setupProject()  →  Read modules/  →  simInit2()  →  spades()
                              ↓                                    ↓               ↓
                        modules/ created               inspect sim$        outputs written
                        packages installed             events(sim)         to outputPath
```
```

- [ ] **Step 2: Verify coverage against spec**

Check against spec section "Document: `spades-ai-workflow.md`". Confirm all 5 steps are present, the module-reading guidance covers `inputObjects`/`outputObjects`/event schedule, and all general principles are included.

- [ ] **Step 3: Commit**

```bash
git add .ai_docs/spades-ai-staging/development-workflow.md
git commit -m "docs(staging): add development-workflow.md for spades.ai"
```

---

## Task 4: Write `workflows/iterative-run.md`

**Files:**
- Create: `.ai_docs/spades-ai-staging/iterative-run.md`

- [ ] **Step 1: Write the file**

Write `.ai_docs/spades-ai-staging/iterative-run.md`:

```markdown
# SpaDES Iterative Development — Error Reference

When `source("global.R")` or a step in the three-step execution pattern fails, use this guide
to diagnose and fix the error. Fix one error at a time; re-run from the failing step.

See `workflows/development-workflow.md` for the full step-by-step workflow.

---

## Iteration Protocol

1. **Fix one error at a time** — resolve the first error before looking at the next
2. **Re-run from the failing step** — do not restart from `setupProject()` unless `out` changed:
   - Fix is in `global.R` (modules list, params, paths) → re-run `setupProject()` and continue
   - Fix is in a module `.R` file only → re-run from `simInit2(out)` directly
3. **Read the module file** before changing anything — error messages name the object or event;
   read the relevant `defineModule()` block or event handler before guessing a fix

---

## `setupProject()` Errors

| Error pattern | Likely cause | Fix |
|---|---|---|
| `curl` error / `cannot open URL` before `setupProject()` runs | Network unavailable, or raw GitHub URL for `getOrUpdatePkg` has moved | Check network; fall back to `install.packages("Require")` and comment out the `source(...)` bootstrap line |
| `Error in Require(...)` / version conflict | Package version mismatch | Check `getOrUpdatePkg()` version pins; update or relax the minimum version |
| GitHub 404 / rate limit | Bad module reference or unauthenticated | Check `"org/repo@branch"` string is correct; set `GITHUB_PAT` env var |
| `Error: path does not exist` | `modulePath` or `inputPath` directory missing | Create the directory: `dir.create("modules", recursive = TRUE)` |

---

## `simInit2()` Errors

Note: when `spades.allowInitDuringSimInit = TRUE`, `init` events run during `simInit2()`. Errors
that look like runtime errors may surface here — check the traceback for the event name.

| Error pattern | Likely cause | Fix |
|---|---|---|
| `object 'X' not found in sim` | Missing `inputObject` | In `defineModule()`, check `sourceModuleSelect` for `X` — if set, that module is missing from `modules` list; if `NA`, supply `X` manually in `global.R` |
| `"unused.*parameter"` / `"not defined in.*module"` | Wrong parameter name in `params` | Read the module's `defineModule()` → `parameters` block for the correct name and spelling |
| `"cannot import Python 'ws3'"` or `reticulate` import error | Python env missing ws3, or wrong Python env | Run `pip install ws3`; check `reticulate::py_config()` points to the correct Python env |
| `studyArea` / `rasterToMatch` CRS error | CRS mismatch between study area and downloaded data | Re-project in the `studyArea = {}` block before passing to `setupProject()` |

---

## `spades()` Errors

| Error pattern | Likely cause | Fix |
|---|---|---|
| Traceback names a specific module + event | Bug in that module's event handler | Read the named event handler function; fix the logic or file an issue upstream |
| `NA` or empty `sim$X` immediately after `simInit2` | The producing module's `init` event returned bad output | Read that module's `init` handler; verify `inputObjects` were valid at init time |
| `NA` or empty `sim$X` mid-run (during `spades()`) | The producing module's periodic/annual event returned bad output | Read the named event handler from the traceback; check upstream `sim$` objects at that timestep |
| Infinite loop / sim never advances | Event scheduling bug | In the affected module, check `scheduleEvent()` calls — the event may be scheduling at the same time as `time(sim)` instead of `time(sim) + interval` |

---

## Post-fix Checklist

Before re-running, confirm:
- [ ] Only one change made
- [ ] The change is in the right file (module `.R` vs `global.R`)
- [ ] Re-running from the correct step (not always from the top)
- [ ] Cache is not stale (clear only if a data input changed)
```

- [ ] **Step 2: Verify coverage against spec**

Check against spec section "Document: `spades-ai-iterative-run.md`". Confirm all three error tables are present, all rows from the spec appear, and the iteration protocol steps match.

- [ ] **Step 3: Commit**

```bash
git add .ai_docs/spades-ai-staging/iterative-run.md
git commit -m "docs(staging): add iterative-run.md for spades.ai"
```

---

## Task 5: Update `SPADES-AI.md` and push all files to GitHub

**Files:**
- Modify: `SPADES-AI.md` in the `AllenLarocque/spades.ai` repo (via GitHub API)
- Push: all four staged files to the repo

The `SPADES-AI.md` file map table currently ends at `templates/module-context-template.md`. Add three new rows.

- [ ] **Step 1: Fetch current `SPADES-AI.md` SHA** (needed for the PUT request)

```bash
gh api repos/AllenLarocque/spades.ai/contents/SPADES-AI.md --jq '.sha'
```

Save the SHA value — it is required for the update API call.

- [ ] **Step 2: Update the file map table in `SPADES-AI.md`**

The existing table ends with:
```
| Creating a module-level CLAUDE.md | `templates/module-context-template.md` |
```

Add after it:
```
| Setting up a new project (`setupProject()` syntax) | `core/setup-project.md` |
| Writing a `global.R` from scratch | `workflows/global-construction.md` |
| Step-by-step development workflow (first run, reading modules, iteration) | `workflows/development-workflow.md` |
| Error reference — diagnosing `setupProject`, `simInit2`, `spades()` failures | `workflows/iterative-run.md` |
```

- [ ] **Step 3: Patch and push the updated `SPADES-AI.md` via GitHub API**

```bash
# 1. Fetch current SHA (required for the PUT request)
SPADES_AI_SHA=$(gh api repos/AllenLarocque/spades.ai/contents/SPADES-AI.md --jq '.sha')

# 2. Decode current content to a temp file
gh api repos/AllenLarocque/spades.ai/contents/SPADES-AI.md --jq '.content' \
  | base64 -d > /tmp/SPADES-AI-current.md
```

Then use the Edit tool to insert the four new rows into `/tmp/SPADES-AI-current.md`.
Find the line:
```
| Creating a module-level CLAUDE.md | `templates/module-context-template.md` |
```
And add after it:
```
| Setting up a new project (`setupProject()` syntax) | `core/setup-project.md` |
| Writing a `global.R` from scratch | `workflows/global-construction.md` |
| Step-by-step development workflow (first run, reading modules, iteration) | `workflows/development-workflow.md` |
| Error reference — diagnosing `setupProject`, `simInit2`, `spades()` failures | `workflows/iterative-run.md` |
```

Save the result as `/tmp/SPADES-AI-updated.md`, then push:

```bash
# 3. Push the patched file
gh api --method PUT repos/AllenLarocque/spades.ai/contents/SPADES-AI.md \
  --field message="feat: add setup-project, global-construction, development-workflow, iterative-run to file map" \
  --field sha="$SPADES_AI_SHA" \
  --field content="$(base64 -w 0 < /tmp/SPADES-AI-updated.md)"
```

**Step 3 must complete successfully before Steps 4–7.** If it fails, do not continue — the index update must land before the content files.

- [ ] **Step 4: Push `core/setup-project.md`**

```bash
gh api --method PUT repos/AllenLarocque/spades.ai/contents/core/setup-project.md \
  --field message="feat: add setup-project.md — finalized setupProject() reference" \
  --field content="$(base64 < .ai_docs/spades-ai-staging/setup-project.md)"
```

- [ ] **Step 5: Push `workflows/global-construction.md`**

```bash
gh api --method PUT repos/AllenLarocque/spades.ai/contents/workflows/global-construction.md \
  --field message="feat: add global-construction.md — how to write a global.R from scratch" \
  --field content="$(base64 < .ai_docs/spades-ai-staging/global-construction.md)"
```

- [ ] **Step 6: Push `workflows/development-workflow.md`**

```bash
gh api --method PUT repos/AllenLarocque/spades.ai/contents/workflows/development-workflow.md \
  --field message="feat: add development-workflow.md — step-by-step SpaDES dev workflow" \
  --field content="$(base64 < .ai_docs/spades-ai-staging/development-workflow.md)"
```

- [ ] **Step 7: Push `workflows/iterative-run.md`**

```bash
gh api --method PUT repos/AllenLarocque/spades.ai/contents/workflows/iterative-run.md \
  --field message="feat: add iterative-run.md — error reference for setupProject/simInit2/spades" \
  --field content="$(base64 < .ai_docs/spades-ai-staging/iterative-run.md)"
```

- [ ] **Step 8: Verify all files appear in the repo**

```bash
gh api repos/AllenLarocque/spades.ai/git/trees/HEAD?recursive=1 \
  --jq '.tree[] | select(.type=="blob") | .path'
```

Expected output includes:
```
core/setup-project.md
workflows/global-construction.md
workflows/development-workflow.md
workflows/iterative-run.md
```

- [ ] **Step 9: Final commit of staging files to WS3_LandR**

```bash
git add .ai_docs/spades-ai-staging/
git commit -m "docs: mark spades.ai staging files as published"
```

---

## Done

All four documents are live in `AllenLarocque/spades.ai`. The `SPADES-AI.md` entry-point index points to them. An AI assistant reading `SPADES-AI.md` will now find the right document for each task in the file map table.
