#' Check for, and optionally install, the .NET 8 runtime
#'
#' The FraNchEstYN backend is a .NET 8 program that ships with the package. It
#' needs the .NET 8 *runtime* (not the SDK) on the computer. This function
#' checks that a usable runtime can be found and, on Linux and macOS, can
#' install one for you.
#'
#' The search follows the same order as [franchestyn()]: `options(franchestyn.dotnet)`
#' or the `FRANCHESTYN_DOTNET` environment variable (when set, only that is
#' used), then `DOTNET_ROOT`, `PATH` and the usual install locations.
#'
#' If no .NET 8 runtime is found on Linux or macOS, the function can download
#' Microsoft's official `dotnet-install.sh` script
#' (<https://dot.net/v1/dotnet-install.sh>) and run it with
#' `--channel 8.0 --runtime dotnet --install-dir ~/.dotnet`. This needs `bash`
#' and an Internet connection, does not need administrator rights and only
#' writes to `~/.dotnet`. It does not install the operating-system libraries
#' that .NET depends on; if the installer reports that any are missing, see
#' <https://learn.microsoft.com/dotnet/core/install/linux>.
#'
#' Nothing is downloaded or installed without your consent: in an interactive
#' session you are asked first, and in a non-interactive session the function
#' only installs when you call it with `install = TRUE`. On Windows the
#' function only checks, because the .NET 8 runtime there is installed with
#' Microsoft's installer from <https://dotnet.microsoft.com/download/dotnet/8.0>.
#'
#' Microsoft ended support for .NET 8 on 10 November 2026. FraNchEstYN
#' currently requires it, and a newer runtime on its own is not accepted.
#'
#' @section Using a different backend build:
#' To use a backend you built yourself (see `BUILDING-CSHARP.md` in the source
#' repository) without changing the installed package, put its
#' `FraNchEstYN.dll`, `FraNchEstYN.runtimeconfig.json`, `FraNchEstYN.deps.json`
#' and `optimizerSimplex.dll` (and `FraNchEstYN.exe` on Windows) in the folder
#' `file.path(tools::R_user_dir("FraNchEstYN", "data"), "bin")`, or set
#' `options(franchestyn.backend_dir = "/path/to/folder")`. A backend found
#' there is used instead of the one shipped with the package.
#'
#' @param install `NA` (default) asks before installing when the session is
#'   interactive and otherwise only checks. `TRUE` installs without asking when
#'   no usable runtime is found. `FALSE` only checks.
#'
#' @return Invisibly, the path to a `dotnet` executable with a .NET 8 runtime,
#'   or `NULL` if one is needed but you declined to install it. An error is
#'   raised when no runtime is available and none was installed.
#'
#' @examples
#' \dontrun{
#' # check, and offer to install, the .NET 8 runtime
#' franchestyn_setup()
#' }
#'
#' @md
#' @export
franchestyn_setup <- function(install = NA) {
  if (!is.logical(install) || length(install) != 1L) {
    stop("`install` must be TRUE, FALSE or NA.", call. = FALSE)
  }
  major <- .franchestyn_dotnet_major

  found <- tryCatch(
    .franchestyn_find_dotnet(required_major = major),
    error = function(e) e
  )
  if (!inherits(found, "error")) {
    message(".NET ", major, " runtime found: ", found)
    return(invisible(found))
  }

  # An explicit override is authoritative: never install somewhere else.
  overridden <- nzchar(Sys.getenv("FRANCHESTYN_DOTNET", unset = "")) ||
    isTRUE(nzchar(getOption("franchestyn.dotnet", default = "")))
  if (overridden || .franchestyn_is_windows() || isFALSE(install)) {
    stop(conditionMessage(found), call. = FALSE)
  }

  if (is.na(install)) {
    if (!.franchestyn_is_interactive()) {
      stop(
        conditionMessage(found),
        "\nNothing was installed because this session is not interactive; ",
        "call franchestyn_setup(install = TRUE) to allow it.",
        call. = FALSE
      )
    }
    message(
      "FraNchEstYN needs the .NET ",
      major,
      " runtime, which was not found.\n",
      "It can be installed into ",
      .franchestyn_dotnet_install_dir(),
      " by downloading and running Microsoft's installer script\n",
      "(",
      .franchestyn_dotnet_install_url(),
      "). No administrator rights are needed.\n",
      "Note: Microsoft ended support for .NET ",
      major,
      " on 10 November 2026, but FraNchEstYN currently requires it."
    )
    if (
      !isTRUE(.franchestyn_ask(paste0(
        "Install the .NET ",
        major,
        " runtime now?"
      )))
    ) {
      message("Nothing was installed.")
      return(invisible(NULL))
    }
  }

  path <- .franchestyn_install_dotnet(.franchestyn_dotnet_install_dir(), major)
  message(
    ".NET ",
    major,
    " runtime installed: ",
    path,
    "\nFraNchEstYN will find it automatically."
  )
  invisible(path)
}

