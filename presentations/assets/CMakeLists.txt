# DF3D asset provider: shared layer-4 infrastructure. Locates
# the Steam install, parses its graphics raws into an index, resolves
# semantic terrain / creature queries to texture regions. Engine-agnostic
# C++20 (no godot headers); only the world model's POD vocabulary
# (wm/types.h, header-only) is used for the query enums. Built and tier-0
# tested in the root build and compiled into the Godot extension.
get_filename_component(DF3D_ASSETS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)

add_library(df3d_assets STATIC
  src/raw_tokens.cpp
  src/steam_install.cpp
  src/index_parse.cpp
  src/index_cache.cpp
  src/resolver.cpp
  src/entity_resolver.cpp
  src/provider.cpp
  src/compositor.cpp
  src/classic_glyphs.cpp)
target_include_directories(df3d_assets PUBLIC include "${DF3D_ASSETS_ROOT}/worldmodel/include")
if(WIN32)
  target_link_libraries(df3d_assets PUBLIC advapi32)
endif()

if(TARGET doctest)
  add_executable(assets_tests tests/assets_tests.cpp tests/compositor_tests.cpp tests/entity_tests.cpp tests/glyph_tests.cpp tests/spatter_tests.cpp)
  target_link_libraries(assets_tests PRIVATE df3d_assets doctest)
  target_compile_definitions(assets_tests PRIVATE
    DF3D_ASSETS_TEST_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests")
  add_test(NAME assets_tests COMMAND assets_tests)
endif()
