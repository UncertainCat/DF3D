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
#include "df3d_assets/gem.h"

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

// Exact native stages select matching raw art. Older recordings retain the
// coarse fallback; an unknown value must not invent an intermediate stage.
int layoutStage(const BuildingLayout& l, const BuildingQuery& q, bool& stageArt) {
  stageArt = false;
  if (l.stages.empty()) return kLayoutNoStage;
  const int complete = l.stages.rbegin()->first;
  if (q.constructionStage >= 0 && l.stages.count(q.constructionStage)) {
    stageArt = q.stage != BuildingStage::Complete;
    return q.constructionStage;
  }
  if (q.stage != BuildingStage::InProgress || l.stages.size() < 2) return complete;
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
    const int stage = layoutStage(*m.layout, q, r.stageArt);
    const Footprint fp{q};
    for (int ly = -m.oy; ly < q.height; ++ly) {
      for (int lx = 0; lx < q.width; ++lx) {
        if (!fp.occupies(lx, std::max(0, ly))) continue;
        const int tx = std::min(lx + m.ox, m.layout->width - 1);
        const int ty = std::min(ly + m.oy, m.layout->height - 1);
        if (const SpriteRef* s = m.layout->tile(stage, tx, ty)) r.tiles.push_back({lx, ly, *s});
      }
    }
    if (!r.tiles.empty()) { r.gridLayout = true; return true; }
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

std::string slabArtworkName(int engraving) {
      static constexpr const char* names[]={"SECRET","IMPORTS_FOOD","IMPORTS_CLOTHING","IMPORTS_GENERAL",
        "SHOP_CLOTH","SHOP_TANNING","SHOP_CLOTHING_CLOTH","SHOP_CLOTHING_LEATHER","SHOP_BONE_CARVER",
        "SHOP_GEM_CUTTER","SHOP_WEAPONSMITH_METAL","SHOP_WEAPONSMITH_WOOD","SHOP_BLACKSMITH","SHOP_ARMORSMITH",
        "SHOP_METAL_CRAFTER","SHOP_LEATHER_ACCESSORIES","SHOP_FURNITURE_WOOD","SHOP_FURNITURE_STONE",
        "SHOP_FURNITURE_METAL","TAVERN","TRUE_NAME"};
  if(engraving==0)return "ITEM_SLAB_ENGRAVED_MEMORIAL";
  if(engraving>=6 && engraving<=26)return std::string("ITEM_SLAB_ENGRAVED_")+names[engraving-6];
  return "ITEM_SLAB_BLANK";
}

}  // namespace

