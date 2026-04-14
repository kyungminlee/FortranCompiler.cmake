# FortranCompiler.cmake

A CMake module that detects the Fortran compiler's `.mod` file format version and provides functions for compiler-aware installation of Fortran modules and libraries.

## Problem

Fortran `.mod` files are incompatible across compiler families (gfortran, Intel, Flang) and can break across major versions within the same family. A library distributing pre-compiled `.mod` files must isolate them by compiler. Additionally, compiled library binaries have ABI compatibility boundaries that don't always align with `.mod` format boundaries.

This module solves both problems with two separate tagging schemes:

- **Module directories** are tagged by `.mod` format version (e.g., `gfortran-mod15`), grouping compilers that produce interchangeable `.mod` files. For example, GCC 8 through 14 all share `gfortran-mod15/`.
- **Library filenames** are tagged by compiler ABI version (e.g., `gfortran-14`), using per-family version truncation that matches actual ABI stability boundaries.

## Quick start

```cmake
cmake_minimum_required(VERSION 3.20)
project(MyLib VERSION 1.0.0 LANGUAGES C Fortran)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(FortranCompiler)

add_library(mylib src/mymodule.f90)
fortran_module_layout(mylib)

fortran_install_modules(mylib)
fortran_install_library(mylib NAMESPACE MyLib::)
```

Downstream consumers use `find_package()`:

```cmake
find_package(MyLib REQUIRED)
target_link_libraries(myapp MyLib::mylib)
```

The generated `MyLibConfig.cmake` automatically detects the consumer's compiler and selects the matching build.

## Installed directory layout

```
<PREFIX>/lib/
  libmylib-gfortran-14.a            # library tagged by compiler ABI version
  libmylib-intel-2025.0.a
  libmylib-flang-22.a
  cmake/MyLib/
    MyLibConfig.cmake                # auto-selects by consumer's compiler
    MyLibTargets-gfortran-14.cmake
    MyLibTargets-intel-2025.0.cmake
    MyLibTargets-flang-22.cmake
  fmod/
    gfortran-mod15/                  # GCC 8-14 all share this
      mymodule.mod
    intel-mod13/
      mymodule.mod
    flang-mod1/
      mymodule.mod
```

## Variables

After `include(FortranCompiler)`, the following variables are set:

| Variable | Example | Description |
|---|---|---|
| `FORTRAN_COMPILER_FAMILY` | `gfortran` | Normalized compiler family |
| `FORTRAN_COMPILER_VERSION` | `14.2.0` | Full compiler version string |
| `FORTRAN_MOD_VERSION` | `15` | Internal `.mod` format version (or `unknown`) |
| `FORTRAN_MOD_COMPAT_TAG` | `gfortran-mod15` | Tag for module directories |
| `FORTRAN_COMPILER_TAG` | `gfortran-14` | Tag for library filenames |

## Functions

### `fortran_module_layout(<target>)`

Sets up build-time and install-time module directories for a Fortran library target. Must be called before `fortran_install_modules()` or `fortran_install_library()`.

Effects:
- Sets `Fortran_MODULE_DIRECTORY` on the target
- Adds `BUILD_INTERFACE` and `INSTALL_INTERFACE` include directories

### `fortran_install_modules(<target> [DESTINATION <base>])`

Installs `.mod` and `.smod` files to `<base>/fmod/<mod-compat-tag>/`. Default `DESTINATION` is `${CMAKE_INSTALL_LIBDIR}`.

Requires `fortran_module_layout()` to have been called on the target first.

### `fortran_install_library(<target> [NAMESPACE <ns>] [EXPORT <export-name>] [DESTINATION <lib-dir>])`

Installs the library with a compiler-version-tagged filename and generates a `<ProjectName>Config.cmake` for `find_package()` support.

| Parameter | Default | Description |
|---|---|---|
| `NAMESPACE` | `${PROJECT_NAME}::` | Namespace for exported targets |
| `EXPORT` | `${PROJECT_NAME}Targets` | Export set name |
| `DESTINATION` | `${CMAKE_INSTALL_LIBDIR}` | Library install directory |

For projects with multiple Fortran library targets, add them all to the same `EXPORT` set. The Config.cmake and export file are generated once per export set.

## Supported compilers

| Compiler | CMake ID | Family | `.mod` format versions |
|---|---|---|---|
| GNU gfortran | `GNU` | `gfortran` | 0 (4.4), 4 (4.5), 6 (4.6), 9 (4.7), 10 (4.8), 12 (4.9), 14 (5-7), **15 (8-14)**, 16 (15+) |
| Intel ifort | `Intel` | `intel` | 10 (16.x), 11 (17.x), 12 (18.x-2021.9), 13 (2021.10+) |
| Intel ifx | `IntelLLVM` | `intel` | 12 (<2023.2), **13 (2023.2+)** |
| LLVM Flang | `LLVMFlang` | `flang` | 1 |
| Classic Flang | `Flang` | `flang-classic` | unknown (tagged by version) |
| NVIDIA nvfortran | `NVHPC` | `nvhpc` | unknown (tagged by version) |
| NAG | `NAG` | `nag` | unknown (tagged by version) |
| Cray | `Cray` | `cray` | unknown (tagged by version) |

### ABI version truncation

Library filenames use ABI-relevant version granularity per compiler family:

| Family | Truncation | Rationale |
|---|---|---|
| `gfortran` | Major only (e.g., `14`) | GCC guarantees ABI stability within a release series |
| `flang` | Major only (e.g., `22`) | Follows LLVM major versioning |
| `intel` | Major.minor (e.g., `2025.0`) | ABI can change at minor releases |
| Others | Full version | Conservative fallback |

## Requirements

- CMake 3.20+
- Fortran language enabled before `include(FortranCompiler)`
