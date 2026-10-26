#pragma once
#include <optional>
#include <cstdint>
#include <string>
#include <array>
#include <vector>
namespace df { struct building_civzonest; struct unit; struct item; }
namespace df3d_area {
// Caller supplies a newly allocated zone and its selected type, at one safe point.
// Includes native initial range direction from supplied extents and target
// centers. Does not allocate, publish or assign occupants.
// Native heading choice is inline; read only semantic contents and pinned
// immutable dispatch/text, never renderer state. Result retains DF encoding.
std::optional<std::string> nativeZoneName(const df::building_civzonest& zone);
bool nativeZoneDefaultsReady();
bool nativeZoneDefaults(df::building_civzonest& zone);
bool nativeZoneOwnerReady();
// Independent native picker predicate with owned context/entry storage.
// Native may refresh semantic historical-figure/position lookup indices.
bool nativeZoneOwnerCandidatesReady();
std::optional<bool> nativeZoneOwnerEligible(df::building_civzonest& zone,df::unit& candidate);
// New-zone admission uses owned unassigned-owner facts; no allocation/publication.
std::optional<bool> nativeZoneNewOwnerEligible(int32_t zoneType,df::unit& candidate);
struct ZoneOwnerOrderFacts {
    bool withoutRoom;int32_t priority;int32_t category;int32_t categoryStatus;
    int32_t stress;std::string nameKey,professionKey;
};
// Semantic keys used by native partition, permanent priority and selectable header callbacks.
std::optional<ZoneOwnerOrderFacts> nativeZoneOwnerOrderFacts(df::building_civzonest& zone,df::unit& candidate);
struct ZoneOwnerRoomStatus { int32_t value=0; std::string label; };
// Owned-room value and native quality label; no widget/drawing state.
std::optional<ZoneOwnerRoomStatus> nativeZoneOwnerRoomStatus(df::building_civzonest& zone,df::unit& candidate);
struct ZoneOwnerDisplayText { std::string combined,name,profession,firstLine,secondLine; };
// Native display readers write caller-owned DF-encoded strings; no renderer call.
std::optional<ZoneOwnerDisplayText> nativeZoneOwnerDisplayText(df::unit& candidate,int32_t columns);
struct ZoneOwnerColorSources {
    int32_t identityId=-1,identityProfession=-1,identityImpersonatedHistfig=-1;
    int32_t positionId=-1,entityId=-1,assignmentId=-1;
    bool positionHasColor=false;
    std::array<int16_t,3> positionColor{};
    int16_t slaveStrength=0,prisonerStrength=0,imprisonerStrength=0;
    int32_t deityHistfigId=-1;
    bool deity=false;
    // Ordinary stage only: early overrides and animated effects are separate.
    std::array<uint8_t,3> ordinaryColor{};
    std::array<uint8_t,3> ordinaryFlashColor{};
};
// Native identity, noble position and historical-link strengths, plus owned
// ordinary color precedence. Early overrides and animated effects are separate.
std::optional<ZoneOwnerColorSources> nativeZoneOwnerColorSources(df::unit& candidate);
// Base profession/raw color from pinned native inline dispatch, with the
// owner widget's background0. No identity/noble/status precedence or animation.
std::optional<std::array<uint8_t,3>> nativeZoneOwnerProfessionColor(const df::unit& candidate,int16_t profession);
struct ZoneOwnerNameColor {
    std::array<uint8_t,3> color{},alternate{};
    // Effect:0 steady,1 legendary (333/1000ms),2 nemesis (500/1000ms),3 fire.
    uint8_t effect=0;
    // Source:0 ordinary,1 unit override,2 ghost,3 undead part,4 water,5 fire.
    uint8_t source=0;
};
// Fortress owner-name color/effect facts. Never reads drawing globals or consumes
// native clock/RNG; animation remains presentation-owned.
std::optional<ZoneOwnerNameColor> nativeZoneOwnerNameColor(df::unit& candidate);
struct ZoneAnimalUnitDisplay {
    ZoneOwnerDisplayText text;
    ZoneOwnerNameColor nameColor;
    bool grazer=false;
    std::string warning;
};
// Animal variant of the same semantic text/color readers. The cached native
// caste flag and immutable warning are independent of widgets and drawing.
std::optional<ZoneAnimalUnitDisplay> nativeZoneAnimalUnitDisplay(df::unit& candidate,int32_t columns);
// Native row-status facts; no artwork, widget state or drawing-cache references.
struct ZoneAnimalStatus {
    // 0 none, 1 pasture, 2 pit, 3 pond, 4 item, 5 native missing-container fallback.
    uint8_t kind=0;
    // 0 no containment help, 1 chained, 2 caged, 3 assigned chain, 4 assigned cage.
    uint8_t containment=0;
    int32_t itemId=-1;
};
std::optional<ZoneAnimalStatus> nativeZoneAnimalStatus(df::building_civzonest& picker,df::unit& candidate);
// Item rows use caller-owned selection membership, never the native widget set.
std::optional<ZoneAnimalStatus> nativeZoneAnimalItemStatus(df::building_civzonest& picker,bool selected);
struct ZoneAnimalContainer {
    // Original cage variant: 0 metal/default, 1 wood, 2 glass.
    uint8_t materialFamily=0;
    std::string solidColor;
    int32_t colorId=-1;
    // First eligible occupant, preserving native reference order: 0 none, 1 unit, 2 item.
    uint8_t occupantEntity=0;
    int32_t occupantId=-1;
};
std::optional<ZoneAnimalContainer> nativeZoneAnimalContainer(df::item& container);
// Normalize caller-owned textbox bytes with the native search routine.
std::optional<std::string> nativeZoneOwnerQuery(std::string query);
// Native may allocate and transfer ownership from another tomb. Callers mark
// the outcome unknown before entry; no automatic rollback or retry is valid.
bool nativeZoneSetOwner(df::building_civzonest& zone,df::unit* owner);
// Native animal assignment with semantic chain-job holder detachment.
// Call only at a safe point after request/admission/staleness validation.
// Entering this function can partially mutate; never retry an unknown result.
bool nativeZoneAnimalAssignmentReady();
struct ZoneAnimalCandidate { int32_t id; bool item; bool assigned; };
// Raw native producer order, before widget search/sorting. Owns all output;
// never reads the native selector. Unsupported/oversized lists fail closed.
std::optional<std::vector<ZoneAnimalCandidate>> nativeZoneAnimalCandidates(const df::building_civzonest& zone);
// Owned native description search and selected-first ordering. Query is DF
// encoded. sort0/2 Category,1 Name,3 Profession; no sort keys leave the bridge.
std::optional<std::vector<ZoneAnimalCandidate>> nativeZoneAnimalPickerCandidates(
    const df::building_civzonest& zone,int32_t sort,bool descending,std::string query);
// Native decorated critter text in DF encoding, written to an owned string.
// Does not call the item-name widget or its display-color method.
std::optional<std::string> nativeZoneAnimalItemText(df::item& item);
bool nativeZoneItemEligible(const df::building_civzonest& zone,const df::item& item);
bool nativeZoneAssignItem(df::building_civzonest& zone,df::item& item,bool assign);
bool nativeZoneAssignUnit(df::building_civzonest& zone,df::unit& unit,bool assign);
bool nativeZoneCreateReady();
bool nativeZoneMultiReady();
// Read-only native room tile eligibility. Caller preflights CreateReady at
// the same safe point; no movement search or native menu scratch is used.
bool nativeZoneTileEligible(int16_t x,int16_t y,int16_t z);
// Multi categorizes before the native Bedroom-to-Dormitory conversion.
// Refresh overlaps once after the complete batch, not once per room.
bool nativeZoneCompleteMulti(df::building_civzonest& zone);
bool nativeZoneRefreshOverlaps();
bool nativeZoneRemoveReady();
// May retire the object. Never inspect zone after this call.
// Multi Undo observes overlap before each retirement; ordinary Remove
// refreshes surviving zones as the native ordinary panel does.
enum class ZoneRemovalKind { Ordinary, MultiUndo };
bool nativeZoneRemove(df::building_civzonest& zone,ZoneRemovalKind kind=ZoneRemovalKind::Ordinary);
// The factory publishes an ID immediately. DF owns the returned pointer;
// callers must prepare all local allocations before entering and never delete it.
df::building_civzonest* nativeZoneAllocate();
bool nativeZoneComplete(df::building_civzonest& zone);
// Rebuild native reciprocal room membership and owned overlap observations.
bool nativeZoneRefresh(df::building_civzonest& zone);
}
