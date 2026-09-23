#include "inspect.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <map>
#include <vector>

namespace inspector {

namespace {
const char* presenceName(wm::Presence p) {
  switch (p) {
    case wm::Presence::NotYetSeen: return "not-yet-seen";
    case wm::Presence::Present: return "present";
    case wm::Presence::Departed: return "departed";
  }
  return "?";
}

char liquidGlyph(const wm::TileState& t) {
  if (t.liquidKind == wm::LiquidKind::Water) return t.liquidLevel >= 4 ? '~' : '-';
  if (t.liquidKind == wm::LiquidKind::Magma) return '&';
  return 0;
}

}  // namespace

char tileGlyph(const wm::TileState& t) {
  if (t.flags & wm::kTileHidden) return '?';
  if (char l = liquidGlyph(t)) return l;
  switch (t.shape) {
    case wm::TileShape::Empty: return ' ';
    case wm::TileShape::Wall:
      if (t.flags & wm::kTileDigDesignated) return 'd';
      if (t.flags & wm::kTileEngraveDesignated) return 'e';  // pending
      if (t.flags & wm::kTileSmoothDesignated) return 's';
      if (t.materialKind == wm::MaterialKind::Mineral || t.materialKind == wm::MaterialKind::Gem)
        return '%';
      return '#';
    case wm::TileShape::Floor:
      if (t.flags & wm::kTileEngraveDesignated) return 'e';
      if (t.flags & wm::kTileSmoothDesignated) return 's';
      if (t.flags & wm::kTileEngraved) return '+';
      if (t.flags & wm::kTileSmooth) return '_';
      if (t.materialKind == wm::MaterialKind::Grass) return ',';
      return '.';
    case wm::TileShape::Ramp: return '/';
    case wm::TileShape::RampTop: return '\'';
    case wm::TileShape::StairUp: return '<';
    case wm::TileShape::StairDown: return '>';
    case wm::TileShape::StairUpDown: return 'X';
    case wm::TileShape::Fortification: return '=';
    case wm::TileShape::Boulder: return 'O';
    case wm::TileShape::Pebbles: return ':';
    case wm::TileShape::TreeTrunk: return 'T';
    case wm::TileShape::TreeBranch: return 't';
    case wm::TileShape::Shrub: return '"';
    case wm::TileShape::Sapling: return 'i';
    case wm::TileShape::Unknown: return '?';
  }
  return '?';
}

const char* glyphLegend() {
  return "legend: ?=unknown/hidden ' '=open #=wall %=vein d=designated .=floor ,=grass "
         "_=smooth +=engraved /=ramp '=ramp-top <=up >=down X=up/down "
         "==fortification O=boulder :=pebbles T=trunk t=branch \"=shrub i=sapling "
         "~=water(4+) -=water(1-3) &=magma | buildings: W=workshop F=furnace D=depot "
         "p=stockpile z=zone b=bed o=door g=gate/hatch B=bridge w=well S=statue n=table "
         "h=chair c=coffin/slab k=storage C=cage/chain/trap A=trap I=support f=farm M=machine "
         "r=road G=grate/bars *=other x=unbuilt | items: l=log 0=boulder $=bar/block/gem "
         ")=weapon/armor e=food v=corpse ;=other | @=unit";
}

char buildingGlyph(const wm::Building& b) {
  using K = wm::BuildingKind;
  if (b.stage != wm::BuildingStage::Complete) return 'x';
  switch (b.kind) {
    case K::Workshop: return 'W';
    case K::Furnace: return 'F';
    case K::TradeDepot: return 'D';
    case K::Stockpile: return 'p';
    case K::Civzone: return 'z';
    case K::Bed: return 'b';
    case K::Door: return 'o';
    case K::Floodgate:
    case K::Hatch: return 'g';
    case K::Bridge: return 'B';
    case K::Well: return 'w';
    case K::Statue: return 'S';
    case K::Table: return 'n';
    case K::Chair: return 'h';
    case K::Coffin:
    case K::Slab: return 'c';
    case K::Cabinet:
    case K::Box:
    case K::Armorstand:
    case K::Weaponrack:
    case K::Bookcase:
    case K::DisplayFurniture: return 'k';
    case K::Cage:
    case K::Chain:
    case K::AnimalTrap: return 'C';
    case K::Trap: return 'A';
    case K::Support: return 'I';
    case K::FarmPlot: return 'f';
    case K::Windmill:
    case K::WaterWheel:
    case K::ScrewPump:
    case K::AxleHorizontal:
    case K::AxleVertical:
    case K::GearAssembly:
    case K::Rollers: return 'M';
    case K::RoadDirt:
    case K::RoadPaved: return 'r';
    case K::GrateWall:
    case K::GrateFloor:
    case K::BarsVertical:
    case K::BarsFloor: return 'G';
    default: return '*';
  }
}

char itemGlyph(const wm::MapItem& it) {
  using K = wm::ItemKind;
  switch (it.kind) {
    case K::Wood: return 'l';
    case K::Boulder:
    case K::Rock: return '0';
    case K::Bar:
    case K::Blocks:
    case K::Coin:
    case K::SmallGem:
    case K::Gem:
    case K::Rough: return '$';
    case K::Weapon:
    case K::Ammo:
    case K::Armor:
    case K::Shield:
    case K::Helm:
    case K::Gloves:
    case K::Shoes:
    case K::Pants: return ')';
    case K::Meat:
    case K::Fish:
    case K::FishRaw:
    case K::Plant:
    case K::PlantGrowth:
    case K::Seeds:
    case K::Drink:
    case K::Cheese:
    case K::Food:
    case K::Egg: return 'e';
    case K::Corpse:
    case K::CorpsePiece:
    case K::Remains: return 'v';
    default: return ';';
  }
}

namespace {

std::string buildingFlagsText(uint8_t flags) {
  std::string out;
  if (flags & wm::kBuildingForbidden) out += "Forbidden,";
  if (flags & wm::kBuildingRoomAssigned) out += "RoomAssigned,";
  if (!out.empty()) out.pop_back();
  return out.empty() ? "-" : out;
}

std::string itemFlagsText(uint8_t flags) {
  std::string out;
  if (flags & wm::kItemForbidden) out += "Forbidden,";
  if (flags & wm::kItemDump) out += "Dump,";
  if (flags & wm::kItemMelt) out += "Melt,";
  if (flags & wm::kItemOnFire) out += "OnFire,";
  if (flags & wm::kItemRotten) out += "Rotten,";
  if (flags & wm::kItemArtifact) out += "Artifact,";
  if (flags & wm::kItemWeb) out += "Web,";
  if (!out.empty()) out.pop_back();
  return out.empty() ? "-" : out;
}

std::string corpseFlagsText(uint16_t flags) {
  static const char* const names[] = {"Unbutchered", "Plant", "Silk", "Leather", "Bone",
                                      "Shell", "Wood", "Soap", "Tooth", "Horn", "Pearl",
                                      "Rottable", "Skull", "HairWool", "Yarn"};
  std::string out;
  for (size_t i = 0; i < 15; ++i)
    if (flags & (1u << i)) out += std::string(names[i]) + ",";
  if (!out.empty()) out.pop_back();
  return out;
}

std::string materialText(const wm::WorldModel& model, wm::MaterialId id) {
  if (id == wm::kNoMaterial) return "-";
  const std::string_view name = model.materialName(id);
  return name.empty() ? "?" : std::string(name);
}

}  // namespace

std::string buildingSummary(const wm::WorldModel& model) {
  char line[256];
  if (!model.buildingsKnown()) {
    std::snprintf(line, sizeof(line), "buildings: none (no Full snapshot yet; %zu known)\n",
                  model.buildingCount());
    return line;
  }
  std::snprintf(line, sizeof(line), "buildings: %zu known | version %llu\n",
                model.buildingCount(), static_cast<unsigned long long>(model.buildingsVersion()));
  std::string out = line;
  std::map<uint8_t, size_t> kinds;
  size_t stages[3] = {0, 0, 0};
  model.forEachBuilding([&](const wm::Building& b) {
    ++kinds[static_cast<uint8_t>(b.kind)];
    ++stages[static_cast<size_t>(b.stage) % 3];
  });
  if (!kinds.empty()) {
    out += "  kinds:";
    for (const auto& [k, n] : kinds) {
      std::snprintf(line, sizeof(line), " %s=%zu",
                    wm::buildingKindName(static_cast<wm::BuildingKind>(k)), n);
      out += line;
    }
    std::snprintf(line, sizeof(line), "\n  stages: Planned=%zu InProgress=%zu Complete=%zu\n",
                  stages[0], stages[1], stages[2]);
    out += line;
  }
  return out;
}

std::string itemSummary(const wm::WorldModel& model) {
  char line[256];
  if (!model.itemsKnown()) {
    std::snprintf(line, sizeof(line), "items: none (no Full snapshot yet; %zu known)\n",
                  model.itemCount());
    return line;
  }
  std::snprintf(line, sizeof(line), "items: %zu on map | version %llu\n", model.itemCount(),
                static_cast<unsigned long long>(model.itemsVersion()));
  std::string out = line;
  std::map<uint8_t, size_t> kinds;
  size_t webs = 0, corpses = 0, corpsesWithStack = 0, corpseLayers = 0;
  model.forEachItem([&](const wm::MapItem& it) {
    ++kinds[static_cast<uint8_t>(it.kind)];
    if (it.flags & wm::kItemWeb) ++webs;
    if (it.kind == wm::ItemKind::Corpse || it.kind == wm::ItemKind::CorpsePiece) {
      ++corpses;
      if (const wm::ItemAppearance* a = model.itemAppearance(it.id); a && !a->layers.empty()) {
        ++corpsesWithStack;
        corpseLayers += a->layers.size();
      }
    }
  });
  if (!kinds.empty()) {
    out += "  kinds:";
    for (const auto& [k, n] : kinds) {
      std::snprintf(line, sizeof(line), " %s=%zu", wm::itemKindName(static_cast<wm::ItemKind>(k)),
                    n);
      out += line;
    }
    out += '\n';
  }
  std::snprintf(line, sizeof(line),
                "  webs=%zu corpses=%zu with-appearance=%zu (%zu layers) | appearance version %llu\n",
                webs, corpses, corpsesWithStack, corpseLayers,
                static_cast<unsigned long long>(model.itemAppearanceVersion()));
  out += line;
  return out;
}

std::string glyphSummary(const wm::WorldModel& model) {
  char line[256];
  std::snprintf(line, sizeof(line), "glyphs: %s | species %zu, materials %zu, itemdefs %zu | version %llu\n",
                model.glyphsKnown() ? "known" : "no Full yet", model.creatureGlyphCount(),
                model.materialGlyphCount(), model.itemDefGlyphCount(),
                static_cast<unsigned long long>(model.glyphVersion()));
  return line;
}

std::string listBuildingsAt(const wm::WorldModel& model, int z) {
  std::string out;
  char line[512];
  for (const wm::Building* b : model.buildingsAt(z)) {
    std::string kind = wm::buildingKindName(b->kind);
    if (b->subtype != wm::kNoSubtype) kind += "/" + std::to_string(b->subtype);
    if (!b->custom.empty()) kind += "(" + b->custom + ")";
    std::snprintf(line, sizeof(line),
                  "  building %u %-14s (%d,%d)-(%d,%d) center (%d,%d)%s material=%s stage=%s "
                  "flags=%s v%llu\n",
                  b->id, kind.c_str(), b->x1, b->y1, b->x2, b->y2, b->centerX, b->centerY,
                  b->extents.empty() ? "" : " extents", materialText(model, b->material).c_str(),
                  wm::buildingStageName(b->stage), buildingFlagsText(b->flags).c_str(),
                  static_cast<unsigned long long>(b->version));
    out += line;
  }
  return out;
}

std::string listItemsAt(const wm::WorldModel& model, int z) {
  std::string out;
  char line[512];
  for (const wm::MapItem* it : model.itemsAt(z)) {
    std::string kind = wm::itemKindName(it->kind);
    if (!it->subtypeRaw.empty()) kind += "(" + it->subtypeRaw + ")";
    else if (it->subtype != wm::kNoSubtype) kind += "/" + std::to_string(it->subtype);
    std::snprintf(line, sizeof(line), "  item %u %-14s x%u (%d,%d) material=%s flags=%s v%llu",
                  it->id, kind.c_str(), it->stack, it->pos.x, it->pos.y,
                  materialText(model, it->material).c_str(), itemFlagsText(it->flags).c_str(),
                  static_cast<unsigned long long>(it->version));
    out += line;
    if (it->corpseFlags) {
      out += " corpse=" + corpseFlagsText(it->corpseFlags);
      if (wm::isSkeleton(it->corpseFlags)) out += " (skeleton)";
    }
    if (const wm::ItemAppearance* a = model.itemAppearance(it->id)) {
      std::snprintf(line, sizeof(line), " appearance v%08x: %zu layers", a->version, a->layers.size());
      out += line;
    }
    out += '\n';
  }
  return out;
}

int defaultZ(const wm::WorldModel& model, double renderTick) {
  std::map<int, int> count;
  for (wm::UnitId id : model.unitIds()) {
    const wm::EvalResult r = model.evaluate(id, renderTick);
    if (r.presence == wm::Presence::Present) ++count[static_cast<int>(std::lround(r.pos.z))];
  }
  int best = 0, bestCount = -1;
  for (const auto& [z, n] : count) {
    if (n > bestCount) {
      best = z;
      bestCount = n;
    }
  }
  return best;
}

std::string terrainSummary(const wm::WorldModel& model) {
  std::string out;
  char line[256];
  if (!model.hasTerrain()) {
    std::snprintf(line, sizeof(line), "terrain: none (no Full snapshot yet; %zu of %zu blocks)\n",
                  model.knownBlockCount(), model.mapBlockCount());
    return out + line;
  }
  std::snprintf(line, sizeof(line),
                "terrain: %zu/%zu blocks known | version %llu | %zu materials\n",
                model.knownBlockCount(), model.mapBlockCount(),
                static_cast<unsigned long long>(model.terrainVersion()), model.materialCount());
  out += line;

  std::array<size_t, 16> shapes{};
  size_t hidden = 0, water = 0, magma = 0, total = 0;
  const wm::TilePos dims = model.mapSize();
  for (int z = 0; z < dims.z; ++z) {
    model.forEachTileAtZ(z, [&](wm::TilePos, const wm::TileState& t) {
      ++total;
      if (t.flags & wm::kTileHidden) ++hidden;
      if (t.liquidKind == wm::LiquidKind::Water) ++water;
      if (t.liquidKind == wm::LiquidKind::Magma) ++magma;
      ++shapes[static_cast<size_t>(t.shape) & 15u];
    });
  }
  out += "  shapes:";
  for (size_t i = 0; i < shapes.size(); ++i) {
    if (!shapes[i]) continue;
    std::snprintf(line, sizeof(line), " %s=%zu", wm::tileShapeName(static_cast<wm::TileShape>(i)),
                  shapes[i]);
    out += line;
  }
  std::snprintf(line, sizeof(line), "\n  tiles=%zu hidden=%zu water=%zu magma=%zu\n", total,
                hidden, water, magma);
  out += line;
  return out;
}

std::string renderZ(const wm::WorldModel& model, int z, double renderTick) {
  const wm::TilePos dims = model.mapSize();
  std::string out;
  char line[128];
  std::snprintf(line, sizeof(line), "z=%d (%dx%d)\n", z, dims.x, dims.y);
  out += line;
  if (!model.hasTerrain() || z < 0 || z >= dims.z) {
    out += "  (no terrain)\n";
    return out;
  }
  const size_t stride = static_cast<size_t>(dims.x) + 1;  // + newline
  std::string grid(stride * static_cast<size_t>(dims.y), '?');
  for (int y = 0; y < dims.y; ++y) grid[static_cast<size_t>(y) * stride + dims.x] = '\n';
  model.forEachTileAtZ(z, [&](wm::TilePos p, const wm::TileState& t) {
    grid[static_cast<size_t>(p.y) * stride + static_cast<size_t>(p.x)] = tileGlyph(t);
  });
  // Buildings (higher ids over lower, so a workshop reads over its
  // stockpile), then items, then units.
  for (const wm::Building* b : model.buildingsAt(z)) {
    const char g = buildingGlyph(*b);
    for (int y = std::max(0, b->y1); y <= std::min(dims.y - 1, b->y2); ++y)
      for (int x = std::max(0, b->x1); x <= std::min(dims.x - 1, b->x2); ++x)
        if (b->occupies(x, y)) grid[static_cast<size_t>(y) * stride + static_cast<size_t>(x)] = g;
  }
  for (const wm::MapItem* it : model.itemsAt(z)) {
    if (it->pos.x < 0 || it->pos.y < 0 || it->pos.x >= dims.x || it->pos.y >= dims.y) continue;
    grid[static_cast<size_t>(it->pos.y) * stride + static_cast<size_t>(it->pos.x)] = itemGlyph(*it);
  }
  for (wm::UnitId id : model.unitIds()) {
    const wm::EvalResult r = model.evaluate(id, renderTick);
    if (r.presence != wm::Presence::Present) continue;
    if (static_cast<int>(std::lround(r.pos.z)) != z) continue;
    const int x = static_cast<int>(std::lround(r.pos.x));
    const int y = static_cast<int>(std::lround(r.pos.y));
    if (x < 0 || y < 0 || x >= dims.x || y >= dims.y) continue;
    grid[static_cast<size_t>(y) * stride + static_cast<size_t>(x)] = '@';
  }
  out += grid;
  out += glyphLegend();
  out += '\n';
  return out;
}

std::string appearanceSummary(const wm::WorldModel& model, wm::UnitId id) {
  const wm::UnitAppearance* a = model.unitAppearance(id);
  if (!a) return "appearance: none yet";
  char head[64];
  std::snprintf(head, sizeof(head), "appearance v%08x: ", a->version);
  std::string out = head;
  if (a->layers.empty()) return out + "no graphics";
  out += std::to_string(a->layers.size()) + " layers [";
  std::vector<wm::PageId> pages;
  std::vector<wm::PaletteId> palettes;
  for (const wm::AppearanceLayer& l : a->layers) {
    if (std::find(pages.begin(), pages.end(), l.page) == pages.end()) pages.push_back(l.page);
    if (l.palette != wm::kNoPalette &&
        std::find(palettes.begin(), palettes.end(), l.palette) == palettes.end()) {
      palettes.push_back(l.palette);
    }
  }
  for (size_t i = 0; i < pages.size(); ++i) {
    if (i) out += ", ";
    out += std::string(model.tilePageName(pages[i]));
  }
  out += "] palettes " + std::to_string(palettes.size());
  return out;
}

std::string report(const wm::WorldModel& model, double renderTick, std::optional<int> z,
                   ReportOptions options) {
  std::string out;
  char line[256];
  const wm::TilePos dims = model.mapSize();
  std::snprintf(line, sizeof(line),
                "map %dx%dx%d | latest tick %llu | render tick %.2f\n", dims.x, dims.y,
                dims.z, static_cast<unsigned long long>(model.latestTick()), renderTick);
  out += line;
  out += terrainSummary(model);
  out += buildingSummary(model);
  out += itemSummary(model);
  out += glyphSummary(model);

  for (wm::UnitId id : model.unitIds()) {
    const std::string* species = model.unitSpecies(id);
    const wm::EvalResult r = model.evaluate(id, renderTick);
    if (r.presence == wm::Presence::Present) {
      std::snprintf(line, sizeof(line),
                    "  unit %llu %-12s %-12s (%.2f, %.2f, %.2f) job=%s motion=%s\n",
                    static_cast<unsigned long long>(id),
                    species ? species->c_str() : "?", presenceName(r.presence), r.pos.x,
                    r.pos.y, r.pos.z, wm::jobName(r.job), wm::segmentKindName(r.segment));
    } else {
      std::snprintf(line, sizeof(line), "  unit %llu %-12s %-12s\n",
                    static_cast<unsigned long long>(id),
                    species ? species->c_str() : "?", presenceName(r.presence));
    }
    out += line;
    if (model.unitAppearance(id)) out += "      " + appearanceSummary(model, id) + "\n";
  }
  const int level = z ? *z : defaultZ(model, renderTick);
  if (options.listEntities) {
    out += listBuildingsAt(model, level);
    out += listItemsAt(model, level);
  }
  out += renderZ(model, level, renderTick);
  return out;
}

}  // namespace inspector
