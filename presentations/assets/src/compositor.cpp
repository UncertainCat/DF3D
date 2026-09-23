#include "df3d_assets/compositor.h"

#include <algorithm>
#include <cstring>

#include "df3d_assets/steam_install.h"

namespace df3d::assets {

// --- RgbaImage ---

RgbaImage RgbaImage::blank(int w, int h) {
  RgbaImage img;
  if (w > 0 && h > 0) {
    img.width = w;
    img.height = h;
    img.pixels.assign(static_cast<size_t>(w) * static_cast<size_t>(h) * 4, 0);
  }
  return img;
}

Rgba RgbaImage::get(int x, int y) const {
  if (!contains(x, y)) return Rgba{};
  const size_t o = (static_cast<size_t>(y) * static_cast<size_t>(width) + static_cast<size_t>(x)) * 4;
  return Rgba{pixels[o], pixels[o + 1], pixels[o + 2], pixels[o + 3]};
}

void RgbaImage::set(int x, int y, Rgba c) {
  if (!contains(x, y)) return;
  const size_t o = (static_cast<size_t>(y) * static_cast<size_t>(width) + static_cast<size_t>(x)) * 4;
  pixels[o] = c.r;
  pixels[o + 1] = c.g;
  pixels[o + 2] = c.b;
  pixels[o + 3] = c.a;
}

// --- palette swap ---

bool PaletteSwap::lookup(uint32_t rgb, uint32_t& out) const {
  auto it = std::lower_bound(table.begin(), table.end(), rgb,
                             [](const std::pair<uint32_t, uint32_t>& e, uint32_t k) { return e.first < k; });
  if (it == table.end() || it->first != rgb) return false;
  out = it->second;
  return true;
}

bool buildPaletteSwap(const RgbaImage& palette, int keyRow, int row, PaletteSwap& out) {
  out.table.clear();
  if (palette.empty() || keyRow < 0 || row < 0 || keyRow >= palette.height || row >= palette.height) {
    return false;
  }
  // Column order first so a duplicated key keeps its first column (the
  // bridge scans columns left to right and stops at the first match);
  // then a stable sort by key for the binary search.
  out.table.reserve(static_cast<size_t>(palette.width));
  for (int c = 0; c < palette.width; ++c) {
    out.table.emplace_back(packRgb(palette.get(c, keyRow)), packRgb(palette.get(c, row)));
  }
  std::stable_sort(out.table.begin(), out.table.end(),
                   [](const auto& a, const auto& b) { return a.first < b.first; });
  out.table.erase(std::unique(out.table.begin(), out.table.end(),
                              [](const auto& a, const auto& b) { return a.first == b.first; }),
                  out.table.end());
  return true;
}

// --- blending ---

void blendOver(Rgba& dst, Rgba src) {
  if (src.a == 0) return;
  if (src.a == 255 || dst.a == 0) {
    dst = src;
    return;
  }
  const int sa = src.a, da = dst.a;
  const int oa = sa + da * (255 - sa) / 255;
  auto mixc = [&](int s, int d) {
    return static_cast<uint8_t>((s * sa + d * da * (255 - sa) / 255) / (oa ? oa : 1));
  };
  dst.r = mixc(src.r, dst.r);
  dst.g = mixc(src.g, dst.g);
  dst.b = mixc(src.b, dst.b);
  dst.a = static_cast<uint8_t>(oa);
}

int fitFactor(int w, int h, int cw, int ch) {
  if (cw <= 0 || ch <= 0) return 1;
  const int fx = (w + cw - 1) / cw, fy = (h + ch - 1) / ch;
  return std::max(1, std::max(fx, fy));
}

bool drawLayer(RgbaImage& canvas, const RgbaImage& src, int srcX, int srcY, int srcW, int srcH,
               int factor, int offsetX, int offsetY, const PaletteSwap* swap) {
  if (srcW <= 0 || srcH <= 0 || srcX < 0 || srcY < 0 || srcX + srcW > src.width ||
      srcY + srcH > src.height) {
    return false;
  }
  if (factor < 1) factor = 1;
  for (int iy = 0; iy < srcH; iy += factor) {
    const int dy = iy / factor + offsetY;
    if (dy < 0 || dy >= canvas.height) continue;
    for (int ix = 0; ix < srcW; ix += factor) {
      const int dx = ix / factor + offsetX;
      if (dx < 0 || dx >= canvas.width) continue;
      Rgba p = src.get(srcX + ix, srcY + iy);
      if (p.a == 0) continue;
      if (swap) {
        uint32_t rep;
        if (swap->lookup(packRgb(p), rep)) {
          p.r = static_cast<uint8_t>(rep >> 16);
          p.g = static_cast<uint8_t>(rep >> 8);
          p.b = static_cast<uint8_t>(rep);
        }
      }
      const size_t o = (static_cast<size_t>(dy) * static_cast<size_t>(canvas.width) +
                        static_cast<size_t>(dx)) * 4;
      Rgba d{canvas.pixels[o], canvas.pixels[o + 1], canvas.pixels[o + 2], canvas.pixels[o + 3]};
      blendOver(d, p);
      canvas.pixels[o] = d.r;
      canvas.pixels[o + 1] = d.g;
      canvas.pixels[o + 2] = d.b;
      canvas.pixels[o + 3] = d.a;
    }
  }
  return true;
}

// --- the compositor ---

namespace {

struct ResolvedLayer {
  const TilePage* page = nullptr;
  const RgbaImage* image = nullptr;
  const RgbaImage* palette = nullptr;
};

bool resolveLayer(const CompositeContext& ctx, const wm::AppearanceLayer& l, size_t i,
                  ResolvedLayer& out, std::string& why) {
  const std::string_view pageName = ctx.names.page ? ctx.names.page(l.page) : std::string_view();
  if (pageName.empty()) {
    why = "layer " + std::to_string(i) + ": unknown page id " + std::to_string(l.page);
    return false;
  }
  out.page = ctx.index ? ctx.index->page(ctx.index->pageIndex(pageName)) : nullptr;
  if (!out.page) {
    why = "layer " + std::to_string(i) + ": page " + std::string(pageName) + " not in the asset index";
    return false;
  }
  if (out.page->absPath.empty()) {
    why = "layer " + std::to_string(i) + ": page " + std::string(pageName) + " has no image file";
    return false;
  }
  out.image = ctx.load ? ctx.load(out.page->absPath) : nullptr;
  if (!out.image || out.image->empty()) {
    why = "layer " + std::to_string(i) + ": cannot load " + out.page->absPath;
    return false;
  }
  if (l.palette != wm::kNoPalette) {
    const std::string_view pal = ctx.names.palette ? ctx.names.palette(l.palette) : std::string_view();
    if (pal.empty()) {
      why = "layer " + std::to_string(i) + ": unknown palette id " + std::to_string(l.palette);
      return false;
    }
    const std::string path = joinPath(ctx.installRoot, pal);
    out.palette = ctx.load ? ctx.load(path) : nullptr;
    if (!out.palette || out.palette->empty()) {
      why = "layer " + std::to_string(i) + ": cannot load palette " + path;
      return false;
    }
  }
  return true;
}

}  // namespace

CompositeResult compositeAppearance(const CompositeContext& ctx,
                                    std::span<const wm::AppearanceLayer> layers) {
  CompositeResult r;
  if (layers.empty()) {
    r.why = "no layers";
    return r;
  }
  // Resolve everything first so a failure leaves no half-drawn sprite.
  std::vector<ResolvedLayer> resolved(layers.size());
  for (size_t i = 0; i < layers.size(); ++i) {
    if (!resolveLayer(ctx, layers[i], i, resolved[i], r.why)) return r;
  }
  r.cellsX = std::max<int>(1, layers[0].cellsX);
  r.cellsY = std::max<int>(1, layers[0].cellsY);
  r.tileW = resolved[0].page->tileW;
  r.tileH = resolved[0].page->tileH;
  if (r.tileW <= 0 || r.tileH <= 0) {
    r.why = "first layer's page has no tile size";
    return r;
  }
  const int bodyW = r.cellsX * r.tileW, bodyH = r.cellsY * r.tileH;
  // Native wieldable LARGE_IMAGE layers overflow the body cell. Do not
  // shrink their blades into the body, where later clothing hides them.
  // Other oversized layers retain the existing policy until independently
  // verified (notably the native hair eligibility rules are incomplete).
  const auto wieldable = [](const TilePage& p) {
    return p.name == "WIELDABLES" || p.name == "WIELDABLES_TALL" || p.name == "WIELDABLES_WIDE";
  };
  int minX = 0, minY = 0, maxX = bodyW, maxY = bodyH;
  for (size_t i = 0; i < layers.size(); ++i) {
    if (!wieldable(*resolved[i].page)) continue;
    const auto& l = layers[i];
    const int w = std::max<int>(1, l.cellsX) * resolved[i].page->tileW;
    const int h = std::max<int>(1, l.cellsY) * resolved[i].page->tileH;
    const int x = bodyW - w + l.offsetX, y = bodyH - h + l.offsetY;
    minX = std::min(minX, x); minY = std::min(minY, y);
    maxX = std::max(maxX, x + w); maxY = std::max(maxY, y + h);
  }
  r.originX = minX; r.originY = minY;
  RgbaImage canvas = RgbaImage::blank(maxX - minX, maxY - minY);

  PaletteSwap swap;
  for (size_t i = 0; i < layers.size(); ++i) {
    const wm::AppearanceLayer& l = layers[i];
    const ResolvedLayer& rl = resolved[i];
    const int ltw = rl.page->tileW, lth = rl.page->tileH;
    const int cx = std::max<int>(1, l.cellsX), cy = std::max<int>(1, l.cellsY);
    const int srcX = l.tileX * ltw, srcY = l.tileY * lth;
    const int srcW = cx * ltw, srcH = cy * lth;
    const PaletteSwap* sw = nullptr;
    if (rl.palette) {
      if (!buildPaletteSwap(*rl.palette, l.paletteKeyRow, l.paletteRow, swap)) {
        r.why = "layer " + std::to_string(i) + ": palette rows " + std::to_string(l.paletteKeyRow) +
                " / " + std::to_string(l.paletteRow) + " outside the palette image (" +
                std::to_string(rl.palette->width) + "x" + std::to_string(rl.palette->height) + ")";
        return r;
      }
      sw = &swap;
    }
    const bool overflow = wieldable(*rl.page);
    const int f = overflow ? 1 : fitFactor(srcW, srcH, bodyW, bodyH);
    const int offsetX = l.offsetX - minX + (overflow ? bodyW - srcW : 0);
    const int offsetY = l.offsetY - minY + (overflow ? bodyH - srcH : 0);
    if (f > 1) ++r.layersScaled;
    if (!drawLayer(canvas, *rl.image, srcX, srcY, srcW, srcH, f, offsetX, offsetY, sw)) {
      r.why = "layer " + std::to_string(i) + ": tile (" + std::to_string(l.tileX) + "," +
              std::to_string(l.tileY) + ") x " + std::to_string(cx) + "x" + std::to_string(cy) +
              " outside page " + rl.page->name + " (" + std::to_string(rl.image->width) + "x" +
              std::to_string(rl.image->height) + ")";
      return r;
    }
    ++r.layersDrawn;
  }
  r.image = std::move(canvas);
  r.ok = true;
  return r;
}

// --- cache ---

const CompositeResult* CompositeCache::find(uint32_t version) const {
  auto it = entries_.find(version);
  return it == entries_.end() ? nullptr : &it->second;
}

const CompositeResult& CompositeCache::put(uint32_t version, CompositeResult result) {
  return entries_.insert_or_assign(version, std::move(result)).first->second;
}

size_t CompositeCache::retain(const std::function<bool(uint32_t)>& live) {
  size_t dropped = 0;
  for (auto it = entries_.begin(); it != entries_.end();) {
    if (live(it->first)) {
      ++it;
    } else {
      it = entries_.erase(it);
      ++dropped;
    }
  }
  return dropped;
}

size_t CompositeCache::imageBytes() const {
  size_t n = 0;
  for (const auto& [v, r] : entries_) n += r.image.pixels.size();
  return n;
}

}  // namespace df3d::assets
