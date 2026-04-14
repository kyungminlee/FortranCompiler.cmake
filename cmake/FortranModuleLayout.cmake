# FortranModuleLayout.cmake
#
# Detects the Fortran compiler's .mod file format version and provides
# functions for compiler-aware installation of Fortran modules and libraries.
#
# After include(FortranModuleLayout), the following variables are set:
#
#   FORTRAN_COMPILER_FAMILY   - Normalized compiler family (gfortran, intel, flang)
#   FORTRAN_COMPILER_VERSION  - Full compiler version string
#   FORTRAN_MOD_VERSION       - Internal .mod format version integer
#   FORTRAN_MOD_COMPAT_TAG    - Module compat tag for .mod dirs (e.g. gfortran-mod15)
#   FORTRAN_COMPILER_TAG      - Compiler version tag for libraries (e.g. gfortran-14)
#
# Functions provided:
#
#   fortran_module_layout(<target>)
#   fortran_install_modules(<target> [DESTINATION <base>])
#   fortran_install_library(<target> [NAMESPACE <ns>] [EXPORT <export-name>])

if(_FORTRAN_MODULE_LAYOUT_INCLUDED)
  return()
endif()
set(_FORTRAN_MODULE_LAYOUT_INCLUDED TRUE)

# ---------------------------------------------------------------------------
# Verify Fortran is enabled
# ---------------------------------------------------------------------------
get_property(_languages GLOBAL PROPERTY ENABLED_LANGUAGES)
if(NOT "Fortran" IN_LIST _languages)
  message(FATAL_ERROR "FortranModuleLayout: Fortran language must be enabled before including this module.")
endif()
unset(_languages)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

# ---------------------------------------------------------------------------
# Detect compiler family
# ---------------------------------------------------------------------------
set(FORTRAN_COMPILER_VERSION "${CMAKE_Fortran_COMPILER_VERSION}")

if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
  set(FORTRAN_COMPILER_FAMILY "gfortran")
elseif(CMAKE_Fortran_COMPILER_ID STREQUAL "Intel")
  set(FORTRAN_COMPILER_FAMILY "intel")
elseif(CMAKE_Fortran_COMPILER_ID STREQUAL "IntelLLVM")
  set(FORTRAN_COMPILER_FAMILY "intel")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "^(LLVMFlang|Flang)$")
  set(FORTRAN_COMPILER_FAMILY "flang")
else()
  set(FORTRAN_COMPILER_FAMILY "${CMAKE_Fortran_COMPILER_ID}")
  string(TOLOWER "${FORTRAN_COMPILER_FAMILY}" FORTRAN_COMPILER_FAMILY)
endif()

# ---------------------------------------------------------------------------
# Determine .mod format version from compiler family + version
# ---------------------------------------------------------------------------
set(FORTRAN_MOD_VERSION "unknown")

if(FORTRAN_COMPILER_FAMILY STREQUAL "gfortran")
  string(REGEX MATCH "^([0-9]+)" _gcc_major "${FORTRAN_COMPILER_VERSION}")
  if(_gcc_major VERSION_GREATER_EQUAL 15)
    set(FORTRAN_MOD_VERSION "16")
  elseif(_gcc_major VERSION_GREATER_EQUAL 8)
    set(FORTRAN_MOD_VERSION "15")
  elseif(_gcc_major VERSION_GREATER_EQUAL 5)
    set(FORTRAN_MOD_VERSION "14")
  elseif(_gcc_major EQUAL 4)
    string(REGEX MATCH "^4\\.([0-9]+)" _gcc_4minor "${FORTRAN_COMPILER_VERSION}")
    set(_minor "${CMAKE_MATCH_1}")
    if(_minor EQUAL 9)
      set(FORTRAN_MOD_VERSION "12")
    elseif(_minor EQUAL 8)
      set(FORTRAN_MOD_VERSION "10")
    elseif(_minor EQUAL 7)
      set(FORTRAN_MOD_VERSION "9")
    elseif(_minor EQUAL 6)
      set(FORTRAN_MOD_VERSION "6")
    elseif(_minor EQUAL 5)
      set(FORTRAN_MOD_VERSION "4")
    elseif(_minor EQUAL 4)
      set(FORTRAN_MOD_VERSION "0")
    endif()
    unset(_minor)
    unset(_gcc_4minor)
  endif()
  unset(_gcc_major)

