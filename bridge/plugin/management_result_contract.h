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
    if(action>=A::WorkOrderList && action<=A::WorkOrderCatalog) {
        auto optionalInteger=[&](const char* key,lua_Integer low,lua_Integer high) {
            lua_getfield(L,-1,key);const bool absent=lua_isnil(L,-1);lua_pop(L,1);
            return absent || integer(key,low,high);
        };
        if(!optionalInteger("list_revision",0,INT64_MAX))return "list_revision must be an integer in 0..INT64_MAX";
        if(!optionalInteger("build_phase",0,3))return "build_phase must be an integer in 0..3";
        if(!optionalInteger("active_kinds",0,31))return "active_kinds must be an integer in 0..31";
        if(!optionalInteger("steps",0,2048))return "steps must be an integer in 0..2048";
        if(!field("active",LUA_TBOOLEAN,false))return "active must be a boolean when present";
    }
    if(action<=A::RemoveConstruction || action==A::ConstructionMaterials) {
        auto optionalInteger=[&](const char* key,lua_Integer low,lua_Integer high) {
            lua_getfield(L,-1,key);const bool absent=lua_isnil(L,-1);lua_pop(L,1);
            return absent || integer(key,low,high);
        };
        if(!optionalInteger("list_revision",0,INT64_MAX))return "list_revision must be an integer in 0..INT64_MAX";
        if(!optionalInteger("build_phase",0,2))return "build_phase must be an integer in 0..2";
        for(const char* key:{"placed","skipped","chunk_placed"})if(!optionalInteger(key,0,1024))return std::string(key)+" must be an integer in 0..1024";
        if(!optionalInteger("first_building",-1,INT32_MAX))return "first_building must be an integer in -1..INT32_MAX";
        if(!optionalInteger("steps",0,2048))return "steps must be an integer in 0..2048";
        if(!optionalInteger("active_kinds",0,8))return "active_kinds must be an integer in 0..8";
        if(!field("active",LUA_TBOOLEAN,false))return "active must be a boolean when present";
    }
    if(!ok || pending)return {};
    if(action>=A::WorkOrderList && action<=A::WorkOrderCatalog) {
        const int top=lua_gettop(L);
        lua_getfield(L,-1,"orders");
        if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1);++i) {
            lua_rawgeti(L,-1,i);
            if(!lua_istable(L,-1)){lua_settop(L,top);return "order must be a table";}
            lua_getfield(L,-1,"conditions");
            if(lua_istable(L,-1))for(size_t j=1;j<=lua_rawlen(L,-1);++j) {
                lua_rawgeti(L,-1,j);
                if(!lua_istable(L,-1)){lua_settop(L,top);return "condition must be a table";}
                lua_getfield(L,-1,"traits");
                if(!lua_isnil(L,-1) && !lua_istable(L,-1)) {
                    lua_settop(L,top);return "condition traits must be a table";
                }
                if(lua_istable(L,-1))for(size_t k=1;k<=lua_rawlen(L,-1);++k) {
                    lua_rawgeti(L,-1,k);
                    const bool string=lua_type(L,-1)==LUA_TSTRING;lua_pop(L,1);
                    if(!string){lua_settop(L,top);return "condition trait must be a string";}
                }
                lua_pop(L,2);
            }
            lua_pop(L,2);
        }
        lua_settop(L,top);
    }
    if(action==A::Catalog && !field("catalog",LUA_TTABLE,true))return "catalog must be a table";
    if(action==A::Preview && (!field("placement_valid",LUA_TBOOLEAN,true) ||
        !integer("required",0,65535) || !field("inputs",LUA_TTABLE,true)))return "preview metadata is incomplete";
    if(action==A::CreatureInspect && (!integer("unit_id",0,INT32_MAX) ||
        !integer("captured_tick",0,INT64_MAX) || !field("complete",LUA_TBOOLEAN,true) ||
        !field("sections",LUA_TTABLE,true)))return "creature metadata is incomplete";
    return {};
}
} // namespace df3d_management
