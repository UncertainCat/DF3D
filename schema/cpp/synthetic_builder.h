// Synthetic fixture builder: hand-built snapshot sequences
// for unit-level tests. Synthetic fixtures test logic; recorded fixtures
// (via the bridge, once it exists) test reality.
#pragma once

#include <array>
#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <tuple>
#include <vector>

#include "entity_util.h"
#include "glyph_util.h"
#include "mirror_generated.h"
#include "terrain_util.h"

namespace df3d::mirror {

class SyntheticFort {
 public:
  explicit SyntheticFort(int32_t sizeX, int32_t sizeY, int32_t sizeZ);

  // --- units ---
  void addUnit(uint64_t id, std::string species, int32_t x, int32_t y, int32_t z,
               JobKind job = JobKind::Idle);
  void moveUnit(uint64_t id, int32_t x, int32_t y, int32_t z);
  void setJob(uint64_t id, JobKind job);
  void setBodyVolume(uint64_t id, uint32_t volume) { live_.at(id).bodyVolumeCm3 = volume; }
  void setUnitStatusFlags(uint64_t id, uint64_t flags) { live_.at(id).statusFlags = flags; }
  void removeUnit(uint64_t id);

  // --- appearance references (v3) ---
  // One layer as authored: names instead of snapshot-local indices; the
  // builder interns them per snapshot. An empty palette name = drawn as-is.
  struct Layer {
    std::string page;
    uint16_t tileX = 0, tileY = 0;
    uint8_t cellsX = 1, cellsY = 1;
    std::string palette;
    int16_t paletteRow = -1, paletteKeyRow = -1;
    int8_t offsetX = 0, offsetY = 0;
  };
  // Sets (or replaces) the unit's layer stack. The next snapshot carries
  // it (appearance_scope Delta); unchanged units are not re-sent unless a
  // Full is requested. Throws std::out_of_range for an unknown unit.
  void setAppearance(uint64_t id, std::vector<Layer> layers);
  // The next snapshot carries every unit's appearance (Full; units that
  // never had one get an empty layer stack).
  void requestFullAppearances();
  // Overrides the appearance_scope stamped on the NEXT snapshot only
  // (validator tests).
  void forgeNextAppearanceScope(AppearanceScope s) {
    forgedAppScope_ = s;
    hasForgedAppScope_ = true;
  }

  // --- terrain ---
  // Interns a raw material identifier (e.g. "GRANITE") and returns the
  // index to store in TileState.material / Building.material /
  // MapItem.material. Idempotent per identifier. Does not by itself turn
  // terrain emission on.
  uint16_t material(const std::string& id);
  // Sets one tile (map coordinates). Throws std::out_of_range outside the
  // map. Marks the containing block dirty if the tile changed.
  void setTile(int32_t x, int32_t y, int32_t z, const TileState& t);
  // Current authored state of a tile; emptyTile() where never set.
  TileState tile(int32_t x, int32_t y, int32_t z) const;
  // Sets every tile in the inclusive box [min, max].
  void fillBox(TilePos min, TilePos max, const TileState& t);
  // Forces a block into the next Delta even if no tile changed.
  void markBlockDirty(int32_t bx, int32_t by, int32_t bz);
  // Sparse DesignationDetail for one tile (priority 1..7, marker-only work);
  // emitted with every block that carries the tile. Marks the block dirty.
  void setDesignationDetail(int32_t x, int32_t y, int32_t z, uint8_t priority, bool marker);
  // The next snapshot emits Full regardless of dirty state.
  void requestFullTerrain();
  bool terrainEnabled() const { return terrainEnabled_; }

  // --- buildings (v4) ---
  // A building as authored. The builder does not validate specs (validator
  // tests author invalid ones on purpose); the validators do.
  struct BuildingSpec {
    BuildingKind kind = BuildingKind::Unknown;
    uint16_t subtype = kNoSubtype;
    std::string custom;
    int32_t x1 = 0, y1 = 0, x2 = 0, y2 = 0, z = 0;
    // -1 (the default) resolves to the rectangle's centre at placement.
    int32_t centerX = -1, centerY = -1;
    std::vector<uint8_t> extents;
    uint16_t material = kNoMaterial;
    BuildingStage stage = BuildingStage::Complete;
    BuildingFlags flags = BuildingFlags::NONE;
    friend bool operator==(const BuildingSpec&, const BuildingSpec&) = default;
  };
  // Adds or replaces a building; the next snapshot carries it if it
  // changed (Delta) or in any case after requestFullBuildings().
  void placeBuilding(uint32_t id, BuildingSpec spec);
  // The authored spec (centre resolved). Throws std::out_of_range.
  BuildingSpec building(uint32_t id) const;
  void setBuildingStage(uint32_t id, BuildingStage stage);
  void setBuildingFlags(uint32_t id, BuildingFlags flags);
  // Removes it; the next Delta lists the id in removed_buildings (unless a
  // Full is emitted instead). Throws std::out_of_range.
  void removeBuilding(uint32_t id);
  void requestFullBuildings();
  bool buildingsEnabled() const { return buildingsEnabled_; }
  // Overrides the building_scope stamped on the NEXT snapshot only.
  void forgeNextBuildingScope(ChangeScope s) {
    forgedBuildingScope_ = s;
    hasForgedBuildingScope_ = true;
  }

