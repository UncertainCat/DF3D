# DF3D terrain mesher: the Godot presentation's pure manifest stage.
# Engine-agnostic C++20 (no godot headers) so it is tier-0/1 testable in the
# root build and linked into the GDExtension by presentations/godot/extension.
get_filename_component(DF3D_MESHER_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)

# Warning flags: the shared helper when the root provides it (cmake/df3d_flags.cmake),
# otherwise the equivalent direct flags so the extension's standalone build
# and the root build compile this tree with the same diagnostics. Never -Werror.
if(NOT COMMAND df3d_apply_warnings AND EXISTS "${DF3D_MESHER_ROOT}/cmake/df3d_flags.cmake")
  include("${DF3D_MESHER_ROOT}/cmake/df3d_flags.cmake")
endif()
function(df3d_mesher_warnings target)
  if(COMMAND df3d_apply_warnings)
    df3d_apply_warnings(${target})
  else()
    target_compile_options(${target} PRIVATE
      $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wall -Wextra>
      $<$<CXX_COMPILER_ID:MSVC>:/W4>)
  endif()
endfunction()

add_library(df3d_mesher STATIC src/block_mesher.cpp src/lazy_tile_layout.cpp)
target_include_directories(df3d_mesher PUBLIC include)
df3d_mesher_warnings(df3d_mesher)
if(TARGET worldmodel)
  target_link_libraries(df3d_mesher PUBLIC worldmodel)
else()
  # Standalone manifest-only embedding: headers suffice. The Godot
  # extension defines and links the worldmodel target above.
  target_include_directories(df3d_mesher PUBLIC "${DF3D_MESHER_ROOT}/worldmodel/include")
endif()

if(TARGET doctest)
  add_executable(mesher_tests tests/mesher_tests.cpp)
  target_link_libraries(mesher_tests PRIVATE df3d_mesher mirror_support doctest)
  target_compile_definitions(mesher_tests PRIVATE
    DF3D_FIXTURE_DIR="${DF3D_MESHER_ROOT}/fixtures")
  add_test(NAME mesher_tests COMMAND mesher_tests)
  df3d_mesher_warnings(mesher_tests)

  add_executable(occluder_tests tests/occluder_tests.cpp)
  target_link_libraries(occluder_tests PRIVATE df3d_mesher doctest)
  add_test(NAME occluder_tests COMMAND occluder_tests)
  df3d_mesher_warnings(occluder_tests)

  add_executable(auxiliary_cache_tests tests/auxiliary_cache_tests.cpp)
  target_link_libraries(auxiliary_cache_tests PRIVATE df3d_mesher doctest)
  add_test(NAME auxiliary_cache_tests COMMAND auxiliary_cache_tests)
  df3d_mesher_warnings(auxiliary_cache_tests)

  add_executable(lazy_tile_layout_tests tests/lazy_tile_layout_tests.cpp)
  target_link_libraries(lazy_tile_layout_tests PRIVATE df3d_mesher doctest)
  add_test(NAME lazy_tile_layout_tests COMMAND lazy_tile_layout_tests)
  df3d_mesher_warnings(lazy_tile_layout_tests)
  # Deterministic unit tests: a hang is a failure, not a wait.
  set_tests_properties(mesher_tests occluder_tests auxiliary_cache_tests lazy_tile_layout_tests
    PROPERTIES TIMEOUT 300)
endif()
