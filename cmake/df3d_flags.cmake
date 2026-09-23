# Shared compiler warning policy. Applied per target so every toolchain gets
# the flags it understands (GCC/Clang: -Wall -Wextra; MSVC: /W4). No -Werror:
# warnings are reviewed, not build breakers.
include_guard(GLOBAL)

function(df3d_apply_warnings target)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "df3d_apply_warnings: no target named '${target}'")
  endif()
  get_target_property(_df3d_type ${target} TYPE)
  if(_df3d_type STREQUAL "INTERFACE_LIBRARY")
    return()
  endif()
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra)
  endif()
endfunction()
