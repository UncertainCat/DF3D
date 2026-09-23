#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <memory>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "wm/evaluate.h"
#include "wm/keyframes.h"
#include "wm/sim_clock.h"
#include "wm/types.h"

namespace wm {

// Neutral snapshot form the world model ingests. Produced from mirror
// buffers by the fixture/shared-memory adapters (mirror_ingest.cpp);
// presentations never construct these.
struct UnitObservation {
  UnitId id = 0;
  TilePos pos;
  JobKind job = JobKind::Idle;
  std::string_view species;
  UnitAttack attack{};
  uint32_t bodyVolumeCm3 = 0;
  uint64_t statusFlags = 0;
};

enum class TerrainScope : uint8_t { None = 0, Delta, Full };

// One observed block. `tiles` points at 256 TileState whose `material`
// indexes the snapshot's own `materials` table (kNoMaterial = none); the
// world model remaps them to model-wide ids on ingest. Storage is owned by
// SnapshotData::tileStorage and lives only for the ingest call.
struct BlockObservation {
  BlockPos pos;
  const TileState* tiles = nullptr;
};

enum class AppearanceScope : uint8_t { None = 0, Delta, Full };

// One unit's observed layer stack. Layer `page` / `palette` index the
// snapshot's own `tilePages` / `palettes` tables (kNoPalette = none); the
// world model remaps them to model-wide ids on ingest.
struct AppearanceObservation {
  UnitId id = 0;
  uint32_t version = 0;
  std::vector<AppearanceLayer> layers;
};

// Scope of the v4 entity tables: Full = every entity present
// (the model removes anything absent), Delta = changed / new entities plus
// removed ids, None = nothing about the table in this snapshot.
enum class ChangeScope : uint8_t { None = 0, Delta, Full };

enum class MatterState : uint8_t { Solid = 0, Liquid, Gas, Powder, Paste, Pressed };
struct GroundSpatter {
  uint8_t tile = 0, amount = 0;
  MaterialId material = kNoMaterial;
  MatterState state = MatterState::Solid;
  friend bool operator==(const GroundSpatter&, const GroundSpatter&) = default;
};
struct SpatterBlockObservation {
  BlockPos pos;
  std::vector<GroundSpatter> entries;
};

// One observed building. `material` indexes the snapshot's own
// `materials` table (kNoMaterial = none); remapped on ingest.
struct BuildingObservation {
  BuildingId id = 0;
  BuildingKind kind = BuildingKind::Unknown;
  uint16_t subtype = kNoSubtype;
  std::string_view custom;
  int32_t x1 = 0, y1 = 0, x2 = 0, y2 = 0, z = 0;
  int32_t centerX = 0, centerY = 0;
  std::vector<uint8_t> extents;  // empty = whole rectangle
  uint16_t material = kNoMaterial;
  BuildingStage stage = BuildingStage::Complete;
  uint8_t flags = 0;  // kBuilding* bits
};

// One observed map item; `material` as for buildings.
struct ItemObservation {
  ItemId id = 0;
  ItemKind kind = ItemKind::Unknown;
  uint16_t subtype = kNoSubtype;
  std::string_view subtypeRaw;
  uint16_t material = kNoMaterial;
  TilePos pos;
  uint32_t stack = 1;
  uint8_t flags = 0;         // kItem* bits
  uint16_t corpseFlags = 0;  // kCorpse* bits (v5)
  int32_t corpseUnitId = -1;
};

// One corpse item's observed layer stack (v5); tables as for units.
struct ItemAppearanceObservation {
  ItemId id = 0;
  uint32_t version = 0;
  std::vector<AppearanceLayer> layers;
};

// Glyph table observations (v5). Keys are the snapshot's own
// strings (species raw id, material raw id, itemdef raw id).
struct CreatureGlyphObservation {
  std::string_view species;
  CreatureGlyph glyph;
};
struct MaterialGlyphObservation {
  std::string_view material;
  MaterialGlyph glyph;
};
struct ItemDefGlyphObservation {
  ItemKind kind = ItemKind::Unknown;
  std::string_view subtypeRaw;
  uint8_t tile = 0;
};

// One command outcome as published (v6).
struct CommandResultObservation {
  uint64_t seq = 0;
  CommandStatus status = CommandStatus::Ok;
  std::string_view message;
};

struct SnapshotData {
  Tick tick = 0;
  uint64_t emittedAtMs = 0;
  TilePos mapSize;
  std::vector<UnitObservation> units;
  TerrainScope terrainScope = TerrainScope::None;
  std::vector<BlockObservation> blocks;
  // Per-snapshot table shared by terrain, buildings and items.
  std::vector<std::string_view> materials;
  std::vector<TileState> tileStorage;  // backing for blocks[].tiles
  AppearanceScope appearanceScope = AppearanceScope::None;
  std::vector<AppearanceObservation> appearances;
  std::vector<std::string_view> tilePages;  // per-snapshot table
  std::vector<std::string_view> palettes;   // per-snapshot table
  ChangeScope buildingScope = ChangeScope::None;
  std::vector<BuildingObservation> buildings;
  std::vector<BuildingId> removedBuildings;
  ChangeScope itemScope = ChangeScope::None;
  std::vector<ItemObservation> items;
  std::vector<ItemId> removedItems;
  // v5: corpse appearances ride with their item records; glyph
  // tables are upserted by key.
  AppearanceScope itemAppearanceScope = AppearanceScope::None;
  std::vector<ItemAppearanceObservation> itemAppearances;
  ChangeScope glyphScope = ChangeScope::None;
  std::vector<CreatureGlyphObservation> creatureGlyphs;
  std::vector<MaterialGlyphObservation> materialGlyphs;
  std::vector<ItemDefGlyphObservation> itemDefGlyphs;
  // v6: outcomes of commands; the bridge repeats each for a few
  // snapshots, the model keeps the first arrival per seq.
  std::vector<CommandResultObservation> commandResults;
  std::vector<CombatEvent> combatEvents;
  std::vector<ProjectileSample> projectileSamples;
  std::vector<ReportEvent> reportEvents;
  uint64_t reportEventsDropped = 0;
  ChangeScope spatterScope = ChangeScope::None;
  std::vector<SpatterBlockObservation> spatters;
  std::vector<ProjectileCombatEvent> projectileCombatEvents;
  uint64_t projectileCombatEventsDropped=0;
  bool projectileCombatEventsAvailable=false;
  std::vector<ResolvedAttack> resolvedAttacks;
  uint64_t resolvedAttacksDropped = 0;
  bool resolvedAttacksAvailable = false;
  std::vector<ItemContactEvent> itemContacts;
  uint64_t itemContactsDropped = 0;
  bool itemContactsAvailable = false;
};

// The outcome of one command sent through MirrorClient, delivered
// once per seq by drainCommandResults(); `tick` is the snapshot that first
// carried it.
struct CommandResult {
  uint64_t seq = 0;
  CommandStatus status = CommandStatus::Ok;
  std::string message;
  Tick tick = 0;
};

struct LifecycleEvent {
  enum class Kind : uint8_t { Appeared, Departed };
  Kind kind;
  UnitId id;
  Tick tick;
};

// A block whose contents changed since the last drainTerrainEvents(). One
// event per block per drain (coalesced); `version` is the block's version
// at drain time and `tick` the snapshot that last changed it.
struct TerrainBlockEvent {
  BlockPos pos;
  uint64_t version = 0;
  Tick tick = 0;
};

// The latest known appearance of a unit or of a corpse item.
// `version` is the bridge's stack hash; `tick` is the snapshot
// that last changed it. Layers are bottom first; empty = DF has no
// page-resolvable graphics for it.
struct AppearanceStack {
  uint32_t version = 0;
  Tick tick = 0;
  std::vector<AppearanceLayer> layers;
};
using UnitAppearance = AppearanceStack;
using ItemAppearance = AppearanceStack;

// A corpse item whose appearance changed since the last
// drainItemAppearanceEvents() (coalesced per item; first arrival counts).
// An item that left the map drops its appearance silently: the item's
// own Removed event covers it.
struct ItemAppearanceEvent {
  ItemId id = 0;
  uint32_t version = 0;
  Tick tick = 0;
};

// An itemdef's classic tile, keyed by (kind, raw id).
struct ItemDefGlyph {
  ItemKind kind = ItemKind::Unknown;
  std::string subtypeRaw;
  uint8_t tile = 0;
};

// A unit whose appearance changed since the last drainAppearanceEvents()
// (coalesced: one event per unit per drain, carrying the latest version).
struct AppearanceEvent {
  UnitId id = 0;
  uint32_t version = 0;
  Tick tick = 0;
};

// --- buildings and map items ---

// A building as the model holds it. `material` is a model-wide id
// (materialName). `version` is 1 on first observation and +1 on every
// ingest that changed any field; `tick` is the snapshot that last changed
// it. Pointers handed out by the queries stay valid until the next ingest().
struct Building {
  BuildingId id = 0;
  BuildingKind kind = BuildingKind::Unknown;
  uint16_t subtype = kNoSubtype;  // DF per-kind subtype (see BuildingKind)
  std::string custom;             // custom workshop / furnace raw id, else empty
  int32_t x1 = 0, y1 = 0, x2 = 0, y2 = 0, z = 0;  // inclusive rectangle
  int32_t centerX = 0, centerY = 0;
  std::vector<uint8_t> extents;  // row-major (y outer) 0/1 per tile; empty = all
  MaterialId material = kNoMaterial;
  BuildingStage stage = BuildingStage::Complete;
  uint8_t flags = 0;  // kBuilding* bits
  uint64_t version = 0;
  Tick tick = 0;

