# Split at source newlines so UTF-8 code points cannot straddle C++ literals.
# Runtime concatenation preserves one Lua lexical chunk without MSVC C2026.
function(df3d_lua_expression output source)
  # C++ raw literals normalize physical source line endings to LF at runtime.
  string(REPLACE "\r\n" "\n" source "${source}")
  string(FIND "${source}" ")DF3D\"" delimiter)
  if(NOT delimiter EQUAL -1)
    message(FATAL_ERROR "Embedded Lua contains the reserved C++ raw-string delimiter")
  endif()
  set(expression "std::string()")
  string(LENGTH "${source}" remaining)
  while(remaining GREATER 0)
    set(length ${remaining})
    if(length GREATER 8192)
      string(SUBSTRING "${source}" 0 8192 prefix)
      string(FIND "${prefix}" "\n" newline REVERSE)
      if(newline EQUAL -1)
        message(FATAL_ERROR "Embedded Lua source line exceeds the 8192-byte literal bound")
      endif()
      math(EXPR length "${newline} + 1")
    endif()
    string(SUBSTRING "${source}" 0 ${length} chunk)
    string(APPEND expression "\n    + R\"DF3D(${chunk})DF3D\"")
    string(SUBSTRING "${source}" ${length} -1 source)
    string(LENGTH "${source}" remaining)
  endwhile()
  set(${output} "${expression}" PARENT_SCOPE)
endfunction()

# Embeds <name>.lua next to this file as `static const std::string k<Name>Script`
# (snake_case name -> CamelCase symbol) in <out_dir>/<name>_script.h; a change
# to the script reconfigures.
function(df3d_embed_lua_script name out_dir)
  cmake_policy(SET CMP0053 NEW)  # @symbol@ below is for file(CONFIGURE), not the parser
  set(lua "${CMAKE_CURRENT_LIST_DIR}/${name}.lua")
  set(symbol "k")
  string(REPLACE "_" ";" words "${name}")
  foreach(word IN LISTS words)
    string(SUBSTRING "${word}" 0 1 head)
    string(SUBSTRING "${word}" 1 -1 tail)
    string(TOUPPER "${head}" head)
    string(APPEND symbol "${head}${tail}")
  endforeach()
  string(APPEND symbol "Script")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${lua}")
  file(READ "${lua}" source)
  df3d_lua_expression(expression "${source}")
  file(CONFIGURE OUTPUT "${out_dir}/${name}_script.h"
       CONTENT "#pragma once\n#include <string>\nstatic const std::string @symbol@ = @expression@;\n"
       @ONLY NEWLINE_STYLE UNIX)
endfunction()
