#pragma once
#include <cstdint>
#include <string>
extern "C" {
#include "lua.h"
}
namespace df3d_management::lua_fields {
// Accepts integral floats too: Lua scripts build bit masks with 2^n, which is a float.
inline int64_t number(lua_State* L,const char* key,int64_t fallback=0) {lua_getfield(L,-1,key);int ok=0;auto v=lua_tointegerx(L,-1,&ok);int64_t n=ok?int64_t(v):fallback;lua_pop(L,1);return n;}
inline bool boolean(lua_State* L,const char* key,bool fallback=false) {lua_getfield(L,-1,key);bool b=lua_isnil(L,-1)?fallback:lua_toboolean(L,-1)!=0;lua_pop(L,1);return b;}
inline std::string text(lua_State* L,const char* key){lua_getfield(L,-1,key);const char* s=lua_tostring(L,-1);std::string r=s?s:"";lua_pop(L,1);return r;}
}
