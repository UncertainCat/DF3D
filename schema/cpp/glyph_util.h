// Classic-glyph constants shared by the validators, the synthetic builder,
// the bridge, and the world model's ingest adapter (schema v5).
// Header-only, C++17-compatible (the MSVC-built bridge includes it).
#pragma once

#include <cstdint>

#include "mirror_generated.h"

namespace df3d::mirror {

// DF colour triples: foreground / background index 0..7 (the eight
// classic colours; bright 1 selects the light variant of the foreground).
inline constexpr uint8_t kMaxGlyphColor = 7;

// Field-wise equality of the generated struct (flatc emits none).
inline bool glyphEquals(const Glyph& a, const Glyph& b) {
  return a.tile() == b.tile() && a.fg() == b.fg() && a.bg() == b.bg() && a.bright() == b.bright();
}

}  // namespace df3d::mirror
