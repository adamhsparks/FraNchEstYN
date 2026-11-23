# Helpers ---------------------------------------------------------------------

# A fake `dotnet` that reports one Microsoft.NETCore.App runtime.
fake_dotnet <- function(path, major = 8L) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(
    c(
      "#!/bin/sh",
      "if [ \"$1\" = \"--list-runtimes\" ]; then",
      sprintf("  echo \"Microsoft.NETCore.App %d.0.1 [/x]\"", major),
      "fi",
      "exit 0"
    ),
    path
  )
  Sys.chmod(path, "755")
  path
}

# A fake dotnet-install.sh. It records its arguments in `log`, creates
# <install-dir>/dotnet (reporting runtime `major`) and exits with `status`.
fake_installer <- function(log, major = 8L, status = 0L) {
  script <- tempfile(fileext = ".sh")
  writeLines(
    c(
      "#!/bin/bash",
      sprintf("echo \"$@\" > '%s'", log),
      "while [ $# -gt 0 ]; do",
      "  case \"$1\" in --install-dir) dir=\"$2\"; shift;; esac",
      "  shift",
      "done",
      "mkdir -p \"$dir\"",
      "cat > \"$dir/dotnet\" <<'EOS'",
      "#!/bin/sh",
      "if [ \"$1\" = \"--list-runtimes\" ]; then",
      sprintf("  echo \"Microsoft.NETCore.App %d.0.1 [/x]\"", major),
      "fi",
      "EOS",
      "chmod +x \"$dir/dotnet\"",
      sprintf("exit %d", status)
    ),
    script
  )
  script
}

# Pretend no usable runtime is installed and no override is set.
local_no_runtime <- function(env = parent.frame()) {
  withr::local_options(franchestyn.dotnet = NULL, .local_envir = env)
  withr::local_envvar(FRANCHESTYN_DOTNET = NA, .local_envir = env)
  testthat::local_mocked_bindings(
    .franchestyn_find_dotnet = function(...) stop("no .NET 8 runtime here"),
    .package = "FraNchEstYN",
    .env = env
  )
}

# `pkg:::obj$name <- value` is not valid R, so go through the environment.
reset_announcement <- function() {
  state <- FraNchEstYN:::.franchestyn_state
  state$announced <- ""
}

make_backend <- function(dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(dir, FraNchEstYN:::.franchestyn_backend_files()))
  dir
}

# franchestyn_setup() ---------------------------------------------------------

test_that("an existing .NET 8 runtime is returned and nothing is installed", {
  skip_on_os("windows")
  exe <- fake_dotnet(file.path(tempfile(), "dotnet"))
  withr::local_options(franchestyn.dotnet = exe)
  local_mocked_bindings(
    .franchestyn_install_dotnet = function(...) stop("must not install"),
    .package = "FraNchEstYN"
  )

  expect_message(res <- franchestyn_setup(install = TRUE), ".NET 8 runtime found")
  expect_equal(res, exe)
})

test_that("only .NET 8 is accepted", {
  skip_on_os("windows")
  exe <- fake_dotnet(file.path(tempfile(), "dotnet"), major = 9L)
  withr::local_options(franchestyn.dotnet = exe)
  local_mocked_bindings(
    .franchestyn_install_dotnet = function(...) stop("must not install"),
    .package = "FraNchEstYN"
  )

  expect_error(franchestyn_setup(install = TRUE), "runtime\\(s\\) 9")
})

test_that("install = FALSE only checks", {
  local_no_runtime()
  local_mocked_bindings(
    .franchestyn_install_dotnet = function(...) stop("must not install"),
    .package = "FraNchEstYN"
  )

  expect_error(franchestyn_setup(install = FALSE), "no .NET 8 runtime here")
})

