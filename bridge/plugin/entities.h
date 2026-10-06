#pragma once

#include <cstdint>
#include <string>

#include "ColorText.h"
#include "appearance.h"
#include "entity_util.h"
#include "flatbuffers/flatbuffers.h"
#include "mirror_generated.h"

namespace df3d_entities {

// Material hooks provided by the bridge: DF (mat_type, mat_index) -> grid
// material id (0xFFFF = none), and grid id -> snapshot-local index while a
// snapshot is being built (interns the string into the snapshot table).
using GridMaterialFn = uint16_t (*)(int16_t type, int32_t index);
using LocalMaterialFn = uint16_t (*)(flatbuffers::FlatBufferBuilder& fbb, uint16_t gridId);

struct Config {
    uint32_t itemPass = 16;      // frames per complete pass over items in play
    uint32_t buildingPass = 8;   // frames per complete pass over buildings
    uint32_t repeat = df3d::mirror::kEntityRepeatFrames;  // frames a change / removal is re-sent
    uint32_t refresh = 256;      // frames between forced re-sends per entity (0 = off)
    uint32_t maxPerSnapshot = 40000;  // entity records per snapshot (cap, spill beyond)
};

// Appearance hooks provided by the bridge: the install-relative
// palette path of a palette page (cached per session, used for the stack
// hash), and the encoder that interns a layer's page / palette into the
// snapshot being built and returns the schema layer.
struct AppearanceHooks {
    const std::string& (*palettePath)(const df::palette_pagest*) = nullptr;
    df3d::mirror::AppearanceLayer (*encodeLayer)(flatbuffers::FlatBufferBuilder&,
                                                 const df3d_appearance::Layer&) = nullptr;
};

struct Stats {
    size_t buildings = 0, items = 0;                 // shadows held
    size_t corpses = 0, corpsesWithStack = 0;        // corpse shadows, of which with a non-empty stack
    uint64_t corpseResolves = 0, corpseChanges = 0;  // resolutions run, stack hash changes after the first
    size_t lastSentItemAppearances = 0;
    double corpseResolveUsLast = 0, corpseResolveUsEma = 0, corpseResolveUsMax = 0;
    uint64_t buildingResyncs = 0, buildingVisits = 0, buildingChanges = 0;
    uint64_t buildingAdds = 0, buildingRemoves = 0;
    uint64_t itemPasses = 0, itemVisits = 0, itemHints = 0, itemChanges = 0;
    uint64_t itemAdds = 0, itemRemoves = 0, itemVerifies = 0;
    uint64_t fullsBuilt = 0, deltasBuilt = 0, sentBuildings = 0, sentItems = 0, spills = 0;
    size_t lastSentBuildings = 0, lastSentItems = 0, lastSentRemoved = 0;
    size_t lastEntityBytes = 0;      // bytes the last snapshot's two tables took
    size_t lastFullBytes = 0;        // bytes the last Full took (both tables)
    double scanUsLast = 0, scanUsEma = 0, scanUsMax = 0;   // per-update walk
    double fullPassUsLast = 0;                              // last complete pass (initial / on request)
};

// Output of build(): offsets to place into CreateSnapshot.
struct Built {
    df3d::mirror::ChangeScope buildingScope = df3d::mirror::ChangeScope::None;
    df3d::mirror::ChangeScope itemScope = df3d::mirror::ChangeScope::None;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<df3d::mirror::Building>>> buildings;
    flatbuffers::Offset<flatbuffers::Vector<uint32_t>> removedBuildings;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<df3d::mirror::MapItem>>> items;
    flatbuffers::Offset<flatbuffers::Vector<uint32_t>> removedItems;
    df3d::mirror::AppearanceScope itemAppearanceScope = df3d::mirror::AppearanceScope::None;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<df3d::mirror::ItemAppearance>>> itemAppearances;
    size_t count = 0;  // entity records serialized
};

// Installs the bridge's appearance hooks (once, at plugin init).
void setAppearanceHooks(const AppearanceHooks& hooks);

Config& config();
const Stats& stats();
Stats& mutableStats();  // the bridge records snapshot byte counts here
void resetStatsMax();

// Drops every shadow (map load / unload).
void reset();

// Compares only the authoritative building pointer sequence; no extraction.
// Native building additions/removals can occur without advancing a paused tick.
bool buildingSequenceChanged();
// Changes to existing pending construction jobs do not necessarily alter that list.
bool pendingConstructionChanged(void (*hintTerrain)(int32_t x, int32_t y, int32_t z));

// One update's worth of change detection. `fullPass` walks everything
// (first update after load, or a Full is about to be served).
void scan(int32_t frame, bool fullPass, GridMaterialFn gridMaterial);

// Serializes the tables for the snapshot being built at `frame`. With
// `full`, every shadow goes out with scope Full; otherwise the due changes
// / removals (scope Delta, or None when nothing is due). Must be called
// between the bridge's begin / finish of the snapshot materials table.
// `ring` = the snapshot goes to the shm slot (cap applies, a Full clears
// the repeat windows); false for a recording's first-entry Full, which
// has no size bound and leaves the ring's state alone.
void build(flatbuffers::FlatBufferBuilder& fbb, int32_t frame, bool full,
           LocalMaterialFn localMaterial, Built& out, bool ring);

// After a ring snapshot built at `frame` was published: retires expired
// removals, or every pending removal when the snapshot was a Full.
void published(int32_t frame, bool full);

// Command hints: re-visit this item / building on the next scan so
// a flag a command just changed lands in the next snapshot instead of
// waiting for the rotating slice.
void hintItem(int32_t id);
void hintBuilding(int32_t id);

// Prints the `df3d status` lines for this module.
void printStatus(DFHack::color_ostream& out);

}  // namespace df3d_entities
