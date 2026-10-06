# World model (layer 3): engine-agnostic; public headers expose no mirror or
# FlatBuffers types. mirror_support is linked PRIVATE so consumers cannot
# reach the mirror through this target.

add_library(worldmodel STATIC
  src/world_source.cpp
  src/sim_clock.cpp
  src/discontinuity.cpp
  src/evaluate.cpp
  src/world_model.cpp
  src/model_events.cpp
  src/spatters.cpp
  src/mirror_ingest.cpp
  src/mirror_client.cpp
  src/buffered_world_client.cpp
  src/session_client.cpp
  src/management_client.cpp
  src/management_codecs.cpp
  src/management_construction_codec.cpp
  src/management_population_codec.cpp
  src/management_production_codec.cpp
  src/management_commerce_codec.cpp
  src/management_information_codec.cpp
  src/resident_info.cpp
  src/creature_info.cpp
  src/track_path.cpp
  src/terrain_grid_sync.cpp)
target_include_directories(worldmodel PUBLIC include)
target_link_libraries(worldmodel PRIVATE mirror_support)
df3d_apply_warnings(worldmodel)

if(TARGET doctest)
find_package(Python3 COMPONENTS Interpreter REQUIRED)
add_executable(track_path_fixture tests/track_path_fixture.cpp)
target_link_libraries(track_path_fixture PRIVATE worldmodel)
df3d_apply_warnings(track_path_fixture)
add_test(NAME track_path_native_fixture COMMAND ${Python3_EXECUTABLE}
  ${CMAKE_CURRENT_SOURCE_DIR}/tests/track_path_fixture_test.py
  $<TARGET_FILE:track_path_fixture>
  ${CMAKE_SOURCE_DIR}/fixtures/construction/connected_track.json)
add_executable(worldmodel_tests
  tests/test_main.cpp
  tests/world_source_tests.cpp
  tests/buffered_world_tests.cpp
  tests/buffered_queue_ownership_tests.cpp
  tests/sim_clock_tests.cpp
  tests/discontinuity_tests.cpp
  tests/evaluate_tests.cpp
  tests/attack_tests.cpp
  tests/combat_event_tests.cpp
  tests/report_event_tests.cpp
  tests/item_contact_tests.cpp
  tests/spatter_tests.cpp
  tests/projectile_tests.cpp
  tests/pipeline_tests.cpp
  tests/terrain_tests.cpp
  tests/terrain_grid_sync_tests.cpp
  tests/entity_tests.cpp
  tests/entity_sync_tests.cpp
  tests/mirror_recovery_tests.cpp
  tests/corpse_glyph_tests.cpp
  tests/command_tests.cpp
  tests/management_tests.cpp
  tests/management_codec_tests.cpp
  tests/resident_info_tests.cpp
  tests/session_tests.cpp)
target_link_libraries(worldmodel_tests PRIVATE worldmodel mirror_support doctest)
target_include_directories(worldmodel_tests PRIVATE src)
target_compile_definitions(worldmodel_tests PRIVATE
  DF3D_FIXTURE_DIR="${CMAKE_SOURCE_DIR}/fixtures")
df3d_apply_warnings(worldmodel_tests)
add_test(NAME worldmodel_tests COMMAND worldmodel_tests)
set_tests_properties(worldmodel_tests PROPERTIES TIMEOUT 300)

endif()
