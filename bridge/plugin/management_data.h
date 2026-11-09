#pragma once
#include "lua_fields.h"
#include "appearance.h"
#include "location_staff_native.h"
#include "df/unit.h"
#include "mirror_generated.h"
#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>
#include <optional>

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
  void collect(df::unit* unit,bool unitSelector=false) {
    *this = {};
    df3d_appearance::Result source;
    if (!(unitSelector?df3d_appearance::resolveUnitSelector(unit,source):df3d_appearance::resolve(unit,source)) || source.layers.size() > 256) return;
    for (const auto& layer : source.layers) appendAppearanceLayer(pages, palettes, layers, layer);
  }
  flatbuffers::Offset<df3d::mirror::SelectionAppearance> build(flatbuffers::FlatBufferBuilder& b) const {
    return buildSelectionAppearance(b, pages, palettes, layers);
  }
};

// --- production ---
struct ProductionRequirement { std::string description; int32_t quantity=0; int16_t itemType=-1; };
struct ProductionAvailability { bool available=false; std::string objection; };
struct ProductionRecipe { std::string key,name; std::vector<ProductionRequirement> requirements; std::optional<ProductionAvailability> availability; };
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
struct NativeFarmCrop { int32_t id=-1; std::string name; bool seedsAvailable=false,currentSeasonWarning=false; std::string rawId; };
struct FarmSnapshot {
  std::string customName,headerName;
  bool removing=false,removalSuspended=false,removalHasWorker=false;
  int32_t currentFertilization=0,maxFertilization=0,pendingFertilization=0;
  bool seasonalFertilization=false;
  int32_t buildingId=-1;
  uint64_t revision=0;
  int8_t selectedSeason=-1,currentSeason=-1;
  std::vector<int32_t> seasonalCrops;
  std::vector<NativeFarmCrop> choices;
};
struct ItemInspectionAppearance { std::string materialToken,subtypeRaw,colorToken;int32_t stack=1;uint8_t flags=0;int8_t instrumentFamily=-1,instrumentPlaced=-1; };
struct BuildingContentsItem {
  int32_t id=-1,role=-1;std::string name;
  bool forbid=false,dump=false,melt=false,hidden=false,canDump=false,canMelt=false,inJob=false,inBuilding=false;
  int32_t itemType=-1;std::string materialToken,subtypeRaw;
  std::optional<ItemInspectionAppearance> appearance;
};
struct BuildingContentsPage {
  int32_t buildingId=-1;uint64_t revision=0;
  uint32_t cursor=0,nextCursor=0,total=0;
  bool completed=false,removing=false;
  std::vector<BuildingContentsItem> rows;
};
struct BuildingItemReceipt { int32_t itemId=-1;df3d::mirror::FarmOperation operation=df3d::mirror::FarmOperation::Crop;int8_t value=-1; };
struct ItemBuildingHolder { int32_t id=-1,type=-1;std::string name; };
struct BuildingItemSnapshot {
  int32_t buildingId=-1;uint64_t revision=0;
  bool completed=false,removing=false;
  BuildingContentsItem item;
  std::string weight,description;
  std::optional<ItemBuildingHolder> holder;
};
struct ItemPosition { int32_t id=-1,x=0,y=0,z=0; };
struct ItemCarrier { int32_t kind=0,id=-1,itemType=-1;std::string name;std::optional<ItemInspectionAppearance> appearance; };
struct ItemOwner { int32_t id=-1;std::string name; };
struct ItemAmmunitionAssignment {int8_t kind=0;int32_t squadId=-1;std::string caption;};
struct IndependentItemSnapshot {
    std::optional<ItemAmmunitionAssignment> ammunitionAssignment;
    std::optional<ItemOwner> owner;
  int32_t id=-1,itemType=-1,stockpileCategories=-1;uint64_t revision=0;
  std::string name,materialToken,subtypeRaw,weight,description;
  bool forbid=false,dump=false,melt=false,hidden=false,canDump=false,canMelt=false,inJob=false,inBuilding=false;
  std::optional<ItemBuildingHolder> holder,stockpile;
  std::optional<ItemCarrier> carrier;
  std::optional<ItemInspectionAppearance> appearance;
};
struct IndependentItemState {
  std::optional<IndependentItemSnapshot> snapshot;
  std::optional<BuildingItemReceipt> edit;
  df3d::mirror::FarmEditOutcome outcome=df3d::mirror::FarmEditOutcome::None;
};
struct BuildingHeaderSnapshot {
  int32_t id=-1,type=-1,stage=-1,maxStage=-1;uint64_t revision=0;
  std::string customName,nativeName,headerName;
  bool removing=false,suspended=false,hasWorker=false;
};
struct BuildingHeaderState {
  std::optional<BuildingHeaderSnapshot> snapshot;
  df3d::mirror::FarmEditOutcome outcome=df3d::mirror::FarmEditOutcome::None;
  df3d::mirror::FarmOperation operation=df3d::mirror::FarmOperation::Crop;
};
struct WorkshopAssignedWorker {
  int32_t id=-1;std::string caption;
  bool specializationVisible=false,canSpecialize=false,specialized=false;
};
struct WorkshopWorkersState {
  std::optional<WorkshopAssignedWorker> assigned;
  df3d::mirror::FarmOperation operation=df3d::mirror::FarmOperation::Crop;
  int32_t buildingId=-1,unitId=-1;
  uint64_t profileRevision=0,revision=0;
  uint32_t cursor=0,nextCursor=0,total=0;
  std::vector<int32_t> permittedWorkers;
  std::vector<df3d_area::LocationStaffCandidate> rows;
  df3d::mirror::FarmEditOutcome outcome=df3d::mirror::FarmEditOutcome::None;
};
struct WorkshopOrdersState {
  int32_t buildingId=-1,generalOrderLimit=0;
  uint64_t revision=0;bool managerAvailable=false;
  std::vector<int32_t> orderIds;int8_t delta=0;int16_t value=-1;
  df3d::mirror::FarmEditOutcome outcome=df3d::mirror::FarmEditOutcome::None;
};
struct ProductionState {
  std::optional<WorkshopOrdersState> workshopOrders;
  std::optional<WorkshopWorkersState> workshopWorkers;
  std::optional<BuildingHeaderState> buildingHeader;
  std::optional<IndependentItemState> independentItem;
  std::optional<ItemPosition> itemPosition;
  std::optional<BuildingItemSnapshot> item;
  std::optional<BuildingItemReceipt> contentsEdit;
  std::optional<BuildingContentsPage> contents;
  df3d::mirror::FarmEditOutcome farmEditOutcome=df3d::mirror::FarmEditOutcome::None;
  std::optional<FarmSnapshot> farm;
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
  int64_t revision=0;
  int8_t detailMember=-1;
  int16_t detailSkill=-1,detailSkillRating=-1;
  uint8_t portraitState=0;
  std::string detailSkillName,rowError;
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
  int32_t icon=-2;
  std::string rowError;
};
struct CitizenState {
  bool outcomeUnknown=false;
  std::vector<CitizenInfo> citizens;
  std::vector<WorkDetailInfo> details;
  uint32_t nextCursor = 0;
  int32_t selectedUnit = -1, selectedDetail = -1;
  bool externalController = false;
  std::string detail;
  uint32_t recalcDone=0,recalcTotal=0;
  int64_t detailListRevision=0;
  std::string recalcError;
};

