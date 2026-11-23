# Build the C# backend on macOS or Linux

FraNchEstYN uses a C# program as its backend. This guide explains how to
install .NET and build that program. Run the commands in a terminal: open
Terminal on macOS, or your terminal application on Linux.

The `feat/cross-platform-support` branch also includes backend files in the R
package. On macOS and Linux, the R package runs the included DLL using .NET 8.
You do not need to rebuild it just to use the included backend.

## 1. Install the .NET 8 SDK

The SDK includes the tools needed to build the program and the .NET 8 runtime
needed to run it. Install the **SDK**, not just the runtime.

1. Open the [.NET 8 download page](https://dotnet.microsoft.com/download/dotnet/8.0).
2. Under **SDK**, choose your operating system and processor:
   - On macOS, choose **Arm64** for Apple silicon or **x64** for Intel, then
     download and open the installer.
   - On Linux, follow Microsoft's
     [Linux installation instructions](https://learn.microsoft.com/dotnet/core/install/linux)
     for your distribution and install the .NET 8 SDK.
3. Open a new terminal and check the installation:

   ```sh
   dotnet --list-sdks
   dotnet --list-runtimes
   ```

The first command should show an SDK starting with `8.0.`. The second should
show `Microsoft.NETCore.App 8.0.`. If `dotnet` is not found, reopen the
terminal and check the installation instructions for your system.

**Note:** .NET 8 is out of support. This project currently targets .NET 8 and
the R package specifically looks for its runtime; installing only a newer
runtime is not enough. See the [.NET support policy](https://dotnet.microsoft.com/platform/support/policy/dotnet-core).

## 2. Get the source code

If Git is installed, run:

```sh
git clone --branch feat/cross-platform-support https://github.com/adamhsparks/FraNchEstYN.git
cd FraNchEstYN
```

Alternatively, download the `feat/cross-platform-support` branch as a ZIP from
GitHub, extract it, and use `cd` in the terminal to enter the extracted
folder. The remaining commands assume you are in the repository's top folder.

## 3. Build the backend

```sh
dotnet build src_csharp/FraNchEstYN/FraNchEstYN/FraNchEstYN.csproj --configuration Release
```

The first build may need an internet connection to restore dependencies.
Look for `Build succeeded` in the output. Warnings are not necessarily
errors; if the build fails, read the error messages above the summary.

The built files are in:

```text
src_csharp/FraNchEstYN/FraNchEstYN/bin/Release/net8.0/
```

The folder includes `FraNchEstYN.dll`, its runtime configuration and
`optimizerSimplex.dll`. Keep these files together. The program needs a valid
JSON configuration and input files to run; the supplied example configuration
contains Windows paths and is not ready to run unchanged on macOS or Linux.

## 4. Use your build with the R package (optional)

Building does not automatically replace the backend in the R package. To use
your newly built backend, copy these four files into `inst/bin` before
installing the package from this checkout:

```sh
cp src_csharp/FraNchEstYN/FraNchEstYN/bin/Release/net8.0/FraNchEstYN.dll inst/bin/
cp src_csharp/FraNchEstYN/FraNchEstYN/bin/Release/net8.0/FraNchEstYN.deps.json inst/bin/
cp src_csharp/FraNchEstYN/FraNchEstYN/bin/Release/net8.0/FraNchEstYN.runtimeconfig.json inst/bin/
cp src_csharp/FraNchEstYN/FraNchEstYN/bin/Release/net8.0/optimizerSimplex.dll inst/bin/
R CMD INSTALL .
```

This last command requires R and the package's R dependencies. Installing from
GitHub instead would use the backend included in that GitHub revision, not
your local build.

The R package normally finds .NET automatically. If it cannot find the
runtime, run `which dotnet` in the terminal, then use the resulting path in R,
for example:

```r
options(franchestyn.dotnet = "/path/to/dotnet")
```

Replace `/path/to/dotnet` with the actual path. This can be useful when
RStudio does not inherit the same PATH as your terminal.
