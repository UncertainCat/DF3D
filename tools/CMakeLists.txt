option(DF3D_BUILD_TOOLS "Build fixture generators and probes" ON)

add_executable(live_client live_client.cpp)
target_link_libraries(live_client PRIVATE worldmodel inspector_lib)

add_executable(session_client session_client.cpp)
target_link_libraries(session_client PRIVATE worldmodel)

add_executable(fixture_evidence fixture_evidence.cpp)
target_link_libraries(fixture_evidence PRIVATE worldmodel mirror_support)

add_executable(management_lua_contract_tests test_management_lua_contract.cpp)
target_include_directories(management_lua_contract_tests PRIVATE ${CMAKE_SOURCE_DIR}/external/dfhack/depends/lua/include)
target_link_libraries(management_lua_contract_tests PRIVATE mirror_support)

add_executable(management_contract_host management_contract_host.cpp)
target_link_libraries(management_contract_host PRIVATE mirror_support)

# Header-only bridge / extension policies, one doctest binary.
add_executable(bridge_policy_tests
  bridge_policy_tests_main.cpp
  test_bridge_scheduling.cpp
  test_client_mailbox.cpp
  test_fortress_population.cpp
  test_interruption_policy.cpp
  test_item_group_members.cpp
  test_layout_causal_probe.cpp
  test_notification_groups.cpp
  test_pending_work.cpp
  test_petition_policy.cpp
  test_report_journal.cpp
  smoke/attack_assembler_test.cpp
  smoke/contact_guard_test.cpp
  smoke/dwarf_layer_anatomy_test.cpp
  smoke/map_warning_policy_test.cpp)
target_link_libraries(bridge_policy_tests PRIVATE mirror_support doctest)
add_test(NAME bridge_policy_tests COMMAND bridge_policy_tests)

# Synthetic before/after designation recordings replayed through the
# engine-independent evidence checker (was a 6 MB recorded fixture).
add_executable(make_designation_fixture make_designation_fixture.cpp)
target_link_libraries(make_designation_fixture PRIVATE mirror_support)
add_test(NAME designation_fixture_evidence
  COMMAND ${CMAKE_COMMAND}
    -DGENERATOR=$<TARGET_FILE:make_designation_fixture>
    -DEVIDENCE=$<TARGET_FILE:fixture_evidence>
    -DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/designation_fixture
    -P ${CMAKE_CURRENT_SOURCE_DIR}/designation_fixture_evidence.cmake)

if(DF3D_BUILD_TOOLS)
  foreach(fixture IN ITEMS demo interaction depth_cache vertical_motion render_cache
          item_updates spatter effect_events corpse_handoff truescale ramp_support
          resource_lifetime)
    add_executable(make_${fixture}_fixture make_${fixture}_fixture.cpp)
    target_link_libraries(make_${fixture}_fixture PRIVATE mirror_support)
  endforeach()

  add_executable(stream_reader_probe stream_reader_probe.cpp)
  target_link_libraries(stream_reader_probe PRIVATE worldmodel)

  add_executable(body_part_stream_probe smoke/body_part_stream_probe.cpp)
  target_link_libraries(body_part_stream_probe PRIVATE worldmodel)

  if(WIN32)
    add_executable(audio_guard audio_guard.cpp)
    target_link_libraries(audio_guard PRIVATE ole32 uuid)
    if(MINGW)
      target_link_options(audio_guard PRIVATE -municode)
    endif()

    # Live command-guard client used by tools/smoke/designation_acceptance.ps1 -GuardProbe.
    # Talks to a running bridge over the shared region; not a test.
    add_executable(command_guard_live qa/command_guard_live.cpp)
    target_link_libraries(command_guard_live PRIVATE mirror_support)
  endif()
endif()

# Warnings for every target in this directory (cmake/df3d_flags.cmake, when configured from a DF3D root).
if(COMMAND df3d_apply_warnings)
  get_property(_df3d_dir_targets DIRECTORY PROPERTY BUILDSYSTEM_TARGETS)
  foreach(_t IN LISTS _df3d_dir_targets)
    get_target_property(_kind ${_t} TYPE)
    if(NOT _kind STREQUAL "INTERFACE_LIBRARY" AND NOT _kind STREQUAL "UTILITY")
      df3d_apply_warnings(${_t})
    endif()
  endforeach()
endif()