// --- reports ---
struct ReportInfo {
 int32_t id=0,year=0,yearTick=0,repeatCount=0,x=-1,y=-1,z=-1,x2=-1,y2=-1,z2=-1;
 std::string category,text;
 bool continuation=false,textComplete=true,positionVisible=false,position2Visible=false;
 uint8_t tab=0,zoomType=0,zoomType2=0; int16_t color=-1; bool bright=false;
 bool positionHidden=false,position2Hidden=false; int32_t speakerId=-1;
};
struct ReportUnitInfo { int32_t unitId=-1; int8_t category=-1; std::string profession,name; bool dead=false; uint32_t logCount=0; std::string error; };
struct ReportState {std::vector<ReportInfo> reports;int32_t nextBeforeId=-1;bool announcementsOnly=true;std::string detail;
 uint8_t view=0,tab=0;int32_t afterId=-1;bool fromEnd=false;
 std::vector<uint32_t> tabCounts;uint32_t total=0;int32_t nextAfterId=-1,trimmedThrough=-1;bool gap=false;
 int32_t unitId=-1; int8_t unitCategory=-1; uint32_t cursor=0,nextCursor=0; uint64_t listRevision=0; std::vector<ReportUnitInfo> units; std::vector<int32_t> missingIds;int16_t notificationCategory=-1;bool alertButton=false;
};