test_that("a non-interactive session never installs unless asked to", {
  local_no_runtime()
  local_mocked_bindings(
    .franchestyn_is_windows = function() FALSE,
    .franchestyn_is_interactive = function() FALSE,
    .franchestyn_install_dotnet = function(...) stop("must not install"),
    .package = "FraNchEstYN"
  )

  expect_error(franchestyn_setup(), "not interactive")
})

test_that("install = TRUE installs into ~/.dotnet without asking", {
  local_no_runtime()
  seen <- NULL
  local_mocked_bindings(
    .franchestyn_is_windows = function() FALSE,
    .franchestyn_is_interactive = function() FALSE,
    .franchestyn_ask = function(...) stop("must not ask"),
    .franchestyn_install_dotnet = function(dir, major) {
      seen <<- list(dir = dir, major = major)
      "/installed/dotnet"
    },
    .package = "FraNchEstYN"
  )

  msgs <- capture_messages(res <- franchestyn_setup(install = TRUE))
  expect_match(paste(msgs, collapse = ""), "runtime installed")
  expect_equal(res, "/installed/dotnet")
  expect_equal(seen$dir, file.path(path.expand("~"), ".dotnet"))
  expect_equal(seen$major, 8L)
})

test_that("an interactive session is asked first", {
  local_no_runtime()
  answer <- TRUE
  asked <- 0L
  installed <- 0L
  local_mocked_bindings(
    .franchestyn_is_windows = function() FALSE,
    .franchestyn_is_interactive = function() TRUE,
    .franchestyn_ask = function(prompt) {
      asked <<- asked + 1L
      answer
    },
    .franchestyn_install_dotnet = function(dir, major) {
      installed <<- installed + 1L
      "/installed/dotnet"
    },
    .package = "FraNchEstYN"
  )

  msgs <- capture_messages(res <- franchestyn_setup())
  expect_match(paste(msgs, collapse = ""), "ended support for .NET 8")
  expect_equal(res, "/installed/dotnet")
  expect_equal(c(asked, installed), c(1L, 1L))

  answer <- FALSE
  msgs <- capture_messages(res <- franchestyn_setup())
  expect_match(paste(msgs, collapse = ""), "Nothing was installed")
  expect_null(res)
  expect_equal(c(asked, installed), c(2L, 1L))

  answer <- NA
  suppressMessages(expect_null(franchestyn_setup()))
  expect_equal(installed, 1L)
})

test_that("an explicit dotnet override is never replaced by an installation", {
  local_no_runtime()
  withr::local_options(franchestyn.dotnet = "/does/not/exist/dotnet")
  local_mocked_bindings(
    .franchestyn_is_windows = function() FALSE,
    .franchestyn_install_dotnet = function(...) stop("must not install"),
    .package = "FraNchEstYN"
  )

  expect_error(franchestyn_setup(install = TRUE), "no .NET 8 runtime here")
})

test_that("Windows is only checked, never installed", {
  local_no_runtime()
  local_mocked_bindings(
    .franchestyn_is_windows = function() TRUE,
    .franchestyn_install_dotnet = function(...) stop("must not install"),
    .package = "FraNchEstYN"
  )

  expect_error(franchestyn_setup(install = TRUE), "no .NET 8 runtime here")
})

test_that("install must be TRUE, FALSE or NA", {
  expect_error(franchestyn_setup(install = "yes"), "TRUE, FALSE or NA")
  expect_error(franchestyn_setup(install = c(TRUE, FALSE)), "TRUE, FALSE or NA")
})

# .franchestyn_install_dotnet() ----------------------------------------------

test_that("the installer script is downloaded and run with the right arguments", {
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("bash")), "bash is not available")
  log <- tempfile()
  dir <- file.path(tempfile(), ".dotnet")
  withr::local_options(
    franchestyn.dotnet_install_url = paste0("file://", fake_installer(log))
  )

  exe <- capture.output(res <- FraNchEstYN:::.franchestyn_install_dotnet(dir, 8L))
  expect_equal(res, file.path(dir, "dotnet"))
  expect_equal(
    trimws(readLines(log)),
    paste("--channel 8.0 --runtime dotnet --install-dir", dir)
  )
  expect_equal(FraNchEstYN:::.franchestyn_dotnet_majors(res), 8L)
})

