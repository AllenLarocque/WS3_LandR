library(testthat)
source("modules/biomass_yieldTablesWS3/R/curveCache.R")

test_that("devTypeTupleKey produces consistent pipe-delimited string key", {
  key <- devTypeTupleKey("Pice_mar", "low", "eco1")
  expect_equal(key, "Pice_mar|low|eco1")
})

test_that("devTypeTupleKey errors on NA input", {
  expect_error(devTypeTupleKey(NA, "low", "eco1"))
  expect_error(devTypeTupleKey("Pice_mar", NA, "eco1"))
})

test_that("diffDevTypes returns only new tuples not in cache", {
  cached  <- c("Pice_mar|low|eco1", "Pinu_ban|med|eco1")
  current <- c("Pice_mar|low|eco1", "Pinu_ban|med|eco1", "Abie_bal|high|eco2")
  result  <- diffDevTypes(current, cached)
  expect_equal(result, "Abie_bal|high|eco2")
})

test_that("diffDevTypes returns all tuples when cache is empty", {
  current <- c("Pice_mar|low|eco1", "Pinu_ban|med|eco1")
  result  <- diffDevTypes(current, character(0))
  expect_equal(sort(result), sort(current))
})

test_that("diffDevTypes returns empty when all tuples already cached", {
  cached  <- c("Pice_mar|low|eco1", "Pinu_ban|med|eco1")
  current <- c("Pice_mar|low|eco1", "Pinu_ban|med|eco1")
  result  <- diffDevTypes(current, cached)
  expect_equal(result, character(0))
})

test_that("saveCurveCache and loadCurveCache roundtrip correctly", {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp))
  curves <- list(
    "Pice_mar|low|eco1" = data.frame(age = 0:5, vol_m3ha = c(0, 1, 3, 6, 10, 15))
  )
  saveCurveCache(curves, tmp)
  loaded <- loadCurveCache(tmp)
  expect_equal(loaded, curves)
})

test_that("loadCurveCache returns empty list when file does not exist", {
  result <- loadCurveCache("/nonexistent/path/curves.rds")
  expect_equal(result, list())
})

test_that("saveCurveCache returns the cache path invisibly", {
  tmp <- tempfile(fileext = ".rds")
  on.exit(unlink(tmp))
  result <- saveCurveCache(list(), tmp)
  expect_equal(result, tmp)
})
