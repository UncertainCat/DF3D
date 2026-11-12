#include "area_links.h"
#include "bed_appearance_native.h"
#include "stockpile_native.h"
#include "zone_native.h"
#include <json/json.h>
#include "tile_description_native.h"
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
#include <charconv>
#include <type_traits>
#include <array>
#include <deque>
#include <string_view>
#include <map>

#include "Core.h"
#include "TileTypes.h"
#include "modules/Buildings.h"
#include "df/world.h"
#include "df/plotinfost.h"
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
#include "df/item.h"
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
#include "farm_native.h"
#include "building_item_native.h"
#include "creature_overview_native.h"
#include "creature_office_native.h"
#include "creature_labor_native.h"
#include "creature_header_native.h"
#include "residents_query_native.h"
#include "residents_row_native.h"
#include "residents_specialization_native.h"
#include "residents_activity_description_native.h"
#include "job_settings_native.h"
#include "job_art_native.h"
#include "creature_follow_native.h"
#include "creature_expel_preview_native.h"
#include "creature_expel_action_native.h"
#include "creature_health_native.h"
#include "creature_health_pages_native.h"
#include "creature_military_native.h"
#include "creature_squad_native.h"
#include "creature_relations_native.h"
#include "creature_groups_native.h"
#include "creature_thoughts_native.h"
#include "creature_personality_native.h"
#include "creature_preferences_native.h"
#include "creature_needs_native.h"
#include "workshop_catalog_native.h"
#include "workshop_workers_page.h"
#include "workshop_orders_native.h"
#include "work_detail_native.h"
#include "work_detail_query_native.h"
#include "work_detail_row_native.h"
#include "work_detail_settings_native.h"
#include "standing_orders_native.h"
#include "hunter_ammunition_captions_native.h"
#include "chores_native.h"
#include "kitchen_native.h"
#include "stone_use_native.h"
#include "stocks_native.h"
#include "tasks_action_native.h"
#include "places_action_native.h"
#include "objects_native.h"
#include "justice_read.h"
#include "df/gamest.h"
#include "work_order_catalog_native.h"
#include "work_order_rows_native.h"
#include "work_order_conditions_native.h"
#include "work_order_art_native.h"
#include "work_order_art_draft_native.h"
#include "creature_skills_native.h"
#include "creature_knowledge_native.h"
#include "skills_caption_native.h"
#include "creature_items_native.h"
#include "farm_transaction.h"
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
#include "nobles_draft_native.h"
#include "nobles_symbol_name_native.h"
#include "nobles_symbol_display_native.h"
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
struct WorkOrderGroup { int16_t type=-1,subtype=-1; int32_t custom=-1; std::string name; uint32_t count=0; std::optional<std::string> customCode; };
struct WorkOrderTask { std::string key,name; int16_t jobType=-1; std::string reaction; int16_t itemType=-1,itemSubtype=-1,matType=-1; int32_t matIndex=-1; };
struct BridgeWorkOrderCondition : WorkOrderCondition {
  std::optional<std::string> itemCaption;
  int16_t itemSubtype=-1,matType=-1; int32_t matIndex=-1;
  std::vector<std::string> traits; uint8_t satisfaction=0; bool estimated=false; int32_t estimateCount=-1;
};
struct BridgeWorkOrderInfo : WorkOrderInfo {
  struct NativeState {m::WorkOrderPhase phase=m::WorkOrderPhase::Unknown;bool validationRequired=false,detailsAvailable=false;std::optional<std::string> workshopName;};
  std::optional<NativeState> nativeState;
  std::optional<std::vector<BridgeWorkOrderCondition>> suggestedConditions;
  int32_t position=-1; uint8_t detailKind=0; int32_t sizeRaw=-1,encrustFlags=0;
  int16_t matType=-1; int32_t matIndex=-1; uint32_t materialCategory=0;
  std::vector<WorkOrderInput> inputs;
  std::vector<BridgeWorkOrderCondition> conditions;
};
struct BridgeWorkOrderState : WorkOrderState {
  std::optional<df3d_production::WorkOrderDetailsObservation> details;
  std::optional<df3d_production::WorkOrderArtPage> art;
  int32_t detailsId=-1;
  int16_t detailsOption=-1;
  uint32_t detailsCursor=0;
  std::optional<df3d_production::NativeWorkOrderListState> nativeState;
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
// Safe-point request-local evidence; reset before every command.
bool citizenWriteStarted = false;
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
struct ConstructionItemAppearance { std::string material_token,subtype_raw,color_token,gem_shape_raw;uint32_t stack=1;uint8_t flags=0;df3d_bed::Facts bedding;int8_t instrument_family=-1,instrument_placed=-1,slab_engraving=-2; };
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
  uint32_t updated=0;int32_t failed_index=-1;std::string warnings;
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
  int8_t tombCitizens=-1,tombPets=-1,gatherTrees=-1,gatherShrubs=-1,gatherFallen=-1;
};
struct NativeArea {
  int32_t id=-1,x=0,y=0,z=0,owner=-1;
  int kind=0,zone=-1,w=0,h=0,barrels=0,bins=0,wheelbarrows=0,storageLimit=-1,overlapping=-1;
  uint32_t categories=0;
  bool active=false,linksOnly=false,ownerAllowed=false;
  std::string name,customName,ownerName;
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
struct NativeOwnerDisplay { uint16_t columns=45; std::string firstLine,secondLine,status; int32_t roomValue=0; std::optional<df3d_area::ZoneOwnerNameColor> nameColor; };
struct NativeAnimalDisplay { uint16_t columns=27; std::string firstLine,secondLine; bool combinedFits=false; std::string warning; df3d_area::ZoneOwnerNameColor nameColor; };
struct NativeAnimalContainer { df3d_area::ZoneAnimalContainer facts; ResidentAppearanceRecipe occupant; };
struct NativeAreaCandidate { int32_t id=-1; std::string name,profession; int8_t sex=-1,squadUse=-1; uint8_t mood=0; bool grazer=false,assigned=false; std::optional<NativeOwnerDisplay> ownerDisplay; ResidentAppearanceRecipe sheetIcon; m::AreaCandidateEntity entity=m::AreaCandidateEntity::Unknown; std::optional<NativeAnimalDisplay> animalDisplay; std::optional<df3d_area::ZoneAnimalStatus> animalStatus; std::optional<NativeAnimalContainer> animalContainer; std::optional<df3d_area::ZoneAnimalRestraint> animalRestraint; std::optional<std::array<uint8_t,3>> animalItemColor; std::optional<std::array<uint8_t,7>> squadSymbol; };
struct NativeAreaLink { int32_t id=-1; uint8_t kind=0,direction=0; std::string name; };
struct NativeLocationNamePage {
  df3d_area::LocationNameSnapshot snapshot;uint8_t component=0;std::string query;
  uint32_t cursor=0,total=0,next=0;bool truncated=false;
  std::vector<df3d_area::LocationNameWord> choices;
};
flatbuffers::Offset<m::LocationNameSnapshot> buildLocationName(flatbuffers::FlatBufferBuilder& b,const df3d_area::LocationNameSnapshot& s) {
  const auto& n=s.name;
  const auto value=m::CreateLocationNameValue(b,
      b.CreateVector(reinterpret_cast<const uint8_t*>(n.firstNameCp437.data()),n.firstNameCp437.size()),
      b.CreateVector(reinterpret_cast<const uint8_t*>(n.nicknameCp437.data()),n.nicknameCp437.size()),
      b.CreateVector(n.words.data(),n.words.size()),b.CreateVector(n.parts.data(),n.parts.size()),n.language,n.type,n.hasName);
  return m::CreateLocationNameSnapshot(b,s.siteId,s.id,s.kind,s.namerId,s.namerRace,df3d_area::locationNameRevision(s),value,b.CreateString(s.nativeHeader),b.CreateString(s.englishHeader));
}
bool publishableLocationName(const df3d_area::LocationNameSnapshot& s) {
  flatbuffers::FlatBufferBuilder b;b.Finish(buildLocationName(b,s));
  return !m::validateLocationNameSnapshot(*flatbuffers::GetRoot<m::LocationNameSnapshot>(b.GetBufferPointer()));
}
flatbuffers::Offset<m::LocationRecognition> buildLocationRecognition(flatbuffers::FlatBufferBuilder& b,const df3d_area::LocationRecognitionReceipt& r) {
  const auto& f=r.facts;
  return m::CreateLocationRecognition(b,f.siteId,f.locationId,f.religionId,r.revision,f.tier,f.rank,f.worshippers,
      f.priestThreshold,f.highPriestThreshold,static_cast<m::LocationRecognitionState>(df3d_area::locationRecognitionState(f)),b.CreateVector(f.continuingAgreements));
}
bool publishableLocationRecognition(const df3d_area::LocationRecognitionReceipt& r) {
  if(r.facts.continuingAgreements.size()>4096)return false;
  flatbuffers::FlatBufferBuilder b;auto value=buildLocationRecognition(b,r);b.Finish(value);
  return !m::validateLocationRecognition(*flatbuffers::GetRoot<m::LocationRecognition>(b.GetBufferPointer()));
}
flatbuffers::Offset<m::LocationReligiousStaff> buildLocationReligiousStaff(flatbuffers::FlatBufferBuilder& b,const df3d_area::LocationReligiousStaffReceipt& r) {
  return m::CreateLocationReligiousStaff(b,r.siteId,r.locationId,r.entityId,r.assignmentId,r.positionId,r.holderId,r.unitId,r.revision,r.removable);
}
bool publishableLocationReligiousStaff(const df3d_area::LocationReligiousStaffReceipt& r) {
  return r.siteId>=0 && r.locationId>=0 && r.entityId>=0 && r.assignmentId>=0 && r.positionId>=0 &&
      r.holderId>=-1 && r.unitId>=-1 && r.revision && r.revision<=uint64_t(INT64_MAX) &&
      (r.holderId!=-1 || (r.unitId==-1 && !r.removable));
}
struct NativeAreaPage {
  std::optional<df3d_area::LocationStaffAssignments> staffAssignments;
  std::optional<df3d_area::LocationStaffSpecializationReceipt> specialization;
  std::optional<df3d_area::LocationReligiousCandidatePage> religiousCandidates;
  std::optional<df3d_area::LocationReligiousAssignmentReceipt> religiousAssignment;
  uint64_t religiousListRevision=0;
  std::optional<df3d_area::LocationReligiousStaffReceipt> locationReligiousStaff;
  std::optional<df3d_area::LocationRecognitionReceipt> locationRecognition;
  std::optional<df3d_area::LocationNameSnapshot> locationName;
  std::optional<NativeLocationNamePage> locationNamePage;
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
  std::optional<std::string> queryBytes;
  uint8_t candidateKind=0,sort=0,buildPhase=0;
  bool sortDescending=false;
  int64_t listRevision=0,capturedTick=-1;
  uint32_t buildDone=0,buildTotal=0,omitted=0;
  int32_t settingsCount=-1;
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
std::optional<std::vector<df3d_hover::Description>> worldHover;
std::optional<df3d_creature::HeaderEditResult> creatureHeader;
std::optional<std::pair<int32_t,df::coord>> creaturePosition;
struct CreatureExpelResult {
  m::CreatureExpelOutcome outcome=m::CreatureExpelOutcome::Rejected;
  std::optional<df3d_creature::ExpelPreview> preview;
  std::vector<ResidentAppearanceRecipe> icons;
};
std::optional<CreatureExpelResult> creatureExpel;
struct CreatureKnowledgeResult {
  int32_t unitId=-1,kind=-1,id=-1;
  m::CreatureKnowledgeOutcome outcome=m::CreatureKnowledgeOutcome::Rejected;
  std::string text;
};
std::optional<CreatureKnowledgeResult> creatureKnowledge;
struct CreatureWorkshopResult {
  int32_t unitId=-1,buildingId=-1;
  m::CreatureWorkshopOutcome outcome=m::CreatureWorkshopOutcome::Rejected;
};
std::optional<CreatureWorkshopResult> creatureWorkshop;
struct CreatureLocationResult {
  int32_t unitId=-1,occupationId=-1;
  m::CreatureLocationOutcome outcome=m::CreatureLocationOutcome::Rejected;
};
std::optional<CreatureLocationResult> creatureLocation;
struct CreatureAnimalResult {
  int32_t unitId=-1,animalId=-1;
  m::CreatureAnimalOutcome outcome=m::CreatureAnimalOutcome::Rejected;
  bool assigned=false;
};
std::optional<CreatureAnimalResult> creatureAnimal;
std::optional<std::vector<int32_t>> residents;
// Strings are converted to UTF-8 and bounded before publishing this batch.
struct ResidentRowResult { int32_t id; df3d_residents::RowText text; std::optional<ResidentAppearanceRecipe> icon; df3d_residents::Specialization specialization; std::vector<df3d_area::LocationStaffAssignment> assignments; df::coord position; std::optional<df3d_residents::ActivityTarget> activityTarget; std::optional<df3d_production::JobSettingsTarget> jobTarget; std::optional<std::vector<df3d_production::WorkDetailSkillText>> workDetailSkills; int8_t detailMember=-1; };
std::optional<std::vector<ResidentRowResult>> residentsRows;
struct ResidentsSpecializationResult {int32_t id=-1;m::ResidentsSpecializationOutcome outcome=m::ResidentsSpecializationOutcome::Rejected;bool onlyAssigned=false;};
std::optional<ResidentsSpecializationResult> residentsSpecialization;
struct ResidentsActivityResult {int32_t unitId;df3d_residents::ActivityDescription description;};
std::optional<ResidentsActivityResult> residentsActivity;
struct JobSettingsResult {int32_t unitId=-1;uint32_t cursor=0;df3d_production::JobSettingsObservation value;std::optional<df3d_production::WorkOrderArtPage> art;};
std::optional<JobSettingsResult> jobSettings;
struct JobSettingsEditResult {int32_t jobId,buildingId,unitId;m::JobSettingsEditOutcome outcome;};
std::optional<JobSettingsEditResult> jobSettingsEdit;
struct WorkDetailSettingsResult {
  int32_t index=-1;uint64_t revision=0;bool editable=false,noModify=false;
  std::vector<int16_t> labors;std::vector<df3d_production::WorkDetailSetting> catalog;
};
std::optional<WorkDetailSettingsResult> workDetailSettings;
struct StandingOrdersResult {
  uint8_t category=0;
  m::StandingOrdersOutcome outcome=m::StandingOrdersOutcome::Rejected;
  std::optional<df3d_standing::WorkshopSettings> settings;
  std::optional<df3d_standing::CategorySettings> categorySettings;
};
std::optional<StandingOrdersResult> standingOrders;
struct HunterResult {
  struct Stack {int32_t id,quantity;std::string caption;df3d_production::ItemInspectionAppearance appearance;};
  struct Rule {std::string caption;int64_t quantity=0;std::vector<Stack> items;};
  m::HunterAmmunitionOutcome outcome=m::HunterAmmunitionOutcome::Rejected;
  int16_t type=-1,subtype=-1;
  df3d_hunter_ammunition::Snapshot specs;
  std::vector<Rule> rules;
  std::vector<std::pair<df3d_hunter_ammunition::Type,std::string>> types;
  std::vector<std::pair<df3d_hunter_ammunition::Material,std::string>> materials;
};
std::optional<HunterResult> hunter;
struct ChoresResult {
  m::ChoresOutcome outcome=m::ChoresOutcome::Rejected;
  std::optional<df3d_chores::Snapshot> snapshot;
  df3d_chores::Captions captions;
};
std::optional<ChoresResult> chores;
struct KitchenResult {
  m::KitchenMenuOutcome outcome=m::KitchenMenuOutcome::Rejected;
  std::vector<df3d_kitchen::Row> rows;
  std::vector<df3d_kitchen::Display> display;
  std::vector<df3d_kitchen::Exclusion> exclusions;
};
std::optional<KitchenResult> kitchen;
struct StoneUseResult {
  m::StoneUseOutcome outcome=m::StoneUseOutcome::Rejected;
  std::vector<df3d_stone_use::Row> rows;
  std::vector<uint8_t> restrictions;
};
std::optional<StoneUseResult> stoneUse;
// Revisions cover semantic edit preconditions, not artwork or animation phase.
uint64_t tasksRowRevision(const df3d_tasks::Row& row) {
  uint64_t h=UINT64_C(14695981039346656037);
  for(int64_t value:{int64_t(row.jobId),int64_t(row.unitId),int64_t(row.buildingId),int64_t(row.itemId),
      int64_t(row.flags),int64_t(row.canViewJob),int64_t(row.canRepeat),int64_t(row.canRemoveWorker),
      int64_t(row.canSuspend),int64_t(row.canCancel),int64_t(row.repeating),int64_t(row.suspended)})
    for(unsigned i=0;i<8;++i){h^=uint8_t(uint64_t(value)>>(8*i));h*=UINT64_C(1099511628211);}
  return (h&INT64_MAX)?h&INT64_MAX:1;
}
struct TasksResult {
  m::TasksOutcome outcome=m::TasksOutcome::Rejected;
  uint64_t listRevision=0;uint32_t total=0,offset=0;int32_t jobId=-1;
  std::vector<df3d_tasks::Row> rows;
};
std::optional<TasksResult> tasks;
struct NoblesResult {
  m::NoblesOutcome outcome=m::NoblesOutcome::Rejected;uint64_t listRevision=0;uint32_t total=0,offset=0;
  std::vector<df3d_nobles::Row> rows;
  std::optional<m::NoblesOffice> target;uint64_t candidateRevision=0;
  std::vector<df3d_nobles::Candidate> candidates;
  struct Symbol {df3d_nobles::SymbolRow facts;df3d_nobles::SymbolDisplay text;int16_t type=-1;std::optional<ItemInspectionAppearance> appearance;bool artifactMood=false;};
  std::vector<Symbol> symbols;
  std::optional<std::string> symbolTargetCaption;
  struct Step {uint64_t token=0;int32_t artifact=-1;uint32_t remaining=0;};
  std::optional<Step> step;
  struct Name {df3d_nobles::SymbolName snapshot;uint8_t component=0;std::string query;uint32_t cursor=0,total=0,next=0;std::vector<df3d_area::LocationNameWord> choices;};
  std::optional<Name> name;
};
std::optional<NoblesResult> nobles;
// One symbol workflow owns the native effect sequence. It retains values only;
// every step rebuilds an independent administrators context at the safe point.
struct NoblesSymbolOwner {
  uint64_t client=0,epoch=0,token=0,baseRevision=0,candidateRevision=0;
  df3d_nobles::OfficeKey office;
  std::vector<df3d_nobles::DraftChoice> draft;
  std::vector<df3d_nobles::SymbolChoice> remaining;
  int32_t artifact=-1;bool uncertain=false;
};
std::optional<NoblesSymbolOwner> noblesSymbolOwner;
struct ObjectsRow {df3d_objects::Names names;std::string ownership;df3d_objects::Destination destination;int16_t itemType=-1;std::optional<ItemInspectionAppearance> appearance;};
struct ObjectsResult {
  m::ObjectsOutcome outcome=m::ObjectsOutcome::Rejected;uint8_t tab=0;
  uint64_t listRevision=0;uint32_t total=0,offset=0;std::vector<ObjectsRow> rows;
  int32_t artifactId=-1;std::optional<df3d_objects::Destination> destination;
};
std::optional<ObjectsResult> objects;
std::optional<df3d_justice::ReadResult> justice;
struct PlacesResult {
  m::PlacesOutcome outcome=m::PlacesOutcome::Rejected;uint8_t tab=0;
  uint64_t listRevision=0;uint32_t total=0,offset=0;std::vector<df3d_places::BuildingRow> rows;
  int32_t buildingId=-1;int8_t siegeAction=-1;
};
std::optional<PlacesResult> places;
struct StocksItemResult : df3d_production::ItemFacts {
  std::optional<df3d_production::ItemInspectionAppearance> appearance;
};
struct StocksResult {
  m::StocksMenuOutcome outcome=m::StocksMenuOutcome::Rejected;
  int16_t category=-1;
  std::vector<df3d_stocks::CategoryDisplay> categories;
  std::vector<int16_t> matches;
  df3d_stocks::Selection selection;
  std::vector<StocksItemResult> items;
};
std::optional<StocksResult> stocks;
df3d::stocks_pages::Store stocksReplies;

// Category -1 requests only the catalog. Selection and expansion belong to
// the viewer; no native menu state is read or changed by this snapshot.
StocksResult readStocks(int16_t category,const std::string& query,
    const std::vector<int32_t>& ids,std::optional<df3d_stocks::Selection> receipt=std::nullopt) {
  StocksResult result;
  auto display=df3d_stocks::categoryDisplay();
  auto order=df3d_stocks::categories("");
  auto matches=query.empty()?order:df3d_stocks::categories(query);
  if(!display || !order || !matches)throw std::runtime_error("stocks catalog unavailable");
  for(auto type:*order){auto row=display->at(type);
    row.caption=DF2UTF(row.caption);row.stored=DF2UTF(row.stored);row.unavailable=DF2UTF(row.unavailable);
    result.categories.push_back(std::move(row));}
  result.matches=std::move(*matches);result.category=category;
  if(category>=0){
    if(!receipt)receipt=df3d_stocks::selection(category,query);
    if(!receipt)throw std::runtime_error("stocks selection unavailable");
    result.selection=std::move(*receipt);
    for(auto& row:result.selection.groups)row.caption=DF2UTF(row.caption);
  }
  for(auto id:ids){
    if(std::find(result.selection.ids.begin(),result.selection.ids.end(),id)==result.selection.ids.end())
      throw std::runtime_error("stocks item no longer eligible");
    auto row=df3d_production::itemFacts(df::item::find(id));
    if(!row || row->itemType!=category)throw std::runtime_error("stocks item unavailable");
    row->caption=DF2UTF(row->caption);
    StocksItemResult item;static_cast<df3d_production::ItemFacts&>(item)=std::move(*row);
    item.appearance=df3d_production::itemAppearance(df::item::find(id));
    result.items.push_back(std::move(item));
  }
  return result;
}


m::TilePos worldHoverTile;
void clearResult() {
  creatureHeader.reset();
  creaturePosition.reset();
  creatureExpel.reset();
  creatureKnowledge.reset();
  creatureWorkshop.reset();
  creatureLocation.reset();
  creatureAnimal.reset();
  residents.reset();
  residentsRows.reset();
  residentsSpecialization.reset();
  residentsActivity.reset();
  jobSettings.reset();jobSettingsEdit.reset();workDetailSettings.reset();standingOrders.reset();hunter.reset();chores.reset();kitchen.reset();stoneUse.reset();stocks.reset();tasks.reset();objects.reset();justice.reset();places.reset();nobles.reset();
  worldHover.reset();
  construction = {};
  production = {};
  workOrders = {};
  citizens = {};
  citizenWriteStarted=false;
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
flatbuffers::Offset<m::WorkOrderArtState> encodeNativeArt(flatbuffers::FlatBufferBuilder& b,const df3d_production::WorkOrderArtPage& a,bool utf8=false) {
  const auto text=[&](const std::string& value){return utf8?value:DF2UTF(value);};
std::vector<flatbuffers::Offset<m::WorkOrderArtRow>> rows;
      for(const auto& row:a.rows)rows.push_back(m::CreateWorkOrderArtRow(b,row.id,b.CreateString(text(row.caption)),row.badge?b.CreateString(text(*row.badge)):0,row.secondary));
      flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>> preview;
      if(a.preview){std::vector<flatbuffers::Offset<flatbuffers::String>> lines;for(const auto& line:*a.preview)lines.push_back(b.CreateString(text(line)));preview=b.CreateVector(lines);}
      flatbuffers::Offset<m::WorkOrderArtDraftValue> draft;
      flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>> description;
      if(a.draft) {
        std::vector<flatbuffers::Offset<m::WorkOrderArtDraftElement>> elements;
        std::vector<flatbuffers::Offset<m::WorkOrderArtDraftRelationship>> relationships;
        for(const auto& e:a.draft->elements)elements.push_back(m::CreateWorkOrderArtDraftElement(b,e.kind,e.id,e.secondary,e.quantity));
        for(const auto& r:a.draft->relationships)relationships.push_back(m::CreateWorkOrderArtDraftRelationship(b,r.verb,r.transitive,r.actor,r.target));
        flatbuffers::Offset<m::LocationNameValue> name;
        if(a.draft->name) {
          const auto& n=*a.draft->name;std::vector<int16_t> parts;for(auto part:n.parts_of_speech)parts.push_back(int16_t(part));
          name=m::CreateLocationNameValue(b,b.CreateVector(reinterpret_cast<const uint8_t*>(n.first_name.data()),n.first_name.size()),
            b.CreateVector(reinterpret_cast<const uint8_t*>(n.nickname.data()),n.nickname.size()),b.CreateVector(n.words.data(),n.words.size()),b.CreateVector(parts),n.language,int16_t(n.type),n.has_name);
        }
        draft=m::CreateWorkOrderArtDraftValue(b,b.CreateVector(elements),b.CreateVector(relationships),name);
      }
      if(a.draftDescription){std::vector<flatbuffers::Offset<flatbuffers::String>> lines;for(const auto& line:*a.draftDescription)lines.push_back(b.CreateString(text(line)));description=b.CreateVector(lines);}
      flatbuffers::Offset<m::WorkOrderArtName> namePage;
      if(a.name) {
        const auto& n=*a.name;std::vector<flatbuffers::Offset<m::LocationNameChoice>> choices;
        for(const auto& row:n.choices)choices.push_back(m::CreateLocationNameChoice(b,row.word,int16_t(row.partOfSpeech),b.CreateString(row.english),b.CreateString(row.translated)));
        namePage=m::CreateWorkOrderArtName(b,b.CreateString(n.nativeHeader),b.CreateString(n.englishHeader),n.component,
          b.CreateVector(reinterpret_cast<const uint8_t*>(n.query.data()),n.query.size()),n.cursor,n.total,n.nextCursor,b.CreateVector(choices));
      }
      return m::CreateWorkOrderArtState(b,a.page,b.CreateString(text(a.caption)),b.CreateVector(rows),a.listRevision,a.total,a.nextCursor,a.hovered,preview,draft,description,namePage);
}

void processJobDraft(df::job& source,int32_t unitId,int32_t buildingId,int16_t option,uint64_t revision,const m::WorkOrderArtRequest& art,bool writing) {
  bool uncertain=false;
  try {
    auto root=df3d_production::nativeJobSettings(source,-1,{},false);
    if(!root || root->buildingId!=buildingId || root->revision!=revision)return;
    if(writing)jobSettingsEdit->outcome=m::JobSettingsEditOutcome::Rejected;
    if(option<0 || size_t(option)>=root->options.size())return;
    const auto kind=root->options[size_t(option)].kind;
    if((kind!=1 && kind!=3) || (kind==3 && int(source.specdata.improvement)!=0))return;
    const auto* a=&art;const auto* draft=a->draft();if(!draft)return;
    const auto draftAction=uint8_t(draft->action());
    const bool worldWrite=draftAction==4 || draftAction==5 || (draftAction==6 && draft->name_edit() && uint8_t(draft->name_edit()->mode())>=2);
    if(writing!=worldWrite)return;
    df3d_production::WorkOrderArtDraftValue value;
    const auto element=[](const m::WorkOrderArtDraftElement& e){return df3d_production::WorkOrderArtDraftElementValue{e.kind(),e.id(),e.secondary(),e.quantity()};};
    const auto relationship=[](const m::WorkOrderArtDraftRelationship& r){return df3d_production::WorkOrderArtDraftRelationshipValue{r.verb(),r.transitive(),r.actor(),r.target()};};
    for(const auto* e:*draft->value()->elements())value.elements.push_back(element(*e));
    for(const auto* r:*draft->value()->relationships())value.relationships.push_back(relationship(*r));
    if(const auto* n=draft->value()->name()) {
      value.name.emplace();auto& name=*value.name;
      name.first_name.assign(reinterpret_cast<const char*>(n->first_name_bytes()->data()),n->first_name_bytes()->size());
      name.nickname.assign(reinterpret_cast<const char*>(n->nickname_bytes()->data()),n->nickname_bytes()->size());
      for(size_t i=0;i<7;++i){name.words[i]=n->words()->Get(i);name.parts_of_speech[i]=df::part_of_speech(n->parts()->Get(i));}
      name.language=n->language();name.type=df::language_name_type(n->type());name.has_name=n->has_name();
    }
    std::optional<df3d_production::WorkOrderArtDraftElementValue> added;
    std::optional<df3d_production::WorkOrderArtDraftRelationshipValue> relation;
    if(draft->element())added=element(*draft->element());if(draft->relationship())relation=relationship(*draft->relationship());

    if(draftAction==5) {
      using O=df3d_production::JobArtDraftOutcome;
      const auto outcome=df3d_production::commitJobArtDraft(source,{source.id,buildingId},revision,option,value);
      jobSettingsEdit->outcome=outcome==O::Applied?m::JobSettingsEditOutcome::Applied:outcome==O::Unknown?m::JobSettingsEditOutcome::Unknown:outcome==O::Stale?m::JobSettingsEditOutcome::Stale:m::JobSettingsEditOutcome::Rejected;
      if(outcome==O::Applied)status=m::ManagementStatus::Ok;
      return;
    }
    std::optional<df3d_production::WorkOrderArtNameQuery> nameQuery;
    std::optional<df3d_production::WorkOrderArtNameEdit> nameEdit;
    if(const auto* n=draft->name_query())nameQuery=df3d_production::WorkOrderArtNameQuery{n->component(),std::string(reinterpret_cast<const char*>(n->query_bytes()->data()),n->query_bytes()->size()),n->cursor()};
    if(const auto* n=draft->name_edit())nameEdit=df3d_production::WorkOrderArtNameEdit{uint8_t(n->mode()),n->target(),n->displayed(),n->word(),n->part(),std::string(reinterpret_cast<const char*>(n->query_bytes()->data()),n->query_bytes()->size())};

    uncertain=writing;
    auto page=df3d_production::nativeJobArtDraftPage(source,a->page(),std::move(value),draftAction,added,relation,draft->delete_index(),a->query()?UTF2DF(a->query()->str()):std::string{},a->cursor(),a->expected_list_revision(),draft->columns(),nameQuery?&*nameQuery:nullptr,nameEdit?&*nameEdit:nullptr);
    if(!page){if(uncertain)jobSettingsEdit->outcome=m::JobSettingsEditOutcome::Unknown;return;}
    const auto convert=[](std::string& text,size_t limit){text=DF2UTF(text);return text.size()<=limit && text.find('\0')==std::string::npos;};
    bool bounded=page->revision==revision && convert(root->caption,512) && convert(page->page.caption,512);
    for(auto& o:root->options)if(!convert(o.caption,512))bounded=false;
    for(auto& row:page->page.rows)if(!convert(row.caption,1024) || (row.badge && !convert(*row.badge,128)))bounded=false;
    if(page->page.draftDescription)for(auto& line:*page->page.draftDescription)if(!convert(line,2048))bounded=false;
    if(!bounded){if(uncertain)jobSettingsEdit->outcome=m::JobSettingsEditOutcome::Unknown;return;}
    root->selected=option;jobSettings=JobSettingsResult{unitId,0,std::move(*root),std::move(page->page)};
    if(writing)jobSettingsEdit->outcome=m::JobSettingsEditOutcome::Applied;
    status=m::ManagementStatus::Ok;
  } catch(...) {jobSettings.reset();if(writing)jobSettingsEdit->outcome=uncertain?m::JobSettingsEditOutcome::Unknown:m::JobSettingsEditOutcome::Rejected;}
}

bool publishStocksPage(df3d::stocks_pages::Identity identity,uint32_t offset) {
  const auto page=stocksReplies.read(identity,offset);if(!page)return false;
  flatbuffers::FlatBufferBuilder b;
  const auto part=m::CreateStocksReplyPage(b,identity.request,page->total,page->offset,b.CreateVector(page->bytes));
  m::ManagementStateBuilder state(b);state.add_revision(++revision);state.add_world_epoch(epoch);
  state.add_client_id(client);state.add_request_seq(seq);state.add_action(action);state.add_status(m::ManagementStatus::Pending);state.add_stocks_page(part);
  b.Finish(state.Finish());
  sh::publishSnapshot(region,b.GetBufferPointer(),b.GetSize(),revision);
  if(reply)sh::publishSnapshot(reply->region(),b.GetBufferPointer(),b.GetSize(),revision);
  reply.reset();status=m::ManagementStatus::Ok;return true;
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
          flatbuffers::Offset<m::BeddingFacts> bedding;
          if(a.bedding.sheet>=0)bedding=m::CreateBeddingFactsDirect(b,a.bedding.sheet,a.bedding.pillow,a.bedding.baseColor.c_str(),a.bedding.sheetColor.c_str());
          appearance=m::CreateConstructionItemAppearance(b,b.CreateString(a.material_token),b.CreateString(a.subtype_raw),b.CreateString(a.color_token),a.stack,a.flags,bedding,a.instrument_family,a.instrument_placed,a.slab_engraving,b.CreateString(a.gem_shape_raw)); }
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
    construction.hasFootprint ? footprint(construction.footprint) : flatbuffers::Offset<m::ConstructionFootprint>{},b.CreateVector(pressureCreatures),trackPreview,construction.outcome,construction.updated,construction.failed_index,b.CreateString(construction.warnings));
  std::vector<flatbuffers::Offset<m::ConstructionInput>> is;
  for (auto& i : inputs)
    is.push_back(m::CreateConstructionInput(b, i.id, b.CreateString(i.description), i.quantity));
  std::vector<flatbuffers::Offset<m::AreaInfo>> as;
  for(const auto& a:areas) {
    m::TilePos pos(a.x,a.y,a.z);
    const auto& z=a.zoneSettings;
    const auto zone=m::CreateAreaZoneSettings(b,z.pondMode,z.facing,z.tombCitizens,z.tombPets,z.gatherTrees,z.gatherShrubs,z.gatherFallen);
    as.push_back(m::CreateAreaInfo(b,a.id,m::AreaKind(a.kind),b.CreateString(a.name),&pos,a.w,a.h,
      b.CreateVector(a.extents),a.zone,a.categories,a.barrels,a.bins,a.wheelbarrows,a.linksOnly,
      a.active,a.owner,b.CreateString(a.ownerName),a.ownerAllowed,b.CreateVector(a.gives),b.CreateVector(a.takes),
      uint64_t(a.revision),b.CreateString(a.zoneLabel),a.locationId,b.CreateString(a.locationName),b.CreateString(a.religion),
      a.organic,a.inorganic,zone,a.tileCount,a.assignedCount,a.locationKind,b.CreateString(a.ownerProfession),a.ownerSex,a.locationSiteId,a.storageLimit,b.CreateString(a.customName),int8_t(a.overlapping)));
  }
  std::vector<flatbuffers::Offset<m::AreaChoice>> ac;
  for(const auto& c:areaChoices) ac.push_back(m::CreateAreaChoice(b,c.id,b.CreateString(c.name),b.CreateString(c.label)));
  std::vector<flatbuffers::Offset<m::AreaSettingRow>> settings;
  std::vector<flatbuffers::Offset<m::AreaLocationRow>> locations;
  std::vector<flatbuffers::Offset<m::AreaCandidateRow>> candidates;
  std::vector<flatbuffers::Offset<m::AreaLinkRow>> links;
  for(const auto& v:areaPage.settings)settings.push_back(m::CreateAreaSettingRow(b,b.CreateString(v.key),v.index,b.CreateString(v.label),v.kind,v.state,v.estimated));
  for(const auto& v:areaPage.locations)locations.push_back(m::CreateAreaLocationRow(b,v.id,b.CreateString(v.name),v.kind,b.CreateString(v.religion),v.guildProfession,v.locationTier,v.siteId));
  for(const auto& v:areaPage.candidates) {
    flatbuffers::Offset<m::AreaOwnerDisplay> display;
    if(v.ownerDisplay) {const auto& d=*v.ownerDisplay;flatbuffers::Offset<m::AreaNameColor> color;
      if(d.nameColor) {const auto& c=*d.nameColor;color=m::CreateAreaNameColor(b,c.color[0],c.color[1],c.color[2],c.alternate[0],c.alternate[1],c.alternate[2],c.effect);}
      display=m::CreateAreaOwnerDisplay(b,d.columns,b.CreateString(d.firstLine),b.CreateString(d.secondLine),b.CreateString(d.status),d.roomValue,color);}
    flatbuffers::Offset<m::AreaAnimalDisplay> animalDisplay;
    if(v.animalDisplay) {const auto& d=*v.animalDisplay;const auto& c=d.nameColor;
      const auto color=m::CreateAreaNameColor(b,c.color[0],c.color[1],c.color[2],c.alternate[0],c.alternate[1],c.alternate[2],c.effect);
      animalDisplay=m::CreateAreaAnimalDisplay(b,d.columns,b.CreateString(d.firstLine),b.CreateString(d.secondLine),d.combinedFits,b.CreateString(d.warning),color);}
    flatbuffers::Offset<m::AreaAnimalStatus> animalStatus;
    if(v.animalStatus) {const auto& s=*v.animalStatus;animalStatus=m::CreateAreaAnimalStatus(b,s.kind,s.containment,s.itemId);}
    flatbuffers::Offset<m::AreaAnimalContainer> container;
    if(v.animalContainer) {const auto& c=*v.animalContainer;container=m::CreateAreaAnimalContainer(b,c.facts.materialFamily,b.CreateString(c.facts.solidColor),c.facts.occupantEntity,c.facts.occupantId,c.occupant.build(b));}
    flatbuffers::Offset<m::AreaAnimalRestraint> restraint;
    if(v.animalRestraint)restraint=m::CreateAreaAnimalRestraint(b,v.animalRestraint->rope,b.CreateString(v.animalRestraint->solidColor));
    flatbuffers::Offset<m::AreaAnimalItemColor> itemColor;
    if(v.animalItemColor){const auto& c=*v.animalItemColor;itemColor=m::CreateAreaAnimalItemColor(b,c[0],c[1],c[2]);}
    flatbuffers::Offset<m::AreaSquadSymbol> squadSymbol;
    if(v.squadSymbol){const auto& s=*v.squadSymbol;squadSymbol=m::CreateAreaSquadSymbol(b,s[0],s[1],s[2],s[3],s[4],s[5],s[6]);}
    candidates.push_back(m::CreateAreaCandidateRow(b,v.id,b.CreateString(v.name),b.CreateString(v.profession),v.sex,v.mood,v.grazer,v.assigned,v.squadUse,display,v.sheetIcon.build(b),v.entity,animalDisplay,animalStatus,container,restraint,itemColor,squadSymbol));
  }
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
  flatbuffers::Offset<m::LocationReligiousCandidates> religiousCandidates;
  if(areaPage.religiousCandidates) {
    const auto& p=*areaPage.religiousCandidates;
    std::vector<flatbuffers::Offset<m::LocationStaffCandidate>> rows;
    for(const auto& r:p.rows) {
      std::vector<flatbuffers::Offset<m::LocationStaffSkill>> skills;
      for(const auto& s:r.skills)skills.push_back(m::CreateLocationStaffSkill(b,s.id,s.rating,s.experience,s.weight));
      rows.push_back(m::CreateLocationStaffCandidate(b,r.unitId,r.histfigId,b.CreateString(r.name),r.score,b.CreateVector(skills),
          b.CreateString(r.baseName),b.CreateString(r.professionName),r.professionColor,r.legendary,
          r.sourceIndex,r.professionOrder,r.statusOrder,b.CreateVector(r.nameSortKey),b.CreateVector(r.professionSortKey)));
    }
    religiousCandidates=m::CreateLocationReligiousCandidates(b,buildLocationReligiousStaff(b,p.target),p.revision,
        areaPage.locationCursor,p.nextCursor,p.total,b.CreateVector(rows));
    if(m::validateLocationCandidatePage(*flatbuffers::GetTemporaryPointer(b,religiousCandidates))) {
      religiousCandidates=0;status=m::ManagementStatus::Rejected;
    }
  }
  flatbuffers::Offset<m::LocationReligiousAssignment> religiousAssignment;
  if(areaPage.religiousAssignment) {
    const auto& r=*areaPage.religiousAssignment;
    religiousAssignment=m::CreateLocationReligiousAssignment(b,buildLocationReligiousStaff(b,r.target),
        r.unitId,r.histfigId,r.nemesisId,r.revision,areaPage.religiousListRevision,r.eligible);
  }
  flatbuffers::Offset<m::LocationSpecialization> specialization;
  flatbuffers::Offset<m::LocationStaffAssignments> staffAssignments;
  if(areaPage.staffAssignments) {
    const auto& r=*areaPage.staffAssignments;
    std::vector<flatbuffers::Offset<m::LocationStaffAssignment>> entries;
    for(const auto& e:r.entries)entries.push_back(m::CreateLocationStaffAssignment(b,
        static_cast<m::LocationStaffAssignmentKind>(e.kind),e.id,e.type,e.subtype,e.custom,b.CreateString(e.name),b.CreateString(e.customCode)));
    staffAssignments=m::CreateLocationStaffAssignments(b,r.siteId,r.locationId,r.occupationId,r.entityId,r.assignmentId,
        r.unitId,r.histfigId,r.revision,b.CreateVector(entries));
  }
  if(areaPage.specialization) {
    const auto& r=*areaPage.specialization;
    specialization=m::CreateLocationSpecialization(b,r.siteId,r.locationId,r.occupationId,r.entityId,r.assignmentId,
        r.unitId,r.histfigId,r.revision,r.eligible,r.specialized);
  }
  flatbuffers::Offset<m::LocationNameSnapshot> locationName;
  flatbuffers::Offset<m::LocationNamePage> locationNamePage;
  if(areaPage.locationName)locationName=buildLocationName(b,*areaPage.locationName);
  if(areaPage.locationNamePage) {
    const auto& p=*areaPage.locationNamePage;auto snapshot=buildLocationName(b,p.snapshot);
    std::vector<flatbuffers::Offset<m::LocationNameChoice>> rows;
    for(const auto& c:p.choices)rows.push_back(m::CreateLocationNameChoice(b,c.word,int16_t(c.partOfSpeech),b.CreateString(c.english),b.CreateString(c.translated)));
    locationNamePage=m::CreateLocationNamePage(b,snapshot,p.component,b.CreateVector(reinterpret_cast<const uint8_t*>(p.query.data()),p.query.size()),
        p.cursor,p.total,p.next,p.truncated,b.CreateVector(rows));
  }
  flatbuffers::Offset<m::LocationRecognition> recognition;
  if(areaPage.locationRecognition)recognition=buildLocationRecognition(b,*areaPage.locationRecognition);
  flatbuffers::Offset<m::LocationReligiousStaff> religiousStaff;
  if(areaPage.locationReligiousStaff)religiousStaff=buildLocationReligiousStaff(b,*areaPage.locationReligiousStaff);
  auto areaResult=m::CreateAreaState(b,b.CreateVector(as),b.CreateVector(ac),areaCursor,areaTruncated,
      areaPage.operation,areaPage.id,b.CreateString(areaPage.listKey),areaPage.candidateKind,areaPage.sort,areaPage.sortDescending,
      b.CreateString(areaPage.query),b.CreateVector(settings),b.CreateVector(locations),b.CreateVector(candidates),b.CreateVector(links),
      uint64_t(areaPage.listRevision),areaPage.buildPhase,areaPage.buildDone,areaPage.buildTotal,areaPage.omitted,areaPage.capturedTick,
      areaPage.interactionId,areaPage.undoToken,areaPage.roomOutcome,areaPage.roomsCreated,
      areaPage.roomsInUse,areaPage.roomsUnenclosed,areaPage.roomsRemoved,areaPage.roomsDormitories,
      areaPage.countGeneration,areaPage.paintedCount,areaPage.previewCount,locationCatalog,locationDetails,areaPage.locationEntryOutcome,areaPage.locationEditOutcome,staffCandidates,areaPage.settingsCount,
      areaPage.queryBytes?b.CreateVector(reinterpret_cast<const uint8_t*>(areaPage.queryBytes->data()),areaPage.queryBytes->size()):flatbuffers::Offset<flatbuffers::Vector<uint8_t>>{},locationName,locationNamePage,recognition,religiousStaff,religiousCandidates,religiousAssignment,specialization,staffAssignments);
  auto reqs=[&](const std::vector<ProductionRequirement>& values){
    std::vector<flatbuffers::Offset<m::ProductionRequirement>> out;
    for(const auto& v:values) out.push_back(m::CreateProductionRequirement(b,b.CreateString(v.description),v.quantity,v.itemType));
    return b.CreateVector(out);
  };
  std::vector<flatbuffers::Offset<m::ProductionBuilding>> pb;
  for(const auto& v:production.buildings){m::TilePos p(v.x,v.y,v.z);pb.push_back(m::CreateProductionBuilding(b,v.id,b.CreateString(v.name),b.CreateString(v.kind),&p,v.buildStage,v.maxStage,v.queueSize));}
  std::vector<flatbuffers::Offset<m::ProductionRecipe>> pr;
  for(const auto& v:production.recipes) {
    flatbuffers::Offset<m::ProductionAvailability> availability;
    if(v.availability)availability=m::CreateProductionAvailability(b,v.availability->available,b.CreateString(v.availability->objection));
    pr.push_back(m::CreateProductionRecipe(b,b.CreateString(v.key),b.CreateString(v.name),reqs(v.requirements),availability));
  }
  std::vector<flatbuffers::Offset<m::ProductionJob>> pj;
  for(const auto& v:production.jobs) pj.push_back(m::CreateProductionJob(b,v.id,b.CreateString(v.name),v.jobType,v.repeat,v.suspended,v.workerId,b.CreateString(v.workerName),v.completionTimer,v.attachedItems,v.editable,b.CreateString(v.status),reqs(v.requirements)));
  std::vector<flatbuffers::Offset<m::FarmCrop>> pc;
  for(const auto& v:production.crops) pc.push_back(m::CreateFarmCrop(b,v.id,b.CreateString(v.name),v.seasons,v.seeds));
  flatbuffers::Offset<m::FarmSnapshot> farmSnapshot;
  if(production.farm) {
    const auto& f=*production.farm;std::vector<flatbuffers::Offset<m::NativeFarmCrop>> rows;
    for(const auto& c:f.choices)rows.push_back(m::CreateNativeFarmCrop(b,c.id,b.CreateString(c.name),c.seedsAvailable,c.currentSeasonWarning,b.CreateString(c.rawId)));
    farmSnapshot=m::CreateFarmSnapshot(b,f.buildingId,f.revision,f.selectedSeason,f.currentSeason,b.CreateVector(f.seasonalCrops),b.CreateVector(rows),f.currentFertilization,f.maxFertilization,f.pendingFertilization,f.seasonalFertilization,b.CreateString(f.customName),b.CreateString(f.headerName),f.removing,f.removalSuspended,f.removalHasWorker);
  }
  const auto encodeContainerContents=[&](const auto& facts) {
    flatbuffers::Offset<m::ItemContainerContentsFacts> result;
    if(facts){std::vector<flatbuffers::Offset<m::ItemContainerContentFacts>> entries;
      for(const auto& e:facts->entries)entries.push_back(m::CreateItemContainerContentFacts(b,e.itemType,b.CreateString(e.materialToken),b.CreateString(e.colorToken),e.effectiveArmorLevel,e.metal,e.coal,e.containsPowder,e.rollsSheets,e.protectsFoldedSheets,e.containsWriting,e.liquid,e.subterraneanPlant));
      result=m::CreateItemContainerContentsFacts(b,facts->container,b.CreateVector(entries),facts->materialInorganic,b.CreateString(facts->solidColor));}
    return result;
  };
  const auto encodeItemRecipe=[&](const std::optional<df3d_production::ItemAppearanceRecipe>& recipe) {
    if(!recipe)return flatbuffers::Offset<m::SelectionAppearance>{};
    std::vector<m::AppearanceLayer> layers;
    for(const auto& l:recipe->layers)layers.emplace_back(uint16_t(l[0]),uint16_t(l[1]),uint16_t(l[2]),uint8_t(l[3]),uint8_t(l[4]),uint16_t(l[5]),int16_t(l[6]),int16_t(l[7]),int8_t(l[8]),int8_t(l[9]));
    return buildSelectionAppearance(b,recipe->pages,recipe->palettes,layers);
  };
  const auto encodeInspectionAppearance=[&](const std::optional<ItemInspectionAppearance>& look) {
    flatbuffers::Offset<m::ItemInspectionAppearance> result;
    if(look){const auto& a=*look;result=m::CreateItemInspectionAppearance(b,b.CreateString(a.materialToken),b.CreateString(a.subtypeRaw),b.CreateString(a.colorToken),a.stack,a.flags,a.instrumentFamily,a.instrumentPlaced,encodeContainerContents(a.contents),a.floodgateOpen,a.doorOpen,a.doorForbidden,a.doorWear,a.bucketLiquid,b.CreateString(a.bucketLiquidColor),a.cageMaterialFamily,a.cageOccupantEntity,a.cageOccupantId,b.CreateString(a.cageSolidColor),a.restraintRope,b.CreateString(a.restraintSolidColor),encodeItemRecipe(a.portrait),encodeItemRecipe(a.cageOccupant),a.slabEngraving,encodeItemRecipe(a.corpseSelector),encodeItemRecipe(a.legwearSelector),a.craftGemColor?b.CreateString(*a.craftGemColor):0,a.craftSoftMaterial,a.artifactMood,a.coffinUnused);}return result;
  };
  flatbuffers::Offset<m::BuildingContentsPage> contentsPage;
  if(production.contents) {
    const auto& page=*production.contents;std::vector<flatbuffers::Offset<m::BuildingContentsItem>> rows;
    for(const auto& row:page.rows)rows.push_back(m::CreateBuildingContentsItem(b,row.id,row.role,b.CreateString(row.name),
      row.forbid,row.dump,row.melt,row.hidden,row.canDump,row.canMelt,row.inJob,row.inBuilding,row.itemType,b.CreateString(row.materialToken),b.CreateString(row.subtypeRaw),encodeInspectionAppearance(row.appearance)));
    contentsPage=m::CreateBuildingContentsPage(b,page.buildingId,page.revision,page.cursor,page.nextCursor,page.total,
      page.completed,page.removing,b.CreateVector(rows));
  }
  flatbuffers::Offset<m::BuildingItemReceipt> contentsEdit;
  if(production.contentsEdit) {
    const auto& edit=*production.contentsEdit;contentsEdit=m::CreateBuildingItemReceipt(b,edit.itemId,edit.operation,edit.value);
  }
  flatbuffers::Offset<m::IndependentItemState> independentItem;
  if(production.independentItem) {
    const auto& state=*production.independentItem;
    flatbuffers::Offset<m::IndependentItemSnapshot> snapshot;
    flatbuffers::Offset<m::BuildingItemReceipt> edit;
    if(state.snapshot) {
      const auto& v=*state.snapshot;
      const auto link=[&](const std::optional<ItemBuildingHolder>& value)->flatbuffers::Offset<m::ItemBuildingHolder> {
        if(!value)return {};return m::CreateItemBuildingHolder(b,value->id,value->type,b.CreateString(value->name));
      };
      const auto holder=link(v.holder),stockpile=link(v.stockpile);
      flatbuffers::Offset<m::ItemCarrier> carrier;
      if(v.carrier){const auto& c=*v.carrier;flatbuffers::Offset<m::ItemInspectionAppearance> appearance;
        if(c.appearance){const auto& a=*c.appearance;appearance=m::CreateItemInspectionAppearance(b,b.CreateString(a.materialToken),b.CreateString(a.subtypeRaw),b.CreateString(a.colorToken),a.stack,a.flags,a.instrumentFamily,a.instrumentPlaced,encodeContainerContents(a.contents),a.floodgateOpen,a.doorOpen,a.doorForbidden,a.doorWear,a.bucketLiquid,b.CreateString(a.bucketLiquidColor),a.cageMaterialFamily,a.cageOccupantEntity,a.cageOccupantId,b.CreateString(a.cageSolidColor),a.restraintRope,b.CreateString(a.restraintSolidColor),encodeItemRecipe(a.portrait),encodeItemRecipe(a.cageOccupant),a.slabEngraving,encodeItemRecipe(a.corpseSelector),encodeItemRecipe(a.legwearSelector),a.craftGemColor?b.CreateString(*a.craftGemColor):0,a.craftSoftMaterial,a.artifactMood,a.coffinUnused);}
        carrier=m::CreateItemCarrier(b,int8_t(c.kind),c.id,c.itemType,b.CreateString(c.name),appearance);}
      flatbuffers::Offset<m::ItemInspectionAppearance> appearance;
      if(v.appearance){const auto& a=*v.appearance;appearance=m::CreateItemInspectionAppearance(b,b.CreateString(a.materialToken),b.CreateString(a.subtypeRaw),b.CreateString(a.colorToken),a.stack,a.flags,a.instrumentFamily,a.instrumentPlaced,encodeContainerContents(a.contents),a.floodgateOpen,a.doorOpen,a.doorForbidden,a.doorWear,a.bucketLiquid,b.CreateString(a.bucketLiquidColor),a.cageMaterialFamily,a.cageOccupantEntity,a.cageOccupantId,b.CreateString(a.cageSolidColor),a.restraintRope,b.CreateString(a.restraintSolidColor),encodeItemRecipe(a.portrait),encodeItemRecipe(a.cageOccupant),a.slabEngraving,encodeItemRecipe(a.corpseSelector),encodeItemRecipe(a.legwearSelector),a.craftGemColor?b.CreateString(*a.craftGemColor):0,a.craftSoftMaterial,a.artifactMood,a.coffinUnused);}
      flatbuffers::Offset<m::ItemOwner> owner;
      if(v.owner)owner=m::CreateItemOwner(b,v.owner->id,b.CreateString(v.owner->name));
      flatbuffers::Offset<m::ItemAmmunitionAssignment> assignment;
      if(v.ammunitionAssignment){const auto& a=*v.ammunitionAssignment;assignment=m::CreateItemAmmunitionAssignment(b,a.kind,a.squadId,b.CreateString(a.caption));}
      flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<m::ItemSheetContent>>> contents;
      if(v.contents){std::vector<flatbuffers::Offset<m::ItemSheetContent>> rows;
        for(const auto& row:*v.contents){flatbuffers::Offset<m::ItemInspectionAppearance> look;
          if(row.appearance){const auto& a=*row.appearance;look=m::CreateItemInspectionAppearance(b,b.CreateString(a.materialToken),b.CreateString(a.subtypeRaw),b.CreateString(a.colorToken),a.stack,a.flags,a.instrumentFamily,a.instrumentPlaced,encodeContainerContents(a.contents),a.floodgateOpen,a.doorOpen,a.doorForbidden,a.doorWear,a.bucketLiquid,b.CreateString(a.bucketLiquidColor),a.cageMaterialFamily,a.cageOccupantEntity,a.cageOccupantId,b.CreateString(a.cageSolidColor),a.restraintRope,b.CreateString(a.restraintSolidColor),encodeItemRecipe(a.portrait),encodeItemRecipe(a.cageOccupant),a.slabEngraving,encodeItemRecipe(a.corpseSelector),encodeItemRecipe(a.legwearSelector),a.craftGemColor?b.CreateString(*a.craftGemColor):0,a.craftSoftMaterial,a.artifactMood,a.coffinUnused);}
          rows.push_back(m::CreateItemSheetContent(b,int8_t(row.kind),row.id,b.CreateString(row.caption),row.itemType,row.flags,row.canDump,row.canMelt,look));
        }contents=b.CreateVector(rows);
      }
      flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<m::ItemUseRow>>> uses;
      if(v.uses){std::vector<flatbuffers::Offset<m::ItemUseRow>> rows;for(const auto& row:*v.uses)rows.push_back(m::CreateItemUseRow(b,b.CreateString(row.caption),row.reaction));uses=b.CreateVector(rows);}
      snapshot=m::CreateIndependentItemSnapshot(b,v.id,v.revision,v.itemType,b.CreateString(v.name),b.CreateString(v.materialToken),b.CreateString(v.subtypeRaw),
        v.forbid,v.dump,v.melt,v.hidden,v.canDump,v.canMelt,v.inJob,v.inBuilding,b.CreateString(v.weight),b.CreateString(v.description),holder,stockpile,v.stockpileCategories,carrier,appearance,owner,assignment,contents,uses);
    }
    if(state.edit)edit=m::CreateBuildingItemReceipt(b,state.edit->itemId,state.edit->operation,state.edit->value);
    independentItem=m::CreateIndependentItemState(b,snapshot,edit,state.outcome);
  }
  flatbuffers::Offset<m::BuildingItemSnapshot> itemSnapshot;
  if(production.item) {
    const auto& value=*production.item;const auto& row=value.item;
    auto item=m::CreateBuildingContentsItem(b,row.id,row.role,b.CreateString(row.name),
      row.forbid,row.dump,row.melt,row.hidden,row.canDump,row.canMelt,row.inJob,row.inBuilding,row.itemType,b.CreateString(row.materialToken),b.CreateString(row.subtypeRaw),encodeInspectionAppearance(row.appearance));
    flatbuffers::Offset<m::ItemBuildingHolder> holder;
    if(value.holder)holder=m::CreateItemBuildingHolder(b,value.holder->id,value.holder->type,b.CreateString(value.holder->name));
    itemSnapshot=m::CreateBuildingItemSnapshot(b,value.buildingId,value.revision,value.completed,value.removing,item,
      b.CreateString(value.weight),b.CreateString(value.description),holder);
  }
  flatbuffers::Offset<m::ItemPosition> itemPosition;
  if(production.itemPosition) {
    const auto& value=*production.itemPosition;const m::TilePos pos(value.x,value.y,value.z);
    itemPosition=m::CreateItemPosition(b,value.id,&pos);
  }
  flatbuffers::Offset<m::BuildingHeaderState> buildingHeader;
  if(production.buildingHeader) {
    const auto& state=*production.buildingHeader;flatbuffers::Offset<m::BuildingHeaderSnapshot> snapshot;
    if(state.snapshot) {
      const auto& f=*state.snapshot;snapshot=m::CreateBuildingHeaderSnapshot(b,f.id,f.type,f.revision,f.stage,f.maxStage,
        b.CreateString(f.customName),b.CreateString(f.nativeName),b.CreateString(f.headerName),f.removing,f.suspended,f.hasWorker);
    }
    buildingHeader=m::CreateBuildingHeaderState(b,snapshot,state.outcome,state.operation);
  }
  flatbuffers::Offset<m::WorkshopOrdersState> workshopOrders;
  if(production.workshopOrders) {
    const auto& p=*production.workshopOrders;
    workshopOrders=m::CreateWorkshopOrdersState(b,p.buildingId,p.revision,p.managerAvailable,p.generalOrderLimit,b.CreateVector(p.orderIds),p.outcome,p.delta,p.value);
  }
  flatbuffers::Offset<m::WorkshopWorkersState> workshopWorkers;
  if(production.workshopWorkers) {
    const auto& p=*production.workshopWorkers;
    std::vector<flatbuffers::Offset<m::LocationStaffCandidate>> rows;
    for(const auto& r:p.rows) {
      std::vector<flatbuffers::Offset<m::LocationStaffSkill>> skills;
      for(const auto& s:r.skills)skills.push_back(m::CreateLocationStaffSkill(b,s.id,s.rating,s.experience,s.weight));
      std::vector<flatbuffers::Offset<m::LocationStaffAssignment>> assignments;
      for(const auto& e:r.assignments)assignments.push_back(m::CreateLocationStaffAssignment(b,
          static_cast<m::LocationStaffAssignmentKind>(e.kind),e.id,e.type,e.subtype,e.custom,b.CreateString(e.name),b.CreateString(e.customCode)));
      rows.push_back(m::CreateLocationStaffCandidate(b,r.unitId,r.histfigId,b.CreateString(r.name),r.score,b.CreateVector(skills),
          b.CreateString(r.baseName),b.CreateString(r.professionName),r.professionColor,r.legendary,
          r.sourceIndex,r.professionOrder,r.statusOrder,b.CreateVector(r.nameSortKey),b.CreateVector(r.professionSortKey),b.CreateVector(assignments)));
    }
    flatbuffers::Offset<m::WorkshopAssignedWorker> assigned;
    if(p.assigned){const auto& a=*p.assigned;assigned=m::CreateWorkshopAssignedWorker(b,a.id,b.CreateString(a.caption),a.specializationVisible,a.canSpecialize,a.specialized);}
    workshopWorkers=m::CreateWorkshopWorkersState(b,p.buildingId,p.profileRevision,b.CreateVector(p.permittedWorkers),p.revision,p.cursor,p.nextCursor,p.total,b.CreateVector(rows),p.outcome,p.unitId,assigned,p.operation);
  }
  auto productionResult=m::CreateProductionState(b,b.CreateVector(pb),production.nextCursor,b.CreateVector(pr),b.CreateVector(pj),b.CreateVector(pc),b.CreateVector(production.seasonalCrops),production.currentSeason,production.selectedBuilding,production.createdJob,b.CreateString(production.detail),farmSnapshot,production.farmEditOutcome,contentsPage,contentsEdit,itemSnapshot,itemPosition,independentItem,buildingHeader,workshopWorkers,workshopOrders);
  std::vector<flatbuffers::Offset<m::WorkOrderInfo>> wo;
  for(const auto& o:workOrders.orders){
    std::vector<flatbuffers::Offset<m::WorkOrderCondition>> cs;
    const auto condition=[&](const auto& c){return m::CreateWorkOrderCondition(b,c.kind,c.index,b.CreateString(c.description),c.editable,c.compare,c.threshold,c.itemType,c.targetOrder,c.dependency,c.satisfied,c.itemSubtype,c.matType,c.matIndex,b.CreateVectorOfStrings(c.traits),c.satisfaction,c.estimated,c.estimateCount,c.itemCaption?b.CreateString(*c.itemCaption):0);};
    for(const auto& c:o.conditions)cs.push_back(condition(c));
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<m::WorkOrderCondition>>> suggestions;
    if(o.suggestedConditions){std::vector<flatbuffers::Offset<m::WorkOrderCondition>> values;for(const auto& c:*o.suggestedConditions)values.push_back(condition(c));suggestions=b.CreateVector(values);}
    std::vector<flatbuffers::Offset<m::WorkOrderInput>> wi;
    for(const auto& v:o.inputs)wi.push_back(m::CreateWorkOrderInput(b,v.index,b.CreateString(v.description),v.matType,v.matIndex,v.editable));
    flatbuffers::Offset<m::WorkOrderNativeState> native;
    if(o.nativeState)native=m::CreateWorkOrderNativeState(b,o.nativeState->phase,o.nativeState->validationRequired,o.nativeState->detailsAvailable,o.nativeState->workshopName?b.CreateString(*o.nativeState->workshopName):0);
    wo.push_back(m::CreateWorkOrderInfo(b,o.id,o.revision,b.CreateString(o.name),o.total,o.remaining,o.frequency,o.validated,o.active,o.finishedYear,o.finishedTick,o.workshopId,o.maxWorkshops,b.CreateVector(o.generatedJobs),b.CreateVector(cs),o.editable,b.CreateString(o.reason),o.position,o.detailKind,o.sizeRaw,o.encrustFlags,o.matType,o.matIndex,o.materialCategory,b.CreateVector(wi),native,suggestions));
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
  for(const auto& v:workOrders.groups)wo_groups.push_back(m::CreateWorkOrderGroup(b,v.type,v.subtype,v.custom,b.CreateString(v.name),v.count,v.customCode?b.CreateString(*v.customCode):0));
  std::vector<flatbuffers::Offset<m::WorkOrderTask>> wo_tasks;
  for(const auto& v:workOrders.tasks)wo_tasks.push_back(m::CreateWorkOrderTask(b,b.CreateString(v.key),b.CreateString(v.name),v.jobType,b.CreateString(v.reaction),v.itemType,v.itemSubtype,v.matType,v.matIndex));
  flatbuffers::Offset<m::WorkOrderListNativeState> workOrderNative;
  if(workOrders.nativeState)workOrderNative=m::CreateWorkOrderListNativeState(b,workOrders.nativeState->managerAvailable,workOrders.nativeState->validationRequired);
  flatbuffers::Offset<m::WorkOrderDetailsState> workOrderDetails;
  if(workOrders.details) {
    const auto& d=*workOrders.details;
    std::vector<flatbuffers::Offset<m::WorkOrderDetailsOption>> options;
    for(const auto& o:d.options)options.push_back(m::CreateWorkOrderDetailsOption(b,uint8_t(o.kind),o.index,b.CreateString(DF2UTF(o.caption))));
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<m::WorkOrderDetailsChoice>>> choices;
    uint32_t next=0;
    if(workOrders.detailsOption>=0 && !workOrders.art) {
      std::vector<flatbuffers::Offset<m::WorkOrderDetailsChoice>> rows;
      const auto end=std::min(size_t(workOrders.detailsCursor)+128,d.materials.size());
      for(size_t i=workOrders.detailsCursor;i<end;++i) {
        const auto& row=d.materials[i];
        std::optional<m::WorkOrderDyeColor> swatch;
        if(row.swatch)swatch.emplace((*row.swatch)[0],(*row.swatch)[1],(*row.swatch)[2]);
        rows.push_back(m::CreateWorkOrderDetailsChoice(b,row.id,b.CreateString(DF2UTF(row.caption)),row.countCaption?b.CreateString(DF2UTF(*row.countCaption)):0,row.estimated,row.dyeColor,row.opensMenu,swatch?&*swatch:nullptr));
      }
      choices=b.CreateVector(rows);next=end<d.materials.size()?uint32_t(end):0;
    }
    flatbuffers::Offset<m::WorkOrderArtState> art;
    if(workOrders.art)art=encodeNativeArt(b,*workOrders.art);
    workOrderDetails=m::CreateWorkOrderDetailsState(b,workOrders.detailsId,d.revision,b.CreateString(DF2UTF(d.caption)),b.CreateVector(options),workOrders.detailsOption,choices,d.choicesRevision,uint32_t(d.materials.size()),next,art,d.currentValue?b.CreateString(DF2UTF(*d.currentValue)):0,d.settingHeading?b.CreateString(DF2UTF(*d.settingHeading)):0,d.dyeTarget);
  }
  auto workOrderResult=m::CreateWorkOrderState(b,b.CreateVector(wo),b.CreateVector(wr),b.CreateVector(wc),b.CreateVector(wm),workOrders.nextCursor,b.CreateString(workOrders.detail),b.CreateVector(wo_materials),b.CreateVector(wo_traits),b.CreateVector(wo_types),b.CreateVector(wo_groups),b.CreateVector(wo_tasks),workOrders.total,workOrders.listRevision,workOrders.buildPhase,workOrders.buildDone,workOrders.buildTotal,workOrderNative,workOrderDetails);
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
  auto citizenResult=citizenAction(action) ? m::CreateCitizenState(b,b.CreateVector(citizenRows),b.CreateVector(detailRows),citizens.nextCursor,citizens.selectedUnit,citizens.selectedDetail,citizens.externalController,b.CreateString(citizens.detail),citizens.recalcDone,citizens.recalcTotal,b.CreateString(citizens.recalcError),citizens.detailListRevision,citizens.outcomeUnknown) : flatbuffers::Offset<m::CitizenState>{};
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
  std::vector<flatbuffers::Offset<m::ContinuingAgreementRow>> trackerRows;
  for(const auto& row:agreements.trackerRows)trackerRows.push_back(m::CreateContinuingAgreementRow(b,row.agreementId,row.subjectId,row.entityId,row.entityType,row.tier,row.profession,row.year,row.yearTick,b.CreateString(row.heading),b.CreateString(row.applicant),b.CreateString(row.date)));
  flatbuffers::Offset<m::ContinuingAgreementDetails> trackerDetails;
  if(agreements.trackerDetails) {const auto& d=*agreements.trackerDetails;trackerDetails=m::CreateContinuingAgreementDetails(b,d.requiredValue,d.matchingLocations,d.locationId,d.locationValue,d.locationTier,d.siteAvailable,d.tierMet,b.CreateString(d.locationName));}
  auto agreementResult=m::CreateAgreementState(b,b.CreateVector(agreementRows),agreements.nextBeforeId,agreements.pendingOnly,b.CreateString(agreements.detail),agreements.tracker,b.CreateVector(trackerRows),trackerDetails);
  auto creatureResult=creature_data::build(b,creature);
  flatbuffers::Offset<m::CreaturePosition> creaturePositionResult;
  if(creaturePosition) {
    const auto& [id,p]=*creaturePosition;const m::TilePos tile(p.x,p.y,p.z);
    creaturePositionResult=m::CreateCreaturePosition(b,id,&tile);
  }
  flatbuffers::Offset<m::CreatureHeaderState> creatureHeaderResult;
  if(creatureHeader) {
    flatbuffers::Offset<m::CreatureHeaderSnapshot> receipt;
    if(creatureHeader->receipt) {
      const auto& h=*creatureHeader->receipt;
      receipt=m::CreateCreatureHeaderSnapshot(b,h.unitId,h.histFigureId,h.hasFigure,h.revision,
          b.CreateString(DF2UTF(h.nickname)),b.CreateString(DF2UTF(h.profession)),b.CreateString(DF2UTF(h.figureNickname)));
    }
    creatureHeaderResult=m::CreateCreatureHeaderState(b,m::CreatureHeaderOutcome(creatureHeader->outcome),creatureHeader->mutated,receipt);
  }
  flatbuffers::Offset<m::WorldHover> terrainResult;
  flatbuffers::Offset<m::CreatureExpelState> creatureExpelResult;
  if(creatureExpel) {
    flatbuffers::Offset<m::CreatureExpelPreview> preview;
    if(creatureExpel->preview) {
      const auto& p=*creatureExpel->preview;
      std::vector<flatbuffers::Offset<m::CreatureExpelUnit>> units;
      std::vector<flatbuffers::Offset<m::CreatureExpelDestination>> destinations;
      for(size_t i=0;i<p.units.size();++i) {
        const auto& row=p.units[i];const auto& c=row.color;
        auto color=m::CreateAreaNameColor(b,c.color[0],c.color[1],c.color[2],c.alternate[0],c.alternate[1],c.alternate[2],c.effect);
        units.push_back(m::CreateCreatureExpelUnit(b,row.id,b.CreateString(DF2UTF(row.name)),color,creatureExpel->icons[i].build(b)));
      }
      for(const auto& row:p.destinations)destinations.push_back(m::CreateCreatureExpelDestination(b,row.id,b.CreateString(DF2UTF(row.name))));
      preview=m::CreateCreatureExpelPreview(b,p.unitId,p.eligible,p.reason,b.CreateVector(units),b.CreateVector(destinations));
    }
    creatureExpelResult=m::CreateCreatureExpelState(b,creatureExpel->outcome,preview);
  }
  flatbuffers::Offset<m::CreatureKnowledgeState> creatureKnowledgeResult;
  if(creatureKnowledge) {
    const auto& value=*creatureKnowledge;
    creatureKnowledgeResult=m::CreateCreatureKnowledgeState(b,value.unitId,value.kind,value.id,value.outcome,b.CreateString(value.text));
  }
  flatbuffers::Offset<m::CreatureAnimalState> creatureAnimalResult;
  const auto residentsResult=residents?m::CreateResidentsState(b,b.CreateVector(*residents)):flatbuffers::Offset<m::ResidentsState>{};
  const auto residentsSpecializationResult=residentsSpecialization?
      m::CreateResidentsSpecializationState(b,residentsSpecialization->id,residentsSpecialization->outcome,residentsSpecialization->onlyAssigned):flatbuffers::Offset<m::ResidentsSpecializationState>{};
  flatbuffers::Offset<m::ResidentsRowsState> residentsRowsResult;
  if(residentsRows) {
    std::vector<flatbuffers::Offset<m::ResidentRow>> rows;
    for(const auto& value:*residentsRows) {
      const auto id=value.id;const auto& row=value.text;
      const auto& c=row.nameColor;const auto& n=row.name;const auto& a=row.activity;
      const auto color=m::CreateAreaNameColor(b,c.color[0],c.color[1],c.color[2],c.alternate[0],c.alternate[1],c.alternate[2],c.effect);
      std::vector<flatbuffers::Offset<m::LocationStaffAssignment>> assignments;
      for(const auto& e:value.assignments)assignments.push_back(m::CreateLocationStaffAssignment(b,m::LocationStaffAssignmentKind(e.kind),e.id,e.type,e.subtype,e.custom,b.CreateString(e.name),b.CreateString(e.customCode)));
      flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<m::WorkDetailSkill>>> skills;
      if(value.workDetailSkills){std::vector<flatbuffers::Offset<m::WorkDetailSkill>> items;
        for(const auto& skill:*value.workDetailSkills)items.push_back(m::CreateWorkDetailSkill(b,skill.skill,skill.rating,b.CreateString(skill.caption)));
        skills=b.CreateVector(items);}
      const m::TilePos position(value.position.x,value.position.y,value.position.z);
      rows.push_back(m::CreateResidentRow(b,id,b.CreateString(n.combined),b.CreateString(n.name),b.CreateString(n.profession),
          b.CreateString(n.firstLine),b.CreateString(n.secondLine),color,b.CreateString(a.caption),uint8_t(a.foreground),uint8_t(a.background),a.bright,
          value.icon?value.icon->build(b):flatbuffers::Offset<m::SelectionAppearance>{},int8_t(row.happiness),m::CreateResidentSpecialization(b,value.specialization.onlyAssigned,value.specialization.revision),b.CreateVector(assignments),&position,value.activityTarget?m::CreateResidentActivityTarget(b,value.activityTarget->activityId,value.activityTarget->eventId):flatbuffers::Offset<m::ResidentActivityTarget>{},value.jobTarget?m::CreateResidentJobTarget(b,value.jobTarget->jobId,value.jobTarget->buildingId):flatbuffers::Offset<m::ResidentJobTarget>{},skills,value.detailMember));
    }
    residentsRowsResult=m::CreateResidentsRowsState(b,b.CreateVector(rows));
  }
  flatbuffers::Offset<m::JobSettingsEditState> jobSettingsEditResult;
  if(jobSettingsEdit) {const auto& v=*jobSettingsEdit;jobSettingsEditResult=m::CreateJobSettingsEditState(b,v.jobId,v.buildingId,v.unitId,v.outcome);}
  flatbuffers::Offset<m::JobSettingsState> jobSettingsResult;
  if(jobSettings) {
    const auto& v=jobSettings->value;
    std::vector<flatbuffers::Offset<m::WorkOrderDetailsOption>> options;
    std::vector<flatbuffers::Offset<m::JobSettingsChoice>> choices;
    for(const auto& o:v.options)options.push_back(m::CreateWorkOrderDetailsOption(b,uint8_t(o.kind),o.index,b.CreateString(o.caption)));
    const size_t end=std::min(size_t(jobSettings->cursor)+64,v.materials.size());
    for(size_t i=jobSettings->cursor;i<end;++i){const auto& c=v.materials[i];choices.push_back(m::CreateJobSettingsChoice(b,c.id,b.CreateString(c.caption),c.countCaption?b.CreateString(*c.countCaption):0,c.estimated));}
    flatbuffers::Offset<m::WorkOrderArtState> art;
    if(jobSettings->art)art=encodeNativeArt(b,*jobSettings->art,true);
    jobSettingsResult=m::CreateJobSettingsState(b,v.jobId,v.buildingId,jobSettings->unitId,v.revision,b.CreateString(v.caption),
      b.CreateVector(options),int16_t(v.selected),b.CreateVector(choices),v.choicesRevision,uint32_t(v.materials.size()),jobSettings->cursor,end<v.materials.size()?uint32_t(end):0,v.currentValue?b.CreateString(*v.currentValue):0,0,art);
  }
  flatbuffers::Offset<m::ResidentsActivityState> residentsActivityResult;
  if(residentsActivity) {
    const auto& value=residentsActivity->description;
    std::vector<flatbuffers::Offset<m::ActivityDescriptionWord>> words;
    std::vector<flatbuffers::Offset<m::ActivityDescriptionLink>> links;
    for(const auto& w:value.words)words.push_back(m::CreateActivityDescriptionWord(b,b.CreateString(w.text),w.red,w.green,w.blue,w.link,uint8_t(w.flags),w.x,w.y));
    for(const auto& l:value.links)links.push_back(m::CreateActivityDescriptionLink(b,l.type,l.id,l.subid));
    residentsActivityResult=m::CreateResidentsActivityState(b,residentsActivity->unitId,value.activityId,value.eventId,uint16_t(value.columns),value.maxY,b.CreateVector(words),b.CreateVector(links));
  }
  if(creatureAnimal) {
    const auto& value=*creatureAnimal;
    creatureAnimalResult=m::CreateCreatureAnimalState(b,value.unitId,value.animalId,value.outcome,value.assigned);
  }
  flatbuffers::Offset<m::CreatureLocationState> creatureLocationResult;
  if(creatureLocation) {
    const auto& value=*creatureLocation;
    creatureLocationResult=m::CreateCreatureLocationState(b,value.unitId,value.occupationId,value.outcome);
  }
  flatbuffers::Offset<m::CreatureWorkshopState> creatureWorkshopResult;
  if(creatureWorkshop) {
    const auto& value=*creatureWorkshop;
    creatureWorkshopResult=m::CreateCreatureWorkshopState(b,value.unitId,value.buildingId,value.outcome);
  }
  if(worldHover) {
    std::vector<flatbuffers::Offset<m::WorldHoverEntry>> entries;
    for(const auto& e:*worldHover) entries.push_back(m::CreateWorldHoverEntry(b,b.CreateString(e.text),uint8_t(e.foreground),uint8_t(e.background),e.bright,e.kind,e.id));
    terrainResult=m::CreateWorldHover(b,&worldHoverTile,b.CreateVector(entries));
  }
  flatbuffers::Offset<m::WorkDetailSettingsState> workDetailSettingsResult;
  if(workDetailSettings) {
    const auto& value=*workDetailSettings;std::vector<flatbuffers::Offset<m::WorkDetailSetting>> catalog;
    for(const auto& entry:value.catalog)catalog.push_back(m::CreateWorkDetailSetting(b,entry.id,b.CreateString(entry.caption)));
    workDetailSettingsResult=m::CreateWorkDetailSettingsState(b,value.index,value.revision,value.editable,value.noModify,
        b.CreateVector(value.labors),b.CreateVector(catalog));
  }
  flatbuffers::Offset<m::StandingOrdersState> standingOrdersResult;
  if(standingOrders) {
    std::vector<flatbuffers::Offset<m::StandingOrderSetting>> rows;
    if(standingOrders->settings)for(const auto& row:*standingOrders->settings)
      rows.push_back(m::CreateStandingOrderSetting(b,row.id,row.value,row.available,row.available));
    if(standingOrders->categorySettings)for(size_t i=0;i<standingOrders->categorySettings->count;++i){
      const auto& row=standingOrders->categorySettings->rows[i];
      rows.push_back(m::CreateStandingOrderSetting(b,row.id,row.value,row.visible,row.editable));
    }
    standingOrdersResult=m::CreateStandingOrdersState(b,standingOrders->category,standingOrders->outcome,b.CreateVector(rows));
  }
  const auto encodeNoblesHelp=[&](const std::optional<df3d_nobles::HoverHelp>& source)->flatbuffers::Offset<m::NoblesHelp>{
    if(!source)return {};const auto& h=*source;
    const auto assessments=[&](const auto& group){std::vector<flatbuffers::Offset<m::NoblesAssessmentHelp>> values;
      for(const auto& v:group)values.push_back(m::CreateNoblesAssessmentHelp(b,b.CreateString(v.actual),b.CreateString(v.required),uint8_t(v.color)));
      return b.CreateVector(values);};
    const auto obligations=[&](const auto& group){std::vector<flatbuffers::Offset<m::NoblesObligationHelp>> values;
      for(const auto& v:group)values.push_back(m::CreateNoblesObligationHelp(b,b.CreateString(v.text),uint8_t(v.color)));
      return b.CreateVector(values);};
    flatbuffers::Offset<m::NoblesAccountingHelp> accounting;
    if(h.accounting){const auto& a=*h.accounting;accounting=m::CreateNoblesAccountingHelp(b,uint8_t(a.setting),uint8_t(a.level),b.CreateString(a.title),b.CreateString(a.examples),b.CreateString(a.attained),b.CreateString(a.progress));}
    return m::CreateNoblesHelp(b,b.CreateString(h.description),assessments(h.rooms),assessments(h.furniture),obligations(h.demands),obligations(h.mandates),accounting);
  };
  flatbuffers::Offset<m::NoblesState> noblesResult;
  if(nobles){std::vector<flatbuffers::Offset<m::NoblesRow>> rows;
    for(const auto& row:nobles->rows)rows.push_back(m::CreateNoblesRow(b,row.entityId,row.positionId,row.assignmentId,row.unitId,row.nemesisId,row.value,
      b.CreateString(row.title),b.CreateString(row.squadCaption),b.CreateString(row.holderCaption),row.canAppoint,row.hasRoomAssessment,
      b.CreateVector(row.requiredRooms.data(),4),b.CreateVector(row.actualRooms.data(),4),b.CreateVector(row.requiredFurniture.data(),4),b.CreateVector(row.actualFurniture.data(),4),
      int8_t(row.demandStatus),int8_t(row.mandateStatus),encodeItemRecipe(row.appearance),encodeNoblesHelp(row.help),row.draftSlot));
    std::vector<flatbuffers::Offset<m::NoblesCandidate>> candidates;
    for(const auto& row:nobles->candidates){std::vector<flatbuffers::Offset<m::NoblesCandidateSkill>> skills;
      for(const auto& skill:row.skills)skills.push_back(m::CreateNoblesCandidateSkill(b,skill.id,skill.rating,b.CreateString(skill.caption)));
      candidates.push_back(m::CreateNoblesCandidate(b,row.unitId,row.value,b.CreateString(row.caption),b.CreateString(row.noSkills),b.CreateVector(skills),encodeItemRecipe(row.appearance)));}
    const auto office=[](const std::optional<df3d_nobles::OfficeKey>& key)->std::optional<m::NoblesOffice>{if(!key)return {};return m::NoblesOffice(key->entityId,key->positionId,key->assignmentId,key->draftSlot);};
    std::vector<flatbuffers::Offset<m::NoblesSymbol>> symbols;
    for(const auto& row:nobles->symbols){const auto current=office(row.facts.currentOffice),selected=office(row.facts.selectedOffice);
      symbols.push_back(m::CreateNoblesSymbol(b,row.facts.itemId,row.type,row.facts.value,current?&*current:nullptr,selected?&*selected:nullptr,
        b.CreateString(row.text.caption),b.CreateString(row.text.officeCaption),b.CreateString(row.text.valueCaption),encodeInspectionAppearance(row.appearance),row.artifactMood));}
    flatbuffers::Offset<m::NoblesSymbolStep> step;
    if(nobles->step){const auto& s=*nobles->step;step=m::CreateNoblesSymbolStep(b,s.token,s.artifact,s.remaining);}
    flatbuffers::Offset<m::NoblesSymbolName> name;
    if(nobles->name){const auto& p=*nobles->name;const auto& s=p.snapshot;const auto& n=s.value;
      const auto value=m::CreateLocationNameValue(b,b.CreateVector(reinterpret_cast<const uint8_t*>(n.firstNameCp437.data()),n.firstNameCp437.size()),
        b.CreateVector(reinterpret_cast<const uint8_t*>(n.nicknameCp437.data()),n.nicknameCp437.size()),b.CreateVector(n.words.data(),n.words.size()),
        b.CreateVector(n.parts.data(),n.parts.size()),n.language,n.type,n.hasName);
      std::vector<flatbuffers::Offset<m::LocationNameChoice>> choices;
      for(const auto& c:p.choices)choices.push_back(m::CreateLocationNameChoice(b,c.word,int16_t(c.partOfSpeech),b.CreateString(c.english),b.CreateString(c.translated)));
      name=m::CreateNoblesSymbolName(b,s.artifactId,s.itemId,s.revision,value,b.CreateString(s.nativeHeader),b.CreateString(s.englishHeader),
        p.component,b.CreateVector(reinterpret_cast<const uint8_t*>(p.query.data()),p.query.size()),p.cursor,p.total,p.next,b.CreateVector(choices));
    }
    noblesResult=m::CreateNoblesState(b,nobles->outcome,nobles->listRevision,nobles->total,nobles->offset,b.CreateVector(rows),
      nobles->target?&*nobles->target:nullptr,nobles->candidateRevision,b.CreateVector(candidates),b.CreateVector(symbols),step,name,
      nobles->symbolTargetCaption?b.CreateString(*nobles->symbolTargetCaption):flatbuffers::Offset<flatbuffers::String>{});
  }
  auto justiceResult=justice?df3d_justice::encode(b,*justice):flatbuffers::Offset<m::JusticeState>{};
  flatbuffers::Offset<m::ObjectsState> objectsResult;
  if(objects){std::vector<flatbuffers::Offset<m::ObjectsRow>> rows;
    for(const auto& row:objects->rows){const auto& p=row.destination.position;const m::TilePos pos(p.x,p.y,p.z);
      rows.push_back(m::CreateObjectsRow(b,row.names.artifactId,row.names.itemId,b.CreateString(row.names.nativeName),
        b.CreateString(row.names.translatedName),b.CreateString(row.ownership),row.destination.available?&pos:nullptr,encodeInspectionAppearance(row.appearance),row.itemType));}
    flatbuffers::Offset<m::ObjectsDestination> destination;
    if(objects->destination){const auto& d=*objects->destination;const m::TilePos pos(d.position.x,d.position.y,d.position.z);
      destination=m::CreateObjectsDestination(b,objects->artifactId,d.itemId,d.available?&pos:nullptr);}
    objectsResult=m::CreateObjectsState(b,objects->outcome,objects->tab,objects->listRevision,objects->total,objects->offset,b.CreateVector(rows),destination);
  }
  flatbuffers::Offset<m::PlacesState> placesResult;
  if(places){std::vector<flatbuffers::Offset<m::PlacesRow>> rows;
    for(const auto& row:places->rows){const m::TilePos pos(row.position.x,row.position.y,row.position.z);
      rows.push_back(m::CreatePlacesRow(b,row.id,row.position.x>=0 && row.position.y>=0 && row.position.z>=0?&pos:nullptr,
        b.CreateString(row.name),b.CreateString(row.subtitle),b.CreateString(row.jobCaption),b.CreateString(row.statusCaption),
        b.CreateString(row.secondaryStatus),b.CreateString(row.statusOverlay),b.CreateString(row.operatorCaption),
        row.additionalJobs,int8_t(row.siegeAction),encodeItemRecipe(row.appearance),row.subtitleLocationId));}
    placesResult=m::CreatePlacesState(b,places->outcome,places->tab,places->listRevision,places->total,places->offset,b.CreateVector(rows),places->buildingId,places->siegeAction);
  }
  flatbuffers::Offset<m::TasksState> tasksResult;
  if(tasks){
    std::vector<flatbuffers::Offset<m::TasksRow>> rows;
    for(const auto& row:tasks->rows){
      flatbuffers::Offset<m::AreaNameColor> color;
      if(row.workerColor){const auto& c=*row.workerColor;color=m::CreateAreaNameColor(b,c.color[0],c.color[1],c.color[2],c.alternate[0],c.alternate[1],c.alternate[2],c.effect);}
      const auto validPos=[](const df::coord& p){return p.x>=0 && p.y>=0 && p.z>=0;};
      const m::TilePos worker(row.workerPosition.x,row.workerPosition.y,row.workerPosition.z);
      const m::TilePos buildingPos(row.buildingPosition.x,row.buildingPosition.y,row.buildingPosition.z);
      rows.push_back(m::CreateTasksRow(b,row.jobId,row.unitId,row.buildingId,tasksRowRevision(row),
        b.CreateString(row.caption),b.CreateString(row.workerName),b.CreateString(row.buildingCaption),
        validPos(row.workerPosition)?&worker:nullptr,validPos(row.buildingPosition)?&buildingPos:nullptr,color,
        row.canViewJob,row.canRepeat,row.canRemoveWorker,row.canSuspend,row.canCancel,row.repeating,row.suspended,
        encodeItemRecipe(row.workerAppearance),encodeItemRecipe(row.buildingAppearance)));
    }
    tasksResult=m::CreateTasksState(b,tasks->outcome,tasks->listRevision,tasks->total,tasks->offset,b.CreateVector(rows),tasks->jobId);
  }
  flatbuffers::Offset<m::StocksMenuState> stocksResult;
  if(stocks){
    std::vector<flatbuffers::Offset<m::StocksCategoryRow>> categories;
    std::vector<flatbuffers::Offset<m::StocksGroupRow>> groups;
    std::vector<flatbuffers::Offset<m::StocksItemRow>> items;
    for(const auto& row:stocks->categories)categories.push_back(m::CreateStocksCategoryRow(b,row.type,
      b.CreateString(row.caption),b.CreateString(row.stored),b.CreateString(row.unavailable),
      std::find(stocks->matches.begin(),stocks->matches.end(),row.type)!=stocks->matches.end()));
    for(const auto& row:stocks->selection.groups){const auto& g=row.group;
      auto key=m::CreateStocksGroupKey(b,g.type,g.subtype,g.subcat1,g.subcat2);
      groups.push_back(m::CreateStocksGroupRow(b,key,g.amount,b.CreateString(row.caption),row.matches,g.expanded,
        uint8_t(row.flags),row.revision,b.CreateVector(row.ids)));}
    for(const auto& row:stocks->items){
      flatbuffers::Offset<m::ItemInspectionAppearance> appearance;
      if(row.appearance){const auto& a=*row.appearance;
        appearance=m::CreateItemInspectionAppearance(b,b.CreateString(a.materialToken),b.CreateString(a.subtypeRaw),b.CreateString(a.colorToken),a.stack,a.flags,a.instrumentFamily,a.instrumentPlaced,encodeContainerContents(a.contents),a.floodgateOpen,a.doorOpen,a.doorForbidden,a.doorWear,a.bucketLiquid,b.CreateString(a.bucketLiquidColor),a.cageMaterialFamily,a.cageOccupantEntity,a.cageOccupantId,b.CreateString(a.cageSolidColor),a.restraintRope,b.CreateString(a.restraintSolidColor),encodeItemRecipe(a.portrait),encodeItemRecipe(a.cageOccupant),a.slabEngraving,encodeItemRecipe(a.corpseSelector),encodeItemRecipe(a.legwearSelector),a.craftGemColor?b.CreateString(*a.craftGemColor):0,a.craftSoftMaterial,a.artifactMood,a.coffinUnused);}
      items.push_back(m::CreateStocksItemRow(b,row.id,int16_t(row.itemType),b.CreateString(row.caption),row.flags,row.canDump,row.canMelt,
        b.CreateString(row.materialToken),b.CreateString(row.subtypeRaw),appearance));
    }
    stocksResult=m::CreateStocksMenuState(b,stocks->outcome,stocks->category,b.CreateVector(categories),b.CreateVector(groups),b.CreateVector(items));
  }
  flatbuffers::Offset<m::StoneUseState> stoneUseResult;
  if(stoneUse){
    std::vector<flatbuffers::Offset<m::StoneUseRow>> rows;
    for(const auto& row:stoneUse->rows)rows.push_back(m::CreateStoneUseRow(b,row.category,row.index,row.restricted,b.CreateString(row.name),b.CreateString(row.uses),row.magmaSafe,b.CreateString(row.materialToken)));
    stoneUseResult=m::CreateStoneUseState(b,stoneUse->outcome,b.CreateVector(rows),b.CreateVector(stoneUse->restrictions));
  }
  flatbuffers::Offset<m::KitchenMenuState> kitchenResult;
  if(kitchen){
    std::vector<flatbuffers::Offset<m::KitchenMenuRow>> rows;
    std::vector<flatbuffers::Offset<m::KitchenExclusion>> exclusions;
    for(size_t i=0;i<kitchen->rows.size();++i){const auto& row=kitchen->rows[i];const auto& d=kitchen->display.at(i);
      const auto key=m::CreateKitchenFoodKey(b,row.type,row.subtype,row.material,row.materialIndex);
      const auto receipt=m::CreateKitchenFoodReceipt(b,key,row.count,row.capabilities);
      rows.push_back(m::CreateKitchenMenuRow(b,receipt,b.CreateString(row.name),b.CreateString(d.countCaption),d.estimated,d.excluded,b.CreateString(d.materialToken)));}
    for(const auto& row:kitchen->exclusions){const auto key=m::CreateKitchenFoodKey(b,row.type,row.subtype,row.material,row.materialIndex);
      exclusions.push_back(m::CreateKitchenExclusion(b,key,row.flags));}
    kitchenResult=m::CreateKitchenMenuState(b,kitchen->outcome,b.CreateVector(rows),b.CreateVector(exclusions));
  }
  flatbuffers::Offset<m::ChoresState> choresResult;
  if(chores){
    flatbuffers::Offset<m::ChoresSnapshot> snapshot;
    if(chores->snapshot){const auto& v=*chores->snapshot;std::vector<flatbuffers::Offset<m::ChoreLabor>> labors;
      for(const auto& [id,enabled]:v.labors)labors.push_back(m::CreateChoreLabor(b,id,enabled));
      snapshot=m::CreateChoresSnapshot(b,v.enabled,b.CreateVector(v.children),b.CreateVector(v.exempted),b.CreateVector(labors));}
    std::vector<flatbuffers::Offset<m::ChoresCaption>> children,labors;
    for(const auto& row:chores->captions.children)children.push_back(m::CreateChoresCaption(b,row.id,b.CreateString(row.text)));
    for(const auto& row:chores->captions.labors)labors.push_back(m::CreateChoresCaption(b,row.id,b.CreateString(row.text)));
    choresResult=m::CreateChoresState(b,chores->outcome,snapshot,b.CreateVector(children),b.CreateVector(labors));
  }
  flatbuffers::Offset<m::HunterAmmunitionState> hunterResult;
  if(hunter){
    std::vector<flatbuffers::Offset<m::HunterAmmunitionSpec>> specs;
    std::vector<flatbuffers::Offset<m::HunterAmmunitionRule>> rules;
    std::vector<flatbuffers::Offset<m::HunterAmmunitionType>> types;
    std::vector<flatbuffers::Offset<m::HunterAmmunitionMaterial>> materials;
    for(const auto& row:hunter->specs)specs.push_back(m::CreateHunterAmmunitionSpec(b,int16_t(row.item_type),int16_t(row.item_subtype),int16_t(row.material_class),int16_t(row.mattype),row.matindex,row.amount,row.flags,b.CreateVector(row.assigned)));
    for(const auto& row:hunter->rules){std::vector<flatbuffers::Offset<m::HunterAmmunitionStack>> items;
      for(const auto& item:row.items){const auto& a=item.appearance;
        auto appearance=m::CreateItemInspectionAppearance(b,b.CreateString(a.materialToken),b.CreateString(a.subtypeRaw),b.CreateString(a.colorToken),a.stack,a.flags);
        items.push_back(m::CreateHunterAmmunitionStack(b,item.id,b.CreateString(item.caption),item.quantity,appearance));}
      rules.push_back(m::CreateHunterAmmunitionRule(b,b.CreateString(row.caption),row.quantity,b.CreateVector(items)));}
    for(const auto& [row,caption]:hunter->types)types.push_back(m::CreateHunterAmmunitionType(b,row.type,row.subtype,row.foreign,b.CreateString(caption)));
    for(const auto& [row,caption]:hunter->materials)materials.push_back(m::CreateHunterAmmunitionMaterial(b,row.category,row.type,row.index,b.CreateString(caption)));
    hunterResult=m::CreateHunterAmmunitionState(b,hunter->outcome,hunter->type,hunter->subtype,b.CreateVector(specs),b.CreateVector(rules),b.CreateVector(types),b.CreateVector(materials));
  }
  auto s = m::CreateManagementState(b, m::kManagementVersion, ++revision, epoch, client, seq,
                                    action, status, b.CreateString(message), b.CreateVector(ds),
                                    b.CreateVector(is), required, cursor, valid, building, stage,
                                    maxStage, removing, jobs, terrainConstructed, areaResult, productionResult, workOrderResult, citizenResult, reportResult, agreementResult, tradeResult, 0, 0, 0, 0, 0, creatureResult, constructionResult, terrainResult,creatureHeaderResult,creaturePositionResult,creatureExpelResult,creatureKnowledgeResult,creatureWorkshopResult,creatureLocationResult,creatureAnimalResult,residentsResult,residentsRowsResult,residentsSpecializationResult,residentsActivityResult,jobSettingsResult,jobSettingsEditResult,workDetailSettingsResult,standingOrdersResult,hunterResult,choresResult,kitchenResult,stoneUseResult,stocksResult,0,tasksResult,placesResult,noblesResult,objectsResult,justiceResult);
  b.Finish(s);
  auto validationError=m::validateManagementState(
      *flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()));
  if(stocks && !validationError && b.GetSize()>m::kManagementCapacity) {
    if(b.GetSize()<=df3d::stocks_pages::retainedBytes &&
       stocksReplies.capture({epoch,client,seq},{b.GetBufferPointer(),b.GetBufferPointer()+b.GetSize()}) && publishStocksPage({epoch,client,seq},0))return;
    validationError="stocks response exceeds retained reply budget";
  }
  if (auto e = validationError) {
    if (publishingFallback) {
      // The minimal fallback failed validation too: nothing sane to publish.
      Core::getInstance().getConsole().printerr("df3d: management fallback response invalid: {}\n", *e);
      return;
    }
    publishingFallback = true;
    const auto placed=construction.placed,skipped=construction.skipped;
    const auto first=construction.first_building;
    const auto standingCategory=standingOrders?standingOrders->category:0;
    const auto tasksTarget=tasks?tasks->jobId:-1;
    const auto justiceTab=justice?justice->tab:0;
    const bool justiceUnknown=justice && (justice->outcome==m::JusticeOutcome::Applied || justice->outcome==m::JusticeOutcome::Unknown);
    const bool tasksUnknown=tasks && (tasks->outcome==m::TasksOutcome::Applied || tasks->outcome==m::TasksOutcome::Unknown);
    const bool stocksUnknown=stocks && (stocks->outcome==m::StocksMenuOutcome::Applied || stocks->outcome==m::StocksMenuOutcome::Unknown);
    const bool stoneUseUnknown=stoneUse && (stoneUse->outcome==m::StoneUseOutcome::Applied || stoneUse->outcome==m::StoneUseOutcome::Unknown);
    const bool kitchenUnknown=kitchen && (kitchen->outcome==m::KitchenMenuOutcome::Applied || kitchen->outcome==m::KitchenMenuOutcome::Unknown);
    const bool choresUnknown=chores && (chores->outcome==m::ChoresOutcome::Applied || chores->outcome==m::ChoresOutcome::Unknown);
    const bool hunterUnknown=hunter && (hunter->outcome==m::HunterAmmunitionOutcome::Applied || hunter->outcome==m::HunterAmmunitionOutcome::Unknown);
    const bool standingUnknown=standingOrders && (standingOrders->outcome==m::StandingOrdersOutcome::Applied || standingOrders->outcome==m::StandingOrdersOutcome::Unknown);
    const bool citizenUnknown=citizenWriteStarted || citizens.outcomeUnknown;
    auto jobWrite=jobSettingsEdit;
    if(jobWrite && jobWrite->outcome!=m::JobSettingsEditOutcome::Applied && jobWrite->outcome!=m::JobSettingsEditOutcome::Unknown)jobWrite.reset();
    clearResult();
    if(justiceUnknown){justice.emplace();justice->tab=justiceTab;justice->outcome=m::JusticeOutcome::Unknown;mutated=true;}
    if(tasksUnknown){tasks.emplace();tasks->jobId=tasksTarget;tasks->outcome=m::TasksOutcome::Unknown;mutated=true;}
    if(stocksUnknown){stocks.emplace();stocks->outcome=m::StocksMenuOutcome::Unknown;mutated=true;}
    if(stoneUseUnknown){stoneUse.emplace();stoneUse->outcome=m::StoneUseOutcome::Unknown;mutated=true;}
    if(kitchenUnknown){kitchen.emplace();kitchen->outcome=m::KitchenMenuOutcome::Unknown;mutated=true;}
    if(choresUnknown){chores.emplace();chores->outcome=m::ChoresOutcome::Unknown;mutated=true;}
    if(hunterUnknown){hunter.emplace();hunter->outcome=m::HunterAmmunitionOutcome::Unknown;mutated=true;}
    if(standingUnknown){standingOrders.emplace();standingOrders->category=standingCategory;standingOrders->outcome=m::StandingOrdersOutcome::Unknown;mutated=true;}
    if(citizenUnknown){citizens.outcomeUnknown=true;mutated=true;}
    if(jobWrite){jobWrite->outcome=m::JobSettingsEditOutcome::Unknown;jobSettingsEdit=jobWrite;}
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
// Owned native rows supply vector membership; Lua builds explicit masks for
// those rows. No local raw classifier or cached menu result is consulted.
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
// Bound both current raws and stored vectors before copying owned native settings.
// A changed raw inventory can leave larger old vectors in a loaded stockpile.
bool areaPresetInventoryFits(df::building_stockpilest* pile) {
  std::array<size_t,78> raw{},stored{};size_t index=0;
  for(const auto& entry:areaSettingRawCounts())raw[index++]=entry.second;
  index=0;
  for(const auto& entry:areaSettingVectors(pile))stored[index++]=entry.second->size();
  return df3d_area::settingsRawTotal(raw).valid && df3d_area::settingsRawTotal(stored).valid;
}
std::optional<std::vector<df3d_area::NativeStockpileRow>> ownedStockpileRows(
    df::building_stockpilest* pile,int32_t mode,const std::string& filter,size_t* coldCacheInsertions=nullptr) {
  if(!pile || !areaPresetInventoryFits(pile))return std::nullopt;
  std::unique_ptr<df::building_stockpilest> scratch(df::allocate<df::building_stockpilest>());
  if(!scratch)return std::nullopt;
  scratch->settings=pile->settings;
  std::vector<df3d_area::NativeStockpileSettingRange> ranges;
  for(const auto& entry:areaSettingVectors(scratch.get()))
    ranges.push_back({entry.first,entry.second->data(),entry.second->size()});
  for(const auto& entry:areaFixedSettings(scratch.get()))
    ranges.push_back({entry.key,entry.values,entry.count});
  return df3d_area::nativeStockpileRows(scratch->settings,mode,filter,ranges,coldCacheInsertions);
}
int areaSettingsSummary(lua_State* L) {
  bool attempted=false;
  const auto fail=[&]() {
    lua_newtable(L);field(L,"ok",false);field(L,"message","");field(L,"steps",0);
    field(L,"work_unknown",attempted);return 1;
  };
  auto* pile=Lua::GetDFObject<df::building_stockpilest>(L,1);
  if(!pile || !lua_isinteger(L,2) || !lua_isnil(L,3) || !areaPresetInventoryFits(pile))return fail();
  const auto selected=lua_tointeger(L,2);if(selected<0 || selected>0x1ffff)return fail();
  try {
    attempted=true;
    const auto result=df3d_area::nativeStockpileSummaries(pile->settings,
        (pile->settings.flags.whole&0x1ffff)|uint32_t(selected));
    if(!result)return fail();
    lua_newtable(L);field(L,"ok",true);field(L,"steps",0);field(L,"work_unknown",true);
    lua_createtable(L,109,0);int index=0;
    for(const auto state:result->states){lua_pushinteger(L,state);lua_rawseti(L,-2,++index);}
    lua_setfield(L,-2,"states");lua_createtable(L,17,0);index=0;
    for(const auto state:result->categories){lua_pushinteger(L,state);lua_rawseti(L,-2,++index);}
    lua_setfield(L,-2,"categories");
    field(L,"plant_cheese",!pile->settings.food.cheese_plant.empty());
    field(L,"animal_powder",!pile->settings.food.powder_creature.empty());return 1;
  } catch(...) {return fail();}
}
int areaSettingsRows(lua_State* L) {
  bool attempted=false;
  const auto fail=[&]() {
    lua_newtable(L);field(L,"ok",false);field(L,"message","");field(L,"steps",0);
    field(L,"work_unknown",attempted);return 1;
  };
  auto* pile=Lua::GetDFObject<df::building_stockpilest>(L,1);
  if(!pile || !lua_isinteger(L,2) || lua_type(L,3)!=LUA_TSTRING || !lua_isnil(L,4))return fail();
  const auto mode=lua_tointeger(L,2);
  size_t length=0;const auto* query=lua_tolstring(L,3,&length);
  if(mode<0 || mode>109 || length>512)return fail();
  try {
    attempted=true;
    const auto rows=ownedStockpileRows(pile,int32_t(mode),UTF2DF(std::string(query,length)));
    if(!rows || rows->size()>65536)return fail();
    for(const auto& row:*rows)if(DF2UTF(row.name).size()>512)return fail();
    lua_newtable(L);field(L,"ok",true);field(L,"steps",0);field(L,"work_unknown",true);
    lua_createtable(L,int(rows->size()),0);int index=0;
    for(const auto& row:*rows) {
      lua_newtable(L);field(L,"field",row.field);field(L,"index",int64_t(row.index));
      field(L,"label",DF2UTF(row.name));field(L,"enabled",row.enabled);field(L,"visible",row.visible);
      lua_rawseti(L,-2,++index);
    }
    lua_setfield(L,-2,"rows");return 1;
  } catch(...) {return fail();}
}
int areaSettingsCategories(lua_State* L) {
  const auto result=[&](bool ok,const char* message,uint32_t steps,bool unknown=false) {
    lua_newtable(L);field(L,"ok",ok);field(L,"message",message);field(L,"steps",steps);
    field(L,"work_unknown",unknown);return 1;
  };
  auto* pile=Lua::GetDFObject<df::building_stockpilest>(L,1);
  if(!pile || !df::global::world)return result(false,"Area no longer exists",1);
  for(int i=2;i<=3;++i)if(!lua_isinteger(L,i) || lua_tointeger(L,i)<0 || lua_tointeger(L,i)>0x1ffff)
    return result(false,"invalid stockpile categories",1);
  if(!areaPresetInventoryFits(pile))return result(false,"Stockpile settings exceed 65,536 entries",158);
  const auto changed=uint32_t(lua_tointeger(L,2)),desired=uint32_t(lua_tointeger(L,3));
  try {
    auto owned=pile->settings;
    for(uint32_t bit=1;bit<=0x10000;bit<<=1)if(changed&bit) {
      if(desired&bit) {
        auto prepared=df3d_area::nativeStockpileCategory(owned,bit);
        if(!prepared)return result(false,"",158,true);
        owned=std::move(*prepared);
      } else owned.flags.whole&=~bit;
    }
    static_assert(std::is_nothrow_swappable_v<df::stockpile_settings>);
    std::swap(pile->settings,owned);
  } catch(...) {return result(false,"",158,true);}
  mutated=true;
  return result(true,"",158,true);
}
int areaSettingsHeader(lua_State* L) {
  const auto result=[&](bool ok,const char* reason,uint32_t steps=0,bool unknown=false) {
    lua_newtable(L);field(L,"ok",ok);field(L,"message",reason);field(L,"steps",steps);
    field(L,"work_unknown",unknown);return 1;
  };
  auto* pile=Lua::GetDFObject<df::building_stockpilest>(L,1);
  if(!pile || !df::global::world)return result(false,"Area no longer exists",1);
  if(!lua_isnil(L,4) || !lua_isinteger(L,2) || lua_tointeger(L,2)<0 ||
      lua_tointeger(L,2)>0x1ffff || lua_type(L,3)!=LUA_TBOOLEAN)return result(false,"");
  if(!areaPresetInventoryFits(pile))return result(false,"Stockpile settings exceed 65,536 entries",158);
  try {
    auto owned=df3d_area::nativeStockpileHeader(pile->settings,uint32_t(lua_tointeger(L,2)),lua_toboolean(L,3)!=0);
    if(!owned)return result(false,"",158,true);
    static_assert(std::is_nothrow_swappable_v<df::stockpile_settings>);
    std::swap(pile->settings,*owned);
  } catch(...) {return result(false,"",158,true);}
  mutated=true;return result(true,"",158,true);
}
int areaSettingsPreset(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=1,bool unknownWork=false) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);
    field(L,"work_unknown",unknownWork);return 1;
  };
  auto* pile=Lua::GetDFObject<df::building_stockpilest>(L,1);
  if(!pile || !df::global::world)return fail("Area no longer exists");
  if(!lua_isinteger(L,2) || lua_tointeger(L,2)<1 || lua_tointeger(L,2)>19)
    return fail("Invalid stockpile preset");
  if(!areaPresetInventoryFits(pile))return fail("Stockpile settings exceed 65,536 entries",158);
  bool applied=false;
  try {
    const auto preset=int(lua_tointeger(L,2));
    auto settings=df3d_area::nativeStockpilePreset(pile->settings,preset);
    const auto containers=df3d_area::nativeStockpilePresetContainers(*pile,preset);
    if(settings && containers) {
      // All allocation and native work precede this nonthrowing publication.
      // Links, identity and all other building state retain their ownership.
      static_assert(std::is_nothrow_swappable_v<df::stockpile_settings>);
      std::swap(pile->settings,*settings);
      pile->storage.max_barrels=(*containers)[0];
      pile->storage.max_bins=(*containers)[1];
      pile->storage.max_wheelbarrows=(*containers)[2];
      applied=true;
    }
  } catch(...) {}
  if(!applied)return fail("Native stockpile preset failed; previous settings restored",158,true);
  mutated=true;
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",158);
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
// A transfer prepares donor cells without changing their allocation or bounds.
// Native paint clears these cells and cleans every affected donor after the
// recipient footprint is published. Empty donors use DF's semantic destructor.
struct StockpileTransfers {
  struct Donor {df::building_stockpilest* pile;std::vector<size_t> cells;};
  std::vector<Donor> donors;
  bool prepare(df::building_stockpilest* recipient,int32_t x,int32_t y,int32_t z) {
    const auto found=df3d_area::nativeStockpileAt(int16_t(x),int16_t(y),int16_t(z));
    if(!found)return false;
    auto* donor=*found;
    if(!donor || donor==recipient)return true;
    if(donor->flags.bits.almost_deleted || !donor->room.extents || donor->room.width<1 || donor->room.height<1 ||
        donor->room.width>256 || donor->room.height>256 ||
        int64_t(donor->room.width)*donor->room.height>32768)return false;
    const int64_t dx=int64_t(x)-donor->room.x,dy=int64_t(y)-donor->room.y;
    if(dx<0 || dy<0 || dx>=donor->room.width || dy>=donor->room.height)return false;
    const size_t index=size_t(dy)*donor->room.width+size_t(dx);
    if(donor->room.extents[index]==df::building_extents_type::None)return false;
    auto row=std::find_if(donors.begin(),donors.end(),[&](const Donor& value){return value.pile==donor;});
    if(row==donors.end()) {
      if(!df3d_area::nativeStockpileRepaintReady(*donor))return false;
      donors.push_back({donor,{}});row=donors.end()-1;
    }
    row->cells.push_back(index);return true;
  }
  void clearCells() {
    for(auto& donor:donors)for(const auto index:donor.cells)
      donor.pile->room.extents[index]=df::building_extents_type::None;
  }
  bool cleanup() {
    for(auto& donor:donors) {
      const auto count=df3d_area::nativeStockpileTileCount(*donor.pile);
      if(!count)return false;
      if(*count) {if(!df3d_area::nativeStockpileRepaintCleanup(*donor.pile))return false;}
      else if(!df3d_area::nativeStockpileRemoveEmpty(*donor.pile))return false;
    }
    return true;
  }
};
// Construction receives the already validated wire request. Only native code
// owns unpublished extents/buildings; Lua sees an ID after native publication.
int areaCreate(lua_State* L) {
  uint64_t steps=0;bool unknownWork=false,noOp=false;int32_t createdId=-1;
  const auto execute=[&]() -> const char* {
    if(action!=m::ManagementAction::AreaCreate || request.empty())return "Area creation request required";
    const auto* a=flatbuffers::GetRoot<m::ConstructionRequest>(request.data())->area();
    if(!a || (a->operation()!=m::AreaOperation::None && a->operation()!=m::AreaOperation::Paint))
      return "Area creation request required";
    if(!df::global::world || !df::global::plotinfo || !df::global::building_next_id)return "World is not loaded";
    if(*df::global::building_next_id<0 || *df::global::building_next_id==INT32_MAX)return "Building IDs exhausted";
    const bool pile=a->kind()==m::AreaKind::Stockpile;
    if(!pile && (!df3d_area::nativeZoneCreateReady() ||
        (a->owner_id()>=0 && !df3d_area::nativeZoneOwnerReady())))return "";
    const int32_t z=a->operation()==m::AreaOperation::Paint?a->paint_z():a->origin()->z();
    if(pile && a->categories()) {
      std::array<size_t,78> counts{};size_t index=0;
      for(const auto& entry:areaSettingRawCounts())counts[index++]=entry.second;
      steps+=79;
      if(!df3d_area::settingsRawTotal(counts).valid)return "Stockpile settings exceed 65,536 entries";
    }
    // Native creation assigns the next per-kind number with max+1.
    int32_t stockpileNumber=1,zoneNumber=1;
    if(pile) {
      for(const auto* b:df::global::world->buildings.other.STOCKPILE) {
        ++steps;if(!b)return "Area no longer exists";
        if(b->stockpile_number==INT32_MAX)return "Stockpile numbers exhausted";
        stockpileNumber=(std::max)(stockpileNumber,b->stockpile_number+1);
      }
    } else {
      for(const auto* b:df::global::world->buildings.other.ANY_ZONE) {
        ++steps;if(!b)return "Area no longer exists";
        if(b->zone_num==INT32_MAX)return "Zone numbers exhausted";
        zoneNumber=(std::max)(zoneNumber,b->zone_num+1);
      }
    }
    std::vector<std::pair<int32_t,int32_t>> clipped;
    StockpileTransfers transfers;
    const auto checkSite=[&](int32_t x,int32_t y) -> const char* {
      auto* block=Maps::isValidTilePos(x,y,z)?Maps::getTileBlock(x,y,z):nullptr;
      if(!block)return "Every selected tile must be visible and loaded";
      const auto& designation=block->designation[x&15][y&15];
      if(pile) {
        const auto eligible=df3d_area::nativeStockpileTileType(uint16_t(block->tiletype[x&15][y&15]));
        if(!eligible)return "";
        if(designation.bits.hidden || !*eligible ||
            (block->occupancy[x&15][y&15].bits.building!=df::tile_building_occ::None && !designation.bits.pile)) {
          clipped.emplace_back(x,y);return nullptr;
        }
        if(designation.bits.pile && !transfers.prepare(nullptr,x,y,z))return "";
      } else if(designation.bits.hidden)return "Every selected tile must be visible and loaded";
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
    for(const auto& cell:clipped) {
      const size_t index=size_t(cell.second-bounds.y)*bounds.width+cell.first-bounds.x;
      if(extents[index]!=df::building_extents_type::None) {
        extents[index]=df::building_extents_type::None;--expectedTiles;
      }
    }
    if(pile && !expectedTiles){noOp=true;return nullptr;}
    if(pile) {
      auto settings=df3d_area::nativeStockpileInitialSettings(a->categories());
      if(!settings || !df3d_area::nativeStockpileCreateReady())return "";
      // Prepare allocations before the native constructor publishes an ID.
      for(int by=bounds.y>>4;by<=(bounds.y+bounds.height-1)>>4;++by)
        for(int bx=bounds.x>>4;bx<=(bounds.x+bounds.width-1)>>4;++bx)areaHints.push_back({bx<<4,by<<4,z});
      unknownWork=true;mutated=true;
      auto* stock=df3d_area::nativeStockpileAllocate();
      if(!stock)return "Native area construction failed; cleanup uncertain; inspect before retrying";
      createdId=stock->id;
      stock->race=df::global::plotinfo->race_id;
      stock->x1=stock->room.x=bounds.x;stock->y1=stock->room.y=bounds.y;stock->z=z;
      stock->x2=bounds.x+bounds.width-1;stock->y2=bounds.y+bounds.height-1;
      stock->centerx=(stock->x1+stock->x2)/2;stock->centery=(stock->y1+stock->y2)/2;
      stock->room.width=bounds.width;stock->room.height=bounds.height;
      stock->stockpile_number=stockpileNumber;stock->settings=std::move(*settings);
      stock->room.extents=extents.release();
      // Native creation marks accepted cells as piles before completion
      // (3538b4..3538dd). Completion sets occupancy but not this designation.
      for(int y=0;y<bounds.height;++y)for(int x=0;x<bounds.width;++x) {
        if(stock->room.extents[y*bounds.width+x]==df::building_extents_type::None)continue;
        auto* block=Maps::getTileBlock(bounds.x+x,bounds.y+y,z);
        block->designation[(bounds.x+x)&15][(bounds.y+y)&15].bits.pile=true;
      }
      if(!df3d_area::nativeStockpileComplete(*stock))return "Native area construction failed; cleanup uncertain; inspect before retrying";
      transfers.clearCells();
      if(!transfers.cleanup())return "Native area construction failed; cleanup uncertain; inspect before retrying";
      return nullptr;
    }
    // The native factory publishes its ID immediately. Prepare owned storage
    // and invalidation hints first; partial native effects are never replayed.
    for(int by=bounds.y>>4;by<=(bounds.y+bounds.height-1)>>4;++by)
      for(int bx=bounds.x>>4;bx<=(bounds.x+bounds.width-1)>>4;++bx)areaHints.push_back({bx<<4,by<<4,z});
    unknownWork=true;mutated=true;
    auto* zone=df3d_area::nativeZoneAllocate();
    if(!zone)return "Native area construction failed; cleanup uncertain; inspect before retrying";
    createdId=zone->id;
    zone->race=df::global::plotinfo->race_id;
    zone->type=static_cast<df::civzone_type>(a->zone_type());
    zone->spec_sub_flag.whole=8;
    zone->x1=zone->room.x=bounds.x;zone->y1=zone->room.y=bounds.y;zone->z=z;
    zone->x2=bounds.x+bounds.width-1;zone->y2=bounds.y+bounds.height-1;
    zone->centerx=(zone->x1+zone->x2)/2;zone->centery=(zone->y1+zone->y2)/2;
    zone->room.width=bounds.width;zone->room.height=bounds.height;
    zone->zone_num=zoneNumber;zone->room.extents=extents.release();
    if(!df3d_area::nativeZoneDefaults(*zone) || !df3d_area::nativeZoneComplete(*zone))
      return "Native area construction failed; cleanup uncertain; inspect before retrying";
    return nullptr;
  };
  const char* reason=nullptr;
  try {reason=execute();}
  catch(...) {reason=mutated?"Native area construction failed; cleanup uncertain; inspect before retrying":"Native area preparation failed; no area created";}
  // All unpublished owners have unwound before Lua can allocate its response.
  lua_newtable(L);field(L,"ok",reason==nullptr);field(L,"message",reason?reason:"");
  field(L,"steps",steps);field(L,"work_unknown",unknownWork);field(L,"building_id",createdId);field(L,"paint_noop",noOp);return 1;
}
int areaSquadName(lua_State* L) {
  auto* squad=Lua::GetDFObject<df::squad>(L,1);
  std::optional<std::string> text;
  if(squad){try{text=df3d_area::nativeZoneSquadName(*squad);}catch(...){}}
  if(!text){lua_pushnil(L);return 1;}
  const auto utf=DF2UTF(*text);lua_pushlstring(L,utf.data(),utf.size());return 1;
}
int areaSquadSymbol(lua_State* L) {
  auto* squad=Lua::GetDFObject<df::squad>(L,1);
  const auto symbol=squad?df3d_area::nativeZoneSquadSymbol(*squad):std::nullopt;
  if(!symbol){lua_pushnil(L);return 1;}
  lua_newtable(L);const char* fields[]={"index","foreground_r","foreground_g","foreground_b","background_r","background_g","background_b"};
  for(size_t i=0;i<7;++i)field(L,fields[i],int((*symbol)[i]));return 1;
}
int areaSquadCandidates(lua_State* L) {
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);
  std::optional<std::vector<int32_t>> ids;
  if(zone && (zone->type==df::civzone_type::Barracks || zone->type==df::civzone_type::ArcheryRange)) {
    try {ids=df3d_area::nativeZoneSquadCandidates();}catch(...){}
  }
  if(!ids){lua_pushnil(L);return 1;}
  lua_newtable(L);int index=0;
  for(auto id:*ids){lua_pushinteger(L,id);lua_rawseti(L,-2,++index);}
  return 1;
}
int areaAnimalCandidates(lua_State* L) {
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);
  std::optional<std::vector<df3d_area::ZoneAnimalCandidate>> rows;
  size_t querySize=0;const char* query=lua_tolstring(L,4,&querySize);
  const auto sort=lua_tointeger(L,2);
  if(zone && lua_isinteger(L,2) && sort>=0 && sort<=3 && lua_isboolean(L,3) && query && querySize<=128) {
    try {rows=df3d_area::nativeZoneAnimalPickerCandidates(*zone,int32_t(sort),lua_toboolean(L,3)!=0,
      lua_toboolean(L,5)?std::string(query,querySize):UTF2DF(std::string(query,querySize)));} catch(...) {}
  }
  if(!rows){lua_pushnil(L);return 1;}
  lua_newtable(L);int index=0;
  for(const auto& row:*rows) {
    lua_newtable(L);field(L,"id",row.id);field(L,"entity",row.item?2:1);field(L,"assigned",row.assigned);
    lua_rawseti(L,-2,++index);
  }
  return 1;
}
int areaAnimalItemText(lua_State* L) {
  auto* item=Lua::GetDFObject<df::item>(L,1);
  std::optional<std::string> text;
  if(item) {try {text=df3d_area::nativeZoneAnimalItemText(*item);} catch(...) {}}
  if(!text){lua_pushnil(L);return 1;}
  const auto utf=DF2UTF(*text);lua_pushlstring(L,utf.data(),utf.size());return 1;
}
int areaAnimalStatus(lua_State* L) {
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);
  const auto entity=lua_tointeger(L,2);
  std::optional<df3d_area::ZoneAnimalStatus> status;
  if(zone)try {
    if(entity==1) {if(auto* unit=Lua::GetDFObject<df::unit>(L,3))status=df3d_area::nativeZoneAnimalStatus(*zone,*unit);}
    else if(entity==2)status=df3d_area::nativeZoneAnimalItemStatus(*zone,lua_toboolean(L,4));
  }catch(...) {}
  if(!status){lua_pushnil(L);return 1;}
  lua_newtable(L);field(L,"kind",status->kind);field(L,"containment",status->containment);field(L,"item_id",status->itemId);return 1;
}
int areaAnimalRestraint(lua_State* L) {
  auto* item=df::item::find(int32_t(lua_tointeger(L,1)));
  std::optional<df3d_area::ZoneAnimalRestraint> facts;
  if(item)try {facts=df3d_area::nativeZoneAnimalRestraint(*item);}catch(...) {}
  if(!facts){lua_pushnil(L);return 1;}
  lua_newtable(L);field(L,"rope",facts->rope);field(L,"solid_color",facts->solidColor);return 1;
}
int areaAnimalContainer(lua_State* L) {
  auto* item=df::item::find(int32_t(lua_tointeger(L,1)));
  std::optional<df3d_area::ZoneAnimalContainer> facts;
  if(item)try {facts=df3d_area::nativeZoneAnimalContainer(*item);}catch(...) {}
  if(!facts){lua_pushnil(L);return 1;}
  ResidentAppearanceRecipe occupant;
  if(facts->occupantEntity==1)occupant.collect(df::unit::find(facts->occupantId),true);
  else if(facts->occupantEntity==2) {
    df3d_appearance::Result source;
    if(df3d_appearance::resolveCritterItemSelector(df::item::find(facts->occupantId),source))
      for(const auto& layer:source.layers)appendAppearanceLayer(occupant.pages,occupant.palettes,occupant.layers,layer);
  }
  lua_newtable(L);field(L,"material_family",facts->materialFamily);field(L,"solid_color",facts->solidColor);
  field(L,"occupant_entity",facts->occupantEntity);field(L,"occupant_id",facts->occupantId);
  if(!occupant.layers.empty()) {
    flatbuffers::FlatBufferBuilder buffer;buffer.Finish(occupant.build(buffer));
    lua_pushlstring(L,reinterpret_cast<const char*>(buffer.GetBufferPointer()),buffer.GetSize());lua_setfield(L,-2,"occupant");
  }
  return 1;
}
int areaAnimalItemColor(lua_State* L) {
  auto* item=Lua::GetDFObject<df::item>(L,1);
  const auto color=item?df3d_area::nativeZoneAnimalItemColor(*item):std::nullopt;
  if(!color){lua_pushnil(L);return 1;}
  lua_newtable(L);field(L,"foreground",(*color)[0]);field(L,"background",(*color)[1]);field(L,"bright",(*color)[2]);return 1;
}
int areaAnimalItemIcon(lua_State* L) {
  auto* item=Lua::GetDFObject<df::item>(L,1);
  df3d_appearance::Result source;
  if(!df3d_appearance::resolveCritterItemSelector(item,source)){lua_pushnil(L);return 1;}
  ResidentAppearanceRecipe icon;
  for(const auto& layer:source.layers)appendAppearanceLayer(icon.pages,icon.palettes,icon.layers,layer);
  flatbuffers::FlatBufferBuilder buffer;buffer.Finish(icon.build(buffer));
  lua_pushlstring(L,reinterpret_cast<const char*>(buffer.GetBufferPointer()),buffer.GetSize());return 1;
}
int areaOwnerEligible(lua_State* L) {
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);
  auto* unit=Lua::GetDFObject<df::unit>(L,2);
  std::optional<bool> eligible;
  if(zone && unit) {
    try {eligible=df3d_area::nativeZoneOwnerEligible(*zone,*unit);} catch(...) {}
  }
  if(eligible.has_value())lua_pushboolean(L,*eligible);else lua_pushnil(L);
  return 1;
}
int areaNewOwnerEligible(lua_State* L) {
  const auto type=lua_tointeger(L,1);
  auto* unit=Lua::GetDFObject<df::unit>(L,2);
  std::optional<bool> eligible;
  if(lua_isnumber(L,1) && type>=0 && type<=INT32_MAX && unit) {
    try {eligible=df3d_area::nativeZoneNewOwnerEligible(int32_t(type),*unit);} catch(...) {}
  }
  if(eligible.has_value())lua_pushboolean(L,*eligible);else lua_pushnil(L);
  return 1;
}
int areaOwnerQuery(lua_State* L) {
  size_t size=0;const char* value=lua_tolstring(L,1,&size);
  std::optional<std::string> normalized;
  if(value && size<=128) {
    try {normalized=df3d_area::nativeZoneOwnerQuery(std::string(value,size));} catch(...) {}
  }
  if(normalized)lua_pushlstring(L,normalized->data(),normalized->size());else lua_pushnil(L);
  return 1;
}
int areaOwnerOrderFacts(lua_State* L) {
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);
  auto* unit=Lua::GetDFObject<df::unit>(L,2);
  std::optional<df3d_area::ZoneOwnerOrderFacts> facts;
  if(zone && unit) {
    try {facts=df3d_area::nativeZoneOwnerOrderFacts(*zone,*unit);} catch(...) {}
  }
  if(!facts){lua_pushnil(L);return 1;}
  lua_newtable(L);field(L,"without_room",facts->withoutRoom);field(L,"priority",facts->priority);
  field(L,"category",facts->category);field(L,"category_status",facts->categoryStatus);field(L,"stress",facts->stress);
  lua_pushlstring(L,facts->nameKey.data(),facts->nameKey.size());lua_setfield(L,-2,"name_key");
  lua_pushlstring(L,facts->professionKey.data(),facts->professionKey.size());lua_setfield(L,-2,"profession_key");return 1;
}
int areaAnimalUnitDisplay(lua_State* L) {
  auto* unit=Lua::GetDFObject<df::unit>(L,1);
  std::optional<df3d_area::ZoneAnimalUnitDisplay> display;
  if(unit)try {display=df3d_area::nativeZoneAnimalUnitDisplay(*unit,27);}catch(...) {}
  if(!display){lua_pushnil(L);return 1;}
  const auto& text=display->text;const auto& color=display->nameColor;
  lua_newtable(L);field(L,"columns",27);field(L,"first_line",DF2UTF(text.firstLine));field(L,"second_line",DF2UTF(text.secondLine));
  field(L,"combined_fits",text.combined.size()<=27);field(L,"warning",DF2UTF(display->warning));field(L,"grazer",display->grazer);
  field(L,"name",DF2UTF(text.combined));field(L,"profession",DF2UTF(text.profession));
  lua_newtable(L);field(L,"foreground",color.color[0]);field(L,"background",color.color[1]);field(L,"bright",color.color[2]);
  field(L,"alternate_foreground",color.alternate[0]);field(L,"alternate_background",color.alternate[1]);field(L,"alternate_bright",color.alternate[2]);field(L,"effect",color.effect);
  lua_setfield(L,-2,"name_color");
  if(lua_toboolean(L,2)) {
    ResidentAppearanceRecipe icon;icon.collect(unit,true);
    if(!icon.layers.empty()) {
      flatbuffers::FlatBufferBuilder buffer;buffer.Finish(icon.build(buffer));
      lua_pushlstring(L,reinterpret_cast<const char*>(buffer.GetBufferPointer()),buffer.GetSize());lua_setfield(L,-2,"sheet_icon");
    }
  }
  return 1;
}
int areaOwnerDisplay(lua_State* L) {
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);
  auto* unit=Lua::GetDFObject<df::unit>(L,2);
  std::optional<df3d_area::ZoneOwnerDisplayText> text;
  std::optional<df3d_area::ZoneOwnerRoomStatus> status;
  std::optional<df3d_area::ZoneOwnerNameColor> color;
  if(zone && unit) {
    try {text=df3d_area::nativeZoneOwnerDisplayText(*unit,45);status=df3d_area::nativeZoneOwnerRoomStatus(*zone,*unit);color=df3d_area::nativeZoneOwnerNameColor(*unit);} catch(...) {}
  }
  if(!text || !status || !color){lua_pushnil(L);return 1;}
  // Current owner panel has45 logical columns; scaling preserves those cells.
  // Retained jobs receive owned UTF-8 values, never callbacks or widget state.
  lua_newtable(L);field(L,"columns",45);field(L,"room_value",status->value);
  field(L,"first_line",DF2UTF(text->firstLine));field(L,"second_line",DF2UTF(text->secondLine));
  field(L,"status",DF2UTF(status->label));field(L,"name",DF2UTF(text->name));field(L,"profession",DF2UTF(text->profession));
  lua_newtable(L);field(L,"foreground",color->color[0]);field(L,"background",color->color[1]);field(L,"bright",color->color[2]);
  field(L,"alternate_foreground",color->alternate[0]);field(L,"alternate_background",color->alternate[1]);field(L,"alternate_bright",color->alternate[2]);field(L,"effect",color->effect);
  lua_setfield(L,-2,"name_color");
  ResidentAppearanceRecipe icon;icon.collect(unit,true);
  if(!icon.layers.empty()) {
    flatbuffers::FlatBufferBuilder buffer;buffer.Finish(icon.build(buffer));
    lua_pushlstring(L,reinterpret_cast<const char*>(buffer.GetBufferPointer()),buffer.GetSize());lua_setfield(L,-2,"sheet_icon");
  }
  return 1;
}
int areaSetOwner(lua_State* L) {
  bool attempted=false;
  const auto result=[&](bool ok,const char* reason) {
    lua_newtable(L);field(L,"ok",ok);field(L,"message",reason);
    field(L,"steps",0);field(L,"work_unknown",attempted);return 1;
  };
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);
  auto* owner=lua_isnil(L,2)?nullptr:Lua::GetDFObject<df::unit>(L,2);
  if(!zone || (!lua_isnil(L,2) && !owner) || !lua_isnil(L,3))
    return result(false,"Native owner assignment failed");
  if(!df3d_area::nativeZoneOwnerReady() || !zone->canBeRoomSubset())
    return result(false,"Native owner assignment failed");
  try {
    attempted=true;mutated=true;
    if(!df3d_area::nativeZoneSetOwner(*zone,owner))
      return result(false,"Native owner assignment failed; inspect before retrying");
  } catch(...) {return result(false,"Native owner assignment failed; inspect before retrying");}
  return result(true,"");
}
int areaRemove(lua_State* L) {
  const auto result=[&](bool ok,const char* reason) {
    lua_newtable(L);field(L,"ok",ok);field(L,"message",reason);
    field(L,"steps",0);field(L,"work_unknown",true);return 1;
  };
  auto* target=Lua::GetDFObject<df::building>(L,1);
  if(!target || (!virtual_cast<df::building_stockpilest>(target) && !virtual_cast<df::building_civzonest>(target)))
    return result(false,"Area no longer exists");
  auto* zone=virtual_cast<df::building_civzonest>(target);
  if(zone && !df3d_area::nativeZoneRemoveReady())return result(false,"Native zone removal unavailable");
  bool removed=false;
  try {
    // Native semantic cleanup owns relationships and destruction.
    // It can mutate before failing; refresh even if no success reply survives.
    mutated=true;removed=zone?df3d_area::nativeZoneRemove(*zone):Buildings::deconstruct(target);
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
  if(lua_type(L,2)!=LUA_TSTRING || lua_type(L,3)!=LUA_TSTRING ||
      lua_type(L,4)!=LUA_TSTRING || lua_type(L,5)!=LUA_TBOOLEAN)
    return fail("Invalid settings fill arguments");
  size_t keyLength=0,membersLength=0,allowedLength=0;
  const char* key=lua_tolstring(L,2,&keyLength);
  const char* members=lua_tolstring(L,3,&membersLength);
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
// Validate semantic identity/staleness before native assignment. Native owns
// membership references and chain-job destruction; failures may be partial.
int areaAssignUnit(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=1) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);return 1;
  };
  if(!lua_isnil(L,4) && (!lua_isinteger(L,4) || lua_tointeger(L,4)<0 || lua_tointeger(L,4)>1536))return fail("Invalid assignment budget",0);
  const uint32_t budget=lua_isnil(L,4)?UINT32_MAX:uint32_t(lua_tointeger(L,4));if(!budget)return fail("Unit assignment exceeds remaining step budget",0);
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);auto* unit=Lua::GetDFObject<df::unit>(L,2);
  if(!zone || !unit || !df::global::world)return fail("Area or unit no longer exists");
  if(!lua_isinteger(L,3) || lua_tointeger(L,3)<0 || lua_tointeger(L,3)>1)return fail("invalid area unit assignment");
  const bool assign=lua_tointeger(L,3)!=0;
  if(action!=m::ManagementAction::AreaUpdate || request.empty())return fail("Unit assignment request required");
  const auto* op=flatbuffers::GetRoot<m::ConstructionRequest>(request.data())->area();
  if(!op || op->operation()!=m::AreaOperation::AssignUnits || op->id()!=zone->id || op->unit_id()!=unit->id || bool(op->assign())!=assign)
    return fail("Unit assignment request required");
  if(zone->type!=df::civzone_type::Pen && zone->type!=df::civzone_type::Pond)return fail("This operation does not apply to this zone type");
  if(!df3d_area::nativeZoneAnimalAssignmentReady())return fail("Native animal assignment unavailable");
  if(assign) {
    std::optional<std::vector<df3d_area::ZoneAnimalCandidate>> candidates;
    try {candidates=df3d_area::nativeZoneAnimalCandidates(*zone);} catch(...) {}
    if(!candidates)return fail("Native animal assignment unavailable");
    if(std::none_of(candidates->begin(),candidates->end(),[&](const auto& row){return !row.item && row.id==unit->id;}))
      return fail("Invalid area unit assignment");
  }
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
  if(zone->assigned_units.size()+zone->assigned_items.size()>4096 || (oldZone && oldZone->assigned_units.size()+oldZone->assigned_items.size()>4096))return fail("Zone exceeds 4,096 assigned units",steps);
  if(assign && !oldRef && unit->general_refs.size()==256)return fail("Zone assignment list exceeds 256 entries",steps);
  if(assign && zone->assigned_units.size()+zone->assigned_items.size()==4096 &&
      std::find(zone->assigned_units.begin(),zone->assigned_units.end(),unit->id)==zone->assigned_units.end())
    return fail("Zone exceeds 4,096 assigned units",steps);
  const auto cageScan=df3d_area::scanAssignedCages(df::global::world->buildings.other.CAGE,unit->id,budget-steps);
  steps+=cageScan.steps;
  if(cageScan.error==ScanError::Limit)return fail("Cage scan exceeds 256 cages",steps);
  if(cageScan.error==ScanError::Budget)return fail("Unit assignment exceeds remaining step budget",steps);
  if(cageScan.error==ScanError::Invalid)return fail("Area no longer exists",steps);
  try {
    mutated=true;
    if(!df3d_area::nativeZoneAssignUnit(*zone,*unit,assign)) {
      lua_newtable(L);field(L,"ok",false);field(L,"message","Native animal assignment failed; inspect before retrying");
      field(L,"steps",steps);field(L,"work_unknown",true);return 1;
    }
  } catch(...) {
    lua_newtable(L);field(L,"ok",false);field(L,"message","Native animal assignment failed; inspect before retrying");
    field(L,"steps",steps);field(L,"work_unknown",true);return 1;
  }
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",steps);field(L,"work_unknown",true);
  return 1;
}
int areaAssignItem(lua_State* L) {
  bool entered=false;uint32_t steps=1;
  const auto result=[&](bool ok,const char* reason) {
    lua_newtable(L);field(L,"ok",ok);field(L,"message",reason);field(L,"steps",steps);
    field(L,"work_unknown",entered);return 1;
  };
  if(!lua_isnil(L,4) && (!lua_isinteger(L,4) || lua_tointeger(L,4)<1 || lua_tointeger(L,4)>1536))
    return result(false,"Invalid assignment budget");
  const uint32_t budget=lua_isnil(L,4)?UINT32_MAX:uint32_t(lua_tointeger(L,4));
  auto* zone=Lua::GetDFObject<df::building_civzonest>(L,1);auto* item=Lua::GetDFObject<df::item>(L,2);
  if(!zone || !item || !df::global::world)return result(false,"Area or item no longer exists");
  if(!lua_isinteger(L,3) || lua_tointeger(L,3)<0 || lua_tointeger(L,3)>1)
    return result(false,"Invalid area item assignment");
  const bool assign=lua_tointeger(L,3)!=0;
  if(action!=m::ManagementAction::AreaUpdate || request.empty())return result(false,"Item assignment request required");
  const auto* op=flatbuffers::GetRoot<m::ConstructionRequest>(request.data())->area();
  if(!op || op->operation()!=m::AreaOperation::AssignUnits || op->id()!=zone->id ||
      op->item_id()!=item->id || op->unit_id()!=-1 || bool(op->assign())!=assign)
    return result(false,"Item assignment request required");
  if(zone->type!=df::civzone_type::Pen && zone->type!=df::civzone_type::Pond)
    return result(false,"This operation does not apply to this zone type");
  if(!df3d_area::nativeZoneAnimalAssignmentReady())return result(false,"Native animal assignment unavailable");
  if(assign && !df3d_area::nativeZoneItemEligible(*zone,*item))return result(false,"Invalid area item assignment");
  const auto scan=df3d_area::scanZoneReferences(item->general_refs,
      [](auto* ref){return virtual_cast<df::general_ref_building_civzone_assignedst>(ref)!=nullptr;},budget-1);
  steps+=scan.steps;
  if(scan.error!=df3d_area::AssignmentScanError::None)return result(false,"Invalid or excessive native item references");
  auto* oldRef=scan.previous?virtual_cast<df::general_ref_building_civzone_assignedst>(scan.previous):nullptr;
  auto* oldZone=oldRef?virtual_cast<df::building_civzonest>(df::building::find(oldRef->building_id)):nullptr;
  if(oldRef && !oldZone)return result(false,"Previous zone no longer exists");
  if(!assign && oldZone && oldZone!=zone)return result(false,"Item assignment changed; inspect again");
  const auto assigned=zone->assigned_units.size()+zone->assigned_items.size();
  const bool present=std::find(zone->assigned_items.begin(),zone->assigned_items.end(),item->id)!=zone->assigned_items.end();
  if(assigned>4096 || (assign && !present && assigned==4096))
    return result(false,"Zone assignment list exceeds 4,096 entries");
  if(assign && !oldRef && item->general_refs.size()==256)return result(false,"Zone assignment list exceeds 256 entries");
  try {
    entered=true;mutated=true;
    if(!df3d_area::nativeZoneAssignItem(*zone,*item,assign))
      return result(false,"Native animal assignment failed; inspect before retrying");
  } catch(...) {return result(false,"Native animal assignment failed; inspect before retrying");}
  return result(true,"");
}
// Native owns squad/zone records, equipment invalidation and rack membership.
int areaSquadUse(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=1) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);return 1;
  };
  if(!lua_isnil(L,4) && (!lua_isinteger(L,4) || lua_tointeger(L,4)<0 || lua_tointeger(L,4)>1536))return fail("Invalid squad budget",0);
  const uint32_t budget=lua_isnil(L,4)?UINT32_MAX:uint32_t(lua_tointeger(L,4));if(!budget)return fail("Squad use exceeds remaining step budget",0);
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
  if(zone->squad_room_info.size()>256)return fail("Zone assignment list exceeds 256 entries");
  if(!df3d_area::nativeZoneSquadAssignmentReady())return fail("Native squad assignment unavailable");
  const uint64_t cost=5+4*((uint64_t(zone->squad_room_info.size())+256)/256)+
      4*((uint64_t(squad->rooms.size())+256)/256);
  if(cost>budget)return fail("Squad use exceeds remaining step budget");
  if(use && zone->squad_room_info.size()==256 &&
      std::none_of(zone->squad_room_info.begin(),zone->squad_room_info.end(),
          [&](const auto* row){return row && row->squad_id==squad->id;}))
    return fail("Zone assignment list exceeds 256 entries",uint32_t(cost));
  try {
    mutated=true;
    if(!df3d_area::nativeZoneSetSquadUse(*zone,*squad,uint32_t(use))) {
      lua_newtable(L);field(L,"ok",false);field(L,"message","Native squad assignment failed; inspect before retrying");
      field(L,"steps",cost);field(L,"work_unknown",true);return 1;
    }
  } catch(...) {
    lua_newtable(L);field(L,"ok",false);field(L,"message","Native squad assignment failed; inspect before retrying");
    field(L,"steps",cost);field(L,"work_unknown",true);return 1;
  }
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",cost);field(L,"work_unknown",true);
  return 1;
}
// Lua checks the pile revision and reserves reply-snapshot work first. Native
// virtual methods include every supported workshop without guessing its type.
int areaLinkTarget(lua_State* L) {
  bool unknownWork=false;
  const auto reply=[&](bool ok,int32_t id=-1) {
    lua_newtable(L);field(L,"ok",ok);field(L,"message","");field(L,"steps",1);
    field(L,"work_unknown",unknownWork);field(L,"building_id",id);return 1;
  };
  auto* source=Lua::GetDFObject<df::building_stockpilest>(L,1);
  if(!source || !lua_isnil(L,2) || action!=m::ManagementAction::AreaInspect || request.empty())return reply(false);
  const auto* a=flatbuffers::GetRoot<m::ConstructionRequest>(request.data())->area();
  if(!a || a->operation()!=m::AreaOperation::LinkTarget || a->id()!=source->id || !a->origin())return reply(false);
  const auto x=a->origin()->x(),y=a->origin()->y(),z=a->origin()->z();
  auto* block=Maps::isValidTilePos(x,y,z)?Maps::getTileBlock(x,y,z):nullptr;
  // Hidden/unloaded/outside-map tiles cannot disclose targets and are ordinary
  // misses. Source visibility and revision were checked by the semantic owner.
  if(!block || block->designation[x&15][y&15].bits.hidden)return reply(true);
  unknownWork=true;
  const auto target=df3d_area::nativeStockpileLinkTarget(*source,x,y,z,a->give());
  return target?reply(true,*target?(*target)->id:-1):reply(false);
}
int areaLink(lua_State* L) {
  const auto fail=[&](const char* reason,uint32_t steps=1) {
    lua_newtable(L);field(L,"ok",false);field(L,"message",reason);field(L,"steps",steps);return 1;
  };
  const bool synchronous=lua_isnil(L,5);
  if(!synchronous && (!lua_isinteger(L,5) || lua_tointeger(L,5)<0 || lua_tointeger(L,5)>1536))return fail("Invalid link budget",0);
  const auto budget=synchronous?UINT32_MAX:uint32_t(lua_tointeger(L,5));
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
  // Native link preparation may copy and shift all four endpoint directions.
  // This explicit action is synchronous at a safe point; budget is not a claim
  // of bounded native work. Publication occurs only after owned preparation.
  const auto result=df3d_area::nativeStockpileLink(*workshop,*pile,give,unlink);
  if(!result)return fail("");
  mutated=*result;
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",1);
  field(L,"work_unknown",true);return 1;
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
  if(zone && !df3d_area::nativeZoneCreateReady())return fail("Native zone refresh unavailable");
  if(areaHoldingCount==areaHolding.size())return fail("Area retire capacity reached; restart DF3D bridge");
  if(!lua_isinteger(L,3) || lua_tointeger(L,3)<1 || lua_tointeger(L,3)>2 || !lua_istable(L,2))
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
  // Native repaint grows its allocation only around accepted cells, unlike
  // creation which retains the full selected rectangle. Filter before planning
  // bounds, using owned spans; never borrow the native paint menu's scratch.
  uint32_t eligibilitySteps=0;
  if(pile && mode==1) {
    if(requested>=budget)return fail("Paint exceeds remaining step budget",uint32_t(count));
    std::vector<df3d_area::Span> eligibleSpans;eligibleSpans.reserve(spans.size());
    for(const auto& span:spans)for(int32_t x=span.x;x<span.x+span.length;++x) {
      ++eligibilitySteps;
      auto* block=Maps::isValidTilePos(x,span.y,b->z)?Maps::getTileBlock(x,span.y,b->z):nullptr;
      if(!block)return fail("Every selected tile must be visible and loaded",eligibilitySteps);
      const auto eligible=df3d_area::nativeStockpileTileType(uint16_t(block->tiletype[x&15][span.y&15]));
      if(!eligible)return fail("",eligibilitySteps);
      const auto& designation=block->designation[x&15][span.y&15];
      if(designation.bits.hidden || !*eligible ||
          (block->occupancy[x&15][span.y&15].bits.building!=df::tile_building_occ::None && !designation.bits.pile))continue;
      if(!eligibleSpans.empty() && eligibleSpans.back().y==span.y && eligibleSpans.back().x+eligibleSpans.back().length==x)
        ++eligibleSpans.back().length;
      else eligibleSpans.push_back({span.y,x,1});
    }
    if(eligibleSpans.empty()) {
      lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",eligibilitySteps);return 1;
    }
    spans.swap(eligibleSpans);
  }
  // Site checks run in the planner's counted tile visit. Native occupancy is a
  // second pass over at most requested tiles; reserve it before allocating.
  const uint32_t reserved=requested+1;
  if(uint64_t(reserved)+eligibilitySteps>=budget || uint64_t(count)+reserved+eligibilitySteps>=budget)return fail("Paint exceeds remaining step budget",uint32_t(count)+eligibilitySteps);
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
  std::vector<Change> changes;changes.reserve(requested);
  StockpileTransfers transfers;
  const char* siteError="Invalid paint site";
  auto plan=df3d_area::paint<df3d_area::NativeExtents<df::building_extents_type>>(
      before,ExtentsView{b,size_t(width),size_t(height)},spans,mode,budget-reserved-eligibilitySteps,
      [&](int32_t x,int32_t y,int64_t prior,int64_t after) {
    auto* block=Maps::isValidTilePos(x,y,b->z)?Maps::getTileBlock(x,y,b->z):nullptr;
    if(!block || (block->designation[x&15][y&15].bits.hidden && !(pile && mode==2))) {
      siteError="Every selected tile must be visible and loaded";return false;
    }
    const auto& designation=block->designation[x&15][y&15];
    // Retained cells already belong to this area. Repainting them must not
    // fail placement validation against their own native occupancy.
    if(after!=0 && prior==0 && pile) {
      const auto eligible=df3d_area::nativeStockpileTileType(uint16_t(block->tiletype[x&15][y&15]));
      if(!eligible){siteError="";return false;}
      if(!*eligible) {siteError="Stockpiles require supported floor on every tile";return false;}
      if(block->occupancy[x&15][y&15].bits.building!=df::tile_building_occ::None && !designation.bits.pile) {
        siteError="Stockpile site contains liquid or a building";return false;
      }
      if(designation.bits.pile && !prior && !transfers.prepare(pile,x,y,b->z)){siteError="";return false;}
    }
    // Zone extents may include walls and fortifications, as native paint does.
    if(prior!=after)changes.push_back({block,x,y,after==0});
    return true;
  },true);
  const uint32_t spent=plan.steps+eligibilitySteps;
  if(plan.error!=df3d_area::Error::None) {
    switch(plan.error) {
      case df3d_area::Error::Empty:return fail("Erase would remove the whole area; use Remove",spent);
      case df3d_area::Error::TooLarge:return fail("Painted area would exceed 256 per side or 32,768 tiles",spent);
      case df3d_area::Error::InvalidSite:return fail(siteError,spent);
      case df3d_area::Error::Budget:return fail("Paint exceeds remaining step budget",spent);
      default:return fail("Invalid area paint geometry",spent);
    }
  }
  if(pile) {
    unknownWork=true;
    if(!df3d_area::nativeStockpileRepaintReady(*pile))return fail("Invalid area paint geometry",spent);
  }
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
  transfers.clearCells();
  b->room.extents=plan.extents.release();b->room.x=b->x1=plan.bounds.x;b->room.y=b->y1=plan.bounds.y;
  b->room.width=plan.bounds.width;b->room.height=plan.bounds.height;
  b->x2=b->x1+plan.bounds.width-1;b->y2=b->y1+plan.bounds.height-1;
  b->centerx=pile?(b->x1+b->x2)/2:b->x1+plan.bounds.width/2;
  b->centery=pile?(b->y1+b->y2)/2:b->y1+plan.bounds.height/2;
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
  if(pile) {
    // Native cleanup includes item lookup and vector retirement work. It runs
    // synchronously at this safe point; do not advertise a bounded work count.
    unknownWork=true;
    if(!transfers.cleanup())return fail("Area changed; inspect again",spent+uint32_t(changes.size())+1);
    if(!df3d_area::nativeStockpileRepaintCleanup(*pile))
      return fail("Area changed; inspect again",spent+uint32_t(changes.size())+1);
  }
  if(zone) {
    unknownWork=true;
    try {if(!df3d_area::nativeZoneRefresh(*zone))return fail("Native zone refresh unavailable",spent+uint32_t(changes.size())+1);}
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
    if(zone->assigned_units.size()+zone->assigned_items.size()>4096)return fail("Zone assignment list exceeds 4,096 entries");
    if(zone->squad_room_info.size()>256)return fail("Zone assignment list exceeds 256 entries");
    members=zone->assigned_units.size()+zone->assigned_items.size()+zone->squad_room_info.size()+zone->contained_buildings.size();
  }
  if(b->name.size()>512)return fail("Area name exceeds bounded snapshot");
  const size_t cells=size_t(width*height);
  // Seven fixed groups plus one step per 256 scalar/extent/list entries.
  // Reserve a non-visibility reply after any settings vector grows to raw size.
  const uint32_t steps=7+df3d_area::bulkSteps(cells+members+b->name.size())+
      (pile?df3d_area::bulkSteps(cells):0)+
      (visibility?df3d_area::bulkSteps(cells):0);
  if(steps>budget)return fail("Area snapshot exceeds remaining step budget");
  std::optional<std::string> zoneName;
  if(zone) {
    zoneName=df3d_area::nativeZoneName(*zone);
    if(!zoneName)return fail("Native zone name unavailable",steps);
  }
  df3d_area::Revision hash;
  if(zoneName){hash.add(zoneName->size());for(unsigned char c:*zoneName)hash.add(c);}
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
  // Native Paint can retain a zero-cell area until exit. Its allocated bounds
  // remain the redraw target. An empty stockpile needs one revealed coordinate
  // in those bounds, so erasing a hidden cell cannot strand its identity before
  // exit/removal. This never fabricates visible occupied cells. Zones retain
  // their separately scoped whole-bounds visibility policy.
  bool emptyAreaVisible=visibility && (zone || pile) && tiles==0;
  if(emptyAreaVisible) {
    bool anyVisible=false,allVisible=true;
    for(int y=b->y1;y<=b->y2;++y)for(int x=b->x1;x<=b->x2;++x) {
      const auto* block=Maps::getTileBlock(x,y,b->z);
      const bool revealed=block && !block->designation[x&15][y&15].bits.hidden;
      anyVisible|=revealed;allVisible&=revealed;
    }
    emptyAreaVisible=pile?anyVisible:allVisible;
  }
  std::vector<int32_t> gives,takes,givesWorkshops,takesWorkshops;
  const auto links=[&](const auto& source,auto& ids) {
    if(!df3d_area::validStockpileLinkVector(source,b->id))return false;
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
    hash.add(zone->flags.bits.room_collision);
    hash.add(zone->type);hash.add(zone->spec_sub_flag.whole);hash.add(zone->assigned_unit_id);
    hash.add(zone->zone_settings.whole.i1);hash.add(zone->zone_settings.whole.i2);
    hash.add(zone->assigned_units.size());for(auto id:zone->assigned_units)hash.add(id);
    hash.add(zone->assigned_items.size());for(auto id:zone->assigned_items)hash.add(id);
    hash.add(zone->squad_room_info.size());for(const auto* squad:zone->squad_room_info) {
      if(!squad)return fail("Area no longer exists",steps);
      hash.add(squad->squad_id);hash.add(squad->mode.whole);
    }
  }
  int32_t storageLimit=-1;
  if(pile) {
    const auto count=df3d_area::nativeStockpileTileCount(*pile);
    if(count && *count<=32767)storageLimit=*count;
  }
  lua_newtable(L);field(L,"ok",true);field(L,"message","");field(L,"steps",steps);
  field(L,"storage_limit",storageLimit);
  field(L,"overlapping",zone?(zone->flags.bits.room_collision?1:0):-1);
  if(zoneName)field(L,"zone_name",DF2UTF(*zoneName));
  field(L,"reply_steps",pile?7+df3d_area::bulkSteps(32768)+df3d_area::bulkSteps(32768+4096+512+members+settingsReplyGrowth):154+df3d_area::bulkSteps(df::global::world->buildings.other.IN_PLAY.size()));
  field(L,"revision",hash.finish());field(L,"tile_count",tiles);field(L,"visible_count",visibleTiles);
  field(L,"has_visibility",visibility);field(L,"visible",visibleTiles!=0 || emptyAreaVisible);
  field(L,"x",b->x1);field(L,"y",b->y1);field(L,"z",b->z);field(L,"width",width);field(L,"height",height);
  const auto array=[&](const char* key,const auto& values) {
    lua_createtable(L,int(values.size()),0);int index=0;
    for(auto value:values){lua_pushinteger(L,lua_Integer(value));lua_rawseti(L,-2,++index);}lua_setfield(L,-2,key);
  };
  array("extents",extents);if(visibility)array("visible_mask",visible);
  array("gives",gives);array("takes",takes);array("gives_workshops",givesWorkshops);array("takes_workshops",takesWorkshops);
  if(zone){array("assigned_units",zone->assigned_units);array("assigned_items",zone->assigned_items);}
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
std::optional<FarmSnapshot> observeFarmSnapshot(int32_t buildingId,int season) {
    if(season<0 || season>3)return {};
    auto* farm=virtual_cast<df::building_farmplotst>(df::building::find(buildingId));
    auto* tile=farm?Maps::getTileDesignation(farm->centerx,farm->centery,farm->z):nullptr;
    if(!farm || !tile || tile->bits.hidden || !df::global::cur_season || *df::global::cur_season<0 || *df::global::cur_season>3) return {};
    const auto choices=df3d_production::farmChoices(farm,season);
    if(!choices || choices->size()>256) return {};
    const auto header=df3d_production::farmHeader(farm);if(!header)return {};
    FarmSnapshot snapshot;snapshot.buildingId=farm->id;snapshot.selectedSeason=season;
    snapshot.customName=DF2UTF(header->customNameCp437);snapshot.headerName=DF2UTF(header->headerNameCp437);
    snapshot.removing=header->removing;snapshot.removalSuspended=header->suspended;snapshot.removalHasWorker=header->hasWorker;
    snapshot.currentSeason=*df::global::cur_season;
    snapshot.currentFertilization=farm->current_fertilization;snapshot.maxFertilization=farm->max_fertilization;
    snapshot.seasonalFertilization=farm->farm_flags.bits.seasonal_fertilize;
    if(snapshot.currentFertilization<0 || snapshot.maxFertilization<0 || farm->jobs.size()>size_t(INT32_MAX))return {};
    for(const auto* job:farm->jobs)if(job && job->job_type==df::job_type::FertilizeField)++snapshot.pendingFertilization;
    for(int i=0;i<4;++i)snapshot.seasonalCrops.push_back(farm->plant_id[i]);
    for(const auto& row:*choices) {
      const auto* plant=df::plant_raw::find(row.cropId);
      if(!plant || plant->id.empty() || plant->id.size()>128)return {};
      snapshot.choices.push_back({row.cropId,DF2UTF(row.name),row.seedsAvailable,row.currentSeasonWarning,plant->id});
    }
    for(const auto& row:snapshot.choices)
      if(row.id<0 || row.id>32767 || row.name.empty() || row.name.size()>512)return {};
    snapshot.revision=df3d_production::farmRevision(snapshot);
    return snapshot;
}
df::building_actual* contentsBuilding(int32_t id,bool editing=false) {
  auto* building=virtual_cast<df::building_actual>(df::building::find(id));
  if(!building)return nullptr;
  const auto type=building->getType();
  if(type!=df::building_type::FarmPlot && type!=df::building_type::Box &&
     (editing || (type!=df::building_type::Workshop && type!=df::building_type::Furnace)))return nullptr;
  auto* tile=Maps::getTileDesignation(building->centerx,building->centery,building->z);
  return tile&&!tile->bits.hidden?building:nullptr;
}
std::optional<df3d_production::BuildingContentsSnapshot> observeBuildingContents(int32_t id,bool editing=false) {
  return df3d_production::buildingContents(contentsBuilding(id,editing));
}
ItemInspectionAppearance copyInspectionAppearance(const df3d_production::ItemInspectionAppearance& a);
std::optional<BuildingContentsPage> contentsPage(const df3d_production::BuildingContentsSnapshot& snapshot,
                                               uint32_t cursor,uint64_t expected) {
  auto slice=df3d_production::pageBuildingContents(snapshot,cursor,expected,
    [](const std::string& caption){return DF2UTF(caption);});
  if(!slice)return std::nullopt;
  BuildingContentsPage page;page.buildingId=snapshot.buildingId;page.revision=snapshot.revision;
  page.completed=snapshot.completed;page.removing=snapshot.removing;
  page.cursor=slice->cursor;page.total=slice->total;page.nextCursor=slice->nextCursor;
  for(auto& row:slice->rows) {
    df::item_flags flags;flags.whole=row.flags;
    const auto material=DF2UTF(row.materialToken),subtype=DF2UTF(row.subtypeRaw);
    if(material.size()>256 || subtype.size()>128)return std::nullopt;
    page.rows.push_back({row.id,row.role,std::move(row.caption),row.forbid,row.dump,row.melt,row.hidden,
      row.canDump,row.canMelt,bool(flags.bits.in_job),bool(flags.bits.in_building),row.itemType,material,subtype});
    if(row.appearance){const auto& a=*row.appearance;auto color=DF2UTF(a.colorToken);if(color.size()>128)return std::nullopt;
      page.rows.back().appearance=copyInspectionAppearance(a);}
  }
  return page;
}
std::optional<BuildingItemSnapshot> observeFarmItem(int32_t buildingId,int32_t itemId) {
  auto* farm=virtual_cast<df::building_farmplotst>(df::building::find(buildingId));
  auto* tile=farm?Maps::getTileDesignation(farm->centerx,farm->centery,farm->z):nullptr;
  if(!tile||tile->bits.hidden)return std::nullopt;
  df::item* item=nullptr;
  for(auto* held:farm->contained_items)if(held&&held->item&&held->item->id==itemId)item=held->item;
  if(!df3d_production::itemDescriptionDispatch(item))return std::nullopt;
  const auto description=df3d_production::itemDescription(item);
  const auto weight=df3d_production::itemWeightCaption(item);
  const auto holder=df3d_production::itemBuildingHolder(item);
  if(!description||!weight||!holder)return std::nullopt;
  // Observe revision after native lazy cache updates, exactly as the diagnostic.
  const auto contents=df3d_production::buildingContents(farm);if(!contents)return std::nullopt;
  for(size_t index=0;index<contents->rows.size();++index)if(contents->rows[index].id==itemId) {
    auto page=contentsPage(*contents,uint32_t(index),contents->revision);
    if(!page||page->rows.empty())return std::nullopt;
    BuildingItemSnapshot value;value.buildingId=buildingId;value.revision=contents->revision;
    value.completed=contents->completed;value.removing=contents->removing;value.item=std::move(page->rows.front());
    value.weight=DF2UTF(*weight);value.description=DF2UTF(*description);
    if(value.weight.size()>128||value.description.size()>32*1024)return std::nullopt;
    if(holder->id>=0) {
      value.holder=ItemBuildingHolder{holder->id,holder->type,DF2UTF(holder->name)};
      if(value.holder->name.size()>512)return std::nullopt;
    }
    return value;
  }
  return std::nullopt;
}
ItemInspectionAppearance copyInspectionAppearance(const df3d_production::ItemInspectionAppearance& a) {
  ItemInspectionAppearance result{DF2UTF(a.materialToken),DF2UTF(a.subtypeRaw),DF2UTF(a.colorToken),a.stack,a.flags,a.instrumentFamily,a.instrumentPlaced};
  result.floodgateOpen=a.floodgateOpen;result.doorOpen=a.doorOpen;result.doorForbidden=a.doorForbidden;result.doorWear=a.doorWear;result.bucketLiquid=a.bucketLiquid;result.bucketLiquidColor=DF2UTF(a.bucketLiquidColor);result.cageMaterialFamily=a.cageMaterialFamily;result.cageOccupantEntity=a.cageOccupantEntity;result.cageOccupantId=a.cageOccupantId;result.cageSolidColor=DF2UTF(a.cageSolidColor);result.restraintRope=a.restraintRope;result.restraintSolidColor=DF2UTF(a.restraintSolidColor);result.slabEngraving=a.slabEngraving;result.portrait=a.portrait;result.cageOccupant=a.cageOccupant;result.corpseSelector=a.corpseSelector;result.legwearSelector=a.legwearSelector;result.craftSoftMaterial=a.craftSoftMaterial;result.artifactMood=a.artifactMood;result.coffinUnused=a.coffinUnused;if(a.craftGemColor)result.craftGemColor=DF2UTF(*a.craftGemColor);
  if(a.contents){auto& c=result.contents.emplace();c.container=a.contents->container;c.materialInorganic=a.contents->materialInorganic;c.solidColor=DF2UTF(a.contents->solidColor);
    for(const auto& e:a.contents->entries)c.entries.push_back({e.itemType,DF2UTF(e.materialToken),DF2UTF(e.colorToken),e.effectiveArmorLevel,e.metal,e.coal,e.containsPowder,e.rollsSheets,e.protectsFoldedSheets,e.containsWriting,e.liquid,e.subterraneanPlant});}
  return result;
}
std::optional<IndependentItemSnapshot> independentItemSnapshot(const df3d_production::ItemObservation& observed) {
  const auto& item=observed.item;IndependentItemSnapshot value;
  if(observed.ammunitionAssignment){const auto& a=*observed.ammunitionAssignment;value.ammunitionAssignment=ItemAmmunitionAssignment{a.kind,a.squadId,DF2UTF(a.caption)};if(value.ammunitionAssignment->caption.size()>1024)return std::nullopt;}
  if(observed.uses){value.uses.emplace();for(const auto& row:*observed.uses)value.uses->push_back({DF2UTF(row.caption),row.reaction});}
  if(observed.contents){value.contents.emplace();for(const auto& row:*observed.contents){
    ItemSheetContent copy;copy.kind=row.kind;copy.id=row.id;copy.caption=DF2UTF(row.caption);
    if(copy.caption.size()>128*1024)return std::nullopt;
    if(row.item){copy.itemType=row.item->itemType;copy.flags=row.item->flags;copy.canDump=row.item->canDump;copy.canMelt=row.item->canMelt;}
    if(row.appearance)copy.appearance=copyInspectionAppearance(*row.appearance);
    value.contents->push_back(std::move(copy));
  }}
  value.id=item.id;value.revision=observed.revision;value.itemType=item.itemType;value.stockpileCategories=observed.stockpileCategories;
  if(observed.owner){value.owner=ItemOwner{observed.owner->id,DF2UTF(observed.owner->name)};if(value.owner->name.size()>512)return std::nullopt;}
  value.name=DF2UTF(item.caption);value.materialToken=DF2UTF(item.materialToken);value.subtypeRaw=DF2UTF(item.subtypeRaw);
  value.weight=DF2UTF(observed.weight);value.description=DF2UTF(observed.description);
  value.forbid=item.forbid;value.dump=item.dump;value.melt=item.melt;value.hidden=item.hidden;value.canDump=item.canDump;value.canMelt=item.canMelt;
  df::item_flags flags;flags.whole=item.flags;value.inJob=flags.bits.in_job;value.inBuilding=flags.bits.in_building;
  if(observed.appearance){const auto& a=*observed.appearance;value.appearance=copyInspectionAppearance(a);
    const auto& encoded=*value.appearance;if(encoded.materialToken.size()>256||encoded.subtypeRaw.size()>128||encoded.colorToken.size()>128)return std::nullopt;}
  if(observed.buildingHolder)value.holder=ItemBuildingHolder{observed.buildingHolder->id,observed.buildingHolder->type,DF2UTF(observed.buildingHolder->name)};
  if(observed.carrier){const auto& c=*observed.carrier;value.carrier=ItemCarrier{c.kind,c.id,c.itemType,DF2UTF(c.name)};
    if(c.appearance){const auto& a=*c.appearance;value.carrier->appearance=copyInspectionAppearance(a);
      const auto& encoded=*value.carrier->appearance;if(encoded.materialToken.size()>256||encoded.subtypeRaw.size()>128||encoded.colorToken.size()>128)return std::nullopt;}}
  if(observed.stockpile)value.stockpile=ItemBuildingHolder{observed.stockpile->id,observed.stockpile->type,DF2UTF(observed.stockpile->name)};
  if(value.name.size()>128*1024 || value.materialToken.size()>256 || value.subtypeRaw.size()>128 || value.weight.size()>128 || value.description.size()>32*1024 ||
     (value.holder && value.holder->name.size()>512) || (value.stockpile && value.stockpile->name.size()>512) || (value.carrier && value.carrier->name.size()>512))return std::nullopt;
  return value;
}
BridgeWorkOrderInfo copyNativeWorkOrder(const df3d_production::NativeWorkOrderRow& native) {
  BridgeWorkOrderInfo row;
  row.id=native.id;row.workshopId=native.workshopId;row.position=native.position;row.revision=native.revision;
  row.name=DF2UTF(native.caption);row.total=native.total;row.remaining=native.remaining;
  row.frequency=native.frequency;row.validated=native.validated;row.active=native.active;
  row.finishedYear=native.finishedYear;row.finishedTick=native.finishedTick;row.maxWorkshops=native.maxWorkshops;
  row.matType=native.matType;row.matIndex=native.matIndex;row.materialCategory=native.materialCategory;
  row.nativeState=BridgeWorkOrderInfo::NativeState{m::WorkOrderPhase(native.phase),native.validationRequired,native.detailsAvailable,native.workshopName?std::optional<std::string>(DF2UTF(*native.workshopName)):std::nullopt};
  for(size_t i=0;i<native.itemConditions.size();++i) {
    const auto& c=native.itemConditions[i];BridgeWorkOrderCondition value;value.index=uint16_t(i);
    value.compare=int8_t(c.compare_type);value.threshold=c.compare_val;value.itemType=int16_t(c.item_type);
    value.itemSubtype=c.item_subtype;value.matType=c.mat_type;value.matIndex=c.mat_index;
    row.conditions.push_back(std::move(value));
  }
  for(size_t i=0;i<native.orderConditions.size();++i) {
    const auto& c=native.orderConditions[i];BridgeWorkOrderCondition value;value.kind=1;value.index=uint16_t(i);
    value.targetOrder=c.order_id;value.dependency=int8_t(c.condition);value.satisfied=c.flags.bits.satisfied;
    const auto& all=df::global::world->manager_orders.all;
    const auto target=std::find_if(all.begin(),all.end(),[&](const auto* order){return order && order->id==c.order_id;});
    if(target!=all.end()) {
      const auto named=df3d_production::nativeWorkOrderRow(**target,int32_t(target-all.begin()));
      if(named)value.description=DF2UTF(named->caption)+(named->total>0?" ("+std::to_string(named->total)+")":"");
    }
    row.conditions.push_back(std::move(value));
  }
  return row;
}
void run(color_ostream& out) {
  citizenWriteStarted=false;
  const auto retireUncertainCitizenReply=[] {
    if(!citizenWriteStarted)return;
    citizens={};citizens.outcomeUnknown=true;mutated=true;
  };
  areaPaintRetired=nullptr;areaPaintCommitted=false;
  const auto* r = flatbuffers::GetRoot<m::ConstructionRequest>(request.data());

  if(r->work_order() && r->work_order()->filter_choice()>=0) {
    const auto* q=r->work_order();message.clear();status=m::ManagementStatus::Rejected;workOrders={};
    try {
      auto* building=df::building::find(q->workshop_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(q->workshop_id()!=-2 && (!tile || tile->bits.hidden)){publish();return;}
      mutated=true;
      const auto result=df3d_production::selectNativeWorkOrderFilter(q->workshop_id(),q->id(),q->expected_revision(),q->condition_index(),int(q->candidate_kind())-3,q->filter_choice(),q->expected_list_revision());
      using O=df3d_production::WorkshopOrdersOutcome;
      mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
      if(result.outcome==O::Applied && result.row){workOrders.orders.push_back(copyNativeWorkOrder(*result.row));status=m::ManagementStatus::Ok;}
    }catch(...) {workOrders={};status=m::ManagementStatus::Rejected;}
    publish();return;
  }
  if(r->action()==m::ManagementAction::WorkOrderCandidates && r->work_order() && (r->work_order()->workshop_id()==-2 || r->work_order()->workshop_id()>=0)) {
    const auto* q=r->work_order();message.clear();status=m::ManagementStatus::Rejected;workOrders={};
    const bool dependencies=q->condition_kind()==1 && q->candidate_kind()==0;
    const bool extra=q->id()<0 || (dependencies?(q->condition_index()!=-1 || (q->query() && q->query()->size())):
      (q->condition_index()<0 || q->condition_kind() || q->candidate_kind()<3 || q->candidate_kind()>5)) || !q->expected_revision() ||
      q->remaining()!=-1 || q->frequency()!=-1 || q->max_workshops()!=-1 || (q->recipe() && q->recipe()->size()) || q->remove_condition() ||
      q->compare()!=-1 || q->threshold()!=-1 || q->item_type()!=-1 || q->item_subtype()!=-1 || q->mat_type()!=-1 || q->mat_index()!=-1 ||
      q->target_order()!=-1 || q->dependency()!=-1 || q->move() || q->expected_neighbor()!=-1 || (q->traits() && q->traits()->size()) ||
      q->input_index()!=-1 || q->group_type()!=-1 || q->group_subtype()!=-1 || q->group_custom()!=-1 || q->encrust_flags()!=-1 || q->suggestion_index()!=-1;
    if(extra){publish();return;}
    try {
      auto* building=df::building::find(q->workshop_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(!df3d_production::nativeWorkOrderScope(q->workshop_id()) || (q->workshop_id()!=-2 && (!tile || tile->bits.hidden))){publish();return;}
      const auto& all=df::global::world->manager_orders.all;
      const auto found=std::find_if(all.begin(),all.end(),[&](const auto* order){return order && order->id==q->id() && (q->workshop_id()==-2 || order->workshop_id==q->workshop_id());});
      if(found==all.end()){publish();return;}
      const auto observed=df3d_production::nativeWorkOrderRow(**found,int32_t(found-all.begin()));
      if(!observed || observed->revision!=q->expected_revision() || (!dependencies && size_t(q->condition_index())>=observed->itemConditions.size())){publish();return;}
      if(dependencies) {
        const auto catalog=df3d_production::nativeWorkOrderDependencies(**found);
        if(!catalog || q->cursor()>catalog->rows.size() || (q->expected_list_revision() && q->expected_list_revision()!=catalog->revision)){publish();return;}
        workOrders.orders.push_back(copyNativeWorkOrder(*observed));
        size_t conditionCount=observed->itemConditions.size()+observed->orderConditions.size();
        size_t at=q->cursor();
        for(;at<catalog->rows.size() && workOrders.orders.size()<16;++at) {
          const auto& candidate=catalog->rows[at];
          const auto count=candidate.itemConditions.size()+candidate.orderConditions.size();
          if(conditionCount+count>128)break;
          conditionCount+=count;workOrders.orders.push_back(copyNativeWorkOrder(candidate));
        }
        if(at==q->cursor() && at<catalog->rows.size()){workOrders={};publish();return;}
        workOrders.total=uint32_t(catalog->rows.size());workOrders.nextCursor=at<catalog->rows.size()?uint32_t(at):0;
        workOrders.listRevision=int64_t(catalog->revision);status=m::ManagementStatus::Ok;publish();return;
      }
      const int kind=int(q->candidate_kind())-3;
      const auto query=q->query()?UTF2DF(q->query()->str()):std::string{};
      if(query.size()>40){publish();return;}
      const auto catalog=df3d_production::nativeWorkOrderFilterChoices(**found,kind,query);
      if(!catalog){publish();return;}
      const auto revision=df3d_production::nativeWorkOrderFilterRevision(*catalog,kind);
      if(q->expected_list_revision() && q->expected_list_revision()!=revision){publish();return;}
      auto row=copyNativeWorkOrder(*observed);
      const auto& condition=observed->itemConditions[size_t(q->condition_index())];
      const auto caption=df3d_production::nativeWorkOrderConditionCaption(condition);
      if(!caption){publish();return;}
      row.conditions[size_t(q->condition_index())].itemCaption=DF2UTF(*caption);
      uint32_t count=0;
      for(size_t i=0;i<catalog->size();++i) {
        const auto& choice=(*catalog)[i];if(!choice.matches)continue;
        const auto offset=count++;
        if(offset<q->cursor() || offset>=uint64_t(q->cursor())+128)continue;
        const auto name=df3d_production::nativeWorkOrderFilterCaption(choice,kind);
        if(!name || DF2UTF(*name).size()>512){workOrders={};publish();return;}
        workOrders.choices.push_back({int32_t(i),DF2UTF(*name)});
        if(kind==2 && choice.trait && df3d_production::nativeWorkOrderTraitSelected(condition,*choice.trait))row.conditions[size_t(q->condition_index())].traits.push_back(std::to_string(i));
      }
      if(q->cursor()>count){workOrders={};publish();return;}
      workOrders.total=count;workOrders.listRevision=int64_t(revision);
      workOrders.nextCursor=q->cursor()+workOrders.choices.size()<count?uint32_t(q->cursor()+workOrders.choices.size()):0;
      workOrders.orders.push_back(std::move(row));status=m::ManagementStatus::Ok;
    }catch(...) {workOrders={};status=m::ManagementStatus::Rejected;}
    publish();return;
  }
  if(r->action()==m::ManagementAction::WorkOrderCondition && r->work_order() && (r->work_order()->workshop_id()==-2 || r->work_order()->workshop_id()>=0) &&
     r->work_order()->condition_kind()==1 && !r->work_order()->remove_condition()) {
    const auto* q=r->work_order();message.clear();status=m::ManagementStatus::Rejected;workOrders={};
    const bool extra=q->remaining()!=-1 || q->frequency()!=-1 || q->max_workshops()!=-1 || q->cursor() ||
      q->suggestion_index()!=-1 || q->filter_choice()!=-1 || (q->recipe() && q->recipe()->size()) || (q->query() && q->query()->size()) ||
      q->compare()!=-1 || q->threshold()!=-1 || q->item_type()!=-1 || q->candidate_kind() || q->move() || q->expected_neighbor()!=-1 ||
      q->item_subtype()!=-1 || q->mat_type()!=-1 || q->mat_index()!=-1 || (q->traits() && q->traits()->size()) ||
      q->input_index()!=-1 || q->group_type()!=-1 || q->group_subtype()!=-1 || q->group_custom()!=-1 || q->encrust_flags()!=-1;
    if(extra){publish();return;}
    try {
      auto* building=df::building::find(q->workshop_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(q->workshop_id()!=-2 && (!tile || tile->bits.hidden)){publish();return;}
      mutated=true;
      const auto result=df3d_production::setNativeWorkOrderDependency(q->workshop_id(),q->id(),q->expected_revision(),q->condition_index(),q->target_order(),q->dependency(),q->expected_list_revision());
      using O=df3d_production::WorkshopOrdersOutcome;
      mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
      if(result.outcome==O::Applied && result.row){workOrders.orders.push_back(copyNativeWorkOrder(*result.row));status=m::ManagementStatus::Ok;}
    }catch(...) {workOrders={};status=m::ManagementStatus::Rejected;}
    publish();return;
  }
  if(r->action()==m::ManagementAction::WorkOrderCondition && r->work_order() &&
     (r->work_order()->workshop_id()==-2 || r->work_order()->workshop_id()>=0) && (r->work_order()->remove_condition() ||
       (!r->work_order()->condition_kind() && r->work_order()->suggestion_index()<0))) {
    const auto* q=r->work_order();message.clear();status=m::ManagementStatus::Rejected;workOrders={};
    const bool extra=q->remaining()!=-1 || q->frequency()!=-1 || q->max_workshops()!=-1 ||
      q->cursor() || q->expected_list_revision() || q->suggestion_index()!=-1 ||
      (q->recipe() && q->recipe()->size()) || (q->query() && q->query()->size()) ||
      (q->remove_condition()?(q->compare()!=-1 || q->threshold()!=-1):(q->compare()<0 || q->threshold()<0)) || q->item_type()!=-1 || q->target_order()!=-1 || q->dependency()!=-1 ||
      q->candidate_kind() || q->move() || q->expected_neighbor()!=-1 || q->item_subtype()!=-1 ||
      q->mat_type()!=-1 || q->mat_index()!=-1 || (q->traits() && q->traits()->size()) ||
      q->input_index()!=-1 || q->group_type()!=-1 || q->group_subtype()!=-1 || q->group_custom()!=-1 || q->encrust_flags()!=-1;
    if(extra || (!q->remove_condition() && q->condition_index()<0 && (q->compare()!=0 || q->threshold()!=0))){publish();return;}
    try {
      auto* building=df::building::find(q->workshop_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(q->workshop_id()!=-2 && (!tile || tile->bits.hidden)){publish();return;}
      mutated=true;
      const auto result=q->remove_condition()?
        df3d_production::removeNativeWorkOrderCondition(q->workshop_id(),q->id(),q->expected_revision(),q->condition_kind(),q->condition_index(),
          workOrderHolding.data(),workOrderHoldingCount,workOrderHolding.size()):
        q->condition_index()<0?df3d_production::addNativeWorkOrderItemCondition(q->workshop_id(),q->id(),q->expected_revision()):
        df3d_production::setNativeWorkOrderConditionAmount(q->workshop_id(),q->id(),q->expected_revision(),q->condition_index(),q->compare(),q->threshold());
      using O=df3d_production::WorkshopOrdersOutcome;
      mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
      if(result.outcome==O::Applied && result.row){workOrders.orders.push_back(copyNativeWorkOrder(*result.row));status=m::ManagementStatus::Ok;}
    }catch(...) {workOrders={};status=m::ManagementStatus::Rejected;}
    publish();return;
  }
  // Native suggestion identity never falls through to manual-filter Lua.
  if(r->work_order() && r->work_order()->suggestion_index()>=0) {
    const auto* q=r->work_order();message.clear();status=m::ManagementStatus::Rejected;workOrders={};
    try {
      auto* building=df::building::find(q->workshop_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(q->workshop_id()!=-2 && (!tile || tile->bits.hidden)){publish();return;}
      mutated=true;
      const auto result=df3d_production::addNativeWorkOrderItemCondition(q->workshop_id(),q->id(),q->expected_revision(),q->suggestion_index());
      using O=df3d_production::WorkshopOrdersOutcome;
      mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
      if(result.outcome==O::Applied && result.row){workOrders.orders.push_back(copyNativeWorkOrder(*result.row));status=m::ManagementStatus::Ok;}
    }catch(...) {workOrders={};status=m::ManagementStatus::Rejected;}
    publish();return;
  }
  // Details uses independently owned native inputs, never the open native sheet.
  if(r->work_order() && r->work_order()->details()) {
    const auto* q=r->work_order();const auto* d=q->details();
    message.clear();status=m::ManagementStatus::Rejected;workOrders={};
    const bool writing=r->action()==m::ManagementAction::WorkOrderUpdate;
    if(!writing && r->action()!=m::ManagementAction::WorkOrderInspect){publish();return;}
    try {
      auto* building=df::building::find(q->workshop_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(!df3d_production::nativeWorkOrderScope(q->workshop_id()) || (q->workshop_id()!=-2 && (!tile || tile->bits.hidden))){publish();return;}
      const auto& all=df::global::world->manager_orders.all;
      const auto found=std::find_if(all.begin(),all.end(),[&](const auto* value){return value && value->id==q->id();});
      auto* order=found==all.end()?nullptr:*found;
      if(!order || (q->workshop_id()!=-2 && order->workshop_id!=q->workshop_id())){publish();return;}
      if(const auto* a=d->art()) {
        auto observed=df3d_production::nativeWorkOrderDetails(*order);
        if(!observed || q->expected_revision()!=observed->revision || d->option()<0 || size_t(d->option())>=observed->options.size()){publish();return;}
        const auto kind=observed->options[size_t(d->option())].kind;
        if(kind!=1 && kind!=3){publish();return;}
        const auto query=a->query()?UTF2DF(a->query()->str()):std::string{};
        if(const auto* draft=a->draft()) {
          // Name generation and world-image installation have their own write
          // paths. Local draft operations never claim a simulation mutation.
          const auto draftAction=uint8_t(draft->action());
          const bool worldWrite=draftAction==4 || draftAction==5 || (draftAction==6 && draft->name_edit() && uint8_t(draft->name_edit()->mode())>=2);
          if(writing!=worldWrite || (kind==3 && int(order->specdata.improvement)!=0)){publish();return;}
          df3d_production::WorkOrderArtDraftValue value;
          const auto element=[](const m::WorkOrderArtDraftElement& e){return df3d_production::WorkOrderArtDraftElementValue{e.kind(),e.id(),e.secondary(),e.quantity()};};
          const auto relationship=[](const m::WorkOrderArtDraftRelationship& r){return df3d_production::WorkOrderArtDraftRelationshipValue{r.verb(),r.transitive(),r.actor(),r.target()};};
          for(const auto* e:*draft->value()->elements())value.elements.push_back(element(*e));
          for(const auto* r:*draft->value()->relationships())value.relationships.push_back(relationship(*r));
          if(const auto* n=draft->value()->name()) {
            value.name.emplace();auto& name=*value.name;
            name.first_name.assign(reinterpret_cast<const char*>(n->first_name_bytes()->data()),n->first_name_bytes()->size());
            name.nickname.assign(reinterpret_cast<const char*>(n->nickname_bytes()->data()),n->nickname_bytes()->size());
            for(size_t i=0;i<7;++i){name.words[i]=n->words()->Get(i);name.parts_of_speech[i]=df::part_of_speech(n->parts()->Get(i));}
            name.language=n->language();name.type=df::language_name_type(n->type());name.has_name=n->has_name();
          }
          std::optional<df3d_production::WorkOrderArtDraftElementValue> added;
          std::optional<df3d_production::WorkOrderArtDraftRelationshipValue> relation;
          if(draft->element())added=element(*draft->element());if(draft->relationship())relation=relationship(*draft->relationship());
          if(draftAction==5) {
            mutated=true;
            auto result=df3d_production::commitWorkOrderArtDraft(*order,q->expected_revision(),value);
            using O=df3d_production::WorkshopOrdersOutcome;
            mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
            if(result.outcome!=O::Applied || !result.observation){publish();return;}
            workOrders.details=std::move(result.observation);workOrders.detailsId=q->id();
            status=m::ManagementStatus::Ok;publish();return;
          }
          // Generating a name advances DF's RNG. A failed receipt must not replay it.
          if(writing)mutated=true;
          std::optional<df3d_production::WorkOrderArtNameQuery> nameQuery;
          std::optional<df3d_production::WorkOrderArtNameEdit> nameEdit;
          if(const auto* n=draft->name_query())nameQuery=df3d_production::WorkOrderArtNameQuery{n->component(),std::string(reinterpret_cast<const char*>(n->query_bytes()->data()),n->query_bytes()->size()),n->cursor()};
          if(const auto* n=draft->name_edit())nameEdit=df3d_production::WorkOrderArtNameEdit{uint8_t(n->mode()),n->target(),n->displayed(),n->word(),n->part(),std::string(reinterpret_cast<const char*>(n->query_bytes()->data()),n->query_bytes()->size())};
          workOrders.art=df3d_production::nativeWorkOrderArtDraftPage(*order,a->page(),std::move(value),uint8_t(draft->action()),added,relation,draft->delete_index(),query,a->cursor(),a->expected_list_revision(),draft->columns(),nameQuery?&*nameQuery:nullptr,nameEdit?&*nameEdit:nullptr);
          if(!workOrders.art){publish();return;}
          workOrders.details=std::move(observed);workOrders.detailsId=q->id();workOrders.detailsOption=d->option();
          status=m::ManagementStatus::Ok;publish();return;
        }
        if(writing) {
          mutated=true;
          auto result=a->page()==-1?df3d_production::beginWorkOrderArt(*order,q->expected_revision(),d->option()):
            df3d_production::setWorkOrderArtSubject(*order,q->expected_revision(),d->option(),a->page(),a->subject(),a->expected_list_revision(),query);
          using O=df3d_production::WorkshopOrdersOutcome;
          mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
          if(result.outcome!=O::Applied || !result.observation){publish();return;}
          observed=std::move(result.observation);
        }
        if(!writing || a->page()==-1) {
          if(kind==3 && int(order->specdata.improvement)!=0){publish();return;}
          workOrders.art=df3d_production::nativeWorkOrderArtPage(*order,a->page(),query,a->cursor(),a->expected_list_revision(),a->hovered(),a->preview_columns());
          if(!workOrders.art){publish();return;}
          workOrders.detailsOption=d->option();
          if(writing && a->page()==-1) {
            auto draft=df3d_production::WorkOrderArtDraft::create();
            if(!draft || !draft->generateName()){workOrders={};publish();return;}
            workOrders.art->draft.emplace();workOrders.art->draft->name=draft->image().name;
            workOrders.art->draftDescription=std::vector<std::string>{};
          }
        }
        workOrders.details=std::move(observed);workOrders.detailsId=q->id();status=m::ManagementStatus::Ok;
        publish();return;
      }
      auto observed=df3d_production::nativeWorkOrderDetails(*order,d->option(),d->query()?UTF2DF(d->query()->str()):std::string{},d->dye_target(),d->dye_filter_applied());
      if(!observed || (q->expected_revision() && q->expected_revision()!=observed->revision) ||
         (d->expected_choices_revision() && d->expected_choices_revision()!=observed->choicesRevision) || d->cursor()>observed->materials.size()){publish();return;}
      if(writing) {
        // Once the semantic helper starts, exceptions cannot prove no effects.
        mutated=true;
        auto result=df3d_production::setWorkOrderDetailMaterial(*order,q->expected_revision(),d->option(),d->expected_choices_revision(),d->choice(),d->dye_target());
        using O=df3d_production::WorkshopOrdersOutcome;
        mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
        if(result.outcome!=O::Applied || !result.observation){publish();return;}
        observed=std::move(result.observation);
      }
      workOrders.details=std::move(observed);workOrders.detailsId=q->id();
      workOrders.detailsOption=writing?-1:d->option();workOrders.detailsCursor=writing?0:d->cursor();
      status=m::ManagementStatus::Ok;
    }catch(...) {workOrders={};status=m::ManagementStatus::Rejected;}
    publish();return;
  }
  // Conditions inspect is explicit: list refreshes do not rebuild suggestions.
  if(r->work_order() && (r->work_order()->workshop_id()==-2 || r->work_order()->workshop_id()>=0) && r->action()==m::ManagementAction::WorkOrderInspect) {
    const auto* q=r->work_order();message.clear();status=m::ManagementStatus::Rejected;workOrders={};
    const bool extra=q->id()<0 || q->remaining()!=-1 || q->frequency()!=-1 || q->max_workshops()!=-1 ||
      q->expected_revision() || q->cursor() || q->expected_list_revision() ||
      (q->recipe() && q->recipe()->size()) || (q->query() && q->query()->size()) ||
      q->condition_kind() || q->condition_index()!=-1 || q->remove_condition() || q->compare()!=-1 ||
      q->threshold()!=-1 || q->item_type()!=-1 || q->target_order()!=-1 || q->dependency()!=-1 ||
      q->candidate_kind() || q->move() || q->expected_neighbor()!=-1 || q->item_subtype()!=-1 ||
      q->mat_type()!=-1 || q->mat_index()!=-1 || (q->traits() && q->traits()->size()) ||
      q->input_index()!=-1 || q->group_type()!=-1 || q->group_subtype()!=-1 || q->group_custom()!=-1 || q->encrust_flags()!=-1;
    if(extra){publish();return;}
    try {
      auto* building=df::building::find(q->workshop_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(!df3d_production::nativeWorkOrderScope(q->workshop_id()) || (q->workshop_id()!=-2 && (!tile || tile->bits.hidden))){publish();return;}
      const auto& all=df::global::world->manager_orders.all;
      const auto found=std::find_if(all.begin(),all.end(),[&](const auto* order){return order && order->id==q->id() && (q->workshop_id()==-2 || order->workshop_id==q->workshop_id());});
      if(found==all.end()){publish();return;}
      const auto observed=df3d_production::nativeWorkOrderRow(**found,int32_t(found-all.begin()));
      const auto suggestions=df3d_production::nativeWorkOrderSuggestions(**found);
      if(!observed || !suggestions || observed->itemConditions.size()+observed->orderConditions.size()+suggestions->size()>128){publish();return;}
      auto row=copyNativeWorkOrder(*observed);
      for(size_t i=0;i<observed->itemConditions.size();++i) {
        const auto caption=df3d_production::nativeWorkOrderConditionCaption(observed->itemConditions[i]);
        if(!caption){publish();return;}
        row.conditions[i].itemCaption=DF2UTF(*caption);
        if(row.conditions[i].itemCaption->size()>1024){publish();return;}
        const auto satisfied=df3d_production::nativeWorkOrderConditionSatisfied(observed->itemConditions[i]);
        if(!satisfied){publish();return;}
        row.conditions[i].satisfied=*satisfied;
      }
      row.suggestedConditions.emplace();
      for(size_t i=0;i<suggestions->size();++i) {
        const auto& source=(*suggestions)[i];
        const auto caption=df3d_production::nativeWorkOrderConditionCaption(source);
        if(!caption){publish();return;}
        BridgeWorkOrderCondition value;value.index=uint16_t(i);value.itemCaption=DF2UTF(*caption);
        if(value.itemCaption->size()>1024){publish();return;}
        value.compare=int8_t(source.compare_type);value.threshold=source.compare_val;
        value.editable=df3d_production::nativeSuggestionAvailable(**found,source);
        value.itemType=int16_t(source.item_type);value.itemSubtype=source.item_subtype;
        value.matType=source.mat_type;value.matIndex=source.mat_index;
        row.suggestedConditions->push_back(std::move(value));
      }
      workOrders.orders.push_back(std::move(row));status=m::ManagementStatus::Ok;
    }catch(...) {workOrders={};status=m::ManagementStatus::Rejected;}
    publish();return;
  }
  // Global numeric/priority edits use native inline effects on simulation data.
  if(r->action()==m::ManagementAction::WorkOrderUpdate && r->work_order() && r->work_order()->workshop_id()==-2) {
    const auto* q=r->work_order();message.clear();status=m::ManagementStatus::Rejected;workOrders={};
    const bool extra=q->id()<0 || !q->expected_revision() || q->cursor() ||
      (q->recipe() && q->recipe()->size()) || (q->query() && q->query()->size()) ||
      q->condition_kind() || q->condition_index()!=-1 || q->remove_condition() || q->compare()!=-1 ||
      q->threshold()!=-1 || q->item_type()!=-1 || q->target_order()!=-1 || q->dependency()!=-1 ||
      q->candidate_kind() || q->item_subtype()!=-1 || q->mat_type()!=-1 || q->mat_index()!=-1 ||
      (q->traits() && q->traits()->size()) || q->input_index()!=-1 || q->group_type()!=-1 ||
      q->group_subtype()!=-1 || q->group_custom()!=-1 || q->encrust_flags()!=-1;
    if(extra){publish();return;}
    try {
      const auto result=df3d_production::setGlobalOrderFields(q->id(),q->expected_revision(),q->remaining(),q->max_workshops(),q->move(),q->expected_list_revision(),q->expected_neighbor(),q->frequency());
      using O=df3d_production::WorkshopOrdersOutcome;
      mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
      if(result.outcome==O::Applied && result.row) {
        workOrders.orders.push_back(copyNativeWorkOrder(*result.row));status=m::ManagementStatus::Ok;
      }
    }catch(...) {status=m::ManagementStatus::Rejected;}
    publish();return;
  }
  // Rows are native observations, independent of any open DF sheet.
  if(r->work_order() && (r->work_order()->workshop_id()>=0 || (r->work_order()->workshop_id()==-2 && (r->action()==m::ManagementAction::WorkOrderList || r->action()==m::ManagementAction::WorkOrderDelete))) && (r->action()==m::ManagementAction::WorkOrderList || r->action()==m::ManagementAction::WorkOrderUpdate || r->action()==m::ManagementAction::WorkOrderDelete)) {
    const auto* q=r->work_order();message.clear();status=m::ManagementStatus::Rejected;workOrders={};
    const bool deleting=r->action()==m::ManagementAction::WorkOrderDelete;
    const bool editing=deleting || r->action()==m::ManagementAction::WorkOrderUpdate;
    const bool frequencyEdit=!deleting && editing && q->frequency()>=0;
    const bool extra=(editing?(q->id()<0 || (deleting || frequencyEdit?q->remaining()!=-1:(q->remaining()<0 || q->remaining()>9999)) || !q->expected_revision() || q->cursor() || q->expected_list_revision()):
      (q->id()!=-1 || q->remaining()!=-1 || q->expected_revision())) || (frequencyEdit?q->frequency()>4:q->frequency()!=-1) || q->max_workshops()!=-1 || (q->recipe() && q->recipe()->size()) || (q->query() && q->query()->size()) ||
      q->condition_kind() || q->condition_index()!=-1 || q->remove_condition() || q->compare()!=-1 ||
      q->threshold()!=-1 || q->item_type()!=-1 || q->target_order()!=-1 || q->dependency()!=-1 ||
      q->candidate_kind() || q->move() || q->expected_neighbor()!=-1 || q->item_subtype()!=-1 ||
      q->mat_type()!=-1 || q->mat_index()!=-1 || (q->traits() && q->traits()->size()) ||
      q->input_index()!=-1 || q->group_type()!=-1 || q->group_subtype()!=-1 || q->group_custom()!=-1 || q->encrust_flags()!=-1;
    if(extra){publish();return;}
    try {
      auto* building=df::building::find(q->workshop_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(editing) {
        if(q->workshop_id()!=-2 && (!tile || tile->bits.hidden)){publish();return;}
        mutated=true;
        if(deleting) {
          const auto result=df3d_production::removeWorkshopOrder(q->workshop_id(),q->id(),q->expected_revision(),
              workOrderHolding.data(),workOrderHoldingCount,workOrderHolding.size());
          using O=df3d_production::WorkshopOrdersOutcome;
          mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
          if(result.outcome==O::Applied && result.page) {
            workOrders.listRevision=result.page->revision;workOrders.total=result.page->total;
            status=m::ManagementStatus::Ok;
          }
          if(result.outcome==O::Applied && result.profile) {
            workOrders.listRevision=result.profile->revision;workOrders.total=uint32_t(result.profile->orderIds.size());
            status=m::ManagementStatus::Ok;
          }
          publish();return;
        }
        const auto result=df3d_production::setWorkshopOrderFields(q->workshop_id(),q->id(),q->expected_revision(),q->remaining(),q->frequency());
        using O=df3d_production::WorkshopOrdersOutcome;
        mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
        if(result.outcome==O::Applied && result.row) {
          workOrders.orders.push_back(copyNativeWorkOrder(*result.row));status=m::ManagementStatus::Ok;
        }
        publish();return;
      }
      const auto page=q->workshop_id()==-2?df3d_production::nativeGlobalOrderPage(q->cursor(),q->expected_list_revision()):tile && !tile->bits.hidden?
        df3d_production::nativeWorkshopOrderPage(building,q->cursor(),q->expected_list_revision()):std::nullopt;
      if(!page){publish();return;}
      workOrders.nativeState=page->nativeState;
      workOrders.listRevision=page->revision;workOrders.total=page->total;workOrders.nextCursor=page->nextCursor;
      for(const auto& native:page->rows) {
        workOrders.orders.push_back(copyNativeWorkOrder(native));
      }
      status=m::ManagementStatus::Ok;
    }catch(...) {workOrders={};status=m::ManagementStatus::Rejected;}
    publish();return;
  }
  // Order picker uses the existing opaque recipe/catalog transport. Native
  // creation owns its default quantity; no Lua recipe reconstruction is used.
  if(r->work_order() && (r->work_order()->workshop_id()==-2 || r->work_order()->workshop_id()>=0) &&
     (r->action()==m::ManagementAction::WorkOrderCatalog || r->action()==m::ManagementAction::WorkOrderCreate)) {
    const auto* q=r->work_order();const bool creating=r->action()==m::ManagementAction::WorkOrderCreate;const bool global=q->workshop_id()==-2;
    message.clear();status=m::ManagementStatus::Rejected;workOrders={};
    const bool extra=q->id()!=-1 || q->frequency()!=-1 || q->max_workshops()!=-1 ||
      q->condition_kind() || q->condition_index()!=-1 || q->remove_condition() || q->compare()!=-1 ||
      q->threshold()!=-1 || q->item_type()!=-1 || q->target_order()!=-1 || q->dependency()!=-1 ||
      q->candidate_kind() || q->move() || q->expected_neighbor()!=-1 || q->item_subtype()!=-1 ||
      q->mat_type()!=-1 || q->mat_index()!=-1 || (q->traits() && q->traits()->size()) ||
      q->input_index()!=-1 || ((!global || creating) && (q->group_type()!=-1 || q->group_subtype()!=-1 || q->group_custom()!=-1)) ||
      q->encrust_flags()!=-1 || (creating && q->query() && q->query()->size());
    if(extra || (creating?(q->remaining()!=10 || q->cursor() || q->expected_list_revision()):
      (q->remaining()!=-1 || q->expected_revision() || (q->recipe() && q->recipe()->size())))) {publish();return;}
    try {
      auto* building=df::building::find(q->workshop_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(!global && (!tile || tile->bits.hidden)){publish();return;}
      if(!creating) {
        const auto query=q->query()?q->query()->str():std::string{};
        const auto nativeQuery=UTF2DF(query);
        if(nativeQuery.size()>76 || DF2UTF(nativeQuery)!=query){publish();return;}
        const auto catalog=df3d_production::workshopOrderCatalog(building,global);
        if(!catalog ||
           (q->cursor() && q->expected_list_revision()!=catalog->revision) ||
           (q->expected_list_revision() && q->expected_list_revision()!=catalog->revision)){publish();return;}
        // Native3c31a0 normalizes the query and searches the pre-normalized
        // caption with e1990. The existing owned-caption helper calls these
        // same leaves; never construct or borrow its picker context.
        std::vector<size_t> candidates;
        if(global) {
          const auto groups=df3d_production::nativeWorkOrderGroups(catalog->rows);
          if(!groups || groups->size()>128){publish();return;}
          bool selected=false;
          for(const auto& group:*groups) {
            std::optional<std::string> customCode;
            if(group.custom>=0) {
              const auto* raw=df::building_def::find(group.custom);
              if(!raw || raw->code.size()>128){workOrders={};publish();return;}
              customCode=raw->code;
            }
            workOrders.groups.push_back({int16_t(group.type),int16_t(group.subtype),group.custom,DF2UTF(group.name),uint32_t(group.rows.size()),customCode});
            if(group.type==q->group_type() && group.subtype==q->group_subtype() && group.custom==q->group_custom()) {
              candidates=group.rows;selected=true;
            }
          }
          if(!selected){workOrders={};publish();return;}
        } else for(size_t i=0;i<catalog->rows.size();++i)candidates.push_back(i);
        std::vector<size_t> matches;
        for(size_t i:candidates) {
          const auto match=df3d_production::workshopCaptionMatches(catalog->rows[i].name,nativeQuery);
          if(!match){publish();return;}if(*match)matches.push_back(i);
        }
        if(q->cursor()>matches.size()){publish();return;}
        workOrders.listRevision=catalog->revision;workOrders.total=uint32_t(matches.size());
        const size_t end=std::min(matches.size(),size_t(q->cursor())+128);
        for(size_t at=q->cursor();at<end;++at) {
          const size_t i=matches[at];
          const auto& row=catalog->rows[i];
          workOrders.recipes.push_back({std::string(global?"native-global:":"native-workshop:")+std::to_string(catalog->revision)+":"+std::to_string(i),DF2UTF(row.name),{}});
        }
        workOrders.nextCursor=end<matches.size()?uint32_t(end):0;status=m::ManagementStatus::Ok;
      } else {
        const std::string key=q->recipe()?q->recipe()->str():"";
        const std::string prefix=std::string(global?"native-global:":"native-workshop:")+std::to_string(q->expected_revision())+":";
        int32_t choice=-1;
        if(key.compare(0,prefix.size(),prefix)!=0){publish();return;}
        const auto parsed=std::from_chars(key.data()+prefix.size(),key.data()+key.size(),choice);
        if(parsed.ec!=std::errc{} || parsed.ptr!=key.data()+key.size() || choice<0){publish();return;}
        // Mark entry into the effect boundary before invoking it. Any escaping
        // exception is uncertain, and must not become a safe-to-retry rejection.
        mutated=true;
        const auto result=df3d_production::createWorkshopOrder(q->workshop_id(),q->expected_revision(),choice);
        using O=df3d_production::WorkshopOrdersOutcome;
        mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
        if(result.outcome==O::Applied) {
          // A successful create returns the new identity. Subsequent inspection
          // supplies the full order and its own edit receipt.
          if(global) {
            const auto& all=df::global::world->manager_orders.all;
            const auto found=std::find_if(all.begin(),all.end(),[&](const auto* order){return order && order->id==result.orderId;});
            const auto row=found!=all.end()?df3d_production::nativeWorkOrderRow(**found,int32_t(found-all.begin()),true):std::nullopt;
            if(row){workOrders.orders.push_back(copyNativeWorkOrder(*row));status=m::ManagementStatus::Ok;}
            publish();return;
          }
          BridgeWorkOrderInfo row;row.id=result.orderId;row.workshopId=q->workshop_id();
          row.total=10;row.remaining=10;row.revision=result.profile->revision;
          row.name=DF2UTF(result.caption);row.validated=result.validated;
          workOrders.orders.push_back(std::move(row));status=m::ManagementStatus::Ok;
        }
      }
    }catch(...) {workOrders={};status=m::ManagementStatus::Rejected;}
    publish();return;
  }
  if(r->production() && r->production()->workshop_orders()) {
    const auto* q=r->production();const bool editing=r->action()==m::ManagementAction::FarmEdit;
    message.clear();status=m::ManagementStatus::Rejected;production={};
    auto& response=production.workshopOrders.emplace();response.buildingId=q->building_id();
    response.outcome=editing?m::FarmEditOutcome::Rejected:m::FarmEditOutcome::None;
    const auto copy=[&](const df3d_production::WorkshopOrdersProfile& p) {
      response.revision=p.revision;response.managerAvailable=p.managerAvailable;
      response.generalOrderLimit=p.generalOrderLimit;response.orderIds=p.orderIds;
    };
    try {
      auto* building=df::building::find(q->building_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(!tile || tile->bits.hidden){publish();return;}
      if(!editing) {
        if(const auto p=df3d_production::workshopOrdersProfile(building)){copy(*p);status=m::ManagementStatus::Ok;}
      } else {
        const auto result=q->general_order_value()>=0?
          df3d_production::setWorkshopGeneralOrders(q->building_id(),q->expected_revision(),q->general_order_value()):
          df3d_production::stepWorkshopGeneralOrders(q->building_id(),q->expected_revision(),q->general_order_delta());
        using O=df3d_production::WorkshopOrdersOutcome;
        mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
        if(result.outcome==O::Applied && result.profile) {
          copy(*result.profile);response.delta=q->general_order_delta();response.value=q->general_order_value();response.outcome=m::FarmEditOutcome::Completed;status=m::ManagementStatus::Ok;
        } else if(result.outcome==O::Unknown)response.outcome=m::FarmEditOutcome::Unknown;
        else if(result.outcome==O::Stale)response.outcome=m::FarmEditOutcome::Stale;
      }
    }catch(...) {
      response={};response.buildingId=q->building_id();
      response.outcome=editing?(mutated?m::FarmEditOutcome::Unknown:m::FarmEditOutcome::Rejected):m::FarmEditOutcome::None;
      status=m::ManagementStatus::Rejected;
    }
    publish();return;
  }
  if(r->production() && r->production()->workshop_workers()) {
    static df3d_production::WorkshopWorkerSnapshot workers;
    const auto* q=r->production();const bool editing=r->action()==m::ManagementAction::FarmEdit;
    message.clear();status=m::ManagementStatus::Rejected;production={};
    auto& response=production.workshopWorkers.emplace();response.buildingId=q->building_id();
    response.outcome=editing?m::FarmEditOutcome::Rejected:m::FarmEditOutcome::None;
    const auto copyProfile=[&](const df3d_production::WorkshopWorkerProfile& p) {
      response.profileRevision=p.revision;response.permittedWorkers=p.permittedWorkers;
      if(p.assigned){const auto& a=*p.assigned;response.assigned=WorkshopAssignedWorker{a.id,DF2UTF(a.caption),a.specializationVisible,a.canSpecialize,a.specialized};}
    };
    try {
      auto* building=df::building::find(q->building_id());
      auto* tile=building?Maps::getTileDesignation(building->centerx,building->centery,building->z):nullptr;
      if(!tile || tile->bits.hidden){workers.invalidate();publish();return;}
      const bool assignedEdit=editing && q->farm_operation()!=m::FarmOperation::WorkerSelect;
      if(assignedEdit) {
        workers.invalidate();
        const auto result=q->farm_operation()==m::FarmOperation::WorkerRemove?
          df3d_production::removeWorkshopWorker(q->building_id(),q->worker_id(),q->expected_revision()):
          df3d_production::specializeWorkshopWorker(q->building_id(),q->worker_id(),q->expected_revision(),q->worker_value()!=0);
        using O=df3d_production::WorkshopWorkerOutcome;
        mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
        if(result.outcome==O::Applied && result.profile){response.outcome=m::FarmEditOutcome::Unknown;copyProfile(*result.profile);response.unitId=q->worker_id();response.operation=q->farm_operation();response.outcome=m::FarmEditOutcome::Completed;status=m::ManagementStatus::Ok;}
        else if(result.outcome==O::Unknown)response.outcome=m::FarmEditOutcome::Unknown;
        else if(result.outcome==O::Stale)response.outcome=m::FarmEditOutcome::Stale;
        publish();return;
      }
      workers.observe(epoch,q->building_id());
      const auto page=workers.page(epoch,q->building_id(),editing?0:q->cursor(),q->worker_list_revision());
      if(page.status==df3d_area::LocationPageStatus::Ready && page.profile) {
        if(!editing) {
          copyProfile(*page.profile);
          response.revision=page.revision;response.cursor=q->cursor();response.nextCursor=page.nextCursor;response.total=page.total;response.rows=page.rows;
          status=m::ManagementStatus::Ok;
        } else {
          // Native eligibility is rechecked by the action at this same safe point.
          // The current full list revision also rejects retired picker authority.
          workers.invalidate();
          const auto result=df3d_production::selectWorkshopWorker(q->building_id(),q->worker_id(),q->expected_revision());
          using O=df3d_production::WorkshopWorkerOutcome;
          mutated=result.outcome==O::Applied || result.outcome==O::Unknown;
          if(result.outcome==O::Applied && result.profile) {
            response.outcome=m::FarmEditOutcome::Unknown;
            copyProfile(*result.profile);response.unitId=q->worker_id();response.operation=q->farm_operation();
            response.outcome=m::FarmEditOutcome::Completed;status=m::ManagementStatus::Ok;
          } else if(result.outcome==O::Unknown)response.outcome=m::FarmEditOutcome::Unknown;
          else if(result.outcome==O::Stale)response.outcome=m::FarmEditOutcome::Stale;
        }
      } else if(editing && page.status==df3d_area::LocationPageStatus::Stale)response.outcome=m::FarmEditOutcome::Stale;
    } catch(...) {
      response={};response.buildingId=q->building_id();
      response.outcome=editing?(mutated?m::FarmEditOutcome::Unknown:m::FarmEditOutcome::Rejected):m::FarmEditOutcome::None;
      status=m::ManagementStatus::Rejected;workers.invalidate();
    }
    publish();return;
  }
  if(r->production() && r->production()->building_header()) {
    const auto* q=r->production();message.clear();status=m::ManagementStatus::Rejected;production={};
    auto& response=production.buildingHeader.emplace();const bool editing=r->action()==m::ManagementAction::FarmEdit;
    response.outcome=editing?m::FarmEditOutcome::Rejected:m::FarmEditOutcome::None;bool entered=false;
    try {
      const auto target=[&]()->df::building* {
        auto* building=df::building::find(q->building_id());
        if(!building)return nullptr;
        const auto type=building->getType();
        if(type!=df::building_type::Box && (editing || (type!=df::building_type::Workshop && type!=df::building_type::Furnace)))return nullptr;
        auto* tile=Maps::getTileDesignation(building->centerx,building->centery,building->z);
        return tile && !tile->bits.hidden?building:nullptr;
      };
      const auto observe=[&]{return df3d_production::observeBuildingHeader(target());};
      const auto convert=[](const df3d_production::BuildingHeaderObservation& f) {
        return BuildingHeaderSnapshot{f.id,f.type,f.stage,f.maxStage,f.revision,DF2UTF(f.customName),DF2UTF(f.nativeName),DF2UTF(f.headerName),f.removing,f.suspended,f.hasWorker};
      };
      const auto before=observe();
      if(before && !editing){response.snapshot=convert(*before);status=m::ManagementStatus::Ok;}
      else if(before) {
        using A=df3d_production::BuildingHeaderOperation;using O=df3d_production::BuildingHeaderOutcome;
        const bool rename=q->farm_operation()==m::FarmOperation::Rename;
        const auto operation=rename?A::Rename:q->farm_operation()==m::FarmOperation::Remove?A::Remove:A::CancelRemoval;
        const auto text=rename?q->farm_name()->str():std::string{};const auto name=UTF2DF(text);
        if(DF2UTF(name)==text) {
          const auto result=df3d_production::finishBuildingHeaderEdit(*before,q->expected_revision(),operation,name,[&]{
            auto* building=target();if(!building)return false;entered=true;
            if(rename){building->name=name;return true;}
            if(operation==A::CancelRemoval){const bool applied=df3d_production::cancelBuildingRemoval(building);if(!applied)entered=false;return applied;}
            building->queueDestroy();return true;
          },observe);
          mutated=result.mutated;
          if(result.outcome==O::Completed) {
            response.outcome=m::FarmEditOutcome::Unknown;response.snapshot=convert(*result.receipt);
            response.operation=q->farm_operation();response.outcome=m::FarmEditOutcome::Completed;status=m::ManagementStatus::Ok;
          } else if(result.outcome==O::Stale)response.outcome=m::FarmEditOutcome::Stale;
          else if(result.outcome==O::Unknown)response.outcome=m::FarmEditOutcome::Unknown;
        }
      }
    }catch(...) {
      response.snapshot.reset();response.operation=m::FarmOperation::Crop;status=m::ManagementStatus::Rejected;
      if(entered || response.outcome==m::FarmEditOutcome::Unknown)response.outcome=m::FarmEditOutcome::Unknown;
    }
    publish();return;
  }
  if(r->production() && r->production()->independent_item()) {
    const auto* q=r->production();message.clear();status=m::ManagementStatus::Rejected;production={};
    auto& response=production.independentItem.emplace();
    const bool editing=r->action()==m::ManagementAction::FarmEdit;
    response.outcome=editing?m::FarmEditOutcome::Rejected:m::FarmEditOutcome::None;
    bool entered=false;
    try {
      const auto observe=[&]{return df3d_production::observeItem(df::item::find(q->item_id()));};
      auto before=observe();
      if(before && !editing) {
        response.snapshot=independentItemSnapshot(*before);if(response.snapshot)status=m::ManagementStatus::Ok;
      } else if(before) {
        using A=df3d_production::BuildingItemAction;
        const auto operation=q->farm_operation()==m::FarmOperation::ItemForbid?A::Forbid:q->farm_operation()==m::FarmOperation::ItemDump?A::Dump:
          q->farm_operation()==m::FarmOperation::ItemMelt?A::Melt:A::Hidden;
        const int32_t target=q->contents_item_id()>=0?q->contents_item_id():q->item_id();
        const auto result=df3d_production::finishItemEdit(*before,q->expected_revision(),operation,q->item_value()!=0,[&]{
          entered=true;const bool applied=df3d_production::setBuildingItemFlag(df::item::find(target),operation,q->item_value()!=0);
          if(!applied)entered=false;return applied;
        },observe,q->contents_item_id());
        using O=df3d_production::FarmEditOutcome;
        if(result.outcome==O::Completed) {
          response.outcome=m::FarmEditOutcome::Unknown;
          response.snapshot=independentItemSnapshot(*result.receipt);
          if(response.snapshot) {
            response.edit=BuildingItemReceipt{target,q->farm_operation(),q->item_value()};
            response.outcome=m::FarmEditOutcome::Completed;status=m::ManagementStatus::Ok;
          }
        } else if(result.outcome==O::Stale)response.outcome=m::FarmEditOutcome::Stale;
        else if(result.outcome==O::Unknown)response.outcome=m::FarmEditOutcome::Unknown;
      }
    }catch(...) {
      response.snapshot.reset();response.edit.reset();status=m::ManagementStatus::Rejected;
      if(entered || response.outcome==m::FarmEditOutcome::Unknown)response.outcome=m::FarmEditOutcome::Unknown;
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::FarmEdit && r->production() &&
     r->production()->farm_operation()>=m::FarmOperation::ItemForbid) {
    message.clear();status=m::ManagementStatus::Rejected;production={};
    production.farmEditOutcome=m::FarmEditOutcome::Rejected;
    const auto* q=r->production();bool entered=false;
    try {
      using A=df3d_production::BuildingItemAction;A action;
      switch(q->farm_operation()) {
      case m::FarmOperation::ItemForbid:action=A::Forbid;break;
      case m::FarmOperation::ItemDump:action=A::Dump;break;
      case m::FarmOperation::ItemMelt:action=A::Melt;break;
      case m::FarmOperation::ItemHidden:action=A::Hidden;break;
      default:publish();return;
      }
      const auto observe=[&]{return observeBuildingContents(q->building_id(),true);};
      const auto before=observe();
      if(before) {
        auto edit=df3d_production::finishBuildingItemEdit(*before,q->expected_revision(),q->item_id(),action,q->item_value()!=0,[&] {
          auto* building=contentsBuilding(q->building_id(),true);
          if(!building)return false;
          for(auto* held:building->contained_items)if(held&&held->item&&held->item->id==q->item_id()) {
            entered=true;return df3d_production::setBuildingItemFlag(held->item,action,q->item_value()!=0);
          }
          return false;
        },observe,contentsBuilding(q->building_id())->getType()==df::building_type::Box);
        mutated=edit.mutated;
        using O=df3d_production::FarmEditOutcome;
        if(edit.outcome==O::Completed) {
          // Conversion/allocation can still fail after native effects. Until
          // the selected item is in a bounded fresh page, grant no authority.
          production.farmEditOutcome=m::FarmEditOutcome::Unknown;
          const auto& receipt=*edit.receipt;
          const auto item=std::find_if(receipt.rows.begin(),receipt.rows.end(),[&](const auto& row){return row.id==q->item_id();});
          const auto index=static_cast<size_t>(item-receipt.rows.begin());
          auto page=index<=UINT32_MAX?contentsPage(receipt,static_cast<uint32_t>(index),receipt.revision):std::nullopt;
          if(page) {
            production.contents=std::move(page);production.selectedBuilding=q->building_id();
            production.contentsEdit=BuildingItemReceipt{q->item_id(),q->farm_operation(),q->item_value()};
            production.farmEditOutcome=m::FarmEditOutcome::Completed;status=m::ManagementStatus::Ok;
          }
        } else if(edit.outcome==O::Stale)production.farmEditOutcome=m::FarmEditOutcome::Stale;
        else if(edit.outcome==O::Unknown)production.farmEditOutcome=m::FarmEditOutcome::Unknown;
      }
    }catch(...) {
      production.contents.reset();production.contentsEdit.reset();status=m::ManagementStatus::Rejected;
      if(entered||production.farmEditOutcome==m::FarmEditOutcome::Unknown)production.farmEditOutcome=m::FarmEditOutcome::Unknown;
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::FarmEdit) {
    message.clear();status=m::ManagementStatus::Rejected;production={};
    production.farmEditOutcome=m::FarmEditOutcome::Rejected;
    const auto* q=r->production();
    if(q) {
      const auto observe=[&]{return observeFarmSnapshot(q->building_id(),q->season());};
      auto before=observe();
      auto* farm=virtual_cast<df::building_farmplotst>(df::building::find(q->building_id()));
      const bool removal=q->farm_operation()==m::FarmOperation::Remove || q->farm_operation()==m::FarmOperation::CancelRemoval;
      if(before && farm && (!before->removing || removal) && farm->getBuildStage()==farm->getMaxBuildStage()) {
        const auto valid=[](const FarmSnapshot& value){return value.revision>0 && value.revision<=INT64_MAX &&
            value.currentFertilization>=0 && value.maxFertilization>=0 && value.pendingFertilization>=0 &&
            value.seasonalCrops.size()==4 && std::all_of(value.seasonalCrops.begin(),value.seasonalCrops.end(),
              [](int32_t crop){return crop>=-1 && crop<=32767;});};
        auto result=removal?
          df3d_production::finishFarmRemoval(*before,q->expected_revision(),q->farm_operation()==m::FarmOperation::Remove,
            [&]{
              if(!df3d_production::farmFunctions())return false;
              if(q->farm_operation()==m::FarmOperation::CancelRemoval)return df3d_production::cancelFarmRemoval(farm);
              farm->queueDestroy();return true;
            },observe,valid):
          q->farm_operation()==m::FarmOperation::Rename?
          df3d_production::finishFarmRename(*before,q->expected_revision(),q->farm_name()->str(),
            [](const std::string& text)->std::optional<std::string> {
              auto bytes=UTF2DF(text);if(DF2UTF(bytes)!=text)return {};return bytes;
            },[&](const std::string& bytes){farm->name=bytes;return true;},observe,valid):
          q->farm_operation()==m::FarmOperation::Crop?
          df3d_production::finishFarmEdit(*before,q->expected_revision(),q->crop_id(),
            [&]{return df3d_production::setFarmCrop(farm,q->season(),q->crop_id());},observe,valid):
          df3d_production::finishFarmFertilization(*before,q->expected_revision(),q->seasonal_fertilization(),
            [&]{return q->farm_operation()==m::FarmOperation::FertilizationToggle?
              df3d_production::toggleFarmFertilization(farm):
              df3d_production::setFarmSeasonalFertilization(farm,q->seasonal_fertilization()!=0);},observe,valid);
        mutated=result.mutated;
        switch(result.outcome) {
          case df3d_production::FarmEditOutcome::Completed:
            production.farmEditOutcome=m::FarmEditOutcome::Completed;
            production.selectedBuilding=q->building_id();production.farm=std::move(result.receipt);
            status=m::ManagementStatus::Ok;break;
          case df3d_production::FarmEditOutcome::Stale:production.farmEditOutcome=m::FarmEditOutcome::Stale;break;
          case df3d_production::FarmEditOutcome::Unknown:production.farmEditOutcome=m::FarmEditOutcome::Unknown;break;
          case df3d_production::FarmEditOutcome::Rejected:break;
        }
      }
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::ProductionInspect && r->production() && r->production()->locate_item()) {
    message.clear();status=m::ManagementStatus::Rejected;production={};
    const auto id=r->production()->item_id();
    const auto pos=df3d_production::itemFollowPosition(df::item::find(id));
    if(pos && pos->isValid() && pos->x>=0 && pos->y>=0 && pos->z>=0) {
      production.itemPosition=ItemPosition{id,pos->x,pos->y,pos->z};status=m::ManagementStatus::Ok;
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::ProductionInspect && r->production() && r->production()->contents()) {
    message.clear();status=m::ManagementStatus::Rejected;production={};
    const auto* q=r->production();
    auto snapshot=observeBuildingContents(q->building_id());
    auto page=snapshot?contentsPage(*snapshot,q->cursor(),q->expected_revision()):std::nullopt;
    if(page) {
      production.selectedBuilding=page->buildingId;production.contents=std::move(page);status=m::ManagementStatus::Ok;
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::ProductionInspect && r->production() && r->production()->item_id()>=0) {
    message.clear();status=m::ManagementStatus::Rejected;production={};
    const auto* q=r->production();auto snapshot=observeFarmItem(q->building_id(),q->item_id());
    if(snapshot) {
      production.selectedBuilding=snapshot->buildingId;production.item=std::move(snapshot);status=m::ManagementStatus::Ok;
    }
    publish();return;
  }
  // Explicit-season reads use the native contract; the default remains legacy.
  if(r->action()==m::ManagementAction::ProductionInspect && r->production() && r->production()->season()>=0) {
    message.clear();status=m::ManagementStatus::Rejected;production={};
    auto snapshot=observeFarmSnapshot(r->production()->building_id(),r->production()->season());
    if(snapshot) {
      production.selectedBuilding=snapshot->buildingId;production.farm=std::move(snapshot);
      status=m::ManagementStatus::Ok;
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::AgreementInspect && r->agreement() && r->agreement()->tracker()) {
    message.clear();status=m::ManagementStatus::Rejected;agreements={};
    auto facts=df3d_area::observeNativeContinuingAgreementDetails(r->agreement()->id());
    if(facts) {
      auto& row=facts->agreement;agreements.tracker=true;
      agreements.trackerRows.push_back({row.agreementId,row.subjectId,row.entityId,row.entityType,row.tier,row.profession,row.year,row.yearTick,std::move(row.heading),std::move(row.applicant),std::move(row.date)});
      agreements.trackerDetails=ContinuingAgreementDetails{facts->requiredValue,facts->matchingLocations,facts->locationId,facts->locationValue,facts->locationTier,facts->siteAvailable,facts->tierMet,std::move(facts->locationName)};
      status=m::ManagementStatus::Ok;
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::AgreementList && r->agreement() && r->agreement()->tracker()) {
    message.clear();status=m::ManagementStatus::Rejected;agreements={};
    auto rows=df3d_area::observeNativeContinuingAgreements();size_t budget=0;
    if(rows)for(const auto& row:*rows)budget+=160+row.heading.size()+row.applicant.size()+row.date.size();
    if(rows && budget<=224*1024) {
      agreements.tracker=true;
      for(auto& row:*rows)agreements.trackerRows.push_back({row.agreementId,row.subjectId,row.entityId,row.entityType,row.tier,row.profession,row.year,row.yearTick,std::move(row.heading),std::move(row.applicant),std::move(row.date)});
      status=m::ManagementStatus::Ok;
    }
    publish();return;
  }
  static df3d_area::LocationReligiousCandidateSnapshot religiousSnapshot;
  if(r->area() && r->area()->operation()==m::AreaOperation::LocationStaffAssignmentsRead) {
    const auto& a=*r->area();areaPage.operation=a.operation();message.clear();status=m::ManagementStatus::Rejected;
    const bool occupation=a.occupation_id()>=0;
    const auto source=occupation?df3d_area::LocationStaffSource::Occupation:df3d_area::LocationStaffSource::ReligiousPosition;
    auto receipt=df3d_area::observeNativeLocationStaffAssignments(a.location_site_id(),a.location_id(),source,
        a.religious_entity_id(),occupation?a.occupation_id():a.religious_assignment_id(),a.unit_id());
    if(receipt){areaPage.staffAssignments=std::move(receipt);status=m::ManagementStatus::Ok;}
    publish();return;
  }
  if(r->area() && (r->area()->operation()==m::AreaOperation::LocationSpecializationRead ||
      r->area()->operation()==m::AreaOperation::LocationSpecializationSet)) {
    const auto& a=*r->area();areaPage.operation=a.operation();message.clear();status=m::ManagementStatus::Rejected;
    const bool apply=a.operation()==m::AreaOperation::LocationSpecializationSet;
    if(apply)areaPage.locationEditOutcome=m::LocationEditOutcome::Rejected;
    const bool occupation=a.occupation_id()>=0;
    const auto source=occupation?df3d_area::LocationStaffSource::Occupation:df3d_area::LocationStaffSource::ReligiousPosition;
    const int32_t rowId=occupation?a.occupation_id():a.religious_assignment_id();
    const auto observe=[&] {return df3d_area::observeNativeLocationStaffSpecialization(
        a.location_site_id(),a.location_id(),source,a.religious_entity_id(),rowId,a.unit_id());};
    auto receipt=observe();
    if(receipt && apply && receipt->revision!=a.expected_revision()) {
      receipt.reset();areaPage.locationEditOutcome=m::LocationEditOutcome::Stale;
    }
    if(receipt && apply) {
      mutated=true;areaPage.locationEditOutcome=m::LocationEditOutcome::Unknown;
      try {
        const auto result=df3d_area::setNativeLocationStaffSpecialization(a.location_site_id(),a.location_id(),source,
            a.religious_entity_id(),rowId,a.unit_id(),a.expected_revision(),a.value()!=0);
        receipt.reset();
        if(result==df3d_area::LocationStaffEditOutcome::Applied) {
          receipt=observe();
          if(receipt && receipt->specialized==(a.value()!=0))areaPage.locationEditOutcome=m::LocationEditOutcome::Completed;
          else receipt.reset();
        } else if(result!=df3d_area::LocationStaffEditOutcome::Unknown) {
          mutated=false;areaPage.locationEditOutcome=result==df3d_area::LocationStaffEditOutcome::Stale?
              m::LocationEditOutcome::Stale:m::LocationEditOutcome::Rejected;
        }
      } catch(...) {receipt.reset();}
    }
    if(receipt){areaPage.specialization=std::move(receipt);status=m::ManagementStatus::Ok;}
    publish();return;
  }
  if(r->area() && r->area()->operation()>=m::AreaOperation::LocationReligiousCandidates &&
      r->area()->operation()<=m::AreaOperation::LocationReligiousAssign) {
    const auto& a=*r->area();areaPage.operation=a.operation();message.clear();status=m::ManagementStatus::Rejected;
    const bool listing=a.operation()==m::AreaOperation::LocationReligiousCandidates;
    const bool apply=a.operation()==m::AreaOperation::LocationReligiousAssign;
    if(apply)areaPage.locationEditOutcome=m::LocationEditOutcome::Rejected;
    const df3d_area::LocationReligiousStaffTarget target{a.location_site_id(),a.location_id(),a.religious_entity_id(),a.religious_assignment_id()};
    const auto observeTarget=[&] {return df3d_area::observeNativeLocationReligiousStaff(target.siteId,target.locationId,target.entityId,target.assignmentId);};
    auto holder=observeTarget();
    if(holder && !publishableLocationReligiousStaff(*holder))holder.reset();
    auto facts=holder?df3d_area::observeNativeReligiousCandidates(target.siteId,target.locationId,target.entityId,target.assignmentId):std::nullopt;
    const bool member=facts && std::any_of(facts->rows.begin(),facts->rows.end(),[&](const auto& row){return row.unitId==a.unit_id();});
    religiousSnapshot.observe(epoch,target,holder,std::move(facts));
    auto page=religiousSnapshot.page(epoch,target,listing?a.cursor():0,a.expected_list_revision());
    if(page.status==df3d_area::LocationPageStatus::Stale ||
        (!listing && holder && holder->holderId!=a.religious_holder_id())) {
      if(apply)areaPage.locationEditOutcome=m::LocationEditOutcome::Stale;
      publish();return;
    }
    if(page.status!=df3d_area::LocationPageStatus::Ready){publish();return;}
    if(listing) {
      size_t bytes=256;bool bounded=page.rows.size()<=128;
      for(const auto& row:page.rows) {
        if(row.name.size()>2048 || row.baseName.size()>2048 || row.professionName.size()>2048 ||
            row.nameSortKey.size()>2048 || row.professionSortKey.size()>2048 || row.skills.size()>10){bounded=false;break;}
        bytes+=128+row.name.size()+row.baseName.size()+row.professionName.size()+row.nameSortKey.size()+row.professionSortKey.size()+48*row.skills.size();
      }
      if(bounded && bytes<=224*1024) {
        areaPage.locationCursor=a.cursor();areaPage.religiousCandidates=std::move(page);status=m::ManagementStatus::Ok;
      }
      publish();return;
    }
    if(!member){publish();return;}
    const auto selected=df3d_area::observeNativeReligiousAssignment(target.siteId,target.locationId,target.entityId,target.assignmentId,a.unit_id());
    if(!selected || !selected->eligible || !publishableLocationReligiousStaff(selected->target) ||
        selected->target.revision!=page.target.revision){publish();return;}
    if(!apply) {
      areaPage.religiousAssignment=*selected;areaPage.religiousListRevision=page.revision;status=m::ManagementStatus::Ok;
      publish();return;
    }
    if(selected->revision!=a.expected_revision()) {
      areaPage.locationEditOutcome=m::LocationEditOutcome::Stale;publish();return;
    }
    // Retire list ownership before entering a mutating native routine. Neither
    // an uncertain result nor a failed post-effect refresh permits replay.
    const auto result=df3d_area::finishReligiousAssignment(religiousSnapshot,*selected,[&] {
      return df3d_area::assignNativeLocationReligiousStaff(target.siteId,target.locationId,target.entityId,
          target.assignmentId,a.unit_id(),a.religious_holder_id(),a.expected_revision());
    },observeTarget,publishableLocationReligiousStaff);
    mutated=result.mutated;areaPage.locationEditOutcome=m::LocationEditOutcome::Unknown;
    if(result.outcome==df3d_area::LocationStaffEditOutcome::Applied) {
      areaPage.locationReligiousStaff=result.receipt;areaPage.locationEditOutcome=m::LocationEditOutcome::Completed;status=m::ManagementStatus::Ok;
    } else if(!result.mutated) {
      areaPage.locationEditOutcome=result.outcome==df3d_area::LocationStaffEditOutcome::Stale?m::LocationEditOutcome::Stale:m::LocationEditOutcome::Rejected;
    }
    publish();return;
  }
  if(r->area() && (r->area()->operation()==m::AreaOperation::LocationReligiousStaffRead || r->area()->operation()==m::AreaOperation::LocationReligiousStaffRemove)) {
    const auto& a=*r->area();areaPage.operation=a.operation();message.clear();status=m::ManagementStatus::Rejected;
    const bool apply=a.operation()==m::AreaOperation::LocationReligiousStaffRemove;
    if(apply)areaPage.locationEditOutcome=m::LocationEditOutcome::Rejected;
    const auto observe=[&] {return df3d_area::observeNativeLocationReligiousStaff(a.location_site_id(),a.location_id(),a.religious_entity_id(),a.religious_assignment_id());};
    auto receipt=observe();
    if(receipt && !publishableLocationReligiousStaff(*receipt))receipt.reset();
    if(receipt && apply && receipt->revision!=a.expected_revision()) {
      receipt.reset();areaPage.locationEditOutcome=m::LocationEditOutcome::Stale;
    }
    if(receipt && apply) {
      mutated=true;areaPage.locationEditOutcome=m::LocationEditOutcome::Unknown;
      try {
        const auto result=df3d_area::removeNativeLocationReligiousStaff(a.location_site_id(),a.location_id(),
            a.religious_entity_id(),a.religious_assignment_id(),a.religious_holder_id(),a.expected_revision());
        receipt.reset();
        if(result==df3d_area::LocationStaffEditOutcome::Applied) {
          receipt=observe();
          if(receipt && publishableLocationReligiousStaff(*receipt) && !receipt->removable)
            areaPage.locationEditOutcome=m::LocationEditOutcome::Completed;
          else receipt.reset();
        } else if(result!=df3d_area::LocationStaffEditOutcome::Unknown) {
          mutated=false;areaPage.locationEditOutcome=result==df3d_area::LocationStaffEditOutcome::Stale?
              m::LocationEditOutcome::Stale:m::LocationEditOutcome::Rejected;
        }
      } catch(...) {receipt.reset();}
    }
    if(receipt){areaPage.locationReligiousStaff=std::move(receipt);status=m::ManagementStatus::Ok;}
    publish();return;
  }
  if(r->area() && (r->area()->operation()==m::AreaOperation::LocationRecognitionRead || r->area()->operation()==m::AreaOperation::LocationRecognize)) {
    const auto& a=*r->area();areaPage.operation=a.operation();message.clear();status=m::ManagementStatus::Rejected;
    const bool apply=a.operation()==m::AreaOperation::LocationRecognize;
    if(apply)areaPage.locationEditOutcome=m::LocationEditOutcome::Rejected;
    auto receipt=df3d_area::observeNativeLocationRecognitionReceipt(a.location_site_id(),a.location_id());
    if(receipt && !publishableLocationRecognition(*receipt))receipt.reset();
    if(receipt && apply && receipt->revision!=a.expected_revision()) {
      receipt.reset();areaPage.locationEditOutcome=m::LocationEditOutcome::Stale;
    }
    if(receipt && apply) {
      auto result=df3d_area::finishLocationRecognition(*receipt,[&] {
        return df3d_area::recognizeNativeLocation(a.location_site_id(),a.location_id(),a.expected_revision());
      },[&] {
        return df3d_area::observeNativeLocationRecognitionReceipt(a.location_site_id(),a.location_id());
      },publishableLocationRecognition);
      mutated=result.mutated;receipt=std::move(result.receipt);
      areaPage.locationEditOutcome=result.outcome==df3d_area::LocationRecognitionOutcome::Applied?m::LocationEditOutcome::Completed:
          result.outcome==df3d_area::LocationRecognitionOutcome::Unknown?m::LocationEditOutcome::Unknown:
          result.outcome==df3d_area::LocationRecognitionOutcome::Stale?m::LocationEditOutcome::Stale:m::LocationEditOutcome::Rejected;
    }
    if(receipt){areaPage.locationRecognition=std::move(receipt);status=m::ManagementStatus::Ok;}
    publish();return;
  }
  if(r->area() && r->area()->operation()>=m::AreaOperation::LocationNameRead && r->area()->operation()<=m::AreaOperation::LocationNameEdit) {
    const auto& a=*r->area();areaPage.operation=a.operation();message.clear();status=m::ManagementStatus::Rejected;
    auto snapshot=df3d_area::observeNativeLocationName(a.location_site_id(),a.location_id());
    if(snapshot && !publishableLocationName(*snapshot))snapshot.reset();
    const bool edit=a.operation()==m::AreaOperation::LocationNameEdit;
    if(edit)areaPage.locationEditOutcome=m::LocationEditOutcome::Rejected;
    if(snapshot && a.operation()!=m::AreaOperation::LocationNameRead && df3d_area::locationNameRevision(*snapshot)!=a.expected_revision()) {
      if(edit)areaPage.locationEditOutcome=m::LocationEditOutcome::Stale;
      snapshot.reset();
    }
    if(snapshot && edit) {
      const auto& e=*a.name_edit();const std::string query(e.query_bytes()->begin(),e.query_bytes()->end());
      mutated=true;areaPage.locationEditOutcome=m::LocationEditOutcome::Unknown;
      try {
        const auto result=df3d_area::editNativeLocationName(a.location_site_id(),a.location_id(),a.expected_revision(),
            static_cast<df3d_area::LocationNameEdit>(e.mode()),e.target(),e.displayed(),e.word(),e.part(),query);
        if(result==df3d_area::LocationAccessOutcome::Completed) {
          snapshot=df3d_area::observeNativeLocationName(a.location_site_id(),a.location_id());
          if(snapshot && publishableLocationName(*snapshot))areaPage.locationEditOutcome=m::LocationEditOutcome::Completed;
          else snapshot.reset();
        } else {
          mutated=false;snapshot.reset();areaPage.locationEditOutcome=result==df3d_area::LocationAccessOutcome::Stale?m::LocationEditOutcome::Stale:m::LocationEditOutcome::Rejected;
        }
      } catch(...) {snapshot.reset();}
    }
    if(snapshot && a.operation()==m::AreaOperation::LocationNameChoices) {
      const auto& q=*a.name_query();const std::string query(q.query_bytes()->begin(),q.query_bytes()->end());
      auto choices=df3d_area::observeNativeLocationNameWords(q.component(),query,snapshot->name.language);
      if(choices && choices->size()<=UINT32_MAX && q.cursor()<=choices->size()) {
        NativeLocationNamePage page;page.snapshot=*snapshot;page.component=q.component();page.query=query;
        page.cursor=q.cursor();page.total=uint32_t(choices->size());
        uint64_t bytes=512+query.size()+snapshot->name.firstNameCp437.size()+snapshot->name.nicknameCp437.size()+snapshot->nativeHeader.size()+snapshot->englishHeader.size();
        for(size_t i=q.cursor();i<choices->size() && page.choices.size()<m::kLocationNamePageRows;++i) {
          const auto size=64+(*choices)[i].english.size()+(*choices)[i].translated.size();
          if(bytes+size>m::kLocationNamePageBytes)break;
          bytes+=size;page.choices.push_back(std::move((*choices)[i]));
        }
        const auto end=uint32_t(page.cursor+page.choices.size());page.truncated=end<page.total;page.next=page.truncated?end:0;
        if(!page.truncated || !page.choices.empty()){areaPage.locationNamePage=std::move(page);status=m::ManagementStatus::Ok;}
      }
    } else if(snapshot) {areaPage.locationName=std::move(snapshot);status=m::ManagementStatus::Ok;}
    publish();return;
  }
  if(r->action()==m::ManagementAction::ResidentsSpecialize) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& query=*r->residents_specialization();
    residentsSpecialization.emplace();auto& result=*residentsSpecialization;
    result.id=query.unit_id();result.onlyAssigned=query.only_assigned();
    const auto outcome=df3d_residents::setSpecialization(result.id,query.expected_revision(),result.onlyAssigned);
    using O=df3d_residents::SpecializationOutcome;
    switch(outcome) {
      case O::Applied:result.outcome=m::ResidentsSpecializationOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;break;
      case O::Stale:result.outcome=m::ResidentsSpecializationOutcome::Stale;break;
      case O::Unavailable:result.outcome=m::ResidentsSpecializationOutcome::Unavailable;break;
      case O::Unknown:result.outcome=m::ResidentsSpecializationOutcome::Unknown;mutated=true;break;
      default:break;
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::JobSettingsApply) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& q=*r->job_settings_edit();
    jobSettingsEdit=JobSettingsEditResult{q.job_id(),q.building_id(),q.unit_id(),m::JobSettingsEditOutcome::Stale};
    try {
      df::job* source=nullptr;
      if(q.unit_id()>=0) {
        const auto eligible=df3d_residents::orderedResidents(0,false);auto* unit=df::unit::find(q.unit_id());
        if(eligible && unit && std::find(eligible->begin(),eligible->end(),q.unit_id())!=eligible->end() &&
           unit->job.current_job && unit->job.current_job->id==q.job_id())source=unit->job.current_job;
      } else if(auto* holder=df::building::find(q.building_id())) {
        for(auto* job:holder->jobs)if(job && job->id==q.job_id()){source=job;break;}
      }
      if(source) {
        if(q.art()){processJobDraft(*source,q.unit_id(),q.building_id(),q.option(),q.expected_revision(),*q.art(),true);publish();return;}
        const auto outcome=q.art_page()==-2?
          df3d_production::applyJobSetting(*source,{q.job_id(),q.building_id()},q.expected_revision(),q.option(),q.expected_choices_revision(),q.choice()):
          q.art_page()==-1?df3d_production::beginJobArt(*source,{q.job_id(),q.building_id()},q.expected_revision(),q.option(),q.expected_choices_revision()):
          df3d_production::applyJobArtSubject(*source,{q.job_id(),q.building_id()},q.expected_revision(),q.option(),q.art_page(),q.choice(),q.expected_choices_revision(),q.query()?UTF2DF(q.query()->str()):std::string{});
        switch(outcome) {
          case df3d_production::JobSettingsOutcome::Applied:jobSettingsEdit->outcome=m::JobSettingsEditOutcome::Applied;status=m::ManagementStatus::Ok;break;
          case df3d_production::JobSettingsOutcome::Stale:jobSettingsEdit->outcome=m::JobSettingsEditOutcome::Stale;break;
          default:jobSettingsEdit->outcome=m::JobSettingsEditOutcome::Rejected;break;
        }
      }
    } catch(...) {
      jobSettings.reset();
      if(!jobSettingsEdit)jobSettingsEdit=JobSettingsEditResult{q.job_id(),q.building_id(),q.unit_id(),m::JobSettingsEditOutcome::Unknown};
      jobSettingsEdit->outcome=(jobSettingsEdit->outcome==m::JobSettingsEditOutcome::Applied || jobSettingsEdit->outcome==m::JobSettingsEditOutcome::Unknown)?m::JobSettingsEditOutcome::Unknown:m::JobSettingsEditOutcome::Rejected;
    }
    // Confirmed/uncertain writes retain an Unknown receipt if publication fails.
    // Ordinary field edits perform no fallible work after their first write.
    publish();return;
  }
  if(r->action()==m::ManagementAction::JobSettingsRead) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& q=*r->job_settings();
    try {
      df::job* source=nullptr;
      if(q.unit_id()>=0) {
        const auto eligible=df3d_residents::orderedResidents(0,false);
        auto* unit=df::unit::find(q.unit_id());
        if(eligible && unit && std::find(eligible->begin(),eligible->end(),q.unit_id())!=eligible->end() &&
           unit->job.current_job && unit->job.current_job->id==q.job_id())source=unit->job.current_job;
      } else if(auto* holder=df::building::find(q.building_id())) {
        for(auto* job:holder->jobs)if(job && job->id==q.job_id()){source=job;break;}
      }
      if(source) {
        if(q.art()){processJobDraft(*source,q.unit_id(),q.building_id(),q.option(),q.expected_revision(),*q.art(),false);publish();return;}
        if(q.art_page()!=-2) {
          auto root=df3d_production::nativeJobSettings(*source,-1,{},false);
          if(root && root->buildingId==q.building_id() && q.option()>=0 && size_t(q.option())<root->options.size() &&
             (root->options[size_t(q.option())].kind==1 || root->options[size_t(q.option())].kind==3)) {
            auto page=df3d_production::nativeJobArtPage(*source,q.art_page(),UTF2DF(q.query()->str()),q.cursor(),q.expected_list_revision(),q.hovered(),q.preview_columns());
            if(page && page->revision==root->revision) {
              const auto convert=[](std::string& text,size_t limit){text=DF2UTF(text);return text.size()<=limit && text.find('\0')==std::string::npos;};
              bool bounded=convert(root->caption,512) && convert(page->page.caption,512);
              for(auto& option:root->options)if(!convert(option.caption,512))bounded=false;
              for(auto& row:page->page.rows)if(!convert(row.caption,1024) || (row.badge && !convert(*row.badge,128)))bounded=false;
              if(page->page.preview)for(auto& line:*page->page.preview)if(!convert(line,2048))bounded=false;
              if(bounded){root->selected=q.option();jobSettings=JobSettingsResult{q.unit_id(),0,std::move(*root),std::move(page->page)};status=m::ManagementStatus::Ok;}
            }
          }
          publish();return;
        }
        auto value=df3d_production::nativeJobSettings(*source,q.option(),UTF2DF(q.query()->str()));
        if(value && value->buildingId==q.building_id() && q.cursor()<=value->materials.size()) {
          const auto convert=[](std::string& text,size_t limit){text=DF2UTF(text);return text.size()<=limit && text.find('\0')==std::string::npos;};
          bool bounded=convert(value->caption,512) && value->options.size()<=65;
          if(value->currentValue && !convert(*value->currentValue,512))bounded=false;
          for(auto& o:value->options)if(!convert(o.caption,512))bounded=false;
          for(auto& c:value->materials)if(!convert(c.caption,512) || (c.countCaption && !convert(*c.countCaption,128)))bounded=false;
          if(bounded){jobSettings=JobSettingsResult{q.unit_id(),q.cursor(),std::move(*value)};status=m::ManagementStatus::Ok;}
        }
      }
    } catch(...) {jobSettings.reset();}
    publish();return;
  }
  if(r->action()==m::ManagementAction::ResidentsActivityRead) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& query=*r->residents_activity();
    try {
      const auto eligible=df3d_residents::orderedResidents(0,false);
      if(eligible && std::find(eligible->begin(),eligible->end(),query.unit_id())!=eligible->end()) {
        auto value=df3d_residents::activityDescription(df::unit::find(query.unit_id()),query.columns(),query.activity_id(),query.event_id());
        if(value) {
          bool bounded=value->maxY>=0 && value->maxY<=32768;size_t bytes=0;
          for(auto& word:value->words){word.text=DF2UTF(word.text);bytes+=word.text.size();
            if(bytes>131072 || word.text.find('\0')!=std::string::npos || word.x < -1 || word.x>131072 || word.y < -1 || word.y>value->maxY)bounded=false;}
          for(const auto& link:value->links)if(link.type < -1 || link.type>11)bounded=false;
          if(bounded){residentsActivity=ResidentsActivityResult{query.unit_id(),std::move(*value)};status=m::ManagementStatus::Ok;}
        }
      }
    } catch(...) {residentsActivity.reset();}
    publish();return;
  }
  if(r->action()==m::ManagementAction::ResidentsRowsRead || r->action()==m::ManagementAction::WorkDetailRowsRead) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& query=*r->residents_rows();
    const bool detail=r->action()==m::ManagementAction::WorkDetailRowsRead;
    try {
      std::optional<std::vector<int32_t>> eligible;
      if(!detail)eligible=df3d_residents::orderedResidents(0,false);
      else {
        const auto receipt=df3d_production::workDetailReceipt(query.detail_index());
        if(receipt && *receipt==query.expected_revision())eligible.emplace(query.unit_ids()->begin(),query.unit_ids()->end());
      }
      if(eligible) {
        std::vector<ResidentRowResult> rows;size_t bytes=0,appearanceBytes=0;
        for(auto id:*query.unit_ids()) {
          if(std::find(eligible->begin(),eligible->end(),id)==eligible->end())break;
          auto* unit=df::unit::find(id);if(!unit)break;
          if(detail){
            if(!df::global::world || std::find(df::global::world->units.active.begin(),df::global::world->units.active.end(),unit)==df::global::world->units.active.end())break;
            const auto allowed=df3d_production::workshopWorkerAllowed(unit);if(!allowed || !*allowed)break;
          }
          auto row=df3d_residents::rowText(unit,query.columns(),query.show_gender(),!detail);
          if(!row || row->activity.foreground<0 || row->activity.foreground>7 ||
             row->activity.background<0 || row->activity.background>7)break;
          bool bounded=true;
          for(auto* text:{&row->name.combined,&row->name.name,&row->name.profession,&row->name.firstLine,&row->name.secondLine,&row->activity.caption}) {
            *text=DF2UTF(*text);bytes+=text->size();
            if(text->size()>4096 || text->find('\0')!=std::string::npos)bounded=false;
          }
          if(!bounded || bytes>131072)break;
          std::optional<ResidentAppearanceRecipe> icon;
          ResidentAppearanceRecipe recipe;recipe.collect(df::unit::find(id),true);
          if(!recipe.layers.empty()) {
            flatbuffers::FlatBufferBuilder check;check.Finish(recipe.build(check));
            if(m::validateOwnerAppearance(*flatbuffers::GetRoot<m::SelectionAppearance>(check.GetBufferPointer()),appearanceBytes) || appearanceBytes>131072)break;
            icon=std::move(recipe);
          }
          const auto specialization=df3d_residents::specialization(df::unit::find(id));if(!specialization)break;
          auto assignments=df3d_area::observeNativeUnitAssignments(id);if(!assignments || assignments->size()>256)break;
          for(const auto& e:*assignments) {
            bytes+=32+e.name.size()+e.customCode.size();
            if(e.name.size()>4096 || e.customCode.size()>64 || e.name.find('\0')!=std::string::npos || e.customCode.find('\0')!=std::string::npos)bounded=false;
          }
          if(!bounded || bytes>131072)break;
          // Native142a4f1 captures unit.pos for Recenter; no holder or follow filter.
          rows.push_back({id,std::move(*row),std::move(icon),*specialization,std::move(*assignments),unit->pos,detail?std::nullopt:df3d_residents::activityDescriptionTarget(unit),detail?std::nullopt:df3d_production::jobSettingsTarget(unit->job.current_job)});
          if(detail) {
            auto skills=df3d_production::workDetailSkillText(query.detail_index(),unit);
            if(!skills || skills->size()>149){rows.pop_back();break;}
            for(auto& skill:*skills){skill.caption=DF2UTF(skill.caption);bytes+=skill.caption.size();
              if(skill.caption.size()>4096 || skill.caption.find('\0')!=std::string::npos)bounded=false;}
            if(!bounded || bytes>131072){rows.pop_back();break;}
            rows.back().workDetailSkills=std::move(*skills);
            const auto& members=df::global::plotinfo->labor_info.work_details[size_t(query.detail_index())]->assigned_units;
            rows.back().detailMember=std::binary_search(members.begin(),members.end(),id)?1:0;
          }
        }
        if(rows.size()==query.unit_ids()->size()) {residentsRows=std::move(rows);status=m::ManagementStatus::Ok;}
      }
    } catch(...) {residentsRows.reset();}
    publish();return;
  }
  if(r->action()==m::ManagementAction::PlacesApply){
    const auto& q=*r->places();status=m::ManagementStatus::Rejected;message.clear();places.emplace();
    places->tab=5;places->buildingId=q.building_id();places->siegeAction=q.siege_action();bool started=false;
    try {
      const auto current=df3d_places::lists();if(!current)throw std::runtime_error("places unavailable");
      const auto& ids=(*current)[5];
      if(df3d_places::membershipRevision(5,ids)!=q.expected_list_revision() ||
        (q.building_id()!=-1 && std::find(ids.begin(),ids.end(),q.building_id())==ids.end()))places->outcome=m::PlacesOutcome::Stale;
      else {
        started=true;const auto result=df3d_places::siegeAction(q.building_id(),q.siege_action());
        if(result==df3d_places::ActionOutcome::Applied){places->outcome=m::PlacesOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;}
        else if(result==df3d_places::ActionOutcome::Unknown){places->outcome=m::PlacesOutcome::Unknown;mutated=true;}
      }
    }catch(...){if(started){places->outcome=m::PlacesOutcome::Unknown;mutated=true;}}
    publish();return;
  }
  if(r->action()==m::ManagementAction::NoblesSymbolsRetire){
    status=m::ManagementStatus::Rejected;message.clear();nobles.emplace();
    if(!noblesSymbolOwner || noblesSymbolOwner->client==client){noblesSymbolOwner.reset();nobles->outcome=m::NoblesOutcome::Applied;status=m::ManagementStatus::Ok;}
    publish();return;
  }
  // A closed mailbox retires its unfinished tail. Already applied effects stay.
  if(noblesSymbolOwner && !sh::ClientMailbox::open(m::kManagementRegionName,
      sh::atomicLoadAcquire(&m::sessionOwner(region)->generation),noblesSymbolOwner->client,m::kManagementVersion,m::kManagementCapacity))noblesSymbolOwner.reset();
  if(r->action()>=m::ManagementAction::NoblesSymbolsRead && r->action()<=m::ManagementAction::NoblesSymbolsContinue){
    status=m::ManagementStatus::Rejected;message.clear();nobles.emplace();
    const auto& q=*r->nobles();using Outcome=df3d_nobles::DraftCommitOutcome;
    bool effects=false;
    const auto finish=[&](Outcome outcome){
      if(outcome==Outcome::Applied){nobles->outcome=m::NoblesOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;}
      else if(outcome==Outcome::Unknown){nobles->outcome=m::NoblesOutcome::Unknown;mutated=true;if(noblesSymbolOwner)noblesSymbolOwner->uncertain=true;}
      else if(outcome==Outcome::Stale)nobles->outcome=m::NoblesOutcome::Stale;
    };
    const auto receipt=[&]{const auto& owner=*noblesSymbolOwner;nobles->step=NoblesResult::Step{owner.token,owner.artifact,uint32_t(owner.remaining.size())};};
    try {
      const bool initial=r->action()==m::ManagementAction::NoblesSymbolsRead || r->action()==m::ManagementAction::NoblesSymbolsApply;
      if(initial && noblesSymbolOwner){publish();return;}
      if(!initial){
        if(!noblesSymbolOwner || noblesSymbolOwner->client!=client || noblesSymbolOwner->epoch!=epoch ||
            noblesSymbolOwner->token!=q.step_token() || noblesSymbolOwner->uncertain){nobles->outcome=m::NoblesOutcome::Stale;publish();return;}
        auto& owner=*noblesSymbolOwner;
        if(r->action()==m::ManagementAction::NoblesSymbolNameRead){
          auto snapshot=df3d_nobles::observeSymbolName(owner.office,owner.artifact);
          if(!snapshot || (q.expected_name_revision() && q.expected_name_revision()!=snapshot->revision)){nobles->outcome=m::NoblesOutcome::Stale;publish();return;}
          const auto& query=*q.name_query();NoblesResult::Name page;page.snapshot=std::move(*snapshot);page.component=query.component();
          page.query.assign(reinterpret_cast<const char*>(query.query_bytes()->data()),query.query_bytes()->size());page.cursor=query.cursor();
          auto words=df3d_area::observeNativeLocationNameWords(page.component,page.query,page.snapshot.value.language);
          if(!words || words->size()>UINT32_MAX || page.cursor>words->size()){publish();return;}
          page.total=uint32_t(words->size());
          size_t bytes=512+page.query.size()+page.snapshot.value.firstNameCp437.size()+page.snapshot.value.nicknameCp437.size()+page.snapshot.nativeHeader.size()+page.snapshot.englishHeader.size();
          for(size_t i=page.cursor;i<words->size() && page.choices.size()<m::kLocationNamePageRows;++i){auto word=std::move((*words)[i]);
            const auto added=64+word.english.size()+word.translated.size();if(bytes+added>m::kLocationNamePageBytes)break;bytes+=added;page.choices.push_back(std::move(word));}
          const auto end=page.cursor+uint32_t(page.choices.size());if(end<page.total && page.choices.empty()){publish();return;}
          page.next=end<page.total?end:0;nobles->name=std::move(page);receipt();nobles->outcome=m::NoblesOutcome::None;status=m::ManagementStatus::Ok;publish();return;
        }
        if(r->action()==m::ManagementAction::NoblesSymbolNameEdit){
          const auto& edit=*q.name_edit();const std::string query(reinterpret_cast<const char*>(edit.query_bytes()->data()),edit.query_bytes()->size());
          effects=true;const auto outcome=df3d_nobles::editSymbolName(owner.office,owner.artifact,q.expected_name_revision(),
            df3d_area::LocationNameEdit(edit.mode()),edit.target(),edit.displayed(),edit.word(),edit.part(),query);
          finish(outcome);publish();return;
        }
        if(!df3d_nobles::namedSymbol(owner.office,owner.artifact)){nobles->outcome=m::NoblesOutcome::Stale;publish();return;}
        if(owner.remaining.empty()){noblesSymbolOwner.reset();finish(Outcome::Applied);publish();return;}
      }
      if(!df3d_nobles::symbolsReady()){publish();return;}
      df3d_nobles::Context owned(reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr)));
      NoblesSymbolOwner intent;
      if(initial){intent.client=client;intent.epoch=epoch;intent.baseRevision=q.expected_list_revision();
        const auto& key=*q.target();intent.office={key.entity_id(),key.position_id(),key.assignment_id(),key.draft_slot()};
        if(q.choices())for(const auto* choice:*q.choices()){const auto& key=*choice->target();intent.draft.push_back({key.entity_id(),key.position_id(),key.assignment_id(),choice->expected_unit_id(),choice->unit_id(),key.draft_slot()});}
      }else intent=*noblesSymbolOwner;
      if(!df3d_nobles::prepareDraft(owned,intent.draft,intent.baseRevision)){if(owned.stale)nobles->outcome=m::NoblesOutcome::Stale;publish();return;}
      if(r->action()==m::ManagementAction::NoblesSymbolsRead){
        auto rows=df3d_nobles::projectSymbols(owned,intent.office);if(!rows || rows->size()>1048576){publish();return;}
        const auto revision=df3d_nobles::symbolRevision(*rows);
        if((q.expected_candidate_revision() && q.expected_candidate_revision()!=revision) || q.offset()>rows->size()){nobles->outcome=m::NoblesOutcome::Stale;publish();return;}
        auto display=df3d_nobles::symbolDisplay(owned,q.offset(),q.limit());if(!display){publish();return;}
        NoblesResult page;page.listRevision=owned.baseRevision;page.candidateRevision=revision;page.target=*q.target();page.total=uint32_t(rows->size());page.offset=q.offset();
        const auto caption=df3d_nobles::symbolOfficeCaption(owned,intent.office);if(!caption){publish();return;}
        page.symbolTargetCaption=DF2UTF(*caption);if(page.symbolTargetCaption->size()>16384){publish();return;}
        size_t bytes=0;
        for(auto& text:*display){const auto& facts=(*rows)[q.offset()+page.symbols.size()];auto* item=df::item::find(facts.itemId);if(!item || text.itemId!=facts.itemId)throw std::runtime_error("symbol item changed");
          NoblesResult::Symbol row;row.facts=facts;row.type=int16_t(item->getType());row.text=std::move(text);row.artifactMood=row.type==24 && item->flags.bits.artifact_mood;
          for(auto* value:{&row.text.caption,&row.text.officeCaption,&row.text.valueCaption}){*value=DF2UTF(*value);if(value->size()>16384)throw std::runtime_error("symbol caption exceeds limit");}
          if(const auto appearance=df3d_production::itemAppearance(item))row.appearance=copyInspectionAppearance(*appearance);
          size_t size=128+row.text.caption.size()+row.text.officeCaption.size()+row.text.valueCaption.size();
          if(row.appearance){const auto& a=*row.appearance;
            if(a.craftGemColor)size+=4+a.craftGemColor->size();
            size+=256+a.materialToken.size()+a.subtypeRaw.size()+a.colorToken.size()+a.bucketLiquidColor.size()+a.cageSolidColor.size()+a.restraintSolidColor.size();
            for(const auto* recipe:{&a.portrait,&a.cageOccupant,&a.corpseSelector,&a.legwearSelector})if(*recipe){size_t n=0;if(!df3d_production::validItemRecipe(**recipe,n))throw std::runtime_error("invalid symbol artwork");size+=n;}
            if(a.contents){size+=64+a.contents->solidColor.size();for(const auto& e:a.contents->entries)size+=64+e.materialToken.size()+e.colorToken.size();}
          }
          if(bytes+size+page.symbolTargetCaption->size()>384*1024)break;bytes+=size;page.symbols.push_back(std::move(row));
        }
        if(page.offset<page.total && page.symbols.empty()){publish();return;}
        page.outcome=m::NoblesOutcome::None;nobles=std::move(page);status=m::ManagementStatus::Ok;publish();return;
      }
      if(initial){std::vector<df3d_nobles::SymbolChoice> choices;
        for(const auto* choice:*q.symbol_choices())choices.push_back({choice->item_id(),choice->selected()});
        if(!df3d_nobles::stageSymbols(owned,intent.office,q.expected_candidate_revision(),choices)){if(owned.stale)nobles->outcome=m::NoblesOutcome::Stale;publish();return;}
      }else if(!df3d_nobles::stageSymbolContinuation(owned,intent.office,intent.candidateRevision,intent.remaining)){if(owned.stale)nobles->outcome=m::NoblesOutcome::Stale;publish();return;}
      // Install ownership before effects. Any ambiguous result poisons this
      // sequence rather than making an initial Apply available for replay.
      noblesSymbolOwner=std::move(intent);effects=true;
      auto step=df3d_nobles::applySymbolStep(owned,noblesSymbolOwner->office);finish(step.outcome);
      if(step.outcome==Outcome::Applied){
        if(step.namingArtifactId<0)noblesSymbolOwner.reset();
        else {auto& owner=*noblesSymbolOwner;owner.artifact=step.namingArtifactId;owner.remaining=std::move(step.remaining);owner.candidateRevision=step.continuationRevision;
          owner.token=executionSerial;receipt();}
      }else if(step.outcome!=Outcome::Unknown && initial)noblesSymbolOwner.reset();
    }catch(...){nobles.emplace();if(effects)finish(Outcome::Unknown);}
    publish();return;
  }
  if(r->action()==m::ManagementAction::NoblesRead || r->action()==m::ManagementAction::NoblesCandidates || r->action()==m::ManagementAction::NoblesCommit || r->action()==m::ManagementAction::NoblesAccounting){
    const auto& q=*r->nobles();status=m::ManagementStatus::Rejected;message.clear();nobles.emplace();
    if(noblesSymbolOwner){publish();return;}
    try {
      std::vector<df3d_nobles::DraftChoice> choices;
      if(q.choices())for(const auto* choice:*q.choices()){const auto& key=*choice->target();
        choices.push_back({key.entity_id(),key.position_id(),key.assignment_id(),choice->expected_unit_id(),choice->unit_id(),key.draft_slot()});}
      if(r->action()==m::ManagementAction::NoblesCommit || r->action()==m::ManagementAction::NoblesAccounting){
        using Outcome=df3d_nobles::DraftCommitOutcome;
        const auto outcome=[&] {
          if(r->action()==m::ManagementAction::NoblesCommit)return df3d_nobles::commitDraft(choices,q.expected_list_revision());
          const auto& key=*q.target();return df3d_nobles::setAccounting(choices,q.expected_list_revision(),
            {key.entity_id(),key.position_id(),key.assignment_id(),key.draft_slot()},q.expected_setting(),q.setting());
        }();
        switch(outcome){
          case Outcome::Applied:nobles->outcome=m::NoblesOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;break;
          case Outcome::Unknown:nobles->outcome=m::NoblesOutcome::Unknown;mutated=true;break;
          case Outcome::Stale:nobles->outcome=m::NoblesOutcome::Stale;break;
          default:break;
        }
        publish();return;
      }
      if(!df3d_nobles::ready())throw std::runtime_error("nobles unavailable");
      df3d_nobles::Context owned(reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr)));
      if(!df3d_nobles::prepareDraft(owned,choices,q.expected_list_revision())){
        if(owned.stale)nobles->outcome=m::NoblesOutcome::Stale;
        publish();return;
      }
      const auto list=owned.baseRevision;
      if(r->action()==m::ManagementAction::NoblesCandidates){
        const auto& key=*q.target();df::noblelistst* target=nullptr;
        for(auto* row:owned.value.noblelist)if(row->enid==key.entity_id() && row->ep->id==key.position_id() &&
            (row->epp?row->epp->id:-1)==key.assignment_id() && owned.slot(row)==key.draft_slot()){
          if(target)throw std::runtime_error("ambiguous nobles draft target");target=row;}
        auto current=df3d_nobles::projectCandidates(owned,target,true);
        if(!current)throw std::runtime_error("nobles candidates unavailable");
        uint64_t revision=UINT64_C(14695981039346656037);
        const auto number=[&](int32_t value){for(unsigned i=0;i<4;++i){revision^=uint8_t(uint32_t(value)>>(8*i));revision*=UINT64_C(1099511628211);}};
        const auto text=[&](const std::string& value){if(value.size()>16384)throw std::runtime_error("nobles candidate text exceeds limit");number(int32_t(value.size()));for(unsigned char byte:value){revision^=byte;revision*=UINT64_C(1099511628211);}};
        for(const auto& row:*current){number(row.unitId);number(row.value);text(row.caption);text(row.noSkills);number(int32_t(row.skills.size()));
          for(const auto& skill:row.skills){number(skill.id);number(skill.rating);text(skill.caption);}}
        revision&=INT64_MAX;if(!revision)revision=1;
        if((q.expected_candidate_revision() && q.expected_candidate_revision()!=revision) || q.offset()>current->size())nobles->outcome=m::NoblesOutcome::Stale;
        else {
          NoblesResult page;page.listRevision=list;page.candidateRevision=revision;page.target=key;page.total=uint32_t(current->size());page.offset=q.offset();size_t bytes=0;
          for(size_t i=q.offset();i<current->size() && page.candidates.size()<q.limit();++i){auto& row=(*current)[i];size_t rowBytes=64;
            const auto convert=[&](std::string& value){value=DF2UTF(value);if(value.size()>16384)throw std::runtime_error("nobles candidate text exceeds limit");rowBytes+=value.size();};
            convert(row.caption);convert(row.noSkills);for(auto& skill:row.skills){rowBytes+=16;convert(skill.caption);}
            if(row.unitId>=0){df3d_appearance::Result recipe;if(df3d_appearance::resolveUnitSelector(df::unit::find(row.unitId),recipe))row.appearance=df3d_production::ownedItemRecipe(recipe);}
            if(row.appearance){size_t n=0;if(!df3d_production::validItemRecipe(*row.appearance,n))throw std::runtime_error("invalid nobles candidate artwork");rowBytes+=n;}
            if(bytes+rowBytes>384*1024)break;bytes+=rowBytes;page.candidates.push_back(std::move(row));
          }
          if(page.offset<page.total && page.candidates.empty())throw std::runtime_error("nobles candidate exceeds page");
          page.outcome=m::NoblesOutcome::None;nobles=std::move(page);status=m::ManagementStatus::Ok;
        }
        publish();return;
      }
      auto current=df3d_nobles::projectOverview(owned,true);if(!current)throw std::runtime_error("nobles unavailable");
      if(q.offset()>current->size())nobles->outcome=m::NoblesOutcome::Stale;
      else {
        NoblesResult page;page.listRevision=list;page.total=uint32_t(current->size());page.offset=q.offset();size_t bytes=0;
        for(size_t i=q.offset();i<current->size() && page.rows.size()<q.limit();++i){
          auto& row=(*current)[i];size_t rowBytes=192;
          if(row.help){auto& help=*row.help;rowBytes+=64;
            const auto text=[&](std::string& value){value=DF2UTF(value);if(value.size()>16384)throw std::runtime_error("nobles help text exceeds limit");rowBytes+=4+value.size();};
            text(help.description);
            for(auto* group:{&help.rooms,&help.furniture})for(auto& part:*group){text(part.actual);text(part.required);rowBytes+=16;}
            for(auto* group:{&help.demands,&help.mandates}){if(group->size()>65536)throw std::runtime_error("nobles obligations exceed limit");for(auto& item:*group){text(item.text);rowBytes+=16;}}
            if(help.accounting){auto& a=*help.accounting;text(a.title);text(a.examples);text(a.attained);text(a.progress);rowBytes+=16;}
          }
          // Native4276d3 uses6d6560 with flag400, matching the shared full-body
          // selector. Resolve only this page, independently of map residency.
          if(row.unitId>=0){df3d_appearance::Result recipe;
            if(df3d_appearance::resolveUnitSelector(df::unit::find(row.unitId),recipe))
              row.appearance=df3d_production::ownedItemRecipe(recipe);
          }
          if(row.appearance){size_t n=0;if(!df3d_production::validItemRecipe(*row.appearance,n))throw std::runtime_error("invalid nobles artwork");rowBytes+=n;}
          for(auto* text:{&row.title,&row.squadCaption,&row.holderCaption}){
            *text=DF2UTF(*text);if(text->size()>16384)throw std::runtime_error("nobles caption exceeds limit");rowBytes+=text->size();}
          if(bytes+rowBytes>384*1024)break;bytes+=rowBytes;page.rows.push_back(std::move(row));
        }
        if(page.offset<page.total && page.rows.empty())throw std::runtime_error("nobles row exceeds page");
        page.outcome=m::NoblesOutcome::None;nobles=std::move(page);status=m::ManagementStatus::Ok;
      }
    }catch(...){nobles.emplace();}
    publish();return;
  }
  if(r->action()>=m::ManagementAction::JusticeRead && r->action()<=m::ManagementAction::JusticeConvict){
    justice=r->action()>=m::ManagementAction::JusticeCandidatesRead?
      df3d_justice::candidateRequest(*r->justice(),r->action()==m::ManagementAction::JusticeConvict):
      df3d_justice::read(*r->justice(),r->action()==m::ManagementAction::JusticeCaseRead);
    status=(justice->outcome==m::JusticeOutcome::None || justice->outcome==m::JusticeOutcome::Applied)?m::ManagementStatus::Ok:m::ManagementStatus::Rejected;
    if(justice->outcome==m::JusticeOutcome::Applied || justice->outcome==m::JusticeOutcome::Unknown)mutated=true;
    message.clear();publish();return;
  }
  if(r->action()==m::ManagementAction::ObjectsRead || r->action()==m::ManagementAction::ObjectsLocate){
    const auto& q=*r->objects();status=m::ManagementStatus::Rejected;message.clear();objects.emplace();objects->tab=q.tab();
    try {
      const auto all=df3d_objects::lists();if(!all)throw std::runtime_error("objects unavailable");
      const auto& ids=(*all)[q.tab()];
      uint64_t revision=UINT64_C(14695981039346656037);revision^=q.tab();revision*=UINT64_C(1099511628211);
      for(auto id:ids)for(unsigned i=0;i<4;++i){revision^=uint8_t(uint32_t(id)>>(8*i));revision*=UINT64_C(1099511628211);}
      revision&=INT64_MAX;if(!revision)revision=1;
      const bool locate=r->action()==m::ManagementAction::ObjectsLocate;
      if((q.expected_list_revision() && q.expected_list_revision()!=revision) || q.offset()>ids.size() ||
        (locate && std::find(ids.begin(),ids.end(),q.artifact_id())==ids.end()))objects->outcome=m::ObjectsOutcome::Stale;
      else {
        ObjectsResult page;page.tab=q.tab();page.listRevision=revision;
        if(locate){page.artifactId=q.artifact_id();page.destination=df3d_objects::destination(q.artifact_id());
          if(!page.destination)throw std::runtime_error("objects destination unavailable");}
        else {
          page.total=uint32_t(ids.size());page.offset=q.offset();size_t bytes=0;
          for(size_t i=q.offset();i<ids.size() && page.rows.size()<q.limit();++i){
            auto names=df3d_objects::names(ids[i]);auto caption=df3d_objects::ownership(ids[i]);auto target=df3d_objects::destination(ids[i]);
            if(!names || !caption || !target)throw std::runtime_error("objects row unavailable");
            ObjectsRow row{std::move(*names),std::move(*caption),*target};size_t rowBytes=128;
            auto* item=df::artifact_record::find(ids[i])->item;row.itemType=int16_t(item->getType());
            if(const auto look=df3d_production::itemAppearance(item))row.appearance=copyInspectionAppearance(*look);
            if(row.appearance){const auto& a=*row.appearance;
              rowBytes+=256+a.materialToken.size()+a.subtypeRaw.size()+a.colorToken.size()+a.bucketLiquidColor.size()+a.cageSolidColor.size()+a.restraintSolidColor.size();
              if(a.craftGemColor)rowBytes+=4+a.craftGemColor->size();
              for(const auto* recipe:{&a.portrait,&a.cageOccupant,&a.corpseSelector,&a.legwearSelector})if(*recipe){size_t n=0;if(!df3d_production::validItemRecipe(**recipe,n))throw std::runtime_error("invalid objects artwork");rowBytes+=n;}
              if(a.contents){rowBytes+=64+a.contents->solidColor.size();for(const auto& e:a.contents->entries)rowBytes+=64+e.materialToken.size()+e.colorToken.size();}
            }
            for(auto* text:{&row.names.nativeName,&row.names.translatedName,&row.ownership}){
              *text=DF2UTF(*text);if(text->size()>16384)throw std::runtime_error("objects caption exceeds limit");rowBytes+=text->size();}
            if(bytes+rowBytes>384*1024)break;bytes+=rowBytes;page.rows.push_back(std::move(row));
          }
          if(page.offset<page.total && page.rows.empty())throw std::runtime_error("objects row exceeds page");
        }
        page.outcome=m::ObjectsOutcome::None;objects=std::move(page);status=m::ManagementStatus::Ok;
      }
    }catch(...){objects.emplace();objects->tab=q.tab();}
    publish();return;
  }
  if(r->action()==m::ManagementAction::PlacesRead){
    const auto& q=*r->places();status=m::ManagementStatus::Rejected;message.clear();places.emplace();places->tab=q.tab();
    try {
      auto all=df3d_places::buildingRows(q.tab());if(!all)throw std::runtime_error("places unavailable");
      auto& current=(*all)[q.tab()];std::vector<int32_t> ids;ids.reserve(current.size());
      for(const auto& row:current)ids.push_back(row.id);
      const auto revision=df3d_places::membershipRevision(q.tab(),ids);
      if((q.expected_list_revision() && q.expected_list_revision()!=revision) || q.offset()>current.size())places->outcome=m::PlacesOutcome::Stale;
      else {
        PlacesResult page;page.tab=q.tab();page.listRevision=revision;page.total=uint32_t(current.size());page.offset=q.offset();size_t bytes=0;
        for(size_t i=q.offset();i<current.size() && page.rows.size()<q.limit();++i){
          auto& row=current[i];size_t rowBytes=128;
          for(auto* text:{&row.name,&row.subtitle,&row.jobCaption,&row.statusCaption,&row.secondaryStatus,&row.statusOverlay,&row.operatorCaption}){
            *text=DF2UTF(*text);if(text->size()>16384)throw std::runtime_error("places caption exceeds limit");rowBytes+=text->size();}
          if(row.appearance){size_t n=0;if(!df3d_production::validItemRecipe(*row.appearance,n))throw std::runtime_error("invalid places artwork");rowBytes+=n;}
          if(bytes+rowBytes>384*1024)break;bytes+=rowBytes;page.rows.push_back(std::move(row));
        }
        if(page.offset<page.total && page.rows.empty())throw std::runtime_error("places row exceeds page");
        page.outcome=m::PlacesOutcome::None;places=std::move(page);status=m::ManagementStatus::Ok;
      }
    }catch(...){places.emplace();places->tab=q.tab();}
    publish();return;
  }
  if(r->action()==m::ManagementAction::TasksRead || r->action()==m::ManagementAction::TasksApply){
    namespace h=df3d_tasks;
    const auto& q=*r->tasks();const bool edit=r->action()==m::ManagementAction::TasksApply;
    status=m::ManagementStatus::Rejected;message.clear();tasks.emplace();tasks->jobId=edit?q.job_id():-1;
    try {
      auto current=h::rows(!edit);if(!current)throw std::runtime_error("tasks unavailable");
      if(edit){
        const auto row=std::find_if(current->begin(),current->end(),[&](const auto& v){return v.jobId==q.job_id();});
        if(row==current->end() || tasksRowRevision(*row)!=q.expected_revision() || row->unitId!=q.worker_id() || row->buildingId!=q.building_id())tasks->outcome=m::TasksOutcome::Stale;
        else {
          const auto result=h::apply(h::Action(q.operation()),q.job_id(),q.worker_id(),q.building_id(),q.expected_state()==1);
          if(result==h::Outcome::Applied){tasks->outcome=m::TasksOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;}
          else if(result==h::Outcome::Unknown){tasks->outcome=m::TasksOutcome::Unknown;mutated=true;}
        }
      }else{
        uint64_t list=UINT64_C(14695981039346656037);
        for(const auto& row:*current)for(unsigned i=0;i<4;++i){list^=uint8_t(uint32_t(row.jobId)>>(8*i));list*=UINT64_C(1099511628211);}
        list&=INT64_MAX;if(!list)list=1;
        if((q.expected_list_revision() && q.expected_list_revision()!=list) || q.offset()>current->size())tasks->outcome=m::TasksOutcome::Stale;
        else {
          TasksResult page;page.listRevision=list;page.total=uint32_t(current->size());page.offset=q.offset();size_t bytes=0;
          for(size_t i=q.offset();i<current->size() && page.rows.size()<q.limit();++i){
            auto& row=(*current)[i];row.caption=DF2UTF(row.caption);row.workerName=DF2UTF(row.workerName);row.buildingCaption=DF2UTF(row.buildingCaption);
            size_t rowBytes=128+row.caption.size()+row.workerName.size()+row.buildingCaption.size();
            for(const auto* recipe:{&row.workerAppearance,&row.buildingAppearance})if(*recipe){size_t n=0;if(!df3d_production::validItemRecipe(**recipe,n))throw std::runtime_error("invalid tasks artwork");rowBytes+=n;}
            if(bytes+rowBytes>384*1024)break;
            bytes+=rowBytes;page.rows.push_back(std::move(row));
          }
          if(page.offset<page.total && page.rows.empty())throw std::runtime_error("tasks row exceeds page");
          page.outcome=m::TasksOutcome::None;tasks=std::move(page);status=m::ManagementStatus::Ok;
        }
      }
    }catch(...){status=m::ManagementStatus::Rejected;tasks.emplace();tasks->jobId=edit?q.job_id():-1;}
    publish();return;
  }
  if(r->action()==m::ManagementAction::StocksMenuRead || r->action()==m::ManagementAction::StocksGroupApply || r->action()==m::ManagementAction::StocksItemApply) {
    namespace h=df3d_stocks;
    status=m::ManagementStatus::Rejected;message.clear();stocks.emplace();bool writeStarted=false;
    try {
      const auto& q=*r->stocks_menu();
      if(q.page_request()) {
        if(!publishStocksPage({epoch,client,q.page_request()},q.page_offset())){message="Stocks reply expired";publish();}
        return;
      }
      stocksReplies.retire(client);
      if(r->action()==m::ManagementAction::StocksMenuRead){
        std::vector<int32_t> ids;if(q.item_ids())ids.assign(q.item_ids()->begin(),q.item_ids()->end());
        stocks=readStocks(q.category(),UTF2DF(q.query()->str()),ids);
        stocks->outcome=m::StocksMenuOutcome::None;status=m::ManagementStatus::Ok;
      }else{
        const auto& key=*q.target();
        const h::Group target{key.type(),key.subtype(),key.subcat1(),key.subcat2(),0,false};
        df3d_production::BuildingItemAction operation;
        switch(q.operation()){
          case m::StocksFlagAction::Forbid:operation=df3d_production::BuildingItemAction::Forbid;break;
          case m::StocksFlagAction::Dump:operation=df3d_production::BuildingItemAction::Dump;break;
          case m::StocksFlagAction::Melt:operation=df3d_production::BuildingItemAction::Melt;break;
          case m::StocksFlagAction::Hidden:operation=df3d_production::BuildingItemAction::Hidden;break;
          default:throw std::runtime_error("invalid stocks operation");
        }
        auto edit=r->action()==m::ManagementAction::StocksItemApply?
          h::editItem(target,q.expected_revision(),q.item_id(),operation,q.value()!=0):h::editGroup(target,q.expected_revision(),operation,q.value()!=0);
        writeStarted=edit.outcome==h::EditOutcome::Applied || edit.outcome==h::EditOutcome::Unknown;
        if(writeStarted)mutated=true;
        if(edit.outcome==h::EditOutcome::Applied){
          if(!edit.receipt)throw std::runtime_error("stocks edit receipt unavailable");
          stocks=readStocks(q.category(),"",{},std::move(edit.receipt));
          stocks->outcome=m::StocksMenuOutcome::Applied;status=m::ManagementStatus::Ok;
        }else if(edit.outcome==h::EditOutcome::Stale)stocks->outcome=m::StocksMenuOutcome::Stale;
        else if(edit.outcome==h::EditOutcome::Unknown)stocks->outcome=m::StocksMenuOutcome::Unknown;
      }
    }catch(...){stocks.emplace();status=m::ManagementStatus::Rejected;
      if(writeStarted){stocks->outcome=m::StocksMenuOutcome::Unknown;mutated=true;}}
    publish();return;
  }
  if(r->action()==m::ManagementAction::StoneUseRead || r->action()==m::ManagementAction::StoneUseApply) {
    namespace h=df3d_stone_use;
    status=m::ManagementStatus::Rejected;message.clear();stoneUse.emplace();bool writeStarted=false;
    try {
      const auto& q=*r->stone_use();
      if(r->action()==m::ManagementAction::StoneUseRead){
        auto rows=h::read();if(!rows || !df::global::plotinfo)throw std::runtime_error("stone use unavailable");
        for(auto& row:*rows){row.name=DF2UTF(row.name);row.uses=DF2UTF(row.uses);}
        const auto& flags=df::global::plotinfo->economic_stone;
        stoneUse->restrictions.assign(flags.begin(),flags.end());stoneUse->rows=std::move(*rows);
        stoneUse->outcome=m::StoneUseOutcome::None;status=m::ManagementStatus::Ok;
      }else{
        std::vector<char> expected(q.expected()->begin(),q.expected()->end());
        const auto outcome=h::apply(q.category(),q.index(),expected,&writeStarted);
        if(outcome==h::Outcome::Applied){stoneUse->outcome=m::StoneUseOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;}
        else if(outcome==h::Outcome::Stale)stoneUse->outcome=m::StoneUseOutcome::Stale;
      }
    }catch(...){stoneUse.emplace();status=m::ManagementStatus::Rejected;
      if(writeStarted){stoneUse->outcome=m::StoneUseOutcome::Unknown;mutated=true;}}
    publish();return;
  }
  if(r->action()==m::ManagementAction::KitchenRead || r->action()==m::ManagementAction::KitchenApply) {
    namespace h=df3d_kitchen;
    status=m::ManagementStatus::Rejected;message.clear();kitchen.emplace();bool writeStarted=false;
    try {
      const auto& q=*r->kitchen_menu();
      if(r->action()==m::ManagementAction::KitchenRead){
        const auto& v=*q.query();std::vector<h::Sort> sorts;
        for(const auto* row:*v.sorts())sorts.push_back({h::Column(row->column()),row->reverse()});
        auto rows=h::read({v.type_filter(),v.capability_filter(),UTF2DF(v.query()->str())},sorts);
        if(!rows)throw std::runtime_error("kitchen rows unavailable");
        auto display=h::display(*rows);auto exclusions=h::exclusions();
        if(!display || display->size()!=rows->size() || !exclusions)throw std::runtime_error("kitchen metadata unavailable");
        for(auto& row:*rows)row.name=DF2UTF(row.name);
        for(auto& row:*display)row.countCaption=DF2UTF(row.countCaption);
        kitchen->rows=std::move(*rows);kitchen->display=std::move(*display);kitchen->exclusions=std::move(*exclusions);
        kitchen->outcome=m::KitchenMenuOutcome::None;status=m::ManagementStatus::Ok;
      }else{
        const auto& target=*q.target();const auto& key=*target.key();std::vector<h::Exclusion> expected;
        expected.reserve(q.expected()->size());
        for(const auto* row:*q.expected()){const auto& k=*row->key();expected.push_back({k.item_type(),k.item_subtype(),k.mat_type(),k.mat_index(),row->flags()});}
        const h::Row row{key.item_type(),key.item_subtype(),key.mat_type(),key.mat_index(),target.count(),target.capabilities(),{}};
        const auto outcome=h::apply(row,q.permission(),expected,&writeStarted);
        if(outcome==h::Outcome::Applied){kitchen->outcome=m::KitchenMenuOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;}
        else if(outcome==h::Outcome::Stale)kitchen->outcome=m::KitchenMenuOutcome::Stale;
      }
      publish();return;
    }catch(...){
      kitchen.emplace();status=m::ManagementStatus::Rejected;
      if(writeStarted){kitchen->outcome=m::KitchenMenuOutcome::Unknown;mutated=true;}
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::ChoresRead || r->action()==m::ManagementAction::ChoresApply) {
    namespace h=df3d_chores;
    status=m::ManagementStatus::Rejected;message.clear();chores.emplace();bool writeStarted=false;
    try {
      const auto& q=*r->chores();
      if(r->action()==m::ManagementAction::ChoresRead){
        auto snapshot=h::read();if(!snapshot)throw std::runtime_error("chores unavailable");
        auto captions=h::captions(*snapshot);if(!captions)throw std::runtime_error("chores captions unavailable");
        for(auto& row:captions->children)row.text=DF2UTF(row.text);
        for(auto& row:captions->labors)row.text=DF2UTF(row.text);
        chores->snapshot=std::move(snapshot);chores->captions=std::move(*captions);
        chores->outcome=m::ChoresOutcome::None;status=m::ManagementStatus::Ok;
      }else{
        const auto& v=*q.expected();h::Snapshot expected;
        expected.enabled=v.enabled();expected.children.assign(v.children()->begin(),v.children()->end());
        expected.exempted.assign(v.exempted()->begin(),v.exempted()->end());
        for(const auto* row:*v.labors())expected.labors.emplace_back(row->id(),row->enabled());
        // Prepare the complete returned receipt before native effects begin.
        auto prepared=expected;
        if(q.operation()==m::ChoresOperation::Enabled)prepared.enabled=q.value();
        else if(q.operation()==m::ChoresOperation::Labor){for(auto& row:prepared.labors)if(row.first==q.id())row.second=q.value();}
        else {auto it=std::lower_bound(prepared.exempted.begin(),prepared.exempted.end(),q.id());
          const bool exists=it!=prepared.exempted.end() && *it==q.id();
          if(q.value() && !exists)prepared.exempted.insert(it,q.id());else if(!q.value() && exists)prepared.exempted.erase(it);}
        const auto outcome=h::apply(h::Operation(q.operation()),q.id(),q.value(),expected,&writeStarted);
        if(outcome==h::Outcome::Applied){
          chores->snapshot=std::move(prepared);chores->outcome=m::ChoresOutcome::Applied;
          mutated=true;status=m::ManagementStatus::Ok;
        }else if(outcome==h::Outcome::Stale)chores->outcome=m::ChoresOutcome::Stale;
      }
      publish();return;
    }catch(...){
      chores.emplace();status=m::ManagementStatus::Rejected;
      if(writeStarted){chores->outcome=m::ChoresOutcome::Unknown;mutated=true;}
    }
    publish();return;
  }
  if(r->action()>=m::ManagementAction::HunterAmmunitionRead && r->action()<=m::ManagementAction::HunterAmmunitionApply) {
    namespace h=df3d_hunter_ammunition;
    message.clear();status=m::ManagementStatus::Rejected;hunter.emplace();bool applied=false;
    const auto& q=*r->hunter_ammunition();
    try {
      if(r->action()==m::ManagementAction::HunterAmmunitionApply){
        h::Snapshot expected;
        for(const auto* v:*q.expected())expected.push_back({v->item_type(),v->item_subtype(),v->material_class(),v->mattype(),v->matindex(),v->amount(),v->flags(),{v->assigned()->begin(),v->assigned()->end()}});
        h::EditResult result;
        switch(q.operation()){
        case m::HunterAmmunitionOperation::Amount:result=h::setAmount(expected,size_t(q.index()),q.amount());break;
        case m::HunterAmmunitionOperation::Material:result=h::setMaterial(expected,size_t(q.index()),{q.material_class(),q.mattype(),q.matindex()});break;
        case m::HunterAmmunitionOperation::Add:result=h::add(expected,{q.item_type(),q.item_subtype(),false});break;
        case m::HunterAmmunitionOperation::Delete:result=h::remove(expected,size_t(q.index()),std::nullopt);break;
        case m::HunterAmmunitionOperation::Remove:result=h::remove(expected,size_t(q.index()),q.item_id());break;
        default:break;
        }
        if(result.outcome==h::EditOutcome::Applied){
          applied=true;mutated=true;hunter->outcome=m::HunterAmmunitionOutcome::Applied;
          hunter->specs=std::move(result.specs);status=m::ManagementStatus::Ok;
        }else if(result.outcome==h::EditOutcome::Stale)hunter->outcome=m::HunterAmmunitionOutcome::Stale;
      }else{
        const auto choices=h::candidates();if(!choices)throw std::runtime_error("ammunition choices unavailable");
        if(r->action()==m::ManagementAction::HunterAmmunitionCandidates){
          bool found=false;for(const auto& type:choices->types)if(type.type==q.item_type() && type.subtype==q.item_subtype()){found=true;break;}
          if(!found)throw std::runtime_error("ammunition type unavailable");
          hunter->type=q.item_type();hunter->subtype=q.item_subtype();
          for(const auto& material:choices->materials){
            const auto caption=h::caption(q.item_type(),q.item_subtype(),material);if(!caption)throw std::runtime_error("ammunition material caption unavailable");
            hunter->materials.emplace_back(material,DF2UTF(*caption));
          }
        }else{
          auto specs=h::snapshot();if(!specs)throw std::runtime_error("ammunition snapshot unavailable");
          hunter->specs=std::move(*specs);
          for(const auto& type:choices->types){
            const auto caption=h::caption(type.type,type.subtype,{-1,-1,-1},true,type.foreign);if(!caption)throw std::runtime_error("ammunition type caption unavailable");
            hunter->types.emplace_back(type,DF2UTF(*caption));
          }
          for(const auto& spec:hunter->specs){
            const auto caption=h::caption(int16_t(spec.item_type),int16_t(spec.item_subtype),{int16_t(spec.material_class),int16_t(spec.mattype),spec.matindex});
            if(!caption)throw std::runtime_error("ammunition rule caption unavailable");
            HunterResult::Rule row;row.caption=DF2UTF(*caption);
            for(auto id:spec.assigned){
              auto* item=df::item::find(id);if(!item)continue;
              const auto name=h::stackCaption(item);if(!name)throw std::runtime_error("ammunition stack caption unavailable");
              auto appearance=df3d_production::itemAppearance(item);if(!appearance)throw std::runtime_error("ammunition appearance unavailable");
              appearance->materialToken=DF2UTF(appearance->materialToken);appearance->subtypeRaw=DF2UTF(appearance->subtypeRaw);appearance->colorToken=DF2UTF(appearance->colorToken);
              const int32_t quantity=item->getStackSize();row.quantity+=quantity;row.items.push_back({id,quantity,DF2UTF(*name),std::move(*appearance)});
            }
            hunter->rules.push_back(std::move(row));
          }
        }
        hunter->outcome=m::HunterAmmunitionOutcome::None;status=m::ManagementStatus::Ok;
      }
      publish();return;
    }catch(...){
      hunter.emplace();status=m::ManagementStatus::Rejected;
      if(applied){hunter->outcome=m::HunterAmmunitionOutcome::Unknown;mutated=true;}
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::StandingOrdersRead || r->action()==m::ManagementAction::StandingOrdersSet) {
    message.clear();status=m::ManagementStatus::Rejected;standingOrders.emplace();
    const auto& query=*r->standing_orders();
    standingOrders->category=query.category();
    if(query.category()!=0){
      try {
        if(r->action()==m::ManagementAction::StandingOrdersRead) {
          const auto snapshot=df3d_standing::categorySettings(query.category());
          if(snapshot){standingOrders->categorySettings=*snapshot;standingOrders->outcome=m::StandingOrdersOutcome::None;status=m::ManagementStatus::Ok;}
        } else {
          df3d_standing::CategorySettings receipt;
          const auto outcome=df3d_standing::setCategory(query.category(),query.setting_id(),query.expected_value(),query.value(),&receipt);
          if(outcome==df3d_standing::EditOutcome::Stale)standingOrders->outcome=m::StandingOrdersOutcome::Stale;
          else if(outcome==df3d_standing::EditOutcome::Applied){
            standingOrders->categorySettings=receipt;standingOrders->outcome=m::StandingOrdersOutcome::Applied;
            mutated=true;status=m::ManagementStatus::Ok;
          }
        }
      } catch(...) {standingOrders.emplace();standingOrders->category=query.category();}
      publish();return;
    }
    const bool set=r->action()==m::ManagementAction::StandingOrdersSet;
    try {
      auto snapshot=df3d_standing::workshopSettings();
      if(snapshot) {
        if(!set){standingOrders->settings=*snapshot;standingOrders->outcome=m::StandingOrdersOutcome::None;status=m::ManagementStatus::Ok;}
        else {
          const auto outcome=df3d_standing::setWorkshop(query.setting_id(),query.expected_value(),query.value());
          if(outcome==df3d_standing::EditOutcome::Stale)standingOrders->outcome=m::StandingOrdersOutcome::Stale;
          else if(outcome==df3d_standing::EditOutcome::Applied) {
            // Safe-point scalar assignment: no allocation or native work follows
            // the write while completing this owned, fixed-size receipt.
            (*snapshot)[size_t(query.setting_id())].value=uint8_t(query.value());
            standingOrders->settings=*snapshot;standingOrders->outcome=m::StandingOrdersOutcome::Applied;
            mutated=true;status=m::ManagementStatus::Ok;
          }
        }
      }
    } catch(...) {standingOrders.emplace();}
    publish();return;
  }
  if(r->action()==m::ManagementAction::WorkDetailSettingsRead || r->action()==m::ManagementAction::WorkDetailSettingsToggle) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& query=*r->work_detail_settings();
    const bool toggle=r->action()==m::ManagementAction::WorkDetailSettingsToggle;
    try {
      const auto receipt=df3d_production::workDetailReceipt(query.detail_index());
      if(receipt && *receipt==query.expected_revision() && df::global::game) {
        auto* detail=df::global::plotinfo->labor_info.work_details[size_t(query.detail_index())];
        const bool editable=!df::global::game->external_flag.bits.automatic_professions_disabled;
        auto allowed=detail->allowed_labors;
        auto catalog=df3d_production::nativeWorkDetailSettings();
        if(catalog && catalog->size()==91 && (!toggle || (editable && df3d_production::nativeWorkDetailToggle(allowed,query.setting_id())))) {
          WorkDetailSettingsResult value;value.index=query.detail_index();value.editable=editable;value.noModify=detail->flags.bits.no_modify;
          value.catalog=std::move(*catalog);bool valid=true;
          for(auto& entry:value.catalog){entry.caption=DF2UTF(entry.caption);if(entry.caption.empty() || entry.caption.size()>512)valid=false;}
          value.labors.reserve(94);for(size_t id=0;id<allowed.size();++id)if(allowed[id])value.labors.push_back(int16_t(id));
          const auto after=df3d_production::workDetailReceipt(query.detail_index(),&allowed);
          if(valid && after) {
            value.revision=*after;workDetailSettings=std::move(value);
            // Every allocation/native call precedes this noexcept definition write.
            // Native settings leaves do not recalculate worker professions/labors.
            if(toggle)detail->allowed_labors=allowed;
            status=m::ManagementStatus::Ok;
          }
        }
      }
    } catch(...) {workDetailSettings.reset();}
    publish();return;
  }
  if(r->action()==m::ManagementAction::WorkDetailWorkersQuery) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& query=*r->work_detail_workers();
    try {
      const auto revision=df3d_production::workDetailReceipt(query.detail_index());
      if(revision && *revision==query.expected_revision()) {
        std::vector<df3d_production::WorkDetailSort> sorts;
        for(const auto* sort:*query.sorts())sorts.push_back({int(sort->column()),sort->descending()});
        auto ids=df3d_production::queryWorkDetailWorkers(query.detail_index(),sorts,
            std::string(query.query_bytes()->begin(),query.query_bytes()->end()));
        if(ids && ids->size()<=m::kResidentsQueryUnits) {
          residents=std::move(*ids);status=m::ManagementStatus::Ok;
        }
      }
    } catch(...) {residents.reset();}
    publish();return;
  }
  if(r->action()==m::ManagementAction::ResidentsQuery) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& query=*r->residents();
    try {
      auto ids=df3d_residents::queryResidents(int(query.sort()),query.descending(),
          std::string(query.query_bytes()->begin(),query.query_bytes()->end()));
      if(ids && ids->size()<=m::kResidentsQueryUnits) {
        residents=std::move(*ids);status=m::ManagementStatus::Ok;
      }
    } catch(...) {residents.reset();}
    publish();return;
  }
  if(r->action()==m::ManagementAction::CreatureAnimalEdit) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& query=*r->creature_animal();
    creatureAnimal.emplace();auto& result=*creatureAnimal;
    result.unitId=query.unit_id();result.animalId=query.animal_id();result.assigned=query.assigned();
    const auto outcome=df3d_creature::editAnimalAssignment(df::unit::find(result.unitId),result.animalId,query.expected_revision(),result.assigned);
    using O=df3d_creature::AnimalEditOutcome;
    if(outcome==O::Applied) {
      result.outcome=m::CreatureAnimalOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;
    } else if(outcome==O::Unavailable)result.outcome=m::CreatureAnimalOutcome::Unavailable;
    else if(outcome==O::Unknown){result.outcome=m::CreatureAnimalOutcome::Unknown;mutated=true;}
    publish();return;
  }
  if(r->action()==m::ManagementAction::CreatureLocationRemove) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& query=*r->creature_location();
    creatureLocation.emplace();auto& result=*creatureLocation;
    result.unitId=query.unit_id();result.occupationId=query.occupation_id();
    const auto outcome=df3d_creature::removeLocationAssignment(df::unit::find(result.unitId),result.occupationId,query.expected_revision());
    using O=df3d_creature::LocationRemoveOutcome;
    if(outcome==O::Applied) {
      result.outcome=m::CreatureLocationOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;
    } else if(outcome==O::Unavailable)result.outcome=m::CreatureLocationOutcome::Unavailable;
    else if(outcome==O::Unknown){result.outcome=m::CreatureLocationOutcome::Unknown;mutated=true;}
    publish();return;
  }
  if(r->action()==m::ManagementAction::CreatureWorkshopRemove) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& query=*r->creature_workshop();
    creatureWorkshop.emplace();auto& result=*creatureWorkshop;
    result.unitId=query.unit_id();result.buildingId=query.building_id();
    const auto outcome=df3d_creature::removeWorkshopAssignment(df::unit::find(result.unitId),result.buildingId,query.expected_revision());
    if(outcome==df3d_creature::WorkshopRemoveOutcome::Applied) {
      result.outcome=m::CreatureWorkshopOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;
    } else if(outcome==df3d_creature::WorkshopRemoveOutcome::Unavailable)result.outcome=m::CreatureWorkshopOutcome::Unavailable;
    publish();return;
  }
  if(r->action()==m::ManagementAction::CreatureKnowledgeRead) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto& query=*r->creature_knowledge();
    creatureKnowledge.emplace();auto& result=*creatureKnowledge;
    result.unitId=query.unit_id();result.kind=query.kind();result.id=query.id();
    if(auto* selected=df::unit::find(result.unitId)) {
      result.outcome=m::CreatureKnowledgeOutcome::Unavailable;
      const auto text=df3d_creature::selectedKnowledgeDetail(selected,result.kind,result.id);
      if(text) {
        auto utf8=DF2UTF(*text);
        if(utf8.size()<=65536 && utf8.find('\0')==std::string::npos) {
          result.text=std::move(utf8);result.outcome=m::CreatureKnowledgeOutcome::Ready;
          status=m::ManagementStatus::Ok;
        }
      }
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::CreatureExpelRead || r->action()==m::ManagementAction::CreatureExpelApply) {
    message.clear();status=m::ManagementStatus::Rejected;creatureExpel.emplace();
    const auto& request=*r->creature_expel();auto* selected=df::unit::find(request.unit_id());
    if(r->action()==m::ManagementAction::CreatureExpelRead) {
      auto preview=df3d_creature::expelPreview(selected);
      if(preview && preview->unitId>=0) {
        bool complete=true;
        for(const auto& row:preview->units) {
          ResidentAppearanceRecipe icon;icon.collect(df::unit::find(row.id),true);
          if(icon.layers.empty()){complete=false;break;}
          creatureExpel->icons.push_back(std::move(icon));
        }
        if(complete) {
          creatureExpel->preview=std::move(preview);creatureExpel->outcome=m::CreatureExpelOutcome::Ready;
          status=m::ManagementStatus::Ok;
        } else {creatureExpel->icons.clear();creatureExpel->outcome=m::CreatureExpelOutcome::Unsupported;}
      } else if(!preview)creatureExpel->outcome=m::CreatureExpelOutcome::Unsupported;
    } else {
      const std::vector<int32_t> expected(request.expected_unit_ids()->begin(),request.expected_unit_ids()->end());
      const auto outcome=df3d_creature::applyExpel(selected,request.destination_id(),expected);
      switch(outcome) {
        case df3d_creature::ExpelOutcome::Unsupported:creatureExpel->outcome=m::CreatureExpelOutcome::Unsupported;break;
        case df3d_creature::ExpelOutcome::Rejected:break;
        case df3d_creature::ExpelOutcome::Applied:creatureExpel->outcome=m::CreatureExpelOutcome::Applied;status=m::ManagementStatus::Ok;mutated=true;break;
        case df3d_creature::ExpelOutcome::Unknown:creatureExpel->outcome=m::CreatureExpelOutcome::Unknown;mutated=true;break;
      }
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::CreatureLocate || r->action()==m::ManagementAction::CreatureSheetLocate) {
    message.clear();status=m::ManagementStatus::Rejected;
    const auto id=r->creature()->unit_id();
    const bool sheet=r->action()==m::ManagementAction::CreatureSheetLocate;
    const auto position=sheet?df3d_creature::sheetPosition(df::unit::find(id)):df3d_creature::followPosition(df::unit::find(id));
    if(position && (sheet?position->x!=-30000:(position->isValid() && position->x>=0 && position->y>=0 && position->z>=0))) {
      creaturePosition=std::make_pair(id,*position);status=m::ManagementStatus::Ok;
    }
    publish();return;
  }
  if(r->action()==m::ManagementAction::CreatureHeaderRead || r->action()==m::ManagementAction::CreatureHeaderEdit) {
    message.clear();status=m::ManagementStatus::Rejected;creatureHeader.emplace();
    const auto& request=*r->creature_header();
    auto visible=[&]() -> df::unit* {
      auto* unit=df::unit::find(request.unit_id());
      if(!unit || !Units::isActive(unit))return nullptr;
      const auto p=Units::getPosition(unit);
      auto* block=Maps::isValidTilePos(p.x,p.y,p.z)?Maps::getTileBlock(p.x,p.y,p.z):nullptr;
      return block && !block->designation[p.x&15][p.y&15].bits.hidden?unit:nullptr;
    };
    if(auto* unit=visible()) {
      const auto before=df3d_creature::headerEditSnapshot(unit);
      if(before && r->action()==m::ManagementAction::CreatureHeaderRead) {
        creatureHeader->receipt=*before;creatureHeader->outcome=df3d_creature::HeaderEditOutcome::Completed;
      } else if(before) {
        const auto requested=request.name()->str();const auto bytes=UTF2DF(requested);
        if(DF2UTF(bytes)==requested) {
          *creatureHeader=df3d_creature::finishHeaderNameEdit(*before,request.expected_revision(),request.profession(),bytes,
              [&](const std::string& owned){return df3d_creature::setHeaderCustomName(unit,request.profession(),owned);},
              [&]{return df3d_creature::headerEditSnapshot(visible());});
          mutated=creatureHeader->mutated;
        }
      }
    }
    if(creatureHeader->outcome==df3d_creature::HeaderEditOutcome::Completed)status=m::ManagementStatus::Ok;
    publish();return;
  }
  if(r->action()==m::ManagementAction::WorldHover) {
    worldHoverTile=*r->origin();
    worldHover=df3d_hover::collect(r->origin()->x(),r->origin()->y(),r->origin()->z());
    message.clear();status=m::ManagementStatus::Ok;publish();return;
  }
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
  if(r->area() && (r->area()->operation()==m::AreaOperation::LocationDetails || r->area()->operation()==m::AreaOperation::LocationOpen || r->area()->operation()==m::AreaOperation::LocationAccess || r->area()->operation()==m::AreaOperation::LocationStaffEdit || r->area()->operation()==m::AreaOperation::LocationQuantity)) {
    const auto& a=*r->area();message.clear();areaPage.operation=a.operation();
    areaPage.capturedTick=df::global::world?df::global::world->frame_counter:-1;
    const bool entry=a.operation()==m::AreaOperation::LocationOpen;
    const bool access=a.operation()==m::AreaOperation::LocationAccess;
    const bool quantityEdit=a.operation()==m::AreaOperation::LocationQuantity;
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
    } else if(access || quantityEdit) {
      areaPage.locationEditOutcome=m::LocationEditOutcome::Rejected;
      if(details && df3d_area::locationDetailsRevision(*details)!=a.expected_revision()) {
        areaPage.locationEditOutcome=m::LocationEditOutcome::Stale;details.reset();
      } else if(details) {
        details.reset();mutated=true;areaPage.locationEditOutcome=m::LocationEditOutcome::Unknown;
        try {
          const auto outcome=quantityEdit?df3d_area::editNativeLocationQuantity(a.location_site_id(),a.location_id(),
              a.expected_revision(),uint8_t(a.quantity_id()),static_cast<df3d_area::LocationQuantityEdit>(a.quantity_mode()),a.quantity_value()):
              df3d_area::setNativeLocationAccess(a.location_site_id(),a.location_id(),
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
    lua_pushcfunction(L,areaSettingsCategories);lua_setfield(L,-2,"settings_categories");
    lua_pushcfunction(L,areaSettingsRows);lua_setfield(L,-2,"settings_rows");
    lua_pushcfunction(L,areaSettingsSummary);lua_setfield(L,-2,"settings_summary");
    lua_pushcfunction(L,areaSettingsHeader);lua_setfield(L,-2,"settings_header");
    lua_pushcfunction(L,areaLocationSet);lua_setfield(L,-2,"set_location");
    lua_pushcfunction(L,areaLocationCreate);lua_setfield(L,-2,"create_location");
    lua_pushcfunction(L,areaCreate);lua_setfield(L,-2,"create_area");
    lua_pushcfunction(L,areaRemove);lua_setfield(L,-2,"remove_area");
    lua_pushcfunction(L,areaRepaint);lua_setfield(L,-2,"repaint");
    lua_pushcfunction(L,areaLink);lua_setfield(L,-2,"link_areas");
    lua_pushcfunction(L,areaLinkTarget);lua_setfield(L,-2,"link_target");
    lua_pushcfunction(L,areaSquadUse);lua_setfield(L,-2,"squad_use");
    lua_pushcfunction(L,areaAssignUnit);lua_setfield(L,-2,"assign_unit");
    lua_pushcfunction(L,areaAssignItem);lua_setfield(L,-2,"assign_item");
    lua_pushcfunction(L,areaSetOwner);lua_setfield(L,-2,"set_owner");
    lua_pushcfunction(L,areaAnimalCandidates);lua_setfield(L,-2,"animal_candidates");
    lua_pushcfunction(L,areaSquadCandidates);lua_setfield(L,-2,"squad_candidates");
    lua_pushcfunction(L,areaSquadName);lua_setfield(L,-2,"squad_name");
    lua_pushcfunction(L,areaSquadSymbol);lua_setfield(L,-2,"squad_symbol");
      lua_pushcfunction(L,areaAnimalItemText);lua_setfield(L,-2,"animal_item_text");
      lua_pushcfunction(L,areaAnimalItemColor);lua_setfield(L,-2,"animal_item_color");
      lua_pushcfunction(L,areaAnimalItemIcon);lua_setfield(L,-2,"animal_item_icon");
      lua_pushcfunction(L,areaAnimalStatus);lua_setfield(L,-2,"animal_status");
      lua_pushcfunction(L,areaAnimalContainer);lua_setfield(L,-2,"animal_container");
      lua_pushcfunction(L,areaAnimalRestraint);lua_setfield(L,-2,"animal_restraint");
      lua_pushcfunction(L,areaAnimalUnitDisplay);lua_setfield(L,-2,"animal_unit_display");
      lua_pushcfunction(L,areaOwnerEligible);lua_setfield(L,-2,"owner_eligible");
    lua_pushcfunction(L,areaNewOwnerEligible);lua_setfield(L,-2,"new_owner_eligible");
    lua_pushcfunction(L,areaOwnerQuery);lua_setfield(L,-2,"owner_query");
    lua_pushcfunction(L,areaOwnerOrderFacts);lua_setfield(L,-2,"owner_order_facts");
    lua_pushcfunction(L,areaOwnerDisplay);lua_setfield(L,-2,"owner_display");
  }
  if(citizenAction(action)) {
    lua_pushcfunction(L,[](lua_State*)->int {citizenWriteStarted=true;return 0;});
    lua_setfield(L,-2,"mark_write");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto index=int32_t(luaL_checkinteger(state,1));
      if(workDetailHoldingCount>=workDetailHolding.size())return luaL_error(state,"Work-detail retirement storage unavailable");
      bool applied=false;
      try {applied=df3d_production::nativeWorkDetailDelete(index,workDetailHolding[workDetailHoldingCount],&citizenWriteStarted);}
      catch(...) {
        if(workDetailHolding[workDetailHoldingCount]){++workDetailHoldingCount;mutated=true;}
        return luaL_error(state,"Native work-detail deletion outcome uncertain");
      }
      if(!applied)return luaL_error(state,"Native work-detail deletion unavailable");
      ++workDetailHoldingCount;mutated=true;
      return 0;
    });lua_setfield(L,-2,"work_detail_delete");
    lua_pushcfunction(L,[](lua_State* state)->int {
      bool applied=false;
      try {applied=df3d_production::nativeWorkDetailEdit(int32_t(luaL_checkinteger(state,1)),int32_t(luaL_checkinteger(state,2)),lua_toboolean(state,3),&citizenWriteStarted);}
      catch(...) {return luaL_error(state,"Native work-detail edit outcome uncertain");}
      if(!applied)return luaL_error(state,"Native work-detail edit unavailable");
      return 0;
    });lua_setfield(L,-2,"work_detail_edit");
    lua_pushcfunction(L,[](lua_State* state)->int {
      bool applied=false;
      try {applied=df3d_production::nativeWorkDetailMembership(int32_t(luaL_checkinteger(state,1)),int32_t(luaL_checkinteger(state,2)),lua_toboolean(state,3),&citizenWriteStarted);}
      catch(...) {return luaL_error(state,"Native work-detail membership outcome uncertain");}
      if(!applied)return luaL_error(state,"Native work-detail membership unavailable");
      return 0;
    });lua_setfield(L,-2,"work_detail_membership");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_production::nativeWorkDetailDefaults();
      if(!value)return luaL_error(state,"Native work-detail defaults unavailable");
      lua_pushlstring(state,value->name.data(),value->name.size());lua_pushinteger(state,value->icon);return 2;
    });lua_setfield(L,-2,"work_detail_defaults");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto eligible=df3d_creature::laborEligible(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!eligible)return luaL_error(state,"Native labor eligibility unavailable");
      lua_pushboolean(state,*eligible);return 1;
    });lua_setfield(L,-2,"labor_eligible");
    field(L,"restart_recalc",citizenRecalcPending && citizenHelperGeneration!=helpers.generation());
    citizenHelperGeneration=helpers.generation();
  }
  if(r->creature()) field(L,"unit_id",r->creature()->unit_id());
  if(action==m::ManagementAction::CreatureInspect) {
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto rows=df3d_creature::overviewHealth(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!rows)return luaL_error(state,"Native creature health status unavailable");
      lua_newtable(state);int index=0;
      for(const auto& row:*rows) {
        lua_newtable(state);field(state,"text",row.text);field(state,"color",row.color);field(state,"flash",row.flash);
        lua_rawseti(state,-2,++index);
      }
      return 1;
    });
    lua_setfield(L,-2,"overview_health");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_creature::noOfficeFallback(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!value)return luaL_error(state,"Native creature office status unavailable");
      lua_pushlstring(state,value->status.data(),value->status.size());
      lua_pushlstring(state,value->position.data(),value->position.size());
      lua_pushinteger(state,value->color);return 3;
    });
    lua_setfield(L,-2,"office_fallback");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto values=df3d_creature::requiredRooms(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!values)return luaL_error(state,"Native creature room requirements unavailable");
      const auto actual=df3d_creature::actualRooms(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!actual)return luaL_error(state,"Native creature room values unavailable");
      const auto warning=df3d_creature::roomWarning(*values,*actual);
      if(!warning)return luaL_error(state,"Native creature room warning unavailable");
      lua_newtable(state);int index=0;
      for(auto value:*values){lua_pushinteger(state,value);lua_rawseti(state,-2,++index);}
      lua_newtable(state);index=0;
      for(auto value:*actual){lua_pushinteger(state,value);lua_rawseti(state,-2,++index);}
      lua_pushlstring(state,warning->text.data(),warning->text.size());lua_pushinteger(state,warning->color);
      return 4;
    });
    lua_setfield(L,-2,"room_requirements");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto rows=df3d_creature::individualRooms(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!rows)return luaL_error(state,"Native creature room list unavailable");
      lua_newtable(state);int index=0;
      for(const auto& row:*rows){lua_newtable(state);field(state,"id",row.id);field(state,"kind",row.kind);
        field(state,"value",row.value);field(state,"subtype",row.subtype);field(state,"caption",row.caption);
        field(state,"name",row.name);field(state,"requirement",row.requirement);field(state,"status",row.status);
        lua_rawseti(state,-2,++index);}
      return 1;
    });
    lua_setfield(L,-2,"room_list");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto rows=df3d_creature::laborWorkshops(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!rows)return luaL_error(state,"Native creature workshop list unavailable");
      lua_newtable(state);int index=0;
      for(const auto& row:*rows){lua_newtable(state);field(state,"id",row.id);field(state,"type",row.type);
        field(state,"subtype",row.subtype);field(state,"custom",row.custom);field(state,"caption",row.caption);
        field(state,"x",row.x);field(state,"y",row.y);field(state,"z",row.z);
        lua_pushinteger(state,lua_Integer(row.revision));lua_setfield(state,-2,"revision");lua_rawseti(state,-2,++index);}
      return 1;
    });lua_setfield(L,-2,"workshop_list");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto rows=df3d_creature::laborLocations(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!rows)return luaL_error(state,"Native creature location list unavailable");
      lua_newtable(state);int index=0;
      for(const auto& row:*rows){lua_newtable(state);field(state,"id",row.id);field(state,"type",row.type);
        field(state,"site_id",row.siteId);field(state,"location_id",row.locationId);field(state,"location_type",row.locationType);
        field(state,"tier",row.tier);field(state,"role",row.role);field(state,"name",row.name);
        field(state,"removable",row.removable?1:0);field(state,"zone_id",row.zoneId);
        lua_pushinteger(state,lua_Integer(row.revision));lua_setfield(state,-2,"revision");
        field(state,"x",row.x);field(state,"y",row.y);field(state,"z",row.z);lua_rawseti(state,-2,++index);}
      return 1;
    });lua_setfield(L,-2,"location_list");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto rows=df3d_creature::laborAnimals(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!rows)return luaL_error(state,"Native creature work-animal list unavailable");
      lua_newtable(state);int index=0;
      for(const auto& row:*rows){lua_newtable(state);field(state,"id",row.id);field(state,"caption",row.caption);
        field(state,"assigned",row.assigned?1:0);field(state,"owner_id",row.ownerId);
        lua_pushinteger(state,lua_Integer(row.revision));lua_setfield(state,-2,"revision");
        field(state,"x",row.position.x);field(state,"y",row.position.y);field(state,"z",row.position.z);lua_rawseti(state,-2,++index);}
      return 1;
    });lua_setfield(L,-2,"work_animal_list");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_creature::militaryKills(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!value)return luaL_error(state,"Native creature kill history unavailable");
      lua_pushlstring(state,value->data(),value->size());return 1;
    });lua_setfield(L,-2,"military_kills");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto rows=df3d_creature::nativeRelations(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!rows)return luaL_error(state,"Native creature relations unavailable");
      lua_newtable(state);int index=0;
      for(const auto& row:*rows) {
        lua_newtable(state);field(state,"hf_id",row.historicalFigureId);field(state,"unit_id",row.unitId);
        field(state,"caption",row.caption);field(state,"description",row.description);field(state,"description_color",row.descriptionColor);
        field(state,"family_type",row.familyType);field(state,"social_type",row.socialType);field(state,"priority",row.priority);
        if(auto* target=df::unit::find(row.unitId)){field(state,"x",target->pos.x);field(state,"y",target->pos.y);field(state,"z",target->pos.z);}
        if(row.nameColor) {
          lua_newtable(state);
          lua_newtable(state);for(int i=0;i<3;++i){lua_pushinteger(state,row.nameColor->color[i]);lua_rawseti(state,-2,i+1);}lua_setfield(state,-2,"color");
          lua_newtable(state);for(int i=0;i<3;++i){lua_pushinteger(state,row.nameColor->alternate[i]);lua_rawseti(state,-2,i+1);}lua_setfield(state,-2,"alternate");
          field(state,"effect",int(row.nameColor->effect));field(state,"source",int(row.nameColor->source));lua_setfield(state,-2,"name_color");
        }
        lua_rawseti(state,-2,++index);
      }
      return 1;
    });lua_setfield(L,-2,"relations");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto rows=df3d_creature::nativeGroups(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!rows)return luaL_error(state,"Native creature groups unavailable");
      lua_newtable(state);int index=0;
      for(const auto& row:*rows) {
        lua_newtable(state);field(state,"entity_id",row.entityId);field(state,"link_type",row.linkType);
        field(state,"position_id",row.positionId);field(state,"assignment_id",row.assignmentId);
        field(state,"spouse",row.spouse?1:0);field(state,"reputation",row.reputation);field(state,"reputation_level",row.reputationLevel);
        field(state,"caption",row.caption);field(state,"type_caption",row.typeCaption);field(state,"role",row.role);
        lua_rawseti(state,-2,++index);
      }
      return 1;
    });lua_setfield(L,-2,"groups");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto text=df3d_creature::thoughtCircumstance(df::unit::find(int32_t(luaL_checkinteger(state,1))),
        int32_t(luaL_checkinteger(state,2)),int32_t(luaL_checkinteger(state,3)),int32_t(luaL_checkinteger(state,4)),lua_toboolean(state,5)!=0);
      if(!text)return luaL_error(state,"Native thought description unavailable");
      lua_pushlstring(state,text->data(),text->size());return 1;
    });lua_setfield(L,-2,"thought_circumstance");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto text=df3d_creature::personalityValues(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!text)return luaL_error(state,"Native personality values unavailable");
      lua_pushlstring(state,text->data(),text->size());return 1;
    });lua_setfield(L,-2,"personality_values");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto text=df3d_creature::personalityTraits(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!text)return luaL_error(state,"Native personality traits unavailable");
      lua_pushlstring(state,text->data(),text->size());return 1;
    });lua_setfield(L,-2,"personality_traits");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto text=df3d_creature::personalityPreferences(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!text)return luaL_error(state,"Native personality preferences unavailable");
      lua_pushlstring(state,text->data(),text->size());return 1;
    });lua_setfield(L,-2,"personality_preferences");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto text=df3d_creature::personalityNeeds(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!text)return luaL_error(state,"Native personality needs unavailable");
      lua_pushlstring(state,text->data(),text->size());return 1;
    });lua_setfield(L,-2,"personality_needs");
    lua_pushcfunction(L,([](lua_State* state)->int {
      const auto page=df3d_creature::militarySquad(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!page)return luaL_error(state,"Native creature squad unavailable");
      lua_newtable(state);field(state,"id",page->id);field(state,"caption",page->caption);
      field(state,"short_name",page->shortName);field(state,"order",page->order);field(state,"order_color",page->color);
      const char* keys[]={"symbol","foreground_r","foreground_g","foreground_b","background_r","background_g","background_b"};
      for(size_t i=0;i<7;++i)field(state,keys[i],int(page->symbol[i]));return 1;
    }));lua_setfield(L,-2,"military_squad");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto page=df3d_creature::militaryUniform(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!page)return luaL_error(state,"Native creature uniform unavailable");
      lua_pushboolean(state,page->hasSquad);lua_newtable(state);int index=0;
      for(const auto& row:page->rows){lua_newtable(state);field(state,"id",row.id);field(state,"caption",row.caption);field(state,"role",row.role);
        field(state,"resolved",row.resolved?1:0);field(state,"carried",row.carried?1:0);
        field(state,"item_type",row.itemType);
        if(row.appearance){const auto& a=*row.appearance;lua_newtable(state);
          field(state,"material_token",a.materialToken);field(state,"subtype_raw",a.subtypeRaw);field(state,"color_token",a.colorToken);
          field(state,"stack",a.stack);field(state,"flags",a.flags);
          if(a.instrumentFamily>=0){lua_newtable(state);field(state,"family",a.instrumentFamily);field(state,"placed",a.instrumentPlaced);lua_setfield(state,-2,"instrument");}
          lua_setfield(state,-2,"appearance");}
        field(state,"x",row.position.x);field(state,"y",row.position.y);field(state,"z",row.position.z);lua_rawseti(state,-2,++index);}
      return 2;
    });lua_setfield(L,-2,"military_uniform");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto values=df3d_creature::officeTitles(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!values)return luaL_error(state,"Native creature office titles unavailable");
      lua_newtable(state);int index=0;
      for(const auto& value:*values) {
        lua_newtable(state);field(state,"id",value.positionId);field(state,"entity_id",value.entityId);
        field(state,"spouse",value.spouse);field(state,"text",value.text);
        lua_rawseti(state,-2,++index);
      }
      return 1;
    });
    lua_setfield(L,-2,"office_titles");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_creature::headerStatus(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!value)return luaL_error(state,"Native creature header status unavailable");
      lua_pushlstring(state,value->text.data(),value->text.size());lua_pushinteger(state,value->color);return 2;
    });
    lua_setfield(L,-2,"header_status");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_creature::headerActivity(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!value)return luaL_error(state,"Native creature header activity unavailable");
      lua_pushlstring(state,value->text.data(),value->text.size());
      lua_pushinteger(state,value->foreground+(value->bright?8:0));lua_pushinteger(state,value->background);return 3;
    });
    lua_setfield(L,-2,"header_activity");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_creature::overviewSkillProfession(int16_t(luaL_checkinteger(state,1)));
      if(!value)return luaL_error(state,"Native skill profession unavailable");
      lua_pushinteger(state,*value);return 1;
    });
    lua_setfield(L,-2,"skill_profession");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_creature::headerName(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!value)return luaL_error(state,"Native creature header name unavailable");
      lua_newtable(state);field(state,"combined",value->combined);field(state,"name",value->name);field(state,"profession",value->profession);
      field(state,"translated_name",value->translated);
      field(state,"effect",int(value->color.effect));field(state,"source",int(value->color.source));
      field(state,"foreground",int(value->color.color[0]));field(state,"background",int(value->color.color[1]));field(state,"bright",int(value->color.color[2]));
      field(state,"alternate_foreground",int(value->color.alternate[0]));field(state,"alternate_background",int(value->color.alternate[1]));field(state,"alternate_bright",int(value->color.alternate[2]));
      return 1;
    });
    lua_setfield(L,-2,"header_name");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_creature::customizeCaptions(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!value)return luaL_error(state,"Native creature Customize captions unavailable");
      lua_pushlstring(state,value->name.data(),value->name.size());
      lua_pushlstring(state,value->profession.data(),value->profession.size());return 2;
    });
    lua_setfield(L,-2,"customize_captions");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_creature::expelEligible(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!value){lua_pushnil(state);return 1;}
      lua_pushboolean(state,*value);return 1;
    });
    lua_setfield(L,-2,"expel_eligible");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_creature::overviewStatus(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!value)return luaL_error(state,"Native creature Overview status unavailable");
      lua_pushboolean(state,value->personality);lua_pushboolean(state,value->needs);
      lua_pushlstring(state,value->squad.data(),value->squad.size());
      lua_pushboolean(state,value->assignedSquad);
      lua_pushlstring(state,value->focus.data(),value->focus.size());
      lua_pushinteger(state,value->focusColor);return 6;
    });
    lua_setfield(L,-2,"overview_status");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto value=df3d_creature::haulingSummary(df::unit::find(int32_t(luaL_checkinteger(state,1))));
      if(!value)return luaL_error(state,"Native creature hauling summary unavailable");
      lua_pushinteger(state,value->itemId);
      // creature.lua's fact boundary performs the single DF-to-UTF8 conversion.
      lua_pushlstring(state,value->text.data(),value->text.size());return 2;
    });
    lua_setfield(L,-2,"hauling_summary");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto* unit=df::unit::find(int32_t(luaL_checkinteger(state,1)));
      const auto inventory=df3d_creature::inventoryDescriptions(unit);
      const auto spatters=df3d_creature::inventorySpatters(unit);
      if(!inventory||!spatters)return luaL_error(state,"Native creature Items descriptions unavailable");
      lua_newtable(state);int index=0;
      const auto append=[&](int kind,int id,int parent,const std::string& caption,const std::string& role,int indicator=-1) {
        lua_newtable(state);field(state,"kind",kind);field(state,"id",id);field(state,"parent",parent);
        field(state,"indicator",indicator);
        // The creature fact boundary converts raw DF text to UTF8 once.
        lua_pushlstring(state,caption.data(),caption.size());lua_setfield(state,-2,"caption");
        lua_pushlstring(state,role.data(),role.size());lua_setfield(state,-2,"role");
        lua_rawseti(state,-2,++index);
      };
      for(const auto& row:*inventory) {
        append(0,row.id,-1,row.caption,row.role,row.indicator);
        for(const auto& child:row.contents)append(child.kind,child.id,row.id,child.caption,"");
      }
      for(const auto& row:*spatters)append(3,-1,-1,row.caption,row.bodyPartCaption);
      return 1;
    });
    lua_setfield(L,-2,"inventory_rows");
  }
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
  if(action==m::ManagementAction::Preview || action==m::ManagementAction::Place) {
    lua_pushcfunction(L,df3d_construction::nativeMaterialRequirements);
    lua_setfield(L,-2,"native_material_recipe");
  }
  if(action==m::ManagementAction::ConstructionMaterials || action==m::ManagementAction::Place) {
    lua_pushcfunction(L,df3d_construction::nativeMaterialCandidates);
    lua_setfield(L,-2,"native_material_candidates");
  }
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
    field(L,"candidate_limit",a->candidate_limit());
    if(const auto* bytes=a->query_bytes()) {
      lua_pushlstring(L,reinterpret_cast<const char*>(bytes->data()),bytes->size());lua_setfield(L,-2,"query_bytes");
    }
    field(L,"operation",int(a->operation()));field(L,"expected_revision",a->expected_revision());field(L,"expected_list_revision",a->expected_list_revision());field(L,"category_opening",a->category_opening());
    field(L,"list_key",a->list_key()?a->list_key()->str():"");field(L,"row_key",a->row_key()?a->row_key()->str():"");
    field(L,"scope",a->scope());field(L,"value",a->value());field(L,"preset",a->preset());field(L,"name",a->name()?a->name()->str():"");
    field(L,"paint_mode",a->paint_mode());field(L,"paint_z",a->paint_z());
    field(L,"location_id",a->location_id());field(L,"location_kind",a->location_kind());field(L,"profession",a->profession());
    field(L,"deity_kind",a->deity_kind());field(L,"deity_id",a->deity_id());
    field(L,"item_id",a->item_id());field(L,"unit_id",a->unit_id());field(L,"assign",a->assign());field(L,"squad_id",a->squad_id());field(L,"squad_use",a->squad_use());
    field(L,"organic",a->organic());field(L,"inorganic",a->inorganic());field(L,"candidate_kind",a->candidate_kind());
    field(L,"sort",a->sort());field(L,"sort_descending",a->sort_descending());
    lua_newtable(L);if(a->spans()){int i=0;for(const auto* v:*a->spans()) {
      lua_newtable(L);field(L,"x",v->x());field(L,"y",v->y());field(L,"length",v->length());lua_rawseti(L,-2,++i);
    }}lua_setfield(L,-2,"spans");
    lua_newtable(L);if(const auto* z=a->zone_settings()) {
      field(L,"pond_mode",z->pond_mode());field(L,"facing",z->facing());field(L,"tomb_citizens",z->tomb_citizens());
      field(L,"tomb_pets",z->tomb_pets());field(L,"gather_trees",z->gather_trees());field(L,"gather_shrubs",z->gather_shrubs());field(L,"gather_fallen",z->gather_fallen());
    }lua_setfield(L,-2,"zone_settings");
    lua_setfield(L,-2,"area");
  }
  if(const auto* p=r->production()) {
    lua_pushcfunction(L,[](lua_State* state)->int {
      auto* job=Lua::GetDFObject<df::job>(state,1);
      auto* building=df::building::find(int32_t(luaL_checkinteger(state,2)));
      if(!job || !df3d_production::workshopRequirements(*job,building))
        return luaL_error(state,"Native workshop requirements unavailable");
      return 0;
    });lua_setfield(L,-2,"workshop_requirements");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto* job=Lua::GetDFObject<df::job>(state,1);
      const auto caption=job?df3d_production::workshopJobCaption(*job):std::nullopt;
      if(!caption)return luaL_error(state,"Native workshop caption unavailable");
      lua_pushlstring(state,caption->data(),caption->size());return 1;
    });lua_setfield(L,-2,"workshop_caption");
    lua_pushcfunction(L,[](lua_State* state)->int {
      size_t leftSize=0;size_t rightSize=0;
      const char* left=luaL_checklstring(state,1,&leftSize);
      const char* right=luaL_checklstring(state,2,&rightSize);
      const auto less=df3d_production::workshopCaptionLess(std::string(left,leftSize),std::string(right,rightSize));
      if(!less)return luaL_error(state,"Native workshop ordering unavailable");
      lua_pushboolean(state,*less);return 1;
    });lua_setfield(L,-2,"workshop_caption_less");
    lua_pushcfunction(L,[](lua_State* state)->int {
      size_t captionSize=0;size_t querySize=0;
      const char* caption=luaL_checklstring(state,1,&captionSize);
      const char* query=luaL_checklstring(state,2,&querySize);
      const auto matches=df3d_production::workshopCaptionMatches(std::string(caption,captionSize),std::string(query,querySize));
      if(!matches)return luaL_error(state,"Native workshop search unavailable");
      lua_pushboolean(state,*matches);return 1;
    });lua_setfield(L,-2,"workshop_caption_matches");
    lua_pushcfunction(L,[](lua_State* state)->int {
      const auto allowed=df3d_production::workshopReactionAllowed(int32_t(luaL_checkinteger(state,1)));
      if(!allowed)return luaL_error(state,"Native reaction permission unavailable");
      lua_pushboolean(state,*allowed);return 1;
    });lua_setfield(L,-2,"workshop_reaction_allowed");
    lua_pushcfunction(L,[](lua_State* state)->int {
      auto* shop=df::building::find(int32_t(luaL_checkinteger(state,1)));
      const auto rows=df3d_production::workshopReactionRows(shop,"");
      if(!rows)return luaL_error(state,"Native workshop reaction choices unavailable");
      lua_newtable(state);int index=0;
      for(const auto& row:*rows) {
        lua_newtable(state);field(state,"raw_index",row.rawIndex);field(state,"code",row.code);
        field(state,"caption",row.caption);field(state,"objection",row.objection);
        lua_pushboolean(state,row.available);lua_setfield(state,-2,"available");
        lua_rawseti(state,-2,++index);
      }
      return 1;
    });lua_setfield(L,-2,"workshop_reactions");
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
    retireUncertainCitizenReply();
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
    retireUncertainCitizenReply();
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
      }
      if(native && operation==m::AreaOperation::Paint && native==areaPaintRetired) {
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
             action==m::ManagementAction::AreaUpdate || action==m::ManagementAction::AreaDelete || action==m::ManagementAction::AreaLink || action==m::ManagementAction::ProductionQueue || action==m::ManagementAction::ProductionJobEdit || action==m::ManagementAction::FarmEdit))
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
    lua_getfield(L,-1,"query_bytes");const bool rawQuery=!lua_isnil(L,-1);lua_pop(L,1);
    if(rawQuery)areaPage.queryBytes=str("query_bytes");
    areaPage.listKey=str("list_key");areaPage.query=str("query");areaPage.candidateKind=uint8_t(number(L,"candidate_kind"));
    areaPage.sort=uint8_t(number(L,"sort"));areaPage.sortDescending=boolean(L,"sort_descending");
    areaPage.listRevision=number(L,"list_revision");areaPage.buildPhase=uint8_t(number(L,"build_phase"));
    areaPage.settingsCount=int32_t(number(L,"settings_count",-1));
    areaPage.buildDone=uint32_t(number(L,"build_done"));areaPage.buildTotal=uint32_t(number(L,"build_total"));
    areaPage.omitted=uint32_t(number(L,"omitted"));areaPage.capturedTick=number(L,"captured_tick",-1);
    each("areas",[&]() {
      NativeArea a;
      a.id=int32_t(number(L,"id",-1));a.kind=int(number(L,"kind"));a.zone=int(number(L,"zone_type",-1));
      a.x=int(number(L,"x"));a.y=int(number(L,"y"));a.z=int(number(L,"z"));
      a.w=int(number(L,"width"));a.h=int(number(L,"height"));a.name=str("name");a.customName=str("custom_name");
      a.categories=uint32_t(number(L,"categories"));a.barrels=int(number(L,"barrels"));a.bins=int(number(L,"bins"));a.wheelbarrows=int(number(L,"wheelbarrows"));
      a.active=boolean(L,"active");a.linksOnly=boolean(L,"links_only");a.ownerAllowed=boolean(L,"owner_allowed");
      a.owner=int32_t(number(L,"owner_id",-1));a.ownerName=str("owner_name");
      a.ownerProfession=str("owner_profession");a.ownerSex=int8_t(number(L,"owner_sex",-1));
      a.locationKind=uint8_t(number(L,"location_kind",0));
      a.revision=number(L,"revision");a.zoneLabel=str("zone_label");a.locationId=int32_t(number(L,"location_id",-1));a.locationSiteId=int32_t(number(L,"location_site_id",-1));
      a.locationName=str("location_name");a.religion=str("religion");a.organic=int8_t(number(L,"organic",-1));a.inorganic=int8_t(number(L,"inorganic",-1));
      a.overlapping=int(number(L,"overlapping",-1));a.storageLimit=int32_t(number(L,"storage_limit",-1));a.tileCount=int32_t(number(L,"tile_count",-1));a.assignedCount=int32_t(number(L,"assigned_count",-1));
      lua_getfield(L,-1,"zone_settings");if(lua_istable(L,-1)) {
        a.zoneSettings={uint8_t(number(L,"pond_mode")),uint8_t(number(L,"facing")),int8_t(number(L,"tomb_citizens",-1)),
            int8_t(number(L,"tomb_pets",-1)),int8_t(number(L,"gather_trees",-1)),int8_t(number(L,"gather_shrubs",-1)),int8_t(number(L,"gather_fallen",-1))};
      }lua_pop(L,1);
      ints("extents",a.extents);ints("gives",a.gives);ints("takes",a.takes);areas.push_back(std::move(a));
    });
    each("choices",[&](){areaChoices.push_back({int32_t(number(L,"id",-1)),str("name"),str("label")});});
    each("settings",[&](){areaPage.settings.push_back({str("key"),str("label"),int32_t(number(L,"index",-1)),uint8_t(number(L,"kind")),uint8_t(number(L,"state")),boolean(L,"estimated")});});
    each("locations",[&](){areaPage.locations.push_back({int32_t(number(L,"id",-1)),str("name"),str("religion"),uint8_t(number(L,"location_kind")),int16_t(number(L,"guild_profession",-1)),int32_t(number(L,"location_tier",-1)),int32_t(number(L,"site_id",-1))});});
    each("candidates",[&](){
      NativeAreaCandidate row{int32_t(number(L,"id",-1)),str("name"),str("profession"),int8_t(number(L,"sex",-1)),int8_t(number(L,"squad_use",-1)),uint8_t(number(L,"mood")),boolean(L,"grazer"),boolean(L,"assigned")};
      row.entity=m::AreaCandidateEntity(number(L,"entity",0));
      lua_getfield(L,-1,"animal_status");
      if(lua_istable(L,-1))row.animalStatus=df3d_area::ZoneAnimalStatus{uint8_t(number(L,"kind")),uint8_t(number(L,"containment")),int32_t(number(L,"item_id",-1))};
      lua_pop(L,1);
      lua_getfield(L,-1,"animal_item_color");
      if(lua_istable(L,-1))row.animalItemColor=std::array<uint8_t,3>{uint8_t(number(L,"foreground")),uint8_t(number(L,"background")),uint8_t(number(L,"bright"))};
      lua_pop(L,1);
      lua_getfield(L,-1,"squad_symbol");
      if(lua_istable(L,-1))row.squadSymbol=std::array<uint8_t,7>{uint8_t(number(L,"index")),uint8_t(number(L,"foreground_r")),uint8_t(number(L,"foreground_g")),uint8_t(number(L,"foreground_b")),uint8_t(number(L,"background_r")),uint8_t(number(L,"background_g")),uint8_t(number(L,"background_b"))};
      lua_pop(L,1);
      lua_getfield(L,-1,"animal_restraint");
      if(lua_istable(L,-1))row.animalRestraint=df3d_area::ZoneAnimalRestraint{boolean(L,"rope"),str("solid_color")};
      lua_pop(L,1);
      lua_getfield(L,-1,"animal_container");
      if(lua_istable(L,-1)) {
        row.animalContainer.emplace();auto& c=*row.animalContainer;
        c.facts.materialFamily=uint8_t(number(L,"material_family"));c.facts.solidColor=str("solid_color");
        c.facts.occupantEntity=uint8_t(number(L,"occupant_entity"));c.facts.occupantId=int32_t(number(L,"occupant_id",-1));
        lua_getfield(L,-1,"occupant");
        if(lua_type(L,-1)==LUA_TSTRING) {
          const auto* image=flatbuffers::GetRoot<m::SelectionAppearance>(lua_tostring(L,-1));
          for(const auto* name:*image->tile_pages())c.occupant.pages.push_back(name->str());
          for(const auto* name:*image->palettes())c.occupant.palettes.push_back(name->str());
          for(const auto* layer:*image->layers())c.occupant.layers.push_back(*layer);
        }
        lua_pop(L,1);
      }
      lua_pop(L,1);
      lua_getfield(L,-1,"animal_display");
      if(lua_istable(L,-1)) {
        row.animalDisplay=NativeAnimalDisplay{uint16_t(number(L,"columns")),str("first_line"),str("second_line"),boolean(L,"combined_fits"),str("warning")};
        lua_getfield(L,-1,"name_color");
        row.animalDisplay->nameColor=df3d_area::ZoneOwnerNameColor{
          {uint8_t(number(L,"foreground")),uint8_t(number(L,"background")),uint8_t(number(L,"bright"))},
          {uint8_t(number(L,"alternate_foreground")),uint8_t(number(L,"alternate_background")),uint8_t(number(L,"alternate_bright"))},uint8_t(number(L,"effect")),0};
        lua_pop(L,1);
      }
      lua_pop(L,1);
      lua_getfield(L,-1,"owner_display");
      if(lua_istable(L,-1)) {
        row.ownerDisplay=NativeOwnerDisplay{uint16_t(number(L,"columns")),str("first_line"),str("second_line"),str("status"),int32_t(number(L,"room_value"))};
        lua_getfield(L,-1,"name_color");
        if(lua_istable(L,-1))row.ownerDisplay->nameColor=df3d_area::ZoneOwnerNameColor{
          {uint8_t(number(L,"foreground")),uint8_t(number(L,"background")),uint8_t(number(L,"bright"))},
          {uint8_t(number(L,"alternate_foreground")),uint8_t(number(L,"alternate_background")),uint8_t(number(L,"alternate_bright"))},uint8_t(number(L,"effect")),0};
        lua_pop(L,1);
      }
      lua_pop(L,1);
      lua_getfield(L,-1,"sheet_icon");
      if(lua_type(L,-1)==LUA_TSTRING) {
        // Result validation already checked this owned FlatBuffer before readback.
        const auto* image=flatbuffers::GetRoot<m::SelectionAppearance>(lua_tostring(L,-1));
        for(const auto* name:*image->tile_pages())row.sheetIcon.pages.push_back(name->str());
        for(const auto* name:*image->palettes())row.sheetIcon.palettes.push_back(name->str());
        for(const auto* layer:*image->layers())row.sheetIcon.layers.push_back(*layer);
      }
      lua_pop(L,1);areaPage.candidates.push_back(std::move(row));
    });
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
  if(action==m::ManagementAction::CreatureInspect) {
    creature_data::read(L,creature);
    if(ok && creature.id>=0) {
      auto* unit=df::unit::find(creature.id);
      size_t bytes=creature.name.size()+creature.species.size()+creature.profession.size()+creature.job.size(),rows=0;
      for(const auto& section:creature.sections){bytes+=section.reason.size();for(const auto& record:section.records){bytes+=record.name.size();for(const auto& fact:record.facts)bytes+=fact.key.size()+fact.text.size();}}
      for(const auto& page:creature.pages)bytes+=page.size();
      for(const auto& palette:creature.palettes)bytes+=palette.size();
      for(int page=0;page<5 && ok;++page) {
        const auto native=df3d_creature::healthPageProbe(unit,page);
        if(!native){ok=false;break;}
        std::vector<std::string> text;
        for(const auto& row:*native){
          auto value=DF2UTF(row);bytes+=value.size();
          if(value.size()>65536 || ++rows>4096 || bytes>131072){ok=false;break;}
          text.push_back(std::move(value));
        }
        if(ok)creature.healthPages.push_back(std::move(text));
      }
      if(ok && !df3d_creature::skillsCaptionReady())ok=false;
      size_t skillRows=0;
      for(int page=0;page<5 && ok;++page){
        const auto native=df3d_creature::skillsPageProbe(unit,page);
        if(!native){ok=false;break;}
        creature_data::CreatureSkillsPage target;target.kind=creature_data::CreatureSkillsPageKind(page);
        const size_t count=page==4?native->knowledgeTypes.size():native->skills.size();
        for(size_t i=0;i<count;++i){
          creature_data::CreatureSkillRow row;
          if(page==4){row.id=native->knowledgeIds[i];row.knowledgeType=native->knowledgeTypes[i];row.knowledgeBits=native->knowledgeBits[i];
            row.caption=DF2UTF(df3d_creature::nativeKnowledgeCaption(row.knowledgeType,row.id,row.knowledgeBits));
            row.subtitle=DF2UTF(df3d_creature::nativeKnowledgeCategory(row.knowledgeType,row.id));
          }else{row.id=native->skills[i];row.rating=native->values[i];row.rustValue=native->rustValues[i];
            row.caption=DF2UTF(df3d_creature::nativeSkillCaption(int16_t(row.id),row.rating,unit->race,unit->caste));
            const auto color=df3d_creature::nativeSkillColor(*unit,int16_t(row.id));
            if(!color || (*color)[0]>7 || (*color)[1]>7 || (*color)[2]>1){ok=false;break;}
            row.captionColor=int16_t((*color)[0]|((*color)[1]<<3)|((*color)[2]<<6));}
          bytes+=row.caption.size()+row.subtitle.size();
          if(++skillRows>4096 || row.caption.size()>4096 || row.subtitle.size()>4096 || bytes>131072){ok=false;break;}
          target.rows.push_back(std::move(row));
        }
        if(ok)creature.skillsPages.push_back(std::move(target));
      }
      if(!ok){creature={};message="Native creature payload unavailable or exceeds contract";}
    }
  }

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
  if(action>=m::ManagementAction::ProductionList && action<=m::ManagementAction::FarmEdit) {
    production.nextCursor=uint32_t(number(L,"next_cursor"));production.selectedBuilding=int32_t(number(L,"selected_building",-1));production.createdJob=int32_t(number(L,"created_job",-1));production.currentSeason=int8_t(number(L,"current_season",-1));production.detail=text(L,"detail");
    auto each=[&](const char* key,size_t cap,auto fn){lua_getfield(L,-1,key);if(lua_istable(L,-1)) for(size_t i=1;i<=lua_rawlen(L,-1)&&i<=cap;++i){lua_rawgeti(L,-1,i);fn();lua_pop(L,1);}lua_pop(L,1);};
    auto reqs=[&](){std::vector<ProductionRequirement> out;each("requirements",16,[&](){out.push_back({text(L,"description"),int32_t(number(L,"quantity")),int16_t(number(L,"item_type",-1))});});return out;};
    each("buildings",64,[&](){ProductionBuilding v;v.id=int32_t(number(L,"id",-1));v.x=int32_t(number(L,"x"));v.y=int32_t(number(L,"y"));v.z=int32_t(number(L,"z"));v.name=text(L,"name");v.kind=text(L,"kind");v.buildStage=int16_t(number(L,"build_stage"));v.maxStage=int16_t(number(L,"max_stage"));v.queueSize=uint16_t(number(L,"queue_size"));production.buildings.push_back(std::move(v));});
    each("recipes",128,[&](){
      ProductionRecipe row{text(L,"key"),text(L,"name"),reqs()};
      lua_getfield(L,-1,"availability");
      if(lua_istable(L,-1))row.availability=ProductionAvailability{boolean(L,"available"),text(L,"objection")};
      lua_pop(L,1);production.recipes.push_back(std::move(row));
    });
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
    construction.warnings=str("warnings",512);
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
            a.gem_shape_raw=str("gem_shape_raw",128);
            if(!a.gem_shape_raw.empty() && v.item_type!=1)invalid=true;
            a.slab_engraving=int8_t(n("slab_engraving",-2,26,-2));
            if(a.slab_engraving!=-2 && v.item_type!=87)invalid=true;
            a.instrument_family=int8_t(n("instrument_family",-1,3,-1));
            a.instrument_placed=int8_t(n("instrument_placed",-1,1,-1));
            if((a.instrument_family==-1)!=(a.instrument_placed==-1) ||
               (a.instrument_family!=-1 && v.item_type!=13))invalid=true;
            if(a.material_token.empty() || (a.flags & ~uint8_t(96)))invalid=true;
            lua_getfield(L,-1,"bedding");
            if(!lua_isnil(L,-1)) {
              if(!lua_istable(L,-1) || v.item_type!=8)invalid=true;
              else {
                a.bedding.sheet=int8_t(n("sheet",0,1,-1));a.bedding.pillow=int8_t(n("pillow",0,2,-1));
                a.bedding.baseColor=str("base_color",128);a.bedding.sheetColor=str("sheet_color",128);
              }
            }
            lua_pop(L,1);
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
  if(!ok)retireUncertainCitizenReply();
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
    if(kind==7){
      lua_pushcfunction(L,areaAnimalCandidates);lua_setfield(L,-2,"animal_candidates");
    lua_pushcfunction(L,areaSquadCandidates);lua_setfield(L,-2,"squad_candidates");
    lua_pushcfunction(L,areaSquadName);lua_setfield(L,-2,"squad_name");
    lua_pushcfunction(L,areaSquadSymbol);lua_setfield(L,-2,"squad_symbol");
      lua_pushcfunction(L,areaAnimalItemText);lua_setfield(L,-2,"animal_item_text");
      lua_pushcfunction(L,areaAnimalItemColor);lua_setfield(L,-2,"animal_item_color");
      lua_pushcfunction(L,areaAnimalItemIcon);lua_setfield(L,-2,"animal_item_icon");
      lua_pushcfunction(L,areaAnimalStatus);lua_setfield(L,-2,"animal_status");
      lua_pushcfunction(L,areaAnimalContainer);lua_setfield(L,-2,"animal_container");
      lua_pushcfunction(L,areaAnimalRestraint);lua_setfield(L,-2,"animal_restraint");
      lua_pushcfunction(L,areaAnimalUnitDisplay);lua_setfield(L,-2,"animal_unit_display");
      lua_pushcfunction(L,areaOwnerEligible);lua_setfield(L,-2,"owner_eligible");
      lua_pushcfunction(L,areaOwnerOrderFacts);lua_setfield(L,-2,"owner_order_facts");
      lua_pushcfunction(L,areaOwnerDisplay);lua_setfield(L,-2,"owner_display");
    }
    if(kind==4){
      field(L,"restart_recalc",citizenRecalcPending && citizenHelperGeneration!=helpers.generation());citizenHelperGeneration=helpers.generation();
      lua_pushcfunction(L,[](lua_State* state)->int {
        const auto eligible=df3d_creature::laborEligible(df::unit::find(int32_t(luaL_checkinteger(state,1))));
        if(!eligible)return luaL_error(state,"Native labor eligibility unavailable");
        lua_pushboolean(state,*eligible);return 1;
      });lua_setfield(L,-2,"labor_eligible");
    }
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
bool printStockpileLinkTarget(color_ostream& out,int32_t id,int16_t x,int16_t y,int16_t z,bool give) {
  auto* source=virtual_cast<df::building_stockpilest>(df::building::find(id));
  auto* block=Maps::isValidTilePos(x,y,z)?Maps::getTileBlock(x,y,z):nullptr;
  if(!source || !block || block->designation[x&15][y&15].bits.hidden)return false;
  const auto target=df3d_area::nativeStockpileLinkTarget(*source,x,y,z,give);
  if(!target)return false;
  out.print("{{\"id\":{}}}\n",*target?(*target)->id:-1);return true;
}
bool printStockpileSummaries(color_ostream& out,int32_t id,uint32_t categories) {
  auto* pile=virtual_cast<df::building_stockpilest>(df::building::find(id));
  if(!pile || !areaPresetInventoryFits(pile))return false;
  try {
    const auto states=df3d_area::nativeStockpileSummaries(pile->settings,categories);
    if(!states)return false;
    Json::Value result(Json::objectValue);
    result["states"]=Json::Value(Json::arrayValue);result["categories"]=Json::Value(Json::arrayValue);
    for(const auto state:states->states)result["states"].append(int(state));
    for(const auto state:states->categories)result["categories"].append(int(state));
    out.print("{}",Json::FastWriter().write(result));return true;
  } catch(...) {return false;}
}
bool printStockpileRows(color_ostream& out,int32_t id,int32_t mode,const std::string& filter,bool coldCache) {
  auto* pile=virtual_cast<df::building_stockpilest>(df::building::find(id));
  if(!pile || !areaPresetInventoryFits(pile))return false;
  try {
    size_t insertions=0;
    const auto rows=ownedStockpileRows(pile,mode,filter,coldCache?&insertions:nullptr);
    if(!rows)return false;
    Json::Value result(Json::arrayValue);
    for(const auto& row:*rows) {
      Json::Value value(Json::objectValue);
      value["field"]=row.field;value["index"]=Json::UInt64(row.index);value["name"]=DF2UTF(row.name);
      value["enabled"]=row.enabled;value["visible"]=row.visible;result.append(value);
    }
    if(coldCache){Json::Value probe;probe["rows"]=result;probe["cache_insertions"]=Json::UInt64(insertions);result=std::move(probe);}
    out.print("{}",Json::FastWriter().write(result));return true;
  } catch(...) {return false;}
}
bool printStockpileWoodRows(color_ostream& out,int32_t id,const std::string& filter) {
  auto* pile=virtual_cast<df::building_stockpilest>(df::building::find(id));
  if(!pile || !areaPresetInventoryFits(pile))return false;
  try {
    const auto rows=df3d_area::nativeStockpileWoodRows(pile->settings,filter);
    if(!rows)return false;
    Json::Value result(Json::arrayValue);
    for(const auto& row:*rows) {
      Json::Value value(Json::objectValue);
      value["index"]=Json::UInt64(row.index);value["name"]=DF2UTF(row.name);
      value["enabled"]=row.enabled;value["visible"]=row.visible;result.append(value);
    }
    out.print("{}",Json::FastWriter().write(result));return true;
  } catch(...) {return false;}
}
static bool printStockpileSettings(color_ostream& out,int32_t id,int32_t choice,bool category,
    std::optional<bool> header=std::nullopt) {
  auto* pile=virtual_cast<df::building_stockpilest>(df::building::find(id));
  if(!pile || !df::global::world)return false;
  if(!areaPresetInventoryFits(pile))return false;
  try {
    auto settings=header?df3d_area::nativeStockpileHeader(pile->settings,uint32_t(choice),*header):
        category?df3d_area::nativeStockpileCategory(pile->settings,uint32_t(choice)):
        df3d_area::nativeStockpilePreset(pile->settings,choice);
    if(!settings)return false;
    std::unique_ptr<df::building_stockpilest> scratch(df::allocate<df::building_stockpilest>());
    if(!scratch)return false;
    scratch->settings=std::move(*settings);
    Json::Value result(Json::objectValue);
    result["flags"]=scratch->settings.flags.whole;
    if(!category && !header) {
      const auto containers=df3d_area::nativeStockpilePresetContainers(*pile,choice);
      if(!containers)return false;
      result["storage"]["barrels"]=(*containers)[0];
      result["storage"]["bins"]=(*containers)[1];
      result["storage"]["wheelbarrows"]=(*containers)[2];
    }
    for(const auto& entry:areaSettingVectors(scratch.get())) {
      Json::Value values(Json::arrayValue);
      for(const auto value:*entry.second)values.append(int(value));
      result["vectors"][entry.first]=std::move(values);
    }
    for(const auto& entry:areaFixedSettings(scratch.get())) {
      Json::Value values(Json::arrayValue);
      for(size_t i=0;i<entry.count;++i)values.append(bool(entry.values[i]));
      result["fixed"][entry.key]=std::move(values);
    }
    out.print("{}",Json::FastWriter().write(result));return true;
  } catch(...) {return false;}
}
bool printStockpilePreset(color_ostream& out,int32_t id,int32_t preset) {
  return printStockpileSettings(out,id,preset,false);
}
bool printStockpileCategory(color_ostream& out,int32_t id,uint32_t category) {
  return printStockpileSettings(out,id,int32_t(category),true);
}
bool printStockpileHeader(color_ostream& out,int32_t id,uint32_t category,bool enabled) {
  return printStockpileSettings(out,id,int32_t(category),false,enabled);
}
bool printMaterialRecipe(color_ostream& out,int32_t type,int32_t subtype,bool collect,bool cold_cache,int32_t custom,int32_t plate_flags,int32_t eligible_tiles) {
  auto* L=Core::getInstance().getLuaState();const int top=lua_gettop(L);
  lua_pushcfunction(L,df3d_construction::nativeMaterialRecipe);lua_pushinteger(L,type);lua_pushinteger(L,subtype);lua_pushboolean(L,collect);lua_pushboolean(L,cold_cache);lua_pushinteger(L,custom);lua_pushinteger(L,plate_flags);lua_pushinteger(L,eligible_tiles);
  bool ok=Lua::SafeCall(out,L,7,1) && lua_istable(L,-1);
  if(ok)ok=Lua::SafeCallString(out,L,"local result=...;return require('json').encode(result)",1,1) && lua_type(L,-1)==LUA_TSTRING;
  if(ok)out.print("{}\n",lua_tostring(L,-1));lua_settop(L,top);return ok;
}
bool printMaterialDistances(color_ostream& out,const std::array<int32_t,6>& positions,int32_t /*legacyTileLimit*/) {
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
  lua_pushcfunction(L,df3d_construction::nativeMaterialCandidates);
  lua_setfield(L,-2,"native_material_candidates");
  lua_pushcfunction(L,df3d_construction::routeTrack);lua_setfield(L,-2,"route_track");
  const auto point=[&](int32_t x,int32_t y,int32_t z){lua_newtable(L);field(L,"x",x);field(L,"y",y);field(L,"z",z);};
  point(positions[0],positions[1],positions[2]);lua_setfield(L,-2,"start");
  point(positions[3],positions[4],positions[5]);lua_setfield(L,-2,"destination");
  field(L,"maximum_candidates",maximumCandidates);
  if(tileLimit!=0) {
    lua_pushboolean(L,true);lua_setfield(L,-2,"material_order_query");
    lua_pushcfunction(L,df3d_construction::nativeMaterialDistances);lua_setfield(L,-2,"material_distances");
  }
  bool ok=Lua::SafeCall(out,L,1,1) && lua_istable(L,-1);
  if(ok)ok=Lua::SafeCallString(out,L,"local result=...;return require('json').encode(result)",1,1) && lua_type(L,-1)==LUA_TSTRING;
  if(ok)out.print("{}\n",lua_tostring(L,-1));
  lua_settop(L,top);return ok;
}
void stop() {
  noblesSymbolOwner.reset();
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
  stocksReplies.clear();
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
    noblesSymbolOwner.reset();
    roomUndo.clear();
    citizenRecalcPending=false;citizenRecalcDone=citizenRecalcTotal=0;
    helpers.reset();builderActive=0;builderStart=0;builderSteps=builderLastUs=0;
    actionTimings={};builderTiming={};constructionCacheEntries=constructionCacheIds=0;
    warnedMalformedRequest=warnedMailboxUnavailable=false;
    areaHints.clear();terrainHint=false;mutated=false;
    if(reply && status==m::ManagementStatus::Pending){status=m::ManagementStatus::Rejected;message="World changed before operation completed";publish();}
    reply.reset();
    epoch = worldEpoch;stocksReplies.world(epoch);
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
