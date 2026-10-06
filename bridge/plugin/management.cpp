#include "management.h"
#include "construction_track_route.h"
#include "construction_material_native.h"
#include "paint_water_native.h"
#include "location_catalog_native.h"
#include "location_details_native.h"
#include "location_catalog_page.h"
#include "location_staff_page.h"
#include "location_value_native.h"
#include <set>

#include <algorithm>
#include <chrono>
#include <type_traits>
#include <array>
#include <deque>
#include <string_view>
#include <map>

#include "Core.h"
#include "TileTypes.h"
#include "modules/Buildings.h"
#include "df/world.h"
#include "MiscUtils.h"
#include "modules/Units.h"
#include "modules/Maps.h"
#include "modules/Materials.h"
#include "df/inorganic_raw.h"
#include "df/material.h"
#include "df/plant_raw.h"
#include "df/creature_raw.h"
#include "df/abstract_building.h"
#include "df/abstract_building_contents.h"
#include "df/abstract_building_inn_tavernst.h"
#include "df/abstract_building_templest.h"
#include "df/abstract_building_libraryst.h"
#include "df/abstract_building_guildhallst.h"
#include "df/abstract_building_hospitalst.h"
#include "df/historical_entity.h"
#include "df/historical_figure.h"
#include "df/entity_site_link.h"
#include "df/world_site.h"
#include "df/building_stockpilest.h"
#include "df/building_civzonest.h"
#include "df/building_squad_infost.h"
#include "df/squad_barracks_infost.h"
#include "df/squad.h"
#include "df/unit.h"
#include "df/building_cagest.h"
#include "df/general_ref_building_civzone_assignedst.h"
#include "df/furniture_type.h"
#include "df/map_block.h"
#include "df/activity_event.h"
#include "df/manager_order.h"
#include "df/work_detail.h"
#include "df/manager_order_condition_item.h"
#include "df/manager_order_condition_order.h"
#include "LuaTools.h"
#include "management_data.h"
#include "lua_fields.h"
#include "management_util.h"
#include "management_helpers.h"
#include "management_result_contract.h"
#include "retry_backoff.h"
#include "builder_schedule.h"
#include "construction_effects.h"
#include "area_geometry.h"
#include "room_mutation_native.h"
// Same Windows prelude as df3d.cpp. The shared-memory transport (named
// kernel objects) has no POSIX path yet; say so instead of failing on HANDLE.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifdef _WIN32
#include <windows.h>
#else
#error "df3d management channel: shared memory transport is Windows-only"
#endif
#include "client_mailbox.h"
namespace df3d_management {
namespace m = df3d::mirror;
namespace sh = df3d::shm;
using namespace DFHack;
namespace {
HANDLE mapping = nullptr;
sh::RegionHeader* region = nullptr;
// Region creation retries at most once per kStartRetryUpdates updates
// (600 updates: a few seconds at DF's frame rate), warned once.
constexpr uint32_t kStartRetryUpdates = 600;
df3d_retry_backoff::Backoff startBackoff;
bool warnedStartFailure = false;
// Once-per-map-load log throttles for dropped requests.
bool warnedMalformedRequest = false, warnedMailboxUnavailable = false;
uint64_t rejectedRequests = 0;
// Citizen rows whose unit id no longer resolves (a stale Lua-reported id).
uint64_t staleUnitsSkipped = 0;
// publish() falls back to a fixed minimal Rejected state when the built
// response fails validation; the fallback itself must not recurse.
bool publishingFallback = false;
std::unique_ptr<sh::ClientMailbox> reply;
uint64_t epoch = 0, revision = 0, client = 0, seq = 0;
df3d_area::RoomUndoReceipt roomUndo;
// Lua scanners need producer-wide identity: separate clients can both send seq 1.
uint64_t executionSerial = 0;
ManagementHelpers helpers;
std::chrono::steady_clock::time_point requestStarted;
// Borrowed native pointers are retained for the entire DLL lifetime, including reloads.
std::array<void*,4096> workOrderHolding{};
size_t workOrderHoldingCount=0;
std::array<void*,256> workDetailHolding{};
size_t workDetailHoldingCount=0;
std::array<void*,1024> areaHolding{};
size_t areaHoldingCount=0,areaHoldingBytes=0;
void* areaPaintRetired=nullptr;
std::array<void*,2> areaSquadRetired{};
void* areaUnitRetired=nullptr;
bool areaPaintCommitted=false;
bool citizenRecalcPending=false;
uint64_t citizenHelperGeneration=0;
uint32_t citizenRecalcDone=0,citizenRecalcTotal=0;
bool citizenAction(m::ManagementAction a) {
  return (a>=m::ManagementAction::CitizenList && a<=m::ManagementAction::WorkDetailMode) ||
      (a>=m::ManagementAction::WorkDetailCreate && a<=m::ManagementAction::CitizenWorkScope);
}
bool areaAction(m::ManagementAction a) {
  return a>=m::ManagementAction::AreaCatalog && a<=m::ManagementAction::AreaCandidates;
}
constexpr uint32_t kWorkOrderStepBudget=2048;
// Global job-kind bits. Extend the reserved entries when those Lua builders land.
struct BuilderEntry { m::ManagementAction action; uint32_t domainMask; bool enabled; };
constexpr std::array<BuilderEntry,df3d_builder::kBuilderKindCount> builderTable{{
  {m::ManagementAction::WorkOrderList,0x7,true}, // 0 candidates (and filters)
  {m::ManagementAction::WorkOrderList,0x7,true}, // 1 task catalog (and filters)
  {m::ManagementAction::WorkOrderList,0x7,true}, // 2 item-condition estimates
  {m::ManagementAction::Catalog,0x8,true},     // 3 construction materials
  {m::ManagementAction::CitizenList,0x10,true}, // 4 citizens recalculation
  {m::ManagementAction::AreaInspect,0xe0,true}, // 5 areas settings labels
  {m::ManagementAction::AreaInspect,0xe0,true}, // 6 areas per-pile summary
  {m::ManagementAction::AreaInspect,0xe0,true}, // 7 areas candidates/locations
  {m::ManagementAction::Catalog,1u<<8,false}, // 8 production add-task tree
  {m::ManagementAction::Catalog,1u<<9,false}, // 9 production materials
  {m::ManagementAction::Catalog,1u<<10,false}, // 10 production workers
  {m::ManagementAction::Catalog,1u<<11,false}, // 11 production crops/seeds
  {m::ManagementAction::Catalog,1u<<12,false}, // 12 reports tab lists
  {m::ManagementAction::Catalog,1u<<13,false}, // 13 reports unit list
  {m::ManagementAction::Catalog,1u<<14,false}, // 14 reports unit log
  {m::ManagementAction::Catalog,1u<<15,false}, // 15 agreements history
  {m::ManagementAction::Catalog,1u<<16,false}, // 16 stocks index
  {m::ManagementAction::Catalog,1u<<17,false}, // 17 nobles candidate roster
}};
uint32_t builderActive=0, builderStart=0, remainingSteps=kWorkOrderStepBudget;
uint64_t builderSteps=0,builderLastUs=0,builderMaxUs=0;
uint64_t synchronousWriteSteps=0,synchronousWritesWithUnknownWork=0;
struct WorkOrderInput { uint16_t index=0; std::string description; int16_t matType=-1; int32_t matIndex=-1; bool editable=false; };
struct WorkOrderMaterial { int16_t matType=-1; int32_t matIndex=-1; std::string name; };
struct WorkOrderTrait { std::string key,name; };
struct WorkOrderItemType { int16_t itemType=-1,itemSubtype=-1; std::string name; };
struct WorkOrderGroup { int16_t type=-1,subtype=-1; int32_t custom=-1; std::string name; uint32_t count=0; };
struct WorkOrderTask { std::string key,name; int16_t jobType=-1; std::string reaction; int16_t itemType=-1,itemSubtype=-1,matType=-1; int32_t matIndex=-1; };
struct BridgeWorkOrderCondition : WorkOrderCondition {
  int16_t itemSubtype=-1,matType=-1; int32_t matIndex=-1;
  std::vector<std::string> traits; uint8_t satisfaction=0; bool estimated=false; int32_t estimateCount=-1;
};
struct BridgeWorkOrderInfo : WorkOrderInfo {
  int32_t position=-1; uint8_t detailKind=0; int32_t sizeRaw=-1,encrustFlags=0;
  int16_t matType=-1; int32_t matIndex=-1; uint32_t materialCategory=0;
  std::vector<WorkOrderInput> inputs;
  std::vector<BridgeWorkOrderCondition> conditions;
};
struct BridgeWorkOrderState : WorkOrderState {
  std::vector<BridgeWorkOrderInfo> orders;
  std::vector<WorkOrderMaterial> materials;
  std::vector<WorkOrderTrait> traits;
  std::vector<WorkOrderItemType> types;
  std::vector<WorkOrderGroup> groups;
  std::vector<WorkOrderTask> tasks;
  uint32_t total=0; int64_t listRevision=0; uint8_t buildPhase=0; uint32_t buildDone=0,buildTotal=0;
};
ProductionState production;
BridgeWorkOrderState workOrders;
CitizenState citizens;
ReportState reports;
creature_data::State creature;
AgreementState agreements;
TradeState trade;
struct ActionTiming { uint64_t count=0,last=0,max=0; };
std::array<ActionTiming,size_t(m::ManagementAction::MAX)+1> actionTimings{};
bool mutated = false;
bool terrainConstructed = false, terrainHint = false;
int32_t hintX = 0, hintY = 0, hintZ = 0;
std::deque<std::array<int32_t,3>> areaHints;
m::ManagementStatus status = m::ManagementStatus::Idle;
m::ManagementAction action = m::ManagementAction::Catalog;
std::string message;
std::vector<uint8_t> request;
struct ConstructionFilter {
  int16_t index=-1,item_type=-1,item_subtype=-1;
  std::string caption,requirement; int32_t quantity=-1;
};
struct ConstructionItemAppearance { std::string material_token,subtype_raw,color_token;uint32_t stack=1;uint8_t flags=0; };
struct ConstructionMaterialCandidate {
  int32_t id=-1; std::string name; uint32_t distance=0;
  std::optional<ConstructionItemAppearance> appearance;
};
struct ConstructionMaterial {
  int16_t item_type=-1,item_subtype=-1,mat_type=-1; int32_t mat_index=-1;
  std::string name,caption; uint32_t count=0;
  std::optional<std::vector<ConstructionMaterialCandidate>> candidates;
  int32_t individual_id=-1;
  std::string last_name;
};
struct ConstructionFootprint {
  uint8_t direction=0; uint16_t width=0,height=0; int16_t center_x=-1,center_y=-1;
};
struct PressureCreatureExample { int32_t size=0,race_id=-1;std::string name; };
struct ConstructionState {
  std::string building_key; int16_t filter=-1;
  std::vector<ConstructionFilter> filters; std::vector<ConstructionMaterial> materials;
  uint32_t total=0,build_done=0,build_total=0,placed=0,skipped=0;
  int64_t list_revision=0; uint8_t build_phase=0; bool estimated=false;
  int32_t first_building=-1; std::vector<uint8_t> valid_mask,pieces;
  ConstructionFootprint footprint; bool hasFootprint=false;
  std::vector<PressureCreatureExample> pressure_creatures;
  bool has_track=false; m::ConnectedTrackStatus track_status=m::ConnectedTrackStatus::UnverifiedTerrain;
  std::vector<m::TilePos> track_path;
  m::ConstructionOutcome outcome=m::ConstructionOutcome::None;
  uint32_t updated=0;int32_t failed_index=-1;
} construction;
struct Def {
  std::string key,name,reason,family,subtype_key,custom_code,native_name;
  uint16_t w=1,h=1,max_width=0,max_height=0,max_depth=0;
  uint8_t area_mode=0,orientations=0; bool supported=false;
  std::vector<ConstructionFilter> filters;
  std::vector<ConstructionFootprint> footprints;
};
struct BuilderTiming { uint32_t stepsLast=0,stepsMax=0; uint64_t usLast=0,usMax=0; };
std::array<BuilderTiming,builderTable.size()> builderTiming{};
uint32_t constructionCacheEntries=0,constructionCacheIds=0;

struct Input {
  int32_t id;
  std::string description;
  uint32_t quantity;
};
std::vector<Def> catalog;
std::vector<Input> inputs;
struct NativeAreaZone {
  uint8_t pondMode=0,facing=0;
  int8_t tombCitizens=-1,tombPets=-1,gatherTrees=-1,gatherShrubs=-1;
};
struct NativeArea {
  int32_t id=-1,x=0,y=0,z=0,owner=-1;
  int kind=0,zone=-1,w=0,h=0,barrels=0,bins=0,wheelbarrows=0;
  uint32_t categories=0;
  bool active=false,linksOnly=false,ownerAllowed=false;
  std::string name,ownerName;
  std::string ownerProfession;
  uint8_t locationKind=0;
  int8_t ownerSex=-1;
  std::vector<uint8_t> extents;
  std::vector<int32_t> gives,takes;
  int64_t revision=0;
  std::string zoneLabel,locationName,religion;
  int32_t locationId=-1,tileCount=-1,assignedCount=-1,locationSiteId=-1;
  int8_t organic=-1,inorganic=-1;
  NativeAreaZone zoneSettings;
};
std::vector<NativeArea> areas;
struct NativeAreaChoice { int32_t id=-1; std::string name,label; };
std::vector<NativeAreaChoice> areaChoices;
struct NativeAreaSetting { std::string key,label; int32_t index=-1; uint8_t kind=0,state=0; bool estimated=false; };
struct NativeAreaLocation { int32_t id=-1; std::string name,religion; uint8_t kind=0; int16_t guildProfession=-1; int32_t locationTier=-1; int32_t siteId=-1; };
struct NativeAreaCandidate { int32_t id=-1; std::string name,profession; int8_t sex=-1,squadUse=-1; uint8_t mood=0; bool grazer=false,assigned=false; };
struct NativeAreaLink { int32_t id=-1; uint8_t kind=0,direction=0; std::string name; };
struct NativeAreaPage {
  m::LocationEntryOutcome locationEntryOutcome=m::LocationEntryOutcome::None;
  m::LocationEditOutcome locationEditOutcome=m::LocationEditOutcome::None;
  std::optional<df3d_area::LocationDetailsCore> locationDetails;
  std::optional<df3d_area::LocationStaffCandidatePage> staffCandidates;
  std::optional<df3d_area::LocationCatalogPage<df3d_area::ReligiousPractice>> religions;
  std::optional<df3d_area::LocationCatalogPage<df3d_area::GuildWorkers>> guilds;
  uint32_t locationCursor=0;
  m::AreaOperation operation=m::AreaOperation::None;
  int32_t id=-1;
  std::string listKey,query;
  uint8_t candidateKind=0,sort=0,buildPhase=0;
  bool sortDescending=false;
  int64_t listRevision=0,capturedTick=-1;
  uint32_t buildDone=0,buildTotal=0,omitted=0;
  uint64_t interactionId=0,undoToken=0;
  m::AreaRoomOutcome roomOutcome=m::AreaRoomOutcome::None;
  uint32_t roomsCreated=0,roomsInUse=0,roomsUnenclosed=0,roomsRemoved=0;
  uint32_t roomsDormitories=0;
  uint64_t countGeneration=0;
  int32_t paintedCount=-1,previewCount=-1;
  std::vector<NativeAreaSetting> settings;
  std::vector<NativeAreaLocation> locations;
  std::vector<NativeAreaCandidate> candidates;
  std::vector<NativeAreaLink> links;
} areaPage;
uint32_t areaCursor=0;
bool areaTruncated=false;
uint32_t cursor = 0;
uint16_t required = 0, jobs = 0;
int32_t building = -1;
int16_t stage = -1, maxStage = -1;
bool valid = false, removing = false;
void clearResult() {
  construction = {};
  production = {};
  workOrders = {};
  citizens = {};
  reports = {};
  creature = {};
  agreements = {};
  trade = {};
  catalog.clear();
  inputs.clear();
  areas.clear();areaChoices.clear();areaCursor=0;areaTruncated=false;
  areaPage={};
  cursor = required = jobs = 0;
  building = stage = maxStage = -1;
  valid = removing = terrainConstructed = false;
}
void publish() {
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<m::BuildingDefinition>> ds;
  auto filters=[&](const std::vector<ConstructionFilter>& values) {
    std::vector<flatbuffers::Offset<m::ConstructionFilter>> rows;
    for(const auto& v:values)rows.push_back(m::CreateConstructionFilter(b,v.index,v.item_type,v.item_subtype,b.CreateString(v.caption),b.CreateString(v.requirement),v.quantity));
    return b.CreateVector(rows);
  };
  auto footprint=[&](const ConstructionFootprint& v) {
    return m::CreateConstructionFootprint(b,v.direction,v.width,v.height,v.center_x,v.center_y);
  };
  for(const auto& d:catalog) {
    std::vector<flatbuffers::Offset<m::ConstructionFootprint>> fps;
    for(const auto& f:d.footprints)fps.push_back(footprint(f));
    ds.push_back(m::CreateBuildingDefinition(b,b.CreateString(d.key),b.CreateString(d.name),d.w,d.h,d.supported,b.CreateString(d.reason),
      b.CreateString(d.family),b.CreateString(d.subtype_key),b.CreateString(d.custom_code),b.CreateString(d.native_name),
      d.area_mode,d.orientations,d.max_width,d.max_height,d.max_depth,filters(d.filters),b.CreateVector(fps)));
  }
  std::vector<flatbuffers::Offset<m::ConstructionMaterial>> materials;
  for(const auto& v:construction.materials) {
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<m::ConstructionMaterialCandidate>>> candidates;
    if(v.candidates) { std::vector<flatbuffers::Offset<m::ConstructionMaterialCandidate>> rows;
      for(const auto& item:*v.candidates) {
        flatbuffers::Offset<m::ConstructionItemAppearance> appearance;
        if(item.appearance) { const auto& a=*item.appearance;
          appearance=m::CreateConstructionItemAppearance(b,b.CreateString(a.material_token),b.CreateString(a.subtype_raw),b.CreateString(a.color_token),a.stack,a.flags); }
        rows.push_back(m::CreateConstructionMaterialCandidate(b,item.id,b.CreateString(item.name),item.distance,appearance)); }
      candidates=b.CreateVector(rows); }
    materials.push_back(m::CreateConstructionMaterial(b,v.item_type,v.item_subtype,v.mat_type,v.mat_index,b.CreateString(v.name),b.CreateString(v.caption),v.count,candidates,v.individual_id,b.CreateString(v.last_name)));
  }
  std::vector<flatbuffers::Offset<m::PressureCreatureExample>> pressureCreatures;
  for(const auto& v:construction.pressure_creatures)pressureCreatures.push_back(m::CreatePressureCreatureExample(b,v.size,v.race_id,b.CreateString(v.name)));
  auto trackPreview=construction.has_track ? m::CreateConnectedTrackPreview(b,construction.track_status,b.CreateVectorOfStructs(construction.track_path)) : flatbuffers::Offset<m::ConnectedTrackPreview>{};
  auto constructionResult=m::CreateConstructionState(b,b.CreateString(construction.building_key),construction.filter,filters(construction.filters),b.CreateVector(materials),
    construction.total,construction.list_revision,construction.estimated,construction.build_phase,construction.build_done,construction.build_total,
    construction.placed,construction.skipped,construction.first_building,b.CreateVector(construction.valid_mask),b.CreateVector(construction.pieces),
    construction.hasFootprint ? footprint(construction.footprint) : flatbuffers::Offset<m::ConstructionFootprint>{},b.CreateVector(pressureCreatures),trackPreview,construction.outcome,construction.updated,construction.failed_index);
  std::vector<flatbuffers::Offset<m::ConstructionInput>> is;
  for (auto& i : inputs)
    is.push_back(m::CreateConstructionInput(b, i.id, b.CreateString(i.description), i.quantity));
  std::vector<flatbuffers::Offset<m::AreaInfo>> as;
  for(const auto& a:areas) {
    m::TilePos pos(a.x,a.y,a.z);
    const auto& z=a.zoneSettings;
    const auto zone=m::CreateAreaZoneSettings(b,z.pondMode,z.facing,z.tombCitizens,z.tombPets,z.gatherTrees,z.gatherShrubs);
    as.push_back(m::CreateAreaInfo(b,a.id,m::AreaKind(a.kind),b.CreateString(a.name),&pos,a.w,a.h,
      b.CreateVector(a.extents),a.zone,a.categories,a.barrels,a.bins,a.wheelbarrows,a.linksOnly,
      a.active,a.owner,b.CreateString(a.ownerName),a.ownerAllowed,b.CreateVector(a.gives),b.CreateVector(a.takes),
      uint64_t(a.revision),b.CreateString(a.zoneLabel),a.locationId,b.CreateString(a.locationName),b.CreateString(a.religion),
      a.organic,a.inorganic,zone,a.tileCount,a.assignedCount,a.locationKind,b.CreateString(a.ownerProfession),a.ownerSex,a.locationSiteId));
  }
  std::vector<flatbuffers::Offset<m::AreaChoice>> ac;
  for(const auto& c:areaChoices) ac.push_back(m::CreateAreaChoice(b,c.id,b.CreateString(c.name),b.CreateString(c.label)));
  std::vector<flatbuffers::Offset<m::AreaSettingRow>> settings;
  std::vector<flatbuffers::Offset<m::AreaLocationRow>> locations;
  std::vector<flatbuffers::Offset<m::AreaCandidateRow>> candidates;
  std::vector<flatbuffers::Offset<m::AreaLinkRow>> links;
  for(const auto& v:areaPage.settings)settings.push_back(m::CreateAreaSettingRow(b,b.CreateString(v.key),v.index,b.CreateString(v.label),v.kind,v.state,v.estimated));
  for(const auto& v:areaPage.locations)locations.push_back(m::CreateAreaLocationRow(b,v.id,b.CreateString(v.name),v.kind,b.CreateString(v.religion),v.guildProfession,v.locationTier,v.siteId));
  for(const auto& v:areaPage.candidates)candidates.push_back(m::CreateAreaCandidateRow(b,v.id,b.CreateString(v.name),b.CreateString(v.profession),v.sex,v.mood,v.grazer,v.assigned,v.squadUse));
  for(const auto& v:areaPage.links)links.push_back(m::CreateAreaLinkRow(b,v.id,m::AreaKind(v.kind),v.direction,b.CreateString(v.name)));
  flatbuffers::Offset<m::LocationCatalog> locationCatalog;
  if(areaPage.religions || areaPage.guilds) {
    std::vector<flatbuffers::Offset<m::LocationReligion>> religions;
    std::vector<flatbuffers::Offset<m::LocationGuild>> guilds;
    if(areaPage.religions)for(const auto& row:areaPage.religions->rows) {
      std::vector<flatbuffers::Offset<m::LocationDeity>> deities;
      for(const auto& d:row.deities)deities.push_back(m::CreateLocationDeity(b,d.id,b.CreateString(d.name),b.CreateVector(d.spheres)));
      religions.push_back(m::CreateLocationReligion(b,uint8_t(row.kind),row.id,b.CreateString(row.name),row.worshippers,row.hasTemple,b.CreateVector(deities)));
    }
    if(areaPage.guilds)for(const auto& row:areaPage.guilds->rows)
      guilds.push_back(m::CreateLocationGuild(b,row.profession,row.workers,row.hasMeetingPlace,row.guildId,b.CreateString(row.guildName),row.members));
    const auto revision=areaPage.religions?areaPage.religions->revision:areaPage.guilds->revision;
    const auto total=areaPage.religions?areaPage.religions->total:areaPage.guilds->total;
    const auto next=areaPage.religions?areaPage.religions->nextCursor:areaPage.guilds->nextCursor;
    locationCatalog=m::CreateLocationCatalog(b,areaPage.religions?2:4,revision,areaPage.locationCursor,total,next,b.CreateVector(religions),b.CreateVector(guilds));
  }
  flatbuffers::Offset<m::LocationDetails> locationDetails;
  if(areaPage.locationDetails) {
    const auto& d=*areaPage.locationDetails;
    std::vector<flatbuffers::Offset<m::LocationSupplyQuantity>> supplies;
    for(size_t i=0;i<d.supplies.size();++i)supplies.push_back(m::CreateLocationSupplyQuantity(b,uint8_t(i),d.supplies[i].stored,d.supplies[i].desired));
    const auto& f=d.facilities;
    const auto facilities=m::CreateLocationFacilities(b,f.chests,f.beds,f.tables,f.tractionBenches,f.bookcases,f.chairs,f.rooms,f.rentedRooms);
    flatbuffers::Offset<m::LocationStaffSnapshot> staff;
    if(d.staff) {
      std::vector<flatbuffers::Offset<m::LocationStaffRow>> rows;
      for(const auto& r:d.staff->rows) {
        flatbuffers::Offset<m::LocationStaffNames> names;
        if(r.names)names=m::CreateLocationStaffNames(b,b.CreateString(r.names->positionName),b.CreateString(r.names->holderName),r.names->holderKind,r.names->holderId);
        rows.push_back(m::CreateLocationStaffRow(b,uint8_t(r.source),r.occupationId,r.role,r.histfigId,r.unitId,r.locationId,r.siteId,r.groupId,r.entityId,r.positionId,r.assignmentId,names));
      }
      staff=m::CreateLocationStaffSnapshot(b,b.CreateVector(rows),b.CreateVector(d.staff->missingRoles));
    }
    flatbuffers::Offset<m::LocationAffiliation> affiliation;
    if(d.affiliation) {const auto& a=*d.affiliation;affiliation=m::CreateLocationAffiliation(b,a.kind,a.id,b.CreateString(a.name),a.count,a.workers);}
    locationDetails=m::CreateLocationDetails(b,d.siteId,d.id,d.kind,b.CreateString(d.name),df3d_area::locationDetailsRevision(d),
        uint8_t(d.access),d.accessFlags.visitors,d.accessFlags.residents,d.accessFlags.members,
        d.profession,d.tier,d.value,d.desiredCopies,d.recognized,b.CreateVector(supplies),b.CreateVector(d.zoneIds),d.appraisal,facilities,d.writtenObjects,d.danceFloorX,d.danceFloorY,staff,affiliation);
  }
  flatbuffers::Offset<m::LocationStaffCandidates> staffCandidates;
  if(areaPage.staffCandidates) {
    const auto& p=*areaPage.staffCandidates;
    std::vector<flatbuffers::Offset<m::LocationStaffCandidate>> rows;
    for(const auto& r:p.rows) {
      std::vector<flatbuffers::Offset<m::LocationStaffSkill>> skills;
      for(const auto& s:r.skills)skills.push_back(m::CreateLocationStaffSkill(b,s.id,s.rating,s.experience,s.weight));
      rows.push_back(m::CreateLocationStaffCandidate(b,r.unitId,r.histfigId,b.CreateString(r.name),r.score,b.CreateVector(skills),
          b.CreateString(r.baseName),b.CreateString(r.professionName),r.professionColor,r.legendary,
          r.sourceIndex,r.professionOrder,r.statusOrder,b.CreateVector(r.nameSortKey),b.CreateVector(r.professionSortKey)));
    }
    staffCandidates=m::CreateLocationStaffCandidates(b,p.target.siteId,p.target.locationId,p.target.occupationId,p.role,
        p.revision,areaPage.locationCursor,p.nextCursor,p.total,b.CreateVector(rows));
    // Refuse invalid native facts without replacing the operation or inventing UI copy.
    if(m::validateLocationStaffCandidates(*flatbuffers::GetTemporaryPointer(b,staffCandidates))) {
      staffCandidates=0;status=m::ManagementStatus::Rejected;
    }
  }
  auto areaResult=m::CreateAreaState(b,b.CreateVector(as),b.CreateVector(ac),areaCursor,areaTruncated,
      areaPage.operation,areaPage.id,b.CreateString(areaPage.listKey),areaPage.candidateKind,areaPage.sort,areaPage.sortDescending,
      b.CreateString(areaPage.query),b.CreateVector(settings),b.CreateVector(locations),b.CreateVector(candidates),b.CreateVector(links),
      uint64_t(areaPage.listRevision),areaPage.buildPhase,areaPage.buildDone,areaPage.buildTotal,areaPage.omitted,areaPage.capturedTick,
      areaPage.interactionId,areaPage.undoToken,areaPage.roomOutcome,areaPage.roomsCreated,
      areaPage.roomsInUse,areaPage.roomsUnenclosed,areaPage.roomsRemoved,areaPage.roomsDormitories,
      areaPage.countGeneration,areaPage.paintedCount,areaPage.previewCount,locationCatalog,locationDetails,areaPage.locationEntryOutcome,areaPage.locationEditOutcome,staffCandidates);
  auto reqs=[&](const std::vector<ProductionRequirement>& values){
    std::vector<flatbuffers::Offset<m::ProductionRequirement>> out;
    for(const auto& v:values) out.push_back(m::CreateProductionRequirement(b,b.CreateString(v.description),v.quantity,v.itemType));
    return b.CreateVector(out);
  };
  std::vector<flatbuffers::Offset<m::ProductionBuilding>> pb;
  for(const auto& v:production.buildings){m::TilePos p(v.x,v.y,v.z);pb.push_back(m::CreateProductionBuilding(b,v.id,b.CreateString(v.name),b.CreateString(v.kind),&p,v.buildStage,v.maxStage,v.queueSize));}
  std::vector<flatbuffers::Offset<m::ProductionRecipe>> pr;
  for(const auto& v:production.recipes) pr.push_back(m::CreateProductionRecipe(b,b.CreateString(v.key),b.CreateString(v.name),reqs(v.requirements)));
  std::vector<flatbuffers::Offset<m::ProductionJob>> pj;
  for(const auto& v:production.jobs) pj.push_back(m::CreateProductionJob(b,v.id,b.CreateString(v.name),v.jobType,v.repeat,v.suspended,v.workerId,b.CreateString(v.workerName),v.completionTimer,v.attachedItems,v.editable,b.CreateString(v.status),reqs(v.requirements)));
  std::vector<flatbuffers::Offset<m::FarmCrop>> pc;
  for(const auto& v:production.crops) pc.push_back(m::CreateFarmCrop(b,v.id,b.CreateString(v.name),v.seasons,v.seeds));
  auto productionResult=m::CreateProductionState(b,b.CreateVector(pb),production.nextCursor,b.CreateVector(pr),b.CreateVector(pj),b.CreateVector(pc),b.CreateVector(production.seasonalCrops),production.currentSeason,production.selectedBuilding,production.createdJob,b.CreateString(production.detail));
  std::vector<flatbuffers::Offset<m::WorkOrderInfo>> wo;
  for(const auto& o:workOrders.orders){
    std::vector<flatbuffers::Offset<m::WorkOrderCondition>> cs;
    for(const auto& c:o.conditions)cs.push_back(m::CreateWorkOrderCondition(b,c.kind,c.index,b.CreateString(c.description),c.editable,c.compare,c.threshold,c.itemType,c.targetOrder,c.dependency,c.satisfied,c.itemSubtype,c.matType,c.matIndex,b.CreateVectorOfStrings(c.traits),c.satisfaction,c.estimated,c.estimateCount));
    std::vector<flatbuffers::Offset<m::WorkOrderInput>> wi;
    for(const auto& v:o.inputs)wi.push_back(m::CreateWorkOrderInput(b,v.index,b.CreateString(v.description),v.matType,v.matIndex,v.editable));
    wo.push_back(m::CreateWorkOrderInfo(b,o.id,o.revision,b.CreateString(o.name),o.total,o.remaining,o.frequency,o.validated,o.active,o.finishedYear,o.finishedTick,o.workshopId,o.maxWorkshops,b.CreateVector(o.generatedJobs),b.CreateVector(cs),o.editable,b.CreateString(o.reason),o.position,o.detailKind,o.sizeRaw,o.encrustFlags,o.matType,o.matIndex,o.materialCategory,b.CreateVector(wi)));
  }
  std::vector<flatbuffers::Offset<m::ProductionRecipe>> wr;for(const auto& r:workOrders.recipes)wr.push_back(m::CreateProductionRecipe(b,b.CreateString(r.key),b.CreateString(r.name)));
  std::vector<flatbuffers::Offset<m::AreaChoice>> wc;for(const auto& c:workOrders.choices)wc.push_back(m::CreateAreaChoice(b,c.id,b.CreateString(c.name)));
  std::vector<flatbuffers::Offset<m::ManagerRole>> wm;for(const auto& v:workOrders.managers)wm.push_back(m::CreateManagerRole(b,v.unitId,b.CreateString(v.name),b.CreateString(v.position),b.CreateVector(v.offices),b.CreateString(v.job)));
  std::vector<flatbuffers::Offset<m::WorkOrderMaterial>> wo_materials;
  for(const auto& v:workOrders.materials)wo_materials.push_back(m::CreateWorkOrderMaterial(b,v.matType,v.matIndex,b.CreateString(v.name)));
  std::vector<flatbuffers::Offset<m::WorkOrderTrait>> wo_traits;
  for(const auto& v:workOrders.traits)wo_traits.push_back(m::CreateWorkOrderTrait(b,b.CreateString(v.key),b.CreateString(v.name)));
  std::vector<flatbuffers::Offset<m::WorkOrderItemType>> wo_types;
  for(const auto& v:workOrders.types)wo_types.push_back(m::CreateWorkOrderItemType(b,v.itemType,v.itemSubtype,b.CreateString(v.name)));
  std::vector<flatbuffers::Offset<m::WorkOrderGroup>> wo_groups;
  for(const auto& v:workOrders.groups)wo_groups.push_back(m::CreateWorkOrderGroup(b,v.type,v.subtype,v.custom,b.CreateString(v.name),v.count));
  std::vector<flatbuffers::Offset<m::WorkOrderTask>> wo_tasks;
  for(const auto& v:workOrders.tasks)wo_tasks.push_back(m::CreateWorkOrderTask(b,b.CreateString(v.key),b.CreateString(v.name),v.jobType,b.CreateString(v.reaction),v.itemType,v.itemSubtype,v.matType,v.matIndex));
  auto workOrderResult=m::CreateWorkOrderState(b,b.CreateVector(wo),b.CreateVector(wr),b.CreateVector(wc),b.CreateVector(wm),workOrders.nextCursor,b.CreateString(workOrders.detail),b.CreateVector(wo_materials),b.CreateVector(wo_traits),b.CreateVector(wo_types),b.CreateVector(wo_groups),b.CreateVector(wo_tasks),workOrders.total,workOrders.listRevision,workOrders.buildPhase,workOrders.buildDone,workOrders.buildTotal);
  std::vector<flatbuffers::Offset<m::CitizenInfo>> citizenRows;
  for(const auto& u:citizens.citizens) {
    std::vector<flatbuffers::Offset<m::CitizenRole>> roles;
    for(const auto& r:u.roles)roles.push_back(m::CreateCitizenRole(b,b.CreateString(r.name),r.requiredOffice));
    m::TilePos pos(u.x,u.y,u.z);
    std::vector<flatbuffers::Offset<m::CitizenWorkDetail>> assignments;
    for(const auto& d:u.assignedDetails)assignments.push_back(m::CreateCitizenWorkDetail(b,d.index,d.icon,b.CreateString(d.name)));
    citizenRows.push_back(m::CreateCitizenInfo(b,u.id,b.CreateString(u.name),b.CreateString(u.profession),b.CreateString(u.job),u.age,u.stress,u.hasStress,&pos,u.canFocus,u.eligible,b.CreateString(u.reason),b.CreateVector(u.labors),b.CreateVector(roles),b.CreateVector(u.offices),b.CreateVectorOfStrings(u.laborNames),u.professionColor,u.professionId,u.jobType,u.sheetIcon.build(b),u.onlyAssignedJobs,b.CreateVector(assignments),u.socialActivity,u.revision,u.detailMember,u.detailSkill,u.detailSkillRating,b.CreateString(u.detailSkillName),u.portraitState,b.CreateString(u.rowError)));
  }
  std::vector<flatbuffers::Offset<m::WorkDetailInfo>> detailRows;
  for(const auto& d:citizens.details)detailRows.push_back(m::CreateWorkDetailInfo(b,d.index,d.revision,b.CreateString(d.name),d.mode,d.noModify,d.cannotBeEverybody,d.editable,d.modeEditable,b.CreateString(d.reason),b.CreateVector(d.labors),b.CreateVector(d.assignedUnits),b.CreateVectorOfStrings(d.laborNames),d.icon,b.CreateString(d.rowError)));
  auto citizenResult=citizenAction(action) ? m::CreateCitizenState(b,b.CreateVector(citizenRows),b.CreateVector(detailRows),citizens.nextCursor,citizens.selectedUnit,citizens.selectedDetail,citizens.externalController,b.CreateString(citizens.detail),citizens.recalcDone,citizens.recalcTotal,b.CreateString(citizens.recalcError),citizens.detailListRevision) : flatbuffers::Offset<m::CitizenState>{};
  std::vector<flatbuffers::Offset<m::ReportInfo>> reportRows;
  for(const auto& r:reports.reports)reportRows.push_back(m::CreateReportInfo(b,r.id,b.CreateString(r.category),b.CreateString(r.text),r.year,r.yearTick,r.repeatCount,r.continuation,r.textComplete,r.x,r.y,r.z,r.x2,r.y2,r.z2,r.positionVisible,r.position2Visible,m::ReportTab(r.tab),r.color,r.bright,m::ReportZoom(r.zoomType),m::ReportZoom(r.zoomType2),r.positionHidden,r.position2Hidden,r.speakerId));
  std::vector<flatbuffers::Offset<m::ReportUnitInfo>> reportUnits;
  for(const auto& u:reports.units)reportUnits.push_back(m::CreateReportUnitInfo(b,u.unitId,u.category,b.CreateString(u.profession),b.CreateString(u.name),u.dead,u.logCount,b.CreateString(u.error)));
  auto reportResult=m::CreateReportState(b,b.CreateVector(reportRows),reports.nextBeforeId,reports.announcementsOnly,b.CreateString(reports.detail),m::ReportView(reports.view),m::ReportTab(reports.tab),reports.afterId,reports.fromEnd,b.CreateVector(reports.tabCounts),reports.total,reports.nextAfterId,reports.trimmedThrough,reports.gap,reports.unitId,reports.unitCategory,reports.cursor,reports.nextCursor,reports.listRevision,b.CreateVector(reportUnits),b.CreateVector(reports.missingIds),reports.notificationCategory,reports.alertButton);
  std::vector<flatbuffers::Offset<m::AgreementInfo>> agreementRows;
  for(const auto& a:agreements.agreements) {
    std::vector<flatbuffers::Offset<m::AgreementDetail>> details;
    for(const auto& d:a.details)details.push_back(m::CreateAgreementDetail(b,d.id,d.kind,d.siteId,d.year,d.yearTick,d.applicantParty,d.governmentParty,d.locationType,d.tier,d.profession,d.deityType,d.deityId,b.CreateString(d.description)));
    std::vector<flatbuffers::Offset<m::AgreementParty>> parties;
    for(const auto& p:a.parties)parties.push_back(m::CreateAgreementParty(b,p.id,b.CreateVector(p.entityIds),b.CreateVector(p.histfigIds),b.CreateString(p.name)));
    agreementRows.push_back(m::CreateAgreementInfo(b,a.id,m::AgreementStatus(a.status),a.notApproved,a.concluded,a.continuing,b.CreateVector(details),b.CreateVector(parties),b.CreateString(a.summary),a.complete,b.CreateString(a.reason)));
  }
  std::vector<flatbuffers::Offset<m::TradeDepot>> td;
  for(const auto& d:trade.depots){m::TilePos pos(d.x,d.y,d.z);td.push_back(m::CreateTradeDepot(b,d.id,&pos,d.revision,d.requested,d.anyone,d.accessible,d.ready,b.CreateString(d.broker),d.hauling,d.goods));}
  std::vector<flatbuffers::Offset<m::TradeCaravan>> tc;
  for(const auto& c:trade.caravans)tc.push_back(m::CreateTradeCaravan(b,c.id,b.CreateString(c.name),b.CreateString(c.state),c.daysRemaining));
  std::vector<flatbuffers::Offset<m::TradeGood>> tg;
  for(const auto& g:trade.goods)tg.push_back(m::CreateTradeGood(b,g.id,b.CreateString(g.description),g.quantity,g.selected,g.selectable,b.CreateString(g.reason)));
  auto tradeResult=m::CreateTradeState(b,b.CreateVector(td),b.CreateVector(tc),b.CreateVector(tg),trade.nextCursor,trade.selectedDepot,b.CreateString(trade.detail));
  auto agreementResult=m::CreateAgreementState(b,b.CreateVector(agreementRows),agreements.nextBeforeId,agreements.pendingOnly,b.CreateString(agreements.detail));
  auto creatureResult=creature_data::build(b,creature);
  auto s = m::CreateManagementState(b, m::kManagementVersion, ++revision, epoch, client, seq,
                                    action, status, b.CreateString(message), b.CreateVector(ds),
                                    b.CreateVector(is), required, cursor, valid, building, stage,
                                    maxStage, removing, jobs, terrainConstructed, areaResult, productionResult, workOrderResult, citizenResult, reportResult, agreementResult, tradeResult, 0, 0, 0, 0, 0, creatureResult, constructionResult);
  b.Finish(s);
  if (auto e = m::validateManagementState(
          *flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()))) {
    if (publishingFallback) {
      // The minimal fallback failed validation too: nothing sane to publish.
      Core::getInstance().getConsole().printerr("df3d: management fallback response invalid: {}\n", *e);
      return;
    }
    publishingFallback = true;
    const auto placed=construction.placed,skipped=construction.skipped;
    const auto first=construction.first_building;
    clearResult();
    construction.placed=placed;construction.skipped=skipped;construction.first_building=first;
    status = m::ManagementStatus::Rejected;
    message = "Invalid native management response: " + *e;
    publish();
    publishingFallback = false;
    return;
  }
  sh::publishSnapshot(region, b.GetBufferPointer(), b.GetSize(), revision);
  if(reply)sh::publishSnapshot(reply->region(),b.GetBufferPointer(),b.GetSize(),revision);
  if(status!=m::ManagementStatus::Pending)reply.reset();
}
bool start(color_ostream& out) {
  auto size = sh::regionSize(m::kManagementCapacity, m::kManagementCommandCapacity);
  mapping = CreateFileMappingA(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, DWORD(size),
                               m::kManagementRegionName);
  if (!mapping) {
    if (!warnedStartFailure) { warnedStartFailure = true; out.printerr("df3d: management channel CreateFileMapping failed (error {}); retrying every {} updates (reported once)\n", GetLastError(), kStartRetryUpdates); }
    return false;
  }
  region = static_cast<sh::RegionHeader*>(MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, size));
  if (!region) {
    // Keep no handle across a failed attempt: a retry per update would leak one each.
    const auto error = GetLastError();
    CloseHandle(mapping);
    mapping = nullptr;
    if (!warnedStartFailure) { warnedStartFailure = true; out.printerr("df3d: management channel MapViewOfFile failed (error {}); retrying every {} updates (reported once)\n", error, kStartRetryUpdates); }
    return false;
  }
  warnedStartFailure = false;
  sh::initRegion(region, m::kManagementVersion, m::kManagementCapacity,
                 m::kManagementCommandCapacity);
  FILETIME ct{}, et{}, kt{}, ut{};
  GetProcessTimes(GetCurrentProcess(), &ct, &et, &kt, &ut);
  auto* o = m::sessionOwner(region);
  sh::atomicStoreRelease(&o->created, (uint64_t(ct.dwHighDateTime) << 32) | ct.dwLowDateTime);
  sh::atomicStoreRelease(&o->generation,
                         uint64_t(std::chrono::steady_clock::now().time_since_epoch().count()));
  sh::atomicStoreRelease(&o->pid, GetCurrentProcessId());
  return true;
}
using lua_fields::boolean;
using lua_fields::number;
using lua_fields::text;
template <class T>
void field(lua_State* L, const char* key, T value) {
  Lua::SetField(L, value, -1, key);
}
// One catalog for native vector access and structural revision sizes.
// Lua owns hierarchy and write selection; native classified fills reacquire
// current raw membership without borrowing a cached label-builder result.
auto areaSettingVectors(df::building_stockpilest* pile) {
  using Entry=std::pair<const char*,std::vector<char>*>;
  return std::array<Entry,78>{{
    {"ammo.type",&pile->settings.ammo.type},
    {"ammo.other_mats",&pile->settings.ammo.other_mats},
    {"ammo.mats",&pile->settings.ammo.mats},
    {"animals.enabled",&pile->settings.animals.enabled},
    {"armor.body",&pile->settings.armor.body},
    {"armor.head",&pile->settings.armor.head},
    {"armor.feet",&pile->settings.armor.feet},
    {"armor.hands",&pile->settings.armor.hands},
    {"armor.legs",&pile->settings.armor.legs},
    {"armor.shield",&pile->settings.armor.shield},
    {"armor.other_mats",&pile->settings.armor.other_mats},
    {"armor.mats",&pile->settings.armor.mats},
    {"armor.color",&pile->settings.armor.color},
    {"bars_blocks.bars_other_mats",&pile->settings.bars_blocks.bars_other_mats},
    {"bars_blocks.blocks_other_mats",&pile->settings.bars_blocks.blocks_other_mats},
    {"bars_blocks.bars_mats",&pile->settings.bars_blocks.bars_mats},
    {"bars_blocks.blocks_mats",&pile->settings.bars_blocks.blocks_mats},
    {"cloth.thread_silk",&pile->settings.cloth.thread_silk},
    {"cloth.thread_plant",&pile->settings.cloth.thread_plant},
    {"cloth.thread_yarn",&pile->settings.cloth.thread_yarn},
    {"cloth.thread_metal",&pile->settings.cloth.thread_metal},
    {"cloth.cloth_silk",&pile->settings.cloth.cloth_silk},
    {"cloth.cloth_plant",&pile->settings.cloth.cloth_plant},
    {"cloth.cloth_yarn",&pile->settings.cloth.cloth_yarn},
    {"cloth.cloth_metal",&pile->settings.cloth.cloth_metal},
    {"cloth.color",&pile->settings.cloth.color},
    {"coins.mats",&pile->settings.coins.mats},
    {"finished_goods.type",&pile->settings.finished_goods.type},
    {"finished_goods.other_mats",&pile->settings.finished_goods.other_mats},
    {"finished_goods.mats",&pile->settings.finished_goods.mats},
    {"finished_goods.color",&pile->settings.finished_goods.color},
    {"food.meat",&pile->settings.food.meat},
    {"food.fish",&pile->settings.food.fish},
    {"food.unprepared_fish",&pile->settings.food.unprepared_fish},
    {"food.egg",&pile->settings.food.egg},
    {"food.plants",&pile->settings.food.plants},
    {"food.drink_plant",&pile->settings.food.drink_plant},
    {"food.drink_animal",&pile->settings.food.drink_animal},
    {"food.cheese_plant",&pile->settings.food.cheese_plant},
    {"food.cheese_animal",&pile->settings.food.cheese_animal},
    {"food.seeds",&pile->settings.food.seeds},
    {"food.leaves",&pile->settings.food.leaves},
    {"food.powder_plant",&pile->settings.food.powder_plant},
    {"food.powder_creature",&pile->settings.food.powder_creature},
    {"food.glob",&pile->settings.food.glob},
    {"food.glob_paste",&pile->settings.food.glob_paste},
    {"food.glob_pressed",&pile->settings.food.glob_pressed},
    {"food.liquid_plant",&pile->settings.food.liquid_plant},
    {"food.liquid_animal",&pile->settings.food.liquid_animal},
    {"food.liquid_misc",&pile->settings.food.liquid_misc},
    {"furniture.type",&pile->settings.furniture.type},
    {"furniture.other_mats",&pile->settings.furniture.other_mats},
    {"furniture.mats",&pile->settings.furniture.mats},
    {"gems.rough_other_mats",&pile->settings.gems.rough_other_mats},
    {"gems.cut_other_mats",&pile->settings.gems.cut_other_mats},
    {"gems.rough_mats",&pile->settings.gems.rough_mats},
    {"gems.cut_mats",&pile->settings.gems.cut_mats},
    {"corpses.corpses",&pile->settings.corpses.corpses},
    {"leather.mats",&pile->settings.leather.mats},
    {"leather.color",&pile->settings.leather.color},
    {"ore.mats",&pile->settings.ore.mats},
    {"refuse.type",&pile->settings.refuse.type},
    {"refuse.corpses",&pile->settings.refuse.corpses},
    {"refuse.body_parts",&pile->settings.refuse.body_parts},
    {"refuse.skulls",&pile->settings.refuse.skulls},
    {"refuse.bones",&pile->settings.refuse.bones},
    {"refuse.hair",&pile->settings.refuse.hair},
    {"refuse.shells",&pile->settings.refuse.shells},
    {"refuse.teeth",&pile->settings.refuse.teeth},
    {"refuse.horns",&pile->settings.refuse.horns},
    {"sheet.paper",&pile->settings.sheet.paper},
    {"sheet.parchment",&pile->settings.sheet.parchment},
    {"stone.mats",&pile->settings.stone.mats},
    {"weapons.weapon_type",&pile->settings.weapons.weapon_type},
    {"weapons.trapcomp_type",&pile->settings.weapons.trapcomp_type},
    {"weapons.other_mats",&pile->settings.weapons.other_mats},
    {"weapons.mats",&pile->settings.weapons.mats},
    {"wood.mats",&pile->settings.wood.mats}}};
}
struct AreaFixedSetting {const char* key;bool* values;size_t count;};
auto areaFixedSettings(df::building_stockpilest* pile) {
  // Pinned stockpile_parameter_* layouts: ten quality arrays and nineteen
  // switches. Category flags remain a separate bitfield, never a bool pointer.
  auto& s=pile->settings;
  return std::array<AreaFixedSetting,29>{{
    {"ammo.quality_core",s.ammo.quality_core.data(),s.ammo.quality_core.size()},
    {"ammo.quality_total",s.ammo.quality_total.data(),s.ammo.quality_total.size()},
    {"armor.quality_core",s.armor.quality_core.data(),s.armor.quality_core.size()},
    {"armor.quality_total",s.armor.quality_total.data(),s.armor.quality_total.size()},
    {"finished_goods.quality_core",s.finished_goods.quality_core.data(),s.finished_goods.quality_core.size()},
    {"finished_goods.quality_total",s.finished_goods.quality_total.data(),s.finished_goods.quality_total.size()},
    {"furniture.quality_core",s.furniture.quality_core.data(),s.furniture.quality_core.size()},
    {"furniture.quality_total",s.furniture.quality_total.data(),s.furniture.quality_total.size()},
    {"weapons.quality_core",s.weapons.quality_core.data(),s.weapons.quality_core.size()},
    {"weapons.quality_total",s.weapons.quality_total.data(),s.weapons.quality_total.size()},
    {"animals.empty_cages",&s.animals.empty_cages,1},
    {"animals.empty_traps",&s.animals.empty_traps,1},
    {"armor.usable",&s.armor.usable,1},
    {"armor.unusable",&s.armor.unusable,1},
    {"armor.dyed",&s.armor.dyed,1},
    {"armor.undyed",&s.armor.undyed,1},
    {"cloth.dyed",&s.cloth.dyed,1},
    {"cloth.undyed",&s.cloth.undyed,1},
    {"finished_goods.dyed",&s.finished_goods.dyed,1},
    {"finished_goods.undyed",&s.finished_goods.undyed,1},
    {"food.prepared_meals",&s.food.prepared_meals,1},
    {"leather.dyed",&s.leather.dyed,1},
    {"leather.undyed",&s.leather.undyed,1},
    {"misc.allow_organic",&s.misc.allow_organic,1},
    {"misc.allow_inorganic",&s.misc.allow_inorganic,1},
    {"refuse.fresh_raw_hide",&s.refuse.fresh_raw_hide,1},
    {"refuse.rotten_raw_hide",&s.refuse.rotten_raw_hide,1},
    {"weapons.usable",&s.weapons.usable,1},
    {"weapons.unusable",&s.weapons.unusable,1}}};
}
// Counts refer to native setting indices, not visible rows. Shared material
// partitions count once per backing vector; their eligibility is built later.
// ore.mats is an unused native field and has no corresponding raw list.
auto areaSettingRawCounts() {
  const auto& raws=df::global::world->raws;
  using Organic=df::organic_mat_category;
  const auto organic=[&](Organic cat){return raws.mat_table.organic_types[cat].size();};
  const size_t inorganic=raws.inorganics.all.size(),creatures=raws.creatures.all.size(),
      colors=raws.descriptors.colors.size(),builtin=raws.mat_table.builtin.size();
  return std::map<std::string_view,size_t>{
    {"ammo.type",raws.itemdefs.ammo.size()},{"ammo.other_mats",2},{"ammo.mats",inorganic},
    {"animals.enabled",creatures},
    {"armor.body",raws.itemdefs.armor.size()},{"armor.head",raws.itemdefs.helms.size()},
    {"armor.feet",raws.itemdefs.shoes.size()},{"armor.hands",raws.itemdefs.gloves.size()},
    {"armor.legs",raws.itemdefs.pants.size()},{"armor.shield",raws.itemdefs.shields.size()},
    {"armor.other_mats",10},{"armor.mats",inorganic},{"armor.color",colors},
    {"bars_blocks.bars_other_mats",5},{"bars_blocks.blocks_other_mats",4},
    {"bars_blocks.bars_mats",inorganic},{"bars_blocks.blocks_mats",inorganic},
    {"cloth.thread_silk",organic(Organic::Silk)},{"cloth.thread_plant",organic(Organic::PlantFiber)},
    {"cloth.thread_yarn",organic(Organic::Yarn)},{"cloth.thread_metal",organic(Organic::MetalThread)},
    {"cloth.cloth_silk",organic(Organic::Silk)},{"cloth.cloth_plant",organic(Organic::PlantFiber)},
    {"cloth.cloth_yarn",organic(Organic::Yarn)},{"cloth.cloth_metal",organic(Organic::MetalThread)},
    {"cloth.color",colors},{"coins.mats",inorganic},
    {"finished_goods.type",size_t(df::enum_traits<df::item_type>::last_item_value)+1},
    {"finished_goods.other_mats",16},{"finished_goods.mats",inorganic},{"finished_goods.color",colors},
    {"food.meat",organic(Organic::Meat)},{"food.fish",organic(Organic::Fish)},
    {"food.unprepared_fish",organic(Organic::UnpreparedFish)},{"food.egg",organic(Organic::Eggs)},
    {"food.plants",organic(Organic::Plants)},{"food.drink_plant",organic(Organic::PlantDrink)},
    {"food.drink_animal",organic(Organic::CreatureDrink)},{"food.cheese_plant",organic(Organic::PlantCheese)},
    {"food.cheese_animal",organic(Organic::CreatureCheese)},{"food.seeds",organic(Organic::Seed)},
    {"food.leaves",organic(Organic::PlantGrowth)},{"food.powder_plant",organic(Organic::PlantPowder)},
    {"food.powder_creature",organic(Organic::CreaturePowder)},{"food.glob",organic(Organic::Glob)},
    {"food.glob_paste",organic(Organic::Paste)},{"food.glob_pressed",organic(Organic::Pressed)},
    {"food.liquid_plant",organic(Organic::PlantLiquid)},{"food.liquid_animal",organic(Organic::CreatureLiquid)},
    {"food.liquid_misc",organic(Organic::MiscLiquid)},
    {"furniture.type",size_t(df::enum_traits<df::furniture_type>::last_item_value)+1},
    {"furniture.other_mats",15},{"furniture.mats",inorganic},
    {"gems.rough_other_mats",builtin},{"gems.cut_other_mats",builtin},
    {"gems.rough_mats",inorganic},{"gems.cut_mats",inorganic},
    {"corpses.corpses",creatures},{"leather.mats",organic(Organic::Leather)},{"leather.color",colors},
    {"ore.mats",0},
    {"refuse.type",size_t(df::enum_traits<df::item_type>::last_item_value)+1},
    {"refuse.corpses",creatures},{"refuse.body_parts",creatures},{"refuse.skulls",creatures},
    {"refuse.bones",creatures},{"refuse.hair",creatures},{"refuse.shells",creatures},
    {"refuse.teeth",creatures},{"refuse.horns",creatures},
    {"sheet.paper",organic(Organic::Paper)},{"sheet.parchment",organic(Organic::Parchment)},
    {"stone.mats",inorganic},{"weapons.weapon_type",raws.itemdefs.weapons.size()},
    {"weapons.trapcomp_type",raws.itemdefs.trapcomps.size()},
    {"weapons.other_mats",10},{"weapons.mats",inorganic},{"wood.mats",raws.plants.all.size()}};
}
int areaSettingsLayout(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=0) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);return 1;
  };
  if(!lua_isnil(L,2) && (!lua_isinteger(L,2) || lua_tointeger(L,2)<0 || lua_tointeger(L,2)>1536))
    return fail("Invalid settings layout budget");
  const uint32_t budget=lua_isnil(L,2)?UINT32_MAX:uint32_t(lua_tointeger(L,2));
  // One fixed group plus one descriptor per vector/array/scalar. No raw or
  // stored setting element is visited, even for a corrupt oversized vector.
  constexpr uint32_t cost=1+78+29;
  if(budget<cost)return fail("Settings layout exceeds remaining step budget");
  auto* pile=Lua::GetDFObject<df::building_stockpilest>(L,1);
  if(!pile || !df::global::world)return fail("Area no longer exists",1);
  const auto counts=areaSettingRawCounts();const auto vectors=areaSettingVectors(pile);
  if(counts.size()!=vectors.size())return fail("Stockpile settings layout changed",cost);
  std::array<size_t,78> lengths{};size_t index=0;
  for(const auto& entry:vectors) {
    const auto count=counts.find(entry.first);
    if(count==counts.end())return fail("Stockpile settings layout changed",cost);
    lengths[index++]=count->second;
  }
  const auto total=df3d_area::settingsRawTotal(lengths);
  if(!total.valid)return fail("Stockpile settings exceed 65,536 entries",cost);
  df3d_area::Revision rawRevision;for(const auto length:lengths)rawRevision.add(length);
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",cost);field(L,"raw_count",total.count);
  field(L,"raw_revision",rawRevision.finish());
  lua_newtable(L);index=0;
  for(const auto& entry:vectors) {
    lua_newtable(L);field(L,"count",lengths[index++]);field(L,"stored_count",entry.second->size());field(L,"fixed",false);
    lua_setfield(L,-2,entry.first);
  }
  for(const auto& entry:areaFixedSettings(pile)) {
    lua_newtable(L);field(L,"count",entry.count);field(L,"stored_count",entry.count);field(L,"fixed",true);
    lua_setfield(L,-2,entry.key);
  }
  lua_setfield(L,-2,"fields");return 1;
}
enum class AreaSettingRule { Any, Metal, MetalStone, Gem, GemStone, GemMetalStone,
                             Stone, Inorganic, Glass, Creature, Plant, FinishedType, RefuseType };
