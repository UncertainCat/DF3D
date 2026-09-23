cmake_minimum_required(VERSION 3.20)
project(df3d LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug)
endif()

add_compile_options(-Wall -Wextra)

if(MINGW)
  # Static runtime: Strawberry Perl's c\bin (machine PATH) ships older MinGW
  # runtime DLLs that shadow msys64's and crash our exes with
  # STATUS_ENTRYPOINT_NOT_FOUND when resolved first. Static linking removes
  # the PATH dependency entirely.
  add_link_options(-static)
endif()

enable_testing()

# Vendored, pinned tooling (see PINS.md).
add_library(doctest INTERFACE)
target_include_directories(doctest INTERFACE ${CMAKE_SOURCE_DIR}/third_party/doctest)

add_library(flatbuffers_headers INTERFACE)
target_include_directories(flatbuffers_headers INTERFACE
  ${CMAKE_SOURCE_DIR}/third_party/flatbuffers/include)

add_subdirectory(schema)
add_subdirectory(worldmodel)
add_subdirectory(consumers/inspector)
add_subdirectory(presentations/godot/mesher)
add_subdirectory(presentations/assets)
add_subdirectory(tools)

# Profiling controls remain testable without loading Godot or a fortress.
find_package(Threads REQUIRED)
add_executable(profiling_tests presentations/godot/extension/tests/profiling_tests.cpp)
target_link_libraries(profiling_tests PRIVATE Threads::Threads)
add_test(NAME profiling_tests COMMAND profiling_tests)

# Presentation dependency invalidation, exercised without Godot or DF assets.
add_executable(glyph_dependencies_tests presentations/godot/extension/tests/glyph_dependencies_tests.cpp)
target_link_libraries(glyph_dependencies_tests PRIVATE worldmodel df3d_assets doctest)
add_test(NAME glyph_dependencies_tests COMMAND glyph_dependencies_tests)

add_executable(terrain_visibility_dependencies_tests presentations/godot/extension/tests/terrain_visibility_dependencies_tests.cpp)
target_link_libraries(terrain_visibility_dependencies_tests PRIVATE worldmodel doctest)
add_test(NAME terrain_visibility_dependencies_tests COMMAND terrain_visibility_dependencies_tests)

add_executable(sprite_ceiling_cache_tests presentations/godot/extension/tests/sprite_ceiling_cache_tests.cpp)
target_link_libraries(sprite_ceiling_cache_tests PRIVATE worldmodel doctest)
add_test(NAME sprite_ceiling_cache_tests COMMAND sprite_ceiling_cache_tests)

add_executable(quiet_sources_tests presentations/godot/extension/tests/quiet_sources_tests.cpp)
target_link_libraries(quiet_sources_tests PRIVATE doctest)
add_test(NAME quiet_sources_tests COMMAND quiet_sources_tests)
add_executable(effect_material_tests presentations/godot/extension/tests/effect_material_tests.cpp)
target_link_libraries(effect_material_tests PRIVATE df3d_assets doctest)
add_test(NAME effect_material_tests COMMAND effect_material_tests)
