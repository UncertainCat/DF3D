# Text inspector (cheap consumer #2). Links only the world model — the
# mirror is out of reach by construction.

add_library(inspector_lib STATIC inspect.cpp)
target_include_directories(inspector_lib PUBLIC .)
target_link_libraries(inspector_lib PUBLIC worldmodel)

add_executable(inspector main.cpp)
target_link_libraries(inspector PRIVATE inspector_lib)

add_executable(inspector_tests tests/inspector_tests.cpp)
target_link_libraries(inspector_tests PRIVATE inspector_lib mirror_support doctest)
add_test(NAME inspector_tests COMMAND inspector_tests)
set_tests_properties(inspector_tests PROPERTIES TIMEOUT 300)
