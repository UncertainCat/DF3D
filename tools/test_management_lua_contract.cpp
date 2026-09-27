// Exercises the real Lua/C++ boundary without starting or attaching to DF.
#include "../bridge/plugin/management_result_contract.h"
#include "../bridge/plugin/lua_fields.h"
#include <iostream>
#include <bit>
#include <stdexcept>
#include <cstdlib>
#include <string>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
static HMODULE library=nullptr;
template<class T> T function(const char* name) {
  auto address=GetProcAddress(library,name);
  // DFHack builds Lua as C++; tolerate its pinned MSVC export decoration.
  static constexpr struct {const char* name;const char* symbol;} aliases[]={
    {"lua_getfield","?lua_getfield@@YAHPEAUlua_State@@HPEBD@Z"},
    {"lua_settop","?lua_settop@@YAXPEAUlua_State@@H@Z"},
    {"lua_type","?lua_type@@YAHPEAUlua_State@@H@Z"},
    {"lua_toboolean","?lua_toboolean@@YAHPEAUlua_State@@H@Z"},
    {"lua_tointegerx","?lua_tointegerx@@YA_JPEAUlua_State@@HPEAH@Z"},
    {"lua_isinteger","?lua_isinteger@@YAHPEAUlua_State@@H@Z"},
    {"luaL_newstate","?luaL_newstate@@YAPEAUlua_State@@XZ"},
    {"luaL_loadstring","?luaL_loadstring@@YAHPEAUlua_State@@PEBD@Z"},
    {"lua_pcallk","?lua_pcallk@@YAHPEAUlua_State@@HHH_JP6AH0H1@Z@Z"},
    {"lua_close","?lua_close@@YAXPEAUlua_State@@@Z"},
    {"lua_gettop","?lua_gettop@@YAHPEAUlua_State@@@Z"},
    {"lua_rawlen","?lua_rawlen@@YA_KPEAUlua_State@@H@Z"},
    {"lua_rawgeti","?lua_rawgeti@@YAHPEAUlua_State@@H_J@Z"},
    {"lua_pushinteger","?lua_pushinteger@@YAXPEAUlua_State@@_J@Z"},
  };
  if(!address)for(const auto& alias:aliases)if(std::string(name)==alias.name)address=GetProcAddress(library,alias.symbol);
  if(!address)throw std::runtime_error(std::string("Lua export missing: ")+name);
  return std::bit_cast<T>(address);
}
extern "C" {
int lua_gettop(lua_State* L) {static auto f=function<decltype(&lua_gettop)>("lua_gettop");return f(L);}
size_t lua_rawlen(lua_State* L,int index) {static auto f=function<decltype(&lua_rawlen)>("lua_rawlen");return f(L,index);}
int lua_rawgeti(lua_State* L,int index,lua_Integer n) {static auto f=function<decltype(&lua_rawgeti)>("lua_rawgeti");return f(L,index,n);}
int lua_getfield(lua_State* L,int index,const char* key) {static auto f=function<decltype(&lua_getfield)>("lua_getfield");return f(L,index,key);}
void lua_settop(lua_State* L,int index) {static auto f=function<decltype(&lua_settop)>("lua_settop");f(L,index);}
int lua_type(lua_State* L,int index) {static auto f=function<decltype(&lua_type)>("lua_type");return f(L,index);}
int lua_toboolean(lua_State* L,int index) {static auto f=function<decltype(&lua_toboolean)>("lua_toboolean");return f(L,index);}
lua_Integer lua_tointegerx(lua_State* L,int index,int* isnum) {static auto f=function<decltype(&lua_tointegerx)>("lua_tointegerx");return f(L,index,isnum);}
int lua_isinteger(lua_State* L,int index) {static auto f=function<decltype(&lua_isinteger)>("lua_isinteger");return f(L,index);}
}
int main(int argc,char** argv) {
  // argv[1] overrides; otherwise the installed DF (DF3D_DF_PATH) supplies hack/lua53.dll.
  const char* dfPath=std::getenv("DF3D_DF_PATH");
  const std::string lua=argc>1?std::string(argv[1]):std::string(dfPath&&*dfPath?dfPath:"C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress")+"/hack/lua53.dll";
  library=LoadLibraryA(lua.c_str());
  if(!library){std::cout<<"QA_INCOMPLETE: installed Lua53 unavailable\n";return 77;}
  auto newState=function<lua_State*(*)()>("luaL_newstate");
  auto load=function<int(*)(lua_State*,const char*)>("luaL_loadstring");
  auto call=function<decltype(&lua_pcallk)>("lua_pcallk");
  auto close=function<decltype(&lua_close)>("lua_close");
  auto top=function<decltype(&lua_gettop)>("lua_gettop");
  if(!newState||!load||!call||!close||!top)return 1;
  auto* L=newState();int result=0;
  try {
    using A=df3d::mirror::ManagementAction;
    auto test=[&](A action,const char* code,bool accepted) {
      lua_settop(L,0);
      if(load(L,code)||call(L,0,1,0,0,nullptr))throw std::runtime_error("Lua fixture parse failed");
      auto error=df3d_management::managementResultError(L,action);
      if(error.empty()!=accepted || top(L)!=1)throw std::runtime_error(std::string("contract fixture: ")+code+" / "+error);
    };
    test(A::Catalog,"return {ok=true,message='ok',catalog={}}",true);
    test(A::Catalog,"return {message='typo',catalog={}}",false);
    test(A::Catalog,"return {ok=1,message='wrong type',catalog={}}",false);
    test(A::Catalog,"return {ok=false,message='not available'}",true);
    test(A::Catalog,"return {ok=true,message=42,catalog={}}",false);
    test(A::Catalog,"return {ok=true,message='ok'}",false);
    test(A::ProductionList,"return {ok=true,pending=true,message='pending'}",true);
    test(A::ProductionList,"return {ok=true,pending='true',message='pending'}",false);
    test(A::Preview,"return {ok=true,message='ok',placement_valid=true,required=1,inputs={}}",true);
    test(A::Preview,"return {ok=true,message='ok',placement_valid=true,required='1',inputs={}}",false);
    test(A::Preview,"return {ok=true,message='ok',placement_valid=true,required=65536,inputs={}}",false);
    test(A::CreatureInspect,"return {ok=true,message='ok',unit_id=2147483000,captured_tick=9007199254740993,complete=true,sections={}}",true);
    if(df3d_management::lua_fields::number(L,"captured_tick")!=9007199254740993LL)throw std::runtime_error("integer identity rounded");
    test(A::CreatureInspect,"return {ok=true,message='ok',unit_id=1.5,captured_tick=1,complete=true,sections={}}",false);
    test(A::CreatureInspect,"return {ok=true,message='ok',unit_id=-1,captured_tick=1,complete=true,sections={}}",false);
    test(A::CreatureInspect,"return {ok=true,message='ok',unit_id=1,captured_tick=1,complete=true}",false);
    for(auto action:{A::WorkOrderList,A::WorkOrderCandidates,A::WorkOrderCatalog}) {
      test(action,"return {ok=true,message='ok',list_revision=9223372036854775807,build_phase=3}",true);
      if(df3d_management::lua_fields::number(L,"list_revision")!=INT64_MAX)
        throw std::runtime_error("63-bit revision rounded");
      for(const auto* code:{
          "return {ok=true,message='bad',list_revision=1.5}",
          "return {ok=true,message='bad',list_revision=1.0}",
          "return {ok=true,message='bad',list_revision='1'}",
          "return {ok=true,message='bad',list_revision=-1}",
          "return {ok=true,message='bad',list_revision=9223372036854775808.0}",
          "return {ok=true,message='bad',build_phase=4}",
          "return {ok=true,message='bad',build_phase=-1}",
          "return {ok=true,message='bad',build_phase=1.5}"}) test(action,code,false);
      test(action,"return {ok=true,message='building',build_phase=1,active=true}",true);
    }
    test(A::WorkOrderInspect,"return {ok=true,message='ok',orders={{conditions={{traits={'rc:CLASS',''}}}}}}",true);
    test(A::WorkOrderInspect,"return {ok=true,message='ok',orders={{conditions={{traits={}}}}}}",true);
    for(const auto* value:{"false","{}","1","42"}) {
      const auto code=std::string("return {ok=true,message='ok',orders={{conditions={{traits={")+value+"}}}}}}";
      test(A::WorkOrderInspect,code.c_str(),false);
      if(df3d_management::managementResultError(L,A::WorkOrderInspect)!="condition trait must be a string")
        throw std::runtime_error("wrong trait refusal");
    }
    for(const auto& fixture:std::initializer_list<std::pair<const char*,const char*>>{
        {"orders={false}","order must be a table"},
        {"orders={{conditions={false}}}","condition must be a table"},
        {"orders={{conditions={{traits=false}}}}","condition traits must be a table"},
        {"active_kinds=32","active_kinds must be an integer in 0..31"},
        {"active_kinds=-1","active_kinds must be an integer in 0..31"},
        {"steps=2049","steps must be an integer in 0..2048"},
        {"steps=-1","steps must be an integer in 0..2048"}}) {
      const auto code=std::string("return {ok=true,message='ok',")+fixture.first+"}";
      test(A::WorkOrderInspect,code.c_str(),false);
      if(df3d_management::managementResultError(L,A::WorkOrderInspect)!=fixture.second)
        throw std::runtime_error("wrong contract refusal");
    }
    test(A::WorkOrderInspect,"return {ok=true,message='ok',active_kinds=31,steps=2048}",true);
    test(A::WorkOrderInspect,"return {ok=true,message='ok',active_kinds=0,steps=0}",true);
    // Transport preserves all 64 bits even though published revisions deliberately
    // mask the high bit. Use integer push, the bridge's Lua::Push integral path.
    auto pushInteger=function<decltype(&lua_pushinteger)>("lua_pushinteger");
    for(uint64_t bits:{uint64_t(1)<<63,(uint64_t(1)<<63)+123,UINT64_MAX}) {
      lua_settop(L,0);
      if(load(L,"local value=...; return {value=value}"))throw std::runtime_error("roundtrip parse");
      pushInteger(L,std::bit_cast<int64_t>(bits));
      if(call(L,1,1,0,0,nullptr))throw std::runtime_error("roundtrip call");
      if(uint64_t(df3d_management::lua_fields::number(L,"value"))!=bits || top(L)!=1)
        throw std::runtime_error("unsigned integer transport lost bits");
    }
    std::cout<<"MANAGEMENT_LUA_CONTRACT_PASS\n";
  } catch(const std::exception& e){std::cerr<<e.what()<<"\n";result=1;}
  close(L);FreeLibrary(library);return result;
}
