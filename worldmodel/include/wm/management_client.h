#pragma once
#include "wm/types.h"
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>
#include "wm/management_enums.h"
namespace wm {
struct SelectionRequest {
  SelectionOperation operation=SelectionOperation::OpenTile;
  int32_t x=-1,y=-1,z=-1,index=-1;
  uint64_t receipt=0;
};
struct SelectionIdentity { SelectionKind kind=SelectionKind::None; int32_t id=-1; std::string name; };
struct SelectionText { SelectionSection section=SelectionSection::AgeSex; std::string text; };
struct SelectionItem { int32_t id=-1; std::string name; };
// Original-asset references; indexes are local to this appearance.
struct SelectionAppearance {
  std::vector<std::string> tilePages,palettes;
  std::vector<AppearanceLayer> layers;
  friend bool operator==(const SelectionAppearance&,const SelectionAppearance&)=default;
};
struct SelectionState {
  bool open=false;
  uint64_t receipt=0;
  SelectionKind kind=SelectionKind::None;
  int32_t id=-1,x=-1,y=-1,z=-1;
  std::string title,subtitle,job,description;
  std::vector<SelectionIdentity> alternatives;
  std::vector<SelectionItem> items;
  std::vector<SelectionText> overview;
  SelectionIdentity container;
  int32_t weight=-1,value=-1;
  bool passable=false,isDoor=false,complete=true;
  SelectionAppearance portrait;
};
struct CreatureFact { std::string key,text; int64_t number=0; bool hasNumber=false; };
struct CreatureRecord { int32_t id=-1,relatedId=-1; std::string name; std::vector<CreatureFact> facts; };
struct CreatureSection { CreatureSectionKind kind=CreatureSectionKind::Identity; bool available=false,truncated=false; std::string reason; std::vector<CreatureRecord> records; };
struct CreatureInfo {
  int32_t unitId=-1,age=-1,sex=-1,x=-1,y=-1,z=-1;
  uint64_t capturedTick=0;
  std::string name,species,profession,job;
  bool complete=false;
  std::vector<CreatureSection> sections;
  SelectionAppearance portrait;
};
struct AreaSpan { int16_t y=0,x=0; uint16_t length=0; };
struct AreaZoneSettings {
  uint8_t pondMode=0,facing=0;
  int8_t tombCitizens=-1,tombPets=-1,gatherTrees=-1,gatherShrubs=-1;
  friend bool operator==(const AreaZoneSettings&,const AreaZoneSettings&)=default;
};
struct AreaPaintPreview { int16_t x=0,y=0; uint16_t width=0,height=0; };
struct AreaRequest {
  AreaKind kind = AreaKind::Stockpile;
  int32_t id=-1,x=0,y=0,z=0;
  uint16_t width=1,height=1;
  int16_t zoneType=-1,barrels=-1,bins=-1,wheelbarrows=-1;
  uint32_t categories=0,changedCategories=0;
  int8_t linksOnly=-1,active=-1;
  int32_t ownerId=-2,linkId=-1;
  bool give=true,unlink=false;
  std::string query;
  uint32_t cursor=0;
  AreaOperation operation=AreaOperation::None;
  int64_t expectedRevision=0,expectedListRevision=0;
  std::string listKey,rowKey,name;
  uint8_t scope=0,value=0,preset=0,paintMode=0,locationKind=0,candidateKind=0,sort=0;
  std::vector<AreaSpan> spans;
  int16_t paintZ=-1,profession=-1;
  int32_t locationId=-2,deityId=-1,unitId=-1,squadId=-1;
  int8_t deityKind=-1,assign=-1,squadUse=-1,organic=-1,inorganic=-1;
  AreaZoneSettings zoneSettings;
  bool sortDescending=false;
  uint8_t roomFurniture=0;
  int64_t interactionId=0,undoToken=0;
  int64_t countGeneration=0;
  std::optional<AreaPaintPreview> paintPreview;
  int32_t locationSiteId=-1,occupationId=-1;
};
struct AreaInfo {
  int32_t id=-1,x=0,y=0,z=0;
  AreaKind kind=AreaKind::Stockpile;
  std::string name,ownerName;
  std::string ownerProfession;
  uint8_t locationKind=0;
  int8_t ownerSex=-1;
  uint16_t width=0,height=0;
  std::vector<uint8_t> extents;
  int16_t zoneType=-1,barrels=0,bins=0,wheelbarrows=0;
  uint32_t categories=0;
  bool linksOnly=false,active=false,ownerAllowed=false;
  int32_t ownerId=-1;
  std::vector<int32_t> gives,takes;
  int64_t revision=0;
  std::string zoneLabel,locationName,religion;
  int32_t locationId=-1,tileCount=-1,assignedCount=-1,locationSiteId=-1;
  int8_t organic=-1,inorganic=-1;
  AreaZoneSettings zoneSettings;
};
struct AreaChoice { int32_t id=-1; std::string name; std::string label{}; };
struct AreaSettingRow { std::string key; int32_t index=-1; std::string label; uint8_t kind=0,state=0; bool estimated=false; };
struct AreaLocationRow { int32_t id=-1; std::string name; uint8_t locationKind=0; std::string religion; int16_t guildProfession=-1; int32_t locationTier=-1; int32_t siteId=-1; };
struct LocationDeity { int32_t id=-1; std::string name; std::vector<int32_t> spheres; };
struct LocationReligion { uint8_t kind=0; int32_t id=-1; std::string name; int32_t worshippers=0; bool hasTemple=false; std::vector<LocationDeity> deities; };
struct LocationGuild { int32_t profession=-1,workers=0; bool hasMeetingPlace=false; int32_t guildId=-1; std::string guildName; int32_t members=0; };
struct LocationCatalog {
  uint8_t kind=0; int64_t revision=0; uint32_t cursor=0,total=0,nextCursor=0;
  std::vector<LocationReligion> religions; std::vector<LocationGuild> guilds;
};
struct AreaCandidateRow {
  int32_t id=-1;
  std::string name,profession;
  int8_t sex=-1;
  uint8_t mood=0;
  bool grazer=false,assigned=false;
  int8_t squadUse=-1;
};
struct AreaLinkRow { int32_t id=-1; AreaKind kind=AreaKind::Stockpile; uint8_t direction=0; std::string name; };
struct LocationSupplyQuantity { uint8_t kind=0; int32_t stored=0,desired=0; };
struct LocationFacilities { int32_t chests=0,beds=0,tables=0,tractionBenches=0,bookcases=0,chairs=0,rooms=0,rentedRooms=0; };
struct LocationStaffNames { std::string positionName,holderName; uint8_t holderKind=0; int32_t holderId=-1; };
struct LocationStaffRow {
  uint8_t source=0;
  int32_t occupationId=-1,role=-1,histfigId=-1,unitId=-1,locationId=-1,siteId=-1,groupId=-1;
  int32_t entityId=-1,positionId=-1,assignmentId=-1;
  std::optional<LocationStaffNames> names;
};
struct LocationStaffSkill { int32_t id=-1,rating=0,experience=0,weight=0; };
struct LocationStaffCandidate {
  int32_t unitId=-1,histfigId=-1,score=0,professionColor=-1;
  std::string name,baseName,professionName; bool legendary=false;
  int32_t sourceIndex=-1,professionOrder=-1,statusOrder=-1;
  std::vector<uint8_t> nameSortKey,professionSortKey;
  std::vector<LocationStaffSkill> skills;
};
struct LocationStaffCandidates {
  int32_t siteId=-1,locationId=-1,occupationId=-1,role=-1;
  int64_t revision=0; uint32_t cursor=0,nextCursor=0,total=0;
  std::vector<LocationStaffCandidate> rows;
};
struct LocationStaffSnapshot { std::vector<LocationStaffRow> rows; std::vector<int32_t> missingRoles; };
struct LocationAffiliation { uint8_t kind=0; int32_t id=-1; std::string name; int32_t count=0,workers=-1; };
struct LocationDetails {
  int32_t siteId=-1,id=-1; uint8_t kind=0; std::string name; int64_t revision=0;
  uint8_t access=0; bool visitors=false,residents=false,members=false;
  int32_t profession=-1,tier=-1,value=-1,desiredCopies=0,appraisal=-2,writtenObjects=-1,danceFloorX=-1,danceFloorY=-1; bool recognized=false;
  std::vector<LocationSupplyQuantity> supplies; std::vector<int32_t> zoneIds;
  std::optional<LocationFacilities> facilities;
  std::optional<LocationStaffSnapshot> staff;
  std::optional<LocationAffiliation> affiliation;
};
struct AreaState {
  LocationEntryOutcome locationEntryOutcome=LocationEntryOutcome::None;
  LocationEditOutcome locationEditOutcome=LocationEditOutcome::None;
  std::optional<LocationDetails> locationDetails;
  std::optional<LocationStaffCandidates> locationStaffCandidates;
  std::optional<LocationCatalog> locationCatalog;
  std::vector<AreaInfo> areas;
  std::vector<AreaChoice> choices;
  uint32_t nextCursor=0;
  bool truncated=false;
  AreaOperation operation=AreaOperation::None;
  int32_t areaId=-1;
  std::string listKey,query;
  uint8_t candidateKind=0,sort=0,buildPhase=0;
  bool sortDescending=false;
  std::vector<AreaSettingRow> settings;
  std::vector<AreaLocationRow> locations;
  std::vector<AreaCandidateRow> candidates;
  std::vector<AreaLinkRow> links;
  int64_t listRevision=0,capturedTick=-1;
  uint32_t buildDone=0,buildTotal=0,omitted=0;
  int64_t interactionId=0,undoToken=0;
  AreaRoomOutcome roomOutcome=AreaRoomOutcome::None;
  uint32_t roomsCreated=0,roomsInUse=0,roomsUnenclosed=0,roomsRemoved=0;
  uint32_t roomsDormitories=0;
  int64_t countGeneration=0;
  int32_t paintedCount=-1,previewCount=-1;
};
struct ProductionRequest {
  int32_t buildingId=-1,jobId=-1,cropId=-1;
  std::string recipe,query;
  uint32_t cursor=0;
  int8_t repeat=-1,suspend=-1,season=-1;
  bool cancel=false;
};
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
struct CitizenRequest {
  int32_t unitId=-1,detailIndex=-1;
  uint64_t expectedRevision=0;
  uint32_t cursor=0;
  std::string query;
  int8_t member=-1,mode=-1;
  std::string name;
  std::vector<int16_t> labors;
  uint8_t edit=0;
  int8_t onlyAssigned=-1;
  int64_t expectedListRevision=0;
};
struct CitizenRole { std::string name; int32_t requiredOffice=0; };
struct CitizenWorkDetail { int32_t index=-1,icon=-1; std::string name; };
struct CitizenInfo {
  bool onlyAssignedJobs=false, socialActivity=false;
  std::vector<CitizenWorkDetail> assignedDetails;
  SelectionAppearance sheetIcon;
  int32_t professionColor=-1,professionId=-1,jobType=-1;
  int32_t id=-1,age=-1,stress=0,x=0,y=0,z=0;
  std::string name,profession,job,reason;
  bool hasStress=false,canFocus=false,eligible=false;
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
  int32_t index=-1;
  uint64_t revision=0;
  std::string name,reason;
  uint8_t mode=0;
  bool noModify=false,cannotBeEverybody=false,editable=false,modeEditable=false;
  std::vector<int16_t> labors;
  std::vector<std::string> laborNames;
  std::vector<int32_t> assignedUnits;
  int32_t icon=-2;
  std::string rowError;
};
struct CitizenState {
  std::vector<CitizenInfo> citizens;
  std::vector<WorkDetailInfo> details;
  uint32_t nextCursor=0;
  int32_t selectedUnit=-1,selectedDetail=-1;
  bool externalController=false;
  std::string detail;
  uint32_t recalcDone=0,recalcTotal=0;
  int64_t detailListRevision=0;
  std::string recalcError;
};
struct WorkOrderRequest {
  int32_t id=-1,remaining=-1,workshopId=-2,maxWorkshops=-1,threshold=-1,targetOrder=-1;
  uint64_t expectedRevision=0;
  std::string recipe,query;
  uint32_t cursor=0;
  int16_t conditionIndex=-1,itemType=-1;
  int8_t frequency=-1,compare=-1,dependency=-1;
  uint8_t conditionKind=0,candidateKind=0;
  bool removeCondition=false;
  int8_t move=0; int32_t expectedNeighbor=-1; int64_t expectedListRevision=0;
  int16_t itemSubtype=-1,matType=-1; int32_t matIndex=-1;
  std::optional<std::vector<std::string>> traits;
  int16_t inputIndex=-1,groupType=-1,groupSubtype=-1; int32_t groupCustom=-1,encrustFlags=-1;
};
struct WorkOrderCondition {
  uint8_t kind=0; uint16_t index=0;
  std::string description;
  bool editable=false,satisfied=false;
  int8_t compare=-1,dependency=-1;
  int16_t itemType=-1;
  int32_t threshold=-1,targetOrder=-1;
  int16_t itemSubtype=-1,matType=-1; int32_t matIndex=-1;
  std::vector<std::string> traits; uint8_t satisfaction=0; bool estimated=false; int32_t estimateCount=-1;
};
struct WorkOrderInput { uint16_t index=0; std::string description; int16_t matType=-1; int32_t matIndex=-1; bool editable=false; };
struct WorkOrderMaterial { int16_t matType=-1; int32_t matIndex=-1; std::string name; };
struct WorkOrderTrait { std::string key,name; };
struct WorkOrderItemType { int16_t itemType=-1,itemSubtype=-1; std::string name; };
struct WorkOrderGroup { int16_t type=-1,subtype=-1; int32_t custom=-1; std::string name; uint32_t count=0; };
struct WorkOrderTask { std::string key,name; int16_t jobType=-1; std::string reaction; int16_t itemType=-1,itemSubtype=-1,matType=-1; int32_t matIndex=-1; };
struct WorkOrderInfo {
  int32_t id=-1,finishedYear=-1,finishedTick=-1,workshopId=-1,maxWorkshops=0;
  uint64_t revision=0;
  std::string name,reason;
  int16_t total=0,remaining=0;
  int8_t frequency=0;
  bool validated=false,active=false,editable=false;
  std::vector<int32_t> generatedJobs;
  std::vector<WorkOrderCondition> conditions;
  int32_t position=-1; uint8_t detailKind=0; int32_t sizeRaw=-1,encrustFlags=0;
  int16_t matType=-1; int32_t matIndex=-1; uint32_t materialCategory=0;
  std::vector<WorkOrderInput> inputs;
};
struct ManagerRole { int32_t unitId=-1; std::string name,position,job; std::vector<int32_t> offices; };
struct WorkOrderState {
  std::vector<WorkOrderInfo> orders;
  std::vector<ProductionRecipe> recipes;
  std::vector<AreaChoice> choices;
  std::vector<ManagerRole> managers;
  uint32_t nextCursor=0;
  std::string detail;
  std::vector<WorkOrderMaterial> materials;
  std::vector<WorkOrderTrait> traits;
  std::vector<WorkOrderItemType> types;
  std::vector<WorkOrderGroup> groups;
  std::vector<WorkOrderTask> tasks;
  uint32_t total=0; int64_t listRevision=0; uint8_t buildPhase=0; uint32_t buildDone=0,buildTotal=0;
};
struct ConstructionSelection {
  int16_t filter=-1,itemType=-1,itemSubtype=-1,matType=-1; int32_t matIndex=-1; uint32_t count=1;
  int64_t expectedListRevision=-1;
  std::optional<std::vector<int32_t>> itemIds;
  int32_t individualId=-1;
};
struct ConstructionFilter {
  int16_t index=-1,itemType=-1,itemSubtype=-1; std::string caption,requirement; int32_t quantity=-1;
};
struct ConstructionItemAppearance {
  std::string materialToken,subtypeRaw,colorToken; uint32_t stack=1; uint8_t flags=0;
};
struct ConstructionMaterialCandidate {
  int32_t id=-1; std::string name; uint32_t distance=0;
  std::optional<ConstructionItemAppearance> appearance;
};
struct ConstructionMaterial {
  int16_t itemType=-1,itemSubtype=-1,matType=-1; int32_t matIndex=-1; std::string name,caption; uint32_t count=0;
  std::optional<std::vector<ConstructionMaterialCandidate>> candidates;
  int32_t individualId=-1;
  std::string lastName;
};
struct ConstructionFootprint {
  uint8_t direction=0; uint16_t width=0,height=0; int16_t centerX=-1,centerY=-1;
};
struct PressureCreatureExample { int32_t size=0,raceId=-1; std::string name; };
enum class ConnectedTrackStatus:uint8_t { Found, NoPath, InvalidInput, FrontierLimit, UnverifiedTerrain, PayloadLimit };
struct ConnectedTrackPreview { ConnectedTrackStatus status=ConnectedTrackStatus::UnverifiedTerrain; std::vector<TilePos> path; };
struct ConstructionState {
  std::string buildingKey; int16_t filter=-1;
  std::vector<ConstructionFilter> filters; std::vector<ConstructionMaterial> materials;
  uint32_t total=0,buildDone=0,buildTotal=0,placed=0,skipped=0;
  int64_t listRevision=0; uint8_t buildPhase=0; bool estimated=false;
  int32_t firstBuilding=-1; std::vector<uint8_t> validMask,pieces;
  std::optional<ConstructionFootprint> footprint;
  std::vector<PressureCreatureExample> pressureCreatures;
  std::optional<ConnectedTrackPreview> connectedTrack;
  ConstructionOutcome outcome=ConstructionOutcome::None;
  uint32_t updated=0;int32_t failedIndex=-1;
};
struct BuildingDefinition {
  std::string key, name;
  uint16_t width = 1, height = 1;
  bool supported = false;
  std::string reason;
  std::string family,subtypeKey,customCode,nativeName;
  uint8_t areaMode=0,orientations=0; uint16_t maxWidth=0,maxHeight=0,maxDepth=0;
  std::vector<ConstructionFilter> filters; std::vector<ConstructionFootprint> footprints;
};

struct AlertRequest { AlertOperation operation=AlertOperation::OpenCategory; int16_t category=-1; uint64_t receipt=0; int32_t entry=-1; int16_t tab=-1,delta=0; };
struct AlertEntry { std::string text; int32_t reportId=-1,unitId=-1; int8_t unitCategory=-1; bool canRecenter=false; };
struct AlertState { AlertView view=AlertView::Closed; uint64_t receipt=0; int16_t category=-1; int32_t unitId=-1; int8_t unitCategory=-1; std::vector<AlertEntry> entries; std::vector<std::string> tabs; int16_t selectedTab=-1; int32_t scroll=0; uint32_t total=0; bool complete=true; int32_t focusX=-1,focusY=-1,focusZ=-1; };

struct ReportEntryUnit {int32_t unitId=-1; uint8_t category=0;};
struct ReportRequest { int32_t id=-1,beforeId=-1; std::string query; bool announcementsOnly=true; ReportView view=ReportView::Flat; ReportTab tab=ReportTab::Unknown; int32_t afterId=-1; bool fromEnd=false; int32_t unitId=-1; int8_t unitCategory=-1; uint32_t cursor=0; uint64_t expectedListRevision=0; std::vector<int32_t> ids; std::vector<ReportEntryUnit> units; bool refresh=false; int16_t notificationCategory=-1; bool alertButton=false; };
struct ReportInfo {
  int32_t id=0,year=0,yearTick=0,repeatCount=0;
  std::string category,text;
  bool continuation=false,textComplete=true,positionVisible=false,position2Visible=false;
  int32_t x=-1,y=-1,z=-1,x2=-1,y2=-1,z2=-1;
  ReportTab tab=ReportTab::Unknown; int16_t color=-1; bool bright=false;
  ReportZoom zoomType=ReportZoom::Unknown,zoomType2=ReportZoom::Unknown;
  bool positionHidden=false,position2Hidden=false; int32_t speakerId=-1;
};
struct ReportUnitInfo { int32_t unitId=-1; int8_t category=-1; std::string profession,name; bool dead=false; uint32_t logCount=0; std::string error; };
struct ReportState { std::vector<ReportInfo> reports; int32_t nextBeforeId=-1; bool announcementsOnly=true; std::string detail;
 ReportView view=ReportView::Flat; ReportTab tab=ReportTab::Unknown; int32_t afterId=-1; bool fromEnd=false;
 std::vector<uint32_t> tabCounts; uint32_t total=0; int32_t nextAfterId=-1,trimmedThrough=-1; bool gap=false;
 int32_t unitId=-1; int8_t unitCategory=-1; uint32_t cursor=0,nextCursor=0; uint64_t listRevision=0; std::vector<ReportUnitInfo> units; std::vector<int32_t> missingIds; int16_t notificationCategory=-1; bool alertButton=false;
};
struct AgreementDetail {
 int32_t id=0,siteId=-1,year=0,yearTick=0,applicantParty=-1,governmentParty=-1,tier=-1,deityId=-1;
 int16_t kind=-1,locationType=-1,profession=-1,deityType=-1;
 std::string description;
};
struct AgreementParty {int32_t id=0;std::vector<int32_t> entityIds,histfigIds;std::string name;};
struct AgreementInfo {int32_t id=0;uint8_t status=0;bool notApproved=false,concluded=false,continuing=false,complete=true;std::vector<AgreementDetail> details;std::vector<AgreementParty> parties;std::string summary,reason;};
struct AgreementState {std::vector<AgreementInfo> agreements;int32_t nextBeforeId=-1;bool pendingOnly=false;std::string detail;};
struct AgreementRequest {int32_t id=-1,beforeId=-1;std::string query;bool pendingOnly=false;};
struct TradeRequest { int32_t depotId=-1,itemId=-1; uint64_t expectedRevision=0; int8_t requested=-1,anyone=-1; uint32_t cursor=0; std::string query; uint64_t receipt=0; uint8_t side=0; int8_t selected=-1; };
struct TradeDepot { int32_t id=-1,x=0,y=0,z=0; uint64_t revision=0; bool requested=false,anyone=false,accessible=false,ready=false; std::string broker; uint32_t hauling=0,goods=0; };
struct TradeCaravan { int32_t id=0; std::string name,state; int32_t daysRemaining=0; };
struct TradeGood { int32_t id=-1; std::string description; uint32_t quantity=1; bool selected=false,selectable=false; std::string reason; };
struct TradeExchange { bool open=false; uint64_t receipt=0; uint8_t side=0; bool canSubmit=false; uint32_t merchantCount=0,fortCount=0,merchantSelected=0,fortSelected=0; int32_t entityId=-1,merchantId=-1,brokerId=-1; std::string reply,reason; uint8_t outcome=0; };
struct TradeState { std::vector<TradeDepot> depots; std::vector<TradeCaravan> caravans; std::vector<TradeGood> goods; uint32_t nextCursor=0; int32_t selectedDepot=-1; std::string detail; TradeExchange exchange; };
struct StockCount { uint32_t amount=0; uint8_t accuracy=0; };
struct StockCategory { int32_t id=0; std::string name; StockCount available,unavailable; };
struct StockItem { int32_t id=0,category=0; std::string description; uint32_t quantity=1; int32_t x=-1,y=-1,z=-1; bool canFocus=false; };
struct StocksState { bool open=false; uint64_t receipt=0; std::vector<StockCategory> categories; std::vector<StockItem> items; uint32_t nextCursor=0; int32_t category=-1; std::string detail; };
struct AppointmentRole { int32_t entityId=0,positionId=0,assignmentId=-1,unitId=-1; std::string name,holder; int32_t office=0,bedroom=0,dining=0,tomb=0,boxes=0,cabinets=0,racks=0,stands=0; bool actionable=false; std::string reason; };
struct AppointmentCandidate { int32_t unitId=-1; std::string name,skill; bool selectable=false; std::string reason; };
struct AppointmentsState { bool open=false,choosing=false; uint64_t receipt=0; std::vector<AppointmentRole> roles; std::vector<AppointmentCandidate> candidates; std::string detail; };
struct KitchenRequest { int32_t itemType=-1,matIndex=-1; int16_t itemSubtype=-1,matType=-1; uint8_t permission=0; int8_t allowed=-1; uint64_t receipt=0; uint32_t cursor=0; std::string query; };
struct KitchenIngredient { int32_t itemType=0,matIndex=-1; int16_t itemSubtype=-1,matType=-1; std::string name; uint32_t count=0; bool canCook=false,canBrew=false,cookAllowed=false,brewAllowed=false; };
struct KitchenState { bool open=false; uint64_t receipt=0; std::vector<KitchenIngredient> ingredients; uint32_t nextCursor=0,total=0; std::string detail; };
struct AppointmentsRequest { int32_t entityId=-1,positionId=-1,assignmentId=-1,unitId=-1; uint64_t receipt=0; };
struct StocksRequest { int32_t category=-1,itemId=-1; uint32_t cursor=0; std::string query; uint64_t receipt=0; };
struct ConstructionInput {
  int32_t id = -1;
  std::string description;
  uint32_t quantity = 1;
};
struct ManagementRequest {
  ManagementAction action = ManagementAction::Catalog;
  std::string definition;
  int32_t x = 0, y = 0, z = 0;
  uint16_t width = 1, height = 1;
  uint8_t direction = 0;
  std::vector<int32_t> items;
  uint32_t cursor = 0;
  int32_t buildingId = -1;
  AreaRequest area;
  ProductionRequest production;
  WorkOrderRequest workOrder;
  CitizenRequest citizen;
  ReportRequest report;
  AgreementRequest agreement;
  TradeRequest trade;
  StocksRequest stocks;
  AppointmentsRequest appointments;
  KitchenRequest kitchen;
  AlertRequest alert;
  SelectionRequest selection;
  int32_t creatureUnitId=-1;
  uint16_t depth=1; bool retracting=false; int16_t filter=-1;
  uint32_t rollerSpeed=0;
  bool cancelRemoval=false;
  struct TrackStopOptions { uint32_t friction=50000; uint8_t dumpDirection=0; };
  std::optional<TrackStopOptions> trackStop;
  struct PressurePlateOptions {
    bool units=false, water=false, magma=false, citizens=false, resets=true, track=false;
    int32_t unitMin=5000, unitMax=200000;
    int8_t waterMin=1, waterMax=7, magmaMin=1, magmaMax=7;
    int32_t trackMin=1, trackMax=2000;
  };
  std::optional<PressurePlateOptions> pressurePlate;
  // origin x/y/z is the press point; endpoint order must not be normalized.
  std::optional<TilePos> connectedTrackDestination;
  std::optional<TilePos> materialAnchor;
  std::vector<ConstructionSelection> selections; int64_t expectedListRevision=0;
};
struct ManagementState {
  uint64_t revision = 0, worldEpoch = 0, requestSeq = 0;
  ManagementAction action = ManagementAction::Catalog;
  ManagementStatus status = ManagementStatus::Idle;
  std::string message;
  std::vector<BuildingDefinition> catalog;
  std::vector<ConstructionInput> inputs;
  uint16_t required = 0;
  uint32_t nextCursor = 0;
  bool placementValid = false, removing = false;
  bool terrainConstruction = false;
  int32_t buildingId = -1;
  int16_t buildStage = -1, maxStage = -1;
  uint16_t jobs = 0;
  AreaState area;
  ProductionState production;
  WorkOrderState workOrder;
  CitizenState citizen;
  ReportState report;
  AgreementState agreement;
  TradeState trade;
  StocksState stocks;
  AppointmentsState appointments;
  KitchenState kitchen;
  AlertState alert;
  SelectionState selection;
  CreatureInfo creature;
  ConstructionState construction;
};
// Independent per-connection replies; reconnect first refreshes a read-only catalog.
// No request is replayed after process/world change. One pending request per client.
class ManagementClient {
 public:
  static std::unique_ptr<ManagementClient> open(std::string& error, const std::string& name = {});
  ~ManagementClient();
  bool poll();
  // False only when this connection's producer identity has ended/replaced.
  // Unlike poll(), unchanged state and malformed replies do not imply loss.
  bool transportAlive() const;
  uint64_t send(const ManagementRequest& request);
  const ManagementState& state() const { return state_; }
  const std::string& lastError() const { return error_; }

 private:
  ManagementClient();
  struct Impl;
  std::unique_ptr<Impl> impl_;
  ManagementState state_;
  std::string error_;
  uint64_t clientId_ = 0, seq_ = 0, pending_ = 0;
  bool catalogReady_ = false;
};
}  // namespace wm
