// Appearance-reference constants and pure helpers shared by the validators,
// the synthetic builder, the bridge, and the world model's ingest adapter
// (schema v3). Header-only, C++17-compatible (the MSVC-built bridge
// includes it).
#pragma once

#include <cstddef>
#include <cstdint>

#include "mirror_generated.h"

namespace df3d::mirror {

inline constexpr uint16_t kNoPalette = 0xFFFF;  // AppearanceLayer.palette sentinel
inline constexpr int16_t kNoPaletteRow = -1;
inline constexpr uint8_t kMaxCellsX = 3;  // DF large images span at most 3x2 tiles
inline constexpr uint8_t kMaxCellsY = 2;

// FNV-1a over the fields of a layer stack: the `UnitAppearance.version`
// convention. Deterministic across builds/platforms (field-wise, not
// memory-wise), so the bridge, the builder and tests agree on it.
inline uint32_t appearanceHashBegin() { return 2166136261u; }
inline uint32_t appearanceHashByte(uint32_t h, uint8_t b) { return (h ^ b) * 16777619u; }
inline uint32_t appearanceHashU16(uint32_t h, uint16_t v) {
  h = appearanceHashByte(h, static_cast<uint8_t>(v & 0xFF));
  return appearanceHashByte(h, static_cast<uint8_t>(v >> 8));
}
inline uint32_t appearanceHashString(uint32_t h, const char* s, size_t n) {
  for (size_t i = 0; i < n; ++i) h = appearanceHashByte(h, static_cast<uint8_t>(s[i]));
  return appearanceHashByte(h, 0);  // terminator: "AB"+"C" != "A"+"BC"
}
// Per-layer contribution. `page` and `palette` are hashed by NAME (the
// snapshot-local indices differ from snapshot to snapshot); pass the
// palette name empty when the layer has none.
inline uint32_t appearanceHashLayer(uint32_t h, const char* page, size_t pageLen, uint16_t tileX,
                                    uint16_t tileY, uint8_t cellsX, uint8_t cellsY,
                                    const char* palette, size_t paletteLen, int16_t paletteRow,
                                    int16_t paletteKeyRow, int8_t offX, int8_t offY) {
  h = appearanceHashString(h, page, pageLen);
  h = appearanceHashU16(h, tileX);
  h = appearanceHashU16(h, tileY);
  h = appearanceHashByte(h, cellsX);
  h = appearanceHashByte(h, cellsY);
  h = appearanceHashString(h, palette, paletteLen);
  h = appearanceHashU16(h, static_cast<uint16_t>(paletteRow));
  h = appearanceHashU16(h, static_cast<uint16_t>(paletteKeyRow));
  h = appearanceHashByte(h, static_cast<uint8_t>(offX));
  h = appearanceHashByte(h, static_cast<uint8_t>(offY));
  return h;
}

}  // namespace df3d::mirror