  int32_t width() const { return x2 - x1 + 1; }
  int32_t height() const { return y2 - y1 + 1; }
  // True if the building occupies tile (x, y) at its z (extents honoured).
  bool occupies(int32_t x, int32_t y) const {
    if (x < x1 || x > x2 || y < y1 || y > y2) return false;
    if (extents.empty()) return true;
    const size_t i = static_cast<size_t>(y - y1) * static_cast<size_t>(width()) +
                     static_cast<size_t>(x - x1);
    return i < extents.size() && extents[i] != 0;
  }
};

// A map item as the model holds it; `version` / `tick` as for Building.
struct MapItem {
  ItemId id = 0;
  ItemKind kind = ItemKind::Unknown;
  uint16_t subtype = kNoSubtype;
  std::string subtypeRaw;  // e.g. "ITEM_WEAPON_PICK", else empty
  MaterialId material = kNoMaterial;
  TilePos pos;
  uint32_t stack = 1;
  uint8_t flags = 0;         // kItem* bits
  int32_t corpseUnitId = -1;
  uint16_t corpseFlags = 0;  // kCorpse* bits: what a corpse / body part counts as (v5)
  uint64_t version = 0;
  Tick tick = 0;
};

// How an entity changed relative to the previous drain: Added (did not
// exist at the last drain, exists now), Changed (existed, still exists,
// any field or position changed at least once since), Removed (existed,
// gone now). An entity added and removed between two drains yields no
// event; one removed and re-added yields Changed (its version restarts
// at 1, so compare versions for inequality, not order).
enum class EntityChange : uint8_t { Added, Changed, Removed };

struct BuildingEvent {
  EntityChange change = EntityChange::Added;
  BuildingId id = 0;
  uint64_t version = 0;  // the entity's version at drain (last version if removed)
  Tick tick = 0;         // snapshot of the last change (or the removal)
};

struct ItemEvent {
  EntityChange change = EntityChange::Added;
  ItemId id = 0;
  uint64_t version = 0;
  Tick tick = 0;
};

// Read-only view of one stored block. `tiles` points at 256 contiguous
// TileState (row-major, local y outer) inside the model; the pointer stays
// valid until the next ingest(). Padding tiles beyond mapSize() are Empty.
struct BlockView {
  BlockPos pos;
  uint64_t version = 0;  // >= 1 for any known block
  const TileState* tiles = nullptr;
};

// Reliable change notifications carried alongside immutable model snapshots.
struct ModelEvents {
  std::vector<LifecycleEvent> lifecycle;
  std::vector<TerrainBlockEvent> terrain;
  std::vector<BlockPos> spatters;
  std::vector<AppearanceEvent> appearances;
  std::vector<BuildingEvent> buildings;
  std::vector<ItemEvent> items;
  std::vector<ItemAppearanceEvent> itemAppearances;
  std::vector<CommandResult> commands;
  // Hard overload boundary; ordered receipts are never silently truncated.
  static constexpr size_t kMaxRetainedBytes = 32 * 1024 * 1024;
  size_t retainedBytes() const;
  void append(ModelEvents newer);
};

struct WorldModelConfig {
  SimClockConfig clock;
  ClassifierConfig classifier;
  MotionConfig motion;
  // Render evaluation trails the estimated sim clock by this many ticks so
  // the keyframe a unit is moving toward is normally already known. Must
  // cover a typical movement cadence (a dwarf walks a tile in roughly ten
  // ticks) or steps degrade to snaps; the cost is latency of
  // renderDelayTicks / ticksPerSecond.
  double renderDelayTicks = 12.0;
  // Off for units-only consumers (and for the benchmark lane to isolate
  // terrain ingest cost); the terrain queries then report "unknown".
  bool ingestTerrain = true;
  // Same for the v4 entity tables: off, the stores stay empty and
  // the benchmark lane can isolate their cost.
  bool ingestBuildings = true;
  bool ingestItems = true;
  // Ordered lifecycle transitions are optional for state-only consumers.
  bool collectLifecycleEvents = true;
};

class WorldModel {
 public:
  explicit WorldModel(WorldModelConfig cfg = {}, uint64_t initialGeneration = 0)
      : cfg_(cfg), sessionGeneration_(initialGeneration) {}
  const WorldModelConfig& config() const { return cfg_; }