elseif(CMAKE_Fortran_COMPILER_ID STREQUAL "Intel")
  if(FORTRAN_COMPILER_VERSION VERSION_GREATER_EQUAL "2021.10")
    set(FORTRAN_MOD_VERSION "13")
  elseif(FORTRAN_COMPILER_VERSION VERSION_GREATER_EQUAL "18.0")
    set(FORTRAN_MOD_VERSION "12")
  elseif(FORTRAN_COMPILER_VERSION VERSION_GREATER_EQUAL "17.0")
    set(FORTRAN_MOD_VERSION "11")
  elseif(FORTRAN_COMPILER_VERSION VERSION_GREATER_EQUAL "16.0")
    set(FORTRAN_MOD_VERSION "10")
  endif()

elseif(CMAKE_Fortran_COMPILER_ID STREQUAL "IntelLLVM")
  if(FORTRAN_COMPILER_VERSION VERSION_GREATER_EQUAL "2023.2")
    set(FORTRAN_MOD_VERSION "13")
  else()
    set(FORTRAN_MOD_VERSION "12")
  endif()

elseif(FORTRAN_COMPILER_FAMILY STREQUAL "flang")
  set(FORTRAN_MOD_VERSION "1")
endif()

# ---------------------------------------------------------------------------
# Build tags:
#   FORTRAN_MOD_COMPAT_TAG  - for .mod directories (by format compatibility)
#   FORTRAN_COMPILER_TAG    - for library files (by ABI-relevant version)
#
# Version truncation per family:
#   gfortran -> major only (ABI stable within a release series)
#   flang    -> major only (follows LLVM major versioning)
#   intel    -> major.minor (ABI can change at minor releases)
#   unknown  -> full version (conservative)
# ---------------------------------------------------------------------------
if(FORTRAN_COMPILER_FAMILY STREQUAL "gfortran" OR FORTRAN_COMPILER_FAMILY STREQUAL "flang")
  string(REGEX MATCH "^([0-9]+)" _abi_version "${FORTRAN_COMPILER_VERSION}")
elseif(FORTRAN_COMPILER_FAMILY STREQUAL "intel")
  string(REGEX MATCH "^([0-9]+\\.[0-9]+)" _abi_version "${FORTRAN_COMPILER_VERSION}")
else()
  set(_abi_version "${FORTRAN_COMPILER_VERSION}")
endif()
set(FORTRAN_COMPILER_TAG "${FORTRAN_COMPILER_FAMILY}-${_abi_version}")
unset(_abi_version)

if(FORTRAN_MOD_VERSION STREQUAL "unknown")
  set(FORTRAN_MOD_COMPAT_TAG "${FORTRAN_COMPILER_TAG}")
else()
  set(FORTRAN_MOD_COMPAT_TAG "${FORTRAN_COMPILER_FAMILY}-mod${FORTRAN_MOD_VERSION}")
endif()

message(STATUS "FortranModuleLayout: compiler=${CMAKE_Fortran_COMPILER_ID} ${FORTRAN_COMPILER_VERSION}")
message(STATUS "FortranModuleLayout: family=${FORTRAN_COMPILER_FAMILY}, mod_version=${FORTRAN_MOD_VERSION}")
message(STATUS "FortranModuleLayout: mod_tag=${FORTRAN_MOD_COMPAT_TAG}, lib_tag=${FORTRAN_COMPILER_TAG}")