test_that("a failing installer is reported", {
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("bash")), "bash is not available")
  withr::local_options(
    franchestyn.dotnet_install_url = paste0(
      "file://",
      fake_installer(tempfile(), status = 3L)
    )
  )

  capture.output(
    expect_error(
      FraNchEstYN:::.franchestyn_install_dotnet(tempfile(), 8L),
      "installer failed \\(exit status 3\\)"
    )
  )
})

test_that("an installer that leaves a different runtime is reported", {
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("bash")), "bash is not available")
  withr::local_options(
    franchestyn.dotnet_install_url = paste0(
      "file://",
      fake_installer(tempfile(), major = 9L)
    )
  )

  capture.output(
    expect_error(
      FraNchEstYN:::.franchestyn_install_dotnet(tempfile(), 8L),
      "no .NET 8 runtime was found"
    )
  )
})

test_that("a download that is not a script is rejected before it is run", {
  skip_on_os("windows")
  skip_if(!nzchar(Sys.which("bash")), "bash is not available")
  page <- tempfile(fileext = ".html")
  writeLines("<html>Sign in to the network</html>", page)

  withr::local_options(franchestyn.dotnet_install_url = paste0("file://", page))
  expect_error(
    FraNchEstYN:::.franchestyn_install_dotnet(tempfile(), 8L),
    "Could not download the installer script"
  )

  withr::local_options(
    franchestyn.dotnet_install_url = "file:///does/not/exist.sh"
  )
  expect_error(
    FraNchEstYN:::.franchestyn_install_dotnet(tempfile(), 8L),
    "Could not download the installer script"
  )
})

# Backend folder --------------------------------------------------------------

test_that("the shipped backend is used by default", {
  withr::local_options(franchestyn.backend_dir = NULL)
  withr::local_envvar(R_USER_DATA_DIR = tempfile())

  expect_equal(
    FraNchEstYN:::.franchestyn_backend_dir(),
    system.file("bin", package = "FraNchEstYN")
  )
})

test_that("options(franchestyn.backend_dir) wins and must be complete", {
  dir <- make_backend(file.path(tempfile(), "my backend"))
  withr::local_envvar(R_USER_DATA_DIR = tempfile())
  withr::local_options(franchestyn.backend_dir = dir)
  reset_announcement()

  expect_message(
    res <- FraNchEstYN:::.franchestyn_backend_dir(),
    "options\\(franchestyn.backend_dir\\)"
  )
  expect_equal(res, normalizePath(dir, winslash = "/"))
  # announced once per folder, not on every call
  expect_no_message(FraNchEstYN:::.franchestyn_backend_dir())

  unlink(file.path(dir, "optimizerSimplex.dll"))
  expect_error(
    FraNchEstYN:::.franchestyn_backend_dir(),
    "does not contain: optimizerSimplex.dll"
  )
})

test_that("a complete backend in the user folder is used, an incomplete one is not", {
  withr::local_options(franchestyn.backend_dir = NULL)
  withr::local_envvar(R_USER_DATA_DIR = tempfile())
  user_bin <- file.path(tools::R_user_dir("FraNchEstYN", "data"), "bin")
  make_backend(user_bin)
  reset_announcement()

  expect_message(
    res <- FraNchEstYN:::.franchestyn_backend_dir(),
    "your user folder"
  )
  expect_equal(res, normalizePath(user_bin, winslash = "/"))

  unlink(file.path(user_bin, "FraNchEstYN.runtimeconfig.json"))
  expect_warning(
    res <- FraNchEstYN:::.franchestyn_backend_dir(),
    "Ignoring the backend folder .*FraNchEstYN.runtimeconfig.json"
  )
  expect_equal(res, system.file("bin", package = "FraNchEstYN"))
})
