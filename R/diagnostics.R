## Run diagnostics for WS3_LandR: verification checks, harvest tracking, and biological summaries.
## Reads the per-decade snapshots written by a run (outputs/<tag>/snapshots/decade_YYYY.rds, plus
## outputs/<tag>/summaries.rds and outputs/<tag>/harvest/clearcut_YYYY.tif) and writes PNGs and
## CSVs. Several runs (tags) are compared side by side.
##
## Usage: source("R/diagnostics.R"); runDiagnostics(c(h10 = "outputs/h10", h25 = "outputs/h25"),
##                                                  outDir = "outputs/diagnostics")

library(data.table)
library(ggplot2)

## ---- reading ------------------------------------------------------------------------------

readRun <- function(runDir) {
  files <- sort(list.files(file.path(runDir, "snapshots"), "^decade_\\d+\\.rds$", full.names = TRUE))
  snaps <- lapply(files, readRDS)
  snaps <- lapply(snaps, function(s) { s$pixelGroupMap <- terra::unwrap(s$pixelGroupMap); s })
  names(snaps) <- vapply(snaps, function(s) as.character(s$year), "")
  sumFile <- file.path(runDir, "summaries.rds")
  list(dir = runDir, snaps = snaps, summaries = if (file.exists(sumFile)) readRDS(sumFile))
}

cellHa <- function(r) prod(terra::res(r)) / 1e4

## clearcut maps for years y; returns a cell-index vector of cut cells per year
cutCells <- function(runDir, years) {
  setNames(lapply(years, function(y) {
    f <- file.path(runDir, "harvest", sprintf("clearcut_%d.tif", y))
    if (!file.exists(f)) return(integer(0))
    v <- terra::values(terra::rast(f), mat = FALSE)
    which(!is.na(v) & v == 1)
  }), years)
}

## dominant (most biomass) cohort per pixel group
leadCohort <- function(cd) cd[cd[, .I[which.max(B)], by = pixelGroup]$V1]

## per-cell table: pixelGroup, dominant species and age (NA cells dropped)
cellTable <- function(snap) {
  pg <- terra::values(snap$pixelGroupMap, mat = FALSE)
  dt <- data.table(cell = seq_along(pg), pixelGroup = pg)[!is.na(pixelGroup)]
  lead <- leadCohort(snap$cohortData)[, .(pixelGroup, species = as.character(speciesCode), age, B)]
  totB <- snap$cohortData[, .(totalB = sum(B)), by = pixelGroup]
  dt <- merge(dt, lead, by = "pixelGroup", all.x = TRUE)
  dt <- merge(dt, totB, by = "pixelGroup", all.x = TRUE)
  dt[pixelGroup == 0 | is.na(species), `:=`(species = "none (cut or empty)", age = 0L, B = 0, totalB = 0)]
  dt[]
}

## ---- tables ---------------------------------------------------------------------------------

decadeTable <- function(run, tag) {
  rbindlist(lapply(run$snaps, function(s) {
    ch <- cellHa(s$pixelGroupMap)
    cuts <- cutCells(run$dir, s$year + 0:9)
    p1 <- s$plan[period == 1]
    data.table(run = tag, horizon = s$horizon, year = s$year,
               plan_cut_ha = p1$cut_ha, plan_cut_m3 = p1$cut_m3,
               plan_m3_per_ha = p1$cut_m3 / p1$cut_ha,
               mean_cut_age = if (nrow(s$cut)) s$cut[, weighted.mean(age, ha)] else NA_real_,
               pct_cut_under_60 = if (nrow(s$cut)) 100 * s$cut[age < 60, sum(ha)] / s$cut[, sum(ha)] else NA_real_,
               mapped_cut_ha = ch * sum(lengths(cuts)),
               inv_ha = p1$inv_ha, inv_ge40_ha = p1$inv_ge40_ha, growing_stock_m3 = p1$inv_m3,
               end_growing_stock_m3 = s$plan[period == max(period), inv_m3],
               solve_secs = s$secs)
  }))[, delivered_pct := 100 * mapped_cut_ha / plan_cut_ha][]
}