# ---------------------------------------------------------------------------
# fortran_module_layout(<target>)
#
# Configures the target's module output directory and include paths.
# Uses FORTRAN_MOD_COMPAT_TAG for module directories.
# ---------------------------------------------------------------------------
function(fortran_module_layout target)
  set(_moddir "${PROJECT_BINARY_DIR}/fmod/${FORTRAN_MOD_COMPAT_TAG}")

  set_target_properties(${target} PROPERTIES
    Fortran_MODULE_DIRECTORY "${_moddir}"
  )

  target_include_directories(${target} PUBLIC
    $<BUILD_INTERFACE:${_moddir}>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_LIBDIR}/fortran/modules/${PROJECT_NAME}/${FORTRAN_MOD_COMPAT_TAG}>
  )
endfunction()

# ---------------------------------------------------------------------------
# fortran_install_modules(<target> [DESTINATION <base>])
#
# Installs .mod files to <base>/fortran/modules/<project>/<mod-compat-tag>/
# Default DESTINATION is ${CMAKE_INSTALL_LIBDIR}.
# ---------------------------------------------------------------------------
function(fortran_install_modules target)
  cmake_parse_arguments(PARSE_ARGV 1 ARG "" "DESTINATION" "")
  if(NOT ARG_DESTINATION)
    set(ARG_DESTINATION "${CMAKE_INSTALL_LIBDIR}")
  endif()

  set(_moddir "${PROJECT_BINARY_DIR}/fmod/${FORTRAN_MOD_COMPAT_TAG}")
  set(_install_moddir "${ARG_DESTINATION}/fortran/modules/${PROJECT_NAME}/${FORTRAN_MOD_COMPAT_TAG}")

  install(
    DIRECTORY "${_moddir}/"
    DESTINATION "${_install_moddir}"
    FILES_MATCHING PATTERN "*.mod"
  )
endfunction()