AreaSettingRule areaSettingRule(std::string_view key) {
  using R=AreaSettingRule;
  if(key=="ammo.mats" || key=="armor.mats" || key=="bars_blocks.bars_mats")return R::Metal;
  if(key=="weapons.mats" || key=="furniture.mats" || key=="bars_blocks.blocks_mats")return R::MetalStone;
  if(key=="finished_goods.mats")return R::GemMetalStone;
  if(key=="gems.rough_mats")return R::Gem;
  if(key=="gems.cut_mats")return R::GemStone;
  if(key=="stone.mats")return R::Stone;
  if(key=="coins.mats")return R::Inorganic;
  if(key=="gems.rough_other_mats" || key=="gems.cut_other_mats")return R::Glass;
  if(key=="animals.enabled" || key=="corpses.corpses" ||
      (key.substr(0,7)=="refuse." && key!="refuse.type"))return R::Creature;
  if(key=="wood.mats")return R::Plant;
  if(key=="finished_goods.type")return R::FinishedType;
  if(key=="refuse.type")return R::RefuseType;
  return R::Any;
}
uint16_t areaSettingPartitions(AreaSettingRule rule) {
  using R=AreaSettingRule;using namespace df3d_area;
  switch(rule) {
    case R::Metal:return Metal;
    case R::MetalStone:return Metal|Stone;
    case R::Gem:return Gem;
    case R::GemStone:return Gem|Stone;
    case R::GemMetalStone:return Gem|Metal|Stone;
    case R::Stone:return MetalOres|Economic|Clay|OtherStone;
    default:return Any;
  }
}
uint16_t areaSettingPartition(AreaSettingRule rule,size_t index) {
  using R=AreaSettingRule;using namespace df3d_area;
  const auto& raws=df::global::world->raws;
  if(rule==R::Any)return Any;
  if(rule==R::Creature) {
    const auto* raw=raws.creatures.all[index];
    return raw && !raw->flags.is_set(df::creature_raw_flags::GENERATED) && raw->creature_id!="EQUIPMENT_WAGON" ? Any : 0;
  }
  if(rule==R::Plant) {
    const auto* raw=raws.plants.all[index];
    return raw && raw->flags.is_set(df::plant_raw_flags::TREE) ? Any : 0;
  }
  if(rule==R::FinishedType) {
    using T=df::item_type;
    switch(T(index)) {
      case T::CHAIN:case T::FLASK:case T::GOBLET:case T::INSTRUMENT:case T::TOY:
      case T::ARMOR:case T::SHOES:case T::HELM:case T::GLOVES:case T::FIGURINE:
      case T::AMULET:case T::SCEPTER:case T::CROWN:case T::RING:case T::EARRING:
      case T::BRACELET:case T::GEM:case T::TOTEM:case T::PANTS:case T::BACKPACK:
      case T::QUIVER:case T::SPLINT:case T::CRUTCH:case T::TOOL:case T::BOOK:return Any;
      default:return 0;
    }
  }
  if(rule==R::RefuseType) {
    using T=df::item_type;
    switch(T(index)) {
      case T::NONE:case T::BAR:case T::SMALLGEM:case T::BLOCKS:case T::ROUGH:
      case T::BOULDER:case T::CORPSE:case T::CORPSEPIECE:case T::ROCK:case T::ORTHOPEDIC_CAST:case T::BRANCH:return 0;
      default:return Any;
    }
  }
  if(rule==R::Glass) {
    MaterialInfo mi(int16_t(index),-1);
    if(!mi.isValid())return 0;
    const auto token=mi.getToken();
    return token=="GLASS_GREEN" || token=="GLASS_CLEAR" || token=="GLASS_CRYSTAL" ? Any : 0;
  }
  MaterialInfo mi(0,int32_t(index));
  if(!mi.isValid() || !mi.material || !mi.inorganic)return 0;
  const auto& flags=mi.material->flags;
  const bool metal=flags.is_set(df::material_flags::IS_METAL),stone=flags.is_set(df::material_flags::IS_STONE),
      gem=flags.is_set(df::material_flags::IS_GEM);
  switch(rule) {
    case R::Inorganic:return Any;
    case R::Metal:return metal ? Metal : 0;
    case R::MetalStone:return metal ? Metal : stone ? Stone : 0;
    case R::Gem:return gem ? Gem : 0;
    case R::GemStone:return gem ? Gem : stone ? Stone : 0;
    case R::GemMetalStone:return gem ? Gem : metal ? Metal : stone ? Stone : 0;
    case R::Stone: {
      const bool soil=mi.inorganic->flags.is_set(df::inorganic_flags::SOIL);
      if(!(soil && !mi.inorganic->flags.is_set(df::inorganic_flags::AQUIFER)) &&
          !(stone && !flags.is_set(df::material_flags::NO_STONE_STOCKPILE)))return 0;
      if(!mi.inorganic->metal_ore.mat_index.empty())return MetalOres;
      if(!mi.inorganic->economic_uses.empty())return Economic;
      return soil ? Clay : OtherStone;
    }
    default:return 0;
  }
}
class AreaPresetGuard {
  df::building_stockpilest* pile_;
  decltype(areaFixedSettings(nullptr)) fixed_;
  std::array<std::array<bool,7>,29> values_{};
  uint32_t flags_,stockpileFlags_;
  int16_t barrels_,bins_,wheelbarrows_;
  bool committed_=false;
  df3d_area::PresetVectors<std::vector<char>,78> vectors_;
  static auto vectorTargets(df::building_stockpilest* pile) {
    std::array<std::vector<char>*,78> targets{};size_t index=0;
    for(const auto& entry:areaSettingVectors(pile)) {
      if(std::string_view(entry.first)!="ore.mats")targets[index]=entry.second;
      ++index;
    }
    return targets;
  }
public:
  explicit AreaPresetGuard(df::building_stockpilest* pile) noexcept
      :pile_(pile),fixed_(areaFixedSettings(pile)),flags_(pile->settings.flags.whole),
       stockpileFlags_(pile->stockpile_flag.whole),barrels_(pile->storage.max_barrels),
       bins_(pile->storage.max_bins),wheelbarrows_(pile->storage.max_wheelbarrows),vectors_(vectorTargets(pile)) {
    for(size_t i=0;i<fixed_.size();++i)std::copy_n(fixed_[i].values,fixed_[i].count,values_[i].begin());
  }
  ~AreaPresetGuard() {
    pile_->storage.max_barrels=barrels_;pile_->storage.max_bins=bins_;pile_->storage.max_wheelbarrows=wheelbarrows_;
    if(!committed_) {
      pile_->settings.flags.whole=flags_;pile_->stockpile_flag.whole=stockpileFlags_;
      for(size_t i=0;i<fixed_.size();++i)std::copy_n(values_[i].begin(),fixed_[i].count,fixed_[i].values);
    } else {
      // Preserve only links-only on success; import owns filter/category state.
      decltype(pile_->stockpile_flag) original{};original.whole=stockpileFlags_;
      pile_->stockpile_flag.bits.use_links_only=original.bits.use_links_only;
    }
  }
  void clear() noexcept {
    pile_->settings.flags.whole=0;
    for(const auto& entry:fixed_)std::fill_n(entry.values,entry.count,false);
  }
  void commit() noexcept {vectors_.commit();committed_=true;}
};
int areaSettingsPreset(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=1,bool unknownWork=false) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);
    field(L,"work_unknown",unknownWork);return 1;
  };
  auto* pile=Lua::GetDFObject<df::building_stockpilest>(L,1);
  if(!pile || !df::global::world)return fail("Area no longer exists");
  if(!lua_isinteger(L,2) || lua_tointeger(L,2)<1 || lua_tointeger(L,2)>19)
    return fail("Invalid stockpile preset");
  const bool none=lua_tointeger(L,2)==19;
  if(!none && (!lua_isfunction(L,3) || lua_type(L,4)!=LUA_TSTRING))
    return fail("Native stockpile preset plugin unavailable");
  std::array<size_t,78> counts{};size_t index=0;
  for(const auto& entry:areaSettingRawCounts())counts[index++]=entry.second;
  const auto total=df3d_area::settingsRawTotal(counts);
  if(!total.valid)return fail("Stockpile settings exceed 65,536 entries",79);
  // Allocate Lua call slots and intern literals before taking buffers out of
  // native settings. pcall contains Lua errors; guard destruction precedes any
  // allocating reply construction, including failed import responses.
  if(!none) {
    luaL_checkstack(L,5,"stockpile preset call");
    lua_pushvalue(L,3);lua_pushvalue(L,4);lua_pushinteger(L,pile->id);
    lua_pushliteral(L,"set");lua_pushliteral(L,"");
  }
  bool imported=false;
  try {
    AreaPresetGuard guard(pile);
    if(none) {guard.clear();imported=true;}
    else {
      const int callStatus=lua_pcall(L,4,1,0);
      imported=callStatus==LUA_OK && lua_type(L,-1)==LUA_TBOOLEAN && lua_toboolean(L,-1);
      lua_pop(L,1);
    }
    if(imported)guard.commit();
  } catch(...) {
    lua_settop(L,5);return fail("Native stockpile preset failed; previous settings restored",79,true);
  }
  if(!imported)return fail("Native stockpile preset failed; previous settings restored",79,true);
  mutated=true;
  // Count the instrumented inventory only. The transaction/native importer is
  // opaque synchronous work, not a fabricated estimate charged to read jobs.
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",79);
  field(L,"work_unknown",true);return 1;
}
int areaLocationSet(lua_State* L) {
  const auto result=[&](bool ok,const char* reason) {
    lua_newtable(L);field(L,"ok",ok);field(L,"message",reason);
    field(L,"steps",0);field(L,"work_unknown",true);return 1;
  };
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);
  const auto refreshLocation=df3d_area::locationRefreshFunction();
  if(!refreshLocation)return result(false,"");
  auto* site=lua_isnil(L,2)?nullptr:Lua::GetDFObject<df::world_site>(L,2);
  if(!zone || !df::global::world)return result(false,"Area no longer exists");
  if(!lua_isinteger(L,3) || lua_tointeger(L,3)<-1 || lua_tointeger(L,3)>INT32_MAX)
    return result(false,"invalid area location");
  const auto id=int32_t(lua_tointeger(L,3));
  const auto find=[](df::world_site* owner,int32_t key)->df::abstract_building* {
    if(!owner || key<0)return nullptr;
    for(auto* candidate:owner->buildings)if(candidate && candidate->id==key)return candidate;
    return nullptr;
  };
  if(id>=0 && (!site || df::world_site::find(site->id)!=site))return result(false,"Location no longer exists");
  auto* target=find(site,id);
  if(id>=0) {
    if(!target)return result(false,"Location no longer exists");
    using T=df::abstract_building_type;
    switch(target->getType()) {
      case T::INN_TAVERN:case T::TEMPLE:case T::LIBRARY:case T::GUILDHALL:case T::HOSPITAL:break;
      default:return result(false,"Location no longer exists");
    }
  }
  auto* old=find(df::world_site::find(zone->site_id),zone->location_id);
  auto* previous=old?old->getContents():nullptr;
  auto* next=target?target->getContents():nullptr;
  if(target && !next)return result(false,"Location no longer exists");
  // Prepare every allocation before changing either relationship. Native IDs
  // are site-local; equal IDs in different sites are distinct locations.
  df3d_area::LocationMembership prepared;
  try {
    prepared=df3d_area::prepareLocationMembership(previous?&previous->building_ids:nullptr,
        next?&next->building_ids:nullptr,zone->id);
  } catch(...) {
    return result(false,"Native location preparation failed; no locations changed");
  }
  mutated=true;
  if(prepared.removePrevious)previous->building_ids.swap(prepared.previous);
  if(prepared.assignNext)next->building_ids.swap(prepared.next);
  zone->site_id=target?site->id:-1;
  zone->location_id=id;
  try {
    // Match pinned quickfort set_location: publish identity, then recategorize.
    zone->uncategorize();zone->categorize(true);
    if(previous && previous!=next) {
      refreshLocation(previous,old->id,true);
      previous->update_timer=100;previous->update_count=0;
    }
    if(next) {
      refreshLocation(next,target->id,true);
      next->update_timer=100;next->update_count=0;
    }
  } catch(...) {
    return result(false,"Native location recategorization failed; inspect before retrying");
  }
  return result(true,"");
}
int areaLocationCreate(lua_State* L) {
  const auto result=[&](const char* reason) {
    lua_newtable(L);field(L,"ok",reason==nullptr);field(L,"message",reason?reason:"");
    field(L,"steps",0);field(L,"work_unknown",true);return 1;
  };
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);
  const auto refreshLocation=df3d_area::locationRefreshFunction();
  if(!refreshLocation)return result(""); // No native source for substitute UI copy.
  auto* site=lua_isnil(L,2)?nullptr:Lua::GetDFObject<df::world_site>(L,2);
  if(!zone || !df::global::world)return result("Area no longer exists");
  if(!site || df::world_site::find(site->id)!=site)return result("Location site no longer exists");
  for(int i=3;i<=8;++i)if(!lua_isinteger(L,i) || lua_tointeger(L,i)<-1 || lua_tointeger(L,i)>INT32_MAX)
    return result("invalid area location creation");
  const auto type=int32_t(lua_tointeger(L,3)),profession=int32_t(lua_tointeger(L,4)),
      deityKind=int32_t(lua_tointeger(L,5)),deityId=int32_t(lua_tointeger(L,6)),
      adjective=int32_t(lua_tointeger(L,7)),noun=int32_t(lua_tointeger(L,8));
  if(type<1 || type>5 || (type==4 ? profession<0 : profession!=-1) ||
      (type==2 ? deityKind<1 || deityKind>3 : deityKind!=-1) ||
      ((type==2 && deityKind>=2) ? deityId<0 : deityId!=-1))return result("invalid area location creation");
  if(type==4 && (profession>df::enum_traits<df::profession>::last_item_value ||
      !df::enum_traits<df::profession>::is_valid(profession)))return result("Profession no longer exists");
  if(type==2 && deityKind==2 && !df::historical_figure::find(deityId))return result("Deity no longer exists");
  if(type==2 && deityKind==3) {
    const auto* entity=df::historical_entity::find(deityId);
    if(!entity || entity->type!=df::historical_entity_type::Religion)return result("Religion no longer exists");
  }
  const auto& words=df::global::world->raws.language.words;
  if(adjective<0 || noun<0 || size_t(adjective)>=words.size() || size_t(noun)>=words.size() ||
      !words[adjective] || !words[noun])return result("Location name words unavailable");
  if(site->next_building_id<0 || site->next_building_id==INT32_MAX)return result("Location IDs exhausted");
  for(const auto* entry:site->buildings)
    if(!entry || entry->id==site->next_building_id)return result("Location registry changed; inspect again");
  // All owning C++ temporaries unwind before allocating the Lua response.
  // Only the final publication transfers ownership to the site registry.
  const auto create=[&]()->const char* {
    std::unique_ptr<df::abstract_building> created;
    using Name=df::language_name_type;
    Name nameType{};
    switch(type) {
      case 1:created.reset(df::allocate<df::abstract_building_inn_tavernst>());nameType=Name::FoodStore;break;
      case 2:created.reset(df::allocate<df::abstract_building_templest>());nameType=Name::Temple;break;
      case 3:created.reset(df::allocate<df::abstract_building_libraryst>());nameType=Name::Library;break;
      case 4:created.reset(df::allocate<df::abstract_building_guildhallst>());nameType=Name::Guildhall;break;
      case 5:created.reset(df::allocate<df::abstract_building_hospitalst>());nameType=Name::Hospital;break;
    }
    if(!created)return "Native location allocation failed; no location created";
    auto* contents=created->getContents();auto* nativeName=created->getName();
    if(!contents || !nativeName)return "Native location fields unavailable; no location created";
    created->id=site->next_building_id;created->site_id=site->id;created->pos=site->pos;
    for(const auto* link:site->entity_links) {
      const auto* owner=link?df::historical_entity::find(link->entity_id):nullptr;
      if(owner && owner->type==df::historical_entity_type::SiteGovernment){created->site_owner_id=owner->id;break;}
    }
    // Native new Guildhall defaults to members only; the other location kinds
    // retain their existing access policy. See protected creation reference110629.
    created->flags.set(df::abstract_building_flags::VISITORS_ALLOWED,type!=4);
    created->flags.set(df::abstract_building_flags::NON_CITIZENS_ALLOWED,type!=4);
    created->flags.set(df::abstract_building_flags::MEMBERS_ONLY,type==4);
    nativeName->has_name=true;nativeName->type=nameType;
    nativeName->parts_of_speech[df::language_name_component::FirstAdjective]=df::part_of_speech::Adjective;
    nativeName->words[df::language_name_component::FirstAdjective]=adjective;
    nativeName->words[df::language_name_component::TheX]=noun;
    if(type==1) {
      contents->desired_goblets=10;contents->desired_instruments=5;
      contents->need_more.bits.goblets=true;contents->need_more.bits.instruments=true;
    } else if(type==2) {
      auto* temple=static_cast<df::abstract_building_templest*>(created.get());
      temple->deity_data.Religion=-1;
      if(deityKind==2) {temple->deity_type=df::religious_practice_type::WORSHIP_HFID;temple->deity_data.Deity=deityId;}
      else if(deityKind==3) {temple->deity_type=df::religious_practice_type::RELIGION_ENID;temple->deity_data.Religion=deityId;}
      contents->desired_instruments=5;contents->need_more.bits.instruments=true;
    } else if(type==3) {contents->desired_paper=10;contents->need_more.bits.paper=true;}
    else if(type==4)contents->profession=df::profession(profession);
    else {
      contents->desired_splints=5;contents->desired_thread=75000;contents->desired_cloth=50000;
      contents->desired_crutches=5;contents->desired_powder=750;contents->desired_buckets=2;contents->desired_soap=750;
      contents->need_more.bits.splints=true;contents->need_more.bits.thread=true;contents->need_more.bits.cloth=true;
      contents->need_more.bits.crutches=true;contents->need_more.bits.powder=true;
      contents->need_more.bits.buckets=true;contents->need_more.bits.soap=true;
    }
    df::abstract_building_contents* previous=nullptr;
    const auto previousId=zone->location_id;
    if(const auto* previousSite=df::world_site::find(zone->site_id))
      for(auto* entry:previousSite->buildings)if(entry && entry->id==zone->location_id){previous=entry->getContents();break;}
    auto prepared=df3d_area::prepareLocationMembership(previous?&previous->building_ids:nullptr,&contents->building_ids,zone->id);
    contents->building_ids.swap(prepared.next);
    auto registry=site->buildings;registry.push_back(created.get());
    std::sort(registry.begin(),registry.end(),[](const auto* a,const auto* b){return a->id<b->id;});
    const auto locationId=created->id;
    mutated=true;
    if(prepared.removePrevious)previous->building_ids.swap(prepared.previous);
    site->buildings.swap(registry);++site->next_building_id;created.release();
    zone->site_id=site->id;zone->location_id=locationId;
    try {
      zone->uncategorize();zone->categorize(true);
      if(previous) {
        refreshLocation(previous,previousId,true);
        previous->update_timer=100;previous->update_count=0;
      }
      refreshLocation(contents,locationId,true);
      contents->update_timer=100;contents->update_count=0;
    }
    catch(...) {return "Native location created but recategorization failed; inspect before retrying";}
    return nullptr;
  };
  const char* reason=nullptr;
  try {reason=create();}
  catch(...) {reason="Native location preparation failed; no location created";}
  return result(reason);
}
// Construction receives the already validated wire request. Only native code
// owns unpublished extents/buildings; Lua sees an ID after native publication.
int areaCreate(lua_State* L) {
  uint64_t steps=0;bool unknownWork=false;int32_t createdId=-1;
  const auto execute=[&]() -> const char* {
    if(action!=m::ManagementAction::AreaCreate || request.empty())return "Area creation request required";
    const auto* a=flatbuffers::GetRoot<m::ConstructionRequest>(request.data())->area();
    if(!a || (a->operation()!=m::AreaOperation::None && a->operation()!=m::AreaOperation::Paint))
      return "Area creation request required";
    if(!df::global::world || !df::global::plotinfo || !df::global::building_next_id)return "World is not loaded";
    if(*df::global::building_next_id<0 || *df::global::building_next_id==INT32_MAX)return "Building IDs exhausted";
    const bool pile=a->kind()==m::AreaKind::Stockpile;
    const int32_t z=a->operation()==m::AreaOperation::Paint?a->paint_z():a->origin()->z();
    if(pile && a->categories()) {
      std::array<size_t,78> counts{};size_t index=0;
      for(const auto& entry:areaSettingRawCounts())counts[index++]=entry.second;
      steps+=79;
      if(!df3d_area::settingsRawTotal(counts).valid)return "Stockpile settings exceed 65,536 entries";
    }
    // Native constructAbstract assigns the next per-kind number with max+1.
    if(pile) {
      for(const auto* b:df::global::world->buildings.other.STOCKPILE) {
        ++steps;if(!b)return "Area no longer exists";
        if(b->stockpile_number==INT32_MAX)return "Stockpile numbers exhausted";
      }
    } else {
      for(const auto* b:df::global::world->buildings.other.ANY_ZONE) {
        ++steps;if(!b)return "Area no longer exists";
        if(b->zone_num==INT32_MAX)return "Zone numbers exhausted";
      }
    }
    const auto checkSite=[&](int32_t x,int32_t y) -> const char* {
      auto* block=Maps::isValidTilePos(x,y,z)?Maps::getTileBlock(x,y,z):nullptr;
      if(!block || block->designation[x&15][y&15].bits.hidden)return "Every selected tile must be visible and loaded";
      const auto& designation=block->designation[x&15][y&15];
      const auto shape=tileShape(block->tiletype[x&15][y&15]);
      if(pile) {
        using namespace df::enums::tiletype_shape;
        if(shape!=FLOOR && shape!=BOULDER && shape!=PEBBLES && shape!=STAIR_UP && shape!=STAIR_DOWN &&
            shape!=STAIR_UPDOWN && shape!=RAMP && shape!=TWIG && shape!=SAPLING && shape!=SHRUB)
          return "Stockpiles require supported floor on every tile";
        if(designation.bits.flow_size || block->occupancy[x&15][y&15].bits.building!=df::tile_building_occ::None)
          return "Stockpile site contains liquid or a building";
        if(designation.bits.pile)return "Stockpiles cannot overlap another stockpile";
      }
      // Native zones retain wall/fortification extent cells, even for a
      // zero-count area. The paint caption counts usable tiles separately.
      return nullptr;
    };
    using Extents=df3d_area::NativeExtents<df::building_extents_type>;
    df3d_area::Bounds bounds;Extents extents;uint32_t expectedTiles=0;
    if(a->operation()==m::AreaOperation::Paint) {
      std::vector<df3d_area::Span> spans;spans.reserve(a->spans()->size());
      for(const auto* span:*a->spans())spans.push_back({span->y(),span->x(),span->length()});
      const char* siteError=nullptr;
      auto plan=df3d_area::paint<Extents>(df3d_area::Bounds{},std::vector<uint8_t>{},spans,1,UINT32_MAX,
          [&](int32_t x,int32_t y,int64_t,int64_t){siteError=checkSite(x,y);return siteError==nullptr;});
      steps+=plan.steps;
      if(plan.error==df3d_area::Error::TooLarge)return "Painted area would exceed 256 per side or 32,768 tiles";
      if(plan.error==df3d_area::Error::InvalidSite)return siteError;
      if(plan.error!=df3d_area::Error::None)return "Invalid area paint geometry";
      bounds=plan.bounds;expectedTiles=plan.tiles;extents=std::move(plan.extents);
    } else {
      bounds={a->origin()->x(),a->origin()->y(),a->width(),a->height()};
      if(!df3d_area::validBounds(bounds) || bounds.width>31 || bounds.height>31)return "invalid area rectangle";
      for(int32_t y=bounds.y;y<bounds.y+bounds.height;++y)for(int32_t x=bounds.x;x<bounds.x+bounds.width;++x) {
        ++steps;if(const auto* reason=checkSite(x,y))return reason;
      }
      expectedTiles=uint32_t(bounds.width*bounds.height);
      extents.resize(expectedTiles,1);steps+=df3d_area::bulkSteps(extents.size());
    }
    const auto destroyUnpublished=[](df::building* b) {
      if(!b)return;
      delete[] b->room.extents;b->room.extents=nullptr;delete b;
    };
    unknownWork=true;
    std::unique_ptr<df::building,decltype(destroyUnpublished)> owned(
        Buildings::allocInstance(df::coord(bounds.x,bounds.y,z),
          pile?df::building_type::Stockpile:df::building_type::Civzone,pile?-1:a->zone_type()),destroyUnpublished);
    if(!owned)return "Native area allocation failed; no area created";
    auto* b=owned.get();
    b->room.x=bounds.x;b->room.y=bounds.y;b->room.width=bounds.width;b->room.height=bounds.height;
    b->room.extents=extents.release();
    if(pile) {
      auto* stock=virtual_cast<df::building_stockpilest>(b);
      if(!stock)return "Native area allocation type changed";
      stock->settings.flags.whole=0;
      for(const auto& entry:areaFixedSettings(stock))std::fill_n(entry.values,entry.count,false);
      for(const auto& entry:areaSettingVectors(stock))entry.second->clear();
    }
    unknownWork=true;
    if(!Buildings::setSize(b,df::coord2d(bounds.width,bounds.height)))return "Native area construction rejected: cannot place at this position";
    // Native setSize may clear unsuitable cells. Creation must preserve the
    // selected footprint exactly, not silently publish a reduced area.
    if(b->x1!=bounds.x || b->y1!=bounds.y || b->x2!=bounds.x+bounds.width-1 || b->y2!=bounds.y+bounds.height-1 ||
        !b->room.extents || b->room.x!=bounds.x || b->room.y!=bounds.y ||
        b->room.width!=bounds.width || b->room.height!=bounds.height)
      return "Native area construction changed the selected footprint";
    uint32_t actualTiles=0;
    for(size_t i=0;i<size_t(bounds.width)*bounds.height;++i)actualTiles+=b->room.extents[i]!=df::building_extents_type::None;
    steps+=df3d_area::bulkSteps(size_t(bounds.width)*bounds.height);
    if(actualTiles!=expectedTiles)return "Native area construction changed the selected footprint";
    // Keep refresh hints even if construction or later Lua initialization fails.
    for(int by=bounds.y>>4;by<=(bounds.y+bounds.height-1)>>4;++by)
      for(int bx=bounds.x>>4;bx<=(bounds.x+bounds.width-1)>>4;++bx)areaHints.push_back({bx<<4,by<<4,z});
    mutated=true;
    owned.release(); // constructAbstract can expose zone pointers before assigning its ID.
    try {
      if(Buildings::constructAbstract(b)){createdId=b->id;return nullptr;}
    } catch(...) {
      // Native construction does not destroy the input. Remove any partially
      // published relationships with native deconstruction, exactly once.
    }
    try {
      if(Buildings::deconstruct(b))return "Native area construction rejected: could not construct the building";
    } catch(...) {}
    // Deconstruction may itself have partly completed. Never dereference b now.
    return "Native area construction failed; cleanup uncertain; inspect before retrying";
  };
  const char* reason=nullptr;
  try {reason=execute();}
  catch(...) {reason="Native area preparation failed; no area created";}
  // All unpublished owners have unwound before Lua can allocate its response.
  lua_newtable(L);field(L,"ok",reason==nullptr);field(L,"message",reason?reason:"");
  field(L,"steps",steps);field(L,"work_unknown",unknownWork);field(L,"building_id",createdId);return 1;
}
int areaRemove(lua_State* L) {
  const auto result=[&](bool ok,const char* reason) {
    lua_newtable(L);field(L,"ok",ok);field(L,"message",reason);
    field(L,"steps",0);field(L,"work_unknown",true);return 1;
  };
  auto* target=Lua::GetDFObject<df::building>(L,1);
  if(!target || (!virtual_cast<df::building_stockpilest>(target) && !virtual_cast<df::building_civzonest>(target)))
    return result(false,"Area no longer exists");
  bool removed=false;
  try {
    // Native deconstruction owns occupancy, relationships and destruction.
    // It can mutate before failing; refresh even if no success reply survives.
    mutated=true;removed=Buildings::deconstruct(target);
  } catch(...) {
    return result(false,"Native area removal failed; inspect before retrying");
  }
  // target may already be freed. Never inspect it after this call.
  return result(removed,removed?"":"Native area removal rejected");
}
int areaSettingsFill(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=1) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);return 1;
  };
  const bool synchronous=lua_isnil(L,6);
  if(!synchronous && (!lua_isinteger(L,6) || lua_tointeger(L,6)<0 || lua_tointeger(L,6)>1536))
    return fail("Invalid settings fill budget",0);
  const uint32_t budget=synchronous?UINT32_MAX:uint32_t(lua_tointeger(L,6));
  if(!budget)return fail("Settings fill exceeds remaining step budget",0);
  auto* pile=Lua::GetDFObject<df::building_stockpilest>(L,1);
  if(!pile)return fail("Area no longer exists");
  const bool classified=lua_istable(L,3);
  if(lua_type(L,2)!=LUA_TSTRING || (!classified && lua_type(L,3)!=LUA_TSTRING) ||
      lua_type(L,4)!=LUA_TSTRING || lua_type(L,5)!=LUA_TBOOLEAN)
    return fail("Invalid settings fill arguments");
  size_t keyLength=0,membersLength=0,allowedLength=0;
  const char* key=lua_tolstring(L,2,&keyLength);
  const char* members=classified ? nullptr : lua_tolstring(L,3,&membersLength);
  const char* allowed=lua_tolstring(L,4,&allowedLength);
  if(keyLength>64)return fail("Unknown stockpile settings vector");
  if(membersLength!=allowedLength)return fail("Settings masks have different lengths");
  if(membersLength>df3d_area::kMaxRaws)return fail("Settings raws exceed 65,536 entries");
  std::vector<char>* values=nullptr;
  for(const auto& setting:areaSettingVectors(pile))
    if(std::string_view(key,keyLength)==setting.first){values=setting.second;break;}
  AreaFixedSetting fixed{};
  if(!values)for(const auto& setting:areaFixedSettings(pile))
    if(std::string_view(key,keyLength)==setting.key){fixed=setting;break;}
  if(!values && !fixed.values)return fail("Unknown stockpile settings vector");
  if(classified) {
    if(!values || !df::global::world || allowedLength)return fail("Invalid classified settings field");
    const auto getInteger=[&](const char* name,int64_t& value) {
      lua_getfield(L,3,name);const bool isInteger=lua_isinteger(L,-1);
      if(isInteger)value=lua_tointeger(L,-1);lua_pop(L,1);return isInteger;
    };
    int64_t count=0,selection=0,row=0;
    if(!getInteger("count",count) || !getInteger("selection",selection) || !getInteger("row",row) ||
        count<0 || count>df3d_area::kMaxRaws || selection<0 || selection>255 || row< -1 || row>=count)
      return fail("Invalid classified settings mask");
    const std::string_view fieldKey(key,keyLength);
    const auto counts=areaSettingRawCounts();const auto found=counts.find(fieldKey);
    if(found==counts.end() || found->second!=size_t(count))return fail("Stockpile settings layout changed");
    const auto rule=areaSettingRule(fieldKey);
    if(selection & ~areaSettingPartitions(rule))return fail("Invalid settings partition");
    const auto result=df3d_area::fillClassifiedSettings(*values,size_t(count),uint16_t(selection),int32_t(row),
        [rule](size_t i){return areaSettingPartition(rule,i);},lua_toboolean(L,5)!=0,budget);
    if(result.error==df3d_area::Error::InvalidMask)return fail("Unknown stockpile settings row",result.steps);
    if(result.error!=df3d_area::Error::None)return fail("Settings fill exceeds remaining step budget",result.steps);
    mutated=true;
    lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",result.steps);
    field(L,"resized",result.resized);return 1;
  }
  // Masks are private producer bit strings: zero excludes, any nonzero byte
  // includes. Their string lengths bound every access without a pre-scan.
  struct Mask {
    const char* bytes;size_t count;
    size_t size()const{return count;}
    bool operator[](size_t index)const{return bytes[index]!=0;}
  };
  const auto memberMask=Mask{members,membersLength},allowedMask=Mask{allowed,allowedLength};
  const bool enabled=lua_toboolean(L,5)!=0;
  const auto result=values
      ? df3d_area::fillSettings(*values,membersLength,memberMask,allowedMask,enabled,budget)
      : df3d_area::fillFixedSettings(fixed.values,fixed.count,memberMask,allowedMask,enabled,budget);
  if(result.error==df3d_area::Error::InvalidMask)
    return fail("Settings mask does not match fixed field",result.steps);
  if(result.error!=df3d_area::Error::None)
    return fail("Settings fill exceeds remaining step budget",result.steps);
  // Keep the native mutation signal even if constructing the Lua reply fails.
  mutated=true;
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",result.steps);
  field(L,"resized",result.resized);return 1;
}
// Prepare unit, zone and every affected cage vector before committing. Each
// filtered copy is one bulk pass; old native references enter holding at commit.
int areaAssignUnit(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=1) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);return 1;
  };
  if(!lua_isinteger(L,4) || lua_tointeger(L,4)<0 || lua_tointeger(L,4)>1536)return fail("Invalid assignment budget",0);
  const uint32_t budget=uint32_t(lua_tointeger(L,4));if(!budget)return fail("Unit assignment exceeds remaining step budget",0);
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);auto* unit=Lua::GetDFObject<df::unit>(L,2);
  if(!zone || !unit || !df::global::world)return fail("Area or unit no longer exists");
  if(!lua_isinteger(L,3) || lua_tointeger(L,3)<0 || lua_tointeger(L,3)>1)return fail("invalid area unit assignment");
  const bool assign=lua_tointeger(L,3)!=0;
  if(action!=m::ManagementAction::AreaUpdate || request.empty())return fail("Unit assignment request required");
  const auto* op=flatbuffers::GetRoot<m::ConstructionRequest>(request.data())->area();
  if(!op || op->operation()!=m::AreaOperation::AssignUnits || op->id()!=zone->id || op->unit_id()!=unit->id || bool(op->assign())!=assign)
    return fail("Unit assignment request required");
  if(zone->type!=df::civzone_type::Pen && zone->type!=df::civzone_type::Pond)return fail("This operation does not apply to this zone type");
  if(areaHoldingCount==areaHolding.size() || areaUnitRetired)return fail("Area retire capacity reached; restart DF3D bridge");
  using ScanError=df3d_area::AssignmentScanError;
  const auto referenceScan=df3d_area::scanZoneReferences(unit->general_refs,
      [](auto* ref){return virtual_cast<df::general_ref_building_civzone_assignedst>(ref)!=nullptr;},budget-1);
  uint32_t steps=1+referenceScan.steps;
  if(referenceScan.error==ScanError::Limit)return fail("Zone assignment list exceeds 256 entries",steps);
  if(referenceScan.error==ScanError::Budget)return fail("Unit assignment exceeds remaining step budget",steps);
  if(referenceScan.error==ScanError::Invalid)return fail("Invalid native unit references",steps);
  if(referenceScan.error==ScanError::Multiple)return fail("Multiple native zone assignments; inspect again",steps);
  auto* oldRef=referenceScan.previous?virtual_cast<df::general_ref_building_civzone_assignedst>(referenceScan.previous):nullptr;
  auto* oldZone=oldRef?virtual_cast<df::building_civzonest>(df::building::find(oldRef->building_id)):nullptr;
  if(oldRef && !oldZone)return fail("Previous zone no longer exists",steps);
  if(!assign && oldZone && oldZone!=zone)return fail("Unit assignment changed; inspect again",steps);
  if(zone->assigned_units.size()>4096 || (oldZone && oldZone->assigned_units.size()>4096))return fail("Zone exceeds 4,096 assigned units",steps);
  if(assign && !oldRef && unit->general_refs.size()==256)return fail("Zone assignment list exceeds 256 entries",steps);
  const auto cageScan=df3d_area::scanAssignedCages(df::global::world->buildings.other.CAGE,unit->id,budget-steps);
  steps+=cageScan.steps;
  if(cageScan.error==ScanError::Limit)return fail("Cage scan exceeds 256 cages",steps);
  if(cageScan.error==ScanError::Budget)return fail("Unit assignment exceeds remaining step budget",steps);
  if(cageScan.error==ScanError::Invalid)return fail("Area no longer exists",steps);
  const uint32_t prepared=df3d_area::assignmentPreparationSteps(unit->general_refs.size(),zone->assigned_units.size(),
      oldZone && oldZone!=zone?oldZone->assigned_units.size():0,cageScan.affected.size(),cageScan.entries);
  if(prepared>budget-steps)return fail("Unit assignment exceeds remaining step budget",steps);
  steps+=prepared;
  std::vector<df::general_ref*> refs;refs.reserve(unit->general_refs.size()+1);
  for(auto* ref:unit->general_refs)if(ref!=oldRef)refs.push_back(ref);
  const auto withoutUnit=[&](const auto& source,size_t extra=0) {
    return df3d_area::withoutValue(source,unit->id,extra);
  };
  auto assigned=withoutUnit(zone->assigned_units,1);
  std::vector<int32_t> previous;if(oldZone && oldZone!=zone)previous=withoutUnit(oldZone->assigned_units);
  if(assign && assigned.size()==4096)return fail("Zone exceeds 4,096 assigned units",steps);
  auto cagePlans=df3d_area::prepareCageAssignments(cageScan.affected,unit->id);
  std::unique_ptr<df::general_ref_building_civzone_assignedst> added;
  if(assign) {
    added.reset(df::allocate<df::general_ref_building_civzone_assignedst>());
    if(!added)return fail("Native zone reference unavailable",steps);
    added->building_id=zone->id;refs.push_back(added.get());assigned.push_back(unit->id);
  }
  unit->general_refs.swap(refs);zone->assigned_units.swap(assigned);
  if(oldZone && oldZone!=zone)oldZone->assigned_units.swap(previous);
  for(auto& plan:cagePlans)plan.first->assigned_units.swap(plan.second);
  added.release();mutated=true;
  if(oldRef){areaUnitRetired=oldRef;areaHolding[areaHoldingCount++]=oldRef;areaHoldingBytes+=sizeof(*oldRef);}
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",steps);
  if(oldRef){lua_newtable(L);Lua::PushDFObject(L,oldRef);lua_rawseti(L,-2,1);lua_setfield(L,-2,"retired");}
  return 1;
}
// Allocate both squad records and replacement vectors before committing. Hold
// detached records immediately so a later Lua failure cannot lose ownership.
int areaSquadUse(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=1) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);return 1;
  };
  if(!lua_isinteger(L,4) || lua_tointeger(L,4)<0 || lua_tointeger(L,4)>1536)return fail("Invalid squad budget",0);
  const auto budget=uint32_t(lua_tointeger(L,4));if(!budget)return fail("Squad use exceeds remaining step budget",0);
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);
  auto* squad=Lua::GetDFObject<df::squad>(L,2);
  if(!zone || !squad)return fail("Area or squad no longer exists");
  if(!lua_isinteger(L,3) || lua_tointeger(L,3)<0 || lua_tointeger(L,3)>15)return fail("invalid area squad use");
  const int use=int(lua_tointeger(L,3));
  if(action!=m::ManagementAction::AreaUpdate || request.empty())return fail("Squad use request required");
  const auto* op=flatbuffers::GetRoot<m::ConstructionRequest>(request.data())->area();
  if(!op || op->operation()!=m::AreaOperation::SquadUse || op->id()!=zone->id || op->squad_id()!=squad->id || op->squad_use()!=use)
    return fail("Squad use request required");
  if(zone->type!=df::civzone_type::Barracks && (zone->type!=df::civzone_type::ArcheryRange || (use&~2)))
    return fail("This operation does not apply to this zone type");
  if(areaSquadRetired[0] || areaSquadRetired[1])return fail("Only one squad removal is allowed per request");
  if(zone->squad_room_info.size()>256)return fail("Zone assignment list exceeds 256 entries");
  // Validate, copy and shift/grow each vector before committing either side.
  const uint64_t cost=5+4*((uint64_t(zone->squad_room_info.size())+256)/256)+
      4*((uint64_t(squad->rooms.size())+256)/256);
  if(cost>budget)return fail("Squad use exceeds remaining step budget");
  df::building_squad_infost* zoneRecord=nullptr;df::squad_barracks_infost* squadRecord=nullptr;
  for(auto* v:zone->squad_room_info) {
    if(!v || (v->squad_id==squad->id && zoneRecord))return fail("Invalid native squad assignments",uint32_t(cost));
    if(v->squad_id==squad->id)zoneRecord=v;
  }
  for(auto* v:squad->rooms) {
    if(!v || (v->building_id==zone->id && squadRecord))return fail("Invalid native squad assignments",uint32_t(cost));
    if(v->building_id==zone->id)squadRecord=v;
  }
  if(use && !zoneRecord && zone->squad_room_info.size()==256)return fail("Zone assignment list exceeds 256 entries",uint32_t(cost));
  if(!use && areaHolding.size()-areaHoldingCount<2)return fail("Area retire capacity reached; restart DF3D bridge",uint32_t(cost));
  auto zones=zone->squad_room_info;auto rooms=squad->rooms;
  std::unique_ptr<df::building_squad_infost> addedZone;
  std::unique_ptr<df::squad_barracks_infost> addedSquad;
  if(use) {
    if(!zoneRecord){addedZone=std::make_unique<df::building_squad_infost>();addedZone->squad_id=squad->id;zoneRecord=addedZone.get();zones.push_back(zoneRecord);}
    if(!squadRecord){addedSquad=std::make_unique<df::squad_barracks_infost>();addedSquad->building_id=zone->id;squadRecord=addedSquad.get();rooms.push_back(squadRecord);}
    zoneRecord->mode.whole=use;squadRecord->mode.whole=use;
  } else {
    if(zoneRecord)zones.erase(std::find(zones.begin(),zones.end(),zoneRecord));
    if(squadRecord)rooms.erase(std::find(rooms.begin(),rooms.end(),squadRecord));
  }
  zone->squad_room_info.swap(zones);squad->rooms.swap(rooms);
  addedZone.release();addedSquad.release();mutated=true;
  if(!use) {
    areaSquadRetired={zoneRecord,squadRecord};
    if(zoneRecord){areaHolding[areaHoldingCount++]=zoneRecord;areaHoldingBytes+=sizeof(*zoneRecord);}
    if(squadRecord){areaHolding[areaHoldingCount++]=squadRecord;areaHoldingBytes+=sizeof(*squadRecord);}
  }
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",cost);
  if(!use) {
    lua_newtable(L);int index=0;
    if(zoneRecord){Lua::PushDFObject(L,zoneRecord);lua_rawseti(L,-2,++index);}
    if(squadRecord){Lua::PushDFObject(L,squadRecord);lua_rawseti(L,-2,++index);}
    lua_setfield(L,-2,"retired");
  }
  return 1;
}
// Lua checks the pile revision and reserves reply-snapshot work first. Native
// virtual methods include every supported workshop without guessing its type.
int areaLink(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=1) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);return 1;
  };
  if(!lua_isinteger(L,5) || lua_tointeger(L,5)<0 || lua_tointeger(L,5)>1536)return fail("Invalid link budget",0);
  const auto budget=uint32_t(lua_tointeger(L,5));
  if(!budget)return fail("Link exceeds remaining step budget",0);
  auto* workshop=Lua::GetDFObject<df::building>(L,1);
  auto* pile=Lua::GetDFObject<df::building_stockpilest>(L,2);
  if(!workshop || !pile)return fail("Area no longer exists");
  if(action!=m::ManagementAction::AreaLink || request.empty())return fail("Area link request required");
  const auto* op=flatbuffers::GetRoot<m::ConstructionRequest>(request.data())->area();
  if(!op || (op->operation()!=m::AreaOperation::WorkshopLink && op->operation()!=m::AreaOperation::None) ||
      op->id()!=workshop->id || op->link_id()!=pile->id || workshop->id==pile->id)
    return fail("Area link request required");
  auto* firstPile=virtual_cast<df::building_stockpilest>(workshop);
  const bool legacy=op->operation()==m::AreaOperation::None;
  if(legacy && !firstPile)return fail("Links require two different stockpiles");
  if(!legacy && !workshop->canLinkToStockpile())return fail("This workshop cannot link to stockpiles");
  auto* links=legacy?&firstPile->links:workshop->getStockpileLinks();
  if(!links)return fail("This workshop cannot link to stockpiles");
  if(lua_type(L,3)!=LUA_TBOOLEAN || lua_type(L,4)!=LUA_TBOOLEAN)return fail("Invalid workshop link arguments");
  const bool give=lua_toboolean(L,3)!=0,unlink=lua_toboolean(L,4)!=0;
  if(give!=op->give() || unlink!=op->unlink())return fail("Workshop link request changed");
  auto& endpoint=give?links->give_to_pile:links->take_from_pile;
  df3d_area::LinkResult result;
  if(legacy) {
    auto& reverse=give?pile->links.take_from_pile:pile->links.give_to_pile;
    result=df3d_area::editLinks(endpoint,reverse,pile,firstPile,unlink,budget);
  } else {
    auto& reverse=give?pile->links.take_from_workshop:pile->links.give_to_workshop;
    result=df3d_area::editLinks(endpoint,reverse,pile,workshop,unlink,budget);
  }
  if(result.error==df3d_area::LinkError::Limit)return fail("Link limit reached; no endpoints changed",result.steps);
  if(result.error==df3d_area::LinkError::Budget)return fail("Link exceeds remaining step budget",result.steps);
  if(result.error!=df3d_area::LinkError::None)return fail("Invalid native link endpoints; inspect again",result.steps);
  mutated=true;
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",result.steps);return 1;
}
// Repaint owns all preflight and allocation before committing any native field.
// Lua checks request identity/revision and reserves reply-snapshot work first.
int areaRepaint(lua_State* L) {
  bool unknownWork=false;
  const auto fail=[&](const char* reason,uint32_t steps=1) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);field(L,"work_unknown",unknownWork);return 1;
  };
  const bool synchronous=lua_isnil(L,4);
  if(!synchronous && (!lua_isinteger(L,4) || lua_tointeger(L,4)<0 || lua_tointeger(L,4)>1536))
    return fail("Invalid repaint budget",0);
  const uint32_t budget=synchronous?UINT32_MAX:uint32_t(lua_tointeger(L,4));
  if(!budget)return fail("Paint exceeds remaining step budget",0);
  auto* b=Lua::GetDFObject<df::building>(L,1);
  if(!b)return fail("Area no longer exists");
  if((action!=m::ManagementAction::AreaCreate && action!=m::ManagementAction::AreaUpdate) || request.empty())
    return fail("Repaint requires an area Paint request");
  const auto* operation=flatbuffers::GetRoot<m::ConstructionRequest>(request.data())->area();
  if(!operation || operation->operation()!=m::AreaOperation::Paint)return fail("Repaint requires an area Paint request");
  auto* pile=virtual_cast<df::building_stockpilest>(b);
  auto* zone=virtual_cast<df::building_civzonest>(b);
  if(!pile && !zone)return fail("Area no longer exists");
  if(areaHoldingCount==areaHolding.size())return fail("Area retire capacity reached; restart DF3D bridge");
  if(!lua_isinteger(L,3) || lua_tointeger(L,3)<1 || lua_tointeger(L,3)>3 || !lua_istable(L,2))
    return fail("Invalid paint arguments");
  const auto mode=uint8_t(lua_tointeger(L,3));
  const size_t count=lua_rawlen(L,2);
  if(!count || count>df3d_area::kMaxSpans)return fail("Paint requires 1..32768 spans");
  if(count+1>budget)return fail("Paint exceeds remaining step budget");
  if(areaPaintCommitted)return fail("Only one paint commit is allowed per request");
  std::vector<df3d_area::Span> spans;spans.reserve(count);uint32_t requested=0;
  for(size_t i=1;i<=count;++i) {
    lua_rawgeti(L,2,i);
    if(!lua_istable(L,-1)){lua_pop(L,1);return fail("Invalid paint span",uint32_t(i));}
    df3d_area::Span span;int32_t* fields[]={&span.y,&span.x,&span.length};
    const char* keys[]={"y","x","length"};bool spanValid=true;
    for(int k=0;k<3;++k) {
      lua_getfield(L,-1,keys[k]);
      spanValid=spanValid && lua_isinteger(L,-1) && lua_tointeger(L,-1)>=0 && lua_tointeger(L,-1)<=32768;
      if(spanValid)*fields[k]=int32_t(lua_tointeger(L,-1));lua_pop(L,1);
    }
    lua_pop(L,1);
    if(!spanValid || !span.length || span.x+span.length>32768 || span.y>32767)
      return fail("Invalid paint span",uint32_t(i));
    requested+=uint32_t(span.length);
    if(requested>df3d_area::kMaxPaintTiles)return fail("Paint exceeds 32768 tiles",uint32_t(i));
    spans.push_back(span);
  }
  const int64_t width=int64_t(b->x2)-b->x1+1,height=int64_t(b->y2)-b->y1+1;
  if(width<1 || height<1 || width>256 || height>256 || b->z<0 || b->z>32767)
    return fail("Invalid area extents",uint32_t(count));
  const df3d_area::Bounds before{b->x1,b->y1,int32_t(width),int32_t(height)};
  if(!df3d_area::validBounds(before) || (b->room.extents &&
      (b->room.width<1 || b->room.height<1 || b->room.width>256 || b->room.height>256 ||
       int64_t(b->room.width)*b->room.height>32768)))
    return fail("Invalid area extents",uint32_t(count));
  if(zone && !df::global::world)return fail("World is not loaded",uint32_t(count));
  // Site checks run in the planner's counted tile visit. Native occupancy is a
  // second pass over at most requested tiles; reserve it before allocating.
  const uint32_t reserved=requested+(mode==3?uint32_t(width*height):0)+1;
  if(reserved>=budget || count+reserved>=budget)return fail("Paint exceeds remaining step budget",uint32_t(count));
  struct ExtentsView {
    const df::building* b;size_t width,height;
    size_t size()const{return width*height;}
    df::building_extents_type operator[](size_t index)const {
      if(!b->room.extents)return df::building_extents_type::Stockpile;
      const int64_t x=int64_t(b->x1)+int64_t(index%width)-b->room.x,y=int64_t(b->y1)+int64_t(index/width)-b->room.y;
      return x<0 || y<0 || x>=b->room.width || y>=b->room.height ? df::building_extents_type::None :
          b->room.extents[size_t(y)*b->room.width+size_t(x)];
    }
  };
  struct Change {df::map_block* block;int32_t x,y;bool remove;};
  std::vector<Change> changes;changes.reserve(requested+(mode==3?size_t(width)*height:0));
  const char* siteError="Invalid paint site";
  auto plan=df3d_area::paint<df3d_area::NativeExtents<df::building_extents_type>>(
      before,ExtentsView{b,size_t(width),size_t(height)},spans,mode,budget-reserved,
      [&](int32_t x,int32_t y,int64_t prior,int64_t after) {
    auto* block=Maps::isValidTilePos(x,y,b->z)?Maps::getTileBlock(x,y,b->z):nullptr;
    if(!block || block->designation[x&15][y&15].bits.hidden) {
      siteError="Every selected tile must be visible and loaded";return false;
    }
    const auto& designation=block->designation[x&15][y&15];
    const auto shape=tileShape(block->tiletype[x&15][y&15]);
    // Retained cells already belong to this area. Its own native occupancy
    // must not make a footprint replacement fail placement validation.
    if(after!=0 && prior==0 && pile) {
      using namespace df::enums::tiletype_shape;
      if(shape!=FLOOR && shape!=BOULDER && shape!=PEBBLES && shape!=STAIR_UP && shape!=STAIR_DOWN &&
          shape!=STAIR_UPDOWN && shape!=RAMP && shape!=TWIG && shape!=SAPLING && shape!=SHRUB) {
        siteError="Stockpiles require supported floor on every tile";return false;
      }
      if(designation.bits.flow_size || block->occupancy[x&15][y&15].bits.building!=df::tile_building_occ::None) {
        siteError="Stockpile site contains liquid or a building";return false;
      }
      if(designation.bits.pile && !prior){siteError="Stockpiles cannot overlap another stockpile";return false;}
    }
    // Zone extents may include walls and fortifications, as native paint does.
    if(prior!=after)changes.push_back({block,x,y,after==0});
    return true;
  },zone!=nullptr);
  const uint32_t spent=plan.steps;
  if(plan.error!=df3d_area::Error::None) {
    switch(plan.error) {
      case df3d_area::Error::Empty:return fail("Erase would remove the whole area; use Remove",spent);
      case df3d_area::Error::TooLarge:return fail("Painted area would exceed 256 per side or 32,768 tiles",spent);
      case df3d_area::Error::InvalidSite:return fail(siteError,spent);
      case df3d_area::Error::Budget:return fail("Paint exceeds remaining step budget",spent);
      default:return fail("Invalid area paint geometry",spent);
    }
  }
  if(plan.erased && pile && (pile->storage.max_barrels>int32_t(plan.tiles) || pile->storage.max_bins>int32_t(plan.tiles) ||
      pile->storage.max_wheelbarrows>int32_t(plan.tiles)-1))
    return fail("Container limits exceed usable stockpile tiles",spent);
  if(changes.empty()) {
    lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",spent);
    field(L,"tile_count",plan.tiles);return 1;
  }
  // Allocate refresh hints before committing. Coalesce by map block so a
  // full-area paint does not enqueue one streaming invalidation per tile.
  auto nextHints=areaHints;
  std::set<std::pair<int32_t,int32_t>> changedBlocks;
  for(const auto& change:changes)changedBlocks.emplace(change.x>>4,change.y>>4);
  for(const auto& block:changedBlocks)nextHints.push_back({block.first<<4,block.second<<4,b->z});
  auto* retired=b->room.extents;
  const size_t retiredBytes=retired?size_t(b->room.width)*b->room.height*sizeof(*retired):0;
  // Retain before returning to Lua: an exception while preparing its reply
  // must not bypass capacity accounting for an already committed native edit.
  areaPaintCommitted=true;mutated=true;areaPaintRetired=retired;
  if(retired){areaHolding[areaHoldingCount++]=retired;areaHoldingBytes+=retiredBytes;}
  b->room.extents=plan.extents.release();b->room.x=b->x1=plan.bounds.x;b->room.y=b->y1=plan.bounds.y;
  b->room.width=plan.bounds.width;b->room.height=plan.bounds.height;
  b->x2=b->x1+plan.bounds.width-1;b->y2=b->y1+plan.bounds.height-1;
  b->centerx=b->x1+plan.bounds.width/2;b->centery=b->y1+plan.bounds.height/2;
  areaHints.swap(nextHints);
  // Pinned Buildings.cpp markBuildingTiles semantics on changed cells only.
  // Civzones do not own occupancy; overlapping actual buildings stay intact.
  const bool occupancy=b->isSettingOccupancy();
  const bool complete=b->getBuildStage()>=b->getMaxBuildStage();
  for(const auto& change:changes) {
    if(!occupancy)continue;
    auto& designation=change.block->designation[change.x&15][change.y&15];
    designation.bits.pile=pile && !change.remove;
    if(!change.remove)designation.bits.dig=df::tile_dig_designation::No;
    if(complete && !change.remove)b->updateOccupancy(change.x,change.y);
    else {
      change.block->occupancy[change.x&15][change.y&15].bits.building=
          change.remove?df::tile_building_occ::None:df::tile_building_occ::Planned;
      if(change.remove){change.block->flags.bits.update_liquid=true;change.block->flags.bits.update_liquid_twice=true;}
    }
  }
  if(zone) {
    unknownWork=true;
    try {Buildings::notifyCivzoneModified(zone);}
    catch(...) {return fail("Native zone notification failed; inspect before retrying",spent+uint32_t(changes.size())+1);}
  }
  lua_newtable(L);field(L,"ok",true);field(L,"message","");
  field(L,"steps",spent+uint32_t(changes.size())+1);field(L,"tile_count",plan.tiles);field(L,"work_unknown",unknownWork);
  if(retired) {
    lua_createtable(L,1,0);lua_pushlightuserdata(L,retired);lua_rawseti(L,-2,1);lua_setfield(L,-2,"retired");
    field(L,"retired_bytes",retiredBytes);
  }
  return 1;
}
// Native area observations are one bounded pass. The Lua dispatcher owns the
// operation/epoch checks and debits the returned work against its inline slice.
int areaSnapshot(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=1) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);return 1;
  };
  auto* b=Lua::GetDFObject<df::building>(L,1);
  const bool visibility=lua_toboolean(L,2)!=0;
  const bool synchronous=lua_isnil(L,3);
  if(!synchronous && (!lua_isinteger(L,3) || lua_tointeger(L,3)<0 || lua_tointeger(L,3)>1536))
    return fail("Invalid area snapshot budget",0);
  const uint32_t budget=synchronous?UINT32_MAX:uint32_t(lua_tointeger(L,3));
  if(!budget)return fail("Area snapshot exceeds remaining step budget",0);
  if(!b)return fail("Area no longer exists");
  auto* pile=virtual_cast<df::building_stockpilest>(b);
  auto* zone=virtual_cast<df::building_civzonest>(b);
  if(!pile && !zone)return fail("Area no longer exists");
  const int64_t width=int64_t(b->x2)-b->x1+1,height=int64_t(b->y2)-b->y1+1;
  if(b->x1<0 || b->y1<0 || b->z<0 || b->x2>32767 || b->y2>32767 || b->z>32767 || width<1 || height<1 || width>256 || height>256 || width*height>32768 ||
      (b->room.extents && (b->room.width<1 || b->room.height<1 || b->room.width>256 || b->room.height>256 || int64_t(b->room.width)*b->room.height>32768)))
    return fail("This area exceeds the bounded extent inspector (256 per side, 32768 tiles)");
  size_t members=0;
  std::vector<size_t> settingsSizes;
  size_t settingsReplyGrowth=0;
  if(pile) {
    if(pile->links.give_to_pile.size()>1024 || pile->links.take_from_pile.size()>1024 ||
        pile->links.give_to_workshop.size()>1024 || pile->links.take_from_workshop.size()>1024)
      return fail("This pile exceeds the bounded link inspector (1024 per direction)");
    members=pile->links.give_to_pile.size()+pile->links.take_from_pile.size()+
        pile->links.give_to_workshop.size()+pile->links.take_from_workshop.size();
    // Settings contents are command preconditions, including same-size external
    // edits while paused. Count all hashed elements before reading any of them.
    const auto rawCounts=areaSettingRawCounts();
    for(const auto& setting:areaSettingVectors(pile)) {
      const size_t size=setting.second->size();
      if(size>df3d_area::kMaxRaws)return fail("Stockpile settings vector exceeds 65,536 entries");
      settingsSizes.push_back(size);members+=size;
      const auto raw=rawCounts.find(setting.first);
      if(raw!=rawCounts.end() && raw->second>size)settingsReplyGrowth+=raw->second-size;
    }
    for(const auto& setting:areaFixedSettings(pile))members+=setting.count;
    members+=settingsSizes.size();
  } else {
    if(zone->assigned_units.size()>4096)return fail("Zone exceeds 4,096 assigned units");
    if(zone->squad_room_info.size()>256)return fail("Zone assignment list exceeds 256 entries");
    members=zone->assigned_units.size()+zone->squad_room_info.size();
  }
  if(b->name.size()>512)return fail("Area name exceeds bounded snapshot");
  const size_t cells=size_t(width*height);
  // Seven fixed groups plus one step per 256 scalar/extent/list entries.
  // Reserve a non-visibility reply after any settings vector grows to raw size.
  const uint32_t steps=7+df3d_area::bulkSteps(cells+members+b->name.size())+
      (visibility?df3d_area::bulkSteps(cells):0);
  if(steps>budget)return fail("Area snapshot exceeds remaining step budget");
  df3d_area::Revision hash;
  hash.add(b->id);hash.add(pile?0:1);hash.add(b->x1);hash.add(b->x2);
  hash.add(b->y1);hash.add(b->y2);hash.add(b->z);hash.add(b->site_id);hash.add(b->location_id);
  hash.add(b->room.x);hash.add(b->room.y);hash.add(b->room.width);hash.add(b->room.height);
  hash.add(b->name.size());for(unsigned char c:b->name)hash.add(c);
  std::vector<uint8_t> extents(cells),visible;
  if(visibility)visible.resize(cells,0);
  uint32_t tiles=0,visibleTiles=0;
  for(int y=b->y1;y<=b->y2;++y)for(int x=b->x1;x<=b->x2;++x) {
    const size_t index=size_t(y-b->y1)*size_t(width)+x-b->x1;
    int raw=1;
    if(b->room.extents) {
      const int64_t rx=int64_t(x)-b->room.x,ry=int64_t(y)-b->room.y;
      raw=rx<0 || ry<0 || rx>=b->room.width || ry>=b->room.height ? 0 : int(b->room.extents[size_t(ry)*b->room.width+size_t(rx)]);
    }
    hash.add(raw);extents[index]=raw!=0;tiles+=raw!=0;
    if(visibility && raw) {
      const auto* block=Maps::getTileBlock(x,y,b->z);
      visible[index]=block && !block->designation[x&15][y&15].bits.hidden;
      visibleTiles+=visible[index]!=0;
    }
  }
  // Native Paint can retain a zero-cell zone until exit. Its allocated bounds
  // remain the redraw target. Permit observing it only when that entire empty
  // footprint is loaded and revealed; do not fabricate visible occupied cells.
  bool emptyZoneVisible=visibility && zone && tiles==0;
  if(emptyZoneVisible)for(int y=b->y1;y<=b->y2 && emptyZoneVisible;++y)for(int x=b->x1;x<=b->x2;++x) {
    const auto* block=Maps::getTileBlock(x,y,b->z);
    if(!block || block->designation[x&15][y&15].bits.hidden){emptyZoneVisible=false;break;}
  }
  std::vector<int32_t> gives,takes,givesWorkshops,takesWorkshops;
  const auto links=[&](const auto& source,auto& ids) {
    hash.add(source.size());
    for(const auto* target:source){if(!target)return false;ids.push_back(target->id);hash.add(target->id);}
    return true;
  };
  if(pile) {
    for(auto size:settingsSizes)hash.add(size);
    for(const auto& setting:areaSettingVectors(pile))
      for(unsigned char value:*setting.second)hash.add(value);
    for(const auto& setting:areaFixedSettings(pile))
      for(size_t i=0;i<setting.count;++i)hash.add(setting.values[i]);
    hash.add(pile->settings.flags.whole);hash.add(pile->settings.misc.allow_organic);hash.add(pile->settings.misc.allow_inorganic);
    hash.add(pile->storage.max_barrels);hash.add(pile->storage.max_bins);hash.add(pile->storage.max_wheelbarrows);
    hash.add(pile->stockpile_flag.bits.use_links_only);
    if(!links(pile->links.give_to_pile,gives) || !links(pile->links.take_from_pile,takes) ||
        !links(pile->links.give_to_workshop,givesWorkshops) || !links(pile->links.take_from_workshop,takesWorkshops))
      return fail("Area no longer exists",steps);
  } else {
    hash.add(zone->type);hash.add(zone->spec_sub_flag.whole);hash.add(zone->assigned_unit_id);
    hash.add(zone->zone_settings.whole.i1);hash.add(zone->zone_settings.whole.i2);
    hash.add(zone->assigned_units.size());for(auto id:zone->assigned_units)hash.add(id);
    hash.add(zone->squad_room_info.size());for(const auto* squad:zone->squad_room_info) {
      if(!squad)return fail("Area no longer exists",steps);
      hash.add(squad->squad_id);hash.add(squad->mode.whole);
    }
  }
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",steps);
  field(L,"reply_steps",pile?7+df3d_area::bulkSteps(32768+4096+512+members+settingsReplyGrowth):154);
  field(L,"revision",hash.finish());field(L,"tile_count",tiles);field(L,"visible_count",visibleTiles);
  field(L,"has_visibility",visibility);field(L,"visible",visibleTiles!=0 || emptyZoneVisible);
  field(L,"x",b->x1);field(L,"y",b->y1);field(L,"z",b->z);field(L,"width",width);field(L,"height",height);
  const auto array=[&](const char* key,const auto& values) {
    lua_createtable(L,int(values.size()),0);int index=0;
    for(auto value:values){lua_pushinteger(L,lua_Integer(value));lua_rawseti(L,-2,++index);}lua_setfield(L,-2,key);
  };
  array("extents",extents);if(visibility)array("visible_mask",visible);
  array("gives",gives);array("takes",takes);array("gives_workshops",givesWorkshops);array("takes_workshops",takesWorkshops);
  if(zone)array("assigned_units",zone->assigned_units);
  return 1;
}
// Restore temporarily borrowed input before dropping a pending native adapter.