planTable <- function(run, tag) {
  rbindlist(lapply(run$snaps, function(s)
    s$plan[, .(run = tag, plan_year = s$year, period, year = s$year + (period - 1) * 10L,
               cut_ha, cut_m3, inv_ha, inv_ge40_ha, inv_m3)]))
}

## pass/fail verification checks per run
verifyTable <- function(run, tag, minAge = 40, flowEps = 0.05) {
  snaps <- run$snaps
  if (!is.null(snaps[[1]]$minAge)) minAge <- snaps[[1]]$minAge  # the run's own minimum harvest age
  yrs <- as.integer(names(snaps))
  ch <- cellHa(snaps[[1]]$pixelGroupMap)
  forestCells <- vapply(snaps, function(s) sum(!is.na(terra::values(s$pixelGroupMap, mat = FALSE))), 0)
  minCut <- min(unlist(lapply(snaps, function(s) s$cut$age)), na.rm = TRUE)
  flowDev <- max(vapply(snaps, function(s) {
    v <- s$plan$cut_m3; max(abs(v / v[1] - 1))
  }, 0))
  dt <- rbindlist(lapply(snaps, function(s) {
    cuts <- cutCells(run$dir, s$year + 0:9)
    pg <- terra::values(s$pixelGroupMap, mat = FALSE)
    ws3_ha <- s$plan[period == 1, inv_ha]
    landr_ha <- ch * sum(!is.na(pg) & pg > 0)
    data.table(year = s$year, ws3_ha = ws3_ha, landr_ha = landr_ha,
               delivered = ch * sum(lengths(cuts)) / s$plan[period == 1, cut_ha])
  }))
  ## harvested cells young afterwards: cells cut in years t-10 .. t-1 at snapshot t
  regen <- rbindlist(lapply(yrs[-1], function(t) {
    cells <- unique(unlist(cutCells(run$dir, (t - 10):(t - 1))))
    ct <- cellTable(snaps[[as.character(t)]])[cell %in% cells]
    data.table(year = t, n = nrow(ct), young = ct[, sum(age <= 11)])
  }))
  data.table(
    run = tag,
    check = c("Forest area is constant (no cells lost to NA)",
              "Cut stands are at least the minimum harvest age",
              "Each plan holds its even-flow band",
              "Cut maps carry at least 95% of each plan",
              "ws3 period-1 inventory vs LandR stocked area (UNRESOLVED: reads post-solve ws3 accounting)",
              "Cells cut in the past decade are 11 years old or younger (whole decade is cut at its start)"),
    expected = c(sprintf("%s cells every decade", format(forestCells[1], big.mark = ",")),
                 sprintf(">= %d years", minAge),
                 sprintf("<= %.0f%% from period 1", 100 * flowEps),
                 ">= 95%",
                 "difference < 0.5%",
                 "100%"),
    observed = c(sprintf("%s to %s cells", format(min(forestCells), big.mark = ","), format(max(forestCells), big.mark = ",")),
                 sprintf("youngest %d years", minCut),
                 sprintf("max %.2f%%", 100 * flowDev),
                 sprintf("%.1f%% to %.1f%%", 100 * min(dt$delivered), 100 * max(dt$delivered)),
                 sprintf("max %.2f%%", 100 * max(abs(dt$ws3_ha / dt$landr_ha - 1))),
                 sprintf("%.1f%% (%s cells)", 100 * sum(regen$young) / sum(regen$n), format(sum(regen$n), big.mark = ","))),
    pass = c(length(unique(forestCells)) == 1,
             minCut >= minAge,
             flowDev <= flowEps + 1e-6,
             min(dt$delivered) >= 0.95,
             max(abs(dt$ws3_ha / dt$landr_ha - 1)) < 0.005,
             sum(regen$young) == sum(regen$n))
  )
}

