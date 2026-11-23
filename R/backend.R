# Where the backend files come from -------------------------------------------
#
# Order: options(franchestyn.backend_dir), then a complete backend in the user
# folder tools::R_user_dir("FraNchEstYN", "data")/bin, then the copy shipped in
# the package (inst/bin). The user folder lets someone use their own build
# without touching the installed package, which may be read-only.

.franchestyn_state <- new.env(parent = emptyenv())

# Files a backend folder must contain to be usable on this platform.
.franchestyn_backend_files <- function() {
  unique(c(
    if (.Platform$OS.type == "windows") "FraNchEstYN.exe",
    "FraNchEstYN.dll",
    "FraNchEstYN.runtimeconfig.json",
    "optimizerSimplex.dll"
  ))
}

.franchestyn_missing_backend_files <- function(dir) {
  need <- .franchestyn_backend_files()
  need[!file.exists(file.path(dir, need))]
}

.franchestyn_announce_backend <- function(dir, why) {
  if (!identical(.franchestyn_state$announced, dir)) {
    message("Using the FraNchEstYN backend from ", why, ": ", dir)
    .franchestyn_state$announced <- dir
  }
}

# Folder holding the backend files to run (internal)
#
# @return Path of the folder to copy the backend from.
.franchestyn_backend_dir <- function() {
  opt <- getOption("franchestyn.backend_dir", default = "")
  if (is.character(opt) && length(opt) == 1L && !is.na(opt) && nzchar(opt)) {
    dir <- path.expand(opt)
    missing_files <- .franchestyn_missing_backend_files(dir)
    if (length(missing_files)) {
      stop(
        "options(franchestyn.backend_dir) is '",
        opt,
        "' but that folder does not contain: ",
        paste(missing_files, collapse = ", "),
        call. = FALSE
      )
    }
    dir <- normalizePath(dir, winslash = "/", mustWork = TRUE)
    .franchestyn_announce_backend(dir, "options(franchestyn.backend_dir)")
    return(dir)
  }

  user_dir <- file.path(tools::R_user_dir("FraNchEstYN", "data"), "bin")
  if (dir.exists(user_dir)) {
    missing_files <- .franchestyn_missing_backend_files(user_dir)
    if (!length(missing_files)) {
      user_dir <- normalizePath(user_dir, winslash = "/", mustWork = TRUE)
      .franchestyn_announce_backend(user_dir, "your user folder")
      return(user_dir)
    }
    warning(
      "Ignoring the backend folder ",
      user_dir,
      " because it does not contain: ",
      paste(missing_files, collapse = ", "),
      ". Using the backend shipped with the package.",
      call. = FALSE
    )
  }

  system.file("bin", package = "FraNchEstYN")
}
