#include "synthetic_builder.h"

#include <stdexcept>

#include "appearance_util.h"
#include "fixture_io.h"

namespace df3d::mirror {

SyntheticFort::SyntheticFort(int32_t sizeX, int32_t sizeY, int32_t sizeZ)
    : sizeX_(sizeX), sizeY_(sizeY), sizeZ_(sizeZ) {}

// --- units ---

void SyntheticFort::addUnit(uint64_t id, std::string species, int32_t x, int32_t y,
                            int32_t z, JobKind job) {
  if (live_.count(id)) throw std::logic_error("SyntheticFort: duplicate unit id");
  live_[id] = UnitRec{std::move(species), x, y, z, job};
}

void SyntheticFort::moveUnit(uint64_t id, int32_t x, int32_t y, int32_t z) {
  auto& u = live_.at(id);
  u.x = x;
  u.y = y;
  u.z = z;
}

void SyntheticFort::setJob(uint64_t id, JobKind job) { live_.at(id).job = job; }

void SyntheticFort::removeUnit(uint64_t id) {
  if (!live_.erase(id)) throw std::logic_error("SyntheticFort: removing unknown unit");
  appearances_.erase(id);
  appDirty_.erase(id);
}

// --- appearance references ---

void SyntheticFort::setAppearance(uint64_t id, std::vector<Layer> layers) {
  if (!live_.count(id)) throw std::out_of_range("SyntheticFort: appearance for unknown unit");
  appearances_[id] = std::move(layers);
  appDirty_.insert(id);
}

void SyntheticFort::requestFullAppearances() { needFullApp_ = true; }

namespace {
uint32_t hashLayers(const std::vector<SyntheticFort::Layer>& layers) {
  uint32_t h = appearanceHashBegin();
  for (const auto& l : layers) {
    h = appearanceHashLayer(h, l.page.data(), l.page.size(), l.tileX, l.tileY, l.cellsX,
                            l.cellsY, l.palette.data(), l.palette.size(), l.paletteRow,
                            l.paletteKeyRow, l.offsetX, l.offsetY);
  }
  return h;
}
}  // namespace

// --- terrain ---

void SyntheticFort::ensureTerrain() {
  if (terrainEnabled_) return;
  terrainEnabled_ = true;
  paddedX_ = blocksAlong(sizeX_) * kBlockSize;
  paddedY_ = blocksAlong(sizeY_) * kBlockSize;
  terrain_.assign(static_cast<size_t>(paddedX_) * paddedY_ * sizeZ_, emptyTile());
}

size_t SyntheticFort::denseIndex(int32_t x, int32_t y, int32_t z) const {
  return (static_cast<size_t>(z) * paddedY_ + static_cast<size_t>(y)) * paddedX_ +
         static_cast<size_t>(x);
}

uint16_t SyntheticFort::material(const std::string& id) {
  if (id.empty()) throw std::invalid_argument("SyntheticFort: empty material identifier");
  auto it = materialIndex_.find(id);
  if (it != materialIndex_.end()) return it->second;
  if (materials_.size() >= kNoMaterial) {
    throw std::length_error("SyntheticFort: material table full");
  }
  const auto idx = static_cast<uint16_t>(materials_.size());
  materials_.push_back(id);
  materialIndex_[id] = idx;
  return idx;
}

void SyntheticFort::setTile(int32_t x, int32_t y, int32_t z, const TileState& t) {
  if (x < 0 || y < 0 || z < 0 || x >= sizeX_ || y >= sizeY_ || z >= sizeZ_) {
    throw std::out_of_range("SyntheticFort: tile outside map");
  }
  ensureTerrain();
  TileState& cur = terrain_[denseIndex(x, y, z)];
  if (tileEquals(cur, t)) return;
  cur = t;
  dirty_.insert(BlockKey{x / kBlockSize, y / kBlockSize, z});
}

TileState SyntheticFort::tile(int32_t x, int32_t y, int32_t z) const {
  if (x < 0 || y < 0 || z < 0 || x >= sizeX_ || y >= sizeY_ || z >= sizeZ_) {
    throw std::out_of_range("SyntheticFort: tile outside map");
  }
  if (!terrainEnabled_) return emptyTile();
  return terrain_[denseIndex(x, y, z)];
}

void SyntheticFort::fillBox(TilePos min, TilePos max, const TileState& t) {
  for (int32_t z = min.z(); z <= max.z(); ++z)
    for (int32_t y = min.y(); y <= max.y(); ++y)
      for (int32_t x = min.x(); x <= max.x(); ++x) setTile(x, y, z, t);
}

void SyntheticFort::markBlockDirty(int32_t bx, int32_t by, int32_t bz) {
  if (bx < 0 || by < 0 || bz < 0 || bx >= blocksAlong(sizeX_) || by >= blocksAlong(sizeY_) ||
      bz >= sizeZ_) {
    throw std::out_of_range("SyntheticFort: block outside map");
  }
  ensureTerrain();
  dirty_.insert(BlockKey{bx, by, bz});
}

void SyntheticFort::requestFullTerrain() {
  ensureTerrain();
  needFull_ = true;
}

void SyntheticFort::setDesignationDetail(int32_t x, int32_t y, int32_t z, uint8_t priority,
                                         bool marker) {
  ensureTerrain();
  denseIndex(x, y, z);  // bounds check
  designationDetails_[{x, y, z}] = {priority, marker};
  dirty_.insert(BlockKey{x / kBlockSize, y / kBlockSize, z});
}

SyntheticFort::BlockRec SyntheticFort::copyBlock(int32_t bx, int32_t by, int32_t bz) const {
  BlockRec b{bx, by, bz, {}, {}};
  for (int32_t ly = 0; ly < kBlockSize; ++ly)
    for (int32_t lx = 0; lx < kBlockSize; ++lx) {
      b.tiles[tileIndex(lx, ly)] =
          terrain_[denseIndex(bx * kBlockSize + lx, by * kBlockSize + ly, bz)];
    }
  for (const auto& [pos, detail] : designationDetails_) {
    const auto [x, y, z] = pos;
    if (x / kBlockSize != bx || y / kBlockSize != by || z != bz) continue;
    b.details.emplace_back(static_cast<uint16_t>(tileIndex(x % kBlockSize, y % kBlockSize)),
                           detail.first, detail.second);
  }
  return b;
}

// --- buildings ---

void SyntheticFort::placeBuilding(uint32_t id, BuildingSpec spec) {
  buildingsEnabled_ = true;
  if (spec.centerX < 0) spec.centerX = spec.x1 + (spec.x2 - spec.x1) / 2;
  if (spec.centerY < 0) spec.centerY = spec.y1 + (spec.y2 - spec.y1) / 2;
  auto it = buildings_.find(id);
  if (it != buildings_.end() && it->second == spec) return;  // no-op
  buildings_[id] = std::move(spec);
  buildingDirty_.insert(id);
  buildingRemoved_.erase(id);  // re-added within the same tick: a change
}

SyntheticFort::BuildingSpec SyntheticFort::building(uint32_t id) const {
  return buildings_.at(id);
}

void SyntheticFort::setBuildingStage(uint32_t id, BuildingStage stage) {
  BuildingSpec spec = buildings_.at(id);
  spec.stage = stage;
  placeBuilding(id, std::move(spec));
}

void SyntheticFort::setBuildingFlags(uint32_t id, BuildingFlags flags) {
  BuildingSpec spec = buildings_.at(id);
  spec.flags = flags;
  placeBuilding(id, std::move(spec));
}

void SyntheticFort::removeBuilding(uint32_t id) {
  if (!buildings_.erase(id)) throw std::out_of_range("SyntheticFort: removing unknown building");
  buildingDirty_.erase(id);
  buildingRemoved_.insert(id);
}

void SyntheticFort::requestFullBuildings() {
  buildingsEnabled_ = true;
  needFullBuildings_ = true;
}

// --- map items ---

void SyntheticFort::placeItem(uint32_t id, ItemSpec spec) {
  itemsEnabled_ = true;
  auto it = items_.find(id);
  if (it != items_.end() && it->second == spec) return;  // no-op
  items_[id] = std::move(spec);
  itemDirty_.insert(id);
  itemRemoved_.erase(id);
}

SyntheticFort::ItemSpec SyntheticFort::item(uint32_t id) const { return items_.at(id); }

void SyntheticFort::moveItem(uint32_t id, int32_t x, int32_t y, int32_t z) {
  ItemSpec spec = items_.at(id);
  spec.x = x;
  spec.y = y;
  spec.z = z;
  placeItem(id, std::move(spec));
}

void SyntheticFort::setItemFlags(uint32_t id, ItemFlags flags) {
  ItemSpec spec = items_.at(id);
  spec.flags = flags;
  placeItem(id, std::move(spec));
}

void SyntheticFort::removeItem(uint32_t id) {
  if (!items_.erase(id)) throw std::out_of_range("SyntheticFort: removing unknown item");
  itemDirty_.erase(id);
  itemRemoved_.insert(id);
  itemAppearances_.erase(id);
  itemAppDirty_.erase(id);
}

// --- corpse appearance references (v5) ---

void SyntheticFort::setItemAppearance(uint32_t id, std::vector<Layer> layers) {
  if (!items_.count(id)) throw std::out_of_range("SyntheticFort: appearance for unknown item");
  itemAppearances_[id] = std::move(layers);
  itemAppDirty_.insert(id);
  itemDirty_.insert(id);  // the stack travels with its item record
}

// --- classic glyph tables (v5) ---

void SyntheticFort::creatureGlyph(const std::string& species, CreatureGlyphSpec spec) {
  if (species.empty()) throw std::invalid_argument("SyntheticFort: empty species");
  glyphsEnabled_ = true;
  auto it = creatureGlyphs_.find(species);
  if (it != creatureGlyphs_.end() && it->second == spec) return;
  creatureGlyphs_[species] = spec;
  creatureGlyphDirty_.insert(species);
}

void SyntheticFort::materialGlyph(const std::string& material, MaterialGlyphSpec spec) {
  if (material.empty()) throw std::invalid_argument("SyntheticFort: empty material");
  glyphsEnabled_ = true;
  auto it = materialGlyphs_.find(material);
  if (it != materialGlyphs_.end() && it->second == spec) return;
  materialGlyphs_[material] = spec;
  materialGlyphDirty_.insert(material);
}

void SyntheticFort::itemDefGlyph(ItemKind kind, const std::string& subtypeRaw, uint8_t tile) {
  if (subtypeRaw.empty()) throw std::invalid_argument("SyntheticFort: empty subtype raw id");
  glyphsEnabled_ = true;
  const std::pair<ItemKind, std::string> key{kind, subtypeRaw};
  auto it = itemDefGlyphs_.find(key);
  if (it != itemDefGlyphs_.end() && it->second == tile) return;
  itemDefGlyphs_[key] = tile;
  itemDefGlyphDirty_.insert(key);
}

void SyntheticFort::requestFullGlyphs() {
  glyphsEnabled_ = true;
  needFullGlyphs_ = true;
}

void SyntheticFort::requestFullItems() {
  itemsEnabled_ = true;
  needFullItems_ = true;
}

// --- snapshots ---

void SyntheticFort::snapshot(uint64_t tick, uint64_t emittedAtMs) {
  SnapRec rec;
  rec.tick = tick;
  rec.emittedAtMs = emittedAtMs ? emittedAtMs : tick * 10;
  rec.units.assign(live_.begin(), live_.end());
  rec.materialCount = materials_.size();
  if (terrainEnabled_) {
    if (needFull_) {
      rec.scope = TerrainScope::Full;
      for (int32_t bz = 0; bz < sizeZ_; ++bz)
        for (int32_t by = 0; by < blocksAlong(sizeY_); ++by)
          for (int32_t bx = 0; bx < blocksAlong(sizeX_); ++bx)
            rec.blocks.push_back(copyBlock(bx, by, bz));
      needFull_ = false;
    } else {
      rec.scope = TerrainScope::Delta;
      for (const auto& [bx, by, bz] : dirty_) rec.blocks.push_back(copyBlock(bx, by, bz));
    }
    dirty_.clear();
  }
  if (hasForgedScope_) {
    rec.scope = forgedScope_;
    hasForgedScope_ = false;
  }
  if (needFullApp_) {
    rec.appScope = AppearanceScope::Full;
    for (const auto& [id, u] : live_) {
      auto it = appearances_.find(id);
      std::vector<Layer> layers = it == appearances_.end() ? std::vector<Layer>{} : it->second;
      rec.appearances.push_back(AppRec{id, hashLayers(layers), std::move(layers)});
    }
    needFullApp_ = false;
  } else if (!appDirty_.empty()) {
    rec.appScope = AppearanceScope::Delta;
    for (uint64_t id : appDirty_) {
      const auto& layers = appearances_.at(id);
      rec.appearances.push_back(AppRec{id, hashLayers(layers), layers});
    }
  }
  appDirty_.clear();
  if (hasForgedAppScope_) {
    rec.appScope = forgedAppScope_;
    hasForgedAppScope_ = false;
  }
  if (buildingsEnabled_) {
    if (needFullBuildings_) {
      rec.buildingScope = ChangeScope::Full;
      rec.buildings.assign(buildings_.begin(), buildings_.end());
      needFullBuildings_ = false;
    } else {
      rec.buildingScope = ChangeScope::Delta;
      for (uint32_t id : buildingDirty_) rec.buildings.emplace_back(id, buildings_.at(id));
      rec.removedBuildings.assign(buildingRemoved_.begin(), buildingRemoved_.end());
    }
    buildingDirty_.clear();
    buildingRemoved_.clear();
  }
  if (hasForgedBuildingScope_) {
    rec.buildingScope = forgedBuildingScope_;
    hasForgedBuildingScope_ = false;
  }
  if (itemsEnabled_) {
    if (needFullItems_) {
      rec.itemScope = ChangeScope::Full;
      rec.items.assign(items_.begin(), items_.end());
      needFullItems_ = false;
    } else {
      rec.itemScope = ChangeScope::Delta;
      for (uint32_t id : itemDirty_) rec.items.emplace_back(id, items_.at(id));
      rec.removedItems.assign(itemRemoved_.begin(), itemRemoved_.end());
    }
    itemDirty_.clear();
    itemRemoved_.clear();
  }
  if (hasForgedItemScope_) {
    rec.itemScope = forgedItemScope_;
    hasForgedItemScope_ = false;
  }
  // Corpse appearances ride with their item records: every authored
  // stack of an item in this snapshot when the item table is Full (plus an
  // empty entry for the other corpse items), else the changed ones.
  if (rec.itemScope == ChangeScope::Full) {
    rec.itemAppScope = AppearanceScope::Full;
    for (const auto& [id, it] : rec.items) {
      auto a = itemAppearances_.find(id);
      if (a != itemAppearances_.end()) {
        rec.itemAppearances.emplace_back(id, a->second);
      } else if (it.kind == ItemKind::Corpse || it.kind == ItemKind::CorpsePiece) {
        rec.itemAppearances.emplace_back(id, std::vector<Layer>{});
      }
    }
  } else if (rec.itemScope == ChangeScope::Delta) {
    for (const auto& [id, it] : rec.items) {
      if (!itemAppDirty_.count(id)) continue;
      rec.itemAppearances.emplace_back(id, itemAppearances_.at(id));
    }
    if (!rec.itemAppearances.empty()) rec.itemAppScope = AppearanceScope::Delta;
  }
  itemAppDirty_.clear();
  if (glyphsEnabled_) {
    if (needFullGlyphs_) {
      rec.glyphScope = ChangeScope::Full;
      rec.creatureGlyphs.assign(creatureGlyphs_.begin(), creatureGlyphs_.end());
      rec.materialGlyphs.assign(materialGlyphs_.begin(), materialGlyphs_.end());
      for (const auto& [key, tile] : itemDefGlyphs_)
        rec.itemDefGlyphs.emplace_back(key.first, key.second, tile);
      needFullGlyphs_ = false;
    } else {
      for (const std::string& k : creatureGlyphDirty_) rec.creatureGlyphs.emplace_back(k, creatureGlyphs_.at(k));
      for (const std::string& k : materialGlyphDirty_) rec.materialGlyphs.emplace_back(k, materialGlyphs_.at(k));
      for (const auto& k : itemDefGlyphDirty_) rec.itemDefGlyphs.emplace_back(k.first, k.second, itemDefGlyphs_.at(k));
      if (!rec.creatureGlyphs.empty() || !rec.materialGlyphs.empty() || !rec.itemDefGlyphs.empty())
        rec.glyphScope = ChangeScope::Delta;
    }
    creatureGlyphDirty_.clear();
    materialGlyphDirty_.clear();
    itemDefGlyphDirty_.clear();
  }
  rec.commandResults = std::move(pendingResults_);
  pendingResults_.clear();
  snaps_.push_back(std::move(rec));
}

void SyntheticFort::commandResult(uint64_t seq, CommandStatus status, std::string message) {
  pendingResults_.emplace_back(seq, status, std::move(message));
}

std::vector<uint8_t> SyntheticFort::serialize() const {
  std::vector<std::vector<uint8_t>> buffers;
  buffers.reserve(snaps_.size());
  for (const auto& rec : snaps_) {
    flatbuffers::FlatBufferBuilder fbb;
    std::vector<flatbuffers::Offset<UnitState>> units;
    units.reserve(rec.units.size());
    for (const auto& [id, u] : rec.units) {
      auto species = fbb.CreateString(u.species);
      TilePos pos(u.x, u.y, u.z);
      units.push_back(CreateUnitState(fbb, id, &pos, species, u.job, 0, u.bodyVolumeCm3, u.statusFlags));
    }
    auto unitsVec = fbb.CreateVector(units);

    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<MapBlock>>> blocksVec = 0;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>>
        materialsVec = 0;
    if (rec.scope != TerrainScope::None || !rec.blocks.empty()) {
      std::vector<flatbuffers::Offset<MapBlock>> blocks;
      blocks.reserve(rec.blocks.size());
      for (const auto& b : rec.blocks) {
        auto tiles = fbb.CreateVectorOfStructs(b.tiles.data(), b.tiles.size());
        flatbuffers::Offset<flatbuffers::Vector<const DesignationDetail*>> details = 0;
        if (!b.details.empty()) details = fbb.CreateVectorOfStructs(b.details);
        blocks.push_back(CreateMapBlock(fbb, b.bx, b.by, b.bz, tiles, details));
      }
      blocksVec = fbb.CreateVector(blocks);
    }
    if (rec.materialCount > 0 || rec.scope != TerrainScope::None) {
      std::vector<flatbuffers::Offset<flatbuffers::String>> mats;
      mats.reserve(rec.materialCount);
      for (size_t i = 0; i < rec.materialCount; ++i) mats.push_back(fbb.CreateString(materials_[i]));
      materialsVec = fbb.CreateVector(mats);
    }

    // Buildings and items (v4).
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<Building>>> buildingsVec = 0;
    flatbuffers::Offset<flatbuffers::Vector<uint32_t>> removedBuildingsVec = 0;
    if (rec.buildingScope != ChangeScope::None || !rec.buildings.empty() ||
        !rec.removedBuildings.empty()) {
      std::vector<flatbuffers::Offset<Building>> list;
      list.reserve(rec.buildings.size());
      for (const auto& [id, b] : rec.buildings) {
        list.push_back(CreateBuildingDirect(
            fbb, id, b.kind, b.subtype, b.custom.empty() ? nullptr : b.custom.c_str(), b.x1,
            b.y1, b.x2, b.y2, b.z, b.centerX, b.centerY, b.extents.empty() ? nullptr : &b.extents,
            b.material, b.stage, b.flags));
      }
      buildingsVec = fbb.CreateVector(list);
      removedBuildingsVec = fbb.CreateVector(rec.removedBuildings);
    }
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<MapItem>>> itemsVec = 0;
    flatbuffers::Offset<flatbuffers::Vector<uint32_t>> removedItemsVec = 0;
    if (rec.itemScope != ChangeScope::None || !rec.items.empty() || !rec.removedItems.empty()) {
      std::vector<flatbuffers::Offset<MapItem>> list;
      list.reserve(rec.items.size());
      for (const auto& [id, it] : rec.items) {
        TilePos pos(it.x, it.y, it.z);
        list.push_back(CreateMapItemDirect(fbb, id, it.kind, it.subtype,
                                           it.subtypeRaw.empty() ? nullptr : it.subtypeRaw.c_str(),
                                           it.material, &pos, it.stack, it.flags, it.corpseFlags, it.corpseUnitId));
      }
      itemsVec = fbb.CreateVector(list);
      removedItemsVec = fbb.CreateVector(rec.removedItems);
    }

    // Appearances: intern page tokens and palette paths per snapshot.
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<UnitAppearance>>> appsVec = 0;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>> pagesVec =
        0;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<flatbuffers::String>>>
        palettesVec = 0;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<ItemAppearance>>> itemAppsVec = 0;
    const bool anyApps = rec.appScope != AppearanceScope::None || !rec.appearances.empty();
    const bool anyItemApps =
        rec.itemAppScope != AppearanceScope::None || !rec.itemAppearances.empty();
    if (anyApps || anyItemApps) {
      std::vector<std::string> pages, palettes;
      auto intern = [](std::vector<std::string>& table, const std::string& name) {
        for (size_t i = 0; i < table.size(); ++i)
          if (table[i] == name) return static_cast<uint16_t>(i);
        table.push_back(name);
        return static_cast<uint16_t>(table.size() - 1);
      };
      auto internLayers = [&](const std::vector<Layer>& src) {
        std::vector<AppearanceLayer> layers;
        layers.reserve(src.size());
        for (const auto& l : src) {
          const uint16_t page = intern(pages, l.page);
          const uint16_t palette = l.palette.empty() ? kNoPalette : intern(palettes, l.palette);
          layers.emplace_back(page, l.tileX, l.tileY, l.cellsX, l.cellsY, palette, l.paletteRow,
                              l.paletteKeyRow, l.offsetX, l.offsetY);
        }
        return fbb.CreateVectorOfStructs(layers);
      };
      if (anyApps) {
        std::vector<flatbuffers::Offset<UnitAppearance>> apps;
        apps.reserve(rec.appearances.size());
        for (const auto& a : rec.appearances) {
          auto layersVec = internLayers(a.layers);
          apps.push_back(CreateUnitAppearance(fbb, a.unit, a.version, layersVec));
        }
        appsVec = fbb.CreateVector(apps);
      }
      if (anyItemApps) {
        std::vector<flatbuffers::Offset<ItemAppearance>> apps;
        apps.reserve(rec.itemAppearances.size());
        for (const auto& [id, layers] : rec.itemAppearances) {
          auto layersVec = internLayers(layers);
          apps.push_back(CreateItemAppearance(fbb, id, hashLayers(layers), layersVec));
        }
        itemAppsVec = fbb.CreateVector(apps);
      }
      pagesVec = fbb.CreateVectorOfStrings(pages);
      palettesVec = fbb.CreateVectorOfStrings(palettes);
    }

    // Glyph tables (v5).
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<CreatureGlyph>>> creatureGlyphsVec = 0;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<MaterialGlyph>>> materialGlyphsVec = 0;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<ItemDefGlyph>>> itemDefGlyphsVec = 0;
    if (rec.glyphScope != ChangeScope::None || !rec.creatureGlyphs.empty() ||
        !rec.materialGlyphs.empty() || !rec.itemDefGlyphs.empty()) {
      std::vector<flatbuffers::Offset<CreatureGlyph>> cg;
      for (const auto& [species, g] : rec.creatureGlyphs) {
        auto name = fbb.CreateString(species);
        cg.push_back(CreateCreatureGlyph(fbb, name, &g.glyph, g.soldierTile));
      }
      creatureGlyphsVec = fbb.CreateVector(cg);
      std::vector<flatbuffers::Offset<MaterialGlyph>> mg;
      for (const auto& [material, g] : rec.materialGlyphs) {
        auto name = fbb.CreateString(material);
        mg.push_back(CreateMaterialGlyph(fbb, name, g.tile, g.itemSymbol, g.basicFg, g.basicBright,
                                         &g.build, &g.tileColor));
      }
      materialGlyphsVec = fbb.CreateVector(mg);
      std::vector<flatbuffers::Offset<ItemDefGlyph>> ig;
      for (const auto& [kind, raw, tile] : rec.itemDefGlyphs) {
        auto name = fbb.CreateString(raw);
        ig.push_back(CreateItemDefGlyph(fbb, kind, name, tile));
      }
      itemDefGlyphsVec = fbb.CreateVector(ig);
    }

    // Command results (v6).
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<CommandResult>>> resultsVec = 0;
    if (!rec.commandResults.empty()) {
      std::vector<flatbuffers::Offset<CommandResult>> rs;
      for (const auto& [seq, status, message] : rec.commandResults) {
        auto msg = fbb.CreateString(message);
        rs.push_back(CreateCommandResult(fbb, seq, status, msg));
      }
      resultsVec = fbb.CreateVector(rs);
    }

    TilePos dims(sizeX_, sizeY_, sizeZ_);
    auto snap = CreateSnapshot(fbb, schemaVersion_, rec.tick, rec.emittedAtMs, &dims, unitsVec,
                               rec.scope, blocksVec, materialsVec, rec.appScope, appsVec,
                               pagesVec, palettesVec, rec.buildingScope, buildingsVec,
                               removedBuildingsVec, rec.itemScope, itemsVec, removedItemsVec,
                               rec.itemAppScope, itemAppsVec, rec.glyphScope, creatureGlyphsVec,
                               materialGlyphsVec, itemDefGlyphsVec, resultsVec);
    fbb.FinishSizePrefixed(snap, SnapshotIdentifier());
    buffers.emplace_back(fbb.GetBufferPointer(), fbb.GetBufferPointer() + fbb.GetSize());
  }
  return assembleFixture(buffers);
}

}  // namespace df3d::mirror