  ModelEvents drainAllEvents();
  void restoreEvents(ModelEvents events);

  // --- ingestion (mirror-facing) ---
  // `arrivalWallSeconds` is injected by the caller. Returns false when the
  // ordered event backlog (lifecycle + command results awaiting a drain)
  // would exceed ModelEvents::kMaxRetainedBytes: the state is still applied
  // and every earlier pending event is kept, but the receipts that did not
  // fit are dropped and counted in eventBudgetDrops() (a dropped command
  // result is not marked seen, so a bridge repeat can still deliver it
  // after a drain). Never throws.
  bool ingest(const SnapshotData& snap, double arrivalWallSeconds);
  uint64_t eventBudgetDrops() const { return eventBudgetDrops_; }
  // Last ingest-time fault (empty when none); cleared by resetSession().
  const std::string& lastIngestError() const { return lastIngestError_; }

  // Clears all session-owned state. Consumers must discard cached identities,
  // versions and pending events when sessionGeneration() changes.
  void resetSession();
  uint64_t sessionGeneration() const { return sessionGeneration_; }

  // --- time ---
  bool hasData() const { return latestTick_.has_value(); }
  // Fractional render tick at a wall time: clock estimate minus render
  // delay, clamped to no earlier than the first ingested tick so a client
  // attaching to a paused sim sees the current state immediately instead
  // of an empty world.
  double renderTickAt(double wallSeconds) const;
  Tick latestTick() const { return latestTick_.value_or(0); }