void prepareRoomEffects(const df3d_area::Bounds& bounds,int32_t z) {
  // Storage is acquired during native preflight, before any room is published
  // or deleted. Extra hints from a rejected preflight are harmless.
  for(int by=bounds.y>>4;by<=(bounds.y+bounds.height-1)>>4;++by)
    for(int bx=bounds.x>>4;bx<=(bounds.x+bounds.width-1)>>4;++bx)
      areaHints.push_back({bx<<4,by<<4,z});
}
void runRooms(const m::AreaRequest& a) {
  using namespace df3d_area;
  const RoomUndoScope scope{epoch,client,a.interaction_id()};
  areaPage.operation=a.operation();areaPage.interactionId=a.interaction_id();
  areaPage.roomOutcome=m::AreaRoomOutcome::Rejected;
  message.clear();
  try {
    if(a.operation()==m::AreaOperation::MultiFinish) {
      roomUndo.finish(scope); // late/foreign Done cannot retire a newer interaction
      areaPage.roomOutcome=m::AreaRoomOutcome::Completed;
    } else if(a.operation()==m::AreaOperation::MultiUndo) {
      const auto result=undoNativeRooms(roomUndo,scope,a.undo_token(),prepareRoomEffects);
      areaPage.roomsRemoved=uint32_t(result.removed);
      switch(result.status) {
        case RoomUndoStatus::Completed:areaPage.roomOutcome=m::AreaRoomOutcome::Completed;break;
        case RoomUndoStatus::Rejected:areaPage.roomOutcome=m::AreaRoomOutcome::Rejected;break;
        case RoomUndoStatus::Stale:areaPage.roomOutcome=m::AreaRoomOutcome::Stale;break;
        case RoomUndoStatus::Unknown:areaPage.roomOutcome=m::AreaRoomOutcome::Unknown;break;
      }
      if(result.removed || result.status==RoomUndoStatus::Unknown)mutated=true;
    } else {
      // A new selection owns the latest history, even if observation fails.
      // Native empty/all-in-use/all-unenclosed completions also replace it.
      roomUndo.clear();
      auto result=createNativeRooms(RoomFurniture(a.room_furniture()),
        {a.origin()->x(),a.origin()->y(),a.width(),a.height()},a.origin()->z(),prepareRoomEffects);
      if(result.status!=RoomCreationStatus::NotStarted && !result.plan.rooms.empty())mutated=true;
      if(result.status==RoomCreationStatus::Committed) {
        const auto installed=roomUndo.replace(scope,std::move(result.undoTargets));
        if(installed.accepted) {
          areaPage.undoToken=installed.token;areaPage.roomsCreated=uint32_t(result.createdIds.size());
          areaPage.roomsDormitories=uint32_t(std::count_if(result.plan.rooms.begin(),result.plan.rooms.end(),
            [](const auto& room){return room.dormitory;}));
          areaPage.roomsInUse=result.plan.rejectedInUse;areaPage.roomsUnenclosed=result.plan.rejectedUnenclosed;
          areaPage.roomOutcome=m::AreaRoomOutcome::Completed;
        } else areaPage.roomOutcome=m::AreaRoomOutcome::Unknown;
      } else if(result.status==RoomCreationStatus::Unknown)areaPage.roomOutcome=m::AreaRoomOutcome::Unknown;
    }
  } catch(...) {
    // A thrown native mutation may already have taken effect. Never retain
    // deletion authority or report a replayable rejection for that outcome.
    roomUndo.clear();mutated=true;areaPage.undoToken=0;
    areaPage.roomOutcome=m::AreaRoomOutcome::Unknown;
  }
  status=areaPage.roomOutcome==m::AreaRoomOutcome::Completed?m::ManagementStatus::Ok:m::ManagementStatus::Rejected;
  publish();
}
void runPaintCounts(const m::AreaRequest& a) {
  message.clear();
  areaPage.operation=m::AreaOperation::PaintCounts;
  areaPage.countGeneration=a.count_generation();
  areaPage.capturedTick=df::global::world?df::global::world->frame_counter:-1;
  std::vector<df3d_area::Span> draft,preview;
  if(a.spans())for(const auto* s:*a.spans())draft.push_back({s->y(),s->x(),s->length()});
  if(const auto* p=a.paint_preview())for(int32_t y=p->y();y<int32_t(p->y())+p->height();++y)
    preview.push_back({y,p->x(),p->width()});
  const auto counts=df3d_area::observeNativePaintCounts(a.zone_type(),a.paint_z(),draft,preview);
  status=counts.valid?m::ManagementStatus::Ok:m::ManagementStatus::Rejected;
  areaPage.paintedCount=counts.painted;areaPage.previewCount=counts.preview;
  publish();
}
void run(color_ostream& out) {
  areaPaintRetired=nullptr;areaPaintCommitted=false;areaSquadRetired={};areaUnitRetired=nullptr;
  const auto* r = flatbuffers::GetRoot<m::ConstructionRequest>(request.data());
  // Read and edit share the same epoch/target/dependency-bound receipt.
  static df3d_area::LocationStaffCandidateSnapshot staffSnapshot;
  if(r->area() && r->area()->operation()==m::AreaOperation::LocationStaffCandidates) {
    const auto& a=*r->area();message.clear();areaPage.operation=a.operation();
    areaPage.locationCursor=a.cursor();areaPage.capturedTick=df::global::world?df::global::world->frame_counter:-1;
    const df3d_area::LocationStaffTarget target{a.location_site_id(),a.location_id(),a.occupation_id()};
    staffSnapshot.observe(epoch,target,df3d_area::observeNativeLocationStaffCandidates(target.siteId,target.locationId,target.occupationId));
    auto page=staffSnapshot.page(epoch,target,a.cursor(),a.expected_list_revision());
    status=m::ManagementStatus::Rejected;
    size_t bytes=128;bool bounded=page.rows.size()<=128;
    for(const auto& row:page.rows) {
      if(row.name.size()>2048 || row.baseName.size()>2048 || row.professionName.size()>2048 || row.skills.size()>10) {bounded=false;break;}
      bytes+=128+row.name.size()+row.baseName.size()+row.professionName.size()+48*row.skills.size();
    }
    if(page.status==df3d_area::LocationPageStatus::Ready && bounded && bytes<=224*1024) {
      areaPage.staffCandidates=std::move(page);status=m::ManagementStatus::Ok;
    }
    publish();return;
  }
  if(r->area() && (r->area()->operation()==m::AreaOperation::LocationDetails || r->area()->operation()==m::AreaOperation::LocationOpen || r->area()->operation()==m::AreaOperation::LocationAccess || r->area()->operation()==m::AreaOperation::LocationStaffEdit)) {
    const auto& a=*r->area();message.clear();areaPage.operation=a.operation();
    areaPage.capturedTick=df::global::world?df::global::world->frame_counter:-1;
    const bool entry=a.operation()==m::AreaOperation::LocationOpen;
    const bool access=a.operation()==m::AreaOperation::LocationAccess;
    const bool staffEdit=a.operation()==m::AreaOperation::LocationStaffEdit;
    const auto publishable=[](const df3d_area::LocationDetailsCore& d,uint64_t additionalRows=0) {
      uint64_t namesBytes=0;
      if(d.affiliation) {if(d.affiliation->name.size()>512)return false;namesBytes+=64+d.affiliation->name.size();}
      if(d.staff)for(const auto& row:d.staff->rows)if(row.names) {
        if(row.names->positionName.size()>512 || row.names->holderName.size()>512)return false;
        namesBytes+=64+row.names->positionName.size()+row.names->holderName.size();
      }
      return d.name.size()<=512 && d.profession>=-1 && d.profession<=511 && d.tier>=0 && d.appraisal>=-1 && d.writtenObjects>=0 && d.danceFloorX>=0 && d.danceFloorY>=0 &&
          512+uint64_t(d.name.size())+4*uint64_t(d.zoneIds.size())+(d.staff?128*uint64_t(d.staff->rows.size())+4*uint64_t(d.staff->missingRoles.size()):0)+192*additionalRows+namesBytes<=224*1024 &&
          std::none_of(d.zoneIds.begin(),d.zoneIds.end(),[](auto id){return id<0;}) &&
          std::adjacent_find(d.zoneIds.begin(),d.zoneIds.end(),std::greater_equal<int32_t>{})==d.zoneIds.end();
    };
    auto details=df3d_area::observeNativeLocationDetailsCore(a.location_site_id(),a.location_id());
    if(details && !publishable(*details,(entry || staffEdit) && details->staff?details->staff->missingRoles.size()+1:0))details.reset();
    if(staffEdit) {
      areaPage.locationEditOutcome=m::LocationEditOutcome::Rejected;
      const df3d_area::LocationStaffTarget target{a.location_site_id(),a.location_id(),a.occupation_id()};
      staffSnapshot.observe(epoch,target,df3d_area::observeNativeLocationStaffCandidates(target.siteId,target.locationId,target.occupationId));
      const auto receipt=staffSnapshot.page(epoch,target,0,a.expected_list_revision());
      if(receipt.status==df3d_area::LocationPageStatus::Stale ||
          (details && df3d_area::locationDetailsRevision(*details)!=a.expected_revision())) {
        areaPage.locationEditOutcome=m::LocationEditOutcome::Stale;details.reset();
      } else if(details && receipt.status==df3d_area::LocationPageStatus::Ready) {
        details.reset();mutated=true;areaPage.locationEditOutcome=m::LocationEditOutcome::Unknown;
        try {
          const auto outcome=df3d_area::editNativeLocationStaff(target.siteId,target.locationId,target.occupationId,a.unit_id());
          if(outcome==df3d_area::LocationStaffEditOutcome::Rejected || outcome==df3d_area::LocationStaffEditOutcome::Unavailable) {
            mutated=false;areaPage.locationEditOutcome=m::LocationEditOutcome::Rejected;
          } else {
            // Applied and uncertain edits consume the receipt even when the
            // refreshed Details cannot be published. Neither authorizes replay.
            staffSnapshot.invalidate();
            if(outcome==df3d_area::LocationStaffEditOutcome::Applied) {
              details=df3d_area::observeNativeLocationDetailsCore(target.siteId,target.locationId);
              if(details && publishable(*details))areaPage.locationEditOutcome=m::LocationEditOutcome::Completed;
              else details.reset();
            }
          }
        } catch(...) {staffSnapshot.invalidate();details.reset();}
      } else details.reset();
    } else if(access) {
      areaPage.locationEditOutcome=m::LocationEditOutcome::Rejected;
      if(details && df3d_area::locationDetailsRevision(*details)!=a.expected_revision()) {
        areaPage.locationEditOutcome=m::LocationEditOutcome::Stale;details.reset();
      } else if(details) {
        details.reset();mutated=true;areaPage.locationEditOutcome=m::LocationEditOutcome::Unknown;
        try {
          const auto outcome=df3d_area::setNativeLocationAccess(a.location_site_id(),a.location_id(),
              a.expected_revision(),static_cast<df3d_area::LocationAccess>(a.value()));
          if(outcome!=df3d_area::LocationAccessOutcome::Completed) {
            mutated=false;areaPage.locationEditOutcome=outcome==df3d_area::LocationAccessOutcome::Stale?
                m::LocationEditOutcome::Stale:m::LocationEditOutcome::Rejected;
          } else {
            details=df3d_area::observeNativeLocationDetailsCore(a.location_site_id(),a.location_id());
            if(details && publishable(*details))areaPage.locationEditOutcome=m::LocationEditOutcome::Completed;
            else details.reset();
          }
        } catch(...) {details.reset();}
      }
    } else if(entry) {
      areaPage.locationEntryOutcome=m::LocationEntryOutcome::Rejected;
      if(details && df3d_area::locationDetailsRevision(*details)!=a.expected_revision()) {
        areaPage.locationEntryOutcome=m::LocationEntryOutcome::Stale;details.reset();
      } else if(details) {
        details.reset();
        // After refresh begins, failures can represent partial native effects.
        // Never turn those into a replayable clean refusal.
        areaPage.locationEntryOutcome=m::LocationEntryOutcome::Unknown;
        mutated=true;
        try {
          if(!df3d_area::refreshNativeLocationDetailsCaches(a.location_site_id(),a.location_id())) {
            mutated=false;areaPage.locationEntryOutcome=m::LocationEntryOutcome::Rejected;
          } else if(df3d_area::prepareNativeLocationStaff(a.location_site_id(),a.location_id())) {
            details=df3d_area::observeNativeLocationDetailsCore(a.location_site_id(),a.location_id());
            if(details && publishable(*details))areaPage.locationEntryOutcome=m::LocationEntryOutcome::Completed;
            else details.reset();
          }
        } catch(...) {details.reset();}
      }
    }
    areaPage.locationDetails=std::move(details);
    status=areaPage.locationDetails?m::ManagementStatus::Ok:m::ManagementStatus::Rejected;
    publish();return;
  }
  if(r->area() && r->area()->operation()==m::AreaOperation::LocationChoices) {
    static df3d_area::LocationCatalogSnapshot<df3d_area::ReligiousPractice> religions;
    static df3d_area::LocationCatalogSnapshot<df3d_area::GuildWorkers> guilds;
    const auto& a=*r->area();message.clear();areaPage.operation=m::AreaOperation::LocationChoices;
    areaPage.locationCursor=a.cursor();areaPage.capturedTick=df::global::world?df::global::world->frame_counter:-1;
    status=m::ManagementStatus::Rejected;
    if(a.location_kind()==2) {
      religions.observe(epoch,df3d_area::observeNativeLocationReligions());
      auto page=religions.page(epoch,a.cursor(),a.expected_list_revision());
      if(page.status==df3d_area::LocationPageStatus::Ready){areaPage.religions=std::move(page);status=m::ManagementStatus::Ok;}
    } else {
      guilds.observe(epoch,df3d_area::observeNativeLocationGuilds());
      auto page=guilds.page(epoch,a.cursor(),a.expected_list_revision());
      if(page.status==df3d_area::LocationPageStatus::Ready){areaPage.guilds=std::move(page);status=m::ManagementStatus::Ok;}
    }
    publish();return;
  }
  if(r->area() && r->area()->operation()==m::AreaOperation::PaintCounts) {
    runPaintCounts(*r->area());return;
  }
  if(r->area() && r->area()->operation()>=m::AreaOperation::MultiCreate && r->area()->operation()<=m::AreaOperation::MultiFinish) {
    runRooms(*r->area());return;
  }
  auto* L = Core::getInstance().getLuaState();
  int top = lua_gettop(L);
  const int domainScript=helpers.acquire(action,out,L);
  if(domainScript==LUA_NOREF) {
    status=m::ManagementStatus::Rejected;message="Management helper unavailable";publish();return;
  }
  lua_rawgeti(L,LUA_REGISTRYINDEX,domainScript);
  lua_newtable(L);
  field(L, "action", int(action));
  field(L, "seq", executionSerial);
  field(L, "epoch", epoch);
  field(L, "client_id", r->client_id());
  field(L, "step_budget", areaAction(action)?std::min(remainingSteps,uint32_t(1536)):remainingSteps);
  const bool synchronousWrite=synchronousAreaWrite(action,r->area()?r->area()->operation():m::AreaOperation::None);
  field(L,"synchronous_write",synchronousWrite);
  field(L,"synchronous_read",synchronousAreaRead(action,r->area()?r->area()->operation():m::AreaOperation::None));
  field(L, "retire_capacity", citizenAction(action) ? workDetailHolding.size()-workDetailHoldingCount : workOrderHolding.size()-workOrderHoldingCount);
  if(areaAction(action)) {
    field(L,"area_retire_capacity",areaHolding.size()-areaHoldingCount);
    lua_pushcfunction(L,areaSnapshot);lua_setfield(L,-2,"area_snapshot");
    lua_pushcfunction(L,areaSettingsFill);lua_setfield(L,-2,"settings_fill");
    lua_pushcfunction(L,areaSettingsLayout);lua_setfield(L,-2,"settings_layout");
    lua_pushcfunction(L,areaSettingsPreset);lua_setfield(L,-2,"settings_preset");
    lua_pushcfunction(L,areaLocationSet);lua_setfield(L,-2,"set_location");
    lua_pushcfunction(L,areaLocationCreate);lua_setfield(L,-2,"create_location");
    lua_pushcfunction(L,areaCreate);lua_setfield(L,-2,"create_area");
    lua_pushcfunction(L,areaRemove);lua_setfield(L,-2,"remove_area");
    lua_pushcfunction(L,areaRepaint);lua_setfield(L,-2,"repaint");
    lua_pushcfunction(L,areaLink);lua_setfield(L,-2,"link_areas");
    lua_pushcfunction(L,areaSquadUse);lua_setfield(L,-2,"squad_use");
    lua_pushcfunction(L,areaAssignUnit);lua_setfield(L,-2,"assign_unit");
  }
  if(citizenAction(action)) {
    field(L,"restart_recalc",citizenRecalcPending && citizenHelperGeneration!=helpers.generation());
    citizenHelperGeneration=helpers.generation();
  }
  if(r->creature()) field(L,"unit_id",r->creature()->unit_id());
  field(L, "definition", r->definition() ? r->definition()->str() : "");
  if (r->origin()) {
    field(L, "x", r->origin()->x());
    field(L, "y", r->origin()->y());
    field(L, "z", r->origin()->z());
  }
  field(L, "width", r->width());
  field(L, "height", r->height());
  field(L, "direction", r->direction());
  field(L, "roller_speed", r->roller_speed());
  if(action==m::ManagementAction::ConstructionMaterials) {
    lua_pushcfunction(L,df3d_construction::nativeMaterialDistances);lua_setfield(L,-2,"material_distances");
  }
  if(const auto* anchor=r->material_anchor()) {
    lua_newtable(L);field(L,"x",anchor->x());field(L,"y",anchor->y());field(L,"z",anchor->z());
    lua_setfield(L,-2,"material_anchor");
  }
  if(const auto* track=r->connected_track()) {
    lua_pushcfunction(L,df3d_construction::routeTrack);lua_setfield(L,-2,"route_track");
    lua_pushcfunction(L,df3d_construction::planTrack);lua_setfield(L,-2,"plan_track");
    lua_pushcfunction(L,df3d_construction::nativeMaterialDistances);lua_setfield(L,-2,"material_distances");
    const auto* end=track->destination();
    lua_newtable(L);field(L,"x",end->x());field(L,"y",end->y());field(L,"z",end->z());
    lua_setfield(L,-2,"connected_track_destination");
  }
  if(const auto* t=r->track_stop()) {
    lua_newtable(L);field(L,"friction",t->friction());field(L,"dump_direction",t->dump_direction());lua_setfield(L,-2,"track_stop");
  }
  if(const auto* p=r->pressure_plate()) {
    lua_newtable(L);
    field(L,"units",p->units());field(L,"water",p->water());field(L,"magma",p->magma());
    field(L,"citizens",p->citizens());field(L,"resets",p->resets());field(L,"track",p->track());
    field(L,"unit_min",p->unit_min());field(L,"unit_max",p->unit_max());
    field(L,"water_min",p->water_min());field(L,"water_max",p->water_max());
    field(L,"magma_min",p->magma_min());field(L,"magma_max",p->magma_max());
    field(L,"track_min",p->track_min());field(L,"track_max",p->track_max());lua_setfield(L,-2,"pressure_plate");
  }
  field(L,"depth",r->depth());field(L,"retracting",r->retracting());field(L,"filter",r->filter());
  field(L,"expected_list_revision",r->expected_list_revision());
  lua_newtable(L);
  if(r->selections()) { int index=0;for(const auto* v:*r->selections()) {
    lua_newtable(L);field(L,"filter",v->filter());field(L,"item_type",v->item_type());field(L,"item_subtype",v->item_subtype());
    field(L,"mat_type",v->mat_type());field(L,"mat_index",v->mat_index());field(L,"count",v->count());field(L,"individual_id",v->individual_id());field(L,"expected_list_revision",v->expected_list_revision());
    if(const auto* ids=v->item_ids()) { lua_newtable(L);int itemIndex=0;
      for(int32_t id:*ids){lua_pushinteger(L,id);lua_rawseti(L,-2,++itemIndex);}lua_setfield(L,-2,"item_ids"); }
    lua_rawseti(L,-2,++index);
  }}
  lua_setfield(L,-2,"selections");
  field(L, "cursor", cursor);
  field(L, "limit", 128 - int(inputs.size()));
  field(L, "building_id", r->building_id());
  field(L, "cancel_removal", r->cancel_removal());
  lua_newtable(L);
  if (r->items()) {
    int i = 0;
    for (auto id : *r->items()) {
      lua_pushinteger(L, id);
      lua_rawseti(L, -2, ++i);
    }
  }
  lua_setfield(L, -2, "items");
  if(const auto* a=r->area()) {
    lua_newtable(L);
    field(L,"kind",int(a->kind()));field(L,"id",a->id());field(L,"zone_type",a->zone_type());
    if(a->origin()){field(L,"x",a->origin()->x());field(L,"y",a->origin()->y());field(L,"z",a->origin()->z());}
    field(L,"width",a->width());field(L,"height",a->height());
    field(L,"categories",a->categories());field(L,"changed_categories",a->changed_categories());
    field(L,"barrels",a->barrels());field(L,"bins",a->bins());field(L,"wheelbarrows",a->wheelbarrows());
    field(L,"links_only",a->links_only());field(L,"active",a->active());field(L,"owner_id",a->owner_id());
    field(L,"link_id",a->link_id());field(L,"give",a->give());field(L,"unlink",a->unlink());
    field(L,"query",a->query()?a->query()->str():"");field(L,"cursor",a->cursor());
    field(L,"operation",int(a->operation()));field(L,"expected_revision",a->expected_revision());field(L,"expected_list_revision",a->expected_list_revision());
    field(L,"list_key",a->list_key()?a->list_key()->str():"");field(L,"row_key",a->row_key()?a->row_key()->str():"");
    field(L,"scope",a->scope());field(L,"value",a->value());field(L,"preset",a->preset());field(L,"name",a->name()?a->name()->str():"");
    field(L,"paint_mode",a->paint_mode());field(L,"paint_z",a->paint_z());
    field(L,"location_id",a->location_id());field(L,"location_kind",a->location_kind());field(L,"profession",a->profession());
    field(L,"deity_kind",a->deity_kind());field(L,"deity_id",a->deity_id());
    field(L,"unit_id",a->unit_id());field(L,"assign",a->assign());field(L,"squad_id",a->squad_id());field(L,"squad_use",a->squad_use());
    field(L,"organic",a->organic());field(L,"inorganic",a->inorganic());field(L,"candidate_kind",a->candidate_kind());
    field(L,"sort",a->sort());field(L,"sort_descending",a->sort_descending());
    lua_newtable(L);if(a->spans()){int i=0;for(const auto* v:*a->spans()) {
      lua_newtable(L);field(L,"x",v->x());field(L,"y",v->y());field(L,"length",v->length());lua_rawseti(L,-2,++i);
    }}lua_setfield(L,-2,"spans");
    lua_newtable(L);if(const auto* z=a->zone_settings()) {
      field(L,"pond_mode",z->pond_mode());field(L,"facing",z->facing());field(L,"tomb_citizens",z->tomb_citizens());
      field(L,"tomb_pets",z->tomb_pets());field(L,"gather_trees",z->gather_trees());field(L,"gather_shrubs",z->gather_shrubs());
    }lua_setfield(L,-2,"zone_settings");
    lua_setfield(L,-2,"area");
  }
  if(const auto* p=r->production()) {
    lua_newtable(L);field(L,"building_id",p->building_id());field(L,"job_id",p->job_id());field(L,"recipe",p->recipe()?p->recipe()->str():"");field(L,"query",p->query()?p->query()->str():"");field(L,"cursor",p->cursor());field(L,"repeat_job",p->repeat());field(L,"suspend",p->suspend());field(L,"cancel",p->cancel());field(L,"season",p->season());field(L,"crop_id",p->crop_id());lua_setfield(L,-2,"production");
  }
  if(const auto* w=r->work_order()) {
    lua_newtable(L);field(L,"id",w->id());field(L,"expected_revision",w->expected_revision());field(L,"recipe",w->recipe()?w->recipe()->str():"");field(L,"query",w->query()?w->query()->str():"");field(L,"cursor",w->cursor());
    field(L,"remaining",w->remaining());field(L,"frequency",w->frequency());field(L,"workshop_id",w->workshop_id());field(L,"max_workshops",w->max_workshops());field(L,"condition_kind",w->condition_kind());field(L,"condition_index",w->condition_index());field(L,"remove_condition",w->remove_condition());field(L,"compare",w->compare());field(L,"threshold",w->threshold());field(L,"item_type",w->item_type());field(L,"target_order",w->target_order());field(L,"dependency",w->dependency());field(L,"candidate_kind",w->candidate_kind());
    field(L,"move",w->move());field(L,"expected_neighbor",w->expected_neighbor());field(L,"expected_list_revision",w->expected_list_revision());field(L,"item_subtype",w->item_subtype());field(L,"mat_type",w->mat_type());field(L,"mat_index",w->mat_index());field(L,"input_index",w->input_index());field(L,"group_type",w->group_type());field(L,"group_subtype",w->group_subtype());field(L,"group_custom",w->group_custom());field(L,"encrust_flags",w->encrust_flags());
    if(w->traits() && (w->traits()->size() || r->action()==m::ManagementAction::WorkOrderCondition)) {
      lua_newtable(L);int index=0;
      for(const auto* t:*w->traits()){Lua::Push(L,t->str());lua_rawseti(L,-2,++index);}
      lua_setfield(L,-2,"traits");
    }
    lua_setfield(L,-2,"work_order");
  }
  if(const auto* c=r->citizen()) {
    lua_newtable(L);field(L,"unit_id",c->unit_id());field(L,"detail_index",c->detail_index());field(L,"expected_revision",c->expected_revision());field(L,"cursor",c->cursor());field(L,"query",c->query()?c->query()->str():"");field(L,"member",c->member());field(L,"mode",c->mode());
    field(L,"name",c->name()?c->name()->str():"");field(L,"edit",c->edit());field(L,"only_assigned",c->only_assigned());field(L,"expected_list_revision",c->expected_list_revision());
    lua_newtable(L);int index=0;if(c->labors())for(auto id:*c->labors()){lua_pushinteger(L,id);lua_rawseti(L,-2,++index);}lua_setfield(L,-2,"labors");
    lua_setfield(L,-2,"citizen");
  }

  if(const auto* t=r->trade()){lua_newtable(L);field(L,"depot_id",t->depot_id());field(L,"item_id",t->item_id());field(L,"expected_revision",t->expected_revision());field(L,"requested",t->requested());field(L,"anyone",t->anyone());field(L,"cursor",t->cursor());field(L,"query",t->query()?t->query()->str():"");lua_setfield(L,-2,"trade");}
  if(const auto* a=r->agreement()){lua_newtable(L);field(L,"id",a->id());field(L,"before_id",a->before_id());field(L,"query",a->query()?a->query()->str():"");field(L,"pending_only",a->pending_only());lua_setfield(L,-2,"agreement");}

  if(const auto* p=r->report()) {lua_newtable(L);field(L,"id",p->id());field(L,"before_id",p->before_id());field(L,"query",p->query()?p->query()->str():"");field(L,"announcements_only",p->announcements_only());field(L,"refresh",p->refresh());field(L,"notification_category",int(p->notification_category()));field(L,"alert_button",p->alert_button());field(L,"view",int(p->view()));field(L,"tab",int(p->tab()));field(L,"after_id",p->after_id());field(L,"from_end",p->from_end());field(L,"unit_id",p->unit_id());field(L,"unit_category",int(p->unit_category()));field(L,"cursor",p->cursor());field(L,"expected_list_revision",p->expected_list_revision());
    lua_newtable(L);if(p->ids()){int i=1;for(auto id:*p->ids()){lua_pushinteger(L,id);lua_rawseti(L,-2,i++);}}lua_setfield(L,-2,"ids");
    lua_newtable(L);if(p->units()){int i=1;for(const auto* u:*p->units()){lua_newtable(L);field(L,"unit_id",u->unit_id());field(L,"category",int(u->category()));lua_rawseti(L,-2,i++);}}lua_setfield(L,-2,"units");
    lua_setfield(L,-2,"report");}
  if (!Lua::SafeCall(out, L, 1, 1) || !lua_istable(L, -1)) {
    status = m::ManagementStatus::Rejected;
    message = "Native management helper failed; no success reported";
    // A helper can fail after native effects; conservatively refresh the world.
    if(action==m::ManagementAction::Place || synchronousWrite)mutated=true;
    if(action==m::ManagementAction::Place)construction.outcome=m::ConstructionOutcome::Unknown;
    if(!synchronousWrite)remainingSteps=0; // Read work is unknown; writes have separate accounting.
    else ++synchronousWritesWithUnknownWork;
    lua_settop(L, top);
    publish();
    return;
  }
  if(const auto error=managementResultError(L,action,r->area()?r->area()->operation():m::AreaOperation::None,
      std::min(remainingSteps,uint32_t(1536))); !error.empty()) {
    status=m::ManagementStatus::Rejected;
    message="Management helper contract failure: "+error;
    if(action==m::ManagementAction::Place || synchronousWrite)mutated=true;
    if(action==m::ManagementAction::Place)construction.outcome=m::ConstructionOutcome::Unknown;
    if(!synchronousWrite)remainingSteps=0;
    else ++synchronousWritesWithUnknownWork;
    lua_settop(L,top);publish();return;
  }
  bool ok = boolean(L, "ok");
  bool productionPending = boolean(L,"pending");
  const auto requestMask=df3d_builder::requestMask(builderTable,
      [&](auto owner){return helpers.sameOwner(action,owner);});
  builderActive=(builderActive & ~requestMask) |
      (uint32_t(number(L,"active_kinds")) & requestMask);
  if(synchronousWrite || requestMask) {
    const auto used=df3d_builder::readCharge(remainingSteps,uint64_t(number(L,"steps")),synchronousWrite);
    remainingSteps-=used;builderSteps+=used;
    if(synchronousWrite) {
      synchronousWriteSteps+=uint64_t(number(L,"steps"));
      if(boolean(L,"work_unknown")) {
        ++synchronousWritesWithUnknownWork;
        // Lua owner/settings edits can precede a rejected native notification.
        // Opaque work may have effects even when the reply cannot confirm them.
        mutated=true;
      }
    }
  }
  if(action>=m::ManagementAction::WorkOrderList && action<=m::ManagementAction::WorkOrderCatalog) {
    if(ok && !productionPending) {
      lua_getfield(L,-1,"retired");
      if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1);++i) {
        lua_rawgeti(L,-1,i);
        void* native=Lua::GetDFObject<df::manager_order>(L,-1);
        if(!native)native=Lua::GetDFObject<df::manager_order_condition_item>(L,-1);
        if(!native)native=Lua::GetDFObject<df::manager_order_condition_order>(L,-1);
        if(native && workOrderHoldingCount<workOrderHolding.size())workOrderHolding[workOrderHoldingCount++]=native;
        else out.printerr("df3d: retired work-order element {} was not retained: {}\n",i,
            native ? "holding array full" : "unrecognized native object");
        lua_pop(L,1);
      }
      lua_pop(L,1);
    }
  }
  if(citizenAction(action)) {
    citizenRecalcPending=(builderActive & 0x10)!=0;
    citizenRecalcDone=uint32_t(number(L,"recalc_done"));citizenRecalcTotal=uint32_t(number(L,"recalc_total"));
    // Retain even when recalculation failed after the native vector erase.
    if(action==m::ManagementAction::WorkDetailDelete) {
      lua_getfield(L,-1,"retired");
      if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1);++i) {
        lua_rawgeti(L,-1,i);void* native=Lua::GetDFObject<df::work_detail>(L,-1);
        if(native && workDetailHoldingCount<workDetailHolding.size()){workDetailHolding[workDetailHoldingCount++]=native;mutated=true;}
        else out.printerr("df3d: retired work-detail element {} was not retained: {}\n",i,native ? "holding array full" : "unrecognized native object");
        lua_pop(L,1);
      }
      lua_pop(L,1);
    }
  }
  if(areaAction(action)) {
    // Keep detached allocations across stop(), helper reload and world changes.
    // Producers preflight area_retire_capacity before the first native change.
    const auto operation=r->area() ? r->area()->operation() : m::AreaOperation::None;
    const auto extentBytes=size_t(number(L,"retired_bytes"));
    lua_getfield(L,-1,"retired");
    if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1);++i) {
      lua_rawgeti(L,-1,i);void* native=nullptr;size_t bytes=0;
      if(operation==m::AreaOperation::Paint && lua_type(L,-1)==LUA_TLIGHTUSERDATA) {
        native=lua_touserdata(L,-1);bytes=extentBytes;
      } else if(operation==m::AreaOperation::AssignUnits) {
        native=Lua::GetDFObject<df::general_ref_building_civzone_assignedst>(L,-1);
        bytes=sizeof(df::general_ref_building_civzone_assignedst);
      } else if(operation==m::AreaOperation::SquadUse) {
        native=Lua::GetDFObject<df::building_squad_infost>(L,-1);bytes=sizeof(df::building_squad_infost);
        if(!native){native=Lua::GetDFObject<df::squad_barracks_infost>(L,-1);bytes=sizeof(df::squad_barracks_infost);}
      }
      if(native && ((operation==m::AreaOperation::Paint && native==areaPaintRetired) ||
          (operation==m::AreaOperation::AssignUnits && native==areaUnitRetired) ||
          (operation==m::AreaOperation::SquadUse && (native==areaSquadRetired[0] || native==areaSquadRetired[1])))) {
        // Already retained by the native commit, including exceptional Lua exits.
      } else if(native && areaHoldingCount<areaHolding.size()) {
        areaHolding[areaHoldingCount++]=native;areaHoldingBytes+=bytes;mutated=true;
      } else out.printerr("df3d: retired area element {} was not retained: {}\n",i,
          native ? "holding array full" : "unrecognized native object");
      lua_pop(L,1);
    }
    lua_pop(L,1);
  }
  const bool isConstruction=action<=m::ManagementAction::RemoveConstruction || action==m::ManagementAction::ConstructionMaterials;
  if(isConstruction) {
    construction.placed=uint32_t(number(L,"placed",construction.placed));
    construction.skipped=uint32_t(number(L,"skipped",construction.skipped));
    construction.first_building=int32_t(number(L,"first_building",construction.first_building));
    constructionCacheEntries=uint32_t(number(L,"cache_entries"));constructionCacheIds=uint32_t(number(L,"cache_ids"));
    df3d_management::constructionEffects(number(L,"chunk_placed"),r->origin(),
        r->width(),r->height(),r->depth(),mutated,
        [&](int x,int y,int z){areaHints.push_back({x,y,z});});
  }
  if(ok && (action==m::ManagementAction::TradeUpdate || action==m::ManagementAction::TradeBring))mutated=true;
  if(ok && action>=m::ManagementAction::WorkOrderCreate && action<=m::ManagementAction::WorkOrderCondition)mutated=true;
  if(ok && (action==m::ManagementAction::WorkDetailMembership || action==m::ManagementAction::WorkDetailMode || (action>=m::ManagementAction::WorkDetailCreate && action<=m::ManagementAction::CitizenWorkScope)))mutated=true;
  message = text(L, "message");
  valid = boolean(L, "placement_valid");
  required = uint16_t(number(L, "required"));
  if (ok && !productionPending && (action == m::ManagementAction::Place || action == m::ManagementAction::Remove ||
             action == m::ManagementAction::RemoveConstruction || action==m::ManagementAction::AreaCreate ||
             action==m::ManagementAction::AreaUpdate || action==m::ManagementAction::AreaDelete || action==m::ManagementAction::AreaLink || action==m::ManagementAction::ProductionQueue || action==m::ManagementAction::ProductionJobEdit || action==m::ManagementAction::FarmSetCrop))
    mutated = true;
  terrainConstructed = boolean(L, "terrain_construction");
  if (ok && (action==m::ManagementAction::AreaCreate || action==m::ManagementAction::AreaDelete)) {
    const int x=number(L,"hint_x"), y=number(L,"hint_y"), z=number(L,"hint_z");
    const int w=number(L,"hint_width"), h=number(L,"hint_height");
    if(x>=0 && y>=0 && z>=0 && w>0 && h>0 && w<=256 && h<=256)
      for(int by=y>>4;by<=(y+h-1)>>4;++by) for(int bx=x>>4;bx<=(x+w-1)>>4;++bx)
        areaHints.push_back({bx<<4,by<<4,z});
  }
  if (ok && action == m::ManagementAction::RemoveConstruction && r->origin()) {
    terrainHint = true;
    hintX = r->origin()->x();
    hintY = r->origin()->y();
    hintZ = r->origin()->z();
  }
  cursor = uint32_t(number(L, "next_cursor"));
  building = int32_t(number(L, "building_id", -1));
  stage = int16_t(number(L, "build_stage", -1));
  maxStage = int16_t(number(L, "max_stage", -1));
  removing = boolean(L, "removing");
  jobs = uint16_t(number(L, "jobs"));
  if(areaAction(action)) {
    areaCursor=uint32_t(number(L,"next_cursor"));areaTruncated=boolean(L,"truncated");
    // managementResultError checked types, dense arrays and every cap before
    // these reads. Never clamp a native reply into an apparently complete page.
    const auto each=[&](const char* key,const auto& callback) {
      lua_getfield(L,-1,key);
      if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1);++i){lua_rawgeti(L,-1,i);callback();lua_pop(L,1);}
      lua_pop(L,1);
    };
    const auto str=[&](const char* key) {
      lua_getfield(L,-1,key);size_t length=0;const char* bytes=lua_tolstring(L,-1,&length);
      std::string result=bytes?std::string(bytes,length):std::string{};lua_pop(L,1);return result;
    };
    const auto ints=[&](const char* key,auto& values){each(key,[&](){values.push_back(typename std::decay_t<decltype(values)>::value_type(lua_tointeger(L,-1)));});};
    areaPage.operation=m::AreaOperation(number(L,"operation"));areaPage.id=int32_t(number(L,"area_id",-1));
    areaPage.listKey=str("list_key");areaPage.query=str("query");areaPage.candidateKind=uint8_t(number(L,"candidate_kind"));
    areaPage.sort=uint8_t(number(L,"sort"));areaPage.sortDescending=boolean(L,"sort_descending");
    areaPage.listRevision=number(L,"list_revision");areaPage.buildPhase=uint8_t(number(L,"build_phase"));
    areaPage.buildDone=uint32_t(number(L,"build_done"));areaPage.buildTotal=uint32_t(number(L,"build_total"));
    areaPage.omitted=uint32_t(number(L,"omitted"));areaPage.capturedTick=number(L,"captured_tick",-1);
    each("areas",[&]() {
      NativeArea a;
      a.id=int32_t(number(L,"id",-1));a.kind=int(number(L,"kind"));a.zone=int(number(L,"zone_type",-1));
      a.x=int(number(L,"x"));a.y=int(number(L,"y"));a.z=int(number(L,"z"));
      a.w=int(number(L,"width"));a.h=int(number(L,"height"));a.name=str("name");
      a.categories=uint32_t(number(L,"categories"));a.barrels=int(number(L,"barrels"));a.bins=int(number(L,"bins"));a.wheelbarrows=int(number(L,"wheelbarrows"));
      a.active=boolean(L,"active");a.linksOnly=boolean(L,"links_only");a.ownerAllowed=boolean(L,"owner_allowed");
      a.owner=int32_t(number(L,"owner_id",-1));a.ownerName=str("owner_name");
      a.ownerProfession=str("owner_profession");a.ownerSex=int8_t(number(L,"owner_sex",-1));
      a.locationKind=uint8_t(number(L,"location_kind",0));
      a.revision=number(L,"revision");a.zoneLabel=str("zone_label");a.locationId=int32_t(number(L,"location_id",-1));a.locationSiteId=int32_t(number(L,"location_site_id",-1));
      a.locationName=str("location_name");a.religion=str("religion");a.organic=int8_t(number(L,"organic",-1));a.inorganic=int8_t(number(L,"inorganic",-1));
      a.tileCount=int32_t(number(L,"tile_count",-1));a.assignedCount=int32_t(number(L,"assigned_count",-1));
      lua_getfield(L,-1,"zone_settings");if(lua_istable(L,-1)) {
        a.zoneSettings={uint8_t(number(L,"pond_mode")),uint8_t(number(L,"facing")),int8_t(number(L,"tomb_citizens",-1)),
            int8_t(number(L,"tomb_pets",-1)),int8_t(number(L,"gather_trees",-1)),int8_t(number(L,"gather_shrubs",-1))};
      }lua_pop(L,1);
      ints("extents",a.extents);ints("gives",a.gives);ints("takes",a.takes);areas.push_back(std::move(a));
    });
    each("choices",[&](){areaChoices.push_back({int32_t(number(L,"id",-1)),str("name"),str("label")});});
    each("settings",[&](){areaPage.settings.push_back({str("key"),str("label"),int32_t(number(L,"index",-1)),uint8_t(number(L,"kind")),uint8_t(number(L,"state")),boolean(L,"estimated")});});
    each("locations",[&](){areaPage.locations.push_back({int32_t(number(L,"id",-1)),str("name"),str("religion"),uint8_t(number(L,"location_kind")),int16_t(number(L,"guild_profession",-1)),int32_t(number(L,"location_tier",-1)),int32_t(number(L,"site_id",-1))});});
    each("candidates",[&](){areaPage.candidates.push_back({int32_t(number(L,"id",-1)),str("name"),str("profession"),int8_t(number(L,"sex",-1)),int8_t(number(L,"squad_use",-1)),uint8_t(number(L,"mood")),boolean(L,"grazer"),boolean(L,"assigned")});});
    each("links",[&](){areaPage.links.push_back({int32_t(number(L,"id",-1)),uint8_t(number(L,"kind")),uint8_t(number(L,"direction")),str("name")});});
  }
  if(citizenAction(action)) {
    citizens.nextCursor=uint32_t(number(L,"next_cursor"));citizens.selectedUnit=int32_t(number(L,"selected_unit",-1));citizens.selectedDetail=int32_t(number(L,"selected_detail",-1));citizens.externalController=boolean(L,"external_controller");citizens.detail=text(L,"detail");
    citizens.recalcDone=citizenRecalcDone;citizens.recalcTotal=citizenRecalcTotal;
    citizens.recalcError=text(L,"recalc_error");citizens.detailListRevision=number(L,"detail_list_revision");
    bool pageInvalid=false;std::string* rowError=nullptr;size_t portraitBytes=0;
    auto error=[&](const char* key){if(rowError){if(rowError->empty())*rowError=std::string("Row exceeds ")+key+" cap";}else pageInvalid=true;};
    auto str=[&](const char* key,size_t cap,bool optional=false)->std::string {
      lua_getfield(L,-1,key);size_t n=0;const bool type=lua_type(L,-1)==LUA_TSTRING;
      const char* data=type ? lua_tolstring(L,-1,&n) : nullptr;
      if((!type && !(optional && lua_isnil(L,-1))) || n>cap)error(key);
      std::string value=data && n<=cap ? std::string(data,n) : std::string{};lua_pop(L,1);return value;
    };
    auto name=[&]()->std::string {
      size_t n=0;const bool type=lua_type(L,-1)==LUA_TSTRING;
      const char* data=type ? lua_tolstring(L,-1,&n) : nullptr;
      if(!type || n>128){error("labor_names");return {};}
      return std::string(data,n);
    };
    auto each=[&](const char* key,size_t cap,auto fn){
      lua_getfield(L,-1,key);
      if(!lua_isnil(L,-1) && !lua_istable(L,-1))error(key);
      if(lua_istable(L,-1)) {
        const size_t count=lua_rawlen(L,-1);
        if(count>cap)error(key);
        else for(size_t i=1;i<=count;++i){
          lua_rawgeti(L,-1,i);
          const std::string_view fieldName(key);
          const bool object=fieldName=="citizens" || fieldName=="details" || fieldName=="roles" || fieldName=="assigned_details";
          if(object && !lua_istable(L,-1))error(key);else fn();
          lua_pop(L,1);
        }
      }
      lua_pop(L,1);
    };
    each("citizens",32,[&](){
      CitizenInfo u;rowError=&u.rowError;
      auto reportedError=str("row_error",256,true);if(u.rowError.empty())u.rowError=std::move(reportedError);u.revision=number(L,"revision");u.detailMember=int8_t(number(L,"detail_member",-1));
      u.detailSkill=int16_t(number(L,"detail_skill",-1));u.detailSkillRating=int16_t(number(L,"detail_skill_rating",-1));u.detailSkillName=str("detail_skill_name",128,true);u.professionColor=int32_t(number(L,"profession_color",-1));u.professionId=int32_t(number(L,"profession_id",-1));u.jobType=int32_t(number(L,"job_type",-1));u.id=int32_t(number(L,"id",-1));u.age=int32_t(number(L,"age",-1));u.stress=int32_t(number(L,"stress"));u.x=int32_t(number(L,"x"));u.y=int32_t(number(L,"y"));u.z=int32_t(number(L,"z"));u.name=str("name",512);u.profession=str("profession",512);u.job=str("job",512);u.reason=str("reason",512);u.hasStress=boolean(L,"has_stress");u.canFocus=boolean(L,"can_focus");u.eligible=boolean(L,"eligible");
      // A stale Lua-reported id (unit removed between the scan and this
      // readback) must not reach the appearance resolver: skip the row.
      auto* nativeUnit=df::unit::find(u.id);
      if(!nativeUnit){++staleUnitsSkipped;rowError=nullptr;return;}
      u.sheetIcon.collect(nativeUnit);
      u.portraitState=u.sheetIcon.layers.empty() ? 2 : 1;
      if(u.portraitState==1) {
        flatbuffers::FlatBufferBuilder portrait;auto encoded=u.sheetIcon.build(portrait);portrait.Finish(encoded);
        // Include alignment slack so the page's combined encoding cannot exceed the cap.
        const size_t bytes=portrait.GetSize()+8;
        if(bytes>256*1024-portraitBytes){u.sheetIcon={};u.portraitState=3;}else portraitBytes+=bytes;
      }
      // Same semantic lookup as DFHack manipulator: a social event replaces
      // the idle caption only when there is no ordinary job. No UI state read.
      if(!nativeUnit->job.current_job) {
        if(auto* event=Units::getMainSocialEvent(nativeUnit)) {
          std::string description;event->getName(nativeUnit->id,&description);
          u.job=DF2UTF(description);u.socialActivity=true;if(u.job.size()>512)error("job");
        }
      }
      u.onlyAssignedJobs=boolean(L,"only_assigned_jobs");
      each("assigned_details",128,[&](){u.assignedDetails.push_back({int32_t(number(L,"index",-1)),int32_t(number(L,"icon",-2)),str("name",512)});});
      each("labor_names",94,[&](){u.laborNames.push_back(name());});
      each("labors",94,[&](){u.labors.push_back(int16_t(lua_tointeger(L,-1)));});
      each("offices",64,[&](){u.offices.push_back(int32_t(lua_tointeger(L,-1)));});
      each("roles",32,[&](){u.roles.push_back({str("name",512),int32_t(number(L,"required_office"))});});if(!u.rowError.empty()) {
        u.name.clear();u.profession.clear();u.job.clear();u.reason.clear();u.detailSkillName.clear();
        u.labors.clear();u.laborNames.clear();u.roles.clear();u.offices.clear();u.assignedDetails.clear();u.sheetIcon={};u.portraitState=2;
      }
      rowError=nullptr;citizens.citizens.push_back(std::move(u));
    });
    each("details",16,[&](){
      WorkDetailInfo d;rowError=&d.rowError;auto reportedError=str("row_error",256,true);if(d.rowError.empty())d.rowError=std::move(reportedError);d.icon=int32_t(number(L,"icon",-2));d.index=int32_t(number(L,"index",-1));d.revision=uint64_t(number(L,"revision"));d.name=str("name",512);d.reason=str("reason",512);d.mode=uint8_t(number(L,"mode"));d.noModify=boolean(L,"no_modify");d.cannotBeEverybody=boolean(L,"cannot_be_everybody");d.editable=boolean(L,"editable");d.modeEditable=boolean(L,"mode_editable");
      each("labor_names",94,[&](){d.laborNames.push_back(name());});
      each("labors",94,[&](){d.labors.push_back(int16_t(lua_tointeger(L,-1)));});each("assigned_units",1024,[&](){d.assignedUnits.push_back(int32_t(lua_tointeger(L,-1)));});if(!d.rowError.empty()){d.name.clear();d.reason.clear();d.labors.clear();d.laborNames.clear();d.assignedUnits.clear();}
      rowError=nullptr;citizens.details.push_back(std::move(d));
    });
    if(pageInvalid){ok=false;productionPending=false;message="Invalid native citizen response: page exceeds contract";citizens.citizens.clear();citizens.details.clear();}
  }
  if(action>=m::ManagementAction::TradeList && action<=m::ManagementAction::TradeBring) {
    trade.nextCursor=uint32_t(number(L,"next_cursor"));trade.selectedDepot=int32_t(number(L,"selected_depot",-1));trade.detail=text(L,"detail");
    auto each=[&](const char* key,auto fn){lua_getfield(L,-1,key);if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1)&&i<=64;++i){lua_rawgeti(L,-1,i);fn();lua_pop(L,1);}lua_pop(L,1);};
    each("depots",[&](){TradeDepot d;d.id=int32_t(number(L,"id",-1));d.x=int32_t(number(L,"x"));d.y=int32_t(number(L,"y"));d.z=int32_t(number(L,"z"));d.revision=uint64_t(number(L,"revision"));d.requested=boolean(L,"requested");d.anyone=boolean(L,"anyone");d.accessible=boolean(L,"accessible");d.ready=boolean(L,"ready");d.broker=text(L,"broker");d.hauling=uint32_t(number(L,"hauling"));d.goods=uint32_t(number(L,"goods"));trade.depots.push_back(std::move(d));});
    each("caravans",[&](){TradeCaravan c;c.id=int32_t(number(L,"id"));c.name=text(L,"name");c.state=text(L,"state");c.daysRemaining=int32_t(number(L,"days_remaining"));trade.caravans.push_back(std::move(c));});
    each("goods",[&](){TradeGood g;g.id=int32_t(number(L,"id",-1));g.description=text(L,"description");g.quantity=uint32_t(number(L,"quantity",1));g.selected=boolean(L,"selected");g.selectable=boolean(L,"selectable");g.reason=text(L,"reason");trade.goods.push_back(std::move(g));});
  }
  if(action==m::ManagementAction::CreatureInspect) creature_data::read(L,creature);

  if(action>=m::ManagementAction::AgreementList && action<=m::ManagementAction::AgreementInspect) {
    agreements.nextBeforeId=int32_t(number(L,"next_before_id",-1));agreements.pendingOnly=boolean(L,"pending_only");agreements.detail=text(L,"detail");
    auto each=[&](const char* key,size_t cap,auto fn){lua_getfield(L,-1,key);if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1)&&i<=cap;++i){lua_rawgeti(L,-1,i);fn();lua_pop(L,1);}lua_pop(L,1);};
    each("agreements",16,[&](){
      AgreementInfo a;a.id=int32_t(number(L,"id",-1));a.status=uint8_t(number(L,"status"));a.notApproved=boolean(L,"not_approved");a.concluded=boolean(L,"concluded");a.continuing=boolean(L,"continuing");a.complete=boolean(L,"complete");a.summary=text(L,"summary");a.reason=text(L,"reason");
      each("details",8,[&](){AgreementDetail d;d.id=int32_t(number(L,"id"));d.kind=int16_t(number(L,"kind",-1));d.siteId=int32_t(number(L,"site_id",-1));d.year=int32_t(number(L,"year"));d.yearTick=int32_t(number(L,"year_tick"));d.applicantParty=int32_t(number(L,"applicant_party",-1));d.governmentParty=int32_t(number(L,"government_party",-1));d.locationType=int16_t(number(L,"location_type",-1));d.tier=int32_t(number(L,"tier",-1));d.profession=int16_t(number(L,"profession",-1));d.deityType=int16_t(number(L,"deity_type",-1));d.deityId=int32_t(number(L,"deity_id",-1));d.description=text(L,"description");a.details.push_back(std::move(d));});
      each("parties",8,[&](){AgreementParty p;p.id=int32_t(number(L,"id"));p.name=text(L,"name");each("entity_ids",32,[&](){p.entityIds.push_back(int32_t(lua_tointeger(L,-1)));});each("histfig_ids",32,[&](){p.histfigIds.push_back(int32_t(lua_tointeger(L,-1)));});a.parties.push_back(std::move(p));});agreements.agreements.push_back(std::move(a));
    });
  }
  if((action>=m::ManagementAction::ReportList && action<=m::ManagementAction::ReportInspect) || action==m::ManagementAction::PrepareAlertDismissal || action==m::ManagementAction::DismissAlert) {
    reports.nextBeforeId=int32_t(number(L,"next_before_id",-1));reports.announcementsOnly=boolean(L,"announcements_only");reports.detail=text(L,"detail");
    reports.view=uint8_t(number(L,"view"));reports.tab=uint8_t(number(L,"tab"));reports.afterId=int32_t(number(L,"after_id",-1));reports.fromEnd=boolean(L,"from_end");
    reports.total=uint32_t(number(L,"total"));reports.nextAfterId=int32_t(number(L,"next_after_id",-1));reports.trimmedThrough=int32_t(number(L,"trimmed_through",-1));reports.gap=boolean(L,"gap");
    lua_getfield(L,-1,"missing_ids");if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1);++i){lua_rawgeti(L,-1,i);reports.missingIds.push_back(int32_t(lua_tointeger(L,-1)));lua_pop(L,1);}lua_pop(L,1);
    reports.unitId=int32_t(number(L,"unit_id",-1));reports.unitCategory=int8_t(number(L,"unit_category",-1));reports.cursor=uint32_t(number(L,"cursor"));reports.nextCursor=uint32_t(number(L,"next_cursor"));reports.listRevision=number(L,"list_revision");reports.notificationCategory=int16_t(number(L,"notification_category",-1));reports.alertButton=boolean(L,"alert_button");
    lua_getfield(L,-1,"units");if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1);++i){lua_rawgeti(L,-1,i);reports.units.push_back({int32_t(number(L,"unit_id",-1)),int8_t(number(L,"category",-1)),text(L,"profession"),text(L,"name"),boolean(L,"dead"),uint32_t(number(L,"log_count")),text(L,"error")});lua_pop(L,1);}lua_pop(L,1);
    lua_getfield(L,-1,"tab_counts");if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1);++i){lua_rawgeti(L,-1,i);reports.tabCounts.push_back(uint32_t(lua_tointeger(L,-1)));lua_pop(L,1);}lua_pop(L,1);
    lua_getfield(L,-1,"reports");
    if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1);++i){
      lua_rawgeti(L,-1,i);ReportInfo p;p.id=int32_t(number(L,"id",-1));p.category=text(L,"category");p.text=text(L,"text");p.year=int32_t(number(L,"year"));p.yearTick=int32_t(number(L,"year_tick"));p.repeatCount=int32_t(number(L,"repeat_count"));p.continuation=boolean(L,"continuation");p.textComplete=boolean(L,"text_complete");p.x=int32_t(number(L,"x",-1));p.y=int32_t(number(L,"y",-1));p.z=int32_t(number(L,"z",-1));p.x2=int32_t(number(L,"x2",-1));p.y2=int32_t(number(L,"y2",-1));p.z2=int32_t(number(L,"z2",-1));p.positionVisible=boolean(L,"position_visible");p.position2Visible=boolean(L,"position2_visible");p.tab=uint8_t(number(L,"tab"));p.color=int16_t(number(L,"color",-1));p.bright=boolean(L,"bright");p.zoomType=uint8_t(number(L,"zoom_type"));p.zoomType2=uint8_t(number(L,"zoom_type2"));p.positionHidden=boolean(L,"position_hidden");p.position2Hidden=boolean(L,"position2_hidden");p.speakerId=int32_t(number(L,"speaker_id",-1));reports.reports.push_back(std::move(p));lua_pop(L,1);
    }lua_pop(L,1);
  }
  if(action>=m::ManagementAction::WorkOrderList && action<=m::ManagementAction::WorkOrderCatalog) {
    workOrders.nextCursor=uint32_t(number(L,"next_cursor"));workOrders.detail=text(L,"detail");
    workOrders.total=uint32_t(number(L,"total"));workOrders.listRevision=number(L,"list_revision");
    workOrders.buildPhase=uint8_t(number(L,"build_phase"));workOrders.buildDone=uint32_t(number(L,"build_done"));workOrders.buildTotal=uint32_t(number(L,"build_total"));
    auto each=[&](const char* key,size_t max,auto fn){lua_getfield(L,-1,key);if(lua_istable(L,-1)){const size_t n=std::min(max,lua_rawlen(L,-1));for(size_t i=1;i<=n;++i){lua_rawgeti(L,-1,i);fn();lua_pop(L,1);}}lua_pop(L,1);};
    each("orders",16,[&](){
      BridgeWorkOrderInfo o;o.id=int32_t(number(L,"id",-1));o.revision=uint64_t(number(L,"revision"));o.name=text(L,"name");o.reason=text(L,"reason");o.total=int16_t(number(L,"total"));o.remaining=int16_t(number(L,"remaining"));o.frequency=int8_t(number(L,"frequency"));o.validated=boolean(L,"validated");o.active=boolean(L,"active");o.finishedYear=int32_t(number(L,"finished_year",-1));o.finishedTick=int32_t(number(L,"finished_tick",-1));o.workshopId=int32_t(number(L,"workshop_id",-1));o.maxWorkshops=int32_t(number(L,"max_workshops"));o.editable=boolean(L,"editable");
      o.position=int32_t(number(L,"position",-1));o.detailKind=uint8_t(number(L,"detail_kind"));o.sizeRaw=int32_t(number(L,"size_raw",-1));o.encrustFlags=int32_t(number(L,"encrust_flags"));o.matType=int16_t(number(L,"mat_type",-1));o.matIndex=int32_t(number(L,"mat_index",-1));o.materialCategory=uint32_t(number(L,"material_category"));
      each("inputs",64,[&](){o.inputs.push_back({uint16_t(number(L,"index")),text(L,"description"),int16_t(number(L,"mat_type",-1)),int32_t(number(L,"mat_index",-1)),boolean(L,"editable")});});
      each("generated_jobs",1024,[&](){o.generatedJobs.push_back(int32_t(lua_tointeger(L,-1)));});
      each("conditions",64,[&](){BridgeWorkOrderCondition c;c.kind=uint8_t(number(L,"kind"));c.index=uint16_t(number(L,"index"));c.description=text(L,"description");c.editable=boolean(L,"editable");c.satisfied=boolean(L,"satisfied");c.compare=int8_t(number(L,"compare",-1));c.dependency=int8_t(number(L,"dependency",-1));c.itemType=int16_t(number(L,"item_type",-1));c.threshold=int32_t(number(L,"threshold",-1));c.targetOrder=int32_t(number(L,"target_order",-1));c.itemSubtype=int16_t(number(L,"item_subtype",-1));c.matType=int16_t(number(L,"mat_type",-1));c.matIndex=int32_t(number(L,"mat_index",-1));c.satisfaction=uint8_t(number(L,"satisfaction"));c.estimated=boolean(L,"estimated");c.estimateCount=int32_t(number(L,"estimate_count",-1));each("traits",256,[&](){c.traits.emplace_back(lua_tostring(L,-1));});o.conditions.push_back(std::move(c));});
      workOrders.orders.push_back(std::move(o));
    });
    each("materials",128,[&](){workOrders.materials.push_back({int16_t(number(L,"mat_type",-1)),int32_t(number(L,"mat_index",-1)),text(L,"name")});});
    each("traits",128,[&](){workOrders.traits.push_back({text(L,"key"),text(L,"name")});});
    each("types",128,[&](){workOrders.types.push_back({int16_t(number(L,"item_type",-1)),int16_t(number(L,"item_subtype",-1)),text(L,"name")});});
    each("groups",128,[&](){workOrders.groups.push_back({int16_t(number(L,"type",-1)),int16_t(number(L,"subtype",-1)),int32_t(number(L,"custom",-1)),text(L,"name"),uint32_t(number(L,"count"))});});
    each("tasks",128,[&](){workOrders.tasks.push_back({text(L,"key"),text(L,"name"),int16_t(number(L,"job_type",-1)),text(L,"reaction"),int16_t(number(L,"item_type",-1)),int16_t(number(L,"item_subtype",-1)),int16_t(number(L,"mat_type",-1)),int32_t(number(L,"mat_index",-1))});});
    each("recipes",128,[&](){workOrders.recipes.push_back({text(L,"key"),text(L,"name"),{}});});
    each("choices",128,[&](){workOrders.choices.push_back({int32_t(number(L,"id",-1)),text(L,"name")});});
    each("managers",32,[&](){ManagerRole v;v.unitId=int32_t(number(L,"unit_id",-1));v.name=text(L,"name");v.position=text(L,"position");v.job=text(L,"job");each("offices",64,[&](){v.offices.push_back(int32_t(lua_tointeger(L,-1)));});workOrders.managers.push_back(std::move(v));});
  }
  if(action>=m::ManagementAction::ProductionList && action<=m::ManagementAction::FarmSetCrop) {
    production.nextCursor=uint32_t(number(L,"next_cursor"));production.selectedBuilding=int32_t(number(L,"selected_building",-1));production.createdJob=int32_t(number(L,"created_job",-1));production.currentSeason=int8_t(number(L,"current_season",-1));production.detail=text(L,"detail");
    auto each=[&](const char* key,size_t cap,auto fn){lua_getfield(L,-1,key);if(lua_istable(L,-1)) for(size_t i=1;i<=lua_rawlen(L,-1)&&i<=cap;++i){lua_rawgeti(L,-1,i);fn();lua_pop(L,1);}lua_pop(L,1);};
    auto reqs=[&](){std::vector<ProductionRequirement> out;each("requirements",16,[&](){out.push_back({text(L,"description"),int32_t(number(L,"quantity")),int16_t(number(L,"item_type",-1))});});return out;};
    each("buildings",64,[&](){ProductionBuilding v;v.id=int32_t(number(L,"id",-1));v.x=int32_t(number(L,"x"));v.y=int32_t(number(L,"y"));v.z=int32_t(number(L,"z"));v.name=text(L,"name");v.kind=text(L,"kind");v.buildStage=int16_t(number(L,"build_stage"));v.maxStage=int16_t(number(L,"max_stage"));v.queueSize=uint16_t(number(L,"queue_size"));production.buildings.push_back(std::move(v));});
    each("recipes",128,[&](){production.recipes.push_back({text(L,"key"),text(L,"name"),reqs()});});
    each("production_jobs",64,[&](){ProductionJob v;v.id=int32_t(number(L,"id",-1));v.jobType=int16_t(number(L,"job_type",-1));v.workerId=int32_t(number(L,"worker_id",-1));v.completionTimer=int32_t(number(L,"completion_timer",-1));v.name=text(L,"name");v.workerName=text(L,"worker_name");v.status=text(L,"status");v.repeat=boolean(L,"repeat_job");v.suspended=boolean(L,"suspended");v.editable=boolean(L,"editable");v.attachedItems=uint16_t(number(L,"attached_items"));v.requirements=reqs();production.jobs.push_back(std::move(v));});
    each("crops",256,[&](){production.crops.push_back({int32_t(number(L,"id",-1)),text(L,"name"),uint8_t(number(L,"seasons")),uint32_t(number(L,"seeds"))});});
    each("seasonal_crops",4,[&](){production.seasonalCrops.push_back(int32_t(lua_tointeger(L,-1)));});
  }
  if(isConstruction) {
    bool invalid=false;
    auto each=[&](const char* key,size_t cap,auto fn) {
      lua_getfield(L,-1,key);
      if(!lua_isnil(L,-1) && !lua_istable(L,-1))invalid=true;
      if(lua_istable(L,-1)) {
        const auto size=lua_rawlen(L,-1);
        if(size>cap)invalid=true;
        else for(size_t i=1;i<=size;++i){
          lua_rawgeti(L,-1,i);
          if(std::string_view(key)!="valid_mask" && std::string_view(key)!="pieces" && !lua_istable(L,-1))invalid=true;
          else fn();lua_pop(L,1);
        }
      }
      lua_pop(L,1);
    };
    auto n=[&](const char* key,int64_t low,int64_t high,int64_t fallback=0) {
      lua_getfield(L,-1,key);
      int64_t value=fallback;
      if(!lua_isnil(L,-1)){if(!lua_isinteger(L,-1))invalid=true;else value=lua_tointeger(L,-1);}
      lua_pop(L,1);if(value<low || value>high){invalid=true;return fallback;}return value;
    };
    auto str=[&](const char* key,size_t cap) {
      lua_getfield(L,-1,key);
      if(!lua_isnil(L,-1) && lua_type(L,-1)!=LUA_TSTRING)invalid=true;
      size_t len=0;const char* data=lua_tolstring(L,-1,&len);
      if(len>cap)invalid=true;
      std::string value=data && len<=cap ? std::string(data,len) : std::string{};lua_pop(L,1);return value;
    };
    auto readFilters=[&]() {
      std::vector<ConstructionFilter> rows;
      each("filters",8,[&](){ConstructionFilter v;v.index=int16_t(n("index",0,7,-1));v.item_type=int16_t(n("item_type",-1,INT16_MAX,-1));v.item_subtype=int16_t(n("item_subtype",-1,INT16_MAX,-1));v.caption=str("caption",64);v.requirement=str("requirement",64);v.quantity=int32_t(n("quantity",-1,INT32_MAX,-1));rows.push_back(std::move(v));});
      return rows;
    };
    auto readFootprint=[&]() {ConstructionFootprint v;v.direction=uint8_t(n("direction",0,7));v.width=uint16_t(n("width",1,31));v.height=uint16_t(n("height",1,31));v.center_x=int16_t(n("center_x",-1,30,-1));v.center_y=int16_t(n("center_y",-1,30,-1));return v;};
    catalog.clear();
    each("catalog",128,[&](){Def d;d.key=str("key",64);d.name=str("name",128);d.reason=str("reason",128);d.w=uint16_t(n("width",1,31,1));d.h=uint16_t(n("height",1,31,1));d.supported=boolean(L,"supported");d.family=str("family",64);d.subtype_key=str("subtype_key",64);d.custom_code=str("custom_code",64);d.native_name=str("native_name",128);d.area_mode=uint8_t(n("area_mode",0,4));d.orientations=uint8_t(n("orientations",0,255));d.max_width=uint16_t(n("max_width",0,31));d.max_height=uint16_t(n("max_height",0,31));d.max_depth=uint16_t(n("max_depth",0,256));d.filters=readFilters();each("footprints",8,[&](){d.footprints.push_back(readFootprint());});catalog.push_back(std::move(d));});
    construction.outcome=m::ConstructionOutcome(n("construction_outcome",0,4));
    construction.updated=uint32_t(n("updated",0,16384));construction.failed_index=int32_t(n("failed_index",-1,16384,-1));
    if(construction.updated || construction.placed || construction.outcome==m::ConstructionOutcome::Unknown)mutated=true;
    each("changed_tiles",16384,[&](){
      const auto x=n("x",0,INT32_MAX),y=n("y",0,INT32_MAX),z=n("z",0,INT32_MAX);
      if(!invalid)areaHints.push_back({int(x),int(y),int(z)});
    });
    construction.building_key=str("building_key",64);construction.filter=int16_t(n("filter",-1,7,-1));construction.filters=readFilters();
    construction.pressure_creatures.clear();
    construction.has_track=false;construction.track_path.clear();
    lua_getfield(L,-1,"track_preview");
    if(!lua_isnil(L,-1)) {
      if(!lua_istable(L,-1) || action!=m::ManagementAction::Preview || !r->connected_track())invalid=true;
      else {
        construction.has_track=true;construction.track_status=m::ConnectedTrackStatus(n("status",0,5,-1));
        each("path",m::kConnectedTrackMaxTiles,[&](){
          construction.track_path.emplace_back(int32_t(n("x",0,INT32_MAX,-1)),int32_t(n("y",0,INT32_MAX,-1)),int32_t(n("z",0,INT32_MAX,-1)));
        });
        const auto& path=construction.track_path;
        if(construction.track_status==m::ConnectedTrackStatus::Found) {
          if(path.size()<2)invalid=true;
          else {
            const auto same=[](const auto& a,const auto* b){return b && a.x()==b->x() && a.y()==b->y() && a.z()==b->z();};
            if(!same(path.front(),r->origin()) || !same(path.back(),r->connected_track()->destination()))invalid=true;
          }
        } else if(!path.empty())invalid=true;
      }
    }
    lua_pop(L,1);
    each("pressure_creatures",200,[&](){PressureCreatureExample v;v.size=int32_t(n("size",1000,200000));v.race_id=int32_t(n("race_id",-1,INT32_MAX,-1));v.name=str("name",128);
      if(v.size!=int32_t((construction.pressure_creatures.size()+1)*1000) || (v.race_id==-1 && !v.name.empty()))invalid=true;
      construction.pressure_creatures.push_back(std::move(v));});
    if(!construction.pressure_creatures.empty() && construction.pressure_creatures.size()!=200)invalid=true;
    size_t materialCandidateCount=0;
    construction.materials.clear();each("materials",128,[&](){ConstructionMaterial v;v.item_type=int16_t(n("item_type",-1,INT16_MAX,-1));v.item_subtype=int16_t(n("item_subtype",-1,INT16_MAX,-1));v.mat_type=int16_t(n("mat_type",-1,INT16_MAX,-1));v.mat_index=int32_t(n("mat_index",-1,INT32_MAX,-1));v.name=str("name",128);v.caption=str("caption",64);v.last_name=str("last_name",128);v.count=uint32_t(n("count",1,UINT32_MAX));v.individual_id=int32_t(n("individual_id",-1,INT32_MAX,-1));
      lua_getfield(L,-1,"candidates");const bool hasCandidates=!lua_isnil(L,-1);lua_pop(L,1);
      if(hasCandidates) { v.candidates.emplace();each("candidates",16384,[&](){if(++materialCandidateCount>16384){invalid=true;return;}ConstructionMaterialCandidate item;
        item.id=int32_t(n("id",0,INT32_MAX,-1));item.name=str("name",128);item.distance=uint32_t(n("distance",0,UINT32_MAX,-1));
        lua_getfield(L,-1,"appearance");
        if(!lua_isnil(L,-1)) {
          if(!lua_istable(L,-1))invalid=true;
          else { ConstructionItemAppearance a;
            a.material_token=str("material_token",256);a.subtype_raw=str("subtype_raw",128);a.color_token=str("color_token",128);
            a.stack=uint32_t(n("stack",1,INT32_MAX,0));a.flags=uint8_t(n("flags",0,96,0));
            if(a.material_token.empty() || (a.flags & ~uint8_t(96)))invalid=true;
            item.appearance=std::move(a); }
        }
        lua_pop(L,1);v.candidates->push_back(std::move(item));}); }
      construction.materials.push_back(std::move(v));});
    construction.total=uint32_t(n("total",0,UINT32_MAX));construction.list_revision=n("list_revision",0,INT64_MAX);construction.estimated=boolean(L,"estimated");
    construction.build_phase=uint8_t(n("build_phase",0,3));construction.build_done=uint32_t(n("build_done",0,UINT32_MAX));construction.build_total=uint32_t(n("build_total",0,UINT32_MAX));
    construction.valid_mask.clear();construction.pieces.clear();
    auto bytes=[&](const char* key,uint8_t max,std::vector<uint8_t>& values){each(key,1024,[&](){if(!lua_isinteger(L,-1) || lua_tointeger(L,-1)<0 || lua_tointeger(L,-1)>max)invalid=true;else values.push_back(uint8_t(lua_tointeger(L,-1)));});};
    bytes("valid_mask",1,construction.valid_mask);bytes("pieces",3,construction.pieces);
    lua_getfield(L,-1,"footprint");construction.hasFootprint=lua_istable(L,-1);if(construction.hasFootprint)construction.footprint=readFootprint();lua_pop(L,1);
    if(invalid){ok=false;productionPending=false;message="Invalid native construction response: field or page exceeds contract";catalog.clear();construction.filters.clear();construction.materials.clear();construction.pressure_creatures.clear();construction.has_track=false;construction.track_path.clear();}
  }
  lua_settop(L, top);
  status = !ok ? m::ManagementStatus::Rejected
               : (productionPending
                      ? m::ManagementStatus::Pending
                      : m::ManagementStatus::Ok);
  publish();
}
void stepBuilder(color_ostream& out,uint32_t budget) {
  const auto started=std::chrono::steady_clock::now();
  auto* L=Core::getInstance().getLuaState();const int top=lua_gettop(L);
  builderSteps+=df3d_builder::advance(builderTable,builderActive,builderStart,budget,
      [&](size_t kind,uint32_t share)->uint32_t {
    const auto slotStarted=std::chrono::steady_clock::now();
    const auto& entry=builderTable[kind];
    const int helper=helpers.acquire(entry.action,out,L);
    if(helper==LUA_NOREF){builderActive &= ~entry.domainMask;return 0;}
    lua_rawgeti(L,LUA_REGISTRYINDEX,helper);lua_newtable(L);
    field(L,"step",share);field(L,"builder_kind",kind);field(L,"epoch",epoch);
    if(kind==4){field(L,"restart_recalc",citizenRecalcPending && citizenHelperGeneration!=helpers.generation());citizenHelperGeneration=helpers.generation();}
    uint32_t used=0;
    if(Lua::SafeCall(out,L,1,1) && lua_istable(L,-1)) {
      const auto workError=areaAction(entry.action) ? areaWorkResultError(L,share) : std::string{};
      if(workError.empty()) {
        builderActive=(builderActive & ~entry.domainMask) |
            (uint32_t(number(L,"active_kinds")) & entry.domainMask);
        used=std::min(share,uint32_t(number(L,"steps")));
      } else {
        builderActive &= ~entry.domainMask;used=share;
        out.printerr("df3d: area builder contract failure: {}\n",workError);
      }
    } else {
      builderActive &= ~entry.domainMask;
      if(areaAction(entry.action))used=share; // Failed Lua may already have spent its slice.
    }
    if(kind==4 && lua_istable(L,-1)) {
      citizenRecalcPending=(builderActive & 0x10)!=0;
      citizenRecalcDone=uint32_t(number(L,"recalc_done"));citizenRecalcTotal=uint32_t(number(L,"recalc_total"));
    }
    if(kind==3 && lua_istable(L,-1)){constructionCacheEntries=uint32_t(number(L,"cache_entries"));constructionCacheIds=uint32_t(number(L,"cache_ids"));}
    auto& timing=builderTiming[kind];timing.stepsLast=used;timing.stepsMax=std::max(timing.stepsMax,used);
    timing.usLast=uint64_t(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-slotStarted).count());timing.usMax=std::max(timing.usMax,timing.usLast);
    lua_settop(L,top);return used;
  });
  builderLastUs=uint64_t(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-started).count());
  builderMaxUs=std::max(builderMaxUs,builderLastUs);
}
}  // namespace
bool printMaterialDistances(color_ostream& out,const std::array<int32_t,6>& positions,int32_t tileLimit) {
  auto* world=df::global::world;
  if(!world || world->map.x_count<=0 || world->map.y_count<=0 || world->map.z_count<=0)return false;
  auto* L=Core::getInstance().getLuaState();const int top=lua_gettop(L);
  const int helper=helpers.acquire(m::ManagementAction::Catalog,out,L);
  if(helper==LUA_NOREF){lua_settop(L,top);return false;}
  lua_rawgeti(L,LUA_REGISTRYINDEX,helper);lua_newtable(L);
  lua_pushboolean(L,true);lua_setfield(L,-2,"material_distance_query");
  lua_pushcfunction(L,df3d_construction::nativeMaterialDistances);lua_setfield(L,-2,"material_distances");
  const auto point=[&](int32_t x,int32_t y,int32_t z){lua_newtable(L);field(L,"x",x);field(L,"y",y);field(L,"z",z);};
  lua_newtable(L);point(positions[0],positions[1],positions[2]);lua_rawseti(L,-2,1);lua_setfield(L,-2,"seeds");
  lua_newtable(L);point(positions[3],positions[4],positions[5]);lua_rawseti(L,-2,1);lua_setfield(L,-2,"targets");
  point(world->map.x_count-1,world->map.y_count-1,world->map.z_count-1);lua_setfield(L,-2,"maximum");
  field(L,"tile_limit",tileLimit);
  bool ok=Lua::SafeCall(out,L,1,1) && lua_istable(L,-1);
  if(ok)ok=Lua::SafeCallString(out,L,"local result=...;return require('json').encode(result)",1,1) && lua_type(L,-1)==LUA_TSTRING;
  if(ok)out.print("{}\n",lua_tostring(L,-1));
  lua_settop(L,top);return ok;
}
bool printTrackMaterialCandidates(color_ostream& out,const std::array<int32_t,6>& positions,int32_t maximumCandidates,int32_t tileLimit) {
  auto* L=Core::getInstance().getLuaState();const int top=lua_gettop(L);
  const int helper=helpers.acquire(m::ManagementAction::Catalog,out,L);
  if(helper==LUA_NOREF){lua_settop(L,top);return false;}
  lua_rawgeti(L,LUA_REGISTRYINDEX,helper);lua_newtable(L);
  lua_pushboolean(L,true);lua_setfield(L,-2,"track_material_candidates_query");
  lua_pushcfunction(L,df3d_construction::routeTrack);lua_setfield(L,-2,"route_track");
  const auto point=[&](int32_t x,int32_t y,int32_t z){lua_newtable(L);field(L,"x",x);field(L,"y",y);field(L,"z",z);};
  point(positions[0],positions[1],positions[2]);lua_setfield(L,-2,"start");
  point(positions[3],positions[4],positions[5]);lua_setfield(L,-2,"destination");
  field(L,"maximum_candidates",maximumCandidates);
  if(tileLimit!=0) {
    lua_pushboolean(L,true);lua_setfield(L,-2,"material_order_query");
    lua_pushcfunction(L,df3d_construction::nativeMaterialDistances);lua_setfield(L,-2,"material_distances");
    field(L,"tile_limit",tileLimit);
  }
  bool ok=Lua::SafeCall(out,L,1,1) && lua_istable(L,-1);
  if(ok)ok=Lua::SafeCallString(out,L,"local result=...;return require('json').encode(result)",1,1) && lua_type(L,-1)==LUA_TSTRING;
  if(ok)out.print("{}\n",lua_tostring(L,-1));
  lua_settop(L,top);return ok;
}
void stop() {
  roomUndo.clear();
  helpers.reset();builderActive=0;builderStart=0;builderSteps=builderLastUs=0;
  areaHints.clear();terrainHint=false;mutated=false;

  if (region) {
    sh::atomicStoreRelease(&m::sessionOwner(region)->pid, 0);
    UnmapViewOfFile(region);
    region = nullptr;
  }
  if (mapping) {
    CloseHandle(mapping);
    mapping = nullptr;
  }
  reply.reset();
  epoch = revision = client = seq = 0;
  request.clear();
  clearResult();
  status = m::ManagementStatus::Idle;
  startBackoff.reset();
  warnedStartFailure = false;
}
bool takeMutation() {
  bool result = mutated;
  mutated = false;
  return result;
}
bool takeTerrainHint(int32_t& x, int32_t& y, int32_t& z) {
  if(!areaHints.empty()) {
    const auto p=areaHints.front();areaHints.pop_front();x=p[0];y=p[1];z=p[2];return true;
  }
  if (!terrainHint) return false;
  terrainHint = false;
  x = hintX;
  y = hintY;
  z = hintZ;
  return true;
}
// Timing rows start at the Residents domain: the construction, area,
// production and work-order actions before it predate the timing table and
// were never profiled through it.
constexpr size_t kFirstTimedAction = size_t(m::ManagementAction::CitizenList);
void printTiming(color_ostream& out) {
  for(size_t i=0;i<builderTable.size();++i)if(builderTable[i].enabled){const auto& t=builderTiming[i];out.print("  builder kind {}: steps {} / {} last/max; {} / {} us last/max\n",i,t.stepsLast,t.stepsMax,t.usLast,t.usMax);}
  out.print("  area holding {}/1024, {} bytes\n",areaHoldingCount,areaHoldingBytes);
  out.print("  work-detail holding {}/256; citizen recalc {}/{}\n",workDetailHoldingCount,citizenRecalcDone,citizenRecalcTotal);
  out.print("  construction cache: {} entries, {} ids; construction holding: none\n",constructionCacheEntries,constructionCacheIds);
  out.print("  work-order holding: {}/4096; builder steps: {}; {} / {} us last/max\n",workOrderHoldingCount,builderSteps,builderLastUs,builderMaxUs);
  out.print("  synchronous writes: {} measured steps; {} calls with unknown work\n",synchronousWriteSteps,synchronousWritesWithUnknownWork);
  for(size_t i=kFirstTimedAction;i<actionTimings.size();++i) {
    const auto& t=actionTimings[i];
    if(t.count) out.print("  management action {}: {} callbacks; {} / {} us last/max (native + serialization)\n",i,t.count,t.last,t.max);
  }
  out.print("  management requests: {} rejected before dispatch, {} stale citizen rows skipped\n",rejectedRequests,staleUnitsSkipped);
}
// A request that cannot be dispatched still gets a visible outcome: the
// broadcast region carries Rejected with the reason (and the client/seq when
// they parsed), and the console says so once per map load. Clients only
// watch the broadcast for world-epoch changes and read outcomes from their
// own mailbox, so when the caller could open that mailbox (`reply` set) the
// Rejected is published there too; publish() releases it afterwards.
void rejectRequest(color_ostream& out, bool& warned, const std::string& reason) {
  ++rejectedRequests;
  if(!warned){warned=true;out.printerr("df3d: management request rejected: {} (reported once per map load)\n",reason);}
  clearResult();
  status=m::ManagementStatus::Rejected;
  message=reason;
  publish();
}
void update(color_ostream& out, uint64_t worldEpoch, bool saving) {
  builderSteps=builderLastUs=0;remainingSteps=kWorkOrderStepBudget;
  for(auto& t:builderTiming){t.stepsLast=0;t.usLast=0;}
  if (!region) {
    if (!startBackoff.due()) return;
    if (!start(out)) { startBackoff.failed(kStartRetryUpdates); return; }
    startBackoff.reset();
  }
  if (epoch != worldEpoch) {
    roomUndo.clear();
    citizenRecalcPending=false;citizenRecalcDone=citizenRecalcTotal=0;
    helpers.reset();builderActive=0;builderStart=0;builderSteps=builderLastUs=0;
    actionTimings={};builderTiming={};constructionCacheEntries=constructionCacheIds=0;
    warnedMalformedRequest=warnedMailboxUnavailable=false;
    areaHints.clear();terrainHint=false;mutated=false;
    if(reply && status==m::ManagementStatus::Pending){status=m::ManagementStatus::Rejected;message="World changed before operation completed";publish();}
    reply.reset();
    epoch = worldEpoch;
    client = seq = 0;
    request.clear();
    clearResult();
    status = m::ManagementStatus::Idle;
    message = "World changed; refresh catalog";

    publish();
  }
  // Process-owned scratch: avoid a multi-megabyte native update stack allocation.
  static std::vector<uint8_t> commandBytes(m::kManagementCommandCapacity);
  auto* bytes=commandBytes.data();
  // One request and one shared builder budget per update, paused included.
  // Preserve the exact native operation through its following-update readback.
  // Reconnect/Catalog requests stay queued until the outcome has been published.
  auto n=status==m::ManagementStatus::Pending ? 0u : sh::popCommand(region,bytes,commandBytes.size());
  if(n==SIZE_MAX){sh::atomicStoreRelease(&region->cmdTail,sh::atomicLoadAcquire(&region->cmdHead));return;}
  if (n) {
    flatbuffers::Verifier v(bytes, n);
    if (!v.VerifyBuffer<m::ConstructionRequest>(nullptr)) {
      // Unparseable: no client id or seq to address; the broadcast state
      // still says a request was dropped and why.
      client=seq=0;
      rejectRequest(out,warnedMalformedRequest,"Malformed management request (FlatBuffers verification failed)");
      return;
    }
    auto* r = flatbuffers::GetRoot<m::ConstructionRequest>(bytes);
    if (auto invalid=m::validateConstructionRequest(*r)) {
      client=r->client_id();seq=r->seq();action=r->action();
      // client_id and seq parsed: address the Rejected to the client's
      // mailbox exactly as the accept path does, else it waits for its
      // timeout. A mailbox that cannot be opened or accept the seq leaves
      // only the broadcast and the console.
      auto rejectedReply=sh::ClientMailbox::open(m::kManagementRegionName,
          sh::atomicLoadAcquire(&m::sessionOwner(region)->generation),r->client_id(),m::kManagementVersion,m::kManagementCapacity);
      if(rejectedReply && rejectedReply->accept(r->seq())) reply=std::move(rejectedReply);
      rejectRequest(out,warnedMalformedRequest,*invalid=="Must span multiple elevations" ? *invalid : "Invalid management request: "+*invalid);
      return;
    }
    auto nextReply=sh::ClientMailbox::open(m::kManagementRegionName,
        sh::atomicLoadAcquire(&m::sessionOwner(region)->generation),r->client_id(),m::kManagementVersion,m::kManagementCapacity);
    if(!nextReply || !nextReply->accept(r->seq())) {
      client=r->client_id();seq=r->seq();action=r->action();
      rejectRequest(out,warnedMailboxUnavailable,nextReply ? "Client mailbox did not accept the request sequence" : "Client mailbox unavailable");
      return;
    }
    reply=std::move(nextReply);
    client=r->client_id();
    seq = r->seq();
    ++executionSerial;
    requestStarted = std::chrono::steady_clock::now();
    action = r->action();
    clearResult();
    request.assign(bytes, bytes + n);
    cursor = r->cursor();
    if (!m::managementRequestAdmitted(action,r->world_epoch(),epoch,saving)) {
      status = m::ManagementStatus::Rejected;
      message = "World changed or fortress unavailable; refresh catalog";
      publish();
      return;
    }
    if(!m::runtimeManagementAction(action)){status=m::ManagementStatus::Rejected;message="Native screen adapters are retired; semantic replacement unfinished";publish();return;}
    status = m::ManagementStatus::Pending;
  }
  if (status == m::ManagementStatus::Pending) {
    // A broken continuation must not starve every other client. A timeout is
    // an unconfirmed outcome, never evidence to replay a possible mutation.
    if (std::chrono::steady_clock::now() - requestStarted >= std::chrono::seconds(10)) {
      status = m::ManagementStatus::Rejected;
      if(construction.placed)mutated=true;
      message = "Operation did not confirm in time; refresh game state before another change";
      publish();
      request.clear();
      return;
    }
    if (saving || !epoch) {
      status = m::ManagementStatus::Rejected;
      if(construction.placed)mutated=true;
      message = "Fortress unavailable";
      publish();
      return;
    }
    const auto timingAction=static_cast<size_t>(action);
    const auto started=std::chrono::steady_clock::now();
    run(out);
    const auto elapsed=static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-started).count());
    if(timingAction<actionTimings.size()) {
      auto& t=actionTimings[timingAction];++t.count;t.last=elapsed;t.max=std::max(t.max,elapsed);
    }
  }
  if(citizenRecalcPending)builderActive|=0x10;
  if(!saving && epoch && builderActive && remainingSteps)stepBuilder(out,remainingSteps);
}
}  // namespace df3d_management