  // --- map items (v4) ---
  struct ItemSpec {
    ItemKind kind = ItemKind::Unknown;
    uint16_t subtype = kNoSubtype;
    std::string subtypeRaw;
    uint16_t material = kNoMaterial;
    int32_t x = 0, y = 0, z = 0;
    uint32_t stack = 1;
    ItemFlags flags = ItemFlags::NONE;
    int32_t corpseUnitId = -1;
    CorpseFlags corpseFlags = CorpseFlags::NONE;  // v5, Corpse / CorpsePiece only
    friend bool operator==(const ItemSpec&, const ItemSpec&) = default;
  };
  void placeItem(uint32_t id, ItemSpec spec);
  ItemSpec item(uint32_t id) const;  // throws std::out_of_range
  void moveItem(uint32_t id, int32_t x, int32_t y, int32_t z);
  void setItemFlags(uint32_t id, ItemFlags flags);
  // The item leaves the map (hauled, destroyed); the next Delta lists it.
  void removeItem(uint32_t id);
  void requestFullItems();
  bool itemsEnabled() const { return itemsEnabled_; }
  void forgeNextItemScope(ChangeScope s) {
    forgedItemScope_ = s;
    hasForgedItemScope_ = true;
  }

  // --- corpse appearance references (v5) ---
  // Sets (or replaces) the item's layer stack (the same Layer vocabulary
  // as units). The item is re-sent with its stack in the next snapshot
  // (item Delta + item_appearance_scope Delta); an item Full carries every
  // authored stack and an empty entry for every other Corpse / CorpsePiece
  // item (Full). Throws std::out_of_range for an unknown item.
  void setItemAppearance(uint32_t id, std::vector<Layer> layers);

  // --- classic glyph tables (v5) ---
  struct CreatureGlyphSpec {
    Glyph glyph;
    uint8_t soldierTile = 0;
    friend bool operator==(const CreatureGlyphSpec& a, const CreatureGlyphSpec& b) {
      return glyphEquals(a.glyph, b.glyph) && a.soldierTile == b.soldierTile;
    }
  };
  struct MaterialGlyphSpec {
    uint8_t tile = 0, itemSymbol = 0, basicFg = 7, basicBright = 0;
    Glyph build, tileColor;
    friend bool operator==(const MaterialGlyphSpec& a, const MaterialGlyphSpec& b) {
      return a.tile == b.tile && a.itemSymbol == b.itemSymbol && a.basicFg == b.basicFg &&
             a.basicBright == b.basicBright && glyphEquals(a.build, b.build) &&
             glyphEquals(a.tileColor, b.tileColor);
    }
  };
  // Adds or replaces an entry; the first snapshot after any glyph call
  // carries every entry (Full), later ones the entries added or changed
  // since the previous snapshot (Delta) or None. An identical re-set is
  // not a change.
  void creatureGlyph(const std::string& species, CreatureGlyphSpec spec);
  void materialGlyph(const std::string& material, MaterialGlyphSpec spec);
  void itemDefGlyph(ItemKind kind, const std::string& subtypeRaw, uint8_t tile);
  void requestFullGlyphs();

  // --- command results (v6) ---
  // Queues one CommandResult for the NEXT snapshot only (the bridge's
  // repeat window is a transport detail; fixtures author each result
  // where it should first appear). The builder does not check seq
  // uniqueness (validator tests author duplicates on purpose).
  void commandResult(uint64_t seq, CommandStatus status, std::string message = {});

  // Records the current state at `tick`. If emittedAtMs is 0 it defaults to
  // tick * 10 (a synthetic 100 ticks/sec bridge clock).
  void snapshot(uint64_t tick, uint64_t emittedAtMs = 0);

  std::vector<uint8_t> serialize() const;

  // Overrides the schema version stamped on subsequent snapshots. Only for
  // building intentionally-invalid fixtures in validator tests.
  void forgeSchemaVersion(uint32_t v) { schemaVersion_ = v; }
  // Overrides the terrain_scope stamped on the NEXT snapshot only, without
  // changing which blocks it carries. Only for validator tests (e.g. a
  // Delta before any Full, or None with blocks attached).
  void forgeNextTerrainScope(TerrainScope s) { forgedScope_ = s; hasForgedScope_ = true; }

