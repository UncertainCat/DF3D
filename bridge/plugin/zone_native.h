#pragma once
#include <optional>
#include <cstdint>
#include <string>
#include <array>
namespace df { struct building_civzonest; struct unit; }
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
};
// Semantic identity and highest-priority noble position used by native name
// coloring. This is not a final color: precedence/effects remain separate.
std::optional<ZoneOwnerColorSources> nativeZoneOwnerColorSources(df::unit& candidate);
// Normalize caller-owned textbox bytes with the native search routine.
std::optional<std::string> nativeZoneOwnerQuery(std::string query);
// Native may allocate and transfer ownership from another tomb. Callers mark
// the outcome unknown before entry; no automatic rollback or retry is valid.
bool nativeZoneSetOwner(df::building_civzonest& zone,df::unit* owner);
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
