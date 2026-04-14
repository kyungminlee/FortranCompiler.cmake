cmake_minimum_required(VERSION 3.20)
project(Example VERSION 1.0.0 LANGUAGES C Fortran)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(FortranCompiler)

add_library(example src/example_mod.f90)
fortran_module_layout(example)

fortran_install_modules(example)
fortran_install_library(example NAMESPACE Example::)