 private:
  struct UnitRec {
    std::string species;
    int32_t x, y, z;
    JobKind job;
    uint32_t bodyVolumeCm3 = 0;
    uint64_t statusFlags = 0;
  };
  using BlockKey = std::tuple<int32_t, int32_t, int32_t>;  // bx, by, bz
  struct BlockRec {
    int32_t bx, by, bz;
    std::array<TileState, kTilesPerBlock> tiles;
    std::vector<DesignationDetail> details;
  };
  struct AppRec {
    uint64_t unit;
    uint32_t version;
    std::vector<Layer> layers;
  };
  struct SnapRec {
    uint64_t tick;
    uint64_t emittedAtMs;
    std::vector<std::pair<uint64_t, UnitRec>> units;
    TerrainScope scope = TerrainScope::None;
    std::vector<BlockRec> blocks;
    size_t materialCount = 0;  // prefix of materials_ visible to this snapshot
    AppearanceScope appScope = AppearanceScope::None;
    std::vector<AppRec> appearances;
    ChangeScope buildingScope = ChangeScope::None;
    std::vector<std::pair<uint32_t, BuildingSpec>> buildings;
    std::vector<uint32_t> removedBuildings;
    ChangeScope itemScope = ChangeScope::None;
    std::vector<std::pair<uint32_t, ItemSpec>> items;
    std::vector<uint32_t> removedItems;
    AppearanceScope itemAppScope = AppearanceScope::None;
    std::vector<std::pair<uint32_t, std::vector<Layer>>> itemAppearances;
    ChangeScope glyphScope = ChangeScope::None;
    std::vector<std::pair<std::string, CreatureGlyphSpec>> creatureGlyphs;
    std::vector<std::pair<std::string, MaterialGlyphSpec>> materialGlyphs;
    std::vector<std::tuple<ItemKind, std::string, uint8_t>> itemDefGlyphs;
    std::vector<std::tuple<uint64_t, CommandStatus, std::string>> commandResults;
  };

  void ensureTerrain();
  size_t denseIndex(int32_t x, int32_t y, int32_t z) const;
  BlockRec copyBlock(int32_t bx, int32_t by, int32_t bz) const;

  int32_t sizeX_, sizeY_, sizeZ_;
  uint32_t schemaVersion_ = static_cast<uint32_t>(SchemaVersion::Current);
  std::map<uint64_t, UnitRec> live_;
  std::vector<SnapRec> snaps_;

  // Terrain: dense block-padded grid, allocated on first terrain call.
  bool terrainEnabled_ = false;
  bool needFull_ = true;
  int32_t paddedX_ = 0, paddedY_ = 0;
  std::vector<TileState> terrain_;
  std::set<BlockKey> dirty_;
  std::map<std::tuple<int32_t, int32_t, int32_t>, std::pair<uint8_t, bool>> designationDetails_;
  std::vector<std::string> materials_;
  std::map<std::string, uint16_t> materialIndex_;
  TerrainScope forgedScope_ = TerrainScope::None;
  bool hasForgedScope_ = false;

  // Appearances: the authored stack per unit, plus which units changed
  // since the last snapshot.
  std::map<uint64_t, std::vector<Layer>> appearances_;
  std::set<uint64_t> appDirty_;
  bool needFullApp_ = false;
  AppearanceScope forgedAppScope_ = AppearanceScope::None;
  bool hasForgedAppScope_ = false;

  // Buildings and items: current state, dirty ids, removed ids.
  bool buildingsEnabled_ = false;
  bool needFullBuildings_ = true;
  std::map<uint32_t, BuildingSpec> buildings_;
  std::set<uint32_t> buildingDirty_;
  std::set<uint32_t> buildingRemoved_;
  ChangeScope forgedBuildingScope_ = ChangeScope::None;
  bool hasForgedBuildingScope_ = false;

  bool itemsEnabled_ = false;
  bool needFullItems_ = true;
  std::map<uint32_t, ItemSpec> items_;
  std::set<uint32_t> itemDirty_;
  std::set<uint32_t> itemRemoved_;
  ChangeScope forgedItemScope_ = ChangeScope::None;
  bool hasForgedItemScope_ = false;

  // Corpse appearances: the authored stack per item, dirty ids.
  std::map<uint32_t, std::vector<Layer>> itemAppearances_;
  std::set<uint32_t> itemAppDirty_;

  // Glyph tables: current entries and the keys changed since the last
  // snapshot.
  bool glyphsEnabled_ = false;
  bool needFullGlyphs_ = true;
  std::map<std::string, CreatureGlyphSpec> creatureGlyphs_;
  std::map<std::string, MaterialGlyphSpec> materialGlyphs_;
  std::map<std::pair<ItemKind, std::string>, uint8_t> itemDefGlyphs_;
  std::set<std::string> creatureGlyphDirty_, materialGlyphDirty_;
  std::set<std::pair<ItemKind, std::string>> itemDefGlyphDirty_;

  // Command results queued for the next snapshot (v6).
  std::vector<std::tuple<uint64_t, CommandStatus, std::string>> pendingResults_;
};

}  // namespace df3d::mirror
