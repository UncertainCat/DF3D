#pragma once
#include "lua_fields.h"
#include "appearance.h"
#include "df/unit.h"
#include "mirror_generated.h"
#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

namespace df3d_management {

// --- shared appearance recipe encoding ---
inline uint16_t internName(std::vector<std::string>& names, const std::string& value) {
  auto it = std::find(names.begin(), names.end(), value);
  if (it != names.end()) return uint16_t(it - names.begin());
  names.push_back(value);
  return uint16_t(names.size() - 1);
}
inline void appendAppearanceLayer(std::vector<std::string>& pages, std::vector<std::string>& palettes,
                                  std::vector<df3d::mirror::AppearanceLayer>& layers,
                                  const df3d_appearance::Layer& layer) {
  const auto page = internName(pages, df3d_appearance::pageToken(layer.page));
  const auto palette = layer.palette ? internName(palettes, df3d_appearance::paletteInstallPath(layer.palette))
                                     : uint16_t(65535);
  layers.emplace_back(page, layer.tileX, layer.tileY, layer.cellsX, layer.cellsY, palette, layer.row,
                      layer.keyRow, layer.offX, layer.offY);
}
inline flatbuffers::Offset<df3d::mirror::SelectionAppearance> buildSelectionAppearance(
    flatbuffers::FlatBufferBuilder& b, const std::vector<std::string>& pages,
    const std::vector<std::string>& palettes, const std::vector<df3d::mirror::AppearanceLayer>& layers) {
  if (layers.empty()) return {};
  return df3d::mirror::CreateSelectionAppearance(b, b.CreateVectorOfStrings(pages),
                                                 b.CreateVectorOfStrings(palettes),
                                                 b.CreateVectorOfStructs(layers));
}

// Original-asset recipe only. No native cached texture or screen state survives
// collection. Ordinary map layers also supply DF sheet icons; PORTRAIT sets
// are distinct head portraits and are not used by the Residents roster.
struct ResidentAppearanceRecipe {
  std::vector<std::string> pages, palettes;
  std::vector<df3d::mirror::AppearanceLayer> layers;
  void collect(df::unit* unit) {
    *this = {};
    df3d_appearance::Result source;
    if (!df3d_appearance::resolve(unit, source) || source.layers.size() > 256) return;
    for (const auto& layer : source.layers) appendAppearanceLayer(pages, palettes, layers, layer);
  }
  flatbuffers::Offset<df3d::mirror::SelectionAppearance> build(flatbuffers::FlatBufferBuilder& b) const {
    return buildSelectionAppearance(b, pages, palettes, layers);
  }
};

// --- production ---
struct ProductionRequirement { std::string description; int32_t quantity=0; int16_t itemType=-1; };
struct ProductionRecipe { std::string key,name; std::vector<ProductionRequirement> requirements; };
struct ProductionJob {
  int32_t id=-1,workerId=-1,completionTimer=-1;
  int16_t jobType=-1;
  std::string name,workerName,status;
  bool repeat=false,suspended=false,editable=false;
  uint16_t attachedItems=0;
  std::vector<ProductionRequirement> requirements;
};
struct ProductionBuilding {
  int32_t id=-1,x=0,y=0,z=0;
  std::string name,kind;
  int16_t buildStage=0,maxStage=0;
  uint16_t queueSize=0;
};
struct FarmCrop { int32_t id=-1; std::string name; uint8_t seasons=0; uint32_t seeds=0; };
struct ProductionState {
  std::vector<ProductionBuilding> buildings;
  std::vector<ProductionRecipe> recipes;
  std::vector<ProductionJob> jobs;
  std::vector<FarmCrop> crops;
  std::vector<int32_t> seasonalCrops;
  uint32_t nextCursor=0;
  int8_t currentSeason=-1;
  int32_t selectedBuilding=-1,createdJob=-1;
  std::string detail;
};

// --- work orders ---
struct WorkOrderChoice { int32_t id=-1; std::string name; };
struct WorkOrderCondition {
  uint8_t kind=0; uint16_t index=0;
  std::string description;
  bool editable=false,satisfied=false;
  int8_t compare=-1,dependency=-1;
  int16_t itemType=-1;
  int32_t threshold=-1,targetOrder=-1;
};
struct WorkOrderInfo {
  int32_t id=-1,finishedYear=-1,finishedTick=-1,workshopId=-1,maxWorkshops=0;
  uint64_t revision=0;
  std::string name,reason;
  int16_t total=0,remaining=0;
  int8_t frequency=0;
  bool validated=false,active=false,editable=false;
  std::vector<int32_t> generatedJobs;
  std::vector<WorkOrderCondition> conditions;
};
struct ManagerRole { int32_t unitId=-1; std::string name,position,job; std::vector<int32_t> offices; };
struct WorkOrderState {
  std::vector<WorkOrderInfo> orders;
  std::vector<ProductionRecipe> recipes;
  std::vector<WorkOrderChoice> choices;
  std::vector<ManagerRole> managers;
  uint32_t nextCursor=0;
  std::string detail;
};

// --- citizens ---
struct CitizenRole {
  std::string name;
  int32_t requiredOffice = 0;
};
struct CitizenWorkDetail { int32_t index=-1,icon=-1; std::string name; };
struct CitizenInfo {
  bool onlyAssignedJobs=false, socialActivity=false;
  std::vector<CitizenWorkDetail> assignedDetails;
  ResidentAppearanceRecipe sheetIcon;
  int32_t professionColor = -1, professionId = -1, jobType = -1;
  int32_t id = -1, age = -1, stress = 0, x = 0, y = 0, z = 0;
  std::string name, profession, job, reason;
  bool hasStress = false, canFocus = false, eligible = false;
  std::vector<int16_t> labors;
  std::vector<std::string> laborNames;
  std::vector<CitizenRole> roles;
  std::vector<int32_t> offices;
};
struct WorkDetailInfo {
  int32_t index = -1;
  uint64_t revision = 0;
  std::string name, reason;
  uint8_t mode = 0;
  bool noModify = false, cannotBeEverybody = false, editable = false,
       modeEditable = false;
  std::vector<int16_t> labors;
  std::vector<std::string> laborNames;
  std::vector<int32_t> assignedUnits;
};
struct CitizenState {
  std::vector<CitizenInfo> citizens;
  std::vector<WorkDetailInfo> details;
  uint32_t nextCursor = 0;
  int32_t selectedUnit = -1, selectedDetail = -1;
  bool externalController = false;
  std::string detail;
};

// --- reports ---
struct ReportInfo {
 int32_t id=0,year=0,yearTick=0,repeatCount=0,x=-1,y=-1,z=-1,x2=-1,y2=-1,z2=-1;
 std::string category,text;
 bool continuation=false,textComplete=true,positionVisible=false,position2Visible=false;
};
struct ReportState {std::vector<ReportInfo> reports;int32_t nextBeforeId=-1;bool announcementsOnly=true;std::string detail;};

// --- agreements ---
struct AgreementDetail {
 int32_t id=0,siteId=-1,year=0,yearTick=0,applicantParty=-1,governmentParty=-1,tier=-1,deityId=-1;
 int16_t kind=-1,locationType=-1,profession=-1,deityType=-1;
 std::string description;
};
struct AgreementParty {int32_t id=0;std::vector<int32_t> entityIds,histfigIds;std::string name;};
struct AgreementInfo {int32_t id=0;uint8_t status=0;bool notApproved=false,concluded=false,continuing=false,complete=true;std::vector<AgreementDetail> details;std::vector<AgreementParty> parties;std::string summary,reason;};
struct AgreementState {std::vector<AgreementInfo> agreements;int32_t nextBeforeId=-1;bool pendingOnly=false;std::string detail;};

// --- trade ---
struct TradeDepot { int32_t id=-1,x=0,y=0,z=0; uint64_t revision=0; bool requested=false,anyone=false,accessible=false,ready=false; std::string broker; uint32_t hauling=0,goods=0; };
struct TradeCaravan { int32_t id=0; std::string name,state; int32_t daysRemaining=0; };
struct TradeGood { int32_t id=-1; std::string description; uint32_t quantity=1; bool selected=false,selectable=false; std::string reason; };
struct TradeState { std::vector<TradeDepot> depots; std::vector<TradeCaravan> caravans; std::vector<TradeGood> goods; uint32_t nextCursor=0; int32_t selectedDepot=-1; std::string detail; };

// --- creature inspection ---
namespace creature_data {
namespace m=df3d::mirror;
struct Fact {std::string key,text;int64_t number=0;bool hasNumber=false;};
struct Record {int32_t id=-1,relatedId=-1;std::string name;std::vector<Fact> facts;};
struct Section {uint8_t kind=0;bool available=false,truncated=false;std::string reason;std::vector<Record> records;};
struct State {int32_t id=-1,age=-1,sex=-1,x=-1,y=-1,z=-1;uint64_t tick=0;bool complete=false;std::string name,species,profession,job;std::vector<Section> sections;
 std::vector<std::string> pages,palettes;std::vector<m::AppearanceLayer> layers;};
inline void read(lua_State* L,State& out) {
 using namespace lua_fields;
 out={};out.id=int32_t(number(L,"unit_id",-1));out.age=int32_t(number(L,"age",-1));out.sex=int32_t(number(L,"sex",-1));
 out.x=int32_t(number(L,"x",-1));out.y=int32_t(number(L,"y",-1));out.z=int32_t(number(L,"z",-1));out.tick=number(L,"captured_tick");
 out.name=text(L,"name");out.species=text(L,"species");out.profession=text(L,"profession");out.job=text(L,"job");out.complete=boolean(L,"complete");
 auto rows=[&](const char* key,size_t max,auto fn){lua_getfield(L,-1,key);if(lua_istable(L,-1)){const auto count=lua_rawlen(L,-1);if(count>max)out.complete=false;for(size_t i=1;i<=std::min<size_t>(count,max);++i){lua_rawgeti(L,-1,i);fn();lua_pop(L,1);}}lua_pop(L,1);};
 rows("sections",25,[&]{Section s;s.kind=uint8_t(number(L,"kind"));s.available=boolean(L,"available");s.truncated=boolean(L,"truncated");s.reason=text(L,"reason");
  rows("records",256,[&]{Record r;r.id=int32_t(number(L,"id",-1));r.relatedId=int32_t(number(L,"related_id",-1));r.name=text(L,"name");
   rows("facts",12,[&]{r.facts.push_back({text(L,"key"),text(L,"text"),number(L,"number"),boolean(L,"has_number")});});s.records.push_back(std::move(r));});out.sections.push_back(std::move(s));});
 if(out.id>=0) {
  df3d_appearance::Result portrait;
  if(df3d_appearance::resolvePortrait(df::unit::find(out.id),portrait)) {
   for(const auto& layer:portrait.layers) {
    if(out.layers.size()>=256){out.complete=false;break;}
    appendAppearanceLayer(out.pages,out.palettes,out.layers,layer);
   }
  }
 }
}
inline flatbuffers::Offset<m::CreatureState> build(flatbuffers::FlatBufferBuilder& b,const State& c) {
 if(c.id<0)return {};
 std::vector<flatbuffers::Offset<m::CreatureSection>> sections;
 for(const auto& s:c.sections){std::vector<flatbuffers::Offset<m::CreatureRecord>> rows;
  for(const auto& r:s.records){std::vector<flatbuffers::Offset<m::CreatureFact>> facts;
   for(const auto& f:r.facts)facts.push_back(m::CreateCreatureFact(b,b.CreateString(f.key),b.CreateString(f.text),f.number,f.hasNumber));
   rows.push_back(m::CreateCreatureRecord(b,r.id,r.relatedId,b.CreateString(r.name),b.CreateVector(facts)));}
  sections.push_back(m::CreateCreatureSection(b,m::CreatureSectionKind(s.kind),s.available,s.truncated,b.CreateString(s.reason),b.CreateVector(rows)));}
 m::TilePos p(c.x,c.y,c.z);
 return m::CreateCreatureState(b,c.id,c.tick,b.CreateString(c.name),b.CreateString(c.species),b.CreateString(c.profession),b.CreateString(c.job),c.age,c.sex,&p,c.complete,b.CreateVector(sections),buildSelectionAppearance(b,c.pages,c.palettes,c.layers));
}
}  // namespace creature_data

}  // namespace df3d_management
