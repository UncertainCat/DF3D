# DF3D bridge plugin — built from inside the DFHack source tree via the
# plugins/external mechanism (see plugins/CMakeLists.txt lines 163-192 in the
# DFHack tree): external/dfhack/plugins/external/CMakeLists.txt does
# add_subdirectory() of this directory, so dfhack_plugin() and the dfhack
# targets are already defined when this file is processed.
#
# Resolve from this source file, regardless of the enclosing DFHack checkout.
get_filename_component(DF3D_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)

set(DF3D_SCHEMA "${DF3D_ROOT}/schema/mirror.fbs")
set(DF3D_FLATC "${DF3D_ROOT}/third_party/flatbuffers/bin/flatc.exe")
set(DF3D_FLATBUFFERS_INCLUDE "${DF3D_ROOT}/third_party/flatbuffers/include")
set(DF3D_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")

# Generate mirror_generated.h from the canonical schema with
# the vendored flatc, using the same flags as the rest of the project.
add_custom_command(
    OUTPUT "${DF3D_GENERATED_DIR}/mirror_generated.h"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${DF3D_GENERATED_DIR}"
    COMMAND "${DF3D_FLATC}" --cpp --scoped-enums -o "${DF3D_GENERATED_DIR}" "${DF3D_SCHEMA}"
    DEPENDS "${DF3D_SCHEMA}"
    COMMENT "Generating df3d mirror_generated.h from mirror.fbs"
    VERBATIM
)
add_custom_target(df3d_generate_mirror
    DEPENDS "${DF3D_GENERATED_DIR}/mirror_generated.h")

include("${CMAKE_CURRENT_SOURCE_DIR}/embed_lua.cmake")
foreach(script IN ITEMS construction construction_track construction_material_facts construction_material_terrain construction_material_opening construction_material_shapes construction_track_material_candidates construction_material_candidate_gate construction_track_material_recipe construction_material_candidate_enabled construction_track_material_groups construction_material_partition construction_material_group_name construction_material_order construction_track_placement_plan construction_track_commit areas production work_orders citizens creature reports report_tabs report_tab_page report_tab_snapshot report_text_snapshot report_unit_profession report_unit_page report_unit_log report_unit_snapshot report_group_snapshot report_alert_dismiss report_dismissal report_entries agreements trade)
    df3d_embed_lua_script(${script} "${DF3D_GENERATED_DIR}")
endforeach()

# validate.cpp (schema validators) is compiled into the plugin so the bridge
# can validate drained commands against the live map (validateCommand).
dfhack_plugin(df3d df3d.cpp terrain_publisher.cpp appearance.cpp entities.cpp commands.cpp session.cpp interruption.cpp petition.cpp management.cpp simulation_events.cpp contact_capture.cpp room_discovery_native.cpp room_mutation_native.cpp paint_water_native.cpp location_catalog_native.cpp location_details_native.cpp location_staff_native.cpp
    "${DF3D_ROOT}/schema/cpp/validate.cpp" LINK_LIBRARIES lua jsoncpp_static)

add_dependencies(df3d df3d_generate_mirror)
# Reuse only the stateless semantic Track rules, not WorldModel, mirror clients
# or presentation state. The same source is exercised by the core native fixtures.
target_sources(df3d PRIVATE construction_track_route.cpp "${DF3D_ROOT}/worldmodel/src/track_path.cpp")
target_sources(df3d PRIVATE construction_material_native.cpp)
target_include_directories(df3d PRIVATE "${DF3D_ROOT}/worldmodel/include")
add_executable(df3d_track_callback_test EXCLUDE_FROM_ALL
    tests/construction_track_route_test.cpp construction_track_route.cpp
    "${DF3D_ROOT}/worldmodel/src/track_path.cpp")
target_include_directories(df3d_track_callback_test PRIVATE
    "${DF3D_ROOT}/worldmodel/include" "${DF3D_ROOT}/external/dfhack/depends/lua/include")
target_link_libraries(df3d_track_callback_test PRIVATE lua)
if(WIN32)
    add_custom_command(TARGET df3d_track_callback_test POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "$<TARGET_FILE:lua>" "$<TARGET_FILE_DIR:df3d_track_callback_test>")
endif()
# Project-wide warning policy (cmake/df3d_flags.cmake); the plugin is built
# from inside the DFHack tree, so include it from the DF3D root explicitly.
if(EXISTS "${DF3D_ROOT}/cmake/df3d_flags.cmake")
    include("${DF3D_ROOT}/cmake/df3d_flags.cmake")
    df3d_apply_warnings(df3d)
    # DFHack's tree adds /WX globally; the DFHack and fmt headers are not
    # /W4-clean (C4100, C4201, C4245, C4458, C4459), so keep the project
    # policy (warnings reviewed, not build breakers) for this target.
    if(MSVC)
        target_compile_options(df3d PRIVATE /WX-)
    endif()
endif()
target_include_directories(df3d PRIVATE
    "${DF3D_GENERATED_DIR}"          # mirror_generated.h
    "${DF3D_ROOT}/schema/cpp"        # shm_layout.h, command_util.h, fixture_io.h
    "${DF3D_FLATBUFFERS_INCLUDE}"    # flatbuffers/*.h
)