# The only .NET major version the backend accepts.
.franchestyn_dotnet_major <- 8L

.franchestyn_dotnet_install_dir <- function() {
  file.path(path.expand("~"), ".dotnet")
}

# `options(franchestyn.dotnet_install_url)` exists for the package's own tests
# (it lets them use a local file instead of the Internet).
.franchestyn_dotnet_install_url <- function() {
  getOption(
    "franchestyn.dotnet_install_url",
    "https://dot.net/v1/dotnet-install.sh"
  )
}

# Thin wrappers so tests can replace the parts that depend on the session.
.franchestyn_is_windows <- function() .Platform$OS.type == "windows"
.franchestyn_is_interactive <- function() interactive()
.franchestyn_ask <- function(prompt) utils::askYesNo(prompt, default = FALSE)

# Install the .NET runtime with Microsoft's dotnet-install.sh (internal)
#
# @param dir Install directory (created if needed).
# @param major .NET major version; the channel is `<major>.0`.
# @return Path to the installed `dotnet` executable. Errors if the script
#   cannot be downloaded, fails, or does not leave a usable runtime.
.franchestyn_install_dotnet <- function(
  dir,
  major = .franchestyn_dotnet_major
) {
  url <- .franchestyn_dotnet_install_url()
  bash <- unname(Sys.which("bash"))
  if (!nzchar(bash)) {
    stop(
      "Installing .NET needs 'bash', which was not found. ",
      "Install .NET ",
      major,
      " manually: https://dotnet.microsoft.com/download/dotnet/",
      major,
      ".0",
      call. = FALSE
    )
  }

  script <- tempfile("dotnet-install-", fileext = ".sh")
  on.exit(unlink(script), add = TRUE)

  downloaded <- tryCatch(
    {
      suppressWarnings(utils::download.file(
        url,
        script,
        mode = "wb",
        quiet = TRUE
      ))
      TRUE
    },
    error = function(e) FALSE
  )
  first_line <- if (
    downloaded && file.exists(script) && file.size(script) > 0
  ) {
    readLines(script, n = 1L, warn = FALSE)
  } else {
    character()
  }
  if (!length(first_line) || !startsWith(first_line, "#!")) {
    stop(
      "Could not download the installer script from ",
      url,
      " (no connection, a proxy or firewall, or the response was not a script). ",
      "Install .NET ",
      major,
      " manually: https://dotnet.microsoft.com/download/dotnet/",
      major,
      ".0",
      call. = FALSE
    )
  }

  res <- processx::run(
    command = bash,
    args = c(
      script,
      "--channel",
      sprintf("%d.0", major),
      "--runtime",
      "dotnet",
      "--install-dir",
      dir
    ),
    echo = TRUE,
    error_on_status = FALSE,
    timeout = 1800
  )
  if (!identical(res$status, 0L)) {
    stop(
      "The .NET installer failed (exit status ",
      res$status,
      "); see its output above. On Linux this is often a missing system ",
      "library, see https://learn.microsoft.com/dotnet/core/install/linux",
      call. = FALSE
    )
  }

  exe <- file.path(dir, "dotnet")
  if (!major %in% .franchestyn_dotnet_majors(exe)) {
    stop(
      "The installer finished but no .NET ",
      major,
      " runtime was found in ",
      dir,
      ".",
      call. = FALSE
    )
  }
  exe
}
