// Text serialisation of the parsed index (the derived cache).
// One record per line, tab separated; the header carries the key
// (build id + content hash) that validates it.
#include <cstdio>
#include <sstream>
#include <string>

#include "df3d_assets/asset_index.h"
#include "df3d_assets/raw_tokens.h"

namespace df3d::assets {

namespace {

constexpr const char* kMagic = "DF3DAIX";
// Bump whenever the parser's output changes shape or meaning: the cache
// key is the raw-content hash, so a stale index for unchanged raws is
// otherwise trusted forever.
constexpr int kFormat = 6;  // 6: creature material descriptors and liquid colors

std::string hex64(uint64_t v) {
  char buf[24];
  std::snprintf(buf, sizeof buf, "%016llx", static_cast<unsigned long long>(v));
  return buf;
}

void putSprite(std::string& out, const SpriteRef& s) {
  out += '\t';
  out += std::to_string(s.page) + "\t" + std::to_string(s.x) + "\t" + std::to_string(s.y) +
         "\t" + std::to_string(s.w) + "\t" + std::to_string(s.h);
}

void putMaterial(std::string& out, const MaterialDef& m) {
  out += '\t' + m.solidColor + '\t' + std::to_string(m.displayFg) + '\t' +
         std::to_string(m.displayBg) + '\t' + std::to_string(m.displayBright) + '\t' +
         std::to_string(m.flags) + '\t' + m.templateName + '\t' + m.liquidColor + '\t' + m.mapDescriptor;
}

std::vector<std::string> splitTabs(std::string_view line) {
  std::vector<std::string> f;
  size_t start = 0;
  while (true) {
    const size_t t = line.find('\t', start);
    if (t == std::string_view::npos) {
      f.emplace_back(line.substr(start));
      break;
    }
    f.emplace_back(line.substr(start, t - start));
    start = t + 1;
  }
  return f;
}

bool getSprite(const std::vector<std::string>& f, size_t at, SpriteRef& s) {
  if (at + 5 > f.size()) return false;
  return parseInt(f[at], s.page) && parseInt(f[at + 1], s.x) && parseInt(f[at + 2], s.y) &&
         parseInt(f[at + 3], s.w) && parseInt(f[at + 4], s.h);
}

bool getMaterial(const std::vector<std::string>& f, size_t at, MaterialDef& m) {
  if (at + 8 > f.size()) return false;
  m.solidColor = f[at];
  int flags = 0;
  if (!parseInt(f[at + 1], m.displayFg) || !parseInt(f[at + 2], m.displayBg) ||
      !parseInt(f[at + 3], m.displayBright) || !parseInt(f[at + 4], flags))
    return false;
  m.flags = static_cast<uint32_t>(flags);
  m.templateName = f[at + 5];
  m.liquidColor = f[at + 6];
  m.mapDescriptor = f[at + 7];
  return true;
}

}  // namespace

std::string serializeIndex(const AssetIndex& idx) {
  std::string out;
  out += std::string(kMagic) + " " + std::to_string(kFormat) + " " + idx.buildId + " " +
         hex64(idx.contentHash) + "\n";
  for (const TilePage& p : idx.pages) {
    out += "page\t" + p.name + '\t' + p.file + '\t' + p.absPath + '\t' + std::to_string(p.tileW) +
           '\t' + std::to_string(p.tileH) + '\t' + std::to_string(p.pageW) + '\t' +
           std::to_string(p.pageH) + "\n";
  }
  for (const auto& [name, variants] : idx.tileGraphics) {
    for (const SpriteRef& s : variants) {
      out += "tile\t" + name;
      putSprite(out, s);
      out += '\n';
    }
  }
  for (const auto& [id, p] : idx.plants) {
    out += "plant\t" + id + '\n';
    for (int i = 0; i < 4; ++i) {
      if (!p.grass[static_cast<size_t>(i)].valid()) continue;
      out += "grass\t" + std::to_string(i);
      putSprite(out, p.grass[static_cast<size_t>(i)]);
      out += '\n';
    }
    if (p.shrub.valid()) putSprite(out += "shrub", p.shrub), out += '\n';
    if (p.shrubDead.valid()) putSprite(out += "shrubdead", p.shrubDead), out += '\n';
    if (p.sapling.valid()) putSprite(out += "sapling", p.sapling), out += '\n';
    if (p.picked.valid()) putSprite(out += "picked", p.picked), out += '\n';
    if (p.seed.valid()) putSprite(out += "seed", p.seed), out += '\n';
    if (p.growthPicked.valid()) putSprite(out += "growthpicked", p.growthPicked), out += '\n';
    for (const auto& [role, s] : p.treeTiles) {
      out += "treetile\t" + role;
      putSprite(out, s);
      out += '\n';
    }
  }
  auto putCreatures = [&](const char* kind,
                          const std::unordered_map<std::string, CreatureGraphics>& m) {
    for (const auto& [id, c] : m) {
      out += std::string(kind) + '\t' + id + '\t' + (c.layered ? "1" : "0") + '\n';
      for (const auto& [state, s] : c.states) {
        out += "state\t" + state;
        putSprite(out, s);
        out += '\n';
      }
    }
  };
  putCreatures("creature", idx.creatures);
  putCreatures("caste", idx.creatureCastes);
  for (const auto& [name, c] : idx.colors) {
    out += "color\t" + name + '\t' + std::to_string(c.r) + '\t' + std::to_string(c.g) + '\t' +
           std::to_string(c.b) + '\n';
  }
  for (const auto& [name, m] : idx.materialTemplates) {
    out += "template\t" + name;
    putMaterial(out, m);
    out += '\n';
  }
  for (const auto& [name, m] : idx.inorganics) {
    out += "inorganic\t" + name;
    putMaterial(out, m);
    out += '\n';
  }
  for(const auto& [species,mats]:idx.creatureMaterials)for(const auto& [name,m]:mats) {
    out+="creaturemat\t"+species+'\t'+name;putMaterial(out,m);out+='\n';
  }
  for(const auto& [species,parent]:idx.creatureMaterialParents)out+="creatureparent\t"+species+'\t'+parent+'\n';
  for (const auto& [plant, mats] : idx.plantMaterials) {
    for (const auto& [mat, m] : mats) {
      out += "plantmat\t" + plant + '\t' + mat;
      putMaterial(out, m);
      out += '\n';
    }
  }
  for (const auto& [name, l] : idx.buildingLayouts) {
    out += "layout\t" + name + '\t' + std::to_string(l.width) + '\t' + std::to_string(l.height) +
           '\n';
    for (const auto& [stage, grid] : l.stages) {
      for (size_t i = 0; i < grid.size(); ++i) {
        if (!grid[i].valid()) continue;
        out += "ltile\t" + std::to_string(stage) + '\t' +
               std::to_string(static_cast<int>(i % static_cast<size_t>(l.width))) + '\t' +
               std::to_string(static_cast<int>(i / static_cast<size_t>(l.width)));
        putSprite(out, grid[i]);
        out += '\n';
      }
    }
  }
  for (const auto& [name, d] : idx.itemDefs) {
    out += "itemdef\t" + name;
    putSprite(out, d.base);
    out += '\n';
    for (const auto& [variant, s] : d.variants) {
      out += "ivar\t" + variant;
      putSprite(out, s);
      out += '\n';
    }
  }
  auto putMatItems = [&](const char* kind, const std::unordered_map<std::string, SpriteRef>& m) {
    for (const auto& [key, s] : m) {
      out += std::string("matitem\t") + kind + '\t' + key;
      putSprite(out, s);
      out += '\n';
    }
  };
  putMatItems("boulder", idx.boulderGraphics);
  putMatItems("bars", idx.barsGraphics);
  putMatItems("gem", idx.roughGemGraphics);
  if (idx.palette) {
    const Palette& pl = *idx.palette;
    out += "palette\t" + pl.name + '\t' + pl.file + '\t' + pl.absPath + '\t' +
           std::to_string(pl.defaultRow) + '\n';
    for (const auto& [color, row] : pl.rows)
      out += "prow\t" + color + '\t' + std::to_string(row) + '\n';
  }
  for (const auto& [name, g] : idx.asciiGraphics) {
    out += "ascii\t" + name + '\t' + std::to_string(g.tile) + '\t' + std::to_string(g.fg) + '\t' +
           std::to_string(g.bg) + '\t' + std::to_string(g.bright) + '\n';
  }
  const IndexStats& s = idx.stats;
  out += "stats";
  for (int v : {s.rawFiles, s.graphicsFiles, s.tilePageFiles, s.tilePages, s.duplicatePages,
                s.tileGraphics, s.plantGraphics, s.grassPlants, s.treePlants, s.creatureGraphics,
                s.creatureSimple, s.creatureLayered, s.creatureCastes, s.colors,
                s.materialTemplates, s.inorganics, s.plants, s.buildingLayouts, s.layoutTiles,
                s.itemDefs, s.itemVariants, s.materialItems, s.asciiGraphics})
    out += '\t' + std::to_string(v);
  out += '\n';
  return out;
}

bool peekIndexKey(std::string_view text, std::string& buildId, uint64_t& hash) {
  const size_t nl = text.find('\n');
  std::istringstream head{std::string(text.substr(0, nl))};
  std::string magic, hashHex;
  int format = 0;
  if (!(head >> magic >> format >> buildId >> hashHex)) return false;
  if (magic != kMagic || format != kFormat) return false;
  hash = std::stoull(hashHex, nullptr, 16);
  return true;
}

bool deserializeIndex(std::string_view text, AssetIndex& out, std::string& err) {
  AssetIndex idx;
  if (!peekIndexKey(text, idx.buildId, idx.contentHash)) {
    err = "not a DF3D asset index (bad header)";
    return false;
  }
  size_t pos = text.find('\n');
  if (pos == std::string_view::npos) {
    err = "truncated index";
    return false;
  }
  ++pos;
  PlantGraphics* plant = nullptr;
  CreatureGraphics* creature = nullptr;
  BuildingLayout* layout = nullptr;
  std::string layoutName;
  ItemDefGraphics* itemDef = nullptr;
  size_t lineNo = 1;
  while (pos < text.size()) {
    size_t nl = text.find('\n', pos);
    if (nl == std::string_view::npos) nl = text.size();
    std::string_view line = text.substr(pos, nl - pos);
    pos = nl + 1;
    ++lineNo;
    if (line.empty()) continue;
    const auto f = splitTabs(line);
    const std::string& k = f[0];
    auto bad = [&]() {
      err = "index line " + std::to_string(lineNo) + ": malformed '" + k + "' record";
      return false;
    };
    if (k == "page") {
      if (f.size() < 8) return bad();
      TilePage p;
      p.name = f[1];
      p.file = f[2];
      p.absPath = f[3];
      if (!parseInt(f[4], p.tileW) || !parseInt(f[5], p.tileH) || !parseInt(f[6], p.pageW) ||
          !parseInt(f[7], p.pageH))
        return bad();
      idx.pageByName[p.name] = static_cast<int>(idx.pages.size());
      idx.pages.push_back(std::move(p));
    } else if (k == "tile") {
      SpriteRef s;
      if (f.size() < 7 || !getSprite(f, 2, s)) return bad();
      idx.tileGraphics[f[1]].push_back(s);
    } else if (k == "plant") {
      if (f.size() < 2) return bad();
      plant = &idx.plants[f[1]];
      creature = nullptr;
    } else if (k == "grass") {
      SpriteRef s;
      int i = 0;
      if (!plant || f.size() < 7 || !parseInt(f[1], i) || i < 0 || i > 3 || !getSprite(f, 2, s))
        return bad();
      plant->grass[static_cast<size_t>(i)] = s;
    } else if (k == "shrub" || k == "shrubdead" || k == "sapling" || k == "picked" ||
               k == "seed" || k == "growthpicked") {
      SpriteRef s;
      if (!plant || !getSprite(f, 1, s)) return bad();
      (k == "shrub"          ? plant->shrub
       : k == "shrubdead"    ? plant->shrubDead
       : k == "sapling"      ? plant->sapling
       : k == "picked"       ? plant->picked
       : k == "seed"         ? plant->seed
                             : plant->growthPicked) = s;
    } else if (k == "layout") {
      int w = 0, h = 0;
      if (f.size() < 4 || !parseInt(f[2], w) || !parseInt(f[3], h) || w < 0 || h < 0 ||
          w > 16 || h > 16)
        return bad();
      layout = &idx.buildingLayouts[f[1]];
      layout->width = w;
      layout->height = h;
      plant = nullptr;
      creature = nullptr;
      itemDef = nullptr;
    } else if (k == "ltile") {
      SpriteRef s;
      int stage = 0, lx = 0, ly = 0;
      if (!layout || f.size() < 9 || !parseInt(f[1], stage) || !parseInt(f[2], lx) ||
          !parseInt(f[3], ly) || !getSprite(f, 4, s) || lx < 0 || ly < 0 ||
          lx >= layout->width || ly >= layout->height)
        return bad();
      auto& grid = layout->stages[stage];
      if (grid.empty())
        grid.resize(static_cast<size_t>(layout->width) * static_cast<size_t>(layout->height));
      grid[static_cast<size_t>(ly) * static_cast<size_t>(layout->width) +
           static_cast<size_t>(lx)] = s;
    } else if (k == "itemdef") {
      SpriteRef s;
      if (f.size() < 7 || !getSprite(f, 2, s)) return bad();
      itemDef = &idx.itemDefs[f[1]];
      itemDef->base = s;
      plant = nullptr;
      creature = nullptr;
      layout = nullptr;
    } else if (k == "ivar") {
      SpriteRef s;
      if (!itemDef || f.size() < 7 || !getSprite(f, 2, s)) return bad();
      itemDef->variants[f[1]] = s;
    } else if (k == "matitem") {
      SpriteRef s;
      if (f.size() < 8 || !getSprite(f, 3, s)) return bad();
      (f[1] == "boulder" ? idx.boulderGraphics
       : f[1] == "bars"  ? idx.barsGraphics
                         : idx.roughGemGraphics)[f[2]] = s;
    } else if (k == "treetile") {
      SpriteRef s;
      if (!plant || f.size() < 7 || !getSprite(f, 2, s)) return bad();
      plant->treeTiles[f[1]] = s;
    } else if (k == "creature" || k == "caste") {
      if (f.size() < 3) return bad();
      creature = k == "creature" ? &idx.creatures[f[1]] : &idx.creatureCastes[f[1]];
      creature->layered = f[2] == "1";
      plant = nullptr;
    } else if (k == "state") {
      SpriteRef s;
      if (!creature || f.size() < 7 || !getSprite(f, 2, s)) return bad();
      creature->states[f[1]] = s;
    } else if (k == "ascii") {
      int v[4];
      if (f.size() < 6 || !parseInt(f[2], v[0]) || !parseInt(f[3], v[1]) || !parseInt(f[4], v[2]) ||
          !parseInt(f[5], v[3]))
        return bad();
      idx.asciiGraphics[f[1]] = wm::Glyph{static_cast<uint8_t>(v[0]), static_cast<uint8_t>(v[1]),
                                          static_cast<uint8_t>(v[2]), static_cast<uint8_t>(v[3])};
    } else if (k == "color") {
      int c[3];
      if (f.size() < 5 || !parseInt(f[2], c[0]) || !parseInt(f[3], c[1]) || !parseInt(f[4], c[2]))
        return bad();
      idx.colors[f[1]] = Rgb{static_cast<uint8_t>(c[0]), static_cast<uint8_t>(c[1]),
                             static_cast<uint8_t>(c[2])};
    } else if (k == "template" || k == "inorganic") {
      MaterialDef m;
      if (f.size() < 8 || !getMaterial(f, 2, m)) return bad();
      (k == "template" ? idx.materialTemplates : idx.inorganics)[f[1]] = m;
    } else if(k=="creatureparent") {
      if(f.size()<3)return bad();idx.creatureMaterialParents[f[1]]=f[2];
    } else if (k == "plantmat" || k == "creaturemat") {
      MaterialDef m;
      if (f.size() < 9 || !getMaterial(f, 3, m)) return bad();
      (k=="plantmat" ? idx.plantMaterials : idx.creatureMaterials)[f[1]][f[2]] = m;
    } else if (k == "palette") {
      Palette pl;
      if (f.size() < 5 || !parseInt(f[4], pl.defaultRow)) return bad();
      pl.name = f[1];
      pl.file = f[2];
      pl.absPath = f[3];
      idx.palette = std::move(pl);
    } else if (k == "prow") {
      int row = 0;
      if (!idx.palette || f.size() < 3 || !parseInt(f[2], row)) return bad();
      idx.palette->rows[f[1]] = row;
    } else if (k == "stats") {
      int* fields[] = {&idx.stats.rawFiles,        &idx.stats.graphicsFiles,
                       &idx.stats.tilePageFiles,   &idx.stats.tilePages,
                       &idx.stats.duplicatePages,  &idx.stats.tileGraphics,
                       &idx.stats.plantGraphics,   &idx.stats.grassPlants,
                       &idx.stats.treePlants,      &idx.stats.creatureGraphics,
                       &idx.stats.creatureSimple,  &idx.stats.creatureLayered,
                       &idx.stats.creatureCastes,  &idx.stats.colors,
                       &idx.stats.materialTemplates, &idx.stats.inorganics,
                       &idx.stats.plants,            &idx.stats.buildingLayouts,
                       &idx.stats.layoutTiles,       &idx.stats.itemDefs,
                       &idx.stats.itemVariants,      &idx.stats.materialItems,
                       &idx.stats.asciiGraphics};
      const size_t n = sizeof(fields) / sizeof(fields[0]);
      if (f.size() < n + 1) return bad();
      for (size_t i = 0; i < n; ++i)
        if (!parseInt(f[i + 1], *fields[i])) return bad();
    } else {
      err = "index line " + std::to_string(lineNo) + ": unknown record '" + k + "'";
      return false;
    }
  }
  out = std::move(idx);
  return true;
}

}  // namespace df3d::assets
