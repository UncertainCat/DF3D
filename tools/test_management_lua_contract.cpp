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
    {"luaL_openlibs","?luaL_openlibs@@YAXPEAUlua_State@@@Z"},
    {"luaL_loadstring","?luaL_loadstring@@YAHPEAUlua_State@@PEBD@Z"},
    {"lua_pcallk","?lua_pcallk@@YAHPEAUlua_State@@HHH_JP6AH0H1@Z@Z"},
    {"lua_close","?lua_close@@YAXPEAUlua_State@@@Z"},
    {"lua_gettop","?lua_gettop@@YAHPEAUlua_State@@@Z"},
    {"lua_rawlen","?lua_rawlen@@YA_KPEAUlua_State@@H@Z"},
    {"lua_rawgeti","?lua_rawgeti@@YAHPEAUlua_State@@H_J@Z"},
    {"lua_pushinteger","?lua_pushinteger@@YAXPEAUlua_State@@_J@Z"},
    {"lua_pushnil","?lua_pushnil@@YAXPEAUlua_State@@@Z"},
    {"lua_next","?lua_next@@YAHPEAUlua_State@@H@Z"},
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
void lua_pushnil(lua_State* L) {static auto f=function<decltype(&lua_pushnil)>("lua_pushnil");f(L);}
int lua_next(lua_State* L,int index) {static auto f=function<decltype(&lua_next)>("lua_next");return f(L,index);}
}
int main(int argc,char** argv) {
  // argv[1] overrides; otherwise the installed DF (DF3D_DF_PATH) supplies hack/lua53.dll.
  const char* dfPath=std::getenv("DF3D_DF_PATH");
  const std::string lua=argc>1?std::string(argv[1]):std::string(dfPath&&*dfPath?dfPath:"C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress")+"/hack/lua53.dll";
  library=LoadLibraryA(lua.c_str());
  if(!library){std::cout<<"QA_INCOMPLETE: installed Lua53 unavailable\n";return 77;}
  auto newState=function<lua_State*(*)()>("luaL_newstate");
  auto openLibraries=function<void(*)(lua_State*)>("luaL_openlibs");
  auto load=function<int(*)(lua_State*,const char*)>("luaL_loadstring");
  auto call=function<decltype(&lua_pcallk)>("lua_pcallk");
  auto close=function<decltype(&lua_close)>("lua_close");
  auto top=function<decltype(&lua_gettop)>("lua_gettop");
  if(!newState||!openLibraries||!load||!call||!close||!top)return 1;
  auto* L=newState();int result=0;
  openLibraries(L);
  try {
    using A=df3d::mirror::ManagementAction;
    using O=df3d::mirror::AreaOperation;
    size_t checked=0;
    auto test=[&](A action,const char* code,bool accepted,O operation=O::None,uint32_t budget=1536) {
      lua_settop(L,0);
      if(load(L,code)||call(L,0,1,0,0,nullptr))throw std::runtime_error(std::string("Lua fixture failed: ")+code);
      auto error=df3d_management::managementResultError(L,action,operation,budget);
      if(error.empty()!=accepted || top(L)!=1)throw std::runtime_error(std::string("contract fixture: ")+code+" / "+error);
      ++checked;
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
    test(A::Preview,"return {ok=true,message='',track_preview={status=0,path={{x=1,y=1,z=1},{x=2,y=1,z=1}}}}",true);
    test(A::Preview,"return {ok=true,message='',track_preview={status=4,path={}}}",true);
    test(A::Preview,"return {ok=true,message='',track_preview={status=6,path={}}}",false);
    test(A::Preview,"return {ok=true,message='',track_preview={status='0',path={}}}",false);
    test(A::Preview,"return {ok=true,message='',track_preview={status=0}}",false);
    test(A::Preview,"return {ok=true,message='',track_preview={}}",false);
    test(A::Preview,"return {ok=true,message='',track_preview=true}",false);
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

    // Construction envelopes are checked even for Rejected and pending results.
    for(auto action:{A::Catalog,A::Preview,A::Place,A::Inspect,A::Remove,
                     A::InspectAtTile,A::RemoveConstruction,A::ConstructionMaterials}) {
      for(const auto& field:std::initializer_list<std::pair<const char*,int64_t>>{
          {"list_revision",INT64_MAX},{"build_phase",3},{"required",65535},{"placed",1024},
          {"skipped",1024},{"chunk_placed",1024},{"first_building",INT32_MAX},
          {"steps",2048},{"active_kinds",8}}) {
        const std::string prefix="return {ok=false,message='',"+std::string(field.first)+"=";
        const auto low=std::string(field.first)=="first_building" ? -1 : 0;
        for(auto value:{int64_t(low),field.second})
          test(action,(prefix+std::to_string(value)+"}").c_str(),true);
        const auto expected=std::string(field.first)+" must be an integer in "+
          (std::string(field.first)=="list_revision" ? "0..INT64_MAX" :
           std::string(field.first)=="first_building" ? "-1..INT32_MAX" : "0.."+std::to_string(field.second));
        for(const auto& value:{std::to_string(low-1),field.second==INT64_MAX ?
            std::string("9223372036854775808.0") : std::to_string(field.second+1),
            std::string("1.0"),std::string("1.5"),std::string("'1'")}) {
          test(action,(prefix+value+"}").c_str(),false);
          if(df3d_management::managementResultError(L,action)!=expected)
            throw std::runtime_error("construction exact refusal: "+expected);
        }
      }
      test(action,"return {ok=false,message='',active=false}",true);
      test(action,"return {ok=false,message='',active=0}",false);
      if(df3d_management::managementResultError(L,action)!="active must be a boolean when present")
        throw std::runtime_error("construction active refusal");
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
    // Citizen envelopes use signed-safe revisions and bounded progress on every route.
    for(auto action:{A::CitizenList,A::CitizenInspect,A::WorkDetailList,A::WorkDetailInspect,
                     A::WorkDetailMembership,A::WorkDetailMode,A::WorkDetailCreate,
                     A::WorkDetailDelete,A::WorkDetailEdit,A::CitizenWorkScope}) {
      for(const auto* field:{"revision","detail_list_revision","recalc_done","recalc_total"}) {
        const bool progress=std::string(field).starts_with("recalc_");
        const std::string limit=progress?"UINT32_MAX":"INT64_MAX";
        const std::string prefix="return {ok=false,message='Citizens inspected',recalc_total=4294967295,"+std::string(field)+"=";
        for(const auto* value:{"0",progress?"4294967295":"9223372036854775807"})
          test(action,(prefix+value+"}").c_str(),true);
        for(const auto* value:{"-1","1.0","1.5","'1'",progress?"4294967296":"9223372036854775808.0"}) {
          test(action,(prefix+value+"}").c_str(),false);
          if(df3d_management::managementResultError(L,action)!=std::string(field)+" must be an integer in 0.."+limit)
            throw std::runtime_error("citizen exact integer refusal");
        }
      }
      test(action,"return {ok=false,message='',recalc_done=1,recalc_total=0}",false);
      if(df3d_management::managementResultError(L,action)!="recalc_done exceeds recalc_total")
        throw std::runtime_error("citizen exact progress refusal");
      for(const auto* rows:{"citizens","details"}) {
        const auto code=std::string("return {ok=false,message='',")+rows+"={{revision=1.5}}}";
        test(action,code.c_str(),false);
        if(df3d_management::managementResultError(L,action)!="revision must be an integer in 0..INT64_MAX")
          throw std::runtime_error("citizen exact row revision refusal");
      }
    }
    // Builders can consume a whole global slice, while inline replies remain
    // capped at 1536. Invalid values must not be coerced or silently clamped.
    for(uint32_t budget:{0u,1u,1536u,2048u}) {
      for(const std::string& steps:std::initializer_list<std::string>{"0",std::to_string(budget),std::to_string(budget+1),"-1","1.0","'1'"}) {
        lua_settop(L,0);
        const auto code="return {steps="+steps+",active_kinds=224}";
        if(load(L,code.c_str()) || call(L,0,1,0,0,nullptr))throw std::runtime_error("builder fixture parse");
        const bool accepted=steps=="0" || steps==std::to_string(budget);
        if(df3d_management::areaWorkResultError(L,budget).empty()!=accepted || top(L)!=1)
          throw std::runtime_error("builder work budget contract");
        ++checked;
      }
    }
    for(const auto* mask:{"0","32","64","128","224","1","225","-1","224.0","'224'"}) {
      lua_settop(L,0);const auto code=std::string("return {steps=0,active_kinds=")+mask+"}";
      if(load(L,code.c_str()) || call(L,0,1,0,0,nullptr))throw std::runtime_error("builder mask parse");
      const bool accepted=std::string(mask)=="0" || std::string(mask)=="32" || std::string(mask)=="64" ||
          std::string(mask)=="128" || std::string(mask)=="224";
      if(df3d_management::areaWorkResultError(L,2048).empty()!=accepted || top(L)!=1)
        throw std::runtime_error("builder active-mask contract");
      ++checked;
    }
    const std::string envelope="ok=false,message='',steps=0,active_kinds=0,";
    for(auto action:{A::AreaCatalog,A::AreaInspectAtTile,A::AreaInspect,A::AreaCreate,A::AreaUpdate,A::AreaDelete,A::AreaLink,A::AreaCandidates}) {
      test(action,("return {"+envelope+"}").c_str(),true);
      for(const char* value:{"revision=1.5","list_revision=1.0","revision=-1","list_revision=9223372036854775808.0",
          "build_phase=4","build_done=2,build_total=1","active_kinds=1","active_kinds=225",
          "steps='1'","operation=16","area_id=-2","candidate_kind=4","sort=4","captured_tick=-2","pending=true",
          "choices=false","settings={false}","retired={}","retired_bytes=1","retired_bytes=32769","retired_bytes=1.0"})
        test(action,("return {"+envelope+value+"}").c_str(),false);
      test(action,("return {"+envelope+"revision=9223372036854775807,list_revision=9223372036854775807,active_kinds=224,steps=1536}").c_str(),true);
      if(df3d_management::lua_fields::number(L,"revision")!=INT64_MAX)throw std::runtime_error("area revision rounded");
      test(action,("return {"+envelope+"steps=1537}").c_str(),action==A::AreaDelete || action==A::AreaUpdate || action==A::AreaCreate || action==A::AreaInspect);
    }
    test(A::AreaInspect,("return {"+envelope+"steps=513}").c_str(),true,O::None,512);
    test(A::AreaInspect,("return {"+envelope+"steps=512}").c_str(),true,O::None,512);
    test(A::AreaDelete,("return {"+envelope+"steps=9000,work_unknown=true}").c_str(),true,O::None,0);
    for(auto operation:{O::None,O::ZoneSettings,O::Paint})
      test(A::AreaUpdate,("return {"+envelope+"steps=9000,work_unknown=true}").c_str(),true,operation,0);
    for(auto operation:{O::None,O::Paint})
      test(A::AreaCreate,("return {"+envelope+"steps=9000,work_unknown=true}").c_str(),true,operation,0);
    // Presets adopt synchronous writes. Large honest counts and explicit
    // unknown native work must not spend or enlarge an ordinary read budget.
    test(A::AreaUpdate,("return {"+envelope+"steps=9000,work_unknown=true}").c_str(),true,O::Preset,0);
    test(A::AreaUpdate,("return {"+envelope+"steps=9223372036854775807,work_unknown=false}").c_str(),true,O::Preset,0);
    test(A::AreaUpdate,("return {"+envelope+"steps=-1,work_unknown=true}").c_str(),false,O::Preset,0);
    test(A::AreaUpdate,("return {"+envelope+"steps=1.0,work_unknown=true}").c_str(),false,O::Preset,0);
    test(A::AreaUpdate,("return {"+envelope+"work_unknown='true'}").c_str(),false,O::Preset,0);
    test(A::AreaInspect,("return {"+envelope+"work_unknown=true}").c_str(),true);
    // Fresh settings summaries may scan all allowed settings in one safe point.
    test(A::AreaInspect,("return {"+envelope+"steps=9000,work_unknown=false}").c_str(),true,O::SettingsPage,0);
    test(A::AreaInspect,("return {"+envelope+"steps=-1}").c_str(),false,O::SettingsPage,0);
    test(A::AreaUpdate,("return {"+envelope+"steps=9000}").c_str(),true,O::SettingsSet,0);
    test(A::AreaUpdate,("return {"+envelope+"steps=-1}").c_str(),false,O::SettingsSet,0);
    test(A::AreaUpdate,("return {"+envelope+"steps=9000,work_unknown=true}").c_str(),true,O::LocationSet,0);
    test(A::AreaInspect,("return {"+envelope+"work_unknown=true}").c_str(),false,O::LocationSet);
    test(A::AreaUpdate,("return {"+envelope+"steps=9000,work_unknown=true}").c_str(),true,O::LocationCreate,0);
    test(A::AreaUpdate,("return {"+envelope+"operation=4}").c_str(),false,O::Paint);
    for(auto operation:{O::Paint,O::AssignUnits,O::SquadUse}) {
      test(A::AreaUpdate,("return {"+envelope+"retired={}}").c_str(),true,operation);
      test(A::AreaUpdate,("return {"+envelope+"retired={1}}").c_str(),false,operation);
    }
    const std::string info="id=1,kind=0,x=0,y=0,z=0,width=1,height=1,name='',owner_name='',extents={1}";
    test(A::AreaInspect,("return {"+envelope+"areas={{"+info+"}}}").c_str(),true);
    for(const char* value:{"revision=1.0","kind=2","owner_name=false","zone_settings={pond_mode=3}",
        "organic=2","tile_count=-2","extents={1.0}","extents={1,1}","gives={1.0}",
        "location_kind=6","owner_sex=2","owner_sex=-2","owner_profession=false","owner_profession=string.rep('x',513)"})
      test(A::AreaInspect,("return {"+envelope+"areas={{"+info+","+value+"}}}").c_str(),false);
    for(const char* value:{"choices={{id=1}}","settings={{key='',label=1}}","locations={{id=1,name=''}}",
        "candidates={{id=1,name='',profession='',sex=2}}","links={{id=1,kind=1,direction=1,name=''}}",
        "links={{id=1,kind=2,direction=0,name=''}}","choices={[2]={id=1,name=''}}",
        "choices={x={id=1,name=''}}","choices={[1]={id=1,name=''},[129]={id=2,name=''}}"})
      test(A::AreaInspect,("return {"+envelope+value+"}").c_str(),false);
    for(const char* value:{"choices={{id=1,name='',label=''}}","settings={{key='',index=-1,label='',kind=4,state=3,estimated=true}}",
        "locations={{id=-1,name='',location_kind=5,religion=''}}","candidates={{id=-1,name='',profession='',sex=-1,mood=7,grazer=true,assigned=false,squad_use=15}}",
        "links={{id=1,kind=2,direction=2,name=''}}"})
      test(A::AreaInspect,("return {"+envelope+value+"}").c_str(),true);
    test(A::AreaInspect,("return {"+envelope+"areas={{"+info+"}},choices={{id=1,name=''}}}").c_str(),false);
    test(A::AreaInspect,("return {"+envelope+"settings={{key='',label=''}},locations={{id=1,name='',religion=''}}}").c_str(),false);
    for(int count:{128,129}) {
      const auto code="local rows={};for i=1,"+std::to_string(count)+" do rows[i]={id=i,name='',label=''} end;return {"+envelope+"choices=rows}";
      test(A::AreaCandidates,code.c_str(),count==128);
    }
    for(int count:{64,65}) {
      const auto code="local rows={};for i=1,"+std::to_string(count)+" do rows[i]={"+info+"} end;return {"+envelope+"areas=rows}";
      test(A::AreaInspectAtTile,code.c_str(),count==64);
    }
    test(A::AreaInspect,("local e={};for i=1,32769 do e[i]=1 end;return {"+envelope+"areas={{"+info+",width=256,height=128,extents=e}}}").c_str(),false);
    for(int count:{16,17,64,65}) {
      const auto code="local rows={};for i=1,"+std::to_string(count)+" do rows[i]={id=i,category='Fixture',text='Fixture'}end;return {ok=true,message='',view=1,reports=rows}";
      test(A::ReportList,code.c_str(),count<=64);
    }
    test(A::ReportList,"return {ok=true,message='',view=1,tab_counts={[2]=1}}",false);
    test(A::ReportList,"return {ok=true,message='',reports={{id=1,category='Fixture',text='Fixture',color=16}}}",false);
    test(A::ReportList,"return {ok=true,message='',reports={{id=1,category='Fixture',text='Fixture',bright=1}}}",false);
    test(A::ReportList,"return {ok=true,message='',view=2,units={1}}",false);
    test(A::ReportList,"return {ok=true,message='',view=2,list_revision=1.0}",false);
    for(int count:{64,65}) {
      const auto code="local u={};for i=1,"+std::to_string(count)+" do u[i]={unit_id=i,category=1,name='',profession='',error='',dead=false,log_count=1}end;return {ok=true,message='',view=2,list_revision=9223372036854775807,units=u}";
      test(A::ReportList,code.c_str(),count==64);
    }
    test(A::ReportInspect,"return {ok=true,message='',view=4,missing_ids={41,41}}",true);
    test(A::ReportInspect,"return {ok=true,message='',view=4,missing_ids={-1}}",false);
    test(A::ReportInspect,"return {ok=true,message='',view=4,missing_ids={[2]=1}}",false);
    test(A::ReportList,"return {ok=true,message='',view=6,notification_category=20,alert_button=false,total=303,list_revision=1}",true);
    test(A::ReportList,"return {ok=true,message='',view=7}",false);
    test(A::ReportList,"return {ok=true,message='',view=6,notification_category=37}",false);
    test(A::ReportList,"return {ok=true,message='',view=6,notification_category='20'}",false);
    test(A::ReportList,"return {ok=true,message='',view=6,alert_button=1}",false);
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
    std::cout<<checked<<" management Lua contract fixtures passed\nMANAGEMENT_LUA_CONTRACT_PASS\n";
  } catch(const std::exception& e){std::cerr<<e.what()<<"\n";result=1;}
  close(L);FreeLibrary(library);return result;
}