## per snapshot: area by leading species and by 20-year age class
compositionTable <- function(run, tag) {
  rbindlist(lapply(run$snaps, function(s) {
    ct <- cellTable(s); ch <- cellHa(s$pixelGroupMap)
    ct[, .(area_ha = .N * ch, biomass_t = sum(totalB) * ch / 100), by = species][, `:=`(run = tag, year = s$year)]
  }))
}

ageTable <- function(run, tag) {
  rbindlist(lapply(run$snaps, function(s) {
    ct <- cellTable(s); ch <- cellHa(s$pixelGroupMap)
    ct[, age_class := pmin(floor(age / 20) * 20, 300)]
    ct[, .(area_ha = .N * ch), by = age_class][, `:=`(run = tag, year = s$year)]
  }))
}

## species of the stands ws3 cut vs the species leading those cells a decade later
regenTable <- function(run, tag) {
  yrs <- as.integer(names(run$snaps))
  rbindlist(lapply(yrs[-1], function(t) {
    before <- cellTable(run$snaps[[as.character(t - 10)]])
    after <- cellTable(run$snaps[[as.character(t)]])
    cells <- unique(unlist(cutCells(run$dir, (t - 10):(t - 1))))
    m <- merge(before[cell %in% cells, .(cell, cut_species = species)],
               after[cell %in% cells, .(cell, regen_species = species)], by = "cell")
    m[, .(cells = .N), by = .(cut_species, regen_species)][, `:=`(run = tag, year = t)]
  }))
}

## ---- plots ----------------------------------------------------------------------------------

theme_diag <- function() theme_minimal(base_size = 11) + theme(panel.grid.minor = element_blank(),
                                                               plot.title = element_text(face = "bold"))
savePlot <- function(p, outDir, name, w = 9, h = 5) {
  ggsave(file.path(outDir, paste0(name, ".png")), p, width = w, height = h, dpi = 150, bg = "white")
}

