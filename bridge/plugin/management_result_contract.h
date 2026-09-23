#pragma once
#include <string>
#include "mirror_generated.h"
extern "C" {
#include "lua.h"
}
namespace df3d_management {
// All helper envelopes are typed; optional fields may be absent, but may not
// change type. Validate before any permissive DTO defaults are applied.
inline std::string managementResultError(lua_State* L,df3d::mirror::ManagementAction action) {
    using A=df3d::mirror::ManagementAction;
    if(!lua_istable(L,-1))return "result must be a table";
    auto field=[&](const char* key,int type,bool required) {
        lua_getfield(L,-1,key);const int actual=lua_type(L,-1);lua_pop(L,1);
        return actual==type || (!required && actual==LUA_TNIL);
    };
    auto integer=[&](const char* key,lua_Integer low,lua_Integer high) {
        lua_getfield(L,-1,key);
        const bool ok=lua_isinteger(L,-1) && lua_tointeger(L,-1)>=low && lua_tointeger(L,-1)<=high;
        lua_pop(L,1);return ok;
    };
    if(!field("ok",LUA_TBOOLEAN,true))return "ok must be a boolean";
    if(!field("message",LUA_TSTRING,true))return "message must be a string";
    if(!field("pending",LUA_TBOOLEAN,false))return "pending must be a boolean when present";
    lua_getfield(L,-1,"ok");const bool ok=lua_toboolean(L,-1);lua_pop(L,1);
    lua_getfield(L,-1,"pending");const bool pending=lua_toboolean(L,-1);lua_pop(L,1);
    if(!ok || pending)return {};
    if(action==A::Catalog && !field("catalog",LUA_TTABLE,true))return "catalog must be a table";
    if(action==A::Preview && (!field("placement_valid",LUA_TBOOLEAN,true) ||
        !integer("required",0,65535) || !field("inputs",LUA_TTABLE,true)))return "preview metadata is incomplete";
    if(action==A::CreatureInspect && (!integer("unit_id",0,INT32_MAX) ||
        !integer("captured_tick",0,INT64_MAX) || !field("complete",LUA_TBOOLEAN,true) ||
        !field("sections",LUA_TTABLE,true)))return "creature metadata is incomplete";
    return {};
}
} // namespace df3d_management
