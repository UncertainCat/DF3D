// Building / map-item constants and pure helpers shared by the validators,
// the synthetic builder, the bridge, and the world model's ingest adapter
// (schema v4). Header-only, C++17-compatible (the MSVC-built bridge
// includes it).
#pragma once

#include <cstddef>
#include <cstdint>
#include <algorithm>
#include <optional>

#include "mirror_generated.h"

namespace df3d::mirror {

inline constexpr uint16_t kNoSubtype = 0xFFFF;  // Building.subtype / MapItem.subtype sentinel
inline constexpr uint32_t kMinStack = 1;         // MapItem.stack lower bound
// Frames the bridge re-sends a building / item change or removal,
// and the tick gap beyond which a live client asks for a Full again.
inline constexpr uint32_t kEntityRepeatFrames = 8;

struct BuildingFootprint {
  int32_t x1, y1, x2, y2, cx, cy;
};

// Native saves can retain zone bounds beyond the embark. Publish only their
// intersection with the map, without changing DF or inventing an edge tile for
// a wholly off-map record. Extents must be sampled at these world coordinates.
inline std::optional<BuildingFootprint> clipBuildingFootprint(
    BuildingFootprint b, int32_t z, int32_t width, int32_t height, int32_t depth) {
  if (width <= 0 || height <= 0 || z < 0 || z >= depth) return std::nullopt;
  if (b.x1 > b.x2) std::swap(b.x1, b.x2);
  if (b.y1 > b.y2) std::swap(b.y1, b.y2);
  b.x1 = std::max(b.x1, 0); b.y1 = std::max(b.y1, 0);
  b.x2 = std::min(b.x2, width - 1); b.y2 = std::min(b.y2, height - 1);
  if (b.x1 > b.x2 || b.y1 > b.y2) return std::nullopt;
  b.cx = std::clamp(b.cx, b.x1, b.x2);
  b.cy = std::clamp(b.cy, b.y1, b.y2);
  return b;
}

// Tile count of a building's inclusive rectangle (x1<=x2, y1<=y2 assumed).
inline constexpr int64_t rectArea(int32_t x1, int32_t y1, int32_t x2, int32_t y2) {
  return static_cast<int64_t>(x2 - x1 + 1) * static_cast<int64_t>(y2 - y1 + 1);
}

}  // namespace df3d::mirror
