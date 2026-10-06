#pragma once
#include <algorithm>
#include <string>
#include <functional>
#include "mirror_generated.h"
extern "C" {
#include "lua.h"
}
namespace df3d_management {
inline bool synchronousAreaRead(df3d::mirror::ManagementAction action,df3d::mirror::AreaOperation operation) {
    return action==df3d::mirror::ManagementAction::AreaInspect &&
        (operation==df3d::mirror::AreaOperation::SettingsPage || operation==df3d::mirror::AreaOperation::None);
}
// Existing reads retain their builder/inline scheduling. Selected synchronous
// operations report measured work plus opaque work outside those budgets.
// This is an implementation choice, not a universal read/write policy.
inline bool synchronousAreaWrite(df3d::mirror::ManagementAction action,df3d::mirror::AreaOperation operation) {
    // These edits use a synchronous path under the 2026-09-28 guidance.
    // Other producers retain their current scheduling until deliberately changed.
    return (action==df3d::mirror::ManagementAction::AreaCreate &&
        (operation==df3d::mirror::AreaOperation::None || operation==df3d::mirror::AreaOperation::Paint)) ||
        (action==df3d::mirror::ManagementAction::AreaDelete && operation==df3d::mirror::AreaOperation::None) ||
        (action==df3d::mirror::ManagementAction::AreaUpdate &&
        (operation==df3d::mirror::AreaOperation::SettingsSet || operation==df3d::mirror::AreaOperation::Preset || operation==df3d::mirror::AreaOperation::LocationSet ||
         operation==df3d::mirror::AreaOperation::LocationCreate || operation==df3d::mirror::AreaOperation::None ||
         operation==df3d::mirror::AreaOperation::ZoneSettings || operation==df3d::mirror::AreaOperation::Paint));
}
inline std::string areaWorkResultError(lua_State* L,uint64_t budget) {
    const int top=lua_gettop(L);
    if(!lua_istable(L,-1))return "area work result must be a table";
    lua_getfield(L,-1,"steps");
    const bool steps=lua_isinteger(L,-1) && lua_tointeger(L,-1)>=0 && uint64_t(lua_tointeger(L,-1))<=budget;
    lua_settop(L,top);
    if(!steps)return "steps must be an integer within the area work budget";
    lua_getfield(L,-1,"active_kinds");
    const bool mask=lua_isinteger(L,-1) && lua_tointeger(L,-1)>=0 &&
        (uint64_t(lua_tointeger(L,-1)) & ~uint64_t(0xe0))==0;
    lua_settop(L,top);
    return mask ? "" : "active_kinds must be a subset of 0xE0";
}
inline std::string areaResultError(lua_State* L,df3d::mirror::AreaOperation operation,uint32_t stepBudget,bool synchronous=false) {
    struct Restore { lua_State* L; int top; ~Restore(){lua_settop(L,top);} } restore{L,lua_gettop(L)};
    std::string error;size_t payload=0,extentTotal=0,linkTotal=0;
    auto bad=[&](const std::string& value){if(error.empty())error=value;return false;};
    auto number=[&](const char* key,lua_Integer low,lua_Integer high,bool required=false) {
        lua_getfield(L,-1,key);const bool absent=lua_isnil(L,-1);
        const bool valid=(!required && absent) || (lua_isinteger(L,-1) && lua_tointeger(L,-1)>=low && lua_tointeger(L,-1)<=high);
        lua_pop(L,1);return valid || bad(std::string(key)+" must be an integer in "+std::to_string(low)+".."+std::to_string(high));
    };
    auto value=[&](const char* key,lua_Integer fallback=0) {
        lua_getfield(L,-1,key);const auto result=lua_isnil(L,-1)?fallback:lua_tointeger(L,-1);lua_pop(L,1);return result;
    };
    auto boolean=[&](const char* key) {
        lua_getfield(L,-1,key);const bool valid=lua_isnil(L,-1) || lua_type(L,-1)==LUA_TBOOLEAN;
        lua_pop(L,1);return valid || bad(std::string(key)+" must be a boolean");
    };
    auto text=[&](const char* key,size_t cap,bool required=true) {
        lua_getfield(L,-1,key);const bool absent=lua_isnil(L,-1);
        const bool valid=(!required && absent) || (lua_type(L,-1)==LUA_TSTRING && lua_rawlen(L,-1)<=cap);
        if(valid && !absent)payload+=lua_rawlen(L,-1);
        lua_pop(L,1);
        return valid || bad(std::string(key)+" must be a string of at most "+std::to_string(cap)+" bytes");
    };
    auto array=[&](const char* key,size_t cap,const std::function<bool()>& row) {
        const int top=lua_gettop(L);lua_getfield(L,-1,key);
        if(lua_isnil(L,-1)){lua_settop(L,top);return true;}
        if(!lua_istable(L,-1)){lua_settop(L,top);return bad(std::string(key)+" must be an array");}
        const int table=lua_gettop(L);const size_t size=lua_rawlen(L,table);
        bool valid=size<=cap;
        // rawlen alone would silently discard sparse or keyed overflow entries.
        size_t seen=0;lua_pushnil(L);
        while(valid && lua_next(L,table)!=0) {
            valid=++seen<=cap && lua_isinteger(L,-2) && lua_tointeger(L,-2)>=1 && uint64_t(lua_tointeger(L,-2))<=size;
            lua_pop(L,1);
        }
        lua_settop(L,table);
        if(!valid || seen!=size){lua_settop(L,top);return bad(std::string(key)+" must be a dense array of at most "+std::to_string(cap)+" entries");}
        if(std::string(key)=="extents")extentTotal+=size;
        if(std::string(key)=="gives" || std::string(key)=="takes")linkTotal+=size;
        if(extentTotal>32768 || linkTotal>8192){lua_settop(L,top);return bad("area response exceeds bounded payload");}
        for(size_t i=1;i<=size && valid;++i){lua_rawgeti(L,table,i);valid=row();lua_pop(L,1);}
        lua_settop(L,top);return valid;
    };
    auto table=[&](){return lua_istable(L,-1) || bad("area row must be a table");};
    auto zone=[&]() {
        const int top=lua_gettop(L);lua_getfield(L,-1,"zone_settings");
        bool valid=lua_isnil(L,-1) || (lua_istable(L,-1) && number("pond_mode",0,2) && number("facing",0,4) &&
            number("tomb_citizens",-1,1) && number("tomb_pets",-1,1) && number("gather_trees",-1,1) && number("gather_shrubs",-1,1));
        lua_settop(L,top);return valid || bad("zone_settings must be a table");
    };
    if(auto workError=areaWorkResultError(L,synchronous?uint64_t(INT64_MAX):std::min(stepBudget,uint32_t(1536)));!workError.empty())return workError;
    if(!boolean("work_unknown"))return error;
    lua_getfield(L,-1,"work_unknown");const bool unknownWork=lua_toboolean(L,-1);lua_pop(L,1);
    if(unknownWork && !synchronous)return "unknown work is allowed only for synchronous operations";
    if(!number("revision",0,INT64_MAX) || !number("list_revision",0,INT64_MAX) ||
        !number("build_phase",0,3) || !number("build_done",0,UINT32_MAX) || !number("build_total",0,UINT32_MAX) ||
        !number("omitted",0,UINT32_MAX) || !number("captured_tick",-1,INT64_MAX) ||
        !number("operation",0,15) || !number("area_id",-1,INT32_MAX) || !number("candidate_kind",0,3) ||
        !number("sort",0,3) || !number("next_cursor",0,UINT32_MAX) ||
        !boolean("sort_descending") || !boolean("truncated") || !text("list_key",64,false) || !text("query",128,false))return error;
    if(value("build_done")>value("build_total"))return "build_done exceeds build_total";
    lua_getfield(L,-1,"pending");const bool pending=lua_toboolean(L,-1);lua_pop(L,1);
    if(pending)return "pending is not valid for area results";
    lua_getfield(L,-1,"operation");const bool echoed=!lua_isnil(L,-1);lua_pop(L,1);
    if(echoed && value("operation")!=int(operation))return "area operation does not match request";
    lua_getfield(L,-1,"retired");const bool retired=!lua_isnil(L,-1);lua_pop(L,1);
    const int op=int(operation);
    if(retired && op!=5 && op!=11 && op!=12)return "retired is only valid on Paint, AssignUnits or SquadUse";
    if(!number("retired_bytes",0,32768))return error;
    if(value("retired_bytes") && (!retired || op!=5))return "retired_bytes is only valid with retired Paint extents";
    if(retired && !array("retired",op==12?2:1,[&](){return lua_type(L,-1)==LUA_TUSERDATA || lua_type(L,-1)==LUA_TLIGHTUSERDATA || bad("retired area element must be native userdata");}))return error;
    if(!array("areas",64,[&]() {
        payload+=4;
        if(!table() || !number("id",0,INT32_MAX,true) || !number("kind",0,1,true) ||
            !number("x",0,32767,true) || !number("y",0,32767,true) || !number("z",0,32767,true) ||
            !number("width",1,256,true) || !number("height",1,256,true) ||
            !number("zone_type",-1,255) || !number("categories",0,0x1ffff) ||
            !number("barrels",0,32767) || !number("bins",0,32767) || !number("wheelbarrows",0,32767) ||
            !number("owner_id",-1,INT32_MAX) || !number("revision",0,INT64_MAX) ||
            !number("location_id",-1,INT32_MAX) || !number("location_site_id",-1,INT32_MAX) || !number("organic",-1,1) || !number("inorganic",-1,1) ||
            !number("tile_count",-1,INT32_MAX) || !number("assigned_count",-1,INT32_MAX) ||
            !boolean("active") || !boolean("links_only") || !boolean("owner_allowed") ||
            !text("name",512) || !text("owner_name",512) || !text("zone_label",512,false) ||
            !text("owner_profession",512,false) || !number("owner_sex",-1,1,false) || !number("location_kind",0,5,false) ||
            !text("location_name",512,false) || !text("religion",512,false) || !zone())return false;
        lua_getfield(L,-1,"extents");const bool shape=lua_istable(L,-1);const size_t cells=shape?lua_rawlen(L,-1):0;lua_pop(L,1);
        if(!shape || cells!=uint64_t(value("width"))*value("height"))return bad("area extents do not match rectangle");
        if(!array("extents",32768,[&](){++payload;return (lua_isinteger(L,-1) && lua_tointeger(L,-1)>=0 && lua_tointeger(L,-1)<=1) || bad("area extent must be 0 or 1");}))return false;
        for(const char* key:{"gives","takes"})if(!array(key,1024,[&](){payload+=4;return (lua_isinteger(L,-1) && lua_tointeger(L,-1)>=0 && lua_tointeger(L,-1)<=INT32_MAX) || bad("area link identity is invalid");}))return false;
        return payload<=224*1024 || bad("area response exceeds bounded payload");
    }))return error;
    if(!array("choices",128,[&](){payload+=4;return table() && number("id",0,INT32_MAX,true) && text("name",512) && text("label",512,false);}))return error;
    if(!array("settings",128,[&](){payload+=7;return table() && text("key",64) && text("label",512) && number("index",-1,INT32_MAX) && number("kind",0,4) && number("state",0,3) && boolean("estimated");}))return error;
    if(!array("locations",128,[&](){payload+=15;return table() && number("id",-1,INT32_MAX,true) && text("name",512) && number("location_kind",0,5) && text("religion",512) && number("guild_profession",-1,511) && number("location_tier",-1,INT32_MAX) && number("site_id",-1,INT32_MAX);}))return error;
    if(!array("candidates",128,[&](){payload+=9;return table() && number("id",-1,INT32_MAX,true) && text("name",512) && text("profession",512) && number("sex",-1,1) && number("mood",0,7) && boolean("grazer") && boolean("assigned") && number("squad_use",-1,15);}))return error;
    if(!array("links",128,[&](){payload+=6;return table() && number("id",0,INT32_MAX,true) && number("kind",0,2,true) && (value("kind")!=1 || bad("area link kind must be Stockpile or Workshop")) && number("direction",1,2,true) && text("name",512);}))return error;
    const auto count=[&](const char* key){lua_getfield(L,-1,key);const size_t n=lua_istable(L,-1)?lua_rawlen(L,-1):0;lua_pop(L,1);return n;};
    const unsigned families=(count("settings")!=0)+(count("locations")!=0)+(count("candidates")!=0)+(count("links")!=0);
    if(families>1 || (count("choices") && (count("areas") || families)) || (families && count("areas")>1))
        return "area response mixes list families";
    if(payload>224*1024)return "area response exceeds bounded payload";
    return {};
}
// All helper envelopes are typed; optional fields may be absent, but may not
// change type. Validate before any permissive DTO defaults are applied.
inline std::string reportResultError(lua_State* L) {
    const int base=lua_gettop(L);
    struct Restore {lua_State* state;int top;~Restore(){lua_settop(state,top);}} restore{L,base};
    std::string error;size_t bytes=0;
    auto bad=[&](const std::string& message){if(error.empty())error=message;return false;};
    auto number=[&](const char* key,lua_Integer low,lua_Integer high) {
        lua_getfield(L,-1,key);const bool valid=lua_isnil(L,-1) ||
            (lua_isinteger(L,-1)&&lua_tointeger(L,-1)>=low&&lua_tointeger(L,-1)<=high);
        lua_pop(L,1);return valid || bad(std::string(key)+" is outside the report contract");
    };
    auto flag=[&](const char* key){lua_getfield(L,-1,key);const bool valid=lua_isnil(L,-1)||lua_type(L,-1)==LUA_TBOOLEAN;lua_pop(L,1);return valid||bad(std::string(key)+" must be a boolean");};
    auto text=[&](const char* key,size_t cap){lua_getfield(L,-1,key);const bool valid=lua_type(L,-1)==LUA_TSTRING&&lua_rawlen(L,-1)<=cap;if(valid)bytes+=lua_rawlen(L,-1);lua_pop(L,1);return valid||bad(std::string(key)+" exceeds the report text contract");};
    auto array=[&](const char* key,size_t cap,const std::function<bool()>& check) {
        const int top=lua_gettop(L);lua_getfield(L,-1,key);
        if(lua_isnil(L,-1)){lua_settop(L,top);return true;}
        if(!lua_istable(L,-1)){lua_settop(L,top);return bad(std::string(key)+" must be an array");}
        const int table=lua_gettop(L);const size_t n=lua_rawlen(L,table);size_t seen=0;bool valid=n<=cap;
        lua_pushnil(L);
        while(valid && lua_next(L,table)!=0){valid=++seen<=cap && lua_isinteger(L,-2) && lua_tointeger(L,-2)>=1 && uint64_t(lua_tointeger(L,-2))<=n;lua_pop(L,1);}
        lua_settop(L,table);
        if(!valid||seen!=n){lua_settop(L,top);return bad(std::string(key)+" must be a bounded dense array");}
        for(size_t i=1;i<=n&&valid;++i){lua_rawgeti(L,table,i);valid=check();lua_pop(L,1);}
        lua_settop(L,top);return valid;
    };
    if(!number("view",0,6)||!number("tab",0,25)||!number("notification_category",-1,36)||!flag("alert_button"))return error;
    lua_getfield(L,-1,"view");const bool textView=lua_tointeger(L,-1)==5;lua_pop(L,1);
    if(!number("total",0,textView?33554432:65536))return error;
    for(const char* key:{"after_id","next_before_id","next_after_id","trimmed_through"})if(!number(key,-1,INT32_MAX))return error;
    for(const char* key:{"announcements_only","from_end","gap"})if(!flag(key))return error;
    lua_getfield(L,-1,"view");const size_t cap=textView?1:lua_tointeger(L,-1)!=0?64:16;lua_pop(L,1);
    if(!array("tab_counts",25,[&](){return (lua_isinteger(L,-1)&&lua_tointeger(L,-1)>=0&&uint64_t(lua_tointeger(L,-1))<=UINT32_MAX)||bad("invalid report tab count");}))return error;
    if(!array("reports",cap,[&](){
        if(!lua_istable(L,-1))return bad("report row must be a table");
        if(!text("category",128)||!text("text",16384)||!number("id",0,INT32_MAX)||!number("year",0,INT32_MAX)||
           !number("year_tick",0,403199)||!number("repeat_count",0,INT32_MAX)||!number("tab",0,25)||
           !number("color",-1,15)||!number("zoom_type",0,4)||!number("zoom_type2",0,4)||!number("speaker_id",-1,INT32_MAX))return false;
        for(const char* key:{"x","y","z","x2","y2","z2"})if(!number(key,INT16_MIN,INT16_MAX))return false;
        for(const char* key:{"continuation","text_complete","position_visible","position2_visible","position_hidden","position2_hidden","bright"})if(!flag(key))return false;
        return true;
    }))return error;
    if(!number("unit_id",-1,INT32_MAX)||!number("unit_category",-1,2)||!number("cursor",0,UINT32_MAX)||
       !number("next_cursor",0,UINT32_MAX)||!number("list_revision",0,INT64_MAX))return error;
    if(!array("missing_ids",64,[&](){return (lua_isinteger(L,-1) && lua_tointeger(L,-1)>=0 && lua_tointeger(L,-1)<=INT32_MAX) || bad("invalid missing report identity");}))return error;
    const size_t reportBytes=bytes;
    if(!array("units",64,[&](){return (lua_istable(L,-1) || bad("report unit row must be a table")) && number("unit_id",0,INT32_MAX) && number("category",0,2) &&
       text("name",512) && text("profession",512) && flag("dead") && number("log_count",0,UINT32_MAX) && text("error",256);}))return error;
    bytes=reportBytes;
    // Category strings are bounded independently; the wire text budget excludes them.
    if(bytes>131072+64*128)return "report payload exceeds text budget";
    return error;
}

inline std::string managementResultError(lua_State* L,df3d::mirror::ManagementAction action,
        df3d::mirror::AreaOperation areaOperation=df3d::mirror::AreaOperation::None,uint32_t areaStepBudget=1536) {
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
    if(action>=A::AreaCatalog && action<=A::AreaCandidates) {
        if(auto error=areaResultError(L,areaOperation,areaStepBudget,synchronousAreaWrite(action,areaOperation) || synchronousAreaRead(action,areaOperation));!error.empty())return error;
    }
    if((action>=A::ReportList && action<=A::ReportInspect) || action==A::PrepareAlertDismissal || action==A::DismissAlert)if(auto error=reportResultError(L);!error.empty())return error;
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
        if(!optionalInteger("build_phase",0,3))return "build_phase must be an integer in 0..3";
        if(!optionalInteger("required",0,65535))return "required must be an integer in 0..65535";
        for(const char* key:{"placed","skipped","chunk_placed"})if(!optionalInteger(key,0,1024))return std::string(key)+" must be an integer in 0..1024";
        if(!optionalInteger("first_building",-1,INT32_MAX))return "first_building must be an integer in -1..INT32_MAX";
        if(!optionalInteger("steps",0,2048))return "steps must be an integer in 0..2048";
        if(!optionalInteger("active_kinds",0,8))return "active_kinds must be an integer in 0..8";
        if(!field("active",LUA_TBOOLEAN,false))return "active must be a boolean when present";
    }
    if((action>=A::CitizenList && action<=A::WorkDetailMode) ||
       (action>=A::WorkDetailCreate && action<=A::CitizenWorkScope)) {
        auto optionalInteger=[&](const char* key,lua_Integer low,lua_Integer high) {
            lua_getfield(L,-1,key);const bool absent=lua_isnil(L,-1);lua_pop(L,1);
            return absent || integer(key,low,high);
        };
        for(const char* key:{"revision","detail_list_revision"})
            if(!optionalInteger(key,0,INT64_MAX))return std::string(key)+" must be an integer in 0..INT64_MAX";
        for(const char* key:{"recalc_done","recalc_total"})
            if(!optionalInteger(key,0,UINT32_MAX))return std::string(key)+" must be an integer in 0..UINT32_MAX";
        lua_getfield(L,-1,"recalc_done");const auto done=lua_tointeger(L,-1);lua_pop(L,1);
        lua_getfield(L,-1,"recalc_total");const auto total=lua_tointeger(L,-1);lua_pop(L,1);
        if(done>total)return "recalc_done exceeds recalc_total";
        if(!optionalInteger("steps",0,INT64_MAX))return "steps must be a nonnegative integer";
        if(!optionalInteger("active_kinds",0,UINT32_MAX))return "active_kinds must be an integer in 0..UINT32_MAX";
        lua_getfield(L,-1,"retired");const bool retired=!lua_isnil(L,-1);lua_pop(L,1);
        if(retired && action!=A::WorkDetailDelete)return "retired is only valid on WorkDetailDelete";
        if(retired && !field("retired",LUA_TTABLE,false))return "retired must be a table";
        for(const char* key:{"citizens","details"}) {
            lua_getfield(L,-1,key);
            if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1);++i) {
                lua_rawgeti(L,-1,i);
                if(!lua_istable(L,-1)){lua_pop(L,2);return "citizen row must be a table";}
                const bool valid=optionalInteger("revision",0,INT64_MAX);lua_pop(L,1);
                if(!valid){lua_pop(L,1);return "revision must be an integer in 0..INT64_MAX";}
            }
            lua_pop(L,1);
        }
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
    if(action==A::Preview) {
        lua_getfield(L,-1,"track_preview");
        const bool track=!lua_isnil(L,-1);
        const bool validTrack=!track || (lua_istable(L,-1) && integer("status",0,5) && field("path",LUA_TTABLE,true));
        lua_pop(L,1);
        if(!validTrack)return "track preview metadata is incomplete";
        // Ordered Track paths have their own typed result. The construction
        // parser validates bounded geometry and request endpoint identity.
        if(!track && (!field("placement_valid",LUA_TBOOLEAN,true) ||
            !integer("required",0,65535) || !field("inputs",LUA_TTABLE,true)))return "preview metadata is incomplete";
    }
    if(action==A::CreatureInspect && (!integer("unit_id",0,INT32_MAX) ||
        !integer("captured_tick",0,INT64_MAX) || !field("complete",LUA_TBOOLEAN,true) ||
        !field("sections",LUA_TTABLE,true)))return "creature metadata is incomplete";
    return {};
}
} // namespace df3d_management