  // --- queries ---
  TilePos mapSize() const { return mapSize_; }
  // Every unit currently retained, sorted: present units plus those that
  // departed within the last kDepartedRetentionTicks ticks.
  std::vector<UnitId> unitIds() const;
  uint64_t unitMembershipVersion() const { return unitMembershipVersion_; }
  // Retiring state is an explicit ownership responsibility: a departed
  // unit's record (history, attacks, appearance) is evicted once the sim is
  // this many ticks past its departure. One DF day; render evaluation trails
  // the sim by tens of ticks, so consumers still see Departed for a while.
  static constexpr Tick kDepartedRetentionTicks = 1200;
  uint64_t departedUnitsEvicted() const { return departedEvictions_; }
  const std::string* unitSpecies(UnitId id) const;
  uint32_t unitBodyVolume(UnitId id) const;
  uint64_t unitStatusFlags(UnitId id) const;
  EvalResult evaluate(UnitId id, double renderTick) const;
  // Units whose evaluated position falls inside [min, max] (inclusive),
  // Present units only. Linear scan for now; becomes a spatial index when
  // the benchmark lane says so.
  std::vector<std::pair<UnitId, EvalResult>> unitsInBox(TilePos min, TilePos max,
                                                        double renderTick) const;

  // --- lifecycle events ---
  // Appeared/Departed events accumulated since the last drain, in order.
  std::vector<LifecycleEvent> drainEvents();

  // --- terrain ---
  // False until a Full terrain snapshot has been ingested; every query
  // below then reports "unknown" for everything.
  bool hasTerrain() const { return terrainKnown_; }
  // Increments once per ingest that changed at least one block.
  uint64_t terrainVersion() const { return terrainVersion_; }
  size_t knownBlockCount() const { return blocks_.size(); }
  // Total blocks the map has (ceil(x/16) * ceil(y/16) * z); 0 before data.
  size_t mapBlockCount() const { return blockIndex_.size(); }

  // The tile at `p`, or nullopt if outside the map or in a block never
  // observed. Hidden tiles are returned as observed (flag set); consumers
  // decide what "hidden" means for them.
  std::optional<TileState> tileAt(TilePos p) const;
  // Block access for meshers. `block` is nullopt for unobserved/out-of-map
  // blocks; `blockVersion` is 0 for those. Versions start at 1 on first
  // observation and increment on every ingest that changed any tile.
  std::optional<BlockView> block(BlockPos b) const;
  uint64_t blockVersion(BlockPos b) const;
  // Known blocks of one z level, ordered by (by, bx).
  std::vector<BlockView> blocksAtZ(int32_t z) const;
  // Calls f(TilePos, const TileState&) for every known in-map tile of z,
  // block by block (by, bx), row-major within a block.
  template <class F>
  void forEachTileAtZ(int32_t z, F&& f) const;

  // Resolves a model-wide material id; empty for kNoMaterial or unknown.
  std::string_view materialName(MaterialId id) const;
  size_t materialCount() const { return materials_.size(); }
  const std::vector<GroundSpatter>& spattersAt(BlockPos pos) const;
  uint64_t spatterVersion() const { return spatterVersion_; }
  std::vector<BlockPos> drainSpatterEvents();

  // Blocks changed since the last drain, coalesced per block, in the order
  // they first changed. Empty if nothing changed.
  std::vector<TerrainBlockEvent> drainTerrainEvents();

  // --- unit appearance references ---
  // The latest appearance published for the unit, or nullptr if none has
  // arrived yet (a consumer draws its placeholder until then). Kept for
  // departed units until eviction. The pointer stays valid until the next ingest().
  const UnitAppearance* unitAppearance(UnitId id) const;
  // Resolves model-wide page / palette ids; empty for unknown ids or
  // kNoPalette. Page names are TILE_PAGE tokens (e.g. "DWARF_BODY");
  // palette names are paths relative to the DF install root.
  std::string_view tilePageName(PageId id) const;
  std::string_view paletteName(PaletteId id) const;
  size_t tilePageCount() const { return tilePages_.size(); }
  size_t paletteCount() const { return palettes_.size(); }
  // Increments once per ingest that changed at least one appearance.
  uint64_t appearanceVersion() const { return appearanceVersion_; }
  // Units whose appearance changed since the last drain (first arrival
  // counts), coalesced per unit, in first-change order.
  std::vector<AppearanceEvent> drainAppearanceEvents();

