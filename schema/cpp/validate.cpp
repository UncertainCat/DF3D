#include "validate.h"

#include <string_view>
#include <unordered_set>
#include <set>
#include <tuple>

#include "appearance_util.h"
#include "command_util.h"
#include "entity_util.h"
#include "glyph_util.h"
#include "terrain_util.h"

namespace df3d::mirror {

namespace {
std::string posToString(const TilePos& p) {
  return "(" + std::to_string(p.x()) + "," + std::to_string(p.y()) + "," +
         std::to_string(p.z()) + ")";
}

std::string blockToString(const MapBlock& b) {
  return "(" + std::to_string(b.bx()) + "," + std::to_string(b.by()) + "," +
         std::to_string(b.bz()) + ")";
}

uint64_t blockKey(const MapBlock& b) {
  // Coordinates are validated non-negative and small before keying.
  return (static_cast<uint64_t>(b.bx()) << 42) | (static_cast<uint64_t>(b.by()) << 21) |
         static_cast<uint64_t>(b.bz());
}

std::optional<std::string> validateTile(const TileState& t, size_t index,
                                        uint32_t materialCount) {
  const std::string tag = "tile " + std::to_string(index) + ": ";
  const RawTileValues raw{static_cast<uint8_t>(t.shape()), static_cast<uint8_t>(t.material_kind()),
                          t.liquid_level(), static_cast<uint8_t>(t.liquid_kind()),
                          static_cast<uint8_t>(t.flags()), static_cast<uint8_t>(t.designation())};
  // Range checks are shared with the grid path (terrain_grid_sync.cpp); only
  // the material index depends on this snapshot's table.
  switch (checkTileValues(raw)) {
    case TileFault::None: break;
    case TileFault::Designation: return tag + "invalid designation kind";
    case TileFault::Shape: return tag + "invalid shape value " + std::to_string(raw.shape);
    case TileFault::MaterialKind:
      return tag + "invalid material_kind value " + std::to_string(raw.materialKind);
    case TileFault::LiquidKind:
      return tag + "invalid liquid_kind value " + std::to_string(raw.liquidKind);
    case TileFault::Flags: return tag + "unknown flag bits in " + std::to_string(raw.flags);
    case TileFault::LiquidLevel:
      return tag + "liquid_level " + std::to_string(raw.liquidLevel) + " exceeds 7";
    case TileFault::LiquidConsistency:
      return tag + "liquid_level " + std::to_string(raw.liquidLevel) +
             " inconsistent with liquid_kind " + std::to_string(raw.liquidKind);
  }
  if (t.material() != kNoMaterial && t.material() >= materialCount) {
    return tag + "material index " + std::to_string(t.material()) +
           " out of range (materials.size() = " + std::to_string(materialCount) + ")";
  }
  return std::nullopt;
}

std::optional<std::string> validateTerrain(const Snapshot& snap, const TilePos& dims,
                                           uint32_t materialCount) {
  const std::string tag = "snapshot tick " + std::to_string(snap.tick()) + ": ";
  const TerrainScope scope = snap.terrain_scope();
  if (scope < TerrainScope::MIN || scope > TerrainScope::MAX) {
    return tag + "invalid terrain_scope value " +
           std::to_string(static_cast<uint8_t>(scope));
  }
  const auto* blocks = snap.blocks();
  const size_t nBlocks = blocks ? blocks->size() : 0;
  if (scope == TerrainScope::None) {
    if (nBlocks != 0) return tag + "terrain_scope None but " + std::to_string(nBlocks) + " blocks present";
    return std::nullopt;
  }

  const int32_t bxCount = blocksAlong(dims.x());
  const int32_t byCount = blocksAlong(dims.y());
  const int32_t bzCount = dims.z();
  std::unordered_set<uint64_t> seen;
  for (size_t i = 0; i < nBlocks; ++i) {
    const MapBlock* b = blocks->Get(static_cast<flatbuffers::uoffset_t>(i));
    const std::string btag = tag + "block " + blockToString(*b) + ": ";
    if (b->bx() < 0 || b->by() < 0 || b->bz() < 0 || b->bx() >= bxCount ||
        b->by() >= byCount || b->bz() >= bzCount) {
      return btag + "outside block grid " + std::to_string(bxCount) + "x" +
             std::to_string(byCount) + "x" + std::to_string(bzCount);
    }
    if (!seen.insert(blockKey(*b)).second) return btag + "duplicate block coordinates";
    const auto* tiles = b->tiles();
    const size_t nTiles = tiles ? tiles->size() : 0;
    if (nTiles != kTilesPerBlock) {
      return btag + "has " + std::to_string(nTiles) + " tiles, expected 256";
    }
    if (const auto* details = b->designation_details()) {
      std::unordered_set<uint16_t> detailTiles;
      for (const auto* d : *details) {
        if (d->tile_index() >= kTilesPerBlock) return btag + "designation detail tile out of range";
        if (d->priority() > 7) return btag + "designation priority exceeds 7";
        if (!detailTiles.insert(d->tile_index()).second) return btag + "duplicate designation detail tile";
      }
    }
    if (const auto* env=b->environment()) {
      std::unordered_set<uint16_t> indices;
      for(const auto* e:*env) {
        if(e->tile_index()>=kTilesPerBlock || e->flags()>7 || e->building_occupancy()>7)
          return btag+"invalid tile environment";
        if(!indices.insert(e->tile_index()).second) return btag+"duplicate tile environment";
      }
    }
    if (const auto* indicators=b->indicators()) {
      std::unordered_set<uint16_t> seenIndicators;
      for (const auto* d : *indicators) {
        if(d->tile_index()>=kTilesPerBlock || d->track()>15 || d->completed_track()>15 || d->traffic()>3 || d->warnings()>3) return btag+"invalid map indicator";
        if(!seenIndicators.insert(d->tile_index()).second) return btag+"duplicate map indicator tile";
      }
    }
    for(const auto* blocked:{b->track_clearance_blocked(),b->track_horizontal_blocked(),b->track_support(),b->track_open()}) if(blocked) {
      std::unordered_set<uint16_t> indices;
      for(uint16_t index:*blocked) {
        if(index>=kTilesPerBlock) return btag+"track blocker tile out of range";
        if(!indices.insert(index).second) return btag+"duplicate track blocker tile";
      }
    }
    for (size_t t = 0; t < kTilesPerBlock; ++t) {
      if (auto err = validateTile(*tiles->Get(static_cast<flatbuffers::uoffset_t>(t)), t,
                                  materialCount)) {
        return btag + *err;
      }
    }
  }
  if (scope == TerrainScope::Full) {
    const int64_t expected = blockCount(dims.x(), dims.y(), dims.z());
    if (static_cast<int64_t>(nBlocks) != expected) {
      return tag + "terrain_scope Full with " + std::to_string(nBlocks) +
             " blocks, map needs " + std::to_string(expected);
    }
  }
  return std::nullopt;
}
std::optional<std::string> validateLayer(const AppearanceLayer& l, size_t index,
                                         uint32_t pageCount, uint32_t paletteCount) {
  const std::string tag = "layer " + std::to_string(index) + ": ";
  if (l.page() >= pageCount) {
    return tag + "page index " + std::to_string(l.page()) +
           " out of range (tile_pages.size() = " + std::to_string(pageCount) + ")";
  }
  if (l.cells_x() < 1 || l.cells_x() > kMaxCellsX || l.cells_y() < 1 ||
      l.cells_y() > kMaxCellsY) {
    return tag + "cells " + std::to_string(l.cells_x()) + "x" + std::to_string(l.cells_y()) +
           " outside 1..3 x 1..2";
  }
  if (l.palette() == kNoPalette) {
    if (l.palette_row() != kNoPaletteRow || l.palette_key_row() != kNoPaletteRow) {
      return tag + "no palette but palette_row/palette_key_row set";
    }
  } else {
    if (l.palette() >= paletteCount) {
      return tag + "palette index " + std::to_string(l.palette()) +
             " out of range (palettes.size() = " + std::to_string(paletteCount) + ")";
    }
    if (l.palette_row() < 0 || l.palette_key_row() < 0) {
      return tag + "palette set but palette_row/palette_key_row negative";
    }
  }
  return std::nullopt;
}

// Appearance references (v3): scope validity, None carries no
// entries, every entry names a unit of this snapshot exactly once, Full
// covers every unit, layer references index the snapshot's tables,
// non-empty table strings, palette paths relative with forward slashes.
std::optional<std::string> validateAppearances(const Snapshot& snap,
                                               const std::unordered_set<uint64_t>& unitIds) {
  const std::string tag = "snapshot tick " + std::to_string(snap.tick()) + ": ";
  const AppearanceScope scope = snap.appearance_scope();
  if (scope < AppearanceScope::MIN || scope > AppearanceScope::MAX) {
    return tag + "invalid appearance_scope value " +
           std::to_string(static_cast<uint8_t>(scope));
  }
  const auto* apps = snap.appearances();
  const size_t nApps = apps ? apps->size() : 0;
  if (scope == AppearanceScope::None) {
    if (nApps != 0) {
      return tag + "appearance_scope None but " + std::to_string(nApps) +
             " appearances present";
    }
    return std::nullopt;
  }
  const auto* pages = snap.tile_pages();
  const uint32_t pageCount = pages ? pages->size() : 0;
  for (uint32_t i = 0; i < pageCount; ++i) {
    const auto* s = pages->Get(i);
    if (!s || s->size() == 0) return tag + "tile_pages[" + std::to_string(i) + "] is empty";
  }
  const auto* palettes = snap.palettes();
  const uint32_t paletteCount = palettes ? palettes->size() : 0;
  for (uint32_t i = 0; i < paletteCount; ++i) {
    const auto* s = palettes->Get(i);
    if (!s || s->size() == 0) return tag + "palettes[" + std::to_string(i) + "] is empty";
    const std::string_view v(s->c_str(), s->size());
    const bool backslash = v.find('\\') != std::string_view::npos;
    const bool absolute = v.front() == '/' || (v.size() >= 2 && v[1] == ':');
    if (backslash || absolute) {
      return tag + "palettes[" + std::to_string(i) +
             "] is not an install-relative path: " + std::string(v);
    }
  }
  std::unordered_set<uint64_t> seen;
  for (size_t i = 0; i < nApps; ++i) {
    const UnitAppearance* a = apps->Get(static_cast<flatbuffers::uoffset_t>(i));
    const std::string atag = tag + "appearance of unit " + std::to_string(a->unit()) + ": ";
    if (!unitIds.count(a->unit())) return atag + "unit not in this snapshot";
    if (!seen.insert(a->unit()).second) return atag + "duplicate appearance";
    if (const auto* layers = a->layers()) {
      for (size_t k = 0; k < layers->size(); ++k) {
        if (auto err = validateLayer(*layers->Get(static_cast<flatbuffers::uoffset_t>(k)), k,
                                     pageCount, paletteCount)) {
          return atag + *err;
        }
      }
    }
  }
  if (scope == AppearanceScope::Full && seen.size() != unitIds.size()) {
    return tag + "appearance_scope Full with " + std::to_string(seen.size()) +
           " appearances for " + std::to_string(unitIds.size()) + " units";
  }
  return std::nullopt;
}

// --- buildings and map items (v4) ---

std::optional<std::string> checkScope(ChangeScope scope, const char* name, size_t present,
                                      size_t removed, const std::string& tag) {
  if (scope < ChangeScope::MIN || scope > ChangeScope::MAX) {
    return tag + "invalid " + name + " value " + std::to_string(static_cast<uint8_t>(scope));
  }
  if (scope == ChangeScope::None && (present != 0 || removed != 0)) {
    return tag + std::string(name) + " None but " + std::to_string(present) + " entries and " +
           std::to_string(removed) + " removed ids present";
  }
  return std::nullopt;
}

// Removed ids must be unique and must not name an entity also present.
std::optional<std::string> checkRemoved(const flatbuffers::Vector<uint32_t>* removed,
                                        const std::unordered_set<uint32_t>& present,
                                        const char* what, const std::string& tag) {
  if (!removed) return std::nullopt;
  std::unordered_set<uint32_t> seen;
  for (uint32_t id : *removed) {
    if (present.count(id)) {
      return tag + "removed " + what + " " + std::to_string(id) + " is also present";
    }
    if (!seen.insert(id).second) {
      return tag + "removed " + what + " " + std::to_string(id) + " listed twice";
    }
  }
  return std::nullopt;
}

std::optional<std::string> validateBuilding(const Building& b, const TilePos& dims,
                                            uint32_t materialCount) {
  if (b.kind() < BuildingKind::MIN || b.kind() > BuildingKind::MAX) {
    return "invalid kind value " + std::to_string(static_cast<uint8_t>(b.kind()));
  }
  if (b.stage() < BuildingStage::MIN || b.stage() > BuildingStage::MAX) {
    return "invalid stage value " + std::to_string(static_cast<uint8_t>(b.stage()));
  }
  if ((static_cast<uint8_t>(b.flags()) & ~static_cast<uint8_t>(BuildingFlags::ANY)) != 0) {
    return "unknown flag bits in " + std::to_string(static_cast<uint8_t>(b.flags()));
  }
  if (b.x1() > b.x2() || b.y1() > b.y2()) {
    return "rectangle (" + std::to_string(b.x1()) + "," + std::to_string(b.y1()) + ")-(" +
           std::to_string(b.x2()) + "," + std::to_string(b.y2()) + ") is inverted";
  }
  if (b.x1() < 0 || b.y1() < 0 || b.z() < 0 || b.x2() >= dims.x() || b.y2() >= dims.y() ||
      b.z() >= dims.z()) {
    return "rectangle (" + std::to_string(b.x1()) + "," + std::to_string(b.y1()) + ")-(" +
           std::to_string(b.x2()) + "," + std::to_string(b.y2()) + ") z " +
           std::to_string(b.z()) + " outside map " + posToString(dims);
  }
  if (b.center_x() < b.x1() || b.center_x() > b.x2() || b.center_y() < b.y1() ||
      b.center_y() > b.y2()) {
    return "center (" + std::to_string(b.center_x()) + "," + std::to_string(b.center_y()) +
           ") outside the rectangle";
  }
  if (const auto* ext = b.extents(); ext && ext->size() != 0) {
    const int64_t area = rectArea(b.x1(), b.y1(), b.x2(), b.y2());
    if (static_cast<int64_t>(ext->size()) != area) {
      return "extents has " + std::to_string(ext->size()) + " bytes, rectangle area is " +
             std::to_string(area);
    }
    for (uint32_t i = 0; i < ext->size(); ++i) {
      if (ext->Get(i) > 1) {
        return "extents[" + std::to_string(i) + "] = " + std::to_string(ext->Get(i)) +
               ", expected 0 or 1";
      }
    }
  }
  if (b.material() != kNoMaterial && b.material() >= materialCount) {
    return "material index " + std::to_string(b.material()) +
           " out of range (materials.size() = " + std::to_string(materialCount) + ")";
  }
  return std::nullopt;
}

std::optional<std::string> validateBuildings(const Snapshot& snap, const TilePos& dims,
                                             uint32_t materialCount) {
  const std::string tag = "snapshot tick " + std::to_string(snap.tick()) + ": ";
  const auto* list = snap.buildings();
  const auto* removed = snap.removed_buildings();
  if (auto err = checkScope(snap.building_scope(), "building_scope", list ? list->size() : 0,
                            removed ? removed->size() : 0, tag)) {
    return err;
  }
  std::unordered_set<uint32_t> seen;
  if (list) {
    for (const Building* b : *list) {
      const std::string btag = tag + "building " + std::to_string(b->id()) + ": ";
      if (!seen.insert(b->id()).second) return btag + "duplicate id";
      if (auto err = validateBuilding(*b, dims, materialCount)) return btag + *err;
    }
  }
  return checkRemoved(removed, seen, "building", tag);
}

std::optional<std::string> validateItem(const MapItem& it, const TilePos& dims,
                                        uint32_t materialCount) {
  if (it.kind() < ItemKind::MIN || it.kind() > ItemKind::MAX) {
    return "invalid kind value " + std::to_string(static_cast<uint8_t>(it.kind()));
  }
  if ((static_cast<uint8_t>(it.flags()) & ~static_cast<uint8_t>(ItemFlags::ANY)) != 0) {
    return "unknown flag bits in " + std::to_string(static_cast<uint8_t>(it.flags()));
  }
  const uint16_t cf = static_cast<uint16_t>(it.corpse_flags());
  if ((cf & ~static_cast<uint16_t>(CorpseFlags::ANY)) != 0) {
    return "unknown corpse flag bits in " + std::to_string(cf);
  }
  if (cf != 0 && it.kind() != ItemKind::Corpse && it.kind() != ItemKind::CorpsePiece) {
    return "corpse_flags " + std::to_string(cf) + " on a non-corpse item";
  }
  const TilePos* p = it.pos();
  if (!p) return "missing pos";
  if (p->x() < 0 || p->y() < 0 || p->z() < 0 || p->x() >= dims.x() || p->y() >= dims.y() ||
      p->z() >= dims.z()) {
    return "pos " + posToString(*p) + " outside map " + posToString(dims);
  }
  if (it.stack() < kMinStack) return "stack " + std::to_string(it.stack()) + " below 1";
  if (it.material() != kNoMaterial && it.material() >= materialCount) {
    return "material index " + std::to_string(it.material()) +
           " out of range (materials.size() = " + std::to_string(materialCount) + ")";
  }
  return std::nullopt;
}

std::optional<std::string> validateItems(const Snapshot& snap, const TilePos& dims,
                                         uint32_t materialCount) {
  const std::string tag = "snapshot tick " + std::to_string(snap.tick()) + ": ";
  const auto* list = snap.items();
  const auto* removed = snap.removed_items();
  if (auto err = checkScope(snap.item_scope(), "item_scope", list ? list->size() : 0,
                            removed ? removed->size() : 0, tag)) {
    return err;
  }
  std::unordered_set<uint32_t> seen;
  if (list) {
    for (const MapItem* it : *list) {
      const std::string itag = tag + "item " + std::to_string(it->id()) + ": ";
      if (!seen.insert(it->id()).second) return itag + "duplicate id";
      if (auto err = validateItem(*it, dims, materialCount)) return itag + *err;
    }
  }
  return checkRemoved(removed, seen, "item", tag);
}

// --- corpse appearance references and classic glyphs (v5) ---

// Item appearances: scope validity, None carries no entries, every entry
// names an item of this snapshot exactly once, Full covers every Corpse /
// CorpsePiece item of the snapshot, layers index the snapshot's tables.
std::optional<std::string> validateItemAppearances(const Snapshot& snap) {
  const std::string tag = "snapshot tick " + std::to_string(snap.tick()) + ": ";
  const AppearanceScope scope = snap.item_appearance_scope();
  if (scope < AppearanceScope::MIN || scope > AppearanceScope::MAX) {
    return tag + "invalid item_appearance_scope value " +
           std::to_string(static_cast<uint8_t>(scope));
  }
  const auto* apps = snap.item_appearances();
  const size_t nApps = apps ? apps->size() : 0;
  if (scope == AppearanceScope::None) {
    if (nApps != 0) {
      return tag + "item_appearance_scope None but " + std::to_string(nApps) +
             " item appearances present";
    }
    return std::nullopt;
  }
  const auto* pages = snap.tile_pages();
  const uint32_t pageCount = pages ? pages->size() : 0;
  const auto* palettes = snap.palettes();
  const uint32_t paletteCount = palettes ? palettes->size() : 0;
  std::unordered_set<uint32_t> itemIds, corpseIds;
  if (const auto* list = snap.items()) {
    for (const MapItem* it : *list) {
      itemIds.insert(it->id());
      if (it->kind() == ItemKind::Corpse || it->kind() == ItemKind::CorpsePiece) {
        corpseIds.insert(it->id());
      }
    }
  }
  std::unordered_set<uint32_t> seen;
  for (size_t i = 0; i < nApps; ++i) {
    const ItemAppearance* a = apps->Get(static_cast<flatbuffers::uoffset_t>(i));
    const std::string atag = tag + "appearance of item " + std::to_string(a->item()) + ": ";
    if (!itemIds.count(a->item())) return atag + "item not in this snapshot";
    if (!seen.insert(a->item()).second) return atag + "duplicate appearance";
    if (const auto* layers = a->layers()) {
      for (size_t k = 0; k < layers->size(); ++k) {
        if (auto err = validateLayer(*layers->Get(static_cast<flatbuffers::uoffset_t>(k)), k,
                                     pageCount, paletteCount)) {
          return atag + *err;
        }
      }
    }
  }
  if (scope == AppearanceScope::Full) {
    for (uint32_t id : corpseIds) {
      if (!seen.count(id)) {
        return tag + "item_appearance_scope Full but corpse item " + std::to_string(id) +
               " has no appearance";
      }
    }
  }
  return std::nullopt;
}

std::optional<std::string> validateGlyph(const Glyph* g, const char* what) {
  if (!g) return std::string("missing ") + what;
  if (g->fg() > kMaxGlyphColor || g->bg() > kMaxGlyphColor || g->bright() > 1) {
    return std::string(what) + " colour (" + std::to_string(g->fg()) + "," +
           std::to_string(g->bg()) + "," + std::to_string(g->bright()) +
           ") outside fg/bg 0..7, bright 0..1";
  }
  return std::nullopt;
}

// Glyph tables: scope validity, None carries no entries, non-empty unique
// keys, colour ranges, itemdef kinds valid.
std::optional<std::string> validateGlyphs(const Snapshot& snap) {
  const std::string tag = "snapshot tick " + std::to_string(snap.tick()) + ": ";
  const ChangeScope scope = snap.glyph_scope();
  if (scope < ChangeScope::MIN || scope > ChangeScope::MAX) {
    return tag + "invalid glyph_scope value " + std::to_string(static_cast<uint8_t>(scope));
  }
  const auto* creatures = snap.creature_glyphs();
  const auto* materials = snap.material_glyphs();
  const auto* itemdefs = snap.itemdef_glyphs();
  const size_t n = (creatures ? creatures->size() : 0) + (materials ? materials->size() : 0) +
                   (itemdefs ? itemdefs->size() : 0);
  if (scope == ChangeScope::None) {
    if (n != 0) return tag + "glyph_scope None but " + std::to_string(n) + " glyph entries present";
    return std::nullopt;
  }
  if (creatures) {
    std::unordered_set<std::string_view> seen;
    for (const CreatureGlyph* g : *creatures) {
      if (!g->species() || g->species()->size() == 0) return tag + "creature glyph with empty species";
      const std::string_view key(g->species()->c_str(), g->species()->size());
      const std::string gtag = tag + "creature glyph " + std::string(key) + ": ";
      if (!seen.insert(key).second) return gtag + "duplicate species";
      if (auto err = validateGlyph(g->glyph(), "glyph")) return gtag + *err;
    }
  }
  if (materials) {
    std::unordered_set<std::string_view> seen;
    for (const MaterialGlyph* g : *materials) {
      if (!g->material() || g->material()->size() == 0) return tag + "material glyph with empty material";
      const std::string_view key(g->material()->c_str(), g->material()->size());
      const std::string gtag = tag + "material glyph " + std::string(key) + ": ";
      if (!seen.insert(key).second) return gtag + "duplicate material";
      if (g->basic_fg() > kMaxGlyphColor || g->basic_bright() > 1) {
        return gtag + "basic colour (" + std::to_string(g->basic_fg()) + "," +
               std::to_string(g->basic_bright()) + ") outside fg 0..7, bright 0..1";
      }
      if (auto err = validateGlyph(g->build(), "build")) return gtag + *err;
      if (auto err = validateGlyph(g->tile_color(), "tile_color")) return gtag + *err;
    }
  }
  if (itemdefs) {
    std::unordered_set<std::string> seen;
    for (const ItemDefGlyph* g : *itemdefs) {
      if (g->kind() < ItemKind::MIN || g->kind() > ItemKind::MAX) {
        return tag + "itemdef glyph with invalid kind value " +
               std::to_string(static_cast<uint8_t>(g->kind()));
      }
      if (!g->subtype_raw() || g->subtype_raw()->size() == 0) {
        return tag + "itemdef glyph with empty subtype_raw";
      }
      const std::string key = std::to_string(static_cast<uint8_t>(g->kind())) + ":" +
                              std::string(g->subtype_raw()->c_str(), g->subtype_raw()->size());
      if (!seen.insert(key).second) {
        return tag + "itemdef glyph " + std::string(g->subtype_raw()->c_str()) + ": duplicate";
      }
    }
  }
  return std::nullopt;
}

// Command results (v6): status validity, unique seq per snapshot.
std::optional<std::string> validateCommandResults(const Snapshot& snap) {
  const auto* results = snap.command_results();
  if (!results) return std::nullopt;
  const std::string tag = "snapshot tick " + std::to_string(snap.tick()) + ": ";
  std::unordered_set<uint64_t> seen;
  for (const CommandResult* r : *results) {
    const std::string rtag = tag + "command result seq " + std::to_string(r->seq()) + ": ";
    if (r->status() < CommandStatus::MIN || r->status() > CommandStatus::MAX) {
      return rtag + "invalid status value " + std::to_string(static_cast<uint8_t>(r->status()));
    }
    if (!seen.insert(r->seq()).second) return rtag + "duplicate seq";
  }
  return std::nullopt;
}

std::optional<std::string> validateRect(const TileRect* rect, const TilePos* dims) {
  if (!rect) return "missing rect";
  if (rect->x1() > rect->x2() || rect->y1() > rect->y2()) {
    return "rect (" + std::to_string(rect->x1()) + "," + std::to_string(rect->y1()) + ")-(" +
           std::to_string(rect->x2()) + "," + std::to_string(rect->y2()) + ") is inverted";
  }
  if (rect->x1() < 0 || rect->y1() < 0 || rect->z() < 0) {
    return "rect (" + std::to_string(rect->x1()) + "," + std::to_string(rect->y1()) + ") z " +
           std::to_string(rect->z()) + " has a negative coordinate";
  }
  if (dims && (rect->x2() >= dims->x() || rect->y2() >= dims->y() || rect->z() >= dims->z())) {
    return "rect (" + std::to_string(rect->x1()) + "," + std::to_string(rect->y1()) + ")-(" +
           std::to_string(rect->x2()) + "," + std::to_string(rect->y2()) + ") z " +
           std::to_string(rect->z()) + " outside map " + posToString(*dims);
  }
  return std::nullopt;
}

std::optional<std::string> validateMaxZ(const TileRect* rect, int32_t maxZ, const TilePos* dims) {
  const uint64_t width=uint64_t(rect->x2())-rect->x1()+1;
  const uint64_t height=uint64_t(rect->y2())-rect->y1()+1;
  const uint64_t depth=maxZ==-1?1:uint64_t(int64_t(maxZ)-rect->z()+1);
  if(width>kMaxDesignationTiles || height>kMaxDesignationTiles/width || depth>kMaxDesignationTiles/(width*height))
    return "designation exceeds 65536 tiles; select a smaller area";
  if(maxZ==-1) return std::nullopt;
  if(maxZ<rect->z() || (dims && maxZ>=dims->z())) return "invalid designation layer span";
  return std::nullopt;
}

std::optional<std::string> validateOptionalBool(OptionalBool v, const char* name) {
  if (v < OptionalBool::MIN || v > OptionalBool::MAX) {
    return std::string("invalid ") + name + " value " + std::to_string(static_cast<uint8_t>(v));
  }
  return std::nullopt;
}
}  // namespace

std::optional<std::string> validateCommand(const Command& cmd, const TilePos* dims) {
  const std::string tag = "command seq " + std::to_string(cmd.seq()) + ": ";
  if (!cmd.payload()) return tag + "missing command payload";
  switch (cmd.payload_type()) {
    case CommandPayload::SetPause:
      return std::nullopt;
    case CommandPayload::DesignateDig: {
      const DesignateDig* d = cmd.payload_as_DesignateDig();
      if (auto err = validateRect(d->rect(), dims)) return tag + *err;
      if (d->kind() < DigKind::MIN || d->kind() > DigKind::MAX) {
        return tag + "invalid dig kind value " + std::to_string(static_cast<uint8_t>(d->kind()));
      }
      if(d->kind()==DigKind::StairsSpan && (d->max_z()<=d->rect()->z() || (dims && d->max_z()>=dims->z()))) return tag + "invalid stair span";
      if(auto err=validateMaxZ(d->rect(),d->max_z(),dims)) return tag + *err;
      if(d->mining_mode()>3) return tag + "invalid mining mode";
      if(d->mining_mode()!=0 && d->kind()!=DigKind::Dig) return tag + "mining filter requires Mine";
      if (d->priority() < kMinDigPriority || d->priority() > kMaxDigPriority) {
        return tag + "priority " + std::to_string(d->priority()) + " outside 1..7";
      }
      return std::nullopt;
    }
    case CommandPayload::DesignateSmooth: {
      const DesignateSmooth* d = cmd.payload_as_DesignateSmooth();
      if (auto err = validateRect(d->rect(), dims)) return tag + *err;
      if(auto err=validateMaxZ(d->rect(),d->max_z(),dims)) return tag + *err;
      if(d->track_end_z() < -1 || (dims && d->track_end_z() >= dims->z())) return tag + "invalid track endpoint layer";
      if(d->kind()!=SmoothKind::Track && d->track_end_z()!=-1) return tag + "track endpoint on non-track operation";
      if(d->kind()==SmoothKind::Track && d->max_z()!=-1 && d->max_z()!=d->rect()->z()) return tag + "tracks require one layer";
      if(d->priority()<1 || d->priority()>7) return tag + "priority outside 1..7";
      if (d->kind() < SmoothKind::MIN || d->kind() > SmoothKind::MAX) {
        return tag + "invalid smooth kind value " +
               std::to_string(static_cast<uint8_t>(d->kind()));
      }
      return std::nullopt;
    }
    case CommandPayload::DesignateChop:
      if(cmd.payload_as_DesignateChop()->priority()<1 || cmd.payload_as_DesignateChop()->priority()>7) return tag + "priority outside 1..7";
      if (auto err = validateRect(cmd.payload_as_DesignateChop()->rect(), dims)) return tag + *err;
      if(auto err=validateMaxZ(cmd.payload_as_DesignateChop()->rect(),cmd.payload_as_DesignateChop()->max_z(),dims)) return tag + *err;
      return std::nullopt;
    case CommandPayload::DesignateGather:
      if(cmd.payload_as_DesignateGather()->priority()<1 || cmd.payload_as_DesignateGather()->priority()>7) return tag + "priority outside 1..7";
      if (auto err = validateRect(cmd.payload_as_DesignateGather()->rect(), dims)) return tag + *err;
      if(auto err=validateMaxZ(cmd.payload_as_DesignateGather()->rect(),cmd.payload_as_DesignateGather()->max_z(),dims)) return tag + *err;
      return std::nullopt;
    case CommandPayload::SetItemFlags: {
      const SetItemFlags* f = cmd.payload_as_SetItemFlags();
      if (f->item() == 0) return tag + "item id 0";
      if (auto err = validateOptionalBool(f->forbidden(), "forbidden")) return tag + *err;
      if (auto err = validateOptionalBool(f->dump(), "dump")) return tag + *err;
      if (auto err = validateOptionalBool(f->melt(), "melt")) return tag + *err;
      return std::nullopt;
    }
    case CommandPayload::SetBuildingFlags: {
      const SetBuildingFlags* f = cmd.payload_as_SetBuildingFlags();
      if (f->building() == 0) return tag + "building id 0";
      if (auto err = validateOptionalBool(f->forbidden(), "forbidden")) return tag + *err;
      return std::nullopt;
    }
    default:
      return tag + "unknown payload type " + std::to_string(static_cast<int>(cmd.payload_type()));
  }
}

std::optional<std::string> validateSnapshot(const Snapshot& snap) {
  if (snap.schema_version() != static_cast<uint32_t>(SchemaVersion::Current)) {
    return "schema version mismatch: snapshot has " + std::to_string(snap.schema_version()) +
           ", consumer expects " +
           std::to_string(static_cast<uint32_t>(SchemaVersion::Current));
  }
  const TilePos* dims = snap.map_size();
  if (!dims) return "snapshot tick " + std::to_string(snap.tick()) + ": missing map_size";
  if (dims->x() <= 0 || dims->y() <= 0 || dims->z() <= 0) {
    return "snapshot tick " + std::to_string(snap.tick()) +
           ": non-positive map_size " + posToString(*dims);
  }

  std::unordered_set<uint64_t> seen;
  if (const auto* units = snap.units()) {
    for (const UnitState* u : *units) {
      const std::string tag = "snapshot tick " + std::to_string(snap.tick()) + ", unit " +
                              std::to_string(u->id()) + ": ";
      if (!seen.insert(u->id()).second) return tag + "duplicate id";
      const TilePos* p = u->pos();
      if (!p) return tag + "missing pos";
      if (p->x() < 0 || p->y() < 0 || p->z() < 0 || p->x() >= dims->x() ||
          p->y() >= dims->y() || p->z() >= dims->z()) {
        return tag + "pos " + posToString(*p) + " outside map " + posToString(*dims);
      }
      if (u->body_volume_cm3() > 2147483647u) return tag + "body volume exceeds source domain";
      if (!u->species() || u->species()->size() == 0) return tag + "missing species";
      if (u->job() < JobKind::MIN || u->job() > JobKind::MAX ||
          EnumNameJobKind(u->job())[0] == '\0') {
        return tag + "invalid job value " +
               std::to_string(static_cast<uint16_t>(u->job()));
      }
    }
  }
  if (const auto* units = snap.units()) {
    for (const auto* u : *units) if (const auto* a = u->attack()) {
      if (a->action_id() < 0 || a->target_unit_id() < 0)
        return "unit attack has invalid action or target id";
      if (static_cast<uint64_t>(a->target_unit_id()) == u->id() ||
          seen.count(static_cast<uint64_t>(a->target_unit_id())) == 0)
        return "unit attack target must be another mirrored unit";
      // Signed counters are intentionally passed through: native sentinel
      // values are not interpreted as animation durations or hit results.
    }
  }
  const auto validRaw=[](const flatbuffers::String* s, bool required=false) {
    if(!s || s->size()==0) return !required;
    if(s->size()>256) return false;
    for(const auto c:*s) if(c<' ' || c=='\x7f') return false;
    return true;
  };
  const auto validEventItem=[&](const EventItem* item) {
    return !item || (item->id()>=0 && validRaw(item->type(),true) &&
      validRaw(item->subtype_raw()) && validRaw(item->material()) && validRaw(item->melee_skill()) &&
      !(item->material_flags() & ~uint32_t(7)) && (item->material_flags_known() || !item->material_flags()));
  };
  if(const auto* events=snap.projectile_combat_events()) {
    if(events->size()>512) return "too many projectile combat events";
    uint64_t previous=0, previousTick=0;
    for(const auto* e:*events) {
      if(!e || !e->id() || e->id()<=previous || e->tick()<previousTick || e->tick()>snap.tick() || snap.tick()-e->tick()>600 || !e->pos() ||
         e->projectile_id()<0 || e->source_unit_id()<-1 || e->target_unit_id()<-1 ||
         uint8_t(e->kind())>uint8_t(ProjectileCombatKind::GroundImpact) ||
         uint8_t(e->launcher())>uint8_t(WeaponLauncher::Ballista) ||
         (e->context_complete() && e->kind()==ProjectileCombatKind::Unknown) ||
         !validEventItem(e->ammunition()) || !validEventItem(e->weapon()))
        return "invalid projectile combat event";
      const auto* p=e->pos();
      if(p->x()<0 || p->y()<0 || p->z()<0 || p->x()>=dims->x() || p->y()>=dims->y() || p->z()>=dims->z())
        return "projectile combat position outside map";
      previous=e->id();previousTick=e->tick();
    }
  }
  if(const auto* events=snap.resolved_attacks()) {
    if(events->size()>512) return "too many resolved attacks";
    uint64_t id=0,tick=0;
    for(const auto* e:*events) {
      if(!e || e->id()<=id || e->tick()<tick || e->tick()>snap.tick() || snap.tick()-e->tick()>600 ||
         e->attacker_id()<0 || e->defender_id()<0 || e->action_id()<0 || !validEventItem(e->weapon()))
        return "invalid resolved attack";
      if(uint8_t(e->outcome())>uint8_t(AttackOutcome::Wrestle) ||
         (e->outcome_complete() && e->outcome()==AttackOutcome::Unknown)) return "invalid attack outcome";
      id=e->id();tick=e->tick();
      const auto* p=e->pos();
      if(!p || p->x()<0 || p->y()<0 || p->z()<0 || p->x()>=dims->x() || p->y()>=dims->y() || p->z()>=dims->z())
        return "attack position outside map";
      if(const auto* wounds=e->wounds()) {
        if(wounds->size()>128) return "too many attack wounds";
        int32_t previous=-1;
        size_t partCount=0;
        for(const auto* w:*wounds) {
          if(!w || w->wound_id()<=previous || w->victim_id()!=e->defender_id()) return "invalid attack wound";
          previous=w->wound_id();
          if(const auto* parts=w->parts()) {
            partCount+=parts->size();
            if(partCount>128) return "too many attack wound parts";
            for(const auto* p:*parts)
              if(!p || p->body_part_id()<-1 || p->layer_id()<-1 || !validRaw(p->body_part_token()) ||
                 !validRaw(p->body_part_category()) || (p->damage_flags() & ~uint32_t(1023)) ||
                 (p->anatomy_flags() & ~uint32_t(31))) return "invalid attack wound part";
          }
        }
      }
      if(const auto* contacts=e->contacts()) {
        if(contacts->size()>100) return "too many attack contacts";
        for(const auto* c:*contacts)
          if(!c || !c->first() || !c->second() || !validEventItem(c->first()) || !validEventItem(c->second()) ||
             c->first()->id()==c->second()->id()) return "invalid attack contact";
      }
    }
  }
  if(const auto* events=snap.item_contacts()) {
    if(events->size()>512) return "too many item contact events";
    uint64_t id=0,tick=0;
    for(const auto* e:*events) {
      if(!e || e->id()<=id || e->tick()<tick || e->tick()>snap.tick() || snap.tick()-e->tick()>600 ||
         !e->first() || !e->second() || !validEventItem(e->first()) || !validEventItem(e->second()) ||
         e->first()->id()==e->second()->id()) return "invalid item contact event";
      id=e->id();tick=e->tick();
      const auto* p=e->pos();
      if(!p || p->x()<0 || p->y()<0 || p->z()<0 || p->x()>=dims->x() || p->y()>=dims->y() || p->z()>=dims->z())
        return "item contact position outside map";
    }
  }
  if(const auto* events=snap.report_events()) {
    if(events->size()>512) return "too many report events";
    uint64_t id=0,tick=0;
    for(const auto* e:*events) {
      if(!e || e->id()<=id || e->tick()<tick || e->tick()>snap.tick() || snap.tick()-e->tick()>600 ||
         e->report_id()<0 || e->speaker_id()<-1 || !validRaw(e->type(),true)) return "invalid report event";
      for(const auto c:*e->type())
        if(!((c>='A' && c<='Z') || (c>='0' && c<='9') || c=='_')) return "invalid report event type token";
      id=e->id();tick=e->tick();
      for(const auto* p:{e->pos(),e->pos2()})
        if(p && (p->x()<0 || p->y()<0 || p->z()<0 || p->x()>=dims->x() || p->y()>=dims->y() || p->z()>=dims->z()))
          return "report event position outside map";
    }
  }
  if (const auto* samples = snap.projectile_samples()) {
    if (samples->size()>512) return "too many projectile samples";
    uint64_t sequence=0, tick=0;
    for (const auto* p : *samples) {
      if (!p || p->sequence()<=sequence || p->tick()<tick || p->tick()>snap.tick() || snap.tick()-p->tick()>120 ||
          p->item_id()<0 || p->firer_id()<-1 || !p->pos() || !p->previous() || !p->origin() || !p->target())
        return "invalid projectile sample";
      sequence=p->sequence();tick=p->tick();
      if(!validEventItem(p->ammunition()) || !validEventItem(p->launcher()) ||
         (p->ammunition() && p->ammunition()->id()!=p->item_id())) return "invalid projectile item source";
      const auto* pos=p->pos();
      if (pos->x()<0 || pos->y()<0 || pos->z()<0 || pos->x()>=dims->x() || pos->y()>=dims->y() || pos->z()>=dims->z())
        return "projectile position outside map";
    }
  }
  if (const auto* events = snap.combat_events()) {
    if (events->size() > 256) return "too many combat events";
    uint64_t previous = 0;
    for (const auto* e : *events) {
      if (!e || e->id() <= previous || e->tick() > snap.tick() || snap.tick()-e->tick() > 600)
        return "invalid combat event identity or tick";
      previous = e->id();
      if(e->report_id()<-1 || e->source_action_id()<-1 || !validEventItem(e->weapon()) ||
         (e->weapon() && e->source_action_id()<0)) return "invalid combat event source context";
      if (e->victim_id() < 0 || e->attacker_id() < -1 || e->wound_id() < -1 ||
          (e->kind() != CombatEventKind::Wound && e->kind() != CombatEventKind::Death))
        return "invalid combat event kind or participants";
      if (e->kind() == CombatEventKind::Wound && (e->attacker_id() < 0 || e->wound_id() < 0))
        return "wound event requires attacker and wound";
      const auto* p = e->pos();
      if (!p || p->x()<0 || p->y()<0 || p->z()<0 || p->x()>=dims->x() || p->y()>=dims->y() || p->z()>=dims->z())
        return "combat event position outside map";
    }
  }
  if (auto err = validateAppearances(snap, seen)) return err;

  // The material table is shared by terrain, buildings and items and may
  // be present with any scope (v4); validate it once.
  const auto* materials = snap.materials();
  const uint32_t materialCount = materials ? materials->size() : 0;
  for (uint32_t i = 0; i < materialCount; ++i) {
    const auto* s = materials->Get(i);
    if (!s || s->size() == 0) {
      return "snapshot tick " + std::to_string(snap.tick()) + ": materials[" +
             std::to_string(i) + "] is empty";
    }
  }
  if (auto err = validateTerrain(snap, *dims, materialCount)) return err;
  if (snap.spatter_scope() < ChangeScope::MIN || snap.spatter_scope() > ChangeScope::MAX)
    return "invalid spatter_scope";
  if (const auto* blocks = snap.spatters()) {
    if (blocks->size() && snap.spatter_scope() == ChangeScope::None) return "spatters present with scope None";
    std::set<std::tuple<int32_t,int32_t,int32_t>> seen;
    for (const auto* b : *blocks) {
      if (b->bx()<0 || b->by()<0 || b->bz()<0 || b->bx()>=blocksAlong(dims->x()) ||
          b->by()>=blocksAlong(dims->y()) || b->bz()>=dims->z()) return "spatter block outside map";
      if (!seen.emplace(b->bx(),b->by(),b->bz()).second) return "duplicate spatter block";
      std::set<std::tuple<uint8_t,uint16_t,uint8_t>> entries;
      if (const auto* es = b->entries()) for (const auto* e : *es) {
        if (e->amount()==0) return "zero spatter amount";
        if (e->material()>=materialCount) return "spatter material outside table";
        if (e->state()<MatterState::MIN || e->state()>MatterState::MAX) return "invalid spatter matter state";
        if (b->bx()*16+e->tile()%16>=dims->x() || b->by()*16+e->tile()/16>=dims->y()) return "spatter on padding tile";
        if (!entries.emplace(e->tile(),e->material(),static_cast<uint8_t>(e->state())).second)
          return "duplicate spatter material/state on tile";
      }
    }
  }
  if (auto err = validateBuildings(snap, *dims, materialCount)) return err;
  if (auto err = validateItems(snap, *dims, materialCount)) return err;
  if (auto err = validateItemAppearances(snap)) return err;
  if (auto err = validateGlyphs(snap)) return err;
  return validateCommandResults(snap);
}

std::optional<std::string> EntityStreamState::check(const Snapshot& snap) {
  const std::string tag = "snapshot tick " + std::to_string(snap.tick()) + ": ";
  if (snap.building_scope() == ChangeScope::Full) seenFullBuildings_ = true;
  if (snap.building_scope() == ChangeScope::Delta && !seenFullBuildings_) {
    return tag + "building_scope Delta before any Full in the stream";
  }
  if (snap.item_scope() == ChangeScope::Full) seenFullItems_ = true;
  if (snap.item_scope() == ChangeScope::Delta && !seenFullItems_) {
    return tag + "item_scope Delta before any Full in the stream";
  }
  return std::nullopt;
}

std::optional<std::string> TerrainStreamState::check(const Snapshot& snap) {
  switch (snap.terrain_scope()) {
    case TerrainScope::Full:
      seenFull_ = true;
      return std::nullopt;
    case TerrainScope::Delta:
      if (!seenFull_) {
        return "snapshot tick " + std::to_string(snap.tick()) +
               ": terrain_scope Delta before any Full in the stream";
      }
      return std::nullopt;
    default:
      return std::nullopt;
  }
}

std::optional<std::string> validateStream(const FixtureStream& stream) {
  bool first = true;
  uint64_t prevTick = 0, prevMs = 0;
  int32_t mx = 0, my = 0, mz = 0;
  TerrainStreamState terrain;
  EntityStreamState entities;
  for (size_t i = 0; i < stream.snapshots.size(); ++i) {
    const Snapshot* s = stream.snapshots[i];
    if (auto err = validateSnapshot(*s)) {
      return "snapshot #" + std::to_string(i) + ": " + *err;
    }
    if (auto err = terrain.check(*s)) {
      return "snapshot #" + std::to_string(i) + ": " + *err;
    }
    if (auto err = entities.check(*s)) {
      return "snapshot #" + std::to_string(i) + ": " + *err;
    }
    if (!first) {
      // Paused semantic commands publish new state at the same simulation tick.
      // File order is publication order; simulation time must not go backwards.
      if (s->tick() < prevTick) {
        return "snapshot #" + std::to_string(i) + ": tick " + std::to_string(s->tick()) +
               " precedes previous tick " + std::to_string(prevTick);
      }
      if (s->emitted_at_ms() < prevMs) {
        return "snapshot #" + std::to_string(i) + ": emitted_at_ms went backwards";
      }
      const TilePos* d = s->map_size();
      if (d->x() != mx || d->y() != my || d->z() != mz) {
        return "snapshot #" + std::to_string(i) + ": map_size changed mid-stream";
      }
    } else {
      const TilePos* d = s->map_size();
      mx = d->x();
      my = d->y();
      mz = d->z();
      first = false;
    }
    prevTick = s->tick();
    prevMs = s->emitted_at_ms();
  }
  return std::nullopt;
}

}  // namespace df3d::mirror
