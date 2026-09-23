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
  };
  if(!address)for(const auto& alias:aliases)if(std::string(name)==alias.name)address=GetProcAddress(library,alias.symbol);
  if(!address)throw std::runtime_error(std::string("Lua export missing: ")+name);
  return std::bit_cast<T>(address);
}
extern "C" {
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
    std::cout<<"MANAGEMENT_LUA_CONTRACT_PASS\n";
  } catch(const std::exception& e){std::cerr<<e.what()<<"\n";result=1;}
  close(L);FreeLibrary(library);return result;
}