  // --- buildings ---
  // False until a Full building snapshot has been ingested (Deltas are
  // still applied; the validators forbid them before a Full upstream).
  bool buildingsKnown() const { return buildingsKnown_; }
  // Increments once per ingest that added, changed or removed a building.
  uint64_t buildingsVersion() const { return buildingsVersion_; }
  size_t buildingCount() const { return buildings_.size(); }
  // nullptr if unknown. Valid until the next ingest().
  const Building* building(BuildingId id) const;
  // Buildings whose rectangle lies on z, sorted by id.
  std::vector<const Building*> buildingsAt(int32_t z) const;
  // Buildings whose rectangle intersects the inclusive [x1..x2] x [y1..y2]
  // at z, sorted by id (rectangle test only; extents are not consulted).
  std::vector<const Building*> buildingsInRect(int32_t x1, int32_t y1, int32_t x2, int32_t y2,
                                               int32_t z) const;
  // The building occupying the tile (extents honoured); the lowest id if
  // several overlap (a stockpile under a workshop); nullptr if none.
  const Building* buildingAt(TilePos p) const;
  // Calls f(const Building&) for every known building, in store order.
  template <class F>
  void forEachBuilding(F&& f) const {
    for (const Building& b : buildings_) f(b);
  }
  // Buildings added / changed / removed since the last drain, coalesced
  // per id (see EntityChange), in first-change order.
  std::vector<BuildingEvent> drainBuildingEvents();

  // --- map items ---
  bool itemsKnown() const { return itemsKnown_; }
  uint64_t itemsVersion() const { return itemsVersion_; }
  size_t itemCount() const { return items_.size(); }
  const MapItem* item(ItemId id) const;
  // Items on z, sorted by id.
  std::vector<const MapItem*> itemsAt(int32_t z) const;
  // Items lying on exactly this tile, sorted by id.
  std::vector<const MapItem*> itemsAtTile(TilePos p) const;
  template <class F>
  void forEachItem(F&& f) const {
    for (const MapItem& it : items_) f(it);
  }
  // Inclusive semantic elevation range. Visits only indexed occupants of those
  // levels; order is unspecified, like forEachItem. References belong to this
  // model snapshot and remain valid until its next ingest.
  template <class F>
  void forEachItemInZRange(int32_t minimum, int32_t maximum, F&& f) const {
    if (minimum > maximum) return;
    for (auto z = itemSpatial_->lower_bound(minimum);
         z != itemSpatial_->end() && z->first <= maximum; ++z) {
      for (const auto& [block, ids] : *z->second)
        for (ItemId id : *ids) f(*item(id));
    }
  }
  std::vector<ItemEvent> drainItemEvents();
  // Inclusive semantic bounds. Reads indexed block occupants, never render state.
  template <class F>
  void forEachItemInBox(TilePos minimum, TilePos maximum, F&& f) const {
    if (minimum.x > maximum.x || minimum.y > maximum.y || minimum.z > maximum.z) return;
    const auto low = itemBlock(minimum), high = itemBlock(maximum);
    for (auto z = itemSpatial_->lower_bound(minimum.z);
         z != itemSpatial_->end() && z->first <= maximum.z; ++z) {
      const auto visit = [&](const auto& ids) {
        for (ItemId id : ids) {
          const auto* value = item(id);
          if (value->pos.x >= minimum.x && value->pos.x <= maximum.x &&
              value->pos.y >= minimum.y && value->pos.y <= maximum.y) f(*value);
        }
      };
      const uint64_t columns = uint64_t(int64_t(high.first)-low.first+1);
      const uint64_t rows = uint64_t(int64_t(high.second)-low.second+1);
      if (columns * rows <= z->second->size()) {
        for (int64_t x=low.first; x<=high.first; ++x)
          for (int64_t y=low.second; y<=high.second; ++y) {
            const auto block=z->second->find({int32_t(x),int32_t(y)});
            if (block!=z->second->end()) visit(*block->second);
          }
      } else {
        for (const auto& [block,ids] : *z->second)
          if (block.first>=low.first && block.first<=high.first &&
              block.second>=low.second && block.second<=high.second) visit(*ids);
      }
    }
  }

  // --- corpse appearance references ---
  // The latest appearance published for a map item (corpses and body
  // parts), or nullptr if none arrived or the item left the map. Same
  // layer vocabulary and page / palette tables as unitAppearance(). The
  // pointer stays valid until the next ingest().
  const ItemAppearance* itemAppearance(ItemId id) const;
  size_t itemAppearanceCount() const { return itemAppearances_.size(); }
  template <class F> void forEachItemAppearance(F&& f) const {
    for (const auto& [id,entry] : itemAppearances_) f(id,entry.appearance);
  }
  // Increments once per ingest that changed at least one item appearance.
  uint64_t itemAppearanceVersion() const { return itemAppearanceVersion_; }
  // Items whose appearance changed since the last drain (first arrival
  // counts), coalesced per item, in first-change order.
  std::vector<ItemAppearanceEvent> drainItemAppearanceEvents();

