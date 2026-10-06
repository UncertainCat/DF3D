#include "df3d_assets/resolver.h"

#include <string>

namespace df3d::assets {

using wm::MaterialKind;
using wm::TileShape;

namespace {

// Sand colour family from the inorganic id (SAND_YELLOW, SAND_WHITE, ...);
// "" is the beige/tan default page.
const char* sandSuffix(std::string_view rawId) {
  if (rawId.find("YELLOW") != std::string_view::npos) return "Y";
  if (rawId.find("WHITE") != std::string_view::npos) return "W";
  if (rawId.find("BLACK") != std::string_view::npos) return "B";
  if (rawId.find("RED") != std::string_view::npos) return "R";
  return "";
}
const char* sandFloorFamily(std::string_view rawId) {
  if (rawId.find("YELLOW") != std::string_view::npos) return "SAND_YELLOW_FLOOR";
  if (rawId.find("WHITE") != std::string_view::npos) return "SAND_WHITE_FLOOR";
  if (rawId.find("BLACK") != std::string_view::npos) return "SAND_BLACK_FLOOR";
  if (rawId.find("RED") != std::string_view::npos) return "SAND_RED_FLOOR";
  return "SAND_FLOOR";
}
const char* sandStairFamily(std::string_view rawId) {
  if (rawId.find("YELLOW") != std::string_view::npos) return "SAND_Y";
  if (rawId.find("WHITE") != std::string_view::npos) return "SAND_W";
  if (rawId.find("BLACK") != std::string_view::npos) return "SAND_B";
  if (rawId.find("RED") != std::string_view::npos) return "SAND_R";
  return "SAND";
}

bool isWoodToken(std::string_view token) {
  return token.compare(0, 6, "PLANT:") == 0 && token.size() > 5 &&
         token.compare(token.size() - 5, 5, ":WOOD") == 0;
}

struct Pick {
  std::string name;  // TILE_GRAPHICS name
  const char* rule = "";
};

// A wall family (`STONE_WALL`, `SMOOTHED_STONE_WALL`, `SAND_Y_WALL`, ...):
// every family in 53.16 carries the same 19 members named by the
// exposed edges (verified against the native surface); the rough
// families (STONE, SOIL, WORN*) number their single / opposite / full
// members `_1.._4`.
struct WallFamily {
  std::string family;
  const char* rule = "";
};

WallFamily wallFamily(const AssetIndex& idx, const TerrainQuery& q, std::string_view rawId) {
  const bool smooth = q.flags & wm::kTileSmooth;
  const bool engraved = q.flags & wm::kTileEngraved;
  switch (q.kind) {
    case MaterialKind::Ice:
      return {smooth || engraved ? "SMOOTHED_ICE_WALL" : "ICE_WALL", "wall.ice"};
    case MaterialKind::Soil: {
      const uint32_t f = idx.materialFlags(q.material);
      if (f & kMatSand) {
        return {std::string("SAND_") + sandSuffix(rawId) + (sandSuffix(rawId)[0] ? "_" : "") +
                    "WALL",
                "wall.sand"};
      }
      return {"SOIL_WALL", "wall.soil"};
    }
    case MaterialKind::Grass:
      return {"SOIL_WALL", "wall.grass->soil"};
    case MaterialKind::Stone:
      if (engraved) return {"ENGRAVED_STONE_WALL", "wall.stone.engraved"};
      if (smooth) return {"SMOOTHED_STONE_WALL", "wall.stone.smooth"};
      return {"STONE_WALL", "wall.stone"};
    case MaterialKind::Mineral:
      if (engraved) return {"ENGRAVED_STONE_WALL", "wall.mineral.engraved"};
      if (smooth) return {"SMOOTHED_STONE_WALL", "wall.mineral.smooth"};
      return {"ORE_VEIN_WALL", "wall.mineral"};
    case MaterialKind::Gem:
      if (engraved) return {"ENGRAVED_STONE_WALL", "wall.gem.engraved"};
      if (smooth) return {"SMOOTHED_STONE_WALL", "wall.gem.smooth"};
      return {"GEM_A_WALL", "wall.gem"};
    case MaterialKind::Magma:
      return {"MAGMA_WALL", "wall.magma"};
    case MaterialKind::Wood:
      return {"WOODEN_WALL", "wall.wood"};
    case MaterialKind::Plant:
      return {"WOODEN_WALL", "wall.plant->wood"};
    case MaterialKind::Constructed: {
      const uint32_t f = idx.materialFlags(q.material);
      if (isWoodToken(q.material) || (f & kMatWood)) return {"WOODEN_WALL", "wall.constructed.wood"};
      if (f & kMatMetal) return {"REINFORCED_METAL_WALL", "wall.constructed.metal"};
      if (q.material == "WATER") return {"ICE_WALL", "wall.constructed.ice"};
      return {"ROCK_BLOCKS_WALL", "wall.constructed.blocks"};
    }
    case MaterialKind::Water:
      return {"ICE_WALL", "wall.water->ice"};
    case MaterialKind::None:
    case MaterialKind::Unknown:
      break;
  }
  return {"STONE_WALL", "wall.unknown->stone"};
}

// `<family>_<suffix>`, or the rough families' numbered `_<suffix>_1`.
Pick wallMember(const AssetIndex& idx, const WallFamily& f, const std::string& suffix) {
  const std::string plain = f.family + "_" + suffix;
  if (idx.tile(plain)) return {plain, f.rule};
  return {plain + "_1", f.rule};
}

// The texture-all-over member dresses a pillar in native DF; retained
// for the vertical faces of a cube (rock on every part of that face).
Pick wallPick(const AssetIndex& idx, const TerrainQuery& q, std::string_view rawId) {
  return wallMember(idx, wallFamily(idx, q, rawId), "N_S_W_E");
}

Pick floorPick(const AssetIndex& idx, const TerrainQuery& q, std::string_view rawId) {
  const bool smooth = q.flags & wm::kTileSmooth;
  const bool engraved = q.flags & wm::kTileEngraved;
  switch (q.kind) {
    case MaterialKind::Grass:
      return {"GRASS_5", "floor.grass.generic"};
    case MaterialKind::Ice:
      return {smooth || engraved ? "SMOOTH_ICE_FLOOR" : "ROUGH_ICE_FLOOR", "floor.ice"};
    case MaterialKind::Soil: {
      const uint32_t f = idx.materialFlags(q.material);
      if (f & kMatSand) return {std::string(sandFloorFamily(rawId)) + "_5", "floor.sand"};
      return {"DIRT_FLOOR_5", "floor.soil"};
    }
    case MaterialKind::Stone:
    case MaterialKind::Mineral:
    case MaterialKind::Gem:
      if (engraved) return {"FLOOR_STONE_ENGRAVED_PALETTE", "floor.stone.engraved"};
      if (smooth) return {"SMOOTH_FLOOR", "floor.stone.smooth"};
      return {"STONE_FLOOR_5", "floor.stone"};
    case MaterialKind::Magma:
      return {"MAGMA_1", "floor.magma"};
    case MaterialKind::Wood:
      return {"WOOD_FLOOR", "floor.wood"};
    case MaterialKind::Plant:
      return {"DIRT_FLOOR_5", "floor.plant->soil"};
    case MaterialKind::Constructed: {
      const uint32_t f = idx.materialFlags(q.material);
      if (isWoodToken(q.material) || (f & kMatWood)) return {"WOOD_FLOOR", "floor.constructed.wood"};
      if (f & kMatMetal) return {"METAL_FLOOR", "floor.constructed.metal"};
      if (f & kMatGlass) return {"GLASS_CLEAR_FLOOR", "floor.constructed.glass"};
      if (q.material == "WATER") return {"SMOOTH_ICE_FLOOR", "floor.constructed.ice"};
      return {"FLOOR_STONE_BLOCK", "floor.constructed.blocks"};
    }
    case MaterialKind::Water:
      return {"ROUGH_ICE_FLOOR", "floor.water->ice"};
    case MaterialKind::None:
    case MaterialKind::Unknown:
      if (q.material == "ASH") return {"FLOOR_ASHES", "floor.ash"};
      break;
  }
  return {"STONE_FLOOR_5", "floor.unknown->stone"};
}

// DF's ramp art (`<K>_RAMP_WITH_WALL_<walls>` on the `<K>_RAMPS` pages,
// 46 wall combinations plus `<K>_RAMP_OTHER`; survey in the README) is
// top-down and lit from the north: the tile whose wall is to the south
// shows a bright slope face rising toward the south. A wedge whose high
// side is D takes the single-wall tile `_WITH_WALL_<D>`, mapped straight
// down onto the slope so the baked lighting coincides with the geometry;
// a lone ramp (no high side) takes `_RAMP_OTHER`. Multi-wall combinations
// are not used: the mesher's wedge is single-direction.
Pick rampPick(const AssetIndex& idx, const TerrainQuery& q, std::string_view rawId) {
  std::string family;
  const char* rule = "ramp.stone";
  switch (q.kind) {
    case MaterialKind::Grass:
      family = "GRASS_RAMP";
      rule = "ramp.grass";
      break;
    case MaterialKind::Soil: {
      const uint32_t f = idx.materialFlags(q.material);
      if (f & kMatSand) {
        const char* s = sandSuffix(rawId);
        family = std::string("SAND_") + (s[0] == 'Y' ? "YELLOW" : s[0] == 'W' ? "WHITE"
                                         : s[0] == 'B' ? "BLACK" : s[0] == 'R' ? "RED"
                                                                               : "BEIGE") +
                 "_RAMP";
        rule = "ramp.sand";
      } else {
        family = "SOIL_RAMP";
        rule = "ramp.soil";
      }
      break;
    }
    default:
      family = "STONE_RAMP";
      break;
  }
  const char* dir = nullptr;
  switch (q.slope) {
    case SlopeDir::North: dir = "N"; break;
    case SlopeDir::South: dir = "S"; break;
    case SlopeDir::West: dir = "W"; break;
    case SlopeDir::East: dir = "E"; break;
    case SlopeDir::None: break;
  }
  if (!dir) return {family + "_OTHER", rule};
  return {family + "_WITH_WALL_" + dir, rule};
}

Pick stairPick(const AssetIndex& idx, const TerrainQuery& q, std::string_view rawId) {
  const char* suffix = q.shape == TileShape::StairUp     ? "_STAIR_UP"
                       : q.shape == TileShape::StairDown ? "_STAIR_DOWN"
                                                         : "_STAIR_UPDOWN";
  switch (q.kind) {
    case MaterialKind::Grass:
      return {std::string("GRASS") + suffix, "stair.grass"};
    case MaterialKind::Soil: {
      const uint32_t f = idx.materialFlags(q.material);
      if (f & kMatSand) return {std::string(sandStairFamily(rawId)) + suffix, "stair.sand"};
      return {std::string("DIRT") + suffix, "stair.soil"};
    }
    case MaterialKind::Stone:
    case MaterialKind::Mineral:
    case MaterialKind::Gem:
    case MaterialKind::Constructed:
      return {std::string("STONE") + suffix, "stair.stone"};
    default:
      return {std::string("STONE") + suffix, "stair.other->stone"};
  }
}

const PlantGraphics* plantOf(const AssetIndex& idx, std::string_view token) {
  if (token.compare(0, 6, "PLANT:") != 0) return nullptr;
  auto it = idx.plants.find(std::string(AssetIndex::materialRawId(token)));
  return it == idx.plants.end() ? nullptr : &it->second;
}

// Per-species TREE_TILE role, else the global TILE_GRAPHICS of that role.
std::optional<SpriteRef> treeTile(const AssetIndex& idx, const PlantGraphics* plant,
                                  std::initializer_list<const char*> roles, const char** which) {
  for (const char* role : roles) {
    if (plant) {
      auto it = plant->treeTiles.find(role);
      if (it != plant->treeTiles.end()) {
        *which = "species";
        return it->second;
      }
    }
  }
  for (const char* role : roles) {
    if (const SpriteRef* s = idx.tile(role)) {
      *which = "default";
      return *s;
    }
  }
  return std::nullopt;
}

// Every opaque terrain face is recoloured by its material (DF swaps keyed
// pixels for all environment pages alike; pages that are not keyed, such
// as grass, are simply unaffected) and composited over the row's base.
void colourise(const AssetIndex& idx, TerrainSprite& r, std::string_view material) {
  r.colorName = std::string(idx.materialColorName(material));
  r.paletteRow = idx.paletteRow(r.colorName);
  if (auto c = idx.materialColor(material)) {
    r.tinted = true;
    r.tint = *c;
  }
  r.fill = !r.cutout;
}

TerrainSprite finish(const AssetIndex& idx, const Pick& p, std::string_view material) {
  TerrainSprite r;
  r.rule = p.rule;
  const SpriteRef* s = idx.tile(p.name);
  if (!s) {
    r.rule = "missing-tile";
    return r;
  }
  r.found = true;
  r.sprite = *s;
  colourise(idx, r, material);
  return r;
}

}  // namespace

std::string wallVariantSuffix(uint8_t walls) {
  std::string s;
  auto add = [&](const char* d) {
    if (!s.empty()) s += '_';
    s += d;
  };
  if (!(walls & kWallN)) add("N");
  if (!(walls & kWallS)) add("S");
  if (!(walls & kWallW)) add("W");
  if (!(walls & kWallE)) add("E");
  return s;
}

std::vector<std::string> wallTopSuffixes(uint8_t walls) {
  std::vector<std::string> out;
  const std::string cardinal = wallVariantSuffix(walls);
  if (!cardinal.empty()) out.push_back(cardinal);
  const struct { uint8_t diagonal, adjacent; const char* name; } corners[] = {
      {kWallNW, kWallN | kWallW, "NW"}, {kWallNE, kWallN | kWallE, "NE"},
      {kWallSW, kWallS | kWallW, "SW"}, {kWallSE, kWallS | kWallE, "SE"}};
  for (const auto& c : corners)
    if (!(walls & c.diagonal) && (walls & c.adjacent) == c.adjacent) out.emplace_back(c.name);
  return out;
}

TerrainSprite resolveTerrain(const AssetIndex& idx, const TerrainQuery& q) {
  const std::string_view rawId = AssetIndex::materialRawId(q.material);
  TerrainSprite r;

  if (q.part == FaceKind::Liquid) {
    const char* name = q.liquid == wm::LiquidKind::Magma ? "MAGMA_1" : "WATER";
    if (const SpriteRef* s = idx.tile(name)) {
      r.found = true;
      r.sprite = *s;
      r.rule = q.liquid == wm::LiquidKind::Magma ? "liquid.magma" : "liquid.water";
    } else {
      r.rule = "missing-tile";
    }
    return r;
  }

  // Completed tracks use a separate transparent rail/groove layer.
  // Native steel SW capture: original STONE_FLOOR_5 backing, palette-swapped
  // TRACK_CONSTRUCTED_STONE_SW above it (no palette/fill on the backing).
  // Protected ramp sweeps use the same rail artwork, over native ramp backing.
  if ((q.shape == TileShape::Floor || q.shape == TileShape::Ramp) && q.completedTrack && q.completedTrack <= 15) {
    if (q.part == FaceKind::Feature && (q.side == FaceSide::Top || q.side == FaceSide::Slope)) {
      std::string name;
      if (q.kind == MaterialKind::Constructed) {
        const bool wood = isWoodToken(q.material) || (idx.materialFlags(q.material) & kMatWood);
        // Pinned native DF uses the WOOD four-way crossing even for steel.
        // Protected direction sweep and isolated repeat agree pixel-for-pixel.
        name = (wood || q.completedTrack == 15) ? "TRACK_CONSTRUCTED_WOOD_" : "TRACK_CONSTRUCTED_STONE_";
      } else {
        name = "TRACK_CARVED_";
      }
      // Native token order is N,S,W,E, independent of the semantic bit order.
      if (q.completedTrack & 1) name += 'N';
      if (q.completedTrack & 2) name += 'S';
      if (q.completedTrack & 8) name += 'W';
      if (q.completedTrack & 4) name += 'E';
      // Native carved grooves retain their painted colors; constructed rails
      // use the construction material palette (protected dolomite/steel captures).
      auto track = finish(idx, Pick{name, "floor.track.rails"},
                          q.kind == MaterialKind::Constructed ? q.material : std::string_view{});
      track.fill = false;
      track.cutout = true;
      return track;
    }
    if (q.part == FaceKind::Terrain && q.shape == TileShape::Floor) {
      if (const auto* sprite = idx.tile("STONE_FLOOR_5")) {
        r.found = true;
        r.sprite = *sprite;
        r.rule = "floor.track.backing";
      } else {
        r.rule = "missing-tile";
      }
      return r;
    }
  }

  const PlantGraphics* plant = plantOf(idx, q.material);

  if (q.part == FaceKind::Feature) {
    switch (q.shape) {
      case TileShape::StairUp:
      case TileShape::StairDown:
      case TileShape::StairUpDown:
        if (q.side == FaceSide::Top) {
          TerrainSprite stair = finish(idx, stairPick(idx, q, rawId), q.material);
          stair.cutout = true;
          stair.fill = false;
          return stair;
        }
        return finish(idx, wallPick(idx, q, rawId), q.material);
      case TileShape::Boulder: {
        TerrainSprite b = finish(idx, Pick{"BOULDER", "feature.boulder"}, q.material);
        return b;
      }
      case TileShape::Pebbles:
        return finish(idx, Pick{"PEBBLES_FLOOR_5", "feature.pebbles"}, q.material);
      case TileShape::TreeBranch: {
        const char* which = "";
        auto s = treeTile(idx, plant, {"TREE_TWIGS_FULL", "TREE_TWIGS", "TREE_HEAVY_BRANCH_NSWE",
                                       "TREE_TRUNK_NSWE"},
                          &which);
        if (!s) {
          r.rule = "missing-tile";
          return r;
        }
        r.found = true;
        r.sprite = *s;
        r.cutout = true;
        r.rule = which[0] == 's' ? "feature.branch.species" : "feature.branch.default";
        colourise(idx, r, q.material);
        return r;
      }
      case TileShape::Shrub: {
        if (plant && plant->shrub.valid()) {
          r.found = true;
          r.sprite = plant->shrub;
          r.cutout = true;
          r.rule = "feature.shrub.species";
          colourise(idx, r, q.material);
          return r;
        }
        TerrainSprite g = finish(idx, Pick{"SHRUB", "feature.shrub.generic"}, q.material);
        g.cutout = true;
        g.fill = false;
        return g;
      }
      case TileShape::Sapling: {
        if (plant && plant->sapling.valid()) {
          r.found = true;
          r.sprite = plant->sapling;
          r.cutout = true;
          r.rule = "feature.sapling.species";
          colourise(idx, r, q.material);
          return r;
        }
        TerrainSprite g =
            finish(idx, Pick{"SAPLING", "feature.sapling.generic"}, q.material);
        g.cutout = true;
        g.fill = false;
        return g;
      }
      default:
        break;
    }
    return finish(idx, floorPick(idx, q, rawId), q.material);
  }

  // Terrain part: the tile's own body.
  switch (q.shape) {
    case TileShape::Wall:
    case TileShape::Unknown: {
      // A single wall top can contain both cardinal edges and several
      // diagonal corner nubs. Composite the art before drawing one face.
      // Missing mod members retain the established full-texture fallback.
      if (q.side == FaceSide::Top) {
        TerrainSprite t = finish(idx, wallPick(idx, q, rawId), q.material);
        if (t.found) {
          t.layeredWall = true;
          for (const auto& suffix : wallTopSuffixes(q.walls)) {
            const Pick member = wallMember(idx, wallFamily(idx, q, rawId), suffix);
            const SpriteRef* sprite = idx.tile(member.name);
            if (!sprite) { t.layeredWall = false; t.wallLayers.clear(); break; }
            t.wallLayers.push_back(*sprite);
          }
          return t;
        }
      }
      return finish(idx, wallPick(idx, q, rawId), q.material);
    }
    case TileShape::Fortification: {
      const char* name = q.kind == MaterialKind::Ice    ? "FORTIFICATION_ICE"
                         : q.kind == MaterialKind::Wood ? "FORTIFICATION_WOOD"
                                                        : "FORTIFICATION";
      return finish(idx, Pick{name, "wall.fortification"}, q.material);
    }
    case TileShape::TreeTrunk: {
      // Tops show the trunk's cross-section (PILLAR); vertical faces want
      // bark, which the raws only draw as the interior of a thick trunk
      // (THICK_INTERIOR) or a straight trunk run (NS).
      const char* which = "";
      auto s = q.side == FaceSide::Top || q.side == FaceSide::Bottom
                   ? treeTile(idx, plant, {"TREE_TRUNK_PILLAR", "TREE_TRUNK_THICK_INTERIOR",
                                           "TREE_TRUNK_NS", "TREE_TRUNK_NS_we"}, &which)
                   : treeTile(idx, plant, {"TREE_TRUNK_THICK_INTERIOR", "TREE_TRUNK_NS",
                                           "TREE_TRUNK_NS_we", "TREE_TRUNK_PILLAR"}, &which);
      if (!s) {
        r.rule = "missing-tile";
        return r;
      }
      r.found = true;
      r.sprite = *s;
      r.rule = which[0] == 's' ? "trunk.species" : "trunk.default";
      colourise(idx, r, q.material);
      return r;
    }
    case TileShape::Floor:
    case TileShape::StairUp:
    case TileShape::StairDown:
    case TileShape::StairUpDown:
    case TileShape::Boulder:
    case TileShape::Pebbles:
    case TileShape::Shrub:
    case TileShape::Sapling:
    case TileShape::TreeBranch: {
      // Floor slabs. Grass uses the plant's own GRASS_1 (full density) when
      // the raws define it; the slab's thin sides get the same tile.
      if (q.kind == MaterialKind::Grass && plant && plant->grass[0].valid()) {
        r.found = true;
        r.sprite = plant->grass[0];
        r.rule = "floor.grass.species";
        colourise(idx, r, q.material);
        return r;
      }
      return finish(idx, floorPick(idx, q, rawId), q.material);
    }
    case TileShape::Ramp: {
      // The slope (and a lone ramp's flat top) takes DF's ramp art for the
      // wedge's direction (rampPick); an install lacking that tile falls
      // back to the material's floor as before. The wedge's vertical
      // sides are the wall of the same material.
      if (q.side == FaceSide::Slope || q.side == FaceSide::Top) {
        TerrainSprite a = finish(idx, rampPick(idx, q, rawId), q.material);
        if (a.found) return a;
        if (q.kind == MaterialKind::Grass && plant && plant->grass[0].valid()) {
          r.found = true;
          r.sprite = plant->grass[0];
          r.rule = "ramp.grass.species";
          colourise(idx, r, q.material);
          return r;
        }
        TerrainSprite f = finish(idx, floorPick(idx, q, rawId), q.material);
        f.rule = "ramp.slope->floor";
        return f;
      }
      TerrainSprite w = finish(idx, wallPick(idx, q, rawId), q.material);
      w.rule = "ramp.side->wall";
      return w;
    }
    case TileShape::Empty:
    case TileShape::RampTop:
      break;
  }
  r.rule = "no-geometry";
  return r;
}

const char* creatureStateToken(CreatureState s) {
  switch (s) {
    case CreatureState::Default: return "DEFAULT";
    case CreatureState::Child: return "CHILD";
    case CreatureState::Animated: return "ANIMATED";
    case CreatureState::Corpse: return "CORPSE";
    case CreatureState::TrainedWar: return "TRAINED_WAR";
    case CreatureState::TrainedHunter: return "TRAINED_HUNTER";
  }
  return "DEFAULT";
}

CreatureSprite resolveCreature(const AssetIndex& idx, std::string_view species,
                               CreatureState state) {
  CreatureSprite r;
  const CreatureGraphics* g = nullptr;
  const char* via = "creature";
  if (auto it = idx.creatures.find(std::string(species)); it != idx.creatures.end()) {
    g = &it->second;
  } else if (auto ct = idx.creatureCastes.find(std::string(species));
             ct != idx.creatureCastes.end()) {
    g = &ct->second;
    via = "caste";
  }
  if (!g) {
    r.rule = "unknown-species";
    return r;
  }
  r.layered = g->layered;
  auto pick = [&](const char* token) -> bool {
    auto it = g->states.find(token);
    if (it == g->states.end()) return false;
    r.found = true;
    r.sprite = it->second;
    return true;
  };
  if (pick(creatureStateToken(state))) {
    r.rule = via;
    return r;
  }
  if (pick("DEFAULT")) {
    r.rule = via[0] == 'c' && via[1] == 'a' ? "caste.default-fallback" : "default-fallback";
    return r;
  }
  r.rule = g->layered ? "layered" : "no-default";
  return r;
}

}  // namespace df3d::assets