MaterialClass materialClassOf(const AssetIndex& idx, std::string_view token) {
  if (token.empty()) return MaterialClass::Unknown;
  if (isWoodToken(token)) return MaterialClass::Wood;
  if(token=="GLASS_GREEN" || token=="GLASS_CLEAR" || token=="GLASS_CRYSTAL")return MaterialClass::Glass;
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
    case BuildingKind::SiegeEngine: return subtype == 2 ? "BOLT_THROWER_READY_N" : subtype == 1 ? "BALLISTA_N" : "CATAPULT_N";
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
    const ItemDefGraphics* d = idx.itemDef(q.constructionToolRaw.empty()?std::string_view(rawId):q.constructionToolRaw);
    const bool complete=q.stage==BuildingStage::Complete;
    const bool owned=complete && q.constructionItemIsLog>=0;
    const auto toolClass=owned?materialClassOf(idx,q.constructionItemMaterial):cls;
    const SpriteRef* s = nullptr;
    if (d) {
      if (variant && *variant) {
        auto it = d->variants.find(variant);
        if (it != d->variants.end()) s = &it->second;
      } else if (complete && toolClass != MaterialClass::Unknown) {
        auto it = d->variants.find(materialClassToken(toolClass));
        if (it != d->variants.end()) s = &it->second;
      }
      if (!s && d->base.valid()) s = &d->base;
    }
    fillTiles(q, s, r);done(rule);
    if(q.kind==BuildingKind::Hive){r.paletteRow=-1;r.colorName.clear();}
    else if(owned) {
      colourise(idx,r,q.constructionItemMaterial);
      if(!q.constructionItemSolidColor.empty()){r.colorName=std::string(q.constructionItemSolidColor);r.paletteRow=idx.paletteRow(r.colorName);}
    }
    return r;
  };

  switch (q.kind) {
    case BuildingKind::Construction: {
      // Native construction_type order; named art owns colour and transparency.
      static constexpr const char* names[] = {
        "FORTIFICATION", "WALL", "FLOOR", "STAIR_UP", "STAIR_DOWN", "STAIR_UPDOWN", "RAMP",
        "TRACK_N", "TRACK_S", "TRACK_E", "TRACK_W", "TRACK_NS", "TRACK_NE", "TRACK_NW",
        "TRACK_SE", "TRACK_SW", "TRACK_WE", "TRACK_NSE", "TRACK_NSW", "TRACK_NWE",
        "TRACK_SWE", "TRACK_NSWE", "TRACK_RN", "TRACK_RS", "TRACK_RE", "TRACK_RW",
        "TRACK_RNS", "TRACK_RNE", "TRACK_RNW", "TRACK_RSE", "TRACK_RSW", "TRACK_RWE",
        "TRACK_RNSE", "TRACK_RNSW", "TRACK_RNWE", "TRACK_RSWE", "TRACK_RNSWE", "REINFORCED_WALL"};
      r.decal = true; r.stageArt = true;
      if (q.stage == wm::BuildingStage::Complete || q.subtype >= std::size(names)) {
        r.rule = "construction.no-pending-art"; return r;
      }
      const auto name = std::string("PLANNED_CONSTRUCTION_") + names[q.subtype];
      fillTiles(q, idx.tile(name), r);
      r.found = !r.tiles.empty();
      r.rule = r.found ? "construction.pending" : "missing-tile";
      return r;
    }
    // --- layouts ---
    case BuildingKind::Workshop:
    case BuildingKind::Furnace:
    case BuildingKind::TradeDepot:
    case BuildingKind::Wagon: {
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
            const int stage = layoutStage(*base, q, ignored);
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
      auto finishLayout = [&](const char* rule) {
        auto result = done(rule);
        if(q.kind==BuildingKind::Workshop && q.stage!=BuildingStage::Complete &&
           (q.subtype==17 || q.subtype==22 || (q.subtype==23 && q.custom=="SCREW_PRESS"))) {
          result.plannedHalfAlpha=true;result.stageArt=true;
        }
        // Native base color comes from construction contents, not b.mat_type.
        // With no component the base retains its painted palette at every stage.
        if (result.gridLayout || (q.kind==BuildingKind::Workshop && (q.subtype==17 || q.subtype==22))) {
          result.paletteRow = -1; result.colorName.clear();
          if (q.constructionItemIsLog >= 0) {
            colourise(idx, result, q.constructionItemMaterial);
            if (!q.constructionItemSolidColor.empty()) {
              result.colorName = std::string(q.constructionItemSolidColor);
              result.paletteRow = idx.paletteRow(result.colorName);
            }
          }
        }
        return result;
      };
      if (!name.empty() && layoutTiles(idx, name, q, r)) {
        withOverlay(name); return finishLayout("layout");
      }
      // A custom shop the graphics raws never named, or a workshop type
      // the raws have no art for (the 53.x tool workshop): the generic
      // custom workshop art.
      if (q.kind != BuildingKind::TradeDepot && layoutTiles(idx, "WORKSHOP_CUSTOM", q, r)) {
        withOverlay("WORKSHOP_CUSTOM"); return finishLayout("layout.custom-generic");
      }
      r.rule = "no-layout";
      return r;
    }
    case BuildingKind::SiegeEngine: {
      if(q.subtype>2) {r.rule="no-layout";return r;}
      const bool complete=q.stage==BuildingStage::Complete;
      const bool bolt=q.subtype==2;
      const std::string base=bolt?"BOLT_THROWER":q.subtype==1?"BALLISTA":"CATAPULT";
      static constexpr const char* directions[]={"N","NE","E","SE","S","SW","W","NW"};
      const char* facing=directions[q.siegeFacing>=0 && q.siegeFacing<8?q.siegeFacing:0];
      std::string name;
      if(!complete && !bolt && q.containedItemCount>=0 && q.constructionStage>=0 && q.constructionStage<=2) {
        name=base+"_CONST_"+std::to_string(q.containedItemCount? q.constructionStage+1:0);
      } else if(!complete && !bolt && q.stage==BuildingStage::InProgress) {
        // Older recordings lack exact construction facts; retain their coarse fallback.
        name=base+"_CONST_1";
      } else {
        const bool firing=complete && ((q.siegeFireTimer>=1 && q.siegeFireTimer<=(bolt?2:5)) ||
                                      (q.subtype==1 && q.containedItemCount==3));
        name=bolt?base+(firing?"_FIRING_":"_READY_")+facing:
                  base+"_"+facing+(firing?"_FIRING":"");
      }
      if(bolt) fillTiles(q,idx.tile(name),r);
      else layoutTiles(idx,name,q,r);
      r.found=!r.tiles.empty();r.rule=r.found?"layout.siege":"no-layout";
      r.stageArt=!complete;
      if(complete && q.constructionItemIsLog>=0) {
        colourise(idx,r,q.constructionItemMaterial);
        if(!q.constructionItemSolidColor.empty()) {
          r.colorName=std::string(q.constructionItemSolidColor);r.paletteRow=idx.paletteRow(r.colorName);
        }
      }
      return r;
    }
    case BuildingKind::Windmill:
      // Orientation and rotation select atlas cells in the machinery shader.
      if(layoutTiles(idx,"WINDMILL_S_1",q,r)) {
        r.found=true;r.rule="layout.windmill";
        if(q.stage==BuildingStage::Complete && q.constructionItemIsLog>=0)colourise(idx,r,q.constructionItemMaterial);
      } else r.rule="no-layout";
      return r;
    case BuildingKind::WaterWheel:
      // Resident art uses frame one; the presentation applies native machine phase.
      if (layoutTiles(idx, q.width > q.height ? "WATER_WHEEL_WE_1" : "WATER_WHEEL_NS_1", q, r)) {
        r.found=true;r.rule="layout.waterwheel";
        if(q.stage==BuildingStage::Complete && q.constructionItemIsLog>=0)
          colourise(idx,r,q.constructionItemMaterial);
        return r;
      }
      r.rule = "no-layout";
      return r;
    case BuildingKind::ScrewPump: {
      // Captured stationary art faces the output, opposite DF's intake enum.
      // Old recordings without direction retain their historical north artwork.
      static constexpr const char* names[]={"SCREWPUMP_S_1","SCREWPUMP_W_1",
                                           "SCREWPUMP_N_1","SCREWPUMP_E_1"};
      if (q.pumpDirection<0) {
        layoutTiles(idx,"SCREWPUMP_N_1",q,r);
      } else if (q.pumpDirection<4) {
        const bool horizontal=(q.pumpDirection%2)!=0;
        if (q.width==(horizontal?2:1) && q.height==(horizontal?1:2)) {
          for (int i=0;i<2;++i) {
            const int x=horizontal?i:0,y=horizontal?0:i;
            if (const auto* sprite=idx.tile(names[q.pumpDirection],size_t(i));
                sprite && fp.occupies(x,y)) r.tiles.push_back({x,y,*sprite});
          }
        }
      }
      // Native stationary pumps use the painted palette, not their material color.
      r.found=!r.tiles.empty();r.rule=r.found?"layout.screwpump":"no-layout";
      return r;
    }

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
    case BuildingKind::RoadDirt:
    case BuildingKind::RoadPaved: {
      const bool farm=q.kind==BuildingKind::FarmPlot;
      // Native uses the paved token for both road classes. Progress is local
      // to the bounding rectangle; holes do not shift its 4/2/1-cell spacing.
      // Recorded cells and palettes: farm_road_rendering.json.gz.
      const auto* sprite=idx.tile(farm?"FARMPLOT":"BLD_PAVED_ROAD");
      r.decal=true;r.stageArt=true;r.found=sprite!=nullptr;
      r.rule=sprite?(farm?"farmplot":"road"):"missing-tile";
      if (!sprite) return r;
      const int stage=q.stage==BuildingStage::Complete?3:
          q.constructionStage>=0?std::clamp(int(q.constructionStage),0,3):
          q.stage==BuildingStage::Planned?0:1;
      const int spacing=1<<(3-stage);
      for(int y=0;y<q.height;++y)for(int x=0;x<q.width;++x) {
        if(!fp.occupies(x,y))continue;
        const bool finished=stage>0 && x%spacing==0 && y%spacing==0;
        if(!farm && stage>0 && !finished)continue;
        r.tiles.push_back({x,y,*sprite,false,true,!finished});
      }
      // An extent mask may exclude every currently drawn road cell.
      return r;
    }

    // Bridge direction/state select installed graphics; see native capture in
    // fixtures/construction/bridge_rendering.json. Hinge wins on a thin span.
    case BuildingKind::Bridge: {
      if(q.bridgeDirection==-1 && q.bridgeRaised) {
        r.found=true;r.rule="bridge.retracted";return r;
      }
      const std::string family = std::string("BLD_BRIDGE_") +
                                 materialClassToken(cls == MaterialClass::Unknown
                                                        ? MaterialClass::Stone
                                                        : cls);
      for (int ly = 0; ly < q.height; ++ly) {
        for (int lx = 0; lx < q.width; ++lx) {
          if (!fp.occupies(lx, ly)) continue;
          if(q.bridgeDirection>=0 && q.bridgeDirection<=3) {
            const bool horizontal=q.bridgeDirection<2;
            const bool reverse=q.bridgeDirection==1 || q.bridgeDirection==3;
            const int along=horizontal?lx:ly, length=horizontal?q.width:q.height;
            const int across=horizontal?ly:lx, breadth=horizontal?q.height:q.width;
            const bool hinge=along==(reverse?length-1:0);
            const bool end=along==(reverse?0:length-1);
            const std::string direction=std::string(1,"WENS"[q.bridgeDirection]);
            const std::string side=breadth==1?"1":across==0?(horizontal?"N":"W"):
                across==breadth-1?(horizontal?"S":"E"):"CENTER";
            std::string name;
            if(q.bridgeRaised) {
              if(!hinge)continue;
              name="RAISED_"+direction+"_"+side;
            } else if(q.width==1 && q.height==1)name="1x1_RAISE_"+direction;
            else if(hinge)name="RAISE_"+direction+"_"+side;
            else if(end)name="RAISE_"+direction+"_END_"+side;
            else name=std::string(horizontal?"WE_":"NS_")+side;
            if(const auto* s=idx.tile(family+"_"+name))r.tiles.push_back({lx,ly,*s});
            continue;
          }
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
      done("bridge.retract");
      if(!q.materialSolidColor.empty()){r.colorName=std::string(q.materialSolidColor);r.paletteRow=idx.paletteRow(r.colorName);}
      return r;
    }

    // --- furniture: the item pages' building members ---
    case BuildingKind::Bed:
      if(q.stage!=BuildingStage::Complete)return single("ITEM_BED", "furniture.bed.planned");
      return member("ITEM_BED", "", "furniture.bed");
    case BuildingKind::Chair:
    case BuildingKind::Table:
    case BuildingKind::Box:
    case BuildingKind::Cabinet: {
      const char* family=q.kind==BuildingKind::Chair?"ITEM_CHAIR":q.kind==BuildingKind::Table?"ITEM_TABLE":q.kind==BuildingKind::Box?"ITEM_BOX":"ITEM_CABINET";
      const char* rule=q.kind==BuildingKind::Chair?"furniture.chair":q.kind==BuildingKind::Table?"furniture.table":q.kind==BuildingKind::Box?"furniture.box":"furniture.cabinet";
      if(q.stage!=BuildingStage::Complete)return single(family,rule);
      const bool owned=q.constructionItemId>=0;
      fillTiles(q,classMember(idx,family,owned?materialClassOf(idx,q.constructionItemMaterial):cls,""),r);
      if(owned && !r.tiles.empty() && q.kind!=BuildingKind::Cabinet) {
        const bool legs=q.kind==BuildingKind::Chair || q.kind==BuildingKind::Table;
        const auto variant=legs?0:gemVariant(uint32_t(q.constructionItemId));
        if(const auto* overlay=idx.tile(std::string(family)+(legs?"_LEG_VARIANT":"_VARIANT"),variant))r.tiles.push_back({0,0,*overlay});
      }
      done(rule);
      if(owned) {
        colourise(idx,r,q.constructionItemMaterial);
        if(!q.constructionItemSolidColor.empty()){r.colorName=std::string(q.constructionItemSolidColor);r.paletteRow=idx.paletteRow(r.colorName);}
      }
      return r;
    }
    case BuildingKind::Coffin: {
      if(q.stage!=BuildingStage::Complete)return member("ITEM_COFFIN", "", "furniture.coffin");
      const bool owned=q.constructionItemId>=0;
      fillTiles(q,classMember(idx,"ITEM_COFFIN",owned?materialClassOf(idx,q.constructionItemMaterial):cls,
                             q.containedItemCount==1?"_UNUSED":""),r);
      done("furniture.coffin");
      if(owned) {
        colourise(idx,r,q.constructionItemMaterial);
        if(!q.constructionItemSolidColor.empty()){r.colorName=std::string(q.constructionItemSolidColor);r.paletteRow=idx.paletteRow(r.colorName);}
      }
      return r;
    }
    case BuildingKind::Statue: {
      std::string baseName;
      const auto* base=classMember(idx,"ITEM_STATUE",cls,"",&baseName);
      if (q.statue.quality==6) {
        if (const auto* artifact=idx.tile("ITEM_STATUE_ARTIFACT")) base=artifact;
      } else if (q.statue.quality>=0) {
        if (const auto* quality=idx.tile(baseName,size_t(q.statue.quality))) base=quality;
      }
      fillTiles(q,base,r);
      const SpriteRef* figure=nullptr;
      if (q.statue.subject==wm::ArtSubject::Creature && !q.statue.subjectRaw.empty()) {
        const auto key="STATUE_CREATURE:"+q.statue.subjectRaw;
        if (!q.statue.casteRaw.empty()) figure=idx.tile(key+":"+q.statue.casteRaw);
        if (!figure) figure=idx.tile(key);
      }
      if (figure) {
        for (int y=0;y<figure->h;++y) for (int x=0;x<figure->w;++x) {
          auto cell=*figure; cell.x+=x; cell.y+=y; cell.w=cell.h=1;
          r.tiles.push_back({x,y-figure->h+1,cell});
        }
      } else {
        std::string family="ITEM_DEFAULT_STATUE";
        if (q.statue.subject==wm::ArtSubject::Shape) family="ITEM_STATUE_GENERIC_SHAPE";
        else if (q.statue.subject==wm::ArtSubject::Tree) family="ITEM_STATUE_GENERIC_TREE";
        else if (q.statue.subject==wm::ArtSubject::Plant) family="ITEM_STATUE_GENERIC_SHRUB";
        else if (q.statue.subject==wm::ArtSubject::Event) {
          static constexpr const char* names[]={"EVENT","EVENT","DUEL","TRIUMPH","CIVILIZED",
              "STRIKE_DOWN","SHOT","ITEM_CREATION","BATTLE","SITE"};
          const size_t event=static_cast<size_t>(q.statue.event);
          family=std::string("ITEM_STATUE_GENERIC_")+names[event<std::size(names)?event:0];
        }
        if (const auto* top=idx.tile(family+"_TOP")) r.tiles.push_back({0,-1,*top});
        if (const auto* bottom=idx.tile(family+"_BOTTOM")) r.tiles.push_back({0,0,*bottom});
      }
      return done("furniture.statue");
    }
    case BuildingKind::Armorstand:
    case BuildingKind::Weaponrack:
      // DF uses the stone member for glass equipment furniture.
      fillTiles(q,classMember(idx,q.kind==BuildingKind::Armorstand?"ITEM_ARMOR_STAND":"ITEM_WEAPON_RACK",
                             cls==MaterialClass::Glass?MaterialClass::Stone:cls,
                             q.stage==BuildingStage::Complete && q.containedItemCount>1?"_FULL":"_EMPTY"),r);
      done(q.kind==BuildingKind::Armorstand?"furniture.armorstand":"furniture.weaponrack");
      if(!q.materialSolidColor.empty()) {
        r.colorName=std::string(q.materialSolidColor);r.paletteRow=idx.paletteRow(r.colorName);
      }
      return r;
    case BuildingKind::Door: {
      if(q.stage!=BuildingStage::Complete)return member("ITEM_DOOR", "", "furniture.door.planned");
      const bool owned=q.constructionItemId>=0;
      const auto itemClass=owned?materialClassOf(idx,q.constructionItemMaterial):cls;
      fillTiles(q, classMember(idx, "ITEM_DOOR", itemClass, "_CLOSED"), r);
      if(owned && !r.tiles.empty())
        if(const auto* overlay=idx.tile("ITEM_DOOR_VARIANT",gemVariant(uint32_t(q.constructionItemId))))r.tiles.push_back({0,0,*overlay});
      if (!r.tiles.empty() && (q.flags & wm::kBuildingForbidden))
        if (const SpriteRef* f = idx.tile("ITEM_DOOR_FORBIDDEN")) r.tiles.push_back({0, 0, *f});
      done("furniture.door");
      if(owned) {
        colourise(idx,r,q.constructionItemMaterial);
        if(!q.constructionItemSolidColor.empty()){r.colorName=std::string(q.constructionItemSolidColor);r.paletteRow=idx.paletteRow(r.colorName);}
      }
      return r;
    }
    case BuildingKind::Floodgate: return member("ITEM_FLOODGATE", "_CLOSED", "furniture.floodgate");
    case BuildingKind::Hatch: {
      if(q.stage!=BuildingStage::Complete)return single("ITEM_HATCH_COVER_GLASS", "furniture.hatch.planned");
      const bool owned=q.constructionItemId>=0;
      const auto itemClass=owned?materialClassOf(idx,q.constructionItemMaterial):cls;
      fillTiles(q, classMember(idx, "ITEM_HATCH_COVER", itemClass, "_CLOSED"), r);
      if(owned && !r.tiles.empty())
        if(const auto* overlay=idx.tile("ITEM_HATCH_COVER_VARIANT",gemVariant(uint32_t(q.constructionItemId))))r.tiles.push_back({0,0,*overlay});
      if (!r.tiles.empty() && (q.flags & wm::kBuildingForbidden))
        if (const SpriteRef* f = idx.tile("ITEM_HATCH_COVER_FORBIDDEN"))
          r.tiles.push_back({0, 0, *f});
      done("furniture.hatch");
      if(owned) {
        colourise(idx,r,q.constructionItemMaterial);
        if(!q.constructionItemSolidColor.empty()){r.colorName=std::string(q.constructionItemSolidColor);r.paletteRow=idx.paletteRow(r.colorName);}
      }
      return r;
    }
    case BuildingKind::GrateWall:
      if(q.stage!=BuildingStage::Complete)return single("ITEM_GRATE_METAL", "furniture.grate.wall.planned");
      return member("ITEM_GRATE", "_WALL_CLOSED", "furniture.grate.wall");
    case BuildingKind::GrateFloor:
      if(q.stage!=BuildingStage::Complete)return single("ITEM_GRATE_METAL_FLOOR_CLOSED", "furniture.grate.floor.planned");
      return member("ITEM_GRATE", "_FLOOR_CLOSED", "furniture.grate.floor");
    case BuildingKind::BarsVertical: {
      // Recorded native composites, ordered back-to-front. Unknown recordings
      // retain the historical south face without inventing adjacency facts.
      if(q.verticalBarsConnections<0)return single("BLD_VERTICAL_BARS_S", "bars.vertical.unknown");
      if(q.verticalBarsConnections>15)return r;
      static constexpr unsigned faces[]={12,3,3,3,12,5,6,7,12,9,10,11,12,13,14,15};
      const auto mask=faces[q.verticalBarsConnections];
      const char* names[]={"BLD_VERTICAL_BARS_N_BACK","BLD_VERTICAL_BARS_W","BLD_VERTICAL_BARS_E","BLD_VERTICAL_BARS_S"};
      const unsigned bits[]={1,4,8,2};
      for(int i=0;i<4;++i)if(mask&bits[i]) {
        const auto* sprite=idx.tile(names[i]);if(!sprite)return BuildingSprites{};
        r.tiles.push_back({0,0,*sprite});
      }
      if(mask&1) {
        const auto* upper=idx.tile("BLD_VERTICAL_BARS_N_UP");if(!upper)return BuildingSprites{};
        r.tiles.push_back({0,-1,*upper});
      }
      r.found=true;r.rule="bars.vertical.native";
      if(q.stage!=BuildingStage::Complete)colourise(idx,r,q.material);
      else if(q.constructionItemIsLog>=0)colourise(idx,r,q.constructionItemMaterial);
      return r;
    }
    case BuildingKind::BarsFloor:
    case BuildingKind::Support: {
      const auto* sprite=q.kind==BuildingKind::BarsFloor ? idx.tile("BLD_FLOOR_BARS") : classMember(idx,"BLD_SUPPORT",cls,"");
      fillTiles(q,sprite,r);r.found=!r.tiles.empty();r.rule=r.found?"structure.native":"missing-tile";
      if(q.stage!=BuildingStage::Complete)colourise(idx,r,q.material);
      else if(q.constructionItemIsLog>=0)colourise(idx,r,q.constructionItemMaterial);
      return r;
    }
    case BuildingKind::WindowGlass:
      single("ITEM_WINDOW_GLASS", "window.glass");
      if(!q.materialSolidColor.empty()) {
        r.colorName=std::string(q.materialSolidColor);r.paletteRow=idx.paletteRow(r.colorName);
      }
      return r;
    case BuildingKind::WindowGem: return single("ITEM_WINDOW_GEM", "window.gem");
    case BuildingKind::Well: {
      const char* name=q.stage!=BuildingStage::Complete || q.wellChainIsMetal<0 ? "BLD_WELL" : q.wellChainIsMetal==1 ? "BLD_WELL_WITH_CHAIN" : "BLD_WELL_WITH_ROPE";
      fillTiles(q,idx.tile(name),r);r.found=!r.tiles.empty();r.rule=r.found?"well.native":"missing-tile";
      return r; // Native well artwork retains its painted palette.
    }
    case BuildingKind::ArcheryTarget:
      fillTiles(q,classMember(idx,"BLD_ARCHERY_TARGET",cls==MaterialClass::Glass?MaterialClass::Metal:cls,""),r);
      r.found=!r.tiles.empty();r.rule=r.found?"archery-target":"missing-tile";
      return r; // Native target artwork keeps its painted palette at every stage.
    case BuildingKind::Chain:
      fillTiles(q,idx.tile(cls == MaterialClass::Metal ? "BLD_CHAIN_METAL" : "BLD_CHAIN_ROPE"),r);
      r.found=!r.tiles.empty();r.rule="chain";
      return r; // Native restraints retain the painted palette in both stages.
    case BuildingKind::Cage:
    case BuildingKind::AnimalTrap: {
      const bool cage=q.kind==BuildingKind::Cage;
      const char* family=cage?"ITEM_CAGE":"ITEM_ANIMAL_TRAP";
      const char* rule=cage?"cage":"animal-trap";
      if(q.stage!=BuildingStage::Complete)return single(cage?"ITEM_CAGE_METAL":"ITEM_ANIMAL_TRAP_METAL",rule);
      const bool owned=q.constructionItemId>=0;
      const auto itemClass=owned?materialClassOf(idx,q.constructionItemMaterial):cls;
      fillTiles(q,classMember(idx,family,cage?itemClass:MaterialClass::Metal,""),r);done(rule);
      if(owned) {
        colourise(idx,r,q.constructionItemMaterial);
        if(!q.constructionItemSolidColor.empty()){r.colorName=std::string(q.constructionItemSolidColor);r.paletteRow=idx.paletteRow(r.colorName);}
      }
      return r;
    }
    case BuildingKind::Slab: {
      // Native unused intents1..5 and absent items retain raw blank artwork.
      const bool known=q.stage==BuildingStage::Complete && q.constructionItemIsLog>=0 &&
          (q.slabEngraving==-1 || q.slabEngraving==0 || (q.slabEngraving>=6 && q.slabEngraving<=26));
      const std::string name=slabArtworkName(known?q.slabEngraving:-1);
      fillTiles(q,idx.tile(name),r);r.found=!r.tiles.empty();r.rule=r.found?"slab.native":"missing-tile";
      if(known)colourise(idx,r,q.constructionItemMaterial);
      return r;
    }
    case BuildingKind::TractionBench: {
      // The supported install aliases CHAIN/ROPE artwork. DF's glass uses metal.
      const char* c=cls==MaterialClass::Stone?"STONE":cls==MaterialClass::Wood?"WOODEN":"METAL";
      fillTiles(q,idx.tile(std::string("ITEM_TRACTION_BENCH_")+c+"_ROPE"),r);
      r.found=!r.tiles.empty();r.rule="traction-bench";return r;
    }
    case BuildingKind::Bookcase: return tool("ITEM_TOOL_BOOKCASE", "", "tool.bookcase");
    case BuildingKind::DisplayFurniture: return tool("ITEM_TOOL_DISPLAY_CASE", "", "tool.display-case");
    case BuildingKind::OfferingPlace: return tool("ITEM_TOOL_ALTAR", "", "tool.altar");
    case BuildingKind::NestBox: return tool("ITEM_TOOL_NEST_BOX", "", "tool.nest-box");
    case BuildingKind::Hive: return tool("ITEM_TOOL_HIVE", "HIVE_BLD", "tool.hive");
    case BuildingKind::Instrument: {
      const bool complete=q.stage==BuildingStage::Complete;
      const bool known=q.instrumentFamily>=0 && q.instrumentFamily<=3 && q.instrumentPlaced>=0;
      const char* families[]={"KEYBOARD","STRINGED","WIND","PERCUSSION"};
      const auto name=std::string("ITEM_INSTRUMENT_")+families[complete && known?q.instrumentFamily:0]+
          (complete && known && q.instrumentPlaced==0?"_HANDHELD":"_BUILDING");
      single(name.c_str(), "instrument.native");
      r.paletteRow=-1;
      if(!complete)colourise(idx,r,q.material);
      else if(known)colourise(idx,r,q.constructionItemMaterial);
      return r;
    }
    case BuildingKind::Nest: return single("NATURAL_NEST", "nest");
    case BuildingKind::Weapon: {
      const bool complete=q.stage==BuildingStage::Complete;
      if(complete && q.weaponCount<0)return single("UPRIGHT_WEAPON_RETRACTED_1", "upright-weapon.unknown");
      const int count=std::clamp(q.weaponCount,1,10);
      if(!complete || q.weaponCount==0 || q.weaponRetracted!=0) {
        const auto name=std::string("UPRIGHT_WEAPON_RETRACTED_")+std::to_string(!complete || q.weaponCount==0?10:count);
        fillTiles(q,idx.tile(name),r);
      } else if(const auto* definition=idx.itemDef(q.constructionWeaponRaw)) {
        const auto prefix=std::string("UPRIGHT_")+std::to_string(count);
        const auto top=definition->variants.find(prefix+"T");
        const auto bottom=definition->variants.find(prefix+"B");
        if(top!=definition->variants.end() && bottom!=definition->variants.end() && top->second.valid() && bottom->second.valid()) {
          // Use the declared lower spike artwork, including counts5..10:
          // the maintainer approved correcting DF53.16's selector-mask bug.
          r.tiles.push_back({0,0,bottom->second});
          r.tiles.push_back({0,-1,top->second});r.tiles.back().foreground=true;
          colourise(idx,r,q.constructionItemMaterial);
          if(!q.constructionItemSolidColor.empty()) {
            r.colorName=std::string(q.constructionItemSolidColor);r.paletteRow=idx.paletteRow(r.colorName);
          }
        }
      }
      r.found=!r.tiles.empty();r.rule=r.found?"upright-weapon.native":"missing-tile";
      if(!complete){r.stageArt=true;r.plannedHalfAlpha=true;}
      return r;
    }

    // --- traps by trap_type ---
    case BuildingKind::Trap:
      switch (q.subtype) {
        case 0: case 1: case 2: case 3: {
          const bool complete=q.stage==BuildingStage::Complete;
          // A known completed trap without a mechanism intentionally has no art.
          // Mark the selection resolved so the host does not substitute a glyph.
          if(complete && q.containedItemCount>=0 && q.constructionItemIsLog<0) {
            r.found=true;r.rule="trap.no-mechanism";return r;
          }
          const bool active=q.trapState>0;
          const bool loaded=q.subtype>=2 && complete && q.containedItemCount>=2 && !active;
          std::string name;
          if(q.subtype==0)name=complete && active?"LEVER_PULLED":"LEVER_SET";
          else if(q.subtype==1) {
            const bool pressed=complete && (active || q.trapReadyTimeout>0 || q.trapFillTimer>0);
            name=pressed?"TRAP_PLATE_PRESSED":"TRAP_PLATE_READY";
            if(complete && q.trapTriggerFlags>=0) {
              if(q.trapTriggerFlags&4)name+="_MAGMA";
              else if(q.trapTriggerFlags&2)name+="_WATER";
              else if(q.trapTriggerFlags&32)name+="_MINECART";
            }
          } else {
            name=q.subtype==2?"TRAP_CAGE":"TRAP_STONE";
            if(complete && q.containedItemCount>=0 && !loaded)name+="_UNLOADED";
          }
          fillTiles(q,idx.tile(name),r);r.found=!r.tiles.empty();r.rule=r.found?"trap.native":"missing-tile";
          if(loaded) {
            if(const auto* top=idx.tile(q.subtype==2?"TRAP_CAGE_TOP":"TRAP_STONE_TOP"))
              r.tiles.push_back({0,-1,*top,true,true});
          }
          if(!complete){r.plannedHalfAlpha=true;r.stageArt=true;}
          else if(q.constructionItemIsLog>=0) {
            colourise(idx,r,q.constructionItemMaterial);
            if(!q.constructionItemSolidColor.empty()) {
              r.colorName=std::string(q.constructionItemSolidColor);r.paletteRow=idx.paletteRow(r.colorName);
            }
          } else if(q.containedItemCount<0)colourise(idx,r,q.material); // older recordings
          return r;
        }
        case 4: {
          const bool complete=q.stage==BuildingStage::Complete;
          const SpriteRef* weapon=nullptr;
          if(complete && q.containedItemCount>=2 && q.trapState>=-128 && q.trapState<=0 && q.weaponCount>0) {
            if(const auto* definition=idx.itemDef(q.constructionWeaponRaw)) {
              const auto variant=definition->variants.find("WEAPON_TRAP");
              if(variant!=definition->variants.end() && variant->second.valid())weapon=&variant->second;
            }
          }
          fillTiles(q,weapon?weapon:idx.tile("TRAP_WEAPON"),r);
          r.found=!r.tiles.empty();r.rule=r.found?"trap.weapon.native":"missing-tile";
          if(!complete){r.stageArt=true;r.plannedHalfAlpha=true;}
          else if(weapon) {
            colourise(idx,r,q.constructionItemMaterial);
            if(!q.constructionItemSolidColor.empty()) {
              r.colorName=std::string(q.constructionItemSolidColor);r.paletteRow=idx.paletteRow(r.colorName);
            }
          }
          return r;
        }
        case 5: {
          // Native completed stops follow underlying track; single-ended track
          // uses straight art. Planned stops and bare floors use the crossing.
          static constexpr const char* suffix[]={"NSWE","NS","NS","NS","WE","NE","SE","NSE",
            "WE","NW","SW","NSW","WE","NWE","SWE","NSWE"};
          const unsigned mask=q.stage==wm::BuildingStage::Complete ? q.completedTrack&15 : 0;
          const bool complete=q.stage==wm::BuildingStage::Complete;
          const auto name=std::string(complete && q.constructionItemIsLog==1?"TRACK_STOP_WOOD_":"TRACK_STOP_STONE_")+suffix[mask];
          fillTiles(q,idx.tile(name),r);
          r.found=!r.tiles.empty();r.rule=r.found?"trap.track-stop":"missing-tile";
          if(complete && q.constructionItemIsLog!=-1)colourise(idx,r,q.constructionItemMaterial);
          return r; // Planned and unknown-item art retain the painted palette.
        }
        default: break;
      }
      r.rule = "trap.unknown-subtype";
      return r;

    // --- machines ---
    case BuildingKind::AxleHorizontal:
    case BuildingKind::AxleVertical:
    case BuildingKind::GearAssembly: {
      const bool vertical=q.horizontalAxleVertical<0 ? q.width<=q.height : q.horizontalAxleVertical==1;
      const char* name=q.kind==BuildingKind::GearAssembly ? "GEAR_ASSEMBLY_1" : q.kind==BuildingKind::AxleVertical ? "AXLE_VERTICAL_1"
          : vertical ? "AXLE_HORIZONTAL_NS_1" : "AXLE_HORIZONTAL_WE_1";
      fillTiles(q,idx.tile(name),r);r.found=!r.tiles.empty();r.rule=r.found?"machine.transmission":"missing-tile";
      // The presentation composites uncolored axle fittings over these shafts.
      if(q.stage==BuildingStage::Complete && q.constructionItemIsLog>=0)colourise(idx,r,q.constructionItemMaterial);
      return r;
    }
    case BuildingKind::Rollers: {
      // DF53.16 draw: per-cell track shape, first item kind/material, and
      // direction-dependent absolute coordinate against linked machine position.
      static constexpr const char* suffix[]={"NSWE","NS","NS","NS","WE","NE","SE","NSE",
        "WE","NW","SW","NSW","WE","NWE","SWE","NSWE"};
      const bool complete=q.stage==BuildingStage::Complete;
      const int direction=q.rollerDirection;
      const bool knownDirection=direction>=0 && direction<=3;
      const int phase=q.rollerMachinePosition==-129 ? 0 : q.rollerMachinePosition%3;
      const Footprint footprint{q};
      for(int y=0;y<q.height;++y)for(int x=0;x<q.width;++x) {
        if(!footprint.occupies(x,y))continue;
        const size_t cell=size_t(y)*size_t(q.width)+size_t(x);
        const unsigned mask=q.completedTracks && cell<q.completedTracks->size() ? (*q.completedTracks)[cell]&15 : 0;
        const char* shape=complete ? suffix[mask] : (knownDirection && (direction&1) ? "WE" : "NS");
        int frame=1;
        if(complete && knownDirection) {
          const int coordinate=(direction&1) ? q.x1+x : q.y1+y;
          const int target=direction==1 || direction==2 ? phase : 2-phase;
          frame=coordinate%3==target ? 1 : 2;
        }
        const auto name=std::string(complete && q.constructionItemIsLog==1 ? "ROLLERS_WOOD_" : "ROLLERS_STONE_")+
          shape+"_"+std::to_string(frame);
        if(const auto* sprite=idx.tile(name))r.tiles.push_back({x,y,*sprite});
      }
      r.found=!r.tiles.empty();r.rule=r.found?"machine.rollers":"missing-tile";
      if(complete && q.constructionItemIsLog!=-1)colourise(idx,r,q.constructionItemMaterial);
      return r;
    }

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

  const bool occupied = q.containedCount != UINT32_MAX && q.containedCount > 0;
  const bool liquid = q.containedKind == ItemKind::Drink || q.containedKind == ItemKind::LiquidMisc;
  auto contentsOverlay = [&](const std::string& name, bool recolor = true) {
    if (const auto* sprite = idx.tile(name))
      r.overlays.push_back({*sprite,recolor ? idx.paletteRow(q.containedColor.empty() ? idx.materialColorName(q.containedMaterial,liquid) : q.containedColor) : -1});
  };
  auto binTop = [&]() -> const char* {
    switch (q.containedKind) {
      case ItemKind::Bar: return q.containedMaterial.find("COAL") != std::string_view::npos ? "COAL" : "BARS";
      case ItemKind::Blocks: return "BLOCKS";
      case ItemKind::SmallGem: case ItemKind::Gem: case ItemKind::Rough: return "GEMS";
      case ItemKind::Armor: case ItemKind::Helm: case ItemKind::Gloves: case ItemKind::Shoes: case ItemKind::Pants:
        return materialClassOf(idx,q.containedMaterial)==MaterialClass::Metal ? "ARMOR_METAL" :
          q.containedMaterial.find(":LEATHER")!=std::string_view::npos ? "ARMOR_LEATHER" : "CLOTHING";
      case ItemKind::Weapon: case ItemKind::Shield: return "WEAPONS";
      case ItemKind::Ammo: return "AMMO";
      case ItemKind::TrapComp: return "TRAP_COMPS";
      case ItemKind::TrapParts: return "MECHANISMS";
      case ItemKind::Cloth: return "CLOTH";
      case ItemKind::SkinTanned: return "LEATHER";
      case ItemKind::Chain: return materialClassOf(idx,q.containedMaterial)==MaterialClass::Metal ? "CHAINS" : "ROPES";
      case ItemKind::PowderMisc: return "POWDERS";
      case ItemKind::Bag: return "BAGS";
      case ItemKind::Book: return "BOOKS";
      case ItemKind::Sheet: return "SHEETS";
      case ItemKind::Coin: return "COINS";
      case ItemKind::Figurine: case ItemKind::Amulet: case ItemKind::Scepter: case ItemKind::Crown:
      case ItemKind::Ring: case ItemKind::Earring: case ItemKind::Bracelet: case ItemKind::Totem: return "CRAFTS";
      default: return "";
    }
  };

  switch (q.kind) {
    case ItemKind::Bar: {
      auto it = idx.barsGraphics.find(std::string(rawId));
      if (it != idx.barsGraphics.end()) return done(&it->second, "bar.material");
      if (q.material.find(":SOAP") != std::string_view::npos) return single("ITEM_BARS_SOAP", "bar.soap");
      return single("ITEM_BARS", "bar");
    }
    case ItemKind::SmallGem: return single("ITEM_GEMS", "gem.small.generic");
    case ItemKind::Gem: return single("ITEM_LARGE_GEM", "gem.large.generic");
    case ItemKind::Rough: {
      auto it = idx.roughGemGraphics.find(std::string(rawId));
      if (it != idx.roughGemGraphics.end()) return done(&it->second, "gem.material");
      return single("ITEM_ROUGH_GEM", "gem.rough");
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
    // Loose statues use the native wrapped transport artwork. The installed
    // building draws its quality pedestal and depicted subject separately.
    case ItemKind::Statue: return single("ITEM_STATUE", "item.statue");
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
    case ItemKind::Instrument: {
      if(q.instrumentFamily>=0 && q.instrumentFamily<=3 && q.instrumentPlaced>=0 && q.instrumentPlaced<=1) {
        const char* families[]={"KEYBOARD","STRINGED","WIND","PERCUSSION"};
        const auto name=std::string("ITEM_INSTRUMENT_")+families[q.instrumentFamily]+
            (q.instrumentPlaced?"_BUILDING":"_HANDHELD");
        return single(name.c_str(), "instrument.native");
      }
      // Older item streams lack generated definition facts. Retain their legacy
      // approximation until the map-item contract supplies those facts too.
      return single("ITEM_INSTRUMENT_STRINGED_HANDHELD", "instrument.approx");
    }
    case ItemKind::Toy: return def("", "ITEM_TOY", "toy");
    case ItemKind::Window: return single("ITEM_WINDOW_GLASS", "window");
    case ItemKind::Cage: return member("ITEM_CAGE", "", "cage");
    case ItemKind::Barrel: {
      const std::string material=cls==MaterialClass::Metal ? "METAL" : "WOOD";
      single(("ITEM_BARREL_"+material+(occupied ? (liquid ? "_LIQUID" : "_ITEM") : "_EMPTY")).c_str(),"barrel");
      if (occupied && liquid) contentsOverlay("LIQUID_FOR_BARREL_"+material);
      else if (occupied) {
        const char* top="";
        switch(q.containedKind) {
          case ItemKind::Food: top="MEAL"; break;
          case ItemKind::Cheese: top="CHEESE"; break;
          case ItemKind::Meat: top="MEAT"; break;
          case ItemKind::Fish: case ItemKind::FishRaw: top="FISH"; break;
          case ItemKind::Bag: top="BAG"; break;
          case ItemKind::Plant: case ItemKind::PlantGrowth: top="PLANT"; break;
          default: break;
        }
        if (*top) contentsOverlay(std::string("ITEM_BARREL_TOP_")+top);
      }
      return r;
    }
    case ItemKind::Bucket:
      metalOrWood("ITEM_BUCKET", "bucket");
      if (occupied && liquid) contentsOverlay(cls==MaterialClass::Metal ? "LIQUID_FOR_BUCKET_METAL" : "LIQUID_FOR_BUCKET_WOOD");
      return r;
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
    case ItemKind::Bag:
      single(occupied ? "ITEM_BAG_IN_USE" : "ITEM_BAG_EMPTY","bag");
      if (!r.found) single("ITEM_BAG","bag");
      if (occupied) {
        if (q.containedKind==ItemKind::Seeds) contentsOverlay("SEEDS_FOR_BAG");
        else if (q.containedKind==ItemKind::PowderMisc) contentsOverlay("POWDER_FOR_BAG");
        else if (q.containedKind==ItemKind::PlantGrowth) contentsOverlay("LEAVES_FOR_BAG");
      }
      return r;
    case ItemKind::Bin:
      single((std::string("ITEM_BIN_")+(cls==MaterialClass::Metal ? "METAL" : "WOOD")+
          (occupied ? "_IN_USE" : "_EMPTY")).c_str(),"bin");
      if (occupied && *binTop()) contentsOverlay(std::string("ITEM_BIN_TOP_")+binTop());
      return r;
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
    case ItemKind::BoltThrowerParts: return single("ITEM_BOLT_THROWER_PARTS", "siege-parts");
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
    case ItemKind::Slab: {
      single(slabArtworkName(q.slabEngraving).c_str(), "slab.native");
      if(q.slabEngraving>=1 && q.slabEngraving<=5)r.paletteRow=-1;
      return r;
    }
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