  // --- classic glyph tables ---
  // False until a Full glyph table has been ingested (Deltas still apply).
  bool glyphsKnown() const { return glyphsKnown_; }
  // Increments once per ingest that added or changed any glyph entry.
  uint64_t glyphVersion() const { return glyphVersion_; }
  // nullptr when unknown. Pointers stay valid until the next ingest().
  const CreatureGlyph* creatureGlyph(std::string_view species) const;
  const MaterialGlyph* materialGlyph(MaterialId material) const;
  const ItemDefGlyph* itemDefGlyph(ItemKind kind, std::string_view subtypeRaw) const;
  size_t creatureGlyphCount() const { return creatureGlyphs_.size(); }
  size_t materialGlyphCount() const { return materialGlyphs_.size(); }
  size_t itemDefGlyphCount() const { return itemDefGlyphs_.size(); }

  // --- command results ---
  // Outcomes of commands that arrived since the last drain, in arrival
  // order, each seq exactly once (the bridge re-sends a result for a few
  // snapshots; repeats are dropped here). Presentations match `seq`
  // against what MirrorClient::send* returned.
  std::vector<CommandResult> drainCommandResults();
  // Distinct results received so far (diagnostics).
  // Recent confirmed outcomes. A consumer owns its cursor; queries do not drain.
  const std::deque<ProjectileSample>& projectileSamples() const { return projectileSamples_; }
  std::vector<ProjectileState> projectilesAt(double renderTick) const;
  const std::deque<CombatEvent>& combatEvents() const { return combatEvents_; }
  const std::deque<ReportEvent>& reportEvents() const { return reportEvents_; }
  const std::deque<ProjectileCombatEvent>& projectileCombatEvents() const { return projectileCombatEvents_; }
  uint64_t projectileCombatEventsDropped() const { return projectileCombatEventsDropped_; }
  bool projectileCombatEventsAvailable() const { return projectileCombatEventsAvailable_; }
  const std::deque<ResolvedAttack>& resolvedAttacks() const { return resolvedAttacks_; }
  uint64_t resolvedAttacksDropped() const { return resolvedAttacksDropped_; }
  bool resolvedAttacksAvailable() const { return resolvedAttacksAvailable_; }
  const std::deque<ItemContactEvent>& itemContacts() const { return itemContacts_; }
  uint64_t itemContactsDropped() const { return itemContactsDropped_; }
  bool itemContactsAvailable() const { return itemContactsAvailable_; }
  uint64_t reportEventsDropped() const { return reportEventsDropped_; }
  uint64_t latestReportEventId() const { return lastReportEventId_; }
  uint64_t commandResultsReceived() const { return commandResultsReceived_; }

 private:
  struct UnitEntry {
    std::string species;
    uint32_t bodyVolumeCm3 = 0;
    uint64_t statusFlags = 0;
    KeyframeHistory history;
    // Independent action changes cannot shorten positional interpolation.
    struct AttackFrame { Tick tick; UnitAttack attack; };
    std::deque<AttackFrame> attacks;
    std::optional<Tick> departedAt;
    std::optional<UnitAppearance> appearance;
    bool appearancePending = false;  // already in pendingAppearances_
    uint64_t seenSerial = 0;  // ingestSerial_ of the last snapshot listing it
  };

  void ingestAppearances(const SnapshotData& snap);
  PageId internTilePage(std::string_view name);
  PaletteId internPalette(std::string_view name);

  struct Block {
    BlockPos pos;
    uint64_t version = 0;
    Tick changedAt = 0;
    bool pending = false;  // already in pendingBlocks_
    using Tiles = std::array<TileState, kTilesPerBlock>;
    std::shared_ptr<Tiles> tiles = std::make_shared<Tiles>();
  };

  // Per-snapshot material indices -> model-wide ids (interning new ones).
  std::vector<MaterialId> remapMaterials(const SnapshotData& snap);
  void ingestTerrain(const SnapshotData& snap, const std::vector<MaterialId>& remap);
  void resetTerrain(TilePos mapSize);
  bool inBlockRange(BlockPos b) const;
  // Dense (bx, by, bz) -> blocks_ index, or -1; -1 also when out of range.
  int64_t blockSlot(BlockPos b) const;
  MaterialId internMaterial(std::string_view name);

