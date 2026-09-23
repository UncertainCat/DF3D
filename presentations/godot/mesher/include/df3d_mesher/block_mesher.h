// DF3D terrain mesher: engine-agnostic, deterministic per-block mesh manifests (tagged quads in DF tile space, CCW winding in right-handed (x, y, z), +z up; a reflecting engine reverses winding).
#pragma once

#include <array>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

#include "wm/types.h"
#include "wm/world_model.h"

namespace df3d::mesher {

struct Vec3 {
  float x = 0, y = 0, z = 0;
  friend bool operator==(const Vec3&, const Vec3&) = default;
};

// Height of a floor slab above the tile bottom; units stand on it.
inline constexpr float kFloorHeight = 0.1f;
// Height of a ramp that has no wall to lean against (first-pass fallback).
inline constexpr float kLoneRampHeight = 0.5f;
// Shrub / sapling decals sit this far above the floor slab (no z-fighting).
inline constexpr float kDecalLift = 0.02f;
// Leaf shells have a tiny gap at tile boundaries, including vertical ones.
inline constexpr float kLeafInset = 0.001f;
// Map the inset shell back to the whole source tile, without cropping its art.
inline float leafTextureCoordinate(float tileCoordinate) {
  return (tileCoordinate - kLeafInset) / (1.0f - 2.0f * kLeafInset);
}

enum class FaceDir : uint8_t {
  PosX,  // east
  NegX,  // west
  PosY,  // south (DF +y)
  NegY,  // north
  PosZ,  // top
  NegZ,  // bottom
  Slope,  // ramp slope: normal has a horizontal and a vertical component
  Cross,  // legacy vertical cross planes; double-sided
};

enum class FacePart : uint8_t {
  Terrain,  // the tile's own body: cube, floor slab, wedge
  Feature,  // marker geometry: stair decal, boulder/pebble box, leaf shell, shrub decal
  Liquid,   // water / magma surface and sides
  // Undisclosed mass cap: opaque, shape Unknown, flags kTileHidden, merged per block; lx, ly name the origin tile.
  Hidden,
};

// FaceTag::walls bits: which of the eight same-z neighbours occlude like cubes (north = -y, west = -x).
inline constexpr uint8_t kWallN = 1u << 0;
inline constexpr uint8_t kWallS = 1u << 1;
inline constexpr uint8_t kWallW = 1u << 2;
inline constexpr uint8_t kWallE = 1u << 3;
inline constexpr uint8_t kWallNW = 1u << 4;
inline constexpr uint8_t kWallNE = 1u << 5;
inline constexpr uint8_t kWallSW = 1u << 6;
inline constexpr uint8_t kWallSE = 1u << 7;

struct FaceTag {
  wm::TileShape shape = wm::TileShape::Empty;
  wm::MaterialKind materialKind = wm::MaterialKind::None;
  wm::MaterialId material = wm::kNoMaterial;
  wm::LiquidKind liquid = wm::LiquidKind::None;  // Liquid faces only
  uint8_t liquidLevel = 0;                        // Liquid faces only (1..7)
  uint8_t flags = 0;                              // wm::kTile* bits
  FaceDir dir = FaceDir::PosZ;
  FacePart part = FacePart::Terrain;
  // Ramp faces: the cardinal side the wedge rises toward; PosZ = lone ramp (half block).
  FaceDir slopeHigh = FaceDir::PosZ;
  // Same-z cube neighbours (kWall* bits) for every face; map edges and unobserved blocks count as open.
  uint8_t walls = 0;
  uint8_t lx = 0, ly = 0;  // tile within the block (z is the block's z)
};

struct Face {
  std::array<Vec3, 4> v;  // CCW seen from the normal side (see header note)
  Vec3 normal;
  FaceTag tag;
};

struct BlockMesh {
  wm::BlockPos pos;
  uint64_t version = 0;  // the block's model version when meshed (0 = unknown block)
  std::vector<Face> faces;
};

struct MeshOptions {
  // z-slice: tiles above topZ are cut away (treated as open air), so the
  // layer at topZ shows its tops. Blocks above topZ are not meshed.
  int32_t topZ = std::numeric_limits<int32_t>::max();
  // Debug aid: mesh Hidden tiles as their true state (off: hidden tiles emit only Hidden caps, except DigDesignated ones).
  bool revealHidden = false;
};

// Neighbour lookups go through this so the mesher is testable on hand-built
// maps (tier 0) as well as on the world model (tier 1).
class BlockSource {
 public:
  virtual ~BlockSource() = default;
  virtual wm::TilePos mapSize() const = 0;
  virtual std::optional<wm::BlockView> block(wm::BlockPos b) const = 0;
};

class WorldModelSource final : public BlockSource {
 public:
  explicit WorldModelSource(const wm::WorldModel& model) : model_(model) {}
  wm::TilePos mapSize() const override { return model_.mapSize(); }
  std::optional<wm::BlockView> block(wm::BlockPos b) const override { return model_.block(b); }

 private:
  const wm::WorldModel& model_;
};

// Meshes one block culling against neighbours; unknown block = empty mesh, version 0; hidden caps merged last.
BlockMesh meshBlock(const BlockSource& src, wm::BlockPos pos, const MeshOptions& options = {});

struct TerrainManifest {
  int32_t topZ = 0, bottomZ = 0;
  size_t blocksVisited = 0;
  std::vector<BlockMesh> blocks;  // only blocks with at least one face, ordered by (bz, by, bx)
};

// Meshes every block with bottomZ <= bz <= min(topZ, mapZ - 1).
TerrainManifest buildTerrainManifest(const BlockSource& src, int32_t topZ, int32_t bottomZ,
                                     const MeshOptions& options = {});

// Whether a tile contributes its own non-Hidden geometry under the reveal rule.
bool producesGeometry(const wm::TileState& t, bool revealHidden);

const char* faceDirName(FaceDir d);

}  // namespace df3d::mesher
