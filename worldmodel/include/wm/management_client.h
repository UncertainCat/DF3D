#pragma once
#include "wm/types.h"
#include <cstdint>
#include <array>
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
enum class CreatureHealthPageKind : uint8_t { Status, Wounds, Treatment, History, Description };
struct CreatureHealthPage { CreatureHealthPageKind kind=CreatureHealthPageKind::Status; std::vector<std::string> rows; };
enum class CreatureSkillsPageKind : uint8_t { Labor, Combat, Social, Other, Knowledge };
struct CreatureSkillRow { int32_t id=-1,knowledgeType=-1;uint32_t knowledgeBits=0;int32_t rating=0,rustValue=0;std::string caption,subtitle;int16_t captionColor=-1; };
struct CreatureSkillsPage { CreatureSkillsPageKind kind=CreatureSkillsPageKind::Labor;std::vector<CreatureSkillRow> rows; };
struct CreatureInfo {
  int32_t unitId=-1,age=-1,sex=-1,x=-1,y=-1,z=-1;
  uint64_t capturedTick=0;
  std::string name,species,profession,job;
  bool complete=false;
  std::vector<CreatureSection> sections;
  std::vector<CreatureHealthPage> healthPages;
  std::vector<CreatureSkillsPage> skillsPages;
  SelectionAppearance portrait;
};
struct AreaSpan { int16_t y=0,x=0; uint16_t length=0; };
struct AreaZoneSettings {
  uint8_t pondMode=0,facing=0;
  int8_t tombCitizens=-1,tombPets=-1,gatherTrees=-1,gatherShrubs=-1,gatherFallen=-1;
  friend bool operator==(const AreaZoneSettings&,const AreaZoneSettings&)=default;
};
struct AreaPaintPreview { int16_t x=0,y=0; uint16_t width=0,height=0; };
struct LocationNameQuery { uint8_t component=0; std::vector<uint8_t> queryBytes; uint32_t cursor=0; };
struct LocationNameEdit {
  LocationNameMode mode=LocationNameMode::Clear;
  int8_t target=-1,displayed=-1; int32_t word=-1;int16_t part=-1;
  std::vector<uint8_t> queryBytes;
};
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
  int32_t religiousEntityId=-1,religiousAssignmentId=-1,religiousHolderId=-1;
  int8_t quantityId=-1;
  LocationQuantityMode quantityMode=LocationQuantityMode::Set;
  int32_t quantityValue=0;
  std::optional<LocationNameQuery> nameQuery;
  std::optional<LocationNameEdit> nameEdit;
  bool categoryOpening=false;
  std::optional<std::vector<uint8_t>> queryBytes;
  uint16_t candidateLimit=0;
  int32_t itemId=-1;
};
struct AreaInfo {
  int32_t id=-1,x=0,y=0,z=0;
  AreaKind kind=AreaKind::Stockpile;
  std::string name,customName,ownerName;
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
  int32_t locationId=-1,tileCount=-1,assignedCount=-1,locationSiteId=-1,storageLimit=-1;
  int8_t organic=-1,inorganic=-1,overlapping=-1;
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
struct AreaNameColor { std::array<uint8_t,3> color{},alternate{}; uint8_t effect=0; };
struct AreaOwnerDisplay { uint16_t columns=0; std::string firstLine,secondLine,status; int32_t roomValue=0; std::optional<AreaNameColor> nameColor; };
struct AreaAnimalRestraint { bool rope=false; std::string solidColor; };
struct AreaAnimalContainer { uint8_t materialFamily=0,occupantEntity=0; std::string solidColor; int32_t occupantId=-1; std::optional<SelectionAppearance> occupant; };
struct AreaAnimalStatus { uint8_t kind=0,containment=0; int32_t itemId=-1; };
struct AreaAnimalDisplay { uint16_t columns=0; std::string firstLine,secondLine; bool combinedFits=false; std::string warning; AreaNameColor nameColor; };
struct AreaCandidateRow {
  int32_t id=-1;
  std::string name,profession;
  int8_t sex=-1;
  uint8_t mood=0;
  bool grazer=false,assigned=false;
  int8_t squadUse=-1;
  std::optional<AreaOwnerDisplay> ownerDisplay;
  std::optional<SelectionAppearance> sheetIcon;
  AreaCandidateEntity entity=AreaCandidateEntity::Unknown;
  std::optional<AreaAnimalDisplay> animalDisplay;
  std::optional<AreaAnimalStatus> animalStatus;
  std::optional<AreaAnimalContainer> animalContainer;
  std::optional<AreaAnimalRestraint> animalRestraint;
  std::optional<std::array<uint8_t,3>> animalItemColor;
  // Saved symbol index, foreground RGB, background RGB (seven unsigned bytes).
  std::optional<std::array<uint8_t,7>> squadSymbol;
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
struct LocationStaffAssignment {
  LocationStaffAssignmentKind kind=LocationStaffAssignmentKind::Occupation;
  int32_t id=-1,type=-1,subtype=-1,custom=-1;std::string name,customCode;
};
struct LocationStaffCandidate {
  int32_t unitId=-1,histfigId=-1,score=0,professionColor=-1;
  std::string name,baseName,professionName; bool legendary=false;
  int32_t sourceIndex=-1,professionOrder=-1,statusOrder=-1;
  std::vector<uint8_t> nameSortKey,professionSortKey;
  std::vector<LocationStaffSkill> skills;
  std::vector<LocationStaffAssignment> assignments;
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
struct LocationNameValue {
  std::vector<uint8_t> firstNameBytes,nicknameBytes;
  std::vector<int32_t> words;std::vector<int16_t> parts;
  int32_t language=-1;int16_t type=-1;bool hasName=false;
};
struct LocationNameSnapshot {
  int32_t siteId=-1,id=-1,namerId=-1;int16_t namerRace=-1;uint8_t kind=0;
  int64_t revision=0;LocationNameValue value;std::string nativeHeader,englishHeader;
};
struct LocationNameChoice { int32_t word=-1;int16_t part=-1;std::string english,translated; };
struct LocationNamePage {
  LocationNameSnapshot snapshot;uint8_t component=0;std::vector<uint8_t> queryBytes;
  uint32_t cursor=0,total=0,nextCursor=0;bool truncated=false;
  std::vector<LocationNameChoice> choices;
};
struct LocationRecognition {
  int32_t siteId=-1,locationId=-1,religionId=-1;int64_t revision=0;
  int32_t tier=-1,rank=0,worshippers=0,priestThreshold=0,highPriestThreshold=0;
  LocationRecognitionState state=LocationRecognitionState::NoAction;
  std::vector<int32_t> continuingAgreements;
};
struct LocationReligiousStaff {
  int32_t siteId=-1,locationId=-1,entityId=-1,assignmentId=-1,positionId=-1,holderId=-1,unitId=-1;
  int64_t revision=0;bool removable=false;
};
struct LocationReligiousCandidates {
  LocationReligiousStaff target;
  int64_t revision=0;uint32_t cursor=0,nextCursor=0,total=0;
  std::vector<LocationStaffCandidate> rows;
};
struct LocationReligiousAssignment {
  LocationReligiousStaff target;
  int32_t unitId=-1,histfigId=-1,nemesisId=-1;
  int64_t revision=0,listRevision=0;bool eligible=false;
};
struct LocationSpecialization {
  int32_t siteId=-1,locationId=-1,occupationId=-1,entityId=-1,assignmentId=-1,unitId=-1,histfigId=-1;
  int64_t revision=0;bool eligible=false,specialized=false;
};
struct LocationStaffAssignments {
  int32_t siteId=-1,locationId=-1,occupationId=-1,entityId=-1,assignmentId=-1,unitId=-1,histfigId=-1;
  int64_t revision=0;std::vector<LocationStaffAssignment> entries;
};
struct AreaState {
  std::optional<LocationStaffAssignments> locationStaffAssignments;
  std::optional<LocationSpecialization> locationSpecialization;
  std::optional<LocationReligiousCandidates> locationReligiousCandidates;
  std::optional<LocationReligiousAssignment> locationReligiousAssignment;
  std::optional<LocationReligiousStaff> locationReligiousStaff;
  std::optional<LocationRecognition> locationRecognition;
  std::optional<LocationNameSnapshot> locationName;
  std::optional<LocationNamePage> locationNamePage;
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
  std::optional<std::vector<uint8_t>> queryBytes;
  uint8_t candidateKind=0,sort=0,buildPhase=0;
  bool sortDescending=false;
  std::vector<AreaSettingRow> settings;
  std::vector<AreaLocationRow> locations;
  std::vector<AreaCandidateRow> candidates;
  std::vector<AreaLinkRow> links;
  int64_t listRevision=0,capturedTick=-1;
  uint32_t buildDone=0,buildTotal=0,omitted=0;
  int32_t settingsCount=-1;
  int64_t interactionId=0,undoToken=0;
  AreaRoomOutcome roomOutcome=AreaRoomOutcome::None;
  uint32_t roomsCreated=0,roomsInUse=0,roomsUnenclosed=0,roomsRemoved=0;
  uint32_t roomsDormitories=0;
  int64_t countGeneration=0;
  int32_t paintedCount=-1,previewCount=-1;
};
struct ProductionRequest {
  int32_t itemId=-1;int8_t itemValue=-1;
  int32_t contentsItemId=-1;
  bool contents=false,locateItem=false,independentItem=false,buildingHeader=false,workshopWorkers=false;
  int32_t workerId=-1;uint64_t workerListRevision=0;int8_t workerValue=-1;
  bool workshopOrders=false;int8_t generalOrderDelta=0;int16_t generalOrderValue=-1;
  FarmOperation farmOperation=FarmOperation::Crop;
  int8_t seasonalFertilization=-1;
  std::string farmName;
  uint64_t expectedRevision=0;
  int32_t buildingId=-1,jobId=-1,cropId=-1;
  std::string recipe,query;
  uint32_t cursor=0;
  int8_t repeat=-1,suspend=-1,season=-1;
  bool cancel=false;
};
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
struct ItemContainerContentFacts {
    int16_t itemType=-1;
    std::string materialToken,colorToken;
    int8_t effectiveArmorLevel=0;
    bool metal=false,coal=false,containsPowder=false;
    bool rollsSheets=false,protectsFoldedSheets=false,containsWriting=false;
    bool liquid=false,subterraneanPlant=false;
};
struct ItemContainerContentsFacts {
    bool container=false;
    std::vector<ItemContainerContentFacts> entries;
    int8_t materialInorganic=-1;std::string solidColor;
};
struct ItemInspectionAppearance { std::string materialToken,subtypeRaw,colorToken;int32_t stack=1;uint8_t flags=0;int8_t instrumentFamily=-1,instrumentPlaced=-1;std::optional<ItemContainerContentsFacts> contents={};int8_t floodgateOpen=-1,doorOpen=-1,doorForbidden=-1,doorWear=-1,bucketLiquid=-1;std::string bucketLiquidColor; int8_t cageMaterialFamily=-1,cageOccupantEntity=-1;int32_t cageOccupantId=-1;std::string cageSolidColor;int8_t restraintRope=-1;std::string restraintSolidColor;std::optional<SelectionAppearance> portrait,cageOccupant;int8_t slabEngraving=-2;std::optional<SelectionAppearance> corpseSelector,legwearSelector;std::optional<std::string> craftGemColor;int8_t craftSoftMaterial=-1,artifactMood=-1,coffinUnused=-1; };
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
struct BuildingItemReceipt { int32_t itemId=-1;FarmOperation operation=FarmOperation::Crop;int8_t value=-1; };
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
struct ItemSheetContent { int32_t kind=0,id=-1,itemType=-1;std::string caption;uint32_t flags=0;bool canDump=false,canMelt=false;std::optional<ItemInspectionAppearance> appearance; };
struct ItemUseRow {std::string caption;int32_t reaction=-1;};
struct IndependentItemSnapshot {
    std::optional<std::vector<ItemUseRow>> uses;
    std::optional<std::vector<ItemSheetContent>> contents;
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
  FarmEditOutcome outcome=FarmEditOutcome::None;
};
struct BuildingHeaderSnapshot {
  int32_t id=-1,type=-1,stage=-1,maxStage=-1;uint64_t revision=0;
  std::string customName,nativeName,headerName;
  bool removing=false,suspended=false,hasWorker=false;
};
struct BuildingHeaderState {
  std::optional<BuildingHeaderSnapshot> snapshot;
  FarmEditOutcome outcome=FarmEditOutcome::None;
  FarmOperation operation=FarmOperation::Crop;
};
struct WorkshopAssignedWorker {
  int32_t id=-1;std::string caption;
  bool specializationVisible=false,canSpecialize=false,specialized=false;
};
struct WorkshopWorkersState {
  std::optional<WorkshopAssignedWorker> assigned;
  FarmOperation operation=FarmOperation::Crop;
  int32_t buildingId=-1,unitId=-1;
  uint64_t profileRevision=0,revision=0;
  uint32_t cursor=0,nextCursor=0,total=0;
  std::vector<int32_t> permittedWorkers;
  std::vector<LocationStaffCandidate> rows;
  FarmEditOutcome outcome=FarmEditOutcome::None;
};
struct WorkshopOrdersState {
  int32_t buildingId=-1,generalOrderLimit=0;
  uint64_t revision=0;bool managerAvailable=false;
  std::vector<int32_t> orderIds;int8_t delta=0;int16_t value=-1;
  FarmEditOutcome outcome=FarmEditOutcome::None;
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
  FarmEditOutcome farmEditOutcome=FarmEditOutcome::None;
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
struct StocksGroupKey {int16_t type=-1,subtype=-1,subcat1=-1,subcat2=-1;};
struct NoblesOffice {int32_t entityId=-1,positionId=-1,assignmentId=-1;uint32_t draftSlot=0;};
struct NoblesChoice {NoblesOffice target;int32_t expectedUnitId=-1,unitId=-1;};
struct NoblesSymbolChoice {int32_t itemId=-1;bool selected=false;};
struct NoblesRequest {uint32_t offset=0;uint16_t limit=32;uint64_t expectedListRevision=0;
  std::vector<NoblesChoice> choices;std::optional<NoblesOffice> target;uint64_t expectedCandidateRevision=0;int8_t expectedSetting=-1,setting=-1;
  std::vector<NoblesSymbolChoice> symbolChoices;uint64_t stepToken=0,expectedNameRevision=0;
  std::optional<LocationNameQuery> nameQuery;std::optional<LocationNameEdit> nameEdit;};
struct NoblesSymbol {int32_t itemId=-1;int16_t itemType=-1;int32_t value=0;
  std::optional<NoblesOffice> currentOffice,selectedOffice;
  std::string caption,officeCaption,valueCaption;std::optional<ItemInspectionAppearance> appearance;bool artifactMood=false;};
struct NoblesSymbolStep {uint64_t token=0;int32_t namingArtifactId=-1;uint32_t remaining=0;};
struct NoblesSymbolName {int32_t artifactId=-1,itemId=-1;uint64_t revision=0;LocationNameValue value;
  std::string nativeHeader,englishHeader;uint8_t component=0;std::vector<uint8_t> queryBytes;
  uint32_t cursor=0,total=0,nextCursor=0;std::vector<LocationNameChoice> choices;};
struct NoblesCandidateSkill {int16_t id=-1;int32_t rating=0;std::string caption;};
struct NoblesCandidate {int32_t unitId=-1,value=0;std::string caption,noSkills;
  std::vector<NoblesCandidateSkill> skills;std::optional<SelectionAppearance> appearance;};
struct NoblesAssessmentHelp {std::string actual,required;uint8_t color=15;};
struct NoblesObligationHelp {std::string text;uint8_t color=15;};
struct NoblesAccountingHelp {uint8_t setting=0,level=0;std::string title,examples,attained,progress;};
struct NoblesHelp {std::string description;std::array<NoblesAssessmentHelp,4> rooms,furniture;
  std::vector<NoblesObligationHelp> demands,mandates;std::optional<NoblesAccountingHelp> accounting;};
struct NoblesRow {
  uint32_t draftSlot=0;
  int32_t entityId=-1,positionId=-1,assignmentId=-1,unitId=-1,nemesisId=-1,priority=0;
  std::string title,squadCaption,holderCaption;bool canAppoint=false,hasRoomAssessment=false;
  std::array<int32_t,4> requiredRooms{},actualRooms{},requiredFurniture{},actualFurniture{};
  int8_t demandStatus=-1,mandateStatus=-1;
  std::optional<NoblesHelp> help;
  std::optional<SelectionAppearance> appearance;
};
struct NoblesState {
  NoblesOutcome outcome=NoblesOutcome::None;uint64_t listRevision=0;uint32_t total=0,offset=0;
  std::vector<NoblesRow> rows;
  std::optional<NoblesOffice> target;uint64_t candidateRevision=0;std::vector<NoblesCandidate> candidates;
  std::vector<NoblesSymbol> symbols;std::optional<NoblesSymbolStep> step;std::optional<NoblesSymbolName> name;
  std::optional<std::string> symbolTargetCaption;
};
// Pointer-free Justice reads retain native row order and paired witness dates.
struct JusticeSort {JusticeCandidateColumn column=JusticeCandidateColumn::Category;bool reverse=false;};
struct JusticeRequest {
  uint8_t tab=0;uint32_t offset=0;uint16_t limit=32;
  uint64_t expectedListRevision=0;int32_t crimeId=-1;uint64_t expectedCaseRevision=0;
  std::string query;uint64_t expectedCandidateRevision=0;int32_t unitId=-1;
  std::vector<JusticeSort> sorts={{JusticeCandidateColumn::Crime,false},{JusticeCandidateColumn::Name,false}};
};
struct JusticeCaseRow {int32_t crimeId=-1;std::string caption;};
struct JusticeWitnessRow {std::string witness,description,date,reported;};
struct JusticeCaseDetail {
  JusticeCaseResolution resolution=JusticeCaseResolution::None;
  int32_t crimeId=-1;uint64_t revision=0;std::string caption;
  std::optional<std::string> injuredParty;std::string status;
  uint32_t total=0,offset=0;std::vector<JusticeWitnessRow> witnesses;
};
struct JusticeCandidateDisplay {
  uint16_t columns=0;std::string name;AreaNameColor nameColor;
  uint32_t witnessCount=0;std::string witnessLabel;uint8_t witnessColor=0;std::string deceased;
};
struct JusticeCandidateRow {
  int32_t unitId=-1,rank=0;bool interrogationPending=false,counterintelligence=false;
  JusticeCandidateDisplay display;
};
struct JusticeCandidatePage {
  int32_t crimeId=-1;uint64_t revision=0;uint32_t total=0,offset=0;std::vector<JusticeCandidateRow> rows;
};
struct JusticeState {
  JusticeOutcome outcome=JusticeOutcome::None;uint8_t tab=0;uint64_t listRevision=0;
  uint32_t total=0,offset=0;std::vector<JusticeCaseRow> rows;std::optional<JusticeCaseDetail> detail;
  std::optional<JusticeCandidatePage> candidates;
};
struct ObjectsRequest {uint8_t tab=0;uint32_t offset=0;uint16_t limit=32;uint64_t expectedListRevision=0;int32_t artifactId=-1;};
struct ObjectsRow {
  int32_t artifactId=-1,itemId=-1;int16_t itemType=-1;std::string nativeName,translatedName,ownership;
  std::optional<TilePos> position;std::optional<ItemInspectionAppearance> appearance;
};
struct ObjectsDestination {int32_t artifactId=-1,itemId=-1;std::optional<TilePos> position;};
struct ObjectsState {
  ObjectsOutcome outcome=ObjectsOutcome::None;uint8_t tab=0;uint64_t listRevision=0;uint32_t total=0,offset=0;
  std::vector<ObjectsRow> rows;std::optional<ObjectsDestination> destination;
};
struct PlacesRequest {uint8_t tab=0;uint32_t offset=0;uint16_t limit=32;uint64_t expectedListRevision=0;
  int32_t buildingId=-1;int8_t siegeAction=-1;};
struct PlacesRow {
  int32_t buildingId=-1;std::optional<TilePos> position;
  std::string name,subtitle,jobCaption,statusCaption,secondaryStatus,statusOverlay,operatorCaption;
  int32_t subtitleLocationId=-1,additionalJobs=0;int8_t siegeAction=-1;std::optional<SelectionAppearance> appearance;
};
struct PlacesState {
  PlacesOutcome outcome=PlacesOutcome::None;uint8_t tab=0;uint64_t listRevision=0;uint32_t total=0,offset=0;
  std::vector<PlacesRow> rows;int32_t buildingId=-1;int8_t siegeAction=-1;
};
struct TasksRequest {
  uint32_t offset=0;uint16_t limit=32;uint64_t expectedListRevision=0;
  int32_t jobId=-1,workerId=-1,buildingId=-1;uint64_t expectedRevision=0;
  TasksOperation operation=TasksOperation::Repeat;int8_t expectedState=-1;
};
struct TasksRow {
  int32_t jobId=-1,workerId=-1,buildingId=-1;uint64_t revision=0;
  std::string caption,workerName,buildingCaption;
  std::optional<TilePos> workerPosition,buildingPosition;
  std::optional<AreaNameColor> workerColor;
  bool canViewJob=false,canRepeat=false,canRemoveWorker=false,canSuspend=false,canCancel=false;
  bool repeating=false,suspended=false;
  std::optional<SelectionAppearance> workerAppearance,buildingAppearance;
};
struct TasksState {
  TasksOutcome outcome=TasksOutcome::None;uint64_t listRevision=0;uint32_t total=0,offset=0;
  std::vector<TasksRow> rows;int32_t jobId=-1;
};
struct StocksMenuRequest {int16_t category=-1;std::string query;std::vector<int32_t> itemIds;std::optional<StocksGroupKey> target;uint64_t expectedRevision=0;StocksFlagAction operation=StocksFlagAction::Forbid;int8_t value=-1;int32_t itemId=-1;uint64_t pageRequest=0;uint32_t pageOffset=0;};
struct StocksCategoryRow {int16_t type=-1;std::string caption,stored,unavailable;bool matches=false;};
struct StocksGroupRow {StocksGroupKey key;int32_t amount=0;std::string caption;bool matches=false,expanded=false;uint8_t flags=0;uint64_t revision=0;std::vector<int32_t> itemIds;};
struct StocksItemRow {int32_t id=-1;int16_t type=-1;std::string caption;uint32_t flags=0;bool canDump=false,canMelt=false;std::string materialToken,subtypeRaw;std::optional<ItemInspectionAppearance> appearance;};
struct StocksMenuState {StocksMenuOutcome outcome=StocksMenuOutcome::None;int16_t category=-1;std::vector<StocksCategoryRow> categories;std::vector<StocksGroupRow> groups;std::vector<StocksItemRow> items;};
struct StoneUseRequest {int32_t category=-1,index=-1;std::optional<std::vector<uint8_t>> expected;};
struct StoneUseRow {int32_t category=-1,index=-1;bool restricted=false;std::string name,uses;bool magmaSafe=false;std::string materialToken;};
struct StoneUseState {StoneUseOutcome outcome=StoneUseOutcome::None;std::vector<StoneUseRow> rows;std::vector<uint8_t> restrictions;};
struct KitchenFoodKey {int16_t itemType=-1,itemSubtype=-1,matType=-1;int32_t matIndex=-1;};
struct KitchenFoodReceipt {KitchenFoodKey key;int32_t count=0;uint8_t capabilities=0;};
struct KitchenExclusion {KitchenFoodKey key;uint8_t flags=0;};
struct KitchenSort {KitchenSortColumn column=KitchenSortColumn::Type;bool reverse=false;};
struct KitchenMenuQuery {int8_t typeFilter=-1;uint8_t capabilityFilter=0;std::string query;std::vector<KitchenSort> sorts{{}};};
struct KitchenMenuRequest {std::optional<KitchenMenuQuery> query;std::optional<KitchenFoodReceipt> target;uint8_t permission=0;std::optional<std::vector<KitchenExclusion>> expected;};
struct KitchenMenuRow {KitchenFoodReceipt receipt;std::string name,countCaption;bool estimated=false;uint8_t excluded=0;std::string materialToken;};
struct KitchenMenuState {KitchenMenuOutcome outcome=KitchenMenuOutcome::None;std::vector<KitchenMenuRow> rows;std::vector<KitchenExclusion> exclusions;};
struct ChoreLabor {int32_t id=-1;bool enabled=false;};
struct ChoresSnapshot {bool enabled=false;std::vector<int32_t> children,exempted;std::vector<ChoreLabor> labors;};
struct ChoresCaption {int32_t id=-1;std::string caption;};
struct ChoresRequest {ChoresOperation operation=ChoresOperation::None;int32_t id=-1;bool value=false;std::optional<ChoresSnapshot> expected;};
struct ChoresState {ChoresOutcome outcome=ChoresOutcome::None;std::optional<ChoresSnapshot> snapshot;std::vector<ChoresCaption> children,labors;};
struct HunterAmmunitionSpec {
  int16_t itemType=-1,itemSubtype=-1,materialClass=-1,matType=-1;
  int32_t matIndex=-1,amount=0;uint32_t flags=0;std::vector<int32_t> assigned;
};
struct HunterAmmunitionRequest {
  HunterAmmunitionOperation operation=HunterAmmunitionOperation::None;
  int32_t index=-1,itemId=-1,amount=-1;int16_t itemType=-1,itemSubtype=-1,materialClass=-1,matType=-1;int32_t matIndex=-1;
  std::vector<HunterAmmunitionSpec> expected;
};
struct HunterAmmunitionStack {int32_t id=-1;std::string caption;int32_t quantity=0;ItemInspectionAppearance appearance;};
struct HunterAmmunitionRule {std::string caption;int64_t quantity=0;std::vector<HunterAmmunitionStack> items;};
struct HunterAmmunitionType {int16_t itemType=-1,itemSubtype=-1;bool foreign=false;std::string caption;};
struct HunterAmmunitionMaterial {int16_t materialClass=-1,matType=-1;int32_t matIndex=-1;std::string caption;};
struct HunterAmmunitionState {
  HunterAmmunitionOutcome outcome=HunterAmmunitionOutcome::None;int16_t itemType=-1,itemSubtype=-1;
  std::vector<HunterAmmunitionSpec> specs;std::vector<HunterAmmunitionRule> rules;
  std::vector<HunterAmmunitionType> types;std::vector<HunterAmmunitionMaterial> materials;
};
struct StandingOrdersRequest { uint8_t category=0; int32_t settingId=-1; int8_t expectedValue=-1,value=-1; };
struct StandingOrderSetting { int32_t id=-1; uint8_t value=0; bool visible=false; bool editable=false; };
struct StandingOrdersState { uint8_t category=0; StandingOrdersOutcome outcome=StandingOrdersOutcome::None; std::vector<StandingOrderSetting> settings; };
struct WorkDetailSettingsRequest { int32_t detailIndex=-1; uint64_t expectedRevision=0; int32_t settingId=-1; };
struct WorkDetailSetting { int32_t id=-1; std::string caption; };
struct WorkDetailSettingsState { int32_t detailIndex=-1; uint64_t revision=0; bool editable=false,noModify=false; std::vector<int16_t> labors; std::vector<WorkDetailSetting> catalog; };
struct WorkDetailSort { WorkDetailWorkerSort column=WorkDetailWorkerSort::Skills; bool descending=false; };
struct WorkDetailWorkersRequest { int32_t detailIndex=-1; uint64_t expectedRevision=0; std::vector<WorkDetailSort> sorts{{}}; std::vector<uint8_t> queryBytes; };
struct ResidentsRequest { ResidentsSort sort=ResidentsSort::Category; bool descending=false; std::vector<uint8_t> queryBytes; };
struct ResidentsState { std::vector<int32_t> unitIds; };
struct ResidentsRowsRequest { std::vector<int32_t> unitIds; uint16_t columns=30; bool showGender=false; int32_t detailIndex=-1; uint64_t expectedRevision=0; };
struct ResidentSpecialization { bool onlyAssigned=false;uint64_t revision=0; };
struct ResidentsSpecializationRequest { int32_t unitId=-1;uint64_t expectedRevision=0;bool onlyAssigned=false; };
struct ResidentsSpecializationState { int32_t unitId=-1;ResidentsSpecializationOutcome outcome=ResidentsSpecializationOutcome::Rejected;bool onlyAssigned=false; };
struct ResidentJobTarget { int32_t jobId=-1,buildingId=-1; };
struct ResidentActivityTarget { int32_t activityId=-1,eventId=-1; };
struct ResidentsActivityRequest { int32_t unitId=-1,activityId=-1,eventId=-1;uint16_t columns=0; };
struct ActivityDescriptionWord { std::string text;uint8_t red=0,green=0,blue=0;int32_t link=-1;uint8_t flags=0;int32_t x=-1,y=-1; };
struct ActivityDescriptionLink { int32_t type=-1,id=-1,subid=-1; };
struct ResidentsActivityState {
  int32_t unitId=-1,activityId=-1,eventId=-1;uint16_t columns=0;int32_t maxY=0;
  std::vector<ActivityDescriptionWord> words;std::vector<ActivityDescriptionLink> links;
};
struct WorkDetailSkill { int16_t skill=-1; int32_t rating=0; std::string caption; };
struct ResidentRow {
  std::optional<std::vector<WorkDetailSkill>> workDetailSkills;
  int8_t detailMember=-1;
  std::optional<ResidentActivityTarget> activityTarget;
  std::optional<ResidentJobTarget> jobTarget;
  int32_t id=-1;
  std::optional<TilePos> position;
  std::optional<ResidentSpecialization> specialization;
  std::optional<std::vector<LocationStaffAssignment>> assignments;
  int8_t happiness=-1; // Unobserved, or native happiest0 through most distressed6.
  std::string combined,name,profession,firstLine,secondLine;
  AreaNameColor nameColor;
  std::string activity;
  uint8_t activityForeground=0,activityBackground=0; bool activityBright=false;
  std::optional<SelectionAppearance> sheetIcon;
};
struct ResidentsRowsState { std::vector<ResidentRow> rows; };
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
  bool outcomeUnknown=false;
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
enum class WorkOrderArtDraftAction:uint8_t {Inspect,AddElement,AddRelationship,Delete,GenerateName,Commit,EditName};
struct WorkOrderArtDraftElement {int16_t kind=0;int32_t id=-1,secondary=-1,quantity=1;};
struct WorkOrderArtDraftRelationship {int32_t verb=-1;bool transitive=false;int32_t actor=-1,target=-1;};
struct WorkOrderArtDraftValue {
  std::vector<WorkOrderArtDraftElement> elements;
  std::vector<WorkOrderArtDraftRelationship> relationships;
  std::optional<LocationNameValue> name;
};
struct WorkOrderArtDraftRequest {
  WorkOrderArtDraftValue value;WorkOrderArtDraftAction action=WorkOrderArtDraftAction::Inspect;
  std::optional<WorkOrderArtDraftElement> element;
  std::optional<WorkOrderArtDraftRelationship> relationship;
  int32_t deleteIndex=-1;uint16_t columns=0;
  std::optional<LocationNameQuery> nameQuery;
  std::optional<LocationNameEdit> nameEdit;
};
struct WorkOrderArtRequest {int16_t page=-1;int32_t subject=-1;uint64_t expectedListRevision=0;std::string query;uint32_t cursor=0;int32_t hovered=-1;uint16_t previewColumns=0;std::optional<WorkOrderArtDraftRequest> draft;};
struct WorkOrderDetailsRequest {int16_t option=-1;int32_t choice=-1;uint64_t expectedChoicesRevision=0;std::string query;uint32_t cursor=0;std::optional<WorkOrderArtRequest> art;int32_t dyeTarget=-1;bool dyeFilterApplied=false;};
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
  int16_t suggestionIndex=-1;
  int32_t filterChoice=-1;
  std::optional<WorkOrderDetailsRequest> details;
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
  std::optional<std::string> itemCaption;
};
struct WorkOrderInput { uint16_t index=0; std::string description; int16_t matType=-1; int32_t matIndex=-1; bool editable=false; };
struct WorkOrderMaterial { int16_t matType=-1; int32_t matIndex=-1; std::string name; };
struct WorkOrderTrait { std::string key,name; };
struct WorkOrderItemType { int16_t itemType=-1,itemSubtype=-1; std::string name; };
struct WorkOrderGroup { int16_t type=-1,subtype=-1; int32_t custom=-1; std::string name; uint32_t count=0; std::optional<std::string> customCode; };
struct WorkOrderTask { std::string key,name; int16_t jobType=-1; std::string reaction; int16_t itemType=-1,itemSubtype=-1,matType=-1; int32_t matIndex=-1; };
struct WorkOrderNativeState {
  WorkOrderPhase phase=WorkOrderPhase::Unknown;
  bool validationRequired=false,detailsAvailable=false;
  std::optional<std::string> workshopName;
};
struct WorkOrderInfo {
  std::optional<WorkOrderNativeState> nativeState;
  std::optional<std::vector<WorkOrderCondition>> suggestedConditions;
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
struct WorkOrderDetailsOption {uint8_t kind=0;int32_t index=-1;std::string caption;};
struct WorkOrderDyeColor {float red=0,green=0,blue=0;};
struct WorkOrderDetailsChoice {int32_t id=-1;std::string caption;std::optional<std::string> countCaption;bool estimated=false;int32_t dyeColor=-1;bool opensMenu=false;std::optional<WorkOrderDyeColor> swatch;};
struct WorkOrderArtRow {int32_t id=-1;std::string caption;std::optional<std::string> badge;int32_t secondary=-1;};
struct WorkOrderArtName {
  std::string nativeHeader,englishHeader;
  uint8_t component=0;std::vector<uint8_t> queryBytes;
  uint32_t cursor=0,total=0,nextCursor=0;
  std::vector<LocationNameChoice> choices;
};
struct WorkOrderArtState {
  int16_t page=-1;std::string caption;std::vector<WorkOrderArtRow> rows;
  uint64_t listRevision=0;uint32_t total=0,nextCursor=0;
  int32_t hovered=-1;std::optional<std::vector<std::string>> preview;
  std::optional<WorkOrderArtDraftValue> draft;
  std::optional<std::vector<std::string>> draftDescription;
  std::optional<WorkOrderArtName> name;
};
struct WorkOrderDetailsState {
  int32_t id=-1;uint64_t revision=0;std::string caption;
  std::vector<WorkOrderDetailsOption> options;
  int16_t selectedOption=-1;
  std::optional<std::vector<WorkOrderDetailsChoice>> choices;
  uint64_t choicesRevision=0;uint32_t total=0,nextCursor=0;
  std::optional<WorkOrderArtState> art;
  std::optional<std::string> currentValue;
  std::optional<std::string> settingHeading;
  int32_t dyeTarget=-1;
};
struct JobSettingsEditRequest {int32_t jobId=-1,buildingId=-1,unitId=-1;int16_t option=-1;uint64_t expectedRevision=0,expectedChoicesRevision=0;int32_t choice=-1;int16_t artPage=-2;std::string query;std::optional<WorkOrderArtRequest> art;};
struct JobSettingsEditState {int32_t jobId=-1,buildingId=-1,unitId=-1;JobSettingsEditOutcome outcome=JobSettingsEditOutcome::Rejected;};
struct JobSettingsRequest {int32_t jobId=-1,buildingId=-1,unitId=-1;int16_t option=-1;std::string query;uint32_t cursor=0;int16_t artPage=-2;uint64_t expectedListRevision=0;int32_t hovered=-1;uint16_t previewColumns=0;uint64_t expectedRevision=0;std::optional<WorkOrderArtRequest> art;};
struct JobSettingsChoice {int32_t id=-1;std::string caption;std::optional<std::string> countCaption;bool estimated=false;};
struct JobSettingsState {
  int32_t jobId=-1,buildingId=-1,unitId=-1;uint64_t revision=0;std::string caption;
  std::vector<WorkOrderDetailsOption> options;int16_t selectedOption=-1;
  std::vector<JobSettingsChoice> choices;uint64_t choicesRevision=0;uint32_t total=0,cursor=0,nextCursor=0;
  std::optional<std::string> currentValue,settingHeading;
  std::optional<WorkOrderArtState> art;
};
struct WorkOrderListNativeState { bool managerAvailable=false,validationRequired=false; };
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
  std::optional<WorkOrderListNativeState> nativeState;
  std::optional<WorkOrderDetailsState> details;
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
  BeddingFacts bedding;
  int8_t instrumentFamily=-1, instrumentPlaced=-1, slabEngraving=-2;
  std::string gemShapeRaw;
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
  uint32_t updated=0;int32_t failedIndex=-1;std::string warnings;
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
struct ContinuingAgreementRow {
 int32_t agreementId=-1,subjectId=-1,entityId=-1,entityType=-1,tier=-1,profession=-1,year=0,yearTick=0;
 std::string heading,applicant,date;
};
struct ContinuingAgreementDetails {int32_t requiredValue=-1,matchingLocations=0,locationId=-1,locationValue=0,locationTier=-1;bool siteAvailable=false,tierMet=false;std::string locationName;};
struct AgreementState {std::vector<AgreementInfo> agreements;int32_t nextBeforeId=-1;bool pendingOnly=false;std::string detail;bool tracker=false;std::vector<ContinuingAgreementRow> trackerRows;std::optional<ContinuingAgreementDetails> trackerDetails;};
struct AgreementRequest {int32_t id=-1,beforeId=-1;std::string query;bool pendingOnly=false,tracker=false;};
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
struct CreatureWorkshopRequest { int32_t unitId=-1,buildingId=-1; uint64_t expectedRevision=0; };
struct CreatureLocationRequest { int32_t unitId=-1,occupationId=-1; uint64_t expectedRevision=0; };
struct CreatureAnimalRequest { int32_t unitId=-1,animalId=-1; uint64_t expectedRevision=0; bool assigned=false; };
struct CreatureWorkshopState { int32_t unitId=-1,buildingId=-1; CreatureWorkshopOutcome outcome=CreatureWorkshopOutcome::Rejected; };
struct CreatureLocationState { int32_t unitId=-1,occupationId=-1; CreatureLocationOutcome outcome=CreatureLocationOutcome::Rejected; };
struct CreatureAnimalState { int32_t unitId=-1,animalId=-1; CreatureAnimalOutcome outcome=CreatureAnimalOutcome::Rejected; bool assigned=false; };
struct CreatureKnowledgeRequest { int32_t unitId=-1,kind=-1,id=-1; };
struct CreatureKnowledgeState { int32_t unitId=-1,kind=-1,id=-1; CreatureKnowledgeOutcome outcome=CreatureKnowledgeOutcome::Rejected; std::string text; };
struct CreaturePosition { int32_t unitId=-1; TilePos position; };
struct CreatureExpelRequest { int32_t unitId=-1,destinationId=-1; std::vector<int32_t> expectedUnitIds; };
struct CreatureExpelUnit { int32_t id=-1; std::string name; AreaNameColor nameColor; SelectionAppearance sheetIcon; };
struct CreatureExpelDestination { int32_t id=-1; std::string name; };
struct CreatureExpelPreview {
  int32_t unitId=-1; bool eligible=false; int32_t reason=-1;
  std::vector<CreatureExpelUnit> units; std::vector<CreatureExpelDestination> destinations;
};
struct CreatureExpelState { CreatureExpelOutcome outcome=CreatureExpelOutcome::Rejected; std::optional<CreatureExpelPreview> preview; };
struct CreatureHeaderRequest { int32_t unitId=-1; bool profession=false; uint64_t expectedRevision=0; std::string name; };
struct CreatureHeaderSnapshot {
  int32_t unitId=-1,historicalFigureId=-1; bool hasFigure=false; uint64_t revision=0;
  std::string nickname,profession,figureNickname;
};
struct CreatureHeaderState {
  CreatureHeaderOutcome outcome=CreatureHeaderOutcome::Rejected; bool mutated=false;
  std::optional<CreatureHeaderSnapshot> snapshot;
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
  CreatureHeaderRequest creatureHeader;
  CreatureExpelRequest creatureExpel;
  CreatureKnowledgeRequest creatureKnowledge;
  CreatureWorkshopRequest creatureWorkshop;
  CreatureLocationRequest creatureLocation;
  CreatureAnimalRequest creatureAnimal;
  ResidentsRequest residents;
  WorkDetailWorkersRequest workDetailWorkers;
  WorkDetailSettingsRequest workDetailSettings;
  StandingOrdersRequest standingOrders;
  HunterAmmunitionRequest hunterAmmunition;
  ChoresRequest chores;
  KitchenMenuRequest kitchenMenu;
  StoneUseRequest stoneUse;
  StocksMenuRequest stocksMenu;
  TasksRequest tasks;
  PlacesRequest places;
  ObjectsRequest objects;
  JusticeRequest justice;
  NoblesRequest nobles;
  ResidentsRowsRequest residentsRows;
  ResidentsSpecializationRequest residentsSpecialization;
  ResidentsActivityRequest residentsActivity;
  JobSettingsRequest jobSettings;
  JobSettingsEditRequest jobSettingsEdit;
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
struct WorldHoverEntry { std::string text; uint8_t foreground=7,background=0; bool bright=false; uint8_t kind=0; int32_t objectId=-1; };
struct WorldHover { int32_t x=-1,y=-1,z=-1; std::vector<WorldHoverEntry> entries; };
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
  std::optional<CreatureHeaderState> creatureHeader;
  std::optional<CreaturePosition> creaturePosition;
  std::optional<CreatureExpelState> creatureExpel;
  std::optional<CreatureKnowledgeState> creatureKnowledge;
  std::optional<CreatureWorkshopState> creatureWorkshop;
  std::optional<CreatureLocationState> creatureLocation;
  std::optional<CreatureAnimalState> creatureAnimal;
  std::optional<ResidentsState> residents;
  std::optional<ResidentsRowsState> residentsRows;
  std::optional<WorkDetailSettingsState> workDetailSettings;
  std::optional<StandingOrdersState> standingOrders;
  std::optional<HunterAmmunitionState> hunterAmmunition;
  std::optional<ChoresState> chores;
  std::optional<KitchenMenuState> kitchenMenu;
  std::optional<StoneUseState> stoneUse;
  std::optional<StocksMenuState> stocksMenu;
  std::optional<TasksState> tasks;
  std::optional<PlacesState> places;
  std::optional<ObjectsState> objects;
  std::optional<JusticeState> justice;
  std::optional<NoblesState> nobles;
  std::optional<ResidentsSpecializationState> residentsSpecialization;
  std::optional<ResidentsActivityState> residentsActivity;
  std::optional<JobSettingsState> jobSettings;
  std::optional<JobSettingsEditState> jobSettingsEdit;
  ConstructionState construction;
  std::optional<WorldHover> worldHover;
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
