# Mirror layer: canonical schema + codegen + validators + fixture I/O.
# FlatBuffers code lands in the build tree. Small neutral/Godot enum contracts
# are checked in for editor use and verified against mirror.fbs on every build.

set(FLATC ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/flatbuffers/bin/flatc.exe)
set(MIRROR_GEN_DIR ${CMAKE_BINARY_DIR}/generated)

add_custom_command(
  OUTPUT ${MIRROR_GEN_DIR}/mirror_generated.h
  COMMAND ${FLATC} --cpp --scoped-enums -o ${MIRROR_GEN_DIR}
          ${CMAKE_CURRENT_SOURCE_DIR}/mirror.fbs
  DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/mirror.fbs
  COMMENT "flatc: generating mirror schema C++")

add_custom_target(mirror_codegen DEPENDS ${MIRROR_GEN_DIR}/mirror_generated.h)

add_library(mirror_support STATIC
  cpp/fixture_io.cpp
  cpp/validate.cpp
  cpp/synthetic_builder.cpp)
add_dependencies(mirror_support mirror_codegen)
target_include_directories(mirror_support PUBLIC ${MIRROR_GEN_DIR} cpp)
target_link_libraries(mirror_support PUBLIC flatbuffers_headers)

if(TARGET doctest)
add_executable(schema_tests tests/validate_tests.cpp tests/shm_tests.cpp
  tests/terrain_tests.cpp tests/appearance_tests.cpp tests/entity_tests.cpp
  tests/corpse_glyph_tests.cpp tests/command_tests.cpp tests/item_visibility_tests.cpp)
target_sources(schema_tests PRIVATE tests/designation_tests.cpp tests/unit_status_tests.cpp tests/track_route_tests.cpp)
target_link_libraries(schema_tests PRIVATE mirror_support doctest)
add_test(NAME schema_tests COMMAND schema_tests)

endif()

# Checked-in neutral/Godot constants must match the canonical wire vocabulary.
find_package(Python3 REQUIRED COMPONENTS Interpreter)
add_test(NAME management_contract_check
  COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/../tools/generate_management_contract.py --check)
