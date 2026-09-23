# DF3D Godot GDExtension. Standalone CMake project (not part of the root
# build): configure with the msys64 compilers pinned explicitly — plain g++
# on PATH may resolve to Strawberry Perl's gcc 13, and C:\msys64\mingw64\bin
# must ALSO be prepended to PATH or Strawberry's runtime DLLs shadow
# msys64's and g++ itself crashes on launch (see PINS.md toolchain):
#
#   $env:Path = "C:\msys64\mingw64\bin;$env:Path"
#   cmake -S presentations/godot/extension -B build/godot-ext -G "MinGW Makefiles"
#         -DCMAKE_BUILD_TYPE=RelWithDebInfo
#         -DCMAKE_C_COMPILER=C:/msys64/mingw64/bin/gcc.exe
#         -DCMAKE_CXX_COMPILER=C:/msys64/mingw64/bin/g++.exe
#         -DCMAKE_MAKE_PROGRAM=C:/msys64/mingw64/bin/mingw32-make.exe
#   cmake --build build/godot-ext -j
#
# Output: presentations/godot/project/bin/df3d_godot.dll
cmake_minimum_required(VERSION 3.20)
project(df3d_godot LANGUAGES CXX)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Build type" FORCE)
endif()
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  message(FATAL_ERROR "Use Release or RelWithDebInfo for the interactive extension")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

get_filename_component(DF3D_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)

# Shared warning flags (cmake/df3d_flags.cmake provides df3d_apply_warnings when
# present, and the layer 2/3 trees below expect it); the direct equivalent otherwise. Never -Werror.
if(NOT COMMAND df3d_apply_warnings AND EXISTS "${DF3D_ROOT}/cmake/df3d_flags.cmake")
  include("${DF3D_ROOT}/cmake/df3d_flags.cmake")
endif()
function(df3d_godot_warnings target)
  if(COMMAND df3d_apply_warnings)
    df3d_apply_warnings(${target})
  else()
    target_compile_options(${target} PRIVATE
      $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wall -Wextra>
      $<$<CXX_COMPILER_ID:MSVC>:/W4>)
  endif()
endfunction()


# Compile layer 2/3 in this optimized build tree. Target dependencies track
# all source/header/schema changes; no prebuilt root archives are consumed.
add_library(flatbuffers_headers INTERFACE)
target_include_directories(flatbuffers_headers INTERFACE "${DF3D_ROOT}/third_party/flatbuffers/include")
add_subdirectory("${DF3D_ROOT}/schema" schema)
add_subdirectory("${DF3D_ROOT}/worldmodel" worldmodel)

# godot-cpp pinned at external/godot-cpp (see PINS.md). add_subdirectory is
# the supported consumption route; target `godot-cpp` propagates includes,
# WINDOWS_ENABLED, and MinGW static-runtime link options (PUBLIC).
# GODOTCPP_TARGET follows the build type: the optimized DLL links the
# template_release library (no debug-feature bookkeeping, no hot-reload
# accounting) instead of template_debug. DF3D_GODOTCPP_TARGET overrides.
set(DF3D_GODOTCPP_TARGET "" CACHE STRING
  "godot-cpp target to link (empty: template_release for Release/RelWithDebInfo/MinSizeRel, template_debug otherwise)")
if(DF3D_GODOTCPP_TARGET)
  set(_df3d_godotcpp_target "${DF3D_GODOTCPP_TARGET}")
elseif(CMAKE_BUILD_TYPE MATCHES "^(Release|RelWithDebInfo|MinSizeRel)$")
  set(_df3d_godotcpp_target template_release)
else()
  set(_df3d_godotcpp_target template_debug)
endif()
set(GODOTCPP_TARGET "${_df3d_godotcpp_target}" CACHE STRING "godot-cpp build target" FORCE)
message(STATUS "df3d_godot: ${CMAKE_BUILD_TYPE} build links godot-cpp ${GODOTCPP_TARGET}")
add_subdirectory("${DF3D_ROOT}/external/godot-cpp" godot-cpp)

# The pure mesher (presentations/godot/mesher) is compiled into this build
# (RelWithDebInfo) rather than linked from the root Debug build: it is the
# hot path per block. It sees no godot headers.
add_subdirectory("${DF3D_ROOT}/presentations/godot/mesher" mesher)
# The asset provider: install discovery, raw parsing, terrain
# and creature resolution. Engine-agnostic; textures are loaded here.
add_subdirectory("${DF3D_ROOT}/presentations/assets" assets)

add_library(df3d_godot SHARED
  src/mesh_batches.cpp
  src/item_payload_kernel.cpp
  src/unit_visual_changes.cpp
  src/df3d_world.cpp
  src/df3d_bindings.cpp
  src/df3d_assets.cpp
  src/df3d_sprite_resources.cpp
  src/df3d_commands.cpp
  src/df3d_requests.cpp
  src/management_construction_codec.cpp
  src/management_production_codec.cpp
  src/management_population_codec.cpp
  src/management_commerce_codec.cpp
  src/management_information_codec.cpp
  src/df3d_resident_info.cpp
  src/df3d_inspection.cpp
  src/df3d_effect_events.cpp
  src/df3d_render_queries.cpp
  src/df3d_entities.cpp
  src/df3d_items.cpp
  src/df3d_depth.cpp
  src/df3d_layout.cpp
  src/df3d_profiling.cpp
  src/df3d_ui.cpp
  src/df3d_selection.cpp
  src/register_types.cpp)

target_link_libraries(df3d_godot PRIVATE
  godot-cpp
  df3d_mesher
  df3d_assets
  worldmodel)
df3d_godot_warnings(df3d_godot)

set_target_properties(df3d_godot PROPERTIES
  PREFIX ""
  OUTPUT_NAME "df3d_godot"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../project/bin")