  ModelEvents restoredEvents_;
  size_t pendingCommandBytes_ = 0;
  // True when `bytes` more of ordered receipts fit under the budget; else
  // records the drop and returns false (the caller keeps the event out).
  bool reservePendingEventBytes(size_t bytes);
  uint64_t eventBudgetDrops_ = 0;
  bool ingestBudgetExceeded_ = false;  // for the current ingest() call
  std::string lastIngestError_;
  uint64_t ingestSerial_ = 0;  // one per ingest(): stamps units seen this snapshot
  uint64_t departedEvictions_ = 0;
  WorldModelConfig cfg_;
  uint64_t sessionGeneration_ = 0;
  SimClockEstimator clock_{cfg_.clock};
  std::unordered_map<UnitId, UnitEntry> units_;
  uint64_t unitMembershipVersion_ = 0;
  std::vector<LifecycleEvent> pendingEvents_;
  std::optional<Tick> firstTick_;
  std::optional<Tick> latestTick_;
  TilePos mapSize_;

  // Terrain payloads are shared between value snapshots and detached only
  // when a block changes. Metadata stays value-owned; blockIndex_ is a dense grid over the map's
  // block extent mapping to a blocks_ slot (-1 = never observed).
  bool terrainKnown_ = false;
  uint64_t terrainVersion_ = 0;
  int32_t blocksX_ = 0, blocksY_ = 0;
  std::vector<int32_t> blockIndex_;
  std::vector<Block> blocks_;
  std::vector<size_t> pendingBlocks_;  // slots with pending == true
  std::vector<std::string> materials_;
  std::map<BlockPos, std::shared_ptr<const std::vector<GroundSpatter>>> spatters_;
  std::set<BlockPos> pendingSpatters_;
  uint64_t spatterVersion_ = 0;
  void ingestSpatters(const SnapshotData& snap, const std::vector<MaterialId>& remap);
  struct SvHash {
    using is_transparent = void;
    size_t operator()(std::string_view s) const noexcept { return std::hash<std::string_view>{}(s); }
  };
  std::unordered_map<std::string, MaterialId, SvHash, std::equal_to<>> materialIds_;

  // Appearance reference tables (model-wide, only grow) and change tracking.
  uint64_t appearanceVersion_ = 0;
  std::vector<std::string> tilePages_;
  std::unordered_map<std::string, PageId, SvHash, std::equal_to<>> tilePageIds_;
  std::vector<std::string> palettes_;
  std::unordered_map<std::string, PaletteId, SvHash, std::equal_to<>> paletteIds_;
  std::vector<UnitId> pendingAppearances_;

  // Entity stores: flat vectors + id -> slot maps (swap-and-pop on
  // removal). Pending events record whether the entity existed at the
  // last drain; the kind is derived at drain time from whether it exists
  // then, which is what coalesces Added/Changed/Removed sequences.
  struct PendingEntity {
    uint32_t id = 0;
    bool existedAtDrain = false;
    uint64_t version = 0;  // latest version seen (kept across a removal)
    Tick tick = 0;
  };
  struct EntityPending {
    std::vector<PendingEntity> list;
    std::unordered_map<uint32_t, size_t> slot;  // id -> index into list
    void note(uint32_t id, bool existedBefore, uint64_t version, Tick tick);
  };
  void ingestBuildings(const SnapshotData& snap, const std::vector<MaterialId>& remap);
  void removeBuildingSlot(size_t slot, Tick tick);
  void ingestItems(const SnapshotData& snap, const std::vector<MaterialId>& remap);
  void removeItemSlot(size_t slot, Tick tick);
  void clearEntities(Tick tick);
  void ingestItemAppearances(const SnapshotData& snap);
  void ingestGlyphs(const SnapshotData& snap);
  void ingestCommandResults(const SnapshotData& snap);

  bool buildingsKnown_ = false;
  uint64_t buildingsVersion_ = 0;
  std::vector<Building> buildings_;
  std::unordered_map<BuildingId, size_t> buildingIndex_;
  EntityPending pendingBuildings_;

  bool itemsKnown_ = false;
  uint64_t itemsVersion_ = 0;
  std::vector<MapItem> items_;
  std::unordered_map<ItemId, size_t> itemIndex_;
  // Three-level COW: publication copies one shared pointer; movement copies
  // only the z directory, affected level's block directory and touched ID
  // buckets. IDs (never item pointers/vector slots) survive snapshot copies
  // and swap/pop removal. Non-position changes leave all buckets shared.
  using ItemBlock = std::pair<int32_t, int32_t>;
  using ItemBucket = std::unordered_set<ItemId>;
  using ItemLevel = std::map<ItemBlock, std::shared_ptr<ItemBucket>>;
  using ItemSpatial = std::map<int32_t, std::shared_ptr<ItemLevel>>;
  std::shared_ptr<ItemSpatial> itemSpatial_ = std::make_shared<ItemSpatial>();
  static ItemBlock itemBlock(TilePos p) {
    return {p.x / 16 - (p.x % 16 < 0), p.y / 16 - (p.y % 16 < 0)};
  }
  void indexItem(ItemId id, TilePos p);
  void unindexItem(ItemId id, TilePos p);
  EntityPending pendingItems_;

  // Corpse appearances: keyed by item id, dropped with the item.
  struct ItemAppearanceEntry {
    ItemAppearance appearance;
    bool pending = false;  // already in pendingItemAppearances_
  };
  uint64_t itemAppearanceVersion_ = 0;
  std::unordered_map<ItemId, ItemAppearanceEntry> itemAppearances_;
  std::vector<ItemId> pendingItemAppearances_;

