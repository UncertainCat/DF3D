# DF3D terrain mesher: the Godot presentation's pure manifest stage.
# Engine-agnostic C++20 (no godot headers) so it is tier-0/1 testable in the
# root build and linked into the GDExtension by presentations/godot/extension.
get_filename_component(DF3D_MESHER_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)

add_library(df3d_mesher STATIC src/block_mesher.cpp src/lazy_tile_layout.cpp)
target_include_directories(df3d_mesher PUBLIC include)
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

  add_executable(occluder_tests tests/occluder_tests.cpp)
  target_link_libraries(occluder_tests PRIVATE df3d_mesher doctest)
  add_test(NAME occluder_tests COMMAND occluder_tests)

  add_executable(auxiliary_cache_tests tests/auxiliary_cache_tests.cpp)
  target_link_libraries(auxiliary_cache_tests PRIVATE df3d_mesher doctest)
  add_test(NAME auxiliary_cache_tests COMMAND auxiliary_cache_tests)

  add_executable(lazy_tile_layout_tests tests/lazy_tile_layout_tests.cpp)
  target_link_libraries(lazy_tile_layout_tests PRIVATE df3d_mesher doctest)
  add_test(NAME lazy_tile_layout_tests COMMAND lazy_tile_layout_tests)
endif()