# ---------------------------------------------------------------------------
# fortran_install_library(<target>
#     [NAMESPACE <ns>]
#     [EXPORT <export-name>]
#     [DESTINATION <lib-dir>])
#
# Installs the library with a compiler-version-tagged filename (for ABI),
# while the export/config system uses the mod compat tag to find modules.
# ---------------------------------------------------------------------------
function(fortran_install_library target)
  cmake_parse_arguments(PARSE_ARGV 1 ARG "" "NAMESPACE;EXPORT;DESTINATION" "")
  if(NOT ARG_NAMESPACE)
    set(ARG_NAMESPACE "${PROJECT_NAME}::")
  endif()
  if(NOT ARG_EXPORT)
    set(ARG_EXPORT "${PROJECT_NAME}Targets")
  endif()
  if(NOT ARG_DESTINATION)
    set(ARG_DESTINATION "${CMAKE_INSTALL_LIBDIR}")
  endif()

  set(_config_name "${PROJECT_NAME}")
  set(_cmake_install_dir "${ARG_DESTINATION}/cmake/${_config_name}")
  # Export file is keyed by compiler version (since the library binary is)
  set(_targets_file "${ARG_EXPORT}-${FORTRAN_COMPILER_TAG}.cmake")

  # Tag the library output filename by compiler version (ABI compatibility)
  set_target_properties(${target} PROPERTIES
    OUTPUT_NAME "${target}-${FORTRAN_COMPILER_TAG}"
  )

  install(TARGETS ${target}
    EXPORT ${ARG_EXPORT}
    ARCHIVE DESTINATION "${ARG_DESTINATION}"
    LIBRARY DESTINATION "${ARG_DESTINATION}"
  )

  install(EXPORT ${ARG_EXPORT}
    FILE "${_targets_file}"
    NAMESPACE "${ARG_NAMESPACE}"
    DESTINATION "${_cmake_install_dir}"
  )

  # Generate Config.cmake that finds the right targets file.
  # Strategy: the config derives the consumer's compiler tag and looks for
  # an exact-version match first, then falls back to scanning for any
  # matching compiler family build.
  set(_config_content "\
# ${_config_name}Config.cmake
# Auto-generated by FortranModuleLayout.cmake
#
# Detects the consuming compiler and includes the matching targets file.
# Library files are tagged by compiler version (ABI compatibility).
# Module directories are tagged by .mod format version (compile-time compatibility).

cmake_minimum_required(VERSION 3.20)

# --- Derive consumer's compiler family and version tag ---
set(_FML_consumer_family \"\")

if(CMAKE_Fortran_COMPILER_ID STREQUAL \"GNU\")
  set(_FML_consumer_family \"gfortran\")
elseif(CMAKE_Fortran_COMPILER_ID STREQUAL \"Intel\")
  set(_FML_consumer_family \"intel\")
elseif(CMAKE_Fortran_COMPILER_ID STREQUAL \"IntelLLVM\")
  set(_FML_consumer_family \"intel\")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES \"^(LLVMFlang|Flang)$\")
  set(_FML_consumer_family \"flang\")
else()
  set(_FML_consumer_family \"\${CMAKE_Fortran_COMPILER_ID}\")
  string(TOLOWER \"\${_FML_consumer_family}\" _FML_consumer_family)
endif()

if(_FML_consumer_family STREQUAL \"gfortran\" OR _FML_consumer_family STREQUAL \"flang\")
  string(REGEX MATCH \"^([0-9]+)\" _FML_abi_version \"\${CMAKE_Fortran_COMPILER_VERSION}\")
elseif(_FML_consumer_family STREQUAL \"intel\")
  string(REGEX MATCH \"^([0-9]+\\\\.[0-9]+)\" _FML_abi_version \"\${CMAKE_Fortran_COMPILER_VERSION}\")
else()
  set(_FML_abi_version \"\${CMAKE_Fortran_COMPILER_VERSION}\")
endif()
set(_FML_consumer_tag \"\${_FML_consumer_family}-\${_FML_abi_version}\")
unset(_FML_abi_version)

# Look for exact compiler version match
set(_FML_targets_file \"\${CMAKE_CURRENT_LIST_DIR}/${ARG_EXPORT}-\${_FML_consumer_tag}.cmake\")

if(NOT EXISTS \"\${_FML_targets_file}\")
  # Fall back: scan for any build from the same compiler family
  file(GLOB _FML_candidates \"\${CMAKE_CURRENT_LIST_DIR}/${ARG_EXPORT}-\${_FML_consumer_family}-*.cmake\")
  if(_FML_candidates)
    # Use the first match (most recently installed typically)
    list(GET _FML_candidates 0 _FML_targets_file)
    message(STATUS \"${_config_name}: exact match for '\${_FML_consumer_tag}' not found, using \${_FML_targets_file}\")
  else()
    set(\${CMAKE_FIND_PACKAGE_NAME}_FOUND FALSE)
    set(\${CMAKE_FIND_PACKAGE_NAME}_NOT_FOUND_MESSAGE
      \"${_config_name}: no pre-built library found for compiler '\${_FML_consumer_tag}'.\"
      \" Available builds can be found in \${CMAKE_CURRENT_LIST_DIR}/.\")
    unset(_FML_consumer_family)
    unset(_FML_consumer_tag)
    unset(_FML_targets_file)
    return()
  endif()
  unset(_FML_candidates)
endif()

include(\"\${_FML_targets_file}\")

unset(_FML_consumer_family)
unset(_FML_consumer_tag)
unset(_FML_targets_file)
")

  file(GENERATE
    OUTPUT "${PROJECT_BINARY_DIR}/cmake/${_config_name}Config.cmake"
    CONTENT "${_config_content}"
  )

  install(
    FILES "${PROJECT_BINARY_DIR}/cmake/${_config_name}Config.cmake"
    DESTINATION "${_cmake_install_dir}"
  )
endfunction()