  // Glyph tables: model-wide, only grow.
  bool glyphsKnown_ = false;
  uint64_t glyphVersion_ = 0;
  std::unordered_map<std::string, CreatureGlyph, SvHash, std::equal_to<>> creatureGlyphs_;
  std::unordered_map<MaterialId, MaterialGlyph> materialGlyphs_;
  std::unordered_map<std::string, ItemDefGlyph, SvHash, std::equal_to<>> itemDefGlyphs_;

  // Command results: pending until drained; seqs already seen are
  // remembered in a bounded window so the bridge's repeats are dropped.
  std::vector<CommandResult> pendingCommandResults_;
  std::unordered_set<uint64_t> seenCommandSeqs_;
  std::vector<uint64_t> seenCommandOrder_;  // FIFO over seenCommandSeqs_
  size_t seenCommandCursor_ = 0;
  uint64_t commandResultsReceived_ = 0;
  std::deque<CombatEvent> combatEvents_;
  uint64_t lastCombatEventId_ = 0;
  std::deque<ReportEvent> reportEvents_;
  uint64_t lastReportEventId_ = 0, reportEventsDropped_ = 0;
  std::deque<ProjectileCombatEvent> projectileCombatEvents_;
  uint64_t lastProjectileCombatEventId_=0, projectileCombatEventsDropped_=0;
  bool projectileCombatEventsAvailable_=false;
  std::deque<ResolvedAttack> resolvedAttacks_;
  uint64_t lastResolvedAttackId_ = 0, resolvedAttacksDropped_ = 0;
  bool resolvedAttacksAvailable_ = false;
  std::deque<ItemContactEvent> itemContacts_;
  uint64_t lastItemContactId_ = 0, itemContactsDropped_ = 0;
  bool itemContactsAvailable_ = false;
  std::deque<ProjectileSample> projectileSamples_;
  uint64_t lastProjectileSequence_ = 0;
};

template <class F>
void WorldModel::forEachTileAtZ(int32_t z, F&& f) const {
  if (z < 0 || z >= mapSize_.z) return;
  for (int32_t by = 0; by < blocksY_; ++by) {
    for (int32_t bx = 0; bx < blocksX_; ++bx) {
      const int64_t slot = blockSlot(BlockPos{bx, by, z});
      if (slot < 0) continue;
      const Block& blk = blocks_[static_cast<size_t>(slot)];
      const int32_t x0 = bx * kBlockSize, y0 = by * kBlockSize;
      const int32_t xn = std::min(kBlockSize, mapSize_.x - x0);
      const int32_t yn = std::min(kBlockSize, mapSize_.y - y0);
      for (int32_t ly = 0; ly < yn; ++ly) {
        for (int32_t lx = 0; lx < xn; ++lx) {
          f(TilePos{x0 + lx, y0 + ly, z}, (*blk.tiles)[tileIndexInBlock(lx, ly)]);
        }
      }
    }
  }
}

// --- fixture replay (adapter over the mirror layer) ---
// Loads a fixture (validating it first), replaying arrival times from each
// snapshot's emitted_at_ms so the run is deterministic. Returns false and
// sets `error` on parse/validation failure.
bool loadFixtureFile(WorldModel& model, const std::string& path, std::string& error);
bool loadFixtureBytes(WorldModel& model, std::vector<uint8_t> bytes, std::string& error);

// Stepwise fixture replay for presentations that run offline from a fixture
// the way they would run from the live mirror: snapshots are ingested as
// the caller's (injected) wall clock passes each one's recorded arrival
// time, so the model's clock estimate, lifecycle and terrain events arrive
// incrementally instead of all at load. The fixture is validated on open.
class FixtureReplay {
 public:
  static std::unique_ptr<FixtureReplay> open(const std::string& path, std::string& error);
  static std::unique_ptr<FixtureReplay> fromBytes(std::vector<uint8_t> bytes, std::string& error);
  ~FixtureReplay();
  FixtureReplay(const FixtureReplay&) = delete;
  FixtureReplay& operator=(const FixtureReplay&) = delete;

  size_t snapshotCount() const;
  bool done() const { return next_ >= snapshotCount(); }
  // Recorded arrival (emitted_at_ms / 1000) of the first / last snapshot.
  double firstArrivalSeconds() const;
  double lastArrivalSeconds() const;
  // Ingests, in order, every not-yet-ingested snapshot whose recorded
  // arrival is <= wallSeconds. Returns how many were ingested.
  size_t stepTo(WorldModel& model, double wallSeconds);
  // Ingests everything remaining (whole-stream load, like loadFixtureFile).
  size_t stepAll(WorldModel& model);

 private:
  FixtureReplay();
  struct Impl;
  std::unique_ptr<Impl> impl_;
  size_t next_ = 0;
};

}  // namespace wm
