#pragma once

#include <algorithm>
#include <cstdint>
#include <span>

namespace df3d::assets {

// Choose opaque backing per tile, before palette replacement. A material's
// palette does not make already-coloured art palette-keyed. Transparent RGB
// is ignored: exporters can leave arbitrary colours underneath alpha zero.
inline uint32_t terrainFillBase(const uint8_t* rgba, int width, int height,
                               int x0, int y0, int tileWidth, int tileHeight,
                               std::span<const uint32_t> keys, uint32_t paletteBase) {
  uint64_t r = 0, g = 0, b = 0, count = 0;
  bool keyed = false;
  for (int y = y0; y < std::min(height, y0 + tileHeight); ++y) {
    for (int x = x0; x < std::min(width, x0 + tileWidth); ++x) {
      const auto* p = rgba + (static_cast<size_t>(y) * width + x) * 4;
      if (!p[3]) continue;
      const uint32_t rgb = (uint32_t{p[0]} << 16) | (uint32_t{p[1]} << 8) | p[2];
      keyed |= std::find(keys.begin(), keys.end(), rgb) != keys.end();
      if (p[3] < 128) continue;
      r += p[0]; g += p[1]; b += p[2]; ++count;
    }
  }
  if (keyed || !count) return paletteBase;
  return (static_cast<uint32_t>(r / count) << 16) |
         (static_cast<uint32_t>(g / count) << 8) | static_cast<uint32_t>(b / count);
}

}  // namespace df3d::assets
