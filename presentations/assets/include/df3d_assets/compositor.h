// Unit appearance compositor: turns a unit's published layer stack into one RGBA sprite the way DF does (palette swap, fit-scaling, alpha composite); pure, engine-agnostic, arithmetic kept in step with bridge/plugin/appearance.cpp.
#pragma once

#include <cstdint>
#include <functional>
#include <span>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

#include "df3d_assets/asset_index.h"
#include "wm/types.h"

namespace df3d::assets {

struct Rgba {
  uint8_t r = 0, g = 0, b = 0, a = 0;
  friend bool operator==(const Rgba&, const Rgba&) = default;
};

// RGBA8, row-major, top row first (PNG / Godot Image order).
struct RgbaImage {
  int width = 0, height = 0;
  std::vector<uint8_t> pixels;

  static RgbaImage blank(int w, int h);
  bool empty() const { return width <= 0 || height <= 0; }
  bool contains(int x, int y) const { return x >= 0 && y >= 0 && x < width && y < height; }
  Rgba get(int x, int y) const;
  void set(int x, int y, Rgba c);
};

// Injected image access: path -> decoded image (nullptr when unreadable), owned by the loader for the call.
using ImageLoader = std::function<const RgbaImage*(const std::string& absPath)>;

// Resolvers for the model-wide ids a layer carries (WorldModel::tilePageName
// / paletteName). Empty = unknown.
struct AppearanceNames {
  std::function<std::string_view(wm::PageId)> page;
  std::function<std::string_view(wm::PaletteId)> palette;
};

struct CompositeContext {
  const AssetIndex* index = nullptr;  // tile pages: file + tile dims
  std::string installRoot;            // palette paths are install-relative
  AppearanceNames names;
  ImageLoader load;
};

struct CompositeResult {
  bool ok = false;
  RgbaImage image;         // the unit's sprite (transparent background)
  int cellsX = 0, cellsY = 0;  // the unit's cell in tiles (first layer)
  int originX = 0, originY = 0; // image top-left relative to logical body, pixels
  int tileW = 0, tileH = 0;    // pixels per tile of the first layer's page
  int layersDrawn = 0;
  int layersScaled = 0;    // layers larger than the cell, scaled down
  std::string why;         // reason when !ok
};

// Composites the stack; fails (ok = false, `why` set) on an empty stack, unknown page/palette or out-of-range rect.
CompositeResult compositeAppearance(const CompositeContext& ctx,
                                    std::span<const wm::AppearanceLayer> layers);

// --- building blocks (pure, tier-0 tested) ---

// DF's colour swap: column c of `keyRow` -> column c of `row`. Only the
// RGB of keys is matched; a key that appears twice keeps its first column.
struct PaletteSwap {
  std::vector<std::pair<uint32_t, uint32_t>> table;  // (key rgb, replacement rgb), sorted
  bool lookup(uint32_t rgb, uint32_t& out) const;
  bool empty() const { return table.empty(); }
};
// False when either row is outside the palette image.
bool buildPaletteSwap(const RgbaImage& palette, int keyRow, int row, PaletteSwap& out);
inline uint32_t packRgb(Rgba c) {
  return (uint32_t{c.r} << 16) | (uint32_t{c.g} << 8) | uint32_t{c.b};
}

// Alpha-over in 8-bit integer arithmetic (the bridge's formula).
void blendOver(Rgba& dst, Rgba src);

// Nearest-neighbour reduction factor: 1 when (w, h) fits (cw, ch), else the smallest integer that does.
int fitFactor(int w, int h, int cw, int ch);

// Draws a source region onto the canvas at an offset, reduced by `factor`, optionally palette-swapped; false when the region is outside `src`.
bool drawLayer(RgbaImage& canvas, const RgbaImage& src, int srcX, int srcY, int srcW, int srcH,
               int factor, int offsetX, int offsetY, const PaletteSwap* swap);

// Composite cache keyed by appearance version (the bridge's stack hash), the whole identity of a sprite.
class CompositeCache {
 public:
  const CompositeResult* find(uint32_t version) const;
  // Inserts or replaces; returns the stored entry.
  const CompositeResult& put(uint32_t version, CompositeResult result);
  bool erase(uint32_t version) { return entries_.erase(version) != 0; }
  // Drops every entry whose version `live(version)` rejects; returns how many.
  size_t retain(const std::function<bool(uint32_t)>& live);
  void clear() { entries_.clear(); }
  size_t size() const { return entries_.size(); }
  // Bytes of image data held.
  size_t imageBytes() const;

 private:
  std::unordered_map<uint32_t, CompositeResult> entries_;
};

}  // namespace df3d::assets
