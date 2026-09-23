// Terrain constants and small pure helpers shared by the validators, the
// synthetic builder, the bridge, and the world model's ingest adapter
// (schema v2). Header-only, C++17-compatible (the MSVC-built bridge
// includes it).
#pragma once

#include <cstddef>
#include <cstdint>

#include "mirror_generated.h"

namespace df3d::mirror {

inline constexpr int32_t kBlockSize = 16;                            // tiles per block edge
inline constexpr size_t kTilesPerBlock = kBlockSize * kBlockSize;    // 256
inline constexpr uint16_t kNoMaterial = 0xFFFF;                      // TileState.material sentinel
inline constexpr uint8_t kMaxLiquidLevel = 7;

// Number of blocks covering `tiles` tiles along one axis (ceil division).
inline constexpr int32_t blocksAlong(int32_t tiles) {
  return (tiles + kBlockSize - 1) / kBlockSize;
}

// Total block count for a map (z is per level, not per 16).
inline constexpr int64_t blockCount(int32_t sizeX, int32_t sizeY, int32_t sizeZ) {
  return static_cast<int64_t>(blocksAlong(sizeX)) * blocksAlong(sizeY) * sizeZ;
}

// Index into MapBlock.tiles for local coordinates (row-major, y outer).
inline constexpr size_t tileIndex(int32_t localX, int32_t localY) {
  return static_cast<size_t>(localY) * kBlockSize + static_cast<size_t>(localX);
}

// A tile with nothing in it: open air, no material, no liquid, no flags.
inline TileState emptyTile() {
  return TileState(TileShape::Empty, MaterialKind::None, kNoMaterial, 0, LiquidKind::None,
                   TileFlags::NONE, df3d::mirror::DesignationKind::None);
}

// One shared range check for tile values, whichever transport carried them
// (ring TileState or resident grid TerrainTile). Values are the raw wire
// bytes; returns the first field that is out of range, or None.
enum class TileFault : uint8_t {
  None = 0, Designation, Shape, MaterialKind, LiquidKind, Flags, LiquidLevel, LiquidConsistency
};
struct RawTileValues {
  uint8_t shape, materialKind, liquidLevel, liquidKind, flags, designation;
};
inline TileFault checkTileValues(const RawTileValues& t) {
  if (t.designation > static_cast<uint8_t>(DesignationKind::MAX)) return TileFault::Designation;
  if (t.shape > static_cast<uint8_t>(TileShape::MAX)) return TileFault::Shape;
  if (t.materialKind > static_cast<uint8_t>(MaterialKind::MAX)) return TileFault::MaterialKind;
  if (t.liquidKind > static_cast<uint8_t>(LiquidKind::MAX)) return TileFault::LiquidKind;
  if ((t.flags & ~static_cast<uint8_t>(TileFlags::ANY)) != 0) return TileFault::Flags;
  if (t.liquidLevel > kMaxLiquidLevel) return TileFault::LiquidLevel;
  if ((t.liquidLevel > 0) != (t.liquidKind != static_cast<uint8_t>(LiquidKind::None)))
    return TileFault::LiquidConsistency;
  return TileFault::None;
}
inline const char* tileFaultName(TileFault f) {
  switch (f) {
    case TileFault::None: return "ok";
    case TileFault::Designation: return "invalid designation kind";
    case TileFault::Shape: return "invalid shape value";
    case TileFault::MaterialKind: return "invalid material_kind value";
    case TileFault::LiquidKind: return "invalid liquid_kind value";
    case TileFault::Flags: return "unknown flag bits";
    case TileFault::LiquidLevel: return "liquid_level exceeds 7";
    case TileFault::LiquidConsistency: return "liquid_level inconsistent with liquid_kind";
  }
  return "?";
}

// Two tiles are equal iff every field matches (padding is ignored).
inline bool tileEquals(const TileState& a, const TileState& b) {
  return a.shape() == b.shape() && a.material_kind() == b.material_kind() &&
         a.material() == b.material() && a.liquid_level() == b.liquid_level() &&
         a.liquid_kind() == b.liquid_kind() && a.flags() == b.flags() &&
         a.designation() == b.designation();
}

}  // namespace df3d::mirror