runDiagnostics <- function(runDirs, outDir = "outputs/diagnostics", minAge = 40) {
  dir.create(outDir, recursive = TRUE, showWarnings = FALSE)
  runs <- lapply(runDirs, readRun)
  tags <- names(runDirs)
  bind <- function(f, ...) rbindlist(Map(function(r, t) f(r, t, ...), runs, tags))

  dec <- bind(decadeTable); plan <- bind(planTable); ver <- bind(verifyTable, minAge = minAge)
  comp <- bind(compositionTable); ages <- bind(ageTable); regen <- bind(regenTable)
  for (x in list(list(dec, "decades"), list(plan, "plans"), list(ver, "verification"),
                 list(comp, "composition"), list(ages, "age_classes"), list(regen, "regeneration")))
    fwrite(x[[1]], file.path(outDir, paste0(x[[2]], ".csv")))

  ## V1 plan vs mapped cut area
  d <- melt(dec, id.vars = c("run", "year"), measure.vars = c("plan_cut_ha", "mapped_cut_ha"))
  savePlot(ggplot(d, aes(factor(year), value / 1000, fill = variable)) +
             geom_col(position = position_dodge(0.8), width = 0.75) + facet_wrap(~run, ncol = 1) +
             scale_fill_manual(values = c(plan_cut_ha = "grey70", mapped_cut_ha = "#2b74d6"),
                               labels = c("Planned by ws3", "On the cut maps"), name = NULL) +
             labs(title = "Planned vs mapped clearcut area, first decade of each plan", x = NULL, y = "thousand ha") +
             theme_diag(), outDir, "V1_plan_vs_mapped")

  ## V2 within-plan flow
  savePlot(ggplot(plan[, rel := cut_m3 / cut_m3[period == 1], by = .(run, plan_year)],
                  aes(year, rel, group = plan_year, colour = plan_year)) +
             annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.95, ymax = 1.05, alpha = 0.12, fill = "#2b74d6") +
             geom_line() + facet_wrap(~run, ncol = 1) + scale_colour_viridis_c(name = "Plan made") +
             labs(title = "Volume by period within each plan, relative to period 1 (band = even-flow limit)",
                  x = NULL, y = "volume / period-1 volume") + theme_diag(), outDir, "V2_even_flow")

  ## V3 cut age distribution
  cuts <- rbindlist(Map(function(r, t) rbindlist(lapply(r$snaps, function(s)
    if (nrow(s$cut)) s$cut[, .(ha = sum(ha)), by = age][, `:=`(run = t, year = s$year,
      minAge = if (is.null(s$minAge)) minAge else s$minAge)])), runs, tags))
  savePlot(ggplot(cuts, aes(age, ha / 1000)) + geom_col(fill = "grey45", width = 9) +
             geom_vline(aes(xintercept = minAge - 5), colour = "#c0392b", linetype = 2) +
             facet_grid(run ~ year) + labs(title = "Age of the stands cut in each plan's first decade (dashed = minimum age)",
                                         x = "age class (years)", y = "thousand ha") +
             theme_diag() + theme(axis.text.x = element_text(size = 7)), outDir, "V3_cut_ages", w = 14, h = 5)

  ## V4 end effect: growing stock along each plan
  savePlot(ggplot(plan, aes(year, inv_m3 / 1e6, group = plan_year, colour = plan_year)) + geom_line() +
             facet_wrap(~run, ncol = 1, scales = "free_x") + scale_colour_viridis_c(name = "Plan made") +
             labs(title = "Merchantable growing stock planned along each plan's horizon",
                  x = NULL, y = "M m³") + theme_diag(), outDir, "V4_growing_stock_horizon")

  ## A1 area vs volume tracking
  a <- melt(dec[, .(run, year, `Cut area (ha)` = plan_cut_ha, `Cut volume (m³)` = plan_cut_m3,
                    `Growing stock (m³)` = growing_stock_m3, `Forest aged 40+ (ha)` = inv_ge40_ha)],
            id.vars = c("run", "year"))[, idx := 100 * value / value[year == min(year)], by = .(run, variable)]
  savePlot(ggplot(a, aes(year, idx, colour = variable)) + geom_hline(yintercept = 100, linetype = 2, colour = "grey60") +
             geom_line(linewidth = 1) + geom_point() + facet_wrap(~run) +
             labs(title = "Harvest area vs volume and the forest behind them (2011 = 100)", x = NULL, y = "index", colour = NULL) +
             theme_diag() + theme(legend.position = "bottom"), outDir, "A1_area_vs_volume")
  savePlot(ggplot(melt(dec[, .(run, year, `m³ per ha cut` = plan_m3_per_ha, `mean age cut` = mean_cut_age,
                               `% of area cut under 60 yr` = pct_cut_under_60)], id.vars = c("run", "year")),
                  aes(year, value, colour = run)) + geom_line(linewidth = 1) + geom_point() +
             facet_wrap(~variable, scales = "free_y") + labs(title = "What is being cut", x = NULL, y = NULL) +
             theme_diag(), outDir, "A2_cut_quality", w = 11, h = 4)

  ## B1 biomass by species (Biomass_core summary)
  sbs <- rbindlist(Map(function(r, t) if (!is.null(r$summaries$summaryBySpecies))
    as.data.table(r$summaries$summaryBySpecies)[, run := t], runs, tags), fill = TRUE)
  if (nrow(sbs) && "BiomassBySpecies" %in% names(sbs)) {
    savePlot(ggplot(sbs, aes(year, BiomassBySpecies, fill = speciesCode)) + geom_area() + facet_wrap(~run) +
               labs(title = "Biomass by species (Biomass_core summary)", x = NULL, y = "biomass (g/m², landscape mean)",
                    fill = NULL) + theme_diag(), outDir, "B1_biomass_by_species")
  }

  ## B2 leading species area
  savePlot(ggplot(comp, aes(year, area_ha / 1000, fill = species)) + geom_area() + facet_wrap(~run) +
             labs(title = "Forest area by leading species", x = NULL, y = "thousand ha", fill = NULL) + theme_diag(),
           outDir, "B2_leading_species")

  ## B3 age structure
  savePlot(ggplot(ages[year %in% c(min(year), 2061, max(year))], aes(age_class, area_ha / 1000, fill = factor(year))) +
             geom_col(position = position_dodge(18), width = 17) + facet_wrap(~run, ncol = 1) +
             scale_fill_brewer(palette = "Blues", name = NULL) +
             labs(title = "Stand age structure (leading cohort, 20-year classes; 300 = 300+)", x = "age (years)",
                  y = "thousand ha") + theme_diag(), outDir, "B3_age_structure")
  old <- ages[, .(`80+` = sum(area_ha[age_class >= 80]), `140+` = sum(area_ha[age_class >= 140]),
                  `200+` = sum(area_ha[age_class >= 200])), by = .(run, year)]
  fwrite(old, file.path(outDir, "old_forest.csv"))
  savePlot(ggplot(melt(old, id.vars = c("run", "year"), variable.name = "age"), aes(year, value / 1000, colour = age, linetype = run)) +
             geom_line(linewidth = 1) + labs(title = "Old forest area by age threshold", x = NULL, y = "thousand ha") +
             theme_diag(), outDir, "B4_old_forest")

  ## B5 what regrows after harvest
  rg <- regen[, .(cells = sum(cells)), by = .(run, cut_species, regen_species)]
  savePlot(ggplot(rg, aes(cut_species, cells, fill = regen_species)) + geom_col(position = "fill") +
             facet_wrap(~run) + scale_y_continuous(labels = scales::percent) +
             labs(title = "Leading species a decade after harvest, by the species that was cut", x = "species cut",
                  y = "share of cut cells", fill = "leading after") + theme_diag() +
             theme(axis.text.x = element_text(angle = 30, hjust = 1)), outDir, "B5_regeneration")

  ## B6 maps: leading species and age, first and last snapshot, per run
  for (t in tags) {
    r <- runs[[t]]; s1 <- r$snaps[[1]]; sN <- r$snaps[[length(r$snaps)]]
    mk <- function(s, what) {
      ct <- cellTable(s); rr <- terra::rast(s$pixelGroupMap); v <- rep(NA, terra::ncell(rr))
      if (what == "age") v[ct$cell] <- ct$age else v[ct$cell] <- ct$species
      xy <- terra::xyFromCell(rr, ct$cell)
      data.table(x = xy[, 1], y = xy[, 2], value = v[ct$cell], year = s$year)
    }
    ag <- rbind(mk(s1, "age"), mk(sN, "age"))
    savePlot(ggplot(ag, aes(x, y, fill = pmin(value, 250))) + geom_raster() + coord_equal() + facet_wrap(~year) +
               scale_fill_viridis_c(name = "age") + labs(title = paste("Leading-cohort age,", t), x = NULL, y = NULL) +
               theme_void(), outDir, paste0("B6_age_map_", t), w = 11, h = 6)
    sp <- rbind(mk(s1, "species"), mk(sN, "species"))
    savePlot(ggplot(sp, aes(x, y, fill = value)) + geom_raster() + coord_equal() + facet_wrap(~year) +
               labs(title = paste("Leading species,", t), fill = NULL, x = NULL, y = NULL) + theme_void(),
             outDir, paste0("B6_species_map_", t), w = 11, h = 6)
    yrs <- seq(as.integer(names(r$snaps)[1]), max(as.integer(names(r$snaps))) - 1)
    cc <- table(unlist(cutCells(r$dir, yrs)))
    rr <- terra::rast(s1$pixelGroupMap)
    xy <- terra::xyFromCell(rr, as.integer(names(cc)))
    savePlot(ggplot(data.table(x = xy[, 1], y = xy[, 2], n = as.integer(cc)), aes(x, y, fill = factor(n))) +
               geom_raster() + coord_equal() + scale_fill_brewer(palette = "OrRd", name = "times cut") +
               labs(title = paste("Cells cut during the run,", t)) + theme_void(), outDir, paste0("B7_times_cut_", t), w = 7, h = 6)
  }
  invisible(list(decades = dec, plans = plan, verification = ver, composition = comp, ages = ages, regeneration = regen))
}
