test_that("backend copies exclude installed results and calibration lookup is isolated", {
  root <- tempfile()
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  bin <- file.path(root, "bin")
  work <- file.path(root, "work")
  calib <- file.path(root, "calibratedParameters")
  dir.create(bin)
  dir.create(work)
  dir.create(calib)
  dir.create(file.path(bin, "calibratedParameters"))
  writeLines("backend", file.path(bin, "FraNchEstYN.dll"))
  writeLines("stale", file.path(bin, "calibratedParameters", "stale.csv"))

  FraNchEstYN:::.franchestyn_copy_backend(bin, work)
  expect_true(file.exists(file.path(work, "FraNchEstYN.dll")))
  expect_length(FraNchEstYN:::.franchestyn_calibration_files(calib, work), 0)
  expect_true(file.exists(file.path(bin, "calibratedParameters", "stale.csv")))

  dir.create(file.path(work, "calibratedParameters"))
  legacy <- file.path(work, "calibratedParameters", "current.csv")
  writeLines("current", legacy)
  expect_equal(FraNchEstYN:::.franchestyn_calibration_files(calib, work), legacy)

  configured <- file.path(calib, "current.csv")
  writeLines("configured", configured)
  expect_equal(FraNchEstYN:::.franchestyn_calibration_files(calib, work), configured)
})

test_that("calibration returns values produced by the isolated backend", {
  if (.Platform$OS.type != "windows") {
    dotnet <- tryCatch(
      FraNchEstYN:::.franchestyn_find_dotnet(),
      error = function(e) NULL
    )
    skip_if(is.null(dotnet), ".NET 8 runtime is not installed")
  }

  old_options <- options(franchestyn.keep_run_dir = TRUE)
  on.exit(options(old_options), add = TRUE)
  run_dir <- NULL
  on.exit(if (!is.null(run_dir)) unlink(run_dir, recursive = TRUE), add = TRUE)
  bin <- system.file("bin", package = "FraNchEstYN")
  installed_files <- list.files(bin, recursive = TRUE, full.names = TRUE)
  installed_hashes <- tools::md5sum(installed_files)
  warnings <- character()

  result <- withCallingHandlers(
    franchestyn(
      weather_data = weather_indiana,
      management_data = management_indiana,
      reference_data = reference_indiana,
      cropParameters = cropParameters$wheat,
      diseaseParameters = diseaseParameters$septoria,
      calibration = "disease",
      start_end = c(1972, 1974),
      iterations = 1
    ),
    message = function(m) {
      text <- conditionMessage(m)
      if (startsWith(text, "Run files kept in: ")) {
        run_dir <<- trimws(sub("Run files kept in: ", "", text, fixed = TRUE))
      }
    },
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
    }
  )

  expect_false(any(grepl("no calibrated parameter files|backend wrote its results", warnings)))
  expect_false(is.null(run_dir))
  files <- FraNchEstYN:::.franchestyn_calibration_files(
    file.path(run_dir, "calibratedParameters"),
    file.path(run_dir, "work")
  )
  expect_length(files, 1)
  params <- read.csv(files[[1]], stringsAsFactors = FALSE)
  expect_gt(nrow(params), 0)
  param <- as.character(params$param[[1]])
  expected <- max(
    result$parameters$disease[[param]]$min,
    min(result$parameters$disease[[param]]$max, params$value[[1]])
  )
  expect_equal(result$parameters$disease[[param]]$value, expected)
  expect_true(file.exists(file.path(run_dir, "work", "outputs", "Indiana_Generic.csv")))
  expect_equal(tools::md5sum(installed_files), installed_hashes)
  expect_equal(list.files(bin, recursive = TRUE, full.names = TRUE), installed_files)
})
