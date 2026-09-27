#include "management.h"

#include <algorithm>
#include <chrono>
#include <type_traits>
#include <array>
#include <deque>

#include "Core.h"
#include "MiscUtils.h"
#include "modules/Units.h"
#include "df/activity_event.h"
#include "df/manager_order.h"
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
// Lua scanners need producer-wide identity: separate clients can both send seq 1.
uint64_t executionSerial = 0;
ManagementHelpers helpers;
std::chrono::steady_clock::time_point requestStarted;
// Borrowed native pointers are retained for the entire DLL lifetime, including reloads.
std::array<void*,4096> workOrderHolding{};
size_t workOrderHoldingCount=0;
constexpr uint32_t kWorkOrderStepBudget=2048;
// Global job-kind bits. Extend the reserved entries when those Lua builders land.
struct BuilderEntry { m::ManagementAction action; uint32_t domainMask; bool enabled; };
constexpr std::array<BuilderEntry,5> builderTable{{
  {m::ManagementAction::WorkOrderList,0x7,true}, // 0 candidates (and filters)
  {m::ManagementAction::WorkOrderList,0x7,true}, // 1 task catalog (and filters)
  {m::ManagementAction::WorkOrderList,0x7,true}, // 2 item-condition estimates
  {m::ManagementAction::Catalog,0x8,false},     // 3 construction materials
  {m::ManagementAction::CitizenList,0x10,false}, // 4 citizens recalculation
}};
uint32_t builderActive=0, builderStart=0, remainingSteps=kWorkOrderStepBudget;
uint64_t builderSteps=0,builderLastUs=0,builderMaxUs=0;
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
struct Def {
  std::string key, name, reason;
  uint16_t w, h;
  bool supported;
};
struct Input {
  int32_t id;
  std::string description;
  uint32_t quantity;
};
std::vector<Def> catalog;
std::vector<Input> inputs;
struct NativeArea {
  int32_t id=-1,x=0,y=0,z=0,owner=-1;
  int kind=0,zone=-1,w=0,h=0,barrels=0,bins=0,wheelbarrows=0;
  uint32_t categories=0;
  bool active=false,linksOnly=false,ownerAllowed=false;
  std::string name,ownerName;
  std::vector<uint8_t> extents;
  std::vector<int32_t> gives,takes;
};
std::vector<NativeArea> areas;
std::vector<std::pair<int32_t,std::string>> areaChoices;
uint32_t areaCursor=0;
bool areaTruncated=false;
uint32_t cursor = 0;
uint16_t required = 0, jobs = 0;
int32_t building = -1;
int16_t stage = -1, maxStage = -1;
bool valid = false, removing = false;
void clearResult() {
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
  cursor = required = jobs = 0;
  building = stage = maxStage = -1;
  valid = removing = terrainConstructed = false;
}
void publish() {
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<m::BuildingDefinition>> ds;
  for (auto& d : catalog)
    ds.push_back(m::CreateBuildingDefinition(b, b.CreateString(d.key), b.CreateString(d.name), d.w,
                                             d.h, d.supported, b.CreateString(d.reason)));
  std::vector<flatbuffers::Offset<m::ConstructionInput>> is;
  for (auto& i : inputs)
    is.push_back(m::CreateConstructionInput(b, i.id, b.CreateString(i.description), i.quantity));
  std::vector<flatbuffers::Offset<m::AreaInfo>> as;
  for(const auto& a:areas) {
    m::TilePos pos(a.x,a.y,a.z);
    as.push_back(m::CreateAreaInfo(b,a.id,m::AreaKind(a.kind),b.CreateString(a.name),&pos,a.w,a.h,
      b.CreateVector(a.extents),a.zone,a.categories,a.barrels,a.bins,a.wheelbarrows,a.linksOnly,
      a.active,a.owner,b.CreateString(a.ownerName),a.ownerAllowed,b.CreateVector(a.gives),b.CreateVector(a.takes)));
  }
  std::vector<flatbuffers::Offset<m::AreaChoice>> ac;
  for(const auto& c:areaChoices) ac.push_back(m::CreateAreaChoice(b,c.first,b.CreateString(c.second)));
  auto areaResult=m::CreateAreaState(b,b.CreateVector(as),b.CreateVector(ac),areaCursor,areaTruncated);
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
    citizenRows.push_back(m::CreateCitizenInfo(b,u.id,b.CreateString(u.name),b.CreateString(u.profession),b.CreateString(u.job),u.age,u.stress,u.hasStress,&pos,u.canFocus,u.eligible,b.CreateString(u.reason),b.CreateVector(u.labors),b.CreateVector(roles),b.CreateVector(u.offices),b.CreateVectorOfStrings(u.laborNames),u.professionColor,u.professionId,u.jobType,u.sheetIcon.build(b),u.onlyAssignedJobs,b.CreateVector(assignments),u.socialActivity));
  }
  std::vector<flatbuffers::Offset<m::WorkDetailInfo>> detailRows;
  for(const auto& d:citizens.details)detailRows.push_back(m::CreateWorkDetailInfo(b,d.index,d.revision,b.CreateString(d.name),d.mode,d.noModify,d.cannotBeEverybody,d.editable,d.modeEditable,b.CreateString(d.reason),b.CreateVector(d.labors),b.CreateVector(d.assignedUnits),b.CreateVectorOfStrings(d.laborNames)));
  auto citizenResult=m::CreateCitizenState(b,b.CreateVector(citizenRows),b.CreateVector(detailRows),citizens.nextCursor,citizens.selectedUnit,citizens.selectedDetail,citizens.externalController,b.CreateString(citizens.detail));
  std::vector<flatbuffers::Offset<m::ReportInfo>> reportRows;
  for(const auto& r:reports.reports)reportRows.push_back(m::CreateReportInfo(b,r.id,b.CreateString(r.category),b.CreateString(r.text),r.year,r.yearTick,r.repeatCount,r.continuation,r.textComplete,r.x,r.y,r.z,r.x2,r.y2,r.z2,r.positionVisible,r.position2Visible));
  auto reportResult=m::CreateReportState(b,b.CreateVector(reportRows),reports.nextBeforeId,reports.announcementsOnly,b.CreateString(reports.detail));
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
                                    maxStage, removing, jobs, terrainConstructed, areaResult, productionResult, workOrderResult, citizenResult, reportResult, agreementResult, tradeResult, 0, 0, 0, 0, 0, creatureResult);
  b.Finish(s);
  if (auto e = m::validateManagementState(
          *flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()))) {
    if (publishingFallback) {
      // The minimal fallback failed validation too: nothing sane to publish.
      Core::getInstance().getConsole().printerr("df3d: management fallback response invalid: {}\n", *e);
      return;
    }
    publishingFallback = true;
    clearResult();
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
// Restore temporarily borrowed input before dropping a pending native adapter.

void run(color_ostream& out) {
  auto* L = Core::getInstance().getLuaState();
  int top = lua_gettop(L);
  const auto* r = flatbuffers::GetRoot<m::ConstructionRequest>(request.data());
  const int domainScript=helpers.acquire(action,out,L);
  if(domainScript==LUA_NOREF) {
    status=m::ManagementStatus::Rejected;message="Management helper unavailable";publish();return;
  }
  lua_rawgeti(L,LUA_REGISTRYINDEX,domainScript);
  lua_newtable(L);
  field(L, "action", int(action));
  field(L, "seq", executionSerial);
  field(L, "epoch", epoch);
  field(L, "step_budget", remainingSteps);
  field(L, "retire_capacity", workOrderHolding.size()-workOrderHoldingCount);
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
  field(L, "cursor", cursor);
  field(L, "limit", 128 - int(inputs.size()));
  field(L, "building_id", r->building_id());
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
    field(L,"x",a->origin()->x());field(L,"y",a->origin()->y());field(L,"z",a->origin()->z());
    field(L,"width",a->width());field(L,"height",a->height());
    field(L,"categories",a->categories());field(L,"changed_categories",a->changed_categories());
    field(L,"barrels",a->barrels());field(L,"bins",a->bins());field(L,"wheelbarrows",a->wheelbarrows());
    field(L,"links_only",a->links_only());field(L,"active",a->active());field(L,"owner_id",a->owner_id());
    field(L,"link_id",a->link_id());field(L,"give",a->give());field(L,"unlink",a->unlink());
    field(L,"query",a->query()?a->query()->str():"");field(L,"cursor",a->cursor());
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
    lua_newtable(L);field(L,"unit_id",c->unit_id());field(L,"detail_index",c->detail_index());field(L,"expected_revision",c->expected_revision());field(L,"cursor",c->cursor());field(L,"query",c->query()?c->query()->str():"");field(L,"member",c->member());field(L,"mode",c->mode());lua_setfield(L,-2,"citizen");
  }

  if(const auto* t=r->trade()){lua_newtable(L);field(L,"depot_id",t->depot_id());field(L,"item_id",t->item_id());field(L,"expected_revision",t->expected_revision());field(L,"requested",t->requested());field(L,"anyone",t->anyone());field(L,"cursor",t->cursor());field(L,"query",t->query()?t->query()->str():"");lua_setfield(L,-2,"trade");}
  if(const auto* a=r->agreement()){lua_newtable(L);field(L,"id",a->id());field(L,"before_id",a->before_id());field(L,"query",a->query()?a->query()->str():"");field(L,"pending_only",a->pending_only());lua_setfield(L,-2,"agreement");}

  if(const auto* p=r->report()) {lua_newtable(L);field(L,"id",p->id());field(L,"before_id",p->before_id());field(L,"query",p->query()?p->query()->str():"");field(L,"announcements_only",p->announcements_only());lua_setfield(L,-2,"report");}
  if (!Lua::SafeCall(out, L, 1, 1) || !lua_istable(L, -1)) {
    status = m::ManagementStatus::Rejected;
    message = "Native management helper failed; no success reported";
    remainingSteps=0; // No trustworthy work count after a helper error.
    lua_settop(L, top);
    publish();
    return;
  }
  if(const auto error=managementResultError(L,action); !error.empty()) {
    status=m::ManagementStatus::Rejected;
    message="Management helper contract failure: "+error;
    remainingSteps=0;
    lua_settop(L,top);publish();return;
  }
  bool ok = boolean(L, "ok");
  bool productionPending = boolean(L,"pending");
  const auto requestMask=df3d_builder::requestMask(builderTable,
      [&](auto owner){return helpers.sameOwner(action,owner);});
  builderActive=(builderActive & ~requestMask) |
      (uint32_t(number(L,"active_kinds")) & requestMask);
  if(requestMask) {
    const auto used=std::min(remainingSteps,uint32_t(number(L,"steps")));
    remainingSteps-=used;builderSteps+=used;
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
  if(ok && (action==m::ManagementAction::TradeUpdate || action==m::ManagementAction::TradeBring))mutated=true;
  if(ok && action>=m::ManagementAction::WorkOrderCreate && action<=m::ManagementAction::WorkOrderCondition)mutated=true;
  if(ok && (action==m::ManagementAction::WorkDetailMembership || action==m::ManagementAction::WorkDetailMode))mutated=true;
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
  if(action>=m::ManagementAction::AreaCatalog && action<=m::ManagementAction::AreaCandidates) {
    areaCursor=uint32_t(number(L,"next_cursor"));areaTruncated=boolean(L,"truncated");
    auto ints=[&](const char* key,auto& values,size_t max){
      lua_getfield(L,-1,key);
      if(lua_istable(L,-1)) for(size_t i=1;i<=lua_rawlen(L,-1)&&i<=max;++i){
        lua_rawgeti(L,-1,i);values.push_back(typename std::decay_t<decltype(values)>::value_type(lua_tointeger(L,-1)));lua_pop(L,1);
      }
      lua_pop(L,1);
    };
    lua_getfield(L,-1,"areas");
    if(lua_istable(L,-1)) for(size_t i=1;i<=lua_rawlen(L,-1)&&i<=64;++i){
      lua_rawgeti(L,-1,i);NativeArea a;
      a.id=int32_t(number(L,"id",-1));a.kind=int(number(L,"kind"));a.zone=int(number(L,"zone_type",-1));
      a.x=int(number(L,"x"));a.y=int(number(L,"y"));a.z=int(number(L,"z"));
      a.w=int(number(L,"width"));a.h=int(number(L,"height"));a.name=text(L,"name");
      a.categories=uint32_t(number(L,"categories"));a.barrels=int(number(L,"barrels"));a.bins=int(number(L,"bins"));a.wheelbarrows=int(number(L,"wheelbarrows"));
      a.active=boolean(L,"active");a.linksOnly=boolean(L,"links_only");a.ownerAllowed=boolean(L,"owner_allowed");
      a.owner=int32_t(number(L,"owner_id",-1));a.ownerName=text(L,"owner_name");
      ints("extents",a.extents,32768);ints("gives",a.gives,1024);ints("takes",a.takes,1024);
      areas.push_back(std::move(a));lua_pop(L,1);
    }
    lua_pop(L,1);
    lua_getfield(L,-1,"choices");
    if(lua_istable(L,-1)) for(size_t i=1;i<=lua_rawlen(L,-1)&&i<=128;++i){
      lua_rawgeti(L,-1,i);areaChoices.emplace_back(int32_t(number(L,"id",-1)),text(L,"name"));lua_pop(L,1);
    }
    lua_pop(L,1);
  }
  if(action>=m::ManagementAction::CitizenList && action<=m::ManagementAction::WorkDetailMode) {
    citizens.nextCursor=uint32_t(number(L,"next_cursor"));citizens.selectedUnit=int32_t(number(L,"selected_unit",-1));citizens.selectedDetail=int32_t(number(L,"selected_detail",-1));citizens.externalController=boolean(L,"external_controller");citizens.detail=text(L,"detail");
    auto each=[&](const char* key,size_t cap,auto fn){lua_getfield(L,-1,key);if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1)&&i<=cap;++i){lua_rawgeti(L,-1,i);fn();lua_pop(L,1);}lua_pop(L,1);};
    each("citizens",32,[&](){
      CitizenInfo u;u.professionColor=int32_t(number(L,"profession_color",-1));u.professionId=int32_t(number(L,"profession_id",-1));u.jobType=int32_t(number(L,"job_type",-1));u.id=int32_t(number(L,"id",-1));u.age=int32_t(number(L,"age",-1));u.stress=int32_t(number(L,"stress"));u.x=int32_t(number(L,"x"));u.y=int32_t(number(L,"y"));u.z=int32_t(number(L,"z"));u.name=text(L,"name");u.profession=text(L,"profession");u.job=text(L,"job");u.reason=text(L,"reason");u.hasStress=boolean(L,"has_stress");u.canFocus=boolean(L,"can_focus");u.eligible=boolean(L,"eligible");
      // A stale Lua-reported id (unit removed between the scan and this
      // readback) must not reach the appearance resolver: skip the row.
      auto* nativeUnit=df::unit::find(u.id);
      if(!nativeUnit){++staleUnitsSkipped;return;}
      u.sheetIcon.collect(nativeUnit);
      // Same semantic lookup as DFHack manipulator: a social event replaces
      // the idle caption only when there is no ordinary job. No UI state read.
      if(!nativeUnit->job.current_job) {
        if(auto* event=Units::getMainSocialEvent(nativeUnit)) {
          std::string description;event->getName(nativeUnit->id,&description);
          u.job=DF2UTF(description);u.socialActivity=true;
        }
      }
      u.onlyAssignedJobs=boolean(L,"only_assigned_jobs");
      each("assigned_details",128,[&](){u.assignedDetails.push_back({int32_t(number(L,"index",-1)),int32_t(number(L,"icon",-1)),text(L,"name")});});
      each("labor_names",94,[&](){u.laborNames.push_back(lua_tostring(L,-1));});
      each("labors",94,[&](){u.labors.push_back(int16_t(lua_tointeger(L,-1)));});
      each("offices",64,[&](){u.offices.push_back(int32_t(lua_tointeger(L,-1)));});
      each("roles",32,[&](){u.roles.push_back({text(L,"name"),int32_t(number(L,"required_office"))});});citizens.citizens.push_back(std::move(u));
    });
    each("details",16,[&](){
      WorkDetailInfo d;d.index=int32_t(number(L,"index",-1));d.revision=uint64_t(number(L,"revision"));d.name=text(L,"name");d.reason=text(L,"reason");d.mode=uint8_t(number(L,"mode"));d.noModify=boolean(L,"no_modify");d.cannotBeEverybody=boolean(L,"cannot_be_everybody");d.editable=boolean(L,"editable");d.modeEditable=boolean(L,"mode_editable");
      each("labor_names",94,[&](){d.laborNames.push_back(lua_tostring(L,-1));});
      each("labors",94,[&](){d.labors.push_back(int16_t(lua_tointeger(L,-1)));});each("assigned_units",1024,[&](){d.assignedUnits.push_back(int32_t(lua_tointeger(L,-1)));});citizens.details.push_back(std::move(d));
    });
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
  if(action>=m::ManagementAction::ReportList && action<=m::ManagementAction::ReportInspect) {
    reports.nextBeforeId=int32_t(number(L,"next_before_id",-1));reports.announcementsOnly=boolean(L,"announcements_only");reports.detail=text(L,"detail");
    lua_getfield(L,-1,"reports");
    if(lua_istable(L,-1))for(size_t i=1;i<=lua_rawlen(L,-1)&&i<=16;++i){
      lua_rawgeti(L,-1,i);ReportInfo p;p.id=int32_t(number(L,"id",-1));p.category=text(L,"category");p.text=text(L,"text");p.year=int32_t(number(L,"year"));p.yearTick=int32_t(number(L,"year_tick"));p.repeatCount=int32_t(number(L,"repeat_count"));p.continuation=boolean(L,"continuation");p.textComplete=boolean(L,"text_complete");p.x=int32_t(number(L,"x",-1));p.y=int32_t(number(L,"y",-1));p.z=int32_t(number(L,"z",-1));p.x2=int32_t(number(L,"x2",-1));p.y2=int32_t(number(L,"y2",-1));p.z2=int32_t(number(L,"z2",-1));p.positionVisible=boolean(L,"position_visible");p.position2Visible=boolean(L,"position2_visible");reports.reports.push_back(std::move(p));lua_pop(L,1);
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
  lua_getfield(L, -1, "catalog");
  if (lua_istable(L, -1))
    for (size_t i = 1; i <= lua_rawlen(L, -1) && i <= 256; ++i) {
      lua_rawgeti(L, -1, i);
      catalog.push_back({text(L, "key"), text(L, "name"), text(L, "reason"),
                         uint16_t(number(L, "width", 1)), uint16_t(number(L, "height", 1)),
                         boolean(L, "supported")});
      lua_pop(L, 1);
    }
  lua_pop(L, 1);
  lua_getfield(L, -1, "inputs");
  if (lua_istable(L, -1))
    for (size_t i = 1; i <= lua_rawlen(L, -1) && inputs.size() < 128; ++i) {
      lua_rawgeti(L, -1, i);
      inputs.push_back(
          {int32_t(number(L, "id", -1)), text(L, "description"), uint32_t(number(L, "quantity"))});
      lua_pop(L, 1);
    }
  lua_pop(L, 1);
  lua_settop(L, top);
  status = !ok ? m::ManagementStatus::Rejected
               : (productionPending || (action == m::ManagementAction::Preview && cursor && inputs.size() < 128)
                      ? m::ManagementStatus::Pending
                      : m::ManagementStatus::Ok);
  publish();
}
void stepBuilder(color_ostream& out,uint32_t budget) {
  const auto started=std::chrono::steady_clock::now();
  auto* L=Core::getInstance().getLuaState();const int top=lua_gettop(L);
  builderSteps+=df3d_builder::advance(builderTable,builderActive,builderStart,budget,
      [&](size_t kind,uint32_t share)->uint32_t {
    const auto& entry=builderTable[kind];
    const int helper=helpers.acquire(entry.action,out,L);
    if(helper==LUA_NOREF){builderActive &= ~entry.domainMask;return 0;}
    lua_rawgeti(L,LUA_REGISTRYINDEX,helper);lua_newtable(L);
    field(L,"step",share);field(L,"builder_kind",kind);
    uint32_t used=0;
    if(Lua::SafeCall(out,L,1,1) && lua_istable(L,-1)) {
      builderActive=(builderActive & ~entry.domainMask) |
          (uint32_t(number(L,"active_kinds")) & entry.domainMask);
      used=std::min(share,uint32_t(number(L,"steps")));
    } else builderActive &= ~entry.domainMask;
    lua_settop(L,top);return used;
  });
  builderLastUs=uint64_t(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-started).count());
  builderMaxUs=std::max(builderMaxUs,builderLastUs);
}
}  // namespace
void stop() {
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
  out.print("  work-order holding: {}/4096; builder steps: {}; {} / {} us last/max\n",workOrderHoldingCount,builderSteps,builderLastUs,builderMaxUs);
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
  if (!region) {
    if (!startBackoff.due()) return;
    if (!start(out)) { startBackoff.failed(kStartRetryUpdates); return; }
    startBackoff.reset();
  }
  if (epoch != worldEpoch) {
    helpers.reset();builderActive=0;builderStart=0;builderSteps=builderLastUs=0;
    actionTimings={};
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
  uint8_t bytes[m::kManagementCommandCapacity];
  // One drained request and at most 512 candidate items per update, paused included.
  // Preserve the exact native operation through its following-update readback.
  // Reconnect/Catalog requests stay queued until the outcome has been published.
  auto n=status==m::ManagementStatus::Pending ? 0u : sh::popCommand(region,bytes,sizeof(bytes));
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
      rejectRequest(out,warnedMalformedRequest,"Invalid management request: "+*invalid);
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
      message = "Operation did not confirm in time; refresh game state before another change";
      publish();
      request.clear();
      return;
    }
    if (saving || !epoch) {
      status = m::ManagementStatus::Rejected;
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
  if(!saving && epoch && builderActive && remainingSteps)stepBuilder(out,remainingSteps);
}
}  // namespace df3d_management
