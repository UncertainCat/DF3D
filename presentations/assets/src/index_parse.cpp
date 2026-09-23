#include <algorithm>
#include <charconv>
#include <cstdio>

#include "df3d_assets/asset_index.h"
#include "df3d_assets/raw_tokens.h"
#include "df3d_assets/steam_install.h"

namespace df3d::assets {

// --- lookups ---

int AssetIndex::pageIndex(std::string_view name) const {
  auto it = pageByName.find(std::string(name));
  return it == pageByName.end() ? -1 : it->second;
}

const SpriteRef* AssetIndex::tile(std::string_view name, size_t variant) const {
  auto it = tileGraphics.find(std::string(name));
  if (it == tileGraphics.end() || it->second.empty()) return nullptr;
  return &it->second[std::min(variant, it->second.size() - 1)];
}

const BuildingLayout* AssetIndex::layout(std::string_view name) const {
  auto it = buildingLayouts.find(std::string(name));
  return it == buildingLayouts.end() ? nullptr : &it->second;
}

const ItemDefGraphics* AssetIndex::itemDef(std::string_view rawId) const {
  auto it = itemDefs.find(std::string(rawId));
  return it == itemDefs.end() ? nullptr : &it->second;
}

int BuildingLayout::stageFor(int stage) const {
  if (stages.empty()) return kLayoutNoStage - 2;
  auto it = stages.find(stage);
  if (it != stages.end()) return it->first;
  // The highest stage below the requested one (a workshop at stage 2 with
  // only 3 and 1 defined shows 1), else the lowest present.
  auto ub = stages.upper_bound(stage);
  if (ub != stages.begin()) return std::prev(ub)->first;
  return stages.begin()->first;
}

const SpriteRef* BuildingLayout::tile(int stage, int lx, int ly) const {
  if (lx < 0 || ly < 0 || lx >= width || ly >= height) return nullptr;
  const int st = stageFor(stage);
  auto it = stages.find(st);
  if (it == stages.end()) return nullptr;
  const SpriteRef& s = it->second[static_cast<size_t>(ly) * static_cast<size_t>(width) +
                                  static_cast<size_t>(lx)];
  return s.valid() ? &s : nullptr;
}

PixelRect AssetIndex::pixels(const SpriteRef& s) const {
  PixelRect r;
  const TilePage* p = page(s.page);
  if (!p || !s.valid()) return r;
  r.page = s.page;
  r.px = s.x * p->tileW;
  r.py = s.y * p->tileH;
  r.pw = s.w * p->tileW;
  r.ph = s.h * p->tileH;
  return r;
}

std::string_view AssetIndex::materialRawId(std::string_view token) {
  const size_t c1 = token.find(':');
  if (c1 == std::string_view::npos) return token;  // builtin: WATER, ASH
  const size_t c2 = token.find(':', c1 + 1);
  return token.substr(c1 + 1, c2 == std::string_view::npos ? std::string_view::npos : c2 - c1 - 1);
}

namespace {

const MaterialDef* findMaterial(const AssetIndex& idx, std::string_view token) {
  const size_t c1 = token.find(':');
  if (c1 == std::string_view::npos) return nullptr;
  const std::string_view kind = token.substr(0, c1);
  const std::string_view rest = token.substr(c1 + 1);
  if (kind == "INORGANIC") {
    auto it = idx.inorganics.find(std::string(rest));
    return it == idx.inorganics.end() ? nullptr : &it->second;
  }
  if (kind == "CREATURE") {
    const size_t c2=rest.find(':');
    if(c2==std::string_view::npos) return nullptr;
    std::string species(rest.substr(0,c2));
    const std::string substance(rest.substr(c2+1));
    for(int depth=0;depth<16;++depth) {
      const auto creature=idx.creatureMaterials.find(species);
      if(creature!=idx.creatureMaterials.end()) {
        const auto material=creature->second.find(substance);
        if(material!=creature->second.end())return &material->second;
      }
      const auto parent=idx.creatureMaterialParents.find(species);
      if(parent==idx.creatureMaterialParents.end())break;
      species=parent->second;
    }
    return nullptr;
  }
  if (kind == "PLANT") {
    const size_t c2 = rest.find(':');
    if (c2 == std::string_view::npos) return nullptr;
    auto pit = idx.plantMaterials.find(std::string(rest.substr(0, c2)));
    if (pit == idx.plantMaterials.end()) return nullptr;
    auto mit = pit->second.find(std::string(rest.substr(c2 + 1)));
    return mit == pit->second.end() ? nullptr : &mit->second;
  }
  return nullptr;
}

}  // namespace

std::string_view AssetIndex::materialColorName(std::string_view token) const {
  const MaterialDef* m = findMaterial(*this, token);
  return m ? std::string_view(m->solidColor) : std::string_view();
}

std::string_view AssetIndex::materialSpatterFamily(std::string_view token, bool liquid) const {
  const auto* mat=findMaterial(*this,token);
  if(!mat)return {};
  if(mat->mapDescriptor=="ICHOR_MAP_DESCRIPTOR")return "SPATTER_BLOOD_ICHOR";
  if(mat->mapDescriptor=="GOO_MAP_DESCRIPTOR")return "SPATTER_BLOOD_GOO";
  if(mat->mapDescriptor!="BLOOD_MAP_DESCRIPTOR")return {};
  const auto color=colors.find(liquid && !mat->liquidColor.empty() ? mat->liquidColor : mat->solidColor);
  if(color!=colors.end()) {
    const auto c=color->second;
    if(int(c.g)>int(c.r)*3/2 && int(c.b)>int(c.r)*3/2 &&
       int(c.g)*5>int(c.b)*3 && int(c.b)*5>int(c.g)*3)return "SPATTER_BLOOD_CYAN";
    if(int(c.b)>int(c.g)*3/2 && int(c.r)>int(c.g)*3/2 &&
       int(c.b)*5>int(c.r)*3 && int(c.r)*5>int(c.b)*3)return "SPATTER_BLOOD_MAGENTA";
  }
  return "SPATTER_BLOOD_RED";
}

std::optional<Rgb> AssetIndex::materialColor(std::string_view token) const {
  const std::string_view name = materialColorName(token);
  if (name.empty()) return std::nullopt;
  auto it = colors.find(std::string(name));
  if (it == colors.end()) return std::nullopt;
  return it->second;
}

int AssetIndex::paletteRow(std::string_view color) const {
  if (!palette || color.empty()) return -1;
  auto it = palette->rows.find(std::string(color));
  return it == palette->rows.end() ? -1 : it->second;
}

uint32_t AssetIndex::materialFlags(std::string_view token) const {
  const MaterialDef* m = findMaterial(*this, token);
  return m ? m->flags : 0u;
}

// --- parsing ---

namespace {

int pageFor(AssetIndex& idx, std::string_view name,
            std::unordered_map<std::string, int>* pending) {
  const int p = idx.pageIndex(name);
  if (p >= 0 || !pending) return p;
  // Graphics may reference a page defined in a file parsed later: reserve
  // a placeholder page that finalizeIndex() resolves or reports.
  auto it = pending->find(std::string(name));
  if (it != pending->end()) return it->second;
  TilePage ph;
  ph.name = std::string(name);
  idx.pages.push_back(ph);
  const int id = static_cast<int>(idx.pages.size()) - 1;
  (*pending)[ph.name] = id;
  return id;
}

bool ints(const std::vector<std::string>& a, size_t first, size_t count, int* out) {
  if (first + count > a.size()) return false;
  for (size_t i = 0; i < count; ++i)
    if (!parseInt(a[first + i], out[i])) return false;
  return true;
}

// PAGE:x:y (3 args) -> sprite; used by plant tokens and TILE_GRAPHICS.
std::optional<SpriteRef> spriteAt(AssetIndex& idx, const std::vector<std::string>& a,
                                  size_t first, std::unordered_map<std::string, int>* pending) {
  int xy[2];
  if (first >= a.size() || !ints(a, first + 1, 2, xy)) return std::nullopt;
  SpriteRef s;
  s.page = pageFor(idx, a[first], pending);
  s.x = xy[0];
  s.y = xy[1];
  return s;
}

void applyMaterialToken(MaterialDef& m, const RawToken& t) {
  const std::string& n = t.name();
  if (n == "STATE_COLOR" && t.argc() >= 3) {
    const std::string_view st = t.arg(1);
    if (st == "ALL_SOLID" || st == "ALL" || st == "SOLID") m.solidColor = t.args[2];
    if (st == "LIQUID" || st == "ALL") m.liquidColor = t.args[2];
  } else if (n == "BLOOD_MAP_DESCRIPTOR" || n == "ICHOR_MAP_DESCRIPTOR" || n == "GOO_MAP_DESCRIPTOR") {
    m.mapDescriptor=n;
  } else if (n == "DISPLAY_COLOR" && t.argc() >= 4) {
    parseInt(t.args[1], m.displayFg);
    parseInt(t.args[2], m.displayBg);
    parseInt(t.args[3], m.displayBright);
  } else if (n == "IS_METAL") {
    m.flags |= kMatMetal;
  } else if (n == "IS_STONE") {
    m.flags |= kMatStone;
  } else if (n == "IS_GEM") {
    m.flags |= kMatGem;
  } else if (n == "SOIL") {
    m.flags |= kMatSoil;
  } else if (n == "SOIL_SAND") {
    m.flags |= kMatSand;
  } else if (n == "IS_GLASS") {
    m.flags |= kMatGlass;
  } else if (n == "WOOD") {
    m.flags |= kMatWood;
  }
}

MaterialDef fromTemplate(const AssetIndex& idx, std::string_view tmpl) {
  MaterialDef m;
  auto it = idx.materialTemplates.find(std::string(tmpl));
  if (it != idx.materialTemplates.end()) m = it->second;
  m.templateName = std::string(tmpl);
  return m;
}

// Places one tile of a building layout, growing the grid as needed (the
// raws list tiles in no guaranteed order; every stage grid is kept at
// the layout's full extent).
void placeLayoutTile(AssetIndex& idx, const std::string& name, int stage, int lx, int ly,
                     const SpriteRef& s) {
  if (lx < 0 || ly < 0 || lx > 15 || ly > 15) return;
  BuildingLayout& l = idx.buildingLayouts[name];
  const int w = std::max(l.width, lx + 1), h = std::max(l.height, ly + 1);
  if (w != l.width || h != l.height) {
    for (auto& [st, grid] : l.stages) {
      std::vector<SpriteRef> g(static_cast<size_t>(w) * static_cast<size_t>(h));
      for (int y = 0; y < l.height; ++y)
        for (int x = 0; x < l.width; ++x)
          g[static_cast<size_t>(y) * static_cast<size_t>(w) + static_cast<size_t>(x)] =
              grid[static_cast<size_t>(y) * static_cast<size_t>(l.width) + static_cast<size_t>(x)];
      grid = std::move(g);
    }
    l.width = w;
    l.height = h;
  }
  auto& grid = l.stages[stage];
  if (grid.empty()) grid.resize(static_cast<size_t>(w) * static_cast<size_t>(h));
  SpriteRef& slot = grid[static_cast<size_t>(ly) * static_cast<size_t>(w) + static_cast<size_t>(lx)];
  if (!slot.valid()) {  // first definition wins, as for tile names
    slot = s;
    idx.stats.layoutTiles += 1;
  }
}

// Item family tokens of graphics_items.txt / graphics_containers.txt:
// WEAPON, ARMOR, TOOL, AMMO, FOOD, TOY, TRAPCOMP, SHIELD, HELM, PANTS,
// GLOVES, SHOES, SIEGEAMMO, ADD_TOOL, PROCEDURAL_ITEM (+ BOULDER, BARS,
// ROUGH_GEM handled apart). `<FAMILY>_GRAPHICS` opens a block for an
// itemdef; `<FAMILY>_GRAPHICS_<VARIANT>` adds a variant to the block (or
// to the itemdef it names itself).
bool itemFamilyToken(std::string_view n, std::string& family, std::string& variant) {
  static const char* const kFamilies[] = {"WEAPON", "ARMOR", "TOOL", "AMMO", "FOOD", "TOY",
                                          "TRAPCOMP", "SHIELD", "HELM", "PANTS", "GLOVES",
                                          "SHOES", "SIEGEAMMO", "ADD_TOOL", "PROCEDURAL_ITEM"};
  for (const char* f : kFamilies) {
    const std::string head = std::string(f) + "_GRAPHICS";
    if (n.compare(0, head.size(), head) != 0) continue;
    if (n.size() == head.size()) {
      family = f;
      variant.clear();
      return true;
    }
    if (n[head.size()] == '_') {
      family = f;
      variant = std::string(n.substr(head.size() + 1));
      return true;
    }
  }
  return false;
}

// Finds `PAGE:x:y` inside an argument list (the page name is any
// non-numeric argument followed by two integers); returns the index of
// the page argument or npos.
size_t findSpriteArgs(const std::vector<std::string>& a, size_t first) {
  for (size_t i = first; i + 2 < a.size(); ++i) {
    int dummy;
    if (parseInt(a[i], dummy)) continue;
    if (parseInt(a[i + 1], dummy) && parseInt(a[i + 2], dummy)) return i;
  }
  return std::string::npos;
}

}  // namespace

std::optional<SpriteRef> parseSpriteArgs(const AssetIndex& index,
                                         const std::vector<std::string>& args, size_t first,
                                         std::unordered_map<std::string, int>* pendingPages) {
  if (first >= args.size()) return std::nullopt;
  AssetIndex& idx = const_cast<AssetIndex&>(index);  // placeholder pages only
  SpriteRef s;
  s.page = pageFor(idx, args[first], pendingPages);
  size_t i = first + 1;
  int v[4];
  if (i < args.size() && args[i] == "LARGE_IMAGE") {
    if (!ints(args, i + 1, 4, v)) return std::nullopt;
    s.x = v[0];
    s.y = v[1];
    s.w = std::max(1, v[2] - v[0] + 1);
    s.h = std::max(1, v[3] - v[1] + 1);
    return s;
  }
  if (!ints(args, i, 2, v)) return std::nullopt;
  s.x = v[0];
  s.y = v[1];
  // Statue-style bare rectangle: x1:y1:x2:y2 with both extra args numeric.
  if (ints(args, i + 2, 2, v + 2)) {
    s.w = std::max(1, v[2] - v[0] + 1);
    s.h = std::max(1, v[3] - v[1] + 1);
  }
  return s;
}

size_t ingestRawText(AssetIndex& index, std::string_view text, const std::string& graphicsDir,
                     const std::string& sourceName, std::vector<std::string>* diagnostics) {
  const std::vector<RawToken> tokens = tokenizeRaw(text);
  const std::string object = rawObjectType(tokens);
  index.stats.rawFiles += 1;
  auto diag = [&](const RawToken& t, const std::string& msg) {
    if (diagnostics)
      diagnostics->push_back(sourceName + ":" + std::to_string(t.line) + ": " + msg);
  };
  std::unordered_map<std::string, int>& pendingPages = index.pendingPages;
  std::unordered_map<std::string, int>* pending = &pendingPages;
  size_t consumed = 0;

  if (object == "TILE_PAGE") {
    index.stats.tilePageFiles += 1;
    TilePage* cur = nullptr;
    bool curIsDuplicate = false;
    for (const RawToken& t : tokens) {
      const std::string& n = t.name();
      if (n == "TILE_PAGE" && t.argc() >= 2) {
        const std::string& name = t.args[1];
        auto it = index.pageByName.find(name);
        if (it != index.pageByName.end()) {
          // Vanilla repeats INTERFACE_BITS_STOCKPILES; the first wins.
          index.stats.duplicatePages += 1;
          curIsDuplicate = true;
          cur = nullptr;
          continue;
        }
        curIsDuplicate = false;
        auto pit = pendingPages.find(name);
        if (pit != pendingPages.end()) {
          cur = &index.pages[static_cast<size_t>(pit->second)];
          index.pageByName[name] = pit->second;
          pendingPages.erase(pit);
        } else {
          index.pages.push_back(TilePage{});
          cur = &index.pages.back();
          cur->name = name;
          index.pageByName[name] = static_cast<int>(index.pages.size()) - 1;
        }
        index.stats.tilePages += 1;
        ++consumed;
      } else if (!cur) {
        if (!curIsDuplicate && n != "OBJECT") diag(t, "token outside a TILE_PAGE: " + n);
      } else if (n == "FILE" && t.argc() >= 2) {
        cur->file = t.args[1];
        cur->absPath = joinPath(graphicsDir, cur->file);
        ++consumed;
      } else if (n == "TILE_DIM" && t.argc() >= 3) {
        parseInt(t.args[1], cur->tileW);
        parseInt(t.args[2], cur->tileH);
        ++consumed;
      } else if (n == "PAGE_DIM_PIXELS" && t.argc() >= 3) {
        parseInt(t.args[1], cur->pageW);
        parseInt(t.args[2], cur->pageH);
        ++consumed;
      } else if (n == "PAGE_DIM" && t.argc() >= 3) {
        int c = 0, r = 0;
        parseInt(t.args[1], c);
        parseInt(t.args[2], r);
        cur->pageW = c * cur->tileW;
        cur->pageH = r * cur->tileH;
        ++consumed;
      }
    }
    return consumed;
  }

  if (object == "GRAPHICS") {
    index.stats.graphicsFiles += 1;
    enum class Block { None, Plant, Creature, Other };
    Block block = Block::None;
    PlantGraphics* plant = nullptr;
    CreatureGraphics* creature = nullptr;
    std::string itemBlock;  // itemdef of the open *_GRAPHICS item block
    for (const RawToken& t : tokens) {
      const std::string& n = t.name();
      if (n == "TILE_GRAPHICS") {
        // PAGE:x:y:NAME[:variant[:frame]]
        if (t.argc() < 5) {
          diag(t, "TILE_GRAPHICS needs PAGE:x:y:NAME");
          continue;
        }
        auto s = spriteAt(index, t.args, 1, pending);
        if (!s) {
          diag(t, "TILE_GRAPHICS coordinates are not numbers");
          continue;
        }
        index.tileGraphics[t.args[4]].push_back(*s);
        // Keep symbolic ground-spatter variants addressable by their native
        // names instead of treating FULL_ISOLATED/PARTIAL_1A as array order.
        if (t.args[4].starts_with("SPATTER_") && t.argc() > 5)
          index.tileGraphics[t.args[4] + ":" + t.args[5]].push_back(*s);
        index.stats.tileGraphics += 1;
        ++consumed;
        // Multi-tile layouts: NAME:stage:lx:ly, NAME:lx:ly, or
        // WORKSHOP_CUSTOM:CODE:stage:lx:ly (the code becomes part of the
        // key). Two trailing integers are ambiguous with `variant:frame`
        // (ITEM_DOOR_VARIANT_DAMAGED:1:2); such a name also lands here as
        // a small layout nobody queries.
        {
          size_t first = 5;
          std::string name = t.args[4];
          int dummy;
          if (t.argc() > 5 && !parseInt(t.args[5], dummy) && t.argc() >= 8 &&
              parseInt(t.args[6], dummy) && parseInt(t.args[7], dummy)) {
            name += ":" + t.args[5];
            first = 6;
          }
          const size_t n = t.argc() - first;
          int v[3];
          if ((n == 2 || n == 3) && ints(t.args, first, n, v)) {
            if (n == 2) placeLayoutTile(index, name, kLayoutNoStage, v[0], v[1], *s);
            else placeLayoutTile(index, name, v[0], v[1], v[2], *s);
          }
        }
        continue;
      }
      if (n == "ASCII_GRAPHICS") {
        // tile:fg:bg:bright:NAME[:x[:y]] (graphics_classic.txt); the
        // tile is a code point, a quoted character ('X') or a bare one (?,
        // c); a ':' character splits into two quote halves. First row per
        // name wins.
        size_t at = 1;
        int tile = -1;
        if (t.argc() >= 6 && t.args[1] == "'" && t.args[2] == "'") {
          tile = ':';
          at = 3;
        } else if (t.argc() >= 6 && t.args[1].size() == 3 && t.args[1].front() == '\'' &&
                   t.args[1].back() == '\'') {
          tile = static_cast<unsigned char>(t.args[1][1]);
          at = 2;
        } else if (t.argc() >= 6 && parseInt(t.args[1], tile)) {
          at = 2;
        } else if (t.argc() >= 6 && t.args[1].size() == 1) {
          tile = static_cast<unsigned char>(t.args[1][0]);  // unquoted: ?, c
          at = 2;
        }
        int v[3];
        if (tile < 0 || tile > 255 || t.argc() < at + 4 || !ints(t.args, at, 3, v)) {
          diag(t, "ASCII_GRAPHICS needs tile:fg:bg:bright:NAME");
          continue;
        }
        const std::string& name = t.args[at + 3];
        if (index.asciiGraphics.emplace(name, wm::Glyph{static_cast<uint8_t>(tile),
                                                        static_cast<uint8_t>(v[0] & 7),
                                                        static_cast<uint8_t>(v[1] & 7),
                                                        static_cast<uint8_t>(v[2] ? 1 : 0)})
                .second) {
          index.stats.asciiGraphics += 1;
        }
        ++consumed;
        continue;
      }
      if (n == "TILE_GRAPHICS_RECTANGLE") {
        // PAGE:x:y:w:h:NAME
        int v[4];
        if (t.argc() < 7 || !ints(t.args, 2, 4, v)) {
          diag(t, "TILE_GRAPHICS_RECTANGLE needs PAGE:x:y:w:h:NAME");
          continue;
        }
        SpriteRef s;
        s.page = pageFor(index, t.args[1], pending);
        s.x = v[0];
        s.y = v[1];
        s.w = std::max(1, v[2]);
        s.h = std::max(1, v[3]);
        index.tileGraphics[t.args[6]].push_back(s);
        index.stats.tileGraphics += 1;
        ++consumed;
        continue;
      }
      if (n == "PLANT_GRAPHICS" && t.argc() >= 2) {
        block = Block::Plant;
        plant = &index.plants[t.args[1]];
        index.stats.plantGraphics += 1;
        ++consumed;
        continue;
      }
      if ((n == "CREATURE_GRAPHICS" && t.argc() >= 2) ||
          (n == "CREATURE_CASTE_GRAPHICS" && t.argc() >= 3)) {
        block = Block::Creature;
        if (n == "CREATURE_GRAPHICS") {
          creature = &index.creatures[t.args[1]];
          index.stats.creatureGraphics += 1;
        } else {
          // First caste seen stands in for the species when no plain
          // CREATURE_GRAPHICS exists (species strings carry no caste).
          auto it = index.creatureCastes.find(t.args[1]);
          if (it == index.creatureCastes.end()) {
            creature = &index.creatureCastes[t.args[1]];
            index.stats.creatureCastes += 1;
          } else {
            creature = nullptr;
            block = Block::Other;
          }
        }
        ++consumed;
        continue;
      }
      // Per-material item sprites: BOULDER_GRAPHICS:PAGE:x:y:INORGANIC:ID,
      // BARS_GRAPHICS:PAGE:x:y:MAT[:SUB], ROUGH_GEM_GRAPHICS:PAGE:x:y:ID.
      if ((n == "BOULDER_GRAPHICS" || n == "BARS_GRAPHICS" || n == "ROUGH_GEM_GRAPHICS") &&
          t.argc() >= 5) {
        if (auto s = spriteAt(index, t.args, 1, pending)) {
          std::string key;
          for (size_t i = 4; i < t.argc(); ++i) key += (i > 4 ? ":" : "") + t.args[i];
          auto& table = n == "BOULDER_GRAPHICS"  ? index.boulderGraphics
                        : n == "BARS_GRAPHICS"   ? index.barsGraphics
                                                 : index.roughGemGraphics;
          if (table.emplace(key, *s).second) index.stats.materialItems += 1;
          ++consumed;
        }
        continue;
      }
      {
        std::string family, variant;
        if (itemFamilyToken(n, family, variant)) {
          block = Block::Other;
          plant = nullptr;
          creature = nullptr;
          // The itemdef named in the token (ITEM_*), else the open block's.
          // (Not the page argument: item pages are named ITEM_AMMO,
          // ITEM_TOY, ... too.)
          const size_t at = findSpriteArgs(t.args, 1);
          std::string named;
          for (size_t i = 1; i < t.argc(); ++i)
            if (i != at && t.args[i].compare(0, 5, "ITEM_") == 0) named = t.args[i];
          std::optional<SpriteRef> s;
          if (at != std::string::npos) s = spriteAt(index, t.args, at, pending);
          auto defFor = [&](const std::string& id) -> ItemDefGraphics& {
            const size_t before = index.itemDefs.size();
            ItemDefGraphics& d = index.itemDefs[id];
            if (index.itemDefs.size() != before) index.stats.itemDefs += 1;
            return d;
          };
          if (variant.empty()) {
            // Block header. TOY_GRAPHICS:PAGE:x:y:NAME:MAT carries a
            // material variant; PROCEDURAL_ITEM_GRAPHICS names are not
            // itemdefs (WEAPON_WHIP_DEFAULT) and open no block.
            if (named.empty()) {
              itemBlock.clear();
              continue;
            }
            itemBlock = named;
            ItemDefGraphics& d = defFor(named);
            std::string mat;
            if (family == "TOY" && at != std::string::npos && t.argc() > at + 4) mat = t.args.back();
            if (s) {
              if (!d.base.valid()) d.base = *s;
              if (!mat.empty() && d.variants.emplace(mat, *s).second) index.stats.itemVariants += 1;
              ++consumed;
            }
            continue;
          }
          const std::string& target = named.empty() ? itemBlock : named;
          if (target.empty() || !s) continue;
          ItemDefGraphics& d = defFor(target);
          if (!d.base.valid()) d.base = *s;
          if (d.variants.emplace(variant, *s).second) index.stats.itemVariants += 1;
          ++consumed;
          continue;
        }
      }
      // Any other top-level *_GRAPHICS block ends the current one.
      if (n.size() > 9 && n.compare(n.size() - 9, 9, "_GRAPHICS") == 0) {
        block = Block::Other;
        plant = nullptr;
        creature = nullptr;
        continue;
      }
      if (block == Block::Plant && plant) {
        if (n == "GRASS_1" || n == "GRASS_2" || n == "GRASS_3" || n == "GRASS_4") {
          if (auto s = spriteAt(index, t.args, 1, pending)) {
            plant->grass[static_cast<size_t>(n[6] - '1')] = *s;
            ++consumed;
          }
        } else if (n == "SHRUB") {
          if (auto s = spriteAt(index, t.args, 1, pending)) plant->shrub = *s, ++consumed;
        } else if (n == "SHRUB_DEAD") {
          if (auto s = spriteAt(index, t.args, 1, pending)) plant->shrubDead = *s, ++consumed;
        } else if (n == "SAPLING") {
          if (auto s = spriteAt(index, t.args, 1, pending)) plant->sapling = *s, ++consumed;
        } else if (n == "PICKED") {
          if (auto s = spriteAt(index, t.args, 1, pending)) plant->picked = *s, ++consumed;
        } else if (n == "SEED") {
          if (auto s = spriteAt(index, t.args, 1, pending)) plant->seed = *s, ++consumed;
        } else if (n == "GROWTH_PICKED") {
          if (auto s = spriteAt(index, t.args, 1, pending)) {
            if (!plant->growthPicked.valid()) plant->growthPicked = *s;  // first growth wins
            ++consumed;
          }
        } else if (n == "TREE_TILE" && t.argc() >= 5) {
          // ROLE:PAGE:x:y or ROLE:stage:PAGE:x:y (autumn)
          size_t first = 2;
          int stage = 0;
          if (t.argc() >= 6 && parseInt(t.args[2], stage)) first = 3;
          if (auto s = spriteAt(index, t.args, first, pending)) {
            std::string role = t.args[1];
            if (first == 3) role += ":" + t.args[2];
            plant->treeTiles.emplace(role, *s);  // first wins
            ++consumed;
          } else {
            diag(t, "TREE_TILE coordinates are not numbers");
          }
        }
        continue;
      }
      if (block == Block::Creature && creature) {
        if (n == "LAYER_SET") {
          creature->layered = true;
          ++consumed;
          continue;
        }
        // Simple-format states only; everything inside a LAYER_SET (LAYER,
        // CONDITION_*, BP_APPEARANCE_MODIFIER_RANGE:HEIGHT:0:80, ...) is
        // ignored so its numeric arguments never read as sprites.
        static const char* const kSimpleStates[] = {
            "DEFAULT",      "CHILD",         "BABY",     "ANIMATED", "CORPSE",
            "TRAINED_WAR",  "TRAINED_HUNTER", "LIST_ICON", "VERMIN",  "REMAINS",
            "SKELETON",     "SKELETON_WITH_SKULL", "ZOMBIE", "GHOUL",  "PORTRAIT"};
        const bool simple = std::find_if(std::begin(kSimpleStates), std::end(kSimpleStates),
                                         [&](const char* s) { return n == s; }) !=
                            std::end(kSimpleStates);
        if (simple && !creature->layered && t.argc() >= 4) {
          if (auto s = parseSpriteArgs(index, t.args, 1, pending)) {
            // CHILD:...:AS_IS:<PARENT>: key child sprites by parent so
            // CHILD alone means the child form of DEFAULT.
            std::string state = n;
            if (n == "CHILD" || n == "BABY") {
              std::string parent = "DEFAULT";
              for (size_t i = 3; i < t.argc(); ++i) {
                if (t.args[i] == "AS_IS" || t.args[i] == "ADD_COLOR") continue;
                int dummy;
                if (parseInt(t.args[i], dummy) || t.args[i] == "LARGE_IMAGE") continue;
                parent = t.args[i];
                break;
              }
              if (parent != "DEFAULT") state = n + ":" + parent;
            }
            creature->states.emplace(state, *s);
            ++consumed;
          }
        }
        continue;
      }
    }
    return consumed;
  }

  if (object == "PALETTE") {
    Palette* cur = nullptr;
    for (const RawToken& t : tokens) {
      const std::string& n = t.name();
      if (n == "PALETTE" && t.argc() >= 2) {
        if (index.palette) {
          diag(t, "second PALETTE block ignored: " + t.args[1]);
          cur = nullptr;
          continue;
        }
        index.palette = Palette{};
        cur = &*index.palette;
        cur->name = t.args[1];
        ++consumed;
      } else if (!cur) {
        continue;
      } else if (n == "FILE" && t.argc() >= 2) {
        cur->file = t.args[1];
        cur->absPath = joinPath(graphicsDir, cur->file);
        ++consumed;
      } else if (n == "PALETTE_DEFAULT" && t.argc() >= 2) {
        parseInt(t.args[1], cur->defaultRow);
        ++consumed;
      } else if (n == "PALETTE_COLOR" && t.argc() >= 3) {
        int row = 0;
        if (parseInt(t.args[2], row)) {
          cur->rows.emplace(t.args[1], row);
          ++consumed;
        }
      }
    }
    return consumed;
  }

  if (object == "DESCRIPTOR_COLOR") {
    std::string cur;
    for (const RawToken& t : tokens) {
      if (t.name() == "COLOR" && t.argc() >= 2) {
        cur = t.args[1];
        ++consumed;
      } else if (t.name() == "RGB" && t.argc() >= 4 && !cur.empty()) {
        int c[3];
        if (ints(t.args, 1, 3, c)) {
          index.colors[cur] = Rgb{static_cast<uint8_t>(std::clamp(c[0], 0, 255)),
                                  static_cast<uint8_t>(std::clamp(c[1], 0, 255)),
                                  static_cast<uint8_t>(std::clamp(c[2], 0, 255))};
          index.stats.colors += 1;
          ++consumed;
        }
      }
    }
    return consumed;
  }

  if (object == "MATERIAL_TEMPLATE") {
    MaterialDef* cur = nullptr;
    for (const RawToken& t : tokens) {
      if (t.name() == "MATERIAL_TEMPLATE" && t.argc() >= 2) {
        cur = &index.materialTemplates[t.args[1]];
        index.stats.materialTemplates += 1;
        ++consumed;
      } else if (cur) {
        applyMaterialToken(*cur, t);
      }
    }
    return consumed;
  }

  if (object == "INORGANIC") {
    MaterialDef* cur = nullptr;
    for (const RawToken& t : tokens) {
      if (t.name() == "INORGANIC" && t.argc() >= 2) {
        cur = &index.inorganics[t.args[1]];
        index.stats.inorganics += 1;
        ++consumed;
      } else if (cur && t.name() == "USE_MATERIAL_TEMPLATE" && t.argc() >= 2) {
        // Template first, then the entry's own tokens in file order.
        *cur = fromTemplate(index, t.args[1]);
      } else if (cur) {
        applyMaterialToken(*cur, t);
      }
    }
    return consumed;
  }

  if (object == "CREATURE") {
    std::string species;
    MaterialDef* cur=nullptr;
    for(const auto& t:tokens) {
      const auto& n=t.name();
      if(n=="CREATURE" && t.argc()>=2){species=t.args[1];cur=nullptr;}
      else if(species.empty())continue;
      else if(n=="COPY_TAGS_FROM" && t.argc()>=2)index.creatureMaterialParents[species]=t.args[1];
      else if(n=="USE_MATERIAL_TEMPLATE" && t.argc()>=3) {
        cur=&index.creatureMaterials[species][t.args[1]];*cur=fromTemplate(index,t.args[2]);++consumed;
      } else if(n=="MATERIAL" && t.argc()>=2) {cur=&index.creatureMaterials[species][t.args[1]];++consumed;}
      else if(n=="SELECT_MATERIAL" && t.argc()>=2) {
        auto& mats=index.creatureMaterials[species];const auto it=mats.find(t.args[1]);cur=it==mats.end()?nullptr:&it->second;
      } else if(n=="REMOVE_MATERIAL" && t.argc()>=2){index.creatureMaterials[species].erase(t.args[1]);cur=nullptr;}
      else if(cur)applyMaterialToken(*cur,t);
    }
    return consumed;
  }
  if (object == "PLANT") {
    std::unordered_map<std::string, MaterialDef>* plantMats = nullptr;
    MaterialDef* cur = nullptr;
    for (const RawToken& t : tokens) {
      if (t.name() == "PLANT" && t.argc() >= 2) {
        plantMats = &index.plantMaterials[t.args[1]];
        cur = nullptr;
        index.stats.plants += 1;
        ++consumed;
      } else if (plantMats && t.name() == "USE_MATERIAL_TEMPLATE" && t.argc() >= 3) {
        cur = &(*plantMats)[t.args[1]];
        *cur = fromTemplate(index, t.args[2]);
        if (t.args[1] == "WOOD") cur->flags |= kMatWood;
      } else if (cur) {
        // Material tokens are indented under the template until the next
        // non-material plant token; colours are the only ones we take,
        // and STATE_COLOR/DISPLAY_COLOR never appear at plant level.
        applyMaterialToken(*cur, t);
      }
    }
    return consumed;
  }
  return 0;
}

void finalizeIndex(AssetIndex& index) {
  // Placeholder pages that never got a TILE_PAGE definition stay with an
  // empty file (pageW == 0); they become findable by name so the index is
  // the same before and after a cache round trip.
  for (const auto& [name, id] : index.pendingPages) index.pageByName.emplace(name, id);
  index.pendingPages.clear();
  index.stats.grassPlants = 0;
  index.stats.treePlants = 0;
  for (const auto& [id, p] : index.plants) {
    if (p.grass[0].valid()) index.stats.grassPlants += 1;
    if (!p.treeTiles.empty()) index.stats.treePlants += 1;
  }
  index.stats.buildingLayouts = static_cast<int>(index.buildingLayouts.size());
  index.stats.creatureSimple = 0;
  index.stats.creatureLayered = 0;
  for (const auto& [id, c] : index.creatures) {
    if (c.layered) index.stats.creatureLayered += 1;
    if (c.states.count("DEFAULT")) index.stats.creatureSimple += 1;
  }
}

}  // namespace df3d::assets
