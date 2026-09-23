// Building and map-item resolution: the world model's building /
// item vocabulary -> regions of the install's building and item pages.
// The rules follow how DF's own raws are organised:
//
//  * multi-tile buildings (workshops, furnaces, the depot, siege engines,
//    machines, wagons) are layouts named per kind / subtype / custom code
//    with a tile per (stage, lx, ly);
//  * furniture buildings draw the *item's* page member for the building's
//    material class (ITEM_BED_WOOD, ITEM_DOOR_STONE_CLOSED, ...): DF has no
//    separate building art for them;
//  * stockpiles, zones, bridges are edge-dressed: the member (or the extra
//    strip) is chosen from which of the four neighbours are outside the
//    building;
//  * items key on their kind, the itemdef raw (weapons, armour, tools,
//    ammo, toys, food) and the material: boulders, bars and rough gems per
//    material, plants and seeds through PLANT_GRAPHICS, corpses through the
//    creature's CORPSE sprite.
//
// Everything is recoloured like terrain: the material's STATE_COLOR row
// of the palette (the item / furniture / workshop pages are painted in
// palette keys). Pure over the index.
#include <algorithm>
#include <string>

#include "df3d_assets/resolver.h"

namespace df3d::assets {

using wm::BuildingKind;
using wm::BuildingStage;
using wm::ItemKind;

namespace {

bool isWoodToken(std::string_view token) {
  return token.compare(0, 6, "PLANT:") == 0 && token.size() > 5 &&
         token.compare(token.size() - 5, 5, ":WOOD") == 0;
}

bool startsWith(std::string_view s, std::string_view head) {
  return s.size() >= head.size() && s.compare(0, head.size(), head) == 0;
}

// The colour and palette row of a material token (as terrain does it).
template <class R>
void colourise(const AssetIndex& idx, R& r, std::string_view material) {
  r.colorName = std::string(idx.materialColorName(material));
  r.paletteRow = idx.paletteRow(r.colorName);
}

// Fallback order of material classes when a family lacks the member for
// the material's own class (a bone chair, a leather box, ...).
const MaterialClass kClassOrder[] = {MaterialClass::Wood, MaterialClass::Stone,
                                     MaterialClass::Metal, MaterialClass::Glass};

// `<family>_<CLASS><suffix>` for the material's class, then the other
// classes in kClassOrder, then the bare `<family><suffix>`; first variant
// (quality 1) of numbered members. nullptr when nothing exists.
const SpriteRef* classMember(const AssetIndex& idx, std::string_view family, MaterialClass cls,
                             std::string_view suffix, std::string* picked = nullptr) {
  auto tryName = [&](const std::string& name) -> const SpriteRef* {
    const SpriteRef* s = idx.tile(name);
    if (s && picked) *picked = name;
    return s;
  };
  if (cls != MaterialClass::Unknown) {
    if (const SpriteRef* s =
            tryName(std::string(family) + "_" + materialClassToken(cls) + std::string(suffix)))
      return s;
  }
  for (MaterialClass c : kClassOrder) {
    if (c == cls) continue;
    if (const SpriteRef* s =
            tryName(std::string(family) + "_" + materialClassToken(c) + std::string(suffix)))
      return s;
  }
  return tryName(std::string(family) + std::string(suffix));
}

// The `_N_S_W_E`-style suffix of the borders in `mask` (kWallN..kWallE
// bits), in N, S, W, E order, joined by `sep`; "" when none.
std::string edgeSuffix(uint8_t mask, const char* sep) {
  std::string s;
  const std::pair<uint8_t, const char*> sides[] = {
      {kWallN, "N"}, {kWallS, "S"}, {kWallW, "W"}, {kWallE, "E"}};
  for (const auto& [bit, name] : sides) {
    if (!(mask & bit)) continue;
    if (!s.empty()) s += sep;
    s += name;
  }
  return s;
}

struct Footprint {
  const BuildingQuery& q;
  bool occupies(int lx, int ly) const {
    if (lx < 0 || ly < 0 || lx >= q.width || ly >= q.height) return false;
    if (!q.extents || q.extents->empty()) return true;
    const size_t i = static_cast<size_t>(ly) * static_cast<size_t>(q.width) + static_cast<size_t>(lx);
    return i < q.extents->size() && (*q.extents)[i] != 0;
  }
  // Borders of tile (lx, ly): the sides whose neighbour is not part of
  // the building.
  uint8_t borders(int lx, int ly) const {
    uint8_t m = 0;
    if (!occupies(lx, ly - 1)) m |= kWallN;
    if (!occupies(lx, ly + 1)) m |= kWallS;
    if (!occupies(lx - 1, ly)) m |= kWallW;
    if (!occupies(lx + 1, ly)) m |= kWallE;
    return m;
  }
};

const char* workshopName(uint16_t subtype) {
  // DF workshop_type (df-structures 53.x order).
  static const char* const kNames[] = {
      "WORKSHOP_CARPENTER", "WORKSHOP_FARMER",     "WORKSHOP_MASON",     "WORKSHOP_CRAFTS",
      "WORKSHOP_JEWELER",   "WORKSHOP_METALSMITH", "WORKSHOP_MAGMAFORGE", "WORKSHOP_BOWYER",
      "WORKSHOP_MECHANIC",  "WORKSHOP_SIEGE",      "WORKSHOP_BUTCHER",   "WORKSHOP_LEATHER",
      "WORKSHOP_TANNER",    "WORKSHOP_CLOTHES",    "WORKSHOP_FISHERY",   "WORKSHOP_STILL",
      "WORKSHOP_LOOM",      "WORKSHOP_QUERN",      "WORKSHOP_KENNEL",    "WORKSHOP_KITCHEN",
      "WORKSHOP_ASHERY",    "WORKSHOP_DYER",       "WORKSHOP_MILLSTONE", "WORKSHOP_CUSTOM",
      "WORKSHOP_TOOL"};
  return subtype < sizeof(kNames) / sizeof(kNames[0]) ? kNames[subtype] : "";
}

const char* furnaceName(uint16_t subtype) {
  // DF furnace_type.
  static const char* const kNames[] = {"FURNACE_WOOD",         "FURNACE_SMELTER",
                                       "FURNACE_GLASS",        "FURNACE_KILN",
                                       "FURNACE_SMELTER_LAVA", "FURNACE_GLASS_LAVA",
                                       "FURNACE_KILN_LAVA",    "FURNACE_CUSTOM"};
  return subtype < sizeof(kNames) / sizeof(kNames[0]) ? kNames[subtype] : "";
}

// Maps the building's grid onto a layout: vanilla layouts are one row
// taller than the building (row 0 sticks up above it), so the building's
// rows are anchored at the bottom of the layout.
struct LayoutMap {
  const BuildingLayout* layout = nullptr;
  int ox = 0, oy = 0;
};

LayoutMap mapLayout(const AssetIndex& idx, const std::string& name, const BuildingQuery& q) {
  LayoutMap m;
  m.layout = idx.layout(name);
  if (!m.layout || m.layout->stages.empty()) {
    m.layout = nullptr;
    return m;
  }
  m.oy = std::max(0, m.layout->height - q.height);
  m.ox = 0;
  return m;
}

// The layout stage for a building stage: the highest stage present is
// the complete one, the one below it stands for InProgress (stageArt),
// Planned takes the complete art (the presentation draws it as a ghost).
int layoutStage(const BuildingLayout& l, BuildingStage stage, bool& stageArt) {
  stageArt = false;
  if (l.stages.empty()) return kLayoutNoStage;
  const int complete = l.stages.rbegin()->first;
  if (stage != BuildingStage::InProgress || l.stages.size() < 2) return complete;
  stageArt = true;
  return std::next(l.stages.rbegin())->first;
}

// One-wide layouts (the 1x1 shops `WORKSHOP_QUERN:1:0` / `:1:1`, the
// screw pump `SCREWPUMP_N_1:0` / `:1`) carry their rows as plain
// variants of the name rather than `stage:lx:ly`; the entries are the
// column top to bottom, one more than the building is tall when the top
// sticks up. Used when no grid layout gives the building a tile.
bool columnTiles(const AssetIndex& idx, const std::string& name, const BuildingQuery& q,
                 BuildingSprites& r) {
  if (q.width != 1) return false;
  auto it = idx.tileGraphics.find(name);
  if (it == idx.tileGraphics.end() || it->second.empty()) return false;
  const std::vector<SpriteRef>& col = it->second;
  const int n = static_cast<int>(col.size());
  const int oy = std::max(0, n - q.height);
  const Footprint fp{q};
  for (int ly = -oy; ly < q.height; ++ly) {
    const int i = ly + oy;
    if (i >= n || !fp.occupies(0, std::max(0, ly))) continue;
    r.tiles.push_back({0, ly, col[static_cast<size_t>(i)]});
  }
  return !r.tiles.empty();
}

bool layoutTiles(const AssetIndex& idx, const std::string& name, const BuildingQuery& q,
                 BuildingSprites& r) {
  const LayoutMap m = mapLayout(idx, name, q);
  if (m.layout) {
    const int stage = layoutStage(*m.layout, q.stage, r.stageArt);
    const Footprint fp{q};
    for (int ly = -m.oy; ly < q.height; ++ly) {
      for (int lx = 0; lx < q.width; ++lx) {
        if (!fp.occupies(lx, std::max(0, ly))) continue;
        const int tx = std::min(lx + m.ox, m.layout->width - 1);
        const int ty = std::min(ly + m.oy, m.layout->height - 1);
        if (const SpriteRef* s = m.layout->tile(stage, tx, ty)) r.tiles.push_back({lx, ly, *s});
      }
    }
    if (!r.tiles.empty()) return true;
    r.stageArt = false;
  }
  return columnTiles(idx, name, q, r);
}

// Every occupied tile gets the same sprite.
bool fillTiles(const BuildingQuery& q, const SpriteRef* s, BuildingSprites& r) {
  if (!s) return false;
  const Footprint fp{q};
  for (int ly = 0; ly < q.height; ++ly)
    for (int lx = 0; lx < q.width; ++lx)
      if (fp.occupies(lx, ly)) r.tiles.push_back({lx, ly, *s});
  return !r.tiles.empty();
}

}  // namespace

MaterialClass materialClassOf(const AssetIndex& idx, std::string_view token) {
  if (token.empty()) return MaterialClass::Unknown;
  if (isWoodToken(token)) return MaterialClass::Wood;
  const uint32_t f = idx.materialFlags(token);
  if (f & kMatWood) return MaterialClass::Wood;
  if (f & kMatMetal) return MaterialClass::Metal;
  if (f & kMatGlass) return MaterialClass::Glass;
  if (f & (kMatStone | kMatGem | kMatSoil)) return MaterialClass::Stone;
  if (startsWith(token, "INORGANIC:")) {
    // Metals and glasses are flagged in their raws; an unflagged
    // inorganic (an unknown or modded one) is treated as stone.
    return MaterialClass::Stone;
  }
  return MaterialClass::Unknown;
}

const char* materialClassToken(MaterialClass c) {
  switch (c) {
    case MaterialClass::Wood: return "WOOD";
    case MaterialClass::Stone: return "STONE";
    case MaterialClass::Metal: return "METAL";
    case MaterialClass::Glass: return "GLASS";
    case MaterialClass::Unknown: break;
  }
  return "";
}

std::string buildingLayoutName(BuildingKind kind, uint16_t subtype, std::string_view custom) {
  switch (kind) {
    case BuildingKind::Workshop: {
      const std::string n = workshopName(subtype);
      if (n == "WORKSHOP_CUSTOM" || (n.empty() && !custom.empty()))
        return "WORKSHOP_CUSTOM:" + std::string(custom);
      return n;
    }
    case BuildingKind::Furnace: {
      const std::string n = furnaceName(subtype);
      if (n == "FURNACE_CUSTOM" || (n.empty() && !custom.empty()))
        return "WORKSHOP_CUSTOM:" + std::string(custom);
      return n;
    }
    case BuildingKind::TradeDepot: return "TRADE_DEPOT";
    case BuildingKind::SiegeEngine: return subtype == 1 ? "BALLISTA_N" : "CATAPULT_N";
    case BuildingKind::Wagon: return "WAGON_BLD";
    case BuildingKind::Windmill: return "WINDMILL_S_1";
    default: break;
  }
  return "";
}

BuildingSprites resolveBuildingTiles(const AssetIndex& idx, const BuildingQuery& q) {
  BuildingSprites r;
  if (q.width < 1 || q.height < 1 || q.width > 64 || q.height > 64) {
    r.rule = "bad-size";
    return r;
  }
  const MaterialClass cls = materialClassOf(idx, q.material);
  const Footprint fp{q};
  auto done = [&](const char* rule) -> BuildingSprites& {
    r.found = !r.tiles.empty();
    r.rule = r.found ? rule : "missing-tile";
    if (r.found) colourise(idx, r, q.material);
    return r;
  };
  auto single = [&](const char* name, const char* rule) -> BuildingSprites& {
    fillTiles(q, idx.tile(name), r);
    return done(rule);
  };
  auto member = [&](const char* family, const char* suffix, const char* rule) -> BuildingSprites& {
    fillTiles(q, classMember(idx, family, cls, suffix), r);
    return done(rule);
  };
  auto tool = [&](const char* rawId, const char* variant, const char* rule) -> BuildingSprites& {
    const ItemDefGraphics* d = idx.itemDef(rawId);
    const SpriteRef* s = nullptr;
    if (d) {
      if (variant && *variant) {
        auto it = d->variants.find(variant);
        if (it != d->variants.end()) s = &it->second;
      } else if (cls != MaterialClass::Unknown) {
        auto it = d->variants.find(materialClassToken(cls));
        if (it != d->variants.end()) s = &it->second;
      }
      if (!s && d->base.valid()) s = &d->base;
    }
    fillTiles(q, s, r);
    return done(rule);
  };

  switch (q.kind) {
    // --- layouts ---
    case BuildingKind::Workshop:
    case BuildingKind::Furnace:
    case BuildingKind::TradeDepot:
    case BuildingKind::Wagon:
    case BuildingKind::Windmill: {
      const std::string name = buildingLayoutName(q.kind, q.subtype, q.custom);
      auto withOverlay = [&](const std::string& selected) {
        BuildingSprites overlay;
        // Custom codes follow the family token in DF's raw names.
        const auto colon = selected.find(':');
        const std::string overlayName = selected.substr(0, colon) + "_OVERLAY" +
          (colon == std::string::npos ? "" : selected.substr(colon));
        // Anchor sparse overlay layouts against the BASE layout dimensions.
        // A lone foreground tile at row zero must still spill north.
        BuildingQuery oq = q;
        if (const auto* base = idx.layout(selected)) {
          if (const auto* front = idx.layout(overlayName)) {
            bool ignored = false;
            const int stage = layoutStage(*base, q.stage, ignored);
            const int oy = std::max(0, base->height - q.height);
            for (const auto& t : r.tiles) {
              if (const auto* s = front->tile(stage, t.lx, t.ly + oy))
                overlay.tiles.push_back({t.lx, t.ly, *s, true});
            }
          }
        }
        if (overlay.tiles.empty() && columnTiles(idx, overlayName, oq, overlay))
          for (auto& t : overlay.tiles) t.foreground = true;
        r.tiles.insert(r.tiles.end(), overlay.tiles.begin(), overlay.tiles.end());
      };
      if (!name.empty() && layoutTiles(idx, name, q, r)) {
        withOverlay(name); return done("layout");
      }
      // A custom shop the graphics raws never named, or a workshop type
      // the raws have no art for (the 53.x tool workshop): the generic
      // custom workshop art.
      if (q.kind != BuildingKind::TradeDepot && layoutTiles(idx, "WORKSHOP_CUSTOM", q, r)) {
        withOverlay("WORKSHOP_CUSTOM"); return done("layout.custom-generic");
      }
      r.rule = "no-layout";
      return r;
    }
    case BuildingKind::SiegeEngine: {
      const bool ballista = q.subtype == 1;
      if (q.stage == BuildingStage::InProgress) {
        BuildingQuery cq = q;
        cq.stage = BuildingStage::Complete;
        if (layoutTiles(idx, ballista ? "BALLISTA_CONST_1" : "CATAPULT_CONST_1", cq, r)) {
          r.stageArt = true;
          return done("layout.siege.construction");
        }
      }
      if (layoutTiles(idx, buildingLayoutName(q.kind, q.subtype, q.custom), q, r))
        return done("layout.siege");
      r.rule = "no-layout";
      return r;
    }
    case BuildingKind::WaterWheel:
      if (layoutTiles(idx, q.width > q.height ? "WATER_WHEEL_WE_1" : "WATER_WHEEL_NS_1", q, r))
        return done("layout.waterwheel");
      r.rule = "no-layout";
      return r;
    case BuildingKind::ScrewPump:
      // Orientation is not mirrored (historical gap record); the north-facing
      // pump stands in.
      if (layoutTiles(idx, "SCREWPUMP_N_1", q, r)) return done("layout.screwpump.approx");
      r.rule = "no-layout";
      return r;

    // --- floor decals ---
    case BuildingKind::Stockpile: {
      // STOCKPILE_FLOOR on every tile, then an edge strip per border side.
      const SpriteRef* floor = idx.tile("STOCKPILE_FLOOR");
      const SpriteRef* edges[4] = {idx.tile("STOCKPILE_N"), idx.tile("STOCKPILE_S"),
                                   idx.tile("STOCKPILE_W"), idx.tile("STOCKPILE_E")};
      // DF splits the raised rope/post artwork across this cell and the
      // cell immediately north. The UP portions are visual spill only.
      const SpriteRef* upper[4] = {idx.tile("STOCKPILE_N_UP"), nullptr,
                                   idx.tile("STOCKPILE_W_UP"), idx.tile("STOCKPILE_E_UP")};
      const uint8_t bits[4] = {kWallN, kWallS, kWallW, kWallE};
      for (int ly = 0; ly < q.height; ++ly) {
        for (int lx = 0; lx < q.width; ++lx) {
          if (!fp.occupies(lx, ly)) continue;
          if (floor) r.tiles.push_back({lx, ly, *floor});
          const uint8_t b = fp.borders(lx, ly);
          for (int i = 0; i < 4; ++i) {
            if (!(b & bits[i])) continue;
            if (edges[i]) r.tiles.push_back({lx, ly, *edges[i]});
            if (upper[i]) r.tiles.push_back({lx, ly - 1, *upper[i]});
          }
        }
      }
      r.decal = true;
      return done("stockpile");
    }
    case BuildingKind::Civzone: {
      // ZONE_ACTIVE with the member named after the bordered sides.
      for (int ly = 0; ly < q.height; ++ly) {
        for (int lx = 0; lx < q.width; ++lx) {
          if (!fp.occupies(lx, ly)) continue;
          const std::string suffix = edgeSuffix(fp.borders(lx, ly), "_");
          const SpriteRef* s = idx.tile(suffix.empty() ? "ZONE_ACTIVE" : "ZONE_ACTIVE_" + suffix);
          if (!s) s = idx.tile("ZONE_ACTIVE");
          if (s) r.tiles.push_back({lx, ly, *s});
        }
      }
      r.decal = true;
      return done("zone");
    }
    case BuildingKind::FarmPlot:
      r.decal = true;
      return single("FARMPLOT", "farmplot");
    case BuildingKind::RoadDirt:
      r.decal = true;
      return single("BLD_DIRT_ROAD", "road.dirt");
    case BuildingKind::RoadPaved:
      r.decal = true;
      return single("BLD_PAVED_ROAD", "road.paved");

    // --- bridges: the retracted deck, edge-dressed ---
    case BuildingKind::Bridge: {
      const std::string family = std::string("BLD_BRIDGE_") +
                                 materialClassToken(cls == MaterialClass::Unknown
                                                        ? MaterialClass::Stone
                                                        : cls);
      for (int ly = 0; ly < q.height; ++ly) {
        for (int lx = 0; lx < q.width; ++lx) {
          if (!fp.occupies(lx, ly)) continue;
          const uint8_t b = fp.borders(lx, ly);
          std::string member;
          if (b == (kWallN | kWallS | kWallW | kWallE)) member = "1x1";
          else if (b == 0) member = "CENTER";
          else member = edgeSuffix(b, "");
          const SpriteRef* s = idx.tile(family + "_RETRACT_" + member);
          if (!s) s = idx.tile(family + "_RETRACT_CENTER");
          if (s) r.tiles.push_back({lx, ly, *s});
        }
      }
      return done("bridge.retract");
    }

    // --- furniture: the item pages' building members ---
    case BuildingKind::Bed: return member("ITEM_BED", "", "furniture.bed");
    case BuildingKind::Chair: return member("ITEM_CHAIR", "", "furniture.chair");
    case BuildingKind::Table: return member("ITEM_TABLE", "", "furniture.table");
    case BuildingKind::Box: return member("ITEM_BOX", "", "furniture.box");
    case BuildingKind::Cabinet: return member("ITEM_CABINET", "", "furniture.cabinet");
    case BuildingKind::Coffin: return member("ITEM_COFFIN", "", "furniture.coffin");
    case BuildingKind::Statue: return member("ITEM_STATUE", "", "furniture.statue");
    case BuildingKind::Armorstand: return member("ITEM_ARMOR_STAND", "_EMPTY", "furniture.armorstand");
    case BuildingKind::Weaponrack: return member("ITEM_WEAPON_RACK", "_EMPTY", "furniture.weaponrack");
    case BuildingKind::Door: {
      fillTiles(q, classMember(idx, "ITEM_DOOR", cls, "_CLOSED"), r);
      if (!r.tiles.empty() && (q.flags & wm::kBuildingForbidden))
        if (const SpriteRef* f = idx.tile("ITEM_DOOR_FORBIDDEN")) r.tiles.push_back({0, 0, *f});
      return done("furniture.door");
    }
    case BuildingKind::Floodgate: return member("ITEM_FLOODGATE", "_CLOSED", "furniture.floodgate");
    case BuildingKind::Hatch: {
      fillTiles(q, classMember(idx, "ITEM_HATCH_COVER", cls, "_CLOSED"), r);
      if (!r.tiles.empty() && (q.flags & wm::kBuildingForbidden))
        if (const SpriteRef* f = idx.tile("ITEM_HATCH_COVER_FORBIDDEN"))
          r.tiles.push_back({0, 0, *f});
      return done("furniture.hatch");
    }
    case BuildingKind::GrateWall: return member("ITEM_GRATE", "_WALL_CLOSED", "furniture.grate.wall");
    case BuildingKind::GrateFloor: return member("ITEM_GRATE", "_FLOOR_CLOSED", "furniture.grate.floor");
    case BuildingKind::BarsVertical: return single("BLD_VERTICAL_BARS_S", "bars.vertical");
    case BuildingKind::BarsFloor: return single("BLD_FLOOR_BARS", "bars.floor");
    case BuildingKind::WindowGlass: return single("ITEM_WINDOW_GLASS", "window.glass");
    case BuildingKind::WindowGem: return single("ITEM_WINDOW_GEM", "window.gem");
    case BuildingKind::Well: return single("BLD_WELL", "well");
    case BuildingKind::ArcheryTarget: return member("BLD_ARCHERY_TARGET", "", "archery-target");
    case BuildingKind::Support: return member("BLD_SUPPORT", "", "support");
    case BuildingKind::Chain:
      return single(cls == MaterialClass::Metal ? "BLD_CHAIN_METAL" : "BLD_CHAIN_ROPE", "chain");
    case BuildingKind::Cage: return member("ITEM_CAGE", "", "cage");
    case BuildingKind::AnimalTrap: return member("ITEM_ANIMAL_TRAP", "", "animal-trap");
    case BuildingKind::Slab: return single("ITEM_SLAB_ENGRAVED_MEMORIAL", "slab.memorial");
    case BuildingKind::TractionBench: {
      // The bench page names wood WOODEN.
      const char* c = cls == MaterialClass::Stone   ? "STONE"
                      : cls == MaterialClass::Metal ? "METAL"
                      : cls == MaterialClass::Glass ? "GLASS"
                                                    : "WOODEN";
      return single((std::string("ITEM_TRACTION_BENCH_") + c + "_ROPE").c_str(), "traction-bench");
    }
    case BuildingKind::Bookcase: return tool("ITEM_TOOL_BOOKCASE", "", "tool.bookcase");
    case BuildingKind::DisplayFurniture: return tool("ITEM_TOOL_DISPLAY_CASE", "", "tool.display-case");
    case BuildingKind::OfferingPlace: return tool("ITEM_TOOL_ALTAR", "", "tool.altar");
    case BuildingKind::NestBox: return tool("ITEM_TOOL_NEST_BOX", "", "tool.nest-box");
    case BuildingKind::Hive: return tool("ITEM_TOOL_HIVE", "HIVE_BLD", "tool.hive");
    case BuildingKind::Instrument:
      // The mirror carries no instrument class; the stringed building
      // instrument stands for all of them (historical gap record).
      return single("ITEM_INSTRUMENT_STRINGED_BUILDING", "instrument.approx");
    case BuildingKind::Nest: return single("NATURAL_NEST", "nest");
    case BuildingKind::Weapon: return single("UPRIGHT_WEAPON_RETRACTED_1", "upright-weapon");

    // --- traps by trap_type ---
    case BuildingKind::Trap:
      switch (q.subtype) {
        case 0: return single("LEVER_SET", "trap.lever");
        case 1: return single("TRAP_PLATE_READY", "trap.plate");
        case 2: return single("TRAP_CAGE", "trap.cage");
        case 3: return single("TRAP_STONE", "trap.stone");
        case 4: return single("TRAP_WEAPON", "trap.weapon");
        case 5:
          // Track direction is not mirrored; a N-S stop stands in.
          return single(cls == MaterialClass::Wood ? "TRACK_STOP_WOOD_NS" : "TRACK_STOP_STONE_NS",
                        "trap.track-stop.approx");
        default: break;
      }
      r.rule = "trap.unknown-subtype";
      return r;

    // --- machines ---
    case BuildingKind::AxleHorizontal:
      return single(q.width > q.height ? "AXLE_HORIZONTAL_WE_1" : "AXLE_HORIZONTAL_NS_1",
                    "machine.axle");
    case BuildingKind::AxleVertical: return single("AXLE_VERTICAL_1", "machine.axle.vertical");
    case BuildingKind::GearAssembly: return single("GEAR_ASSEMBLY_1", "machine.gear");
    case BuildingKind::Rollers:
      return single((std::string("ROLLERS_") +
                     (cls == MaterialClass::Wood ? "WOOD" : "STONE") +
                     (q.width > q.height ? "_WE_1" : "_NS_1"))
                        .c_str(),
                    "machine.rollers.approx");

    case BuildingKind::Shop:
    case BuildingKind::Unknown:
      break;
  }
  r.rule = "no-art";
  return r;
}

namespace {

const PlantGraphics* plantOfToken(const AssetIndex& idx, std::string_view token) {
  if (!startsWith(token, "PLANT:")) return nullptr;
  auto it = idx.plants.find(std::string(AssetIndex::materialRawId(token)));
  return it == idx.plants.end() ? nullptr : &it->second;
}

// The creature id of a CREATURE:<id>:<mat> token; "" otherwise.
std::string_view creatureOfToken(std::string_view token) {
  if (!startsWith(token, "CREATURE:")) return {};
  return AssetIndex::materialRawId(token);
}

// The tissue of a CREATURE:<id>:<tissue> token ("" otherwise).
std::string_view tissueOfToken(std::string_view token) {
  if (!startsWith(token, "CREATURE:")) return {};
  const size_t second = token.find(':', 9);
  return second == std::string_view::npos ? std::string_view() : token.substr(second + 1);
}

}  // namespace

std::string corpsePieceTileName(uint16_t f, std::string_view material, uint32_t id) {
  const std::string_view tissue = tissueOfToken(material);
  auto is = [&](const char* name) { return tissue == name; };
  // Flags first: they are DF's own semantics of what the piece counts as.
  // Measured (corpse_probe, 53.16): Unbutchered pieces draw BODYPART_LARGE_1..3 whatever else they count as; variant spread by id (assumed), SMALL_1..3 unobserved.
  if (f & wm::kCorpseUnbutchered && !(f & wm::kCorpseSkull)) {
    static const char* const kLarge[3] = {"BODYPART_LARGE_1", "BODYPART_LARGE_2", "BODYPART_LARGE_3"};
    return kLarge[id % 3];
  }
  // One lone skull observed (item 50048, even id) drew BODYPART_SKULL_2.
  if (f & wm::kCorpseSkull) return id % 2 ? "BODYPART_SKULL_1" : "BODYPART_SKULL_2";
  if (f & wm::kCorpseBone) return "BODYPART_BONE";
  if (f & wm::kCorpseTooth) return "BODYPART_TEETH";
  if (f & wm::kCorpseHorn) {
    if (is("HOOF")) return "BODYPART_HOOF";
    if (is("ANTLER")) return "BODYPART_ANTLER";
    return "BODYPART_HORN";
  }
  if (f & wm::kCorpseShell) return "BODYPART_SHELL";
  if (f & wm::kCorpsePearl) return "BODYPART_SHELL";
  if (f & wm::kCorpseHairWool) {
    if (is("WOOL") || is("HAIR_WOOL")) return "BODYPART_WOOL";
    return "BODYPART_HAIR";
  }
  if (f & wm::kCorpseLeather) {
    // DF's skin registry keys on colour / pattern / surface
    // (bodypart_skin_graphics_info), which the raws we parse do not carry:
    // the surface is guessed from the tissue name, the pattern is plain.
    if (is("SCALE") || is("SCALES")) return "BODYPART_SKIN_SCALES";
    if (is("FEATHER") || is("FEATHERS")) return "BODYPART_SKIN_FEATHERS";
    if (is("HAIR") || is("FUR")) return "BODYPART_SKIN_HAIR";
    return "BODYPART_SKIN_SMOOTH";
  }
  if (f & wm::kCorpseSilk) return "BODYPART_SMALL_1";
  // Then the tissue: organs and the like have their own tiles.
  // Measured (corpse_probe, 53.16): a butchered tooth has no corpse flag, tissue TOOTH, and draws BODYPART_TEETH.
  if (is("TOOTH")) return "BODYPART_TEETH";
  if (is("MUSCLE") || is("MEAT")) return "BODYPART_MEAT";
  if (is("FAT")) return "BODYPART_FAT";
  if (is("EYE")) return "BODYPART_EYE";
  if (is("CARTILAGE")) return "BODYPART_CARTILAGE";
  if (is("LUNG")) return "BODYPART_LUNG";
  if (is("HEART")) return "BODYPART_HEART";
  if (is("GUT") || is("GUTS") || is("INTESTINES")) return "BODYPART_INTESTINES";
  if (is("LIVER")) return "BODYPART_LIVER";
  if (is("STOMACH") || is("TRIPE")) return "BODYPART_TRIPE";
  if (is("PANCREAS") || is("SWEETBREAD")) return "BODYPART_SWEETBREAD";
  if (is("SPLEEN")) return "BODYPART_SPLEEN";
  if (is("KIDNEY")) return "BODYPART_KIDNEY";
  if (is("NERVE") || is("NERVOUS_TISSUE")) return "BODYPART_NERVOUS_TISSUE";
  if (is("BRAIN")) return "BODYPART_BRAIN";
  if (is("SCALE") || is("SCALES")) return "BODYPART_SCALE";
  if (is("CHITIN")) return "BODYPART_CHITIN_1";
  if (is("GIZZARD")) return "BODYPART_GIZZARD";
  if (is("HOOF")) return "BODYPART_HOOF";
  if (is("ANTLER")) return "BODYPART_ANTLER";
  if (is("HAIR") || is("FUR")) return "BODYPART_HAIR";
  if (is("BONE")) return "BODYPART_BONE";
  if (is("SKIN")) return "BODYPART_SKIN_SMOOTH";
  return "BODYPART_LARGE_1";  // creature size is not in the index
}

ItemSprite resolveItem(const AssetIndex& idx, const ItemQuery& q) {
  ItemSprite r;
  const MaterialClass cls = materialClassOf(idx, q.material);
  const std::string_view rawId = AssetIndex::materialRawId(q.material);
  auto done = [&](const SpriteRef* s, const char* rule) -> ItemSprite& {
    if (s) {
      r.found = true;
      r.sprite = *s;
      r.rule = rule;
      colourise(idx, r, q.material);
    } else {
      r.rule = "missing-tile";
    }
    return r;
  };
  auto single = [&](const char* name, const char* rule) -> ItemSprite& {
    return done(idx.tile(name), rule);
  };
  auto member = [&](const char* family, const char* suffix, const char* rule) -> ItemSprite& {
    return done(classMember(idx, family, cls, suffix), rule);
  };
  // The itemdef's sprite: the named variant when present, else the
  // material class variant, else the base; `fallback` when the itemdef
  // is unknown to the raws.
  auto def = [&](const char* variant, const char* fallback, const char* rule) -> ItemSprite& {
    const ItemDefGraphics* d = q.subtypeRaw.empty() ? nullptr : idx.itemDef(q.subtypeRaw);
    if (d) {
      if (variant && *variant) {
        auto it = d->variants.find(variant);
        if (it != d->variants.end()) return done(&it->second, rule);
      }
      if (cls != MaterialClass::Unknown) {
        auto it = d->variants.find(materialClassToken(cls));
        if (it != d->variants.end()) return done(&it->second, rule);
      }
      if (d->base.valid()) return done(&d->base, rule);
    }
    return single(fallback, "itemdef-fallback");
  };
  auto metalOrWood = [&](const char* family, const char* rule) -> ItemSprite& {
    return single((std::string(family) + (cls == MaterialClass::Metal ? "_METAL" : "_WOOD")).c_str(),
                  rule);
  };
  auto creature = [&](CreatureState state, const char* rule, const char* why) -> ItemSprite& {
    const std::string_view species = creatureOfToken(q.material);
    if (species.empty()) {
      r.rule = why;
      return r;
    }
    const CreatureSprite c = resolveCreature(idx, species, state);
    if (c.found) return done(&c.sprite, rule);
    r.rule = c.layered ? "creature.layered" : "creature.no-sprite";
    return r;
  };

  switch (q.kind) {
    case ItemKind::Bar: {
      auto it = idx.barsGraphics.find(std::string(rawId));
      if (it != idx.barsGraphics.end()) return done(&it->second, "bar.material");
      if (q.material.find(":SOAP") != std::string_view::npos) return single("ITEM_BARS_SOAP", "bar.soap");
      return single("ITEM_BARS", "bar");
    }
    case ItemKind::SmallGem:
    case ItemKind::Gem:
    case ItemKind::Rough: {
      auto it = idx.roughGemGraphics.find(std::string(rawId));
      if (it != idx.roughGemGraphics.end()) return done(&it->second, "gem.material");
      // Cut gems have no page of their own in vanilla; the rough gem
      // sprite (recoloured) stands in (historical gap record).
      return single("ITEM_ROUGH_GEM", q.kind == ItemKind::Rough ? "gem.rough" : "gem.cut->rough");
    }
    case ItemKind::Blocks: return single("ITEM_BLOCKS", "blocks");
    case ItemKind::Boulder: {
      auto it = idx.boulderGraphics.find(std::string(q.material));
      if (it != idx.boulderGraphics.end()) return done(&it->second, "boulder.material");
      return single("ITEM_BOULDER", "boulder");
    }
    case ItemKind::Wood: return single("ITEM_WOOD", "wood");
    case ItemKind::Rock: return single("ITEM_ROCK", "rock");
    case ItemKind::Branch: return single("ITEM_BRANCH", "branch");
    case ItemKind::Door: return member("ITEM_DOOR", "", "item.door");
    case ItemKind::Floodgate: return member("ITEM_FLOODGATE", "", "item.floodgate");
    case ItemKind::HatchCover: return member("ITEM_HATCH_COVER", "", "item.hatch");
    case ItemKind::Grate: return member("ITEM_GRATE", "", "item.grate");
    case ItemKind::Bed: return member("ITEM_BED", "", "item.bed");
    case ItemKind::Chair: return member("ITEM_CHAIR", "", "item.chair");
    case ItemKind::Table: return member("ITEM_TABLE", "", "item.table");
    case ItemKind::Coffin: return member("ITEM_COFFIN", "", "item.coffin");
    case ItemKind::Statue: return member("ITEM_STATUE", "", "item.statue");
    case ItemKind::Box: return member("ITEM_BOX", "", "item.box");
    case ItemKind::Cabinet: return member("ITEM_CABINET", "", "item.cabinet");
    case ItemKind::Armorstand: return member("ITEM_ARMOR_STAND", "_EMPTY", "item.armorstand");
    case ItemKind::Weaponrack: return member("ITEM_WEAPON_RACK", "_EMPTY", "item.weaponrack");
    case ItemKind::Chain:
      return single(cls == MaterialClass::Metal ? "ITEM_CHAIN_METAL" : "ITEM_CHAIN_ROPE", "chain");
    case ItemKind::Flask:
      return single(cls == MaterialClass::Glass   ? "ITEM_FLASK_GLASS"
                    : cls == MaterialClass::Metal ? "ITEM_FLASK_METAL"
                                                  : "ITEM_FLASK_LEATHER",
                    "flask");
    case ItemKind::Goblet: return member("ITEM_GOBLET", "", "goblet");
    case ItemKind::Instrument:
      // Instrument class is not mirrored (historical gap record).
      return single("ITEM_INSTRUMENT_STRINGED_HANDHELD", "instrument.approx");
    case ItemKind::Toy: return def("", "ITEM_TOY", "toy");
    case ItemKind::Window: return single("ITEM_WINDOW_GLASS", "window");
    case ItemKind::Cage: return member("ITEM_CAGE", "", "cage");
    case ItemKind::Barrel:
      return single(cls == MaterialClass::Metal ? "ITEM_BARREL_METAL_EMPTY" : "ITEM_BARREL_WOOD_EMPTY",
                    "barrel");
    case ItemKind::Bucket: return metalOrWood("ITEM_BUCKET", "bucket");
    case ItemKind::AnimalTrap: return metalOrWood("ITEM_ANIMAL_TRAP", "animal-trap");
    case ItemKind::Corpse:
      // A whole corpse that has rotted to bone is DF's bone pile (the
      // skeleton derivation); a fresh one of a layered species is drawn by
      // the presentation from its published stack (rule creature.layered
      // tells it so), a simple species from its CORPSE sprite.
      if (wm::isSkeleton(q.corpseFlags)) {
        ItemSprite& r2 = single("SKELETON", "corpse.skeleton");
        r2.bodyPart = r2.found;
        return r2;
      }
      return creature(CreatureState::Corpse, "corpse.creature", "corpse.no-species");
    case ItemKind::CorpsePiece: {
      // Body parts and bone piles are BODYPART_* / SKELETON tiles chosen
      // from what the piece counts as (corpse flags) and its tissue.
      const std::string name = corpsePieceTileName(q.corpseFlags, q.material, q.id);
      const SpriteRef* s = idx.tile(name);
      if (!s && startsWith(name, "BODYPART_SKIN_")) s = idx.tile("BODYPART_SKIN_SMOOTH");
      if (!s) s = idx.tile("BODYPART_LARGE_1");
      ItemSprite& r2 = done(s, "piece.bodypart");
      r2.bodyPart = r2.found;
      return r2;
    }
    case ItemKind::Remains: return single("ITEM_REMAINS", "remains");
    case ItemKind::Vermin:
    case ItemKind::Pet: {
      const std::string_view species = creatureOfToken(q.material);
      if (!species.empty()) {
        auto it = idx.creatures.find(std::string(species));
        if (it != idx.creatures.end()) {
          auto st = it->second.states.find("VERMIN");
          if (st != it->second.states.end()) return done(&st->second, "vermin.creature");
        }
      }
      return single("VERMIN_LIGHT", "vermin.generic");
    }
    case ItemKind::Weapon:
      return def((q.flags & wm::kItemArtifact) ? "ARTIFACT"
                 : cls == MaterialClass::Wood  ? "WOOD"
                                               : "DEFAULT",
                 "ITEM_TOOL", "weapon");
    case ItemKind::Armor: return def("", "ITEM_ARMOR_COAT", "armor");
    case ItemKind::Shoes: return def(cls == MaterialClass::Metal ? "METAL" : "", "ITEM_SHOES_SHOES", "shoes");
    case ItemKind::Shield: return def(cls == MaterialClass::Wood ? "WOODEN" : "", "ITEM_SHIELD", "shield");
    case ItemKind::Helm: return def("", "ITEM_HELM_HELM", "helm");
    case ItemKind::Gloves: return def("", "ITEM_GLOVES_GLOVES", "gloves");
    case ItemKind::Pants: return def("", "ITEM_PANTS_PANTS", "pants");
    case ItemKind::Bag: return single("ITEM_BAG", "bag");
    case ItemKind::Bin:
      return single(cls == MaterialClass::Metal ? "ITEM_BIN_METAL_EMPTY" : "ITEM_BIN_WOOD_EMPTY", "bin");
    case ItemKind::Figurine: return metalOrWood("ITEM_FIGURINE", "craft.figurine");
    case ItemKind::Amulet: return metalOrWood("ITEM_AMULET", "craft.amulet");
    case ItemKind::Scepter: return metalOrWood("ITEM_SCEPTER", "craft.scepter");
    case ItemKind::Crown: return metalOrWood("ITEM_CROWN", "craft.crown");
    case ItemKind::Ring: return metalOrWood("ITEM_RING", "craft.ring");
    case ItemKind::Earring: return metalOrWood("ITEM_EARRING", "craft.earring");
    case ItemKind::Bracelet: return metalOrWood("ITEM_BRACELET", "craft.bracelet");
    case ItemKind::Totem: return single("ITEM_TOTEM", "craft.totem");
    case ItemKind::Ammo:
      return def(cls == MaterialClass::Wood ? "STRAIGHT_WOOD" : "STRAIGHT_DEFAULT", "ITEM_AMMO", "ammo");
    case ItemKind::SiegeAmmo: return def("STRAIGHT_DEFAULT", "ITEM_AMMO", "siege-ammo");
    case ItemKind::BallistaArrowhead: return single("ITEM_BALLISTA_ARROWHEAD", "ballista-arrowhead");
    case ItemKind::Anvil: return single("ITEM_ANVIL", "anvil");
    case ItemKind::Seeds:
      if (const PlantGraphics* p = plantOfToken(idx, q.material); p && p->seed.valid())
        return done(&p->seed, "seeds.plant");
      return single("SEEDS_FOR_BAG", "seeds.generic");
    case ItemKind::Plant:
      if (const PlantGraphics* p = plantOfToken(idx, q.material); p && p->picked.valid())
        return done(&p->picked, "plant.picked");
      return single("ITEM_PLANT", "plant.generic");
    case ItemKind::PlantGrowth:
      if (const PlantGraphics* p = plantOfToken(idx, q.material); p && p->growthPicked.valid())
        return done(&p->growthPicked, "growth.picked");
      return single("ITEM_PLANT_GROWTH", "growth.generic");
    case ItemKind::SkinTanned: return single("ITEM_TANNED_SKIN", "leather");
    case ItemKind::Thread:
      // A THREAD item lying as a spider's web (wm::kItemWeb) is one
      // of DF's four harmless web tiles, picked by the item id so a web
      // keeps its look; ITEM_WEB_THICK is not distinguishable from the
      // flag.
      if (q.flags & wm::kItemWeb) {
        if (const SpriteRef* w = idx.tile("ITEM_WEB_HARMLESS", static_cast<size_t>(q.id % 4)))
          return done(w, "web.harmless");
        return single("ITEM_THREAD", "web->thread");
      }
      return single("ITEM_THREAD", "thread");
    case ItemKind::Cloth: return single("ITEM_CLOTH", "cloth");
    case ItemKind::Backpack: return single("ITEM_BACKPACK", "backpack");
    case ItemKind::Quiver: return single("ITEM_QUIVER", "quiver");
    case ItemKind::CatapultParts: return single("ITEM_CATAPULT_PARTS", "siege-parts");
    case ItemKind::BallistaParts: return single("ITEM_BALLISTA_PARTS", "siege-parts");
    case ItemKind::TrapParts: return single("ITEM_MECHANISMS", "mechanisms");
    case ItemKind::TrapComp: return def("", "ITEM_TRAP_COMPONENT", "trapcomp");
    case ItemKind::Drink:
    case ItemKind::LiquidMisc: return single("ITEM_LIQUID", "liquid");
    case ItemKind::PowderMisc: return single("ITEM_POWDER", "powder");
    case ItemKind::Cheese: return single("ITEM_CHEESE", "cheese");
    case ItemKind::Food: return def("", "ITEM_PREPARED_MEAL", "food");
    case ItemKind::Coin: {
      const char* name = q.stack <= 1    ? "ITEM_COINS_SINGLE"
                         : q.stack < 10  ? "ITEM_COINS_PILE_1"
                         : q.stack < 50  ? "ITEM_COINS_PILE_2"
                         : q.stack < 200 ? "ITEM_COINS_PILE_3"
                                         : "ITEM_COINS_PILE_4";
      return single(name, "coins");
    }
    case ItemKind::PipeSection: return single("ITEM_PIPE_SECTION", "pipe");
    case ItemKind::Quern: return single("ITEM_QUERN", "quern");
    case ItemKind::Millstone: return single("ITEM_MILLSTONE", "millstone");
    case ItemKind::Splint: return single("ITEM_SPLINT", "splint");
    case ItemKind::Crutch: return single("ITEM_CRUTCH", "crutch");
    case ItemKind::OrthopedicCast: return single("ITEM_ORTHOPEDIC_CAST", "cast");
    case ItemKind::TractionBench: {
      const char* c = cls == MaterialClass::Stone   ? "STONE"
                      : cls == MaterialClass::Metal ? "METAL"
                      : cls == MaterialClass::Glass ? "GLASS"
                                                    : "WOODEN";
      return single((std::string("ITEM_TRACTION_BENCH_") + c + "_ROPE").c_str(), "traction-bench");
    }
    case ItemKind::Tool: return def("", "ITEM_TOOL", "tool");
    case ItemKind::Slab: return single("ITEM_SLAB_BLANK", "slab");
    case ItemKind::Egg: return single("ITEM_EGG_SIZE2", "egg");
    case ItemKind::Book: return member("ITEM_BOOK", "", "book");
    case ItemKind::Sheet: return single("ITEM_SHEET", "sheet");
    case ItemKind::Meat:
    case ItemKind::Fish:
    case ItemKind::FishRaw:
    case ItemKind::Glob:
      // No page names these in vanilla 53.16 (they are drawn from the
      // creature's remains / meat colours in-game); placeholder.
      r.rule = "no-art";
      return r;
    case ItemKind::Unknown: break;
  }
  r.rule = "no-art";
  return r;
}

}  // namespace df3d::assets