// --- agreements ---
struct AgreementDetail {
 int32_t id=0,siteId=-1,year=0,yearTick=0,applicantParty=-1,governmentParty=-1,tier=-1,deityId=-1;
 int16_t kind=-1,locationType=-1,profession=-1,deityType=-1;
 std::string description;
};
struct AgreementParty {int32_t id=0;std::vector<int32_t> entityIds,histfigIds;std::string name;};
struct AgreementInfo {int32_t id=0;uint8_t status=0;bool notApproved=false,concluded=false,continuing=false,complete=true;std::vector<AgreementDetail> details;std::vector<AgreementParty> parties;std::string summary,reason;};
struct ContinuingAgreementRow {
 int32_t agreementId=-1,subjectId=-1,entityId=-1,entityType=-1,tier=-1,profession=-1,year=0,yearTick=0;
 std::string heading,applicant,date;
};
struct ContinuingAgreementDetails {int32_t requiredValue=-1,matchingLocations=0,locationId=-1,locationValue=0,locationTier=-1;bool siteAvailable=false,tierMet=false;std::string locationName;};
struct AgreementState {std::vector<AgreementInfo> agreements;int32_t nextBeforeId=-1;bool pendingOnly=false;std::string detail;bool tracker=false;std::vector<ContinuingAgreementRow> trackerRows;std::optional<ContinuingAgreementDetails> trackerDetails;};

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
enum class CreatureSkillsPageKind : uint8_t { Labor, Combat, Social, Other, Knowledge };
struct CreatureSkillRow { int32_t id=-1,knowledgeType=-1;uint32_t knowledgeBits=0;int32_t rating=0,rustValue=0;std::string caption,subtitle;int16_t captionColor=-1; };
struct CreatureSkillsPage { CreatureSkillsPageKind kind=CreatureSkillsPageKind::Labor;std::vector<CreatureSkillRow> rows; };
struct State {int32_t id=-1,age=-1,sex=-1,x=-1,y=-1,z=-1;uint64_t tick=0;bool complete=false;std::string name,species,profession,job;std::vector<Section> sections;std::vector<std::vector<std::string>> healthPages;std::vector<CreatureSkillsPage> skillsPages;
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
 // The Lua-reported id may be stale by the time of this readback; the
 // resolver dereferences the unit, so an absent unit simply has no portrait.
 if(auto* unit=out.id>=0 ? df::unit::find(out.id) : nullptr) {
  df3d_appearance::Result portrait;
  if(df3d_appearance::resolvePortrait(unit,portrait)) {
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
 std::vector<flatbuffers::Offset<m::CreatureHealthPage>> healthPages;
 for(size_t i=0;i<c.healthPages.size();++i)
  healthPages.push_back(m::CreateCreatureHealthPage(b,m::CreatureHealthPageKind(i),b.CreateVectorOfStrings(c.healthPages[i])));
 m::TilePos p(c.x,c.y,c.z);
 std::vector<flatbuffers::Offset<m::CreatureSkillsPage>> skillsPages;
 for(const auto& page:c.skillsPages){
  std::vector<flatbuffers::Offset<m::CreatureSkillRow>> rows;
  for(const auto& row:page.rows)rows.push_back(m::CreateCreatureSkillRow(b,row.id,row.knowledgeType,row.knowledgeBits,row.rating,row.rustValue,b.CreateString(row.caption),b.CreateString(row.subtitle),row.captionColor));
  skillsPages.push_back(m::CreateCreatureSkillsPage(b,m::CreatureSkillsPageKind(page.kind),b.CreateVector(rows)));
 }
 return m::CreateCreatureState(b,c.id,c.tick,b.CreateString(c.name),b.CreateString(c.species),b.CreateString(c.profession),b.CreateString(c.job),c.age,c.sex,&p,c.complete,b.CreateVector(sections),buildSelectionAppearance(b,c.pages,c.palettes,c.layers),healthPages.empty()?0:b.CreateVector(healthPages),skillsPages.empty()?0:b.CreateVector(skillsPages));
}
}  // namespace creature_data

}  // namespace df3d_management
