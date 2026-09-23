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
foreach(script IN ITEMS construction areas production work_orders citizens creature reports agreements trade)
    df3d_embed_lua_script(${script} "${DF3D_GENERATED_DIR}")
endforeach()

# validate.cpp (schema validators) is compiled into the plugin so the bridge
# can validate drained commands against the live map (validateCommand).
dfhack_plugin(df3d df3d.cpp terrain_publisher.cpp appearance.cpp entities.cpp commands.cpp session.cpp interruption.cpp petition.cpp management.cpp simulation_events.cpp contact_capture.cpp
    "${DF3D_ROOT}/schema/cpp/validate.cpp" LINK_LIBRARIES lua)

add_dependencies(df3d df3d_generate_mirror)
target_include_directories(df3d PRIVATE
    "${DF3D_GENERATED_DIR}"          # mirror_generated.h
    "${DF3D_ROOT}/schema/cpp"        # shm_layout.h, command_util.h, fixture_io.h
    "${DF3D_FLATBUFFERS_INCLUDE}"    # flatbuffers/*.h
)
