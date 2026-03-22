# SpaDES AI Documentation Design Spec

**Date:** 2026-03-22
**Project:** WS3_LandR / spades.ai repo
**Status:** Approved — ready for implementation plan

---

## Overview

Create four reference documents for the `spades.ai` GitHub repo (AllenLarocque/spades.ai) that teach AI assistants to work effectively with SpaDES.project workflows. The documents cover: `setupProject()` syntax, writing a `global.R` from scratch, the step-by-step development workflow, and error-driven iteration.

An existing draft (`spades-ai-setupProject-draft.md`) is finalized and promoted to the canonical reference.

---

## Goals

- Enable an AI to write a well-formed `global.R` before the first run, in both known-modules (application) and goal-driven (module development) scenarios
- Guide the AI through the bootstrap problem: the first `source("global.R")` downloads modules and creates project context that the AI should read before continuing
- Teach the AI to use the three-step execution pattern (`setupProject` → `simInit2` → `spades`) rather than the opaque `simInitAndSpades()`, enabling pause-and-assess at each stage
- Provide actionable error interpretation so the AI can fix problems and re-run without human intervention

---

## Document Set

| File (in spades.ai repo) | Role |
|---|---|
| `spades-ai-setupProject.md` | Finalized `setupProject()` syntax reference (promotes existing draft) |
| `spades-ai-global-construction.md` | How to write a `global.R` from scratch — two paths |
| `spades-ai-workflow.md` | Orchestrating workflow doc — step-by-step with what to anticipate |
| `spades-ai-iterative-run.md` | Error-driven iteration — common error patterns and fixes |

---

## Document: `spades-ai-setupProject.md`

Finalized version of the existing `spades-ai-setupProject-draft.md`. Improvements:

- Remove "draft" framing; promote to canonical reference
- Add `Require::setupOff()` and `getOrUpdatePkg()` bootstrap pattern (as seen in the real `global.R`)
- Add `Require::setLinuxBinaryRepo()` pattern for Linux binary packages
- Clarify the `require` vs `packages` argument distinction: `require` installs packages in the bootstrap phase before modules are downloaded (use for `Require`, `SpaDES.project`, `reticulate`); `packages` installs packages after modules are resolved (use for packages that modules depend on, including GitHub packages). Putting a GitHub package in `require` breaks install order.
- Add the `simInit2` + `spades()` two-step pattern as the preferred alternative to `simInitAndSpades()`
- Add note on `Require::setupOff()` — disables Require's automatic package management during the sim run

---

## Document: `spades-ai-global-construction.md`

How to write a `global.R` from scratch. Two paths:

### Path A: Application (modules known)

User provides the module list. AI's job is to wire them correctly:

1. Write the bootstrap block (`Require::setupOff`, `getOrUpdatePkg`, binary repo)
2. Define project-level scalars (period length, base year, horizon, etc.)
3. Call `setupProject()` with correct `paths`, `times`, `modules`, `params`, shared objects
4. Ensure `.globals` carries any parameters shared across modules
5. Use curly-brace expressions for `studyArea`, `studyAreaLarge`, and any derived spatial objects
6. End with the three-step execution block

### Path B: Development (goal known, modules unknown)

User describes the goal. AI must select modules:

1. Identify the domain (succession, fire, harvest, carbon, data prep)
2. Map to the standard LandR module stack:
   - Data prep: `Biomass_borealDataPrep`
   - Succession: `Biomass_core`
   - Fire: `scfm` suite or `LandMine`
   - Harvest: domain-specific (e.g., `biomass_ws3Harvest` for WS3 coupling)
   - Carbon: `LandRCBM` suite
3. For each new/custom module: use a local path in `modulePath` rather than a GitHub reference
4. Write the `global.R` with placeholder parameters; annotate unknowns with `# TODO:` comments
5. Note that the first run will reveal correct parameter names from downloaded module metadata

### Common patterns for both paths

- Typically define `studyAreaLarge` as a buffer (usually 20,000 m) around `studyArea` — `Biomass_borealDataPrep` uses this to download climate/inventory data for the surrounding region; the buffer size has a functional meaning, not just stylistic
- Never use `library()` — use `require` argument in `setupProject()`
- Never use `setwd()`
- Local modules not on GitHub: add their parent directory to `modulePath` as a vector

---

## Document: `spades-ai-workflow.md`

The orchestrating document — what an AI should do, in order, and what to expect at each step.

### Step 1: Write `global.R`

Follow `spades-ai-global-construction.md`. At this point the AI has limited context — modules are not yet downloaded. Write defensively with `# TODO:` annotations for unknowns.

### Step 2: Run `setupProject()`

```r
out <- SpaDES.project::setupProject(...)
```

- This is where module downloading occurs (via `Require`). It may take several minutes on first run.
- **What to anticipate:** package installation errors, GitHub authentication errors, version conflicts
- **If it succeeds:** `out` is a named list ready to pass to `simInit2`. Modules are now in `modules/`.
- **On error:** see `spades-ai-iterative-run.md`

### Step 3: Read downloaded modules

Before initializing the sim, read the downloaded module `.R` files:

- Each module's main file (e.g., `modules/Biomass_core/Biomass_core.R`) contains `inputObjects`, `outputObjects`, and the event schedule in `defineModule()`
- In `inputObjects`: check `objectClass` (the expected R class) and `sourceModuleSelect` (which module in the stack produces this object — if present, a missing-object error means that module is absent from `modules` list, not that you need to supply it manually)
- In `outputObjects`: check what each module produces and at what event; this tells you which modules must load before others
- In the event schedule (`doEvent.*` functions): check `scheduleEvent()` calls to understand timing and dependencies
- This context is critical for diagnosing both Step 4 and Step 5 errors

### Step 4: Run `simInit2()`

```r
sim <- SpaDES.core::simInit2(out)
```

- Initializes the sim: validates inputs, runs `init` events, sets up the event queue
- **What to anticipate:** missing input objects, type mismatches, parameter name errors
- **If it succeeds:** `sim` is a `simList` object; inspect with `inputs(sim)`, `outputs(sim)`, `events(sim)`
- **On error:** re-read the relevant module's `inputObjects` definition; error messages usually name the missing object

### Step 5: Run `spades()`

```r
sim <- SpaDES.core::spades(sim)
```

- Executes the event queue
- **What to anticipate:** event-level R errors (these surface as tracebacks naming the module and event)
- **If it succeeds:** outputs are in `sim$` and in `paths$outputPath`
- **On error:** the traceback names the module and event; read that module's event handler function

### General principles

- **Never skip `simInit2`** in favor of going straight to `simInitAndSpades` — the intermediate `sim` object allows inspection. `simInitAndSpades` is acceptable only in finalized production scripts where the run is known to succeed.
- **`simInit2` runs `init` events** when `spades.allowInitDuringSimInit = TRUE` (the default in this project). Errors that look like `spades()` errors may actually surface during `simInit2` — check the traceback for the event name.
- **After any fix, restart from the failing step** — do not re-run from `setupProject()` unless `out` itself changed
- **Cache is your friend** — `reproducible.useCache = TRUE` means repeated runs skip expensive data downloads; don't clear cache unless a data input genuinely changed
- **`loadOrder` matters** — if `simInit2` throws a dependency error naming two modules, post-process `out$loadOrder <- unlist(out$modules)` to enforce explicit load order before retrying

---

## Document: `spades-ai-iterative-run.md`

Error-driven iteration guide. Covers the most common failure modes at each stage.

### `setupProject()` errors

| Error pattern | Likely cause | Fix |
|---|---|---|
| `Error in Require(...)` / version conflict | Package version mismatch | Check `getOrUpdatePkg()` version pins; update or relax |
| GitHub 404 / rate limit | Bad module ref or unauthenticated | Check `"org/repo@branch"` string; set `GITHUB_PAT` |
| `Error: path does not exist` | `modulePath` or `inputPath` missing | Create the directory; `dir.create("modules")` etc. |
| `curl` error / `cannot open URL` before `setupProject()` runs | Network unavailable or raw GitHub URL for `getOrUpdatePkg` moved | Check network; fall back to `install.packages("Require")` and comment out the `source(...)` line |

### `simInit2()` errors

| Error pattern | Likely cause | Fix |
|---|---|---|
| `object 'X' not found in sim` | Missing `inputObject` | Check which module produces `X`; ensure it's in `modules` list or supply manually |
| `"unused.*parameter"` / `"not defined in.*module"` warning/error | Wrong parameter name in `params` | Read `defineModule()` in the module file for the correct param names and spelling |
| `"cannot import Python 'ws3'"` or `reticulate` import error | Python env missing ws3 | Run `pip install ws3` in the active Python env; check `reticulate::py_config()` points to the right env |
| `studyArea` / `rasterToMatch` CRS error | CRS mismatch between study area and data | Re-project in the `studyArea = {}` block |

### `spades()` errors

| Error pattern | Likely cause | Fix |
|---|---|---|
| Traceback names a specific module + event | Bug in that module's event handler | Read the handler; fix or file an issue |
| `NA` or empty object immediately after `simInit2` | `init` event of the producing module returned bad output | Read that module's `init` handler; check `inputObjects` were valid at init time |
| `NA` or empty object mid-run (during `spades()`) | Periodic/annual event of producing module returned bad output | Read the named event handler in the traceback; check upstream `sim$` objects at that time step |
| Infinite loop / sim never advances | Event scheduling bug | Check `scheduleEvent()` calls in the affected module |

### Iteration protocol

1. Fix one error at a time
2. Re-run from the failing step (not from the top)
3. If the fix requires changing `out` (e.g., adding a module or changing a parameter), re-run `setupProject()` and continue from Step 2
4. If the fix is in a module file only, re-run from `simInit2(out)` — no need to re-run `setupProject()`

---

## Delivery

Files are written locally in this project, then pushed to the `AllenLarocque/spades.ai` GitHub repo. The existing `spades-ai-setupProject-draft.md` in `.ai_docs/` is the source for the finalized `spades-ai-setupProject.md`.

---

## Key References

- [spades.ai repo](https://github.com/AllenLarocque/spades.ai) — destination for all four files
- `.ai_docs/spades-ai-setupProject-draft.md` — source for the finalized setupProject doc
- `global.R` in this project — canonical real-world example
- [SpaDES.project](https://github.com/PredictiveEcology/SpaDES.project) — upstream source
