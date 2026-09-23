#pragma once

#include <map>

#include "df3d_assets/compositor.h"
#include "df3d_assets/resolver.h"

namespace df3d::assets {

// Dominant fully opaque source color; transparent RGB and partially
// transparent antialias pixels cannot choose the backing. Ties are stable.
inline Rgba dominantOpaque(const RgbaImage& image, PixelRect rect, Rgba fallback) {
  std::map<uint32_t, size_t> counts;
  for (int y = rect.py; y < rect.py + rect.ph; ++y)
    for (int x = rect.px; x < rect.px + rect.pw; ++x) {
      if (!image.contains(x, y)) continue;
      const Rgba p = image.get(x, y);
      if (p.a == 255) ++counts[(uint32_t{p.r} << 16) | (uint32_t{p.g} << 8) | p.b];
    }
  size_t best = 0;
  for (const auto& [rgb, count] : counts) if (count > best) {
    best = count;
    fallback = {static_cast<uint8_t>(rgb >> 16), static_cast<uint8_t>(rgb >> 8),
                static_cast<uint8_t>(rgb), 255};
  }
  return fallback;
}

inline Rgba nativeRockBacking(const AssetIndex& index, const ImageLoader& load,
                              Rgba fallback = {64, 64, 64, 255}) {
  if (load) if (const SpriteRef* rock = index.tile("HIDDEN_ROCK_1"))
    if (const TilePage* page = index.page(rock->page))
      if (const RgbaImage* image = load(page->absPath))
        fallback = dominantOpaque(*image, index.pixels(*rock), fallback);
  fallback.a = 255;
  return fallback;
}

// Native wall overlays are blended over an opaque backing. Round to nearest
// as the displayed native overlay does; do not change unit-stack arithmetic.
inline Rgba blendWallOverOpaque(Rgba background, Rgba foreground) {
  const int a = foreground.a;
  const auto channel = [a](int src, int dst) {
    return static_cast<uint8_t>((src * a + dst * (255 - a) + 127) / 255);
  };
  return {channel(foreground.r, background.r), channel(foreground.g, background.g),
          channel(foreground.b, background.b), 255};
}

// One opaque image for one top face. This never creates coincident geometry.
// Runtime images are injected so topology/composition tests ship no game art.
inline RgbaImage composeWallTop(const AssetIndex& index, const TerrainSprite& wall,
                                const ImageLoader& load, std::string& why) {
  why.clear();
  const PixelRect dimensions = index.pixels(wall.sprite);
  if (!wall.found || !wall.layeredWall || dimensions.pw <= 0 || dimensions.ph <= 0 ||
      dimensions.pw > 256 || dimensions.ph > 256 || wall.wallLayers.size() > 4 || !load) {
    why = "invalid wall composition"; return {};
  }
  PaletteSwap swap;
  bool recolor = false;
  Rgba backing{64, 64, 64, 255};
  if (index.palette) if (const RgbaImage* palette = load(index.palette->absPath)) {
    const int row = wall.paletteRow >= 0 ? wall.paletteRow : index.palette->defaultRow;
    if (palette->contains(0, row)) backing = palette->get(0, row);
    if (wall.paletteRow >= 0)
      recolor = buildPaletteSwap(*palette, index.palette->defaultRow, row, swap);
  }
  // Native runtime surfaces use the same opaque rock backing for revealed
  // soil, stone and constructed walls. Source it from the installed art.
  backing = nativeRockBacking(index, load, backing);
  RgbaImage output = RgbaImage::blank(dimensions.pw, dimensions.ph);
  for (int y = 0; y < output.height; ++y)
    for (int x = 0; x < output.width; ++x) output.set(x, y, backing);
  for (const SpriteRef& layer : wall.wallLayers) {
    const TilePage* page = index.page(layer.page);
    const RgbaImage* image = page ? load(page->absPath) : nullptr;
    const PixelRect rect = index.pixels(layer);
    if (!image || rect.pw != output.width || rect.ph != output.height ||
        !image->contains(rect.px, rect.py) || !image->contains(rect.px + rect.pw - 1, rect.py + rect.ph - 1)) {
      why = "wall layer image missing or dimensions inconsistent"; return {};
    }
    for (int y = 0; y < output.height; ++y) for (int x = 0; x < output.width; ++x) {
      Rgba p = image->get(rect.px + x, rect.py + y);
      uint32_t replacement = 0;
      if (recolor && p.a && swap.lookup((uint32_t{p.r} << 16) | (uint32_t{p.g} << 8) | p.b, replacement)) {
        p.r = static_cast<uint8_t>(replacement >> 16);
        p.g = static_cast<uint8_t>(replacement >> 8);
        p.b = static_cast<uint8_t>(replacement);
      }
      output.set(x, y, blendWallOverOpaque(output.get(x, y), p));
    }
  }
  return output;
}

}  // namespace df3d::assets
