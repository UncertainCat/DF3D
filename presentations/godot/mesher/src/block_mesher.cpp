#include "df3d_mesher/block_mesher.h"

#include <algorithm>
#include <cmath>

namespace df3d::mesher {

namespace {

using wm::kBlockSize;
using wm::TileShape;
using wm::TileState;

constexpr float kEps = 1e-4f;
constexpr float kH = kFloorHeight;

// --- neighbourhood ---------------------------------------------------------

// One cell of the 18x18x3 neighbourhood around a block. `phantom` cells are
// undisclosed hidden tiles: they occlude like a full cube and emit only
// Hidden caps toward non-cube neighbours.
struct Cell {
  TileState t;
  bool phantom = false;
};

constexpr int kN = kBlockSize + 2;  // padded extent per horizontal axis

struct Neighbourhood {
  std::array<Cell, static_cast<size_t>(kN) * kN * 3> cells;
  // lx, ly in -1..16; dz in -1..1 (relative to the block's z).
  const Cell& at(int lx, int ly, int dz) const {
    return cells[(static_cast<size_t>(dz + 1) * kN + static_cast<size_t>(ly + 1)) * kN +
                 static_cast<size_t>(lx + 1)];
  }
  Cell& at(int lx, int ly, int dz) {
    return cells[(static_cast<size_t>(dz + 1) * kN + static_cast<size_t>(ly + 1)) * kN +
                 static_cast<size_t>(lx + 1)];
  }
};

Cell openCell() {
  Cell c;
  c.t.shape = TileShape::Empty;
  return c;
}

Neighbourhood gather(const BlockSource& src, wm::BlockPos pos, const MeshOptions& options) {
  Neighbourhood n;
  const wm::TilePos map = src.mapSize();
  const int32_t bxCount = (map.x + kBlockSize - 1) / kBlockSize;
  const int32_t byCount = (map.y + kBlockSize - 1) / kBlockSize;
  // The 27 blocks touching this one, fetched once. Neighbours past the map
  // edge (bx/by of -1 or the block count) are never requested from the source:
  // they stay unobserved, which the face rules treat as open.
  std::array<std::optional<wm::BlockView>, 27> views;
  for (int dz = -1; dz <= 1; ++dz)
    for (int dy = -1; dy <= 1; ++dy)
      for (int dx = -1; dx <= 1; ++dx) {
        const wm::BlockPos b{pos.bx + dx, pos.by + dy, pos.bz + dz};
        auto& slot = views[static_cast<size_t>((dz + 1) * 9 + (dy + 1) * 3 + (dx + 1))];
        if (b.bz < 0 || b.bz >= map.z || b.bz > options.topZ) continue;  // cut / out of map
        if (b.bx < 0 || b.by < 0 || b.bx >= bxCount || b.by >= byCount) continue;  // out of map
        slot = src.block(b);
      }
  const int32_t x0 = pos.bx * kBlockSize, y0 = pos.by * kBlockSize;
  for (int dz = -1; dz <= 1; ++dz) {
    for (int ly = -1; ly <= kBlockSize; ++ly) {
      for (int lx = -1; lx <= kBlockSize; ++lx) {
        Cell& c = n.at(lx, ly, dz);
        c = openCell();
        const int32_t x = x0 + lx, y = y0 + ly, z = pos.bz + dz;
        if (x < 0 || y < 0 || x >= map.x || y >= map.y) continue;
        if (z < 0 || z >= map.z || z > options.topZ) continue;
        const int dx = lx < 0 ? -1 : (lx >= kBlockSize ? 1 : 0);
        const int dy = ly < 0 ? -1 : (ly >= kBlockSize ? 1 : 0);
        const auto& view = views[static_cast<size_t>((dz + 1) * 9 + (dy + 1) * 3 + (dx + 1))];
        if (!view) continue;  // never observed: open
        const int ix = ((lx % kBlockSize) + kBlockSize) % kBlockSize;
        const int iy = ((ly % kBlockSize) + kBlockSize) % kBlockSize;
        c.t = view->tiles[wm::tileIndexInBlock(ix, iy)];
        if ((c.t.flags & wm::kTileHidden) && !options.revealHidden &&
            !(c.t.flags & wm::kTileDigDesignated)) {
          c.phantom = true;
        }
      }
    }
  }
  return n;
}

// --- shape classification --------------------------------------------------

bool isCube(const Cell& c) {
  if (c.phantom) return true;
  switch (c.t.shape) {
    case TileShape::Wall:
    case TileShape::Fortification:
    case TileShape::TreeTrunk:
    case TileShape::Unknown: return true;
    default: return false;
  }
}

bool hasFloorSlab(const Cell& c) {
  if (c.phantom) return false;
  switch (c.t.shape) {
    case TileShape::Floor:
    case TileShape::StairUp:
    case TileShape::StairDown:
    case TileShape::StairUpDown:
    case TileShape::Boulder:
    case TileShape::Pebbles:
    case TileShape::Shrub:
    case TileShape::Sapling: return true;
    default: return false;
  }
}

// Height the liquid column starts at inside this cell.
float liquidBase(const Cell& c) { return hasFloorSlab(c) ? kH : 0.0f; }

float liquidTop(const Cell& c) {
  if (c.phantom || c.t.liquidKind == wm::LiquidKind::None || c.t.liquidLevel == 0) return 0.0f;
  const float base = liquidBase(c);
  const float lvl = std::min<float>(c.t.liquidLevel, wm::kMaxLiquidLevel) / 7.0f;
  return base + (1.0f - base) * lvl;
}

// --- occlusion --------------------------------------------------------------

// A rectangle in a face plane. Plane axes: ±X → (y, z), ±Y → (x, z), ±Z →
// (x, y). Coordinates are tile-local, 0..1.
struct Rect {
  float a0, b0, a1, b1;
  bool contains(const Rect& r) const {
    return a0 <= r.a0 + kEps && b0 <= r.b0 + kEps && a1 >= r.a1 - kEps && b1 >= r.b1 - kEps;
  }
};

constexpr Rect kFull{0, 0, 1, 1};

bool isLateral(FaceDir d) {
  return d == FaceDir::PosX || d == FaceDir::NegX || d == FaceDir::PosY || d == FaceDir::NegY;
}

FaceDir opposite(FaceDir d) {
  switch (d) {
    case FaceDir::PosX: return FaceDir::NegX;
    case FaceDir::NegX: return FaceDir::PosX;
    case FaceDir::PosY: return FaceDir::NegY;
    case FaceDir::NegY: return FaceDir::PosY;
    case FaceDir::PosZ: return FaceDir::NegZ;
    case FaceDir::NegZ: return FaceDir::PosZ;
    default: return d;
  }
}

// FaceTag::walls for the tile: the eight same-z neighbours that are cubes.
uint8_t wallMask(const Neighbourhood& n, int lx, int ly) {
  uint8_t m = 0;
  if (isCube(n.at(lx, ly - 1, 0))) m |= kWallN;
  if (isCube(n.at(lx, ly + 1, 0))) m |= kWallS;
  if (isCube(n.at(lx - 1, ly, 0))) m |= kWallW;
  if (isCube(n.at(lx + 1, ly, 0))) m |= kWallE;
  if (isCube(n.at(lx - 1, ly - 1, 0))) m |= kWallNW;
  if (isCube(n.at(lx + 1, ly - 1, 0))) m |= kWallNE;
  if (isCube(n.at(lx - 1, ly + 1, 0))) m |= kWallSW;
  if (isCube(n.at(lx + 1, ly + 1, 0))) m |= kWallSE;
  return m;
}

// Direction a ramp's high side faces (the wall it leans on), if any.
std::optional<FaceDir> rampHighSide(const Neighbourhood& n, int lx, int ly) {
  const FaceDir order[] = {FaceDir::NegY, FaceDir::PosX, FaceDir::PosY, FaceDir::NegX};
  for (FaceDir d : order) {
    const int dx = d == FaceDir::PosX ? 1 : (d == FaceDir::NegX ? -1 : 0);
    const int dy = d == FaceDir::PosY ? 1 : (d == FaceDir::NegY ? -1 : 0);
    if (isCube(n.at(lx + dx, ly + dy, 0))) return d;
  }
  return std::nullopt;
}

// Opaque rectangles on the boundary face of `c` that faces `d`. Used to
// cull the faces of the tile on the other side.
void occluders(const Neighbourhood& n, int lx, int ly, int dz, FaceDir d, std::vector<Rect>& out) {
  out.clear();
  const Cell& c = n.at(lx, ly, dz);
  if (isCube(c)) {
    out.push_back(kFull);
    return;
  }
  if (c.phantom) return;
  const TileShape s = c.t.shape;
  if (hasFloorSlab(c)) {
    if (d == FaceDir::NegZ) out.push_back(kFull);
    else if (isLateral(d)) out.push_back(Rect{0, 0, 1, kH});
    return;
  }
  if (s == TileShape::Ramp) {
    if (d == FaceDir::NegZ) {
      out.push_back(kFull);
      return;
    }
    if (!isLateral(d)) return;
    // dz != 0 ramps are only asked about their top/bottom by neighbours
    // above/below; lateral queries always come from the same z.
    const auto high = rampHighSide(n, lx, ly);
    if (!high) {
      out.push_back(Rect{0, 0, 1, kLoneRampHeight});
    } else if (*high == d) {
      out.push_back(kFull);
    } else if (opposite(*high) == d) {
      out.push_back(Rect{0, 0, 1, kH});
    }
    // The two trapezoid sides occlude only partially: not counted.
  }
}

bool coveredBy(const std::vector<Rect>& occ, const Rect& r) {
  for (const Rect& o : occ)
    if (o.contains(r)) return true;
  return false;
}

// --- emission -----------------------------------------------------------------

struct Emitter {
  const Neighbourhood& n;
  const MeshOptions& options;
  wm::BlockPos pos;
  std::vector<Face>& faces;
  std::vector<Rect> scratch;

  Vec3 origin(int lx, int ly) const {
    return Vec3{static_cast<float>(pos.bx * kBlockSize + lx),
                static_cast<float>(pos.by * kBlockSize + ly), static_cast<float>(pos.bz)};
  }

  static Vec3 sub(Vec3 a, Vec3 b) { return Vec3{a.x - b.x, a.y - b.y, a.z - b.z}; }
  static Vec3 cross(Vec3 a, Vec3 b) {
    return Vec3{a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
  }
  static float dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
  static Vec3 normalize(Vec3 v) {
    const float l = std::sqrt(dot(v, v));
    return l > 0 ? Vec3{v.x / l, v.y / l, v.z / l} : v;
  }

  // Emits a planar quad (tile-local coordinates) with winding fixed so the
  // computed normal points along `want`.
  void quad(int lx, int ly, std::array<Vec3, 4> v, Vec3 want, FaceTag tag) {
    Vec3 nrm = normalize(cross(sub(v[1], v[0]), sub(v[2], v[0])));
    if (dot(nrm, want) < 0) {
      std::swap(v[1], v[3]);
      nrm = Vec3{-nrm.x, -nrm.y, -nrm.z};
    }
    const Vec3 o = origin(lx, ly);
    Face f;
    for (int i = 0; i < 4; ++i) f.v[i] = Vec3{o.x + v[i].x, o.y + v[i].y, o.z + v[i].z};
    f.normal = nrm;
    f.tag = tag;
    faces.push_back(f);
  }

  // Is the axis face at plane coordinate `at` (0 or 1 → boundary) covered by
  // the neighbour in direction d?
  bool culled(int lx, int ly, FaceDir d, float at, const Rect& r) {
    const bool boundary = (d == FaceDir::PosX || d == FaceDir::PosY || d == FaceDir::PosZ)
                              ? std::abs(at - 1.0f) < kEps
                              : std::abs(at) < kEps;
    if (!boundary) return false;
    int dx = 0, dy = 0, dz = 0;
    switch (d) {
      case FaceDir::PosX: dx = 1; break;
      case FaceDir::NegX: dx = -1; break;
      case FaceDir::PosY: dy = 1; break;
      case FaceDir::NegY: dy = -1; break;
      case FaceDir::PosZ: dz = 1; break;
      case FaceDir::NegZ: dz = -1; break;
      default: return false;
    }
    occluders(n, lx + dx, ly + dy, dz, opposite(d), scratch);
    return coveredBy(scratch, r);
  }

  // Axis-aligned face of a box. `at` is the plane coordinate along d's axis;
  // (a0,b0)-(a1,b1) the extent in the plane axes (see Rect).
  void axisFace(int lx, int ly, FaceDir d, float at, Rect r, FaceTag tag) {
    if (culled(lx, ly, d, at, r)) return;
    tag.dir = d;
    std::array<Vec3, 4> v;
    Vec3 want;
    switch (d) {
      case FaceDir::PosX:
      case FaceDir::NegX:
        v = {Vec3{at, r.a0, r.b0}, Vec3{at, r.a1, r.b0}, Vec3{at, r.a1, r.b1}, Vec3{at, r.a0, r.b1}};
        want = Vec3{d == FaceDir::PosX ? 1.f : -1.f, 0, 0};
        break;
      case FaceDir::PosY:
      case FaceDir::NegY:
        v = {Vec3{r.a0, at, r.b0}, Vec3{r.a1, at, r.b0}, Vec3{r.a1, at, r.b1}, Vec3{r.a0, at, r.b1}};
        want = Vec3{0, d == FaceDir::PosY ? 1.f : -1.f, 0};
        break;
      default:
        v = {Vec3{r.a0, r.b0, at}, Vec3{r.a1, r.b0, at}, Vec3{r.a1, r.b1, at}, Vec3{r.a0, r.b1, at}};
        want = Vec3{0, 0, d == FaceDir::PosZ ? 1.f : -1.f};
        break;
    }
    quad(lx, ly, v, want, tag);
  }

  // Box [x0,x1]×[y0,y1]×[z0,z1] in tile-local coordinates. `skip` is a
  // bitmask of FaceDir values whose faces are omitted (e.g. a box bottom
  // resting on the same tile's floor slab).
  void box(int lx, int ly, float x0, float y0, float z0, float x1, float y1, float z1,
           FaceTag tag, unsigned skip = 0) {
    auto want = [&](FaceDir d) { return (skip & (1u << static_cast<unsigned>(d))) == 0; };
    if (want(FaceDir::PosX)) axisFace(lx, ly, FaceDir::PosX, x1, Rect{y0, z0, y1, z1}, tag);
    if (want(FaceDir::NegX)) axisFace(lx, ly, FaceDir::NegX, x0, Rect{y0, z0, y1, z1}, tag);
    if (want(FaceDir::PosY)) axisFace(lx, ly, FaceDir::PosY, y1, Rect{x0, z0, x1, z1}, tag);
    if (want(FaceDir::NegY)) axisFace(lx, ly, FaceDir::NegY, y0, Rect{x0, z0, x1, z1}, tag);
    if (want(FaceDir::PosZ)) axisFace(lx, ly, FaceDir::PosZ, z1, Rect{x0, y0, x1, y1}, tag);
    if (want(FaceDir::NegZ)) axisFace(lx, ly, FaceDir::NegZ, z0, Rect{x0, y0, x1, y1}, tag);
  }

  void floorSlab(int lx, int ly, FaceTag tag) { box(lx, ly, 0, 0, 0, 1, 1, kH, tag); }

  // Six textured alpha-cutout faces, slightly inset so adjacent leaf cubes
  // never put two double-sided surfaces on the same plane. Branch cells stay
  // non-occluding: their transparent gaps must reveal neighbouring geometry.
  void leafCube(int lx, int ly, FaceTag tag) {
    tag.part = FacePart::Feature;
    box(lx, ly, kLeafInset, kLeafInset, kLeafInset,
        1 - kLeafInset, 1 - kLeafInset, 1 - kLeafInset, tag);
  }

  // A flat top-down decal just above the floor slab: DF's shrub and
  // sapling tiles are top-down art (a bush seen from above), so stood
  // upright as cross planes they read as X-shaped clutter from the usual
  // camera; laid on the slab they read as DF
  // draws them. Never culled (it is inside the tile, off every boundary).
  void decal(int lx, int ly, FaceTag tag, float lift = kDecalLift) {
    tag.dir = FaceDir::PosZ;
    tag.part = FacePart::Feature;
    const float z = kH + lift;
    std::array<Vec3, 4> v = {Vec3{0, 0, z}, Vec3{1, 0, z}, Vec3{1, 1, z}, Vec3{0, 1, z}};
    quad(lx, ly, v, Vec3{0, 0, 1}, tag);
  }

  void ramp(int lx, int ly, FaceTag tag) {
    const auto high = rampHighSide(n, lx, ly);
    if (!high) {
      box(lx, ly, 0, 0, 0, 1, 1, kLoneRampHeight, tag);  // slopeHigh stays PosZ
      return;
    }
    tag.slopeHigh = *high;  // every face of the wedge carries its direction
    // Height at each of the four corners: 1 on the high side, kH on the low.
    auto h = [&](float x, float y) {
      switch (*high) {
        case FaceDir::PosX: return x > 0.5f ? 1.0f : kH;
        case FaceDir::NegX: return x < 0.5f ? 1.0f : kH;
        case FaceDir::PosY: return y > 0.5f ? 1.0f : kH;
        default: return y < 0.5f ? 1.0f : kH;
      }
    };
    const float h00 = h(0, 0), h10 = h(1, 0), h11 = h(1, 1), h01 = h(0, 1);
    // Bottom.
    axisFace(lx, ly, FaceDir::NegZ, 0, kFull, tag);
    // Slope.
    {
      FaceTag t = tag;
      t.dir = FaceDir::Slope;
      std::array<Vec3, 4> v = {Vec3{0, 0, h00}, Vec3{1, 0, h10}, Vec3{1, 1, h11}, Vec3{0, 1, h01}};
      quad(lx, ly, v, Vec3{0, 0, 1}, t);
    }
    // Four sides: full square on the high side, strip on the low side,
    // trapezoids on the other two. Each is culled by its bounding rect.
    auto side = [&](FaceDir d, float at, std::array<Vec3, 4> v, float top) {
      if (culled(lx, ly, d, at, Rect{0, 0, 1, top})) return;
      FaceTag t = tag;
      t.dir = d;
      Vec3 want{d == FaceDir::PosX ? 1.f : (d == FaceDir::NegX ? -1.f : 0.f),
                d == FaceDir::PosY ? 1.f : (d == FaceDir::NegY ? -1.f : 0.f), 0.f};
      quad(lx, ly, v, want, t);
    };
    side(FaceDir::PosX, 1, {Vec3{1, 0, 0}, Vec3{1, 1, 0}, Vec3{1, 1, h11}, Vec3{1, 0, h10}},
         std::max(h10, h11));
    side(FaceDir::NegX, 0, {Vec3{0, 0, 0}, Vec3{0, 1, 0}, Vec3{0, 1, h01}, Vec3{0, 0, h00}},
         std::max(h00, h01));
    side(FaceDir::PosY, 1, {Vec3{0, 1, 0}, Vec3{1, 1, 0}, Vec3{1, 1, h11}, Vec3{0, 1, h01}},
         std::max(h01, h11));
    side(FaceDir::NegY, 0, {Vec3{0, 0, 0}, Vec3{1, 0, 0}, Vec3{1, 0, h10}, Vec3{0, 0, h00}},
         std::max(h00, h10));
  }

  void liquid(int lx, int ly, const Cell& c) {
    const float top = liquidTop(c);
    if (top <= 0.0f) return;
    const float base = liquidBase(c);
    FaceTag tag;
    tag.shape = c.t.shape;
    tag.materialKind = c.t.materialKind;
    tag.material = c.t.material;
    tag.liquid = c.t.liquidKind;
    tag.liquidLevel = c.t.liquidLevel;
    tag.flags = c.t.flags;
    tag.part = FacePart::Liquid;
    tag.lx = static_cast<uint8_t>(lx);
    tag.ly = static_cast<uint8_t>(ly);

    // Surface: on the tile boundary only at level 7, where liquid or drawn
    // rock above hides it. Undisclosed hidden rock (phantom) does not: it
    // draws nothing, so the surface must stay readable through the void.
    bool drawTop = true;
    if (std::abs(top - 1.0f) < kEps) {
      const Cell& above = n.at(lx, ly, 1);
      if (liquidTop(above) > 0.0f) drawTop = false;
      else if (!above.phantom && culled(lx, ly, FaceDir::PosZ, 1.0f, kFull)) drawTop = false;
    }
    if (drawTop) {
      FaceTag t = tag;
      t.dir = FaceDir::PosZ;
      std::array<Vec3, 4> v = {Vec3{0, 0, top}, Vec3{1, 0, top}, Vec3{1, 1, top}, Vec3{0, 1, top}};
      quad(lx, ly, v, Vec3{0, 0, 1}, t);
    }

    // Sides where the neighbour's liquid is lower (or absent).
    struct Side {
      FaceDir d;
      int dx, dy;
      float at;
    };
    const Side sides[] = {{FaceDir::PosX, 1, 0, 1}, {FaceDir::NegX, -1, 0, 0},
                          {FaceDir::PosY, 0, 1, 1}, {FaceDir::NegY, 0, -1, 0}};
    for (const Side& s : sides) {
      const Cell& nb = n.at(lx + s.dx, ly + s.dy, 0);
      const float nbTop = liquidTop(nb);
      if (nbTop >= top - kEps) continue;
      const float lo = std::max(base, nbTop);
      axisFace(lx, ly, s.d, s.at, Rect{0, lo, 1, top}, tag);
    }
  }

  // The undisclosed mass: a cube whose faces are Hidden caps, culled like
  // any cube's (nothing is emitted between two hidden tiles or against a
  // drawn wall), so the fort's unseen rock reads as an opaque body from
  // every angle rather than a window onto the levels below.
  void hidden(int lx, int ly) {
    // Fast path: most undisclosed tiles are buried among cubes (hidden
    // rock, drawn walls) and emit nothing; skip the rectangle bookkeeping.
    if (isCube(n.at(lx + 1, ly, 0)) && isCube(n.at(lx - 1, ly, 0)) && isCube(n.at(lx, ly + 1, 0)) &&
        isCube(n.at(lx, ly - 1, 0)) && isCube(n.at(lx, ly, 1)) && isCube(n.at(lx, ly, -1))) {
      return;
    }
    FaceTag tag;
    tag.shape = TileShape::Unknown;
    tag.flags = wm::kTileHidden;
    tag.part = FacePart::Hidden;
    tag.lx = static_cast<uint8_t>(lx);
    tag.ly = static_cast<uint8_t>(ly);
    box(lx, ly, 0, 0, 0, 1, 1, 1, tag);
  }

  void tile(int lx, int ly) {
    const Cell& c = n.at(lx, ly, 0);
    if (c.phantom) {
      hidden(lx, ly);
      return;
    }
    const TileState& t = c.t;
    FaceTag tag;
    tag.shape = t.shape;
    tag.materialKind = t.materialKind;
    tag.material = t.material;
    tag.flags = t.flags;
    tag.walls = wallMask(n, lx, ly);
    tag.lx = static_cast<uint8_t>(lx);
    tag.ly = static_cast<uint8_t>(ly);
    FaceTag feature = tag;
    feature.part = FacePart::Feature;
    constexpr unsigned kSkipBottom = 1u << static_cast<unsigned>(FaceDir::NegZ);

    switch (t.shape) {
      case TileShape::Empty:
      case TileShape::RampTop: break;
      case TileShape::Wall:
      case TileShape::Fortification:
      case TileShape::TreeTrunk:
      case TileShape::Unknown: box(lx, ly, 0, 0, 0, 1, 1, 1, tag); break;
      case TileShape::Floor: floorSlab(lx, ly, tag); break;
      case TileShape::Ramp: ramp(lx, ly, tag); break;
      case TileShape::StairUp:
      case TileShape::StairUpDown:
      case TileShape::StairDown:
        floorSlab(lx, ly, tag);
        // A full tile preserves DF's complete stair art. The old .3-tile
        // pillar sampled only the central 30%, hiding almost every step.
        // Keep the art above the slab but below the building decal band.
        decal(lx, ly, feature, .001f);
        break;
      case TileShape::Boulder:
        floorSlab(lx, ly, tag);
        box(lx, ly, 0.25f, 0.25f, kH, 0.75f, 0.75f, 0.6f, feature, kSkipBottom);
        break;
      case TileShape::Pebbles:
        floorSlab(lx, ly, tag);
        box(lx, ly, 0.35f, 0.35f, kH, 0.65f, 0.65f, 0.25f, feature, kSkipBottom);
        break;
      case TileShape::TreeBranch: leafCube(lx, ly, tag); break;
      case TileShape::Shrub:
      case TileShape::Sapling:
        floorSlab(lx, ly, tag);
        decal(lx, ly, tag);
        break;
    }
    liquid(lx, ly, c);
  }
};

// Merges the block's Hidden caps: same-direction unit squares on one plane
// become rectangles (tops / bottoms, 2-D greedy over the 16x16 grid) or
// runs along the face (sides, one z level per block). Deterministic: scan
// order (ly, lx); the merged face keeps the origin tile's lx, ly.
void mergeHidden(std::vector<Face>& faces, wm::BlockPos pos) {
  std::array<std::array<bool, kBlockSize * kBlockSize>, 6> mask{};
  std::vector<Face> kept;
  kept.reserve(faces.size());
  bool any = false;
  for (const Face& f : faces) {
    if (f.tag.part != FacePart::Hidden) {
      kept.push_back(f);
      continue;
    }
    mask[static_cast<size_t>(f.tag.dir)][static_cast<size_t>(f.tag.ly * kBlockSize + f.tag.lx)] = true;
    any = true;
  }
  if (!any) return;
  const float x0 = static_cast<float>(pos.bx * kBlockSize), y0 = static_cast<float>(pos.by * kBlockSize);
  const float z0 = static_cast<float>(pos.bz);
  auto emit = [&](FaceDir d, int lx, int ly, int w, int h) {
    Face f;
    f.tag.shape = TileShape::Unknown;
    f.tag.flags = wm::kTileHidden;
    f.tag.part = FacePart::Hidden;
    f.tag.dir = d;
    f.tag.lx = static_cast<uint8_t>(lx);
    f.tag.ly = static_cast<uint8_t>(ly);
    const float ax = x0 + static_cast<float>(lx), ay = y0 + static_cast<float>(ly);
    const float fw = static_cast<float>(w), fh = static_cast<float>(h);
    switch (d) {
      case FaceDir::PosZ:
      case FaceDir::NegZ: {
        const float z = d == FaceDir::PosZ ? z0 + 1 : z0;
        f.v = {Vec3{ax, ay, z}, Vec3{ax + fw, ay, z}, Vec3{ax + fw, ay + fh, z}, Vec3{ax, ay + fh, z}};
        f.normal = Vec3{0, 0, d == FaceDir::PosZ ? 1.f : -1.f};
        break;
      }
      case FaceDir::PosX:
      case FaceDir::NegX: {
        const float x = d == FaceDir::PosX ? ax + 1 : ax;
        f.v = {Vec3{x, ay, z0}, Vec3{x, ay + fw, z0}, Vec3{x, ay + fw, z0 + 1}, Vec3{x, ay, z0 + 1}};
        f.normal = Vec3{d == FaceDir::PosX ? 1.f : -1.f, 0, 0};
        break;
      }
      default: {
        const float y = d == FaceDir::PosY ? ay + 1 : ay;
        f.v = {Vec3{ax, y, z0}, Vec3{ax + fw, y, z0}, Vec3{ax + fw, y, z0 + 1}, Vec3{ax, y, z0 + 1}};
        f.normal = Vec3{0, d == FaceDir::PosY ? 1.f : -1.f, 0};
        break;
      }
    }
    // Winding: CCW seen from the normal side (the quad() rule).
    const Vec3 g = Emitter::cross(Emitter::sub(f.v[1], f.v[0]), Emitter::sub(f.v[2], f.v[0]));
    if (Emitter::dot(g, f.normal) < 0) std::swap(f.v[1], f.v[3]);
    kept.push_back(f);
  };
  for (int di = 0; di < 6; ++di) {
    auto& m = mask[static_cast<size_t>(di)];
    const FaceDir d = static_cast<FaceDir>(di);
    auto at = [&](int lx, int ly) -> bool& { return m[static_cast<size_t>(ly * kBlockSize + lx)]; };
    const bool vertical = d == FaceDir::PosZ || d == FaceDir::NegZ;
    const bool runAlongX = vertical || d == FaceDir::PosY || d == FaceDir::NegY;
    for (int ly = 0; ly < kBlockSize; ++ly) {
      for (int lx = 0; lx < kBlockSize; ++lx) {
        if (!at(lx, ly)) continue;
        int w = 1;
        if (runAlongX) {
          while (lx + w < kBlockSize && at(lx + w, ly)) ++w;
        } else {
          while (ly + w < kBlockSize && at(lx, ly + w)) ++w;
        }
        int h = 1;
        if (vertical) {
          bool grow = true;
          while (grow && ly + h < kBlockSize) {
            for (int i = 0; i < w; ++i) grow = grow && at(lx + i, ly + h);
            if (grow) ++h;
          }
        }
        if (runAlongX) {
          for (int j = 0; j < h; ++j)
            for (int i = 0; i < w; ++i) at(lx + i, ly + j) = false;
        } else {
          for (int i = 0; i < w; ++i) at(lx, ly + i) = false;
        }
        emit(d, lx, ly, w, h);
      }
    }
  }
  faces.swap(kept);
}

}  // namespace

bool producesGeometry(const TileState& t, bool revealHidden) {
  if ((t.flags & wm::kTileHidden) && !revealHidden && !(t.flags & wm::kTileDigDesignated))
    return false;
  if (t.liquidKind != wm::LiquidKind::None && t.liquidLevel > 0) return true;
  return t.shape != TileShape::Empty && t.shape != TileShape::RampTop;
}

const char* faceDirName(FaceDir d) {
  switch (d) {
    case FaceDir::PosX: return "+x";
    case FaceDir::NegX: return "-x";
    case FaceDir::PosY: return "+y";
    case FaceDir::NegY: return "-y";
    case FaceDir::PosZ: return "top";
    case FaceDir::NegZ: return "bottom";
    case FaceDir::Slope: return "slope";
    case FaceDir::Cross: return "cross";
  }
  return "?";
}

BlockMesh meshBlock(const BlockSource& src, wm::BlockPos pos, const MeshOptions& options) {
  BlockMesh out;
  out.pos = pos;
  const auto view = src.block(pos);
  if (!view || pos.bz > options.topZ) return out;
  out.version = view->version;
  const Neighbourhood n = gather(src, pos, options);
  Emitter e{n, options, pos, out.faces, {}};
  for (int ly = 0; ly < kBlockSize; ++ly)
    for (int lx = 0; lx < kBlockSize; ++lx) e.tile(lx, ly);
  mergeHidden(out.faces, pos);
  return out;
}

TerrainManifest buildTerrainManifest(const BlockSource& src, int32_t topZ, int32_t bottomZ,
                                     const MeshOptions& options) {
  TerrainManifest m;
  MeshOptions opts = options;
  opts.topZ = std::min(opts.topZ, topZ);
  const wm::TilePos map = src.mapSize();
  const int32_t bxCount = (map.x + kBlockSize - 1) / kBlockSize;
  const int32_t byCount = (map.y + kBlockSize - 1) / kBlockSize;
  m.topZ = std::min(opts.topZ, map.z - 1);
  m.bottomZ = std::max<int32_t>(bottomZ, 0);
  for (int32_t bz = m.bottomZ; bz <= m.topZ; ++bz)
    for (int32_t by = 0; by < byCount; ++by)
      for (int32_t bx = 0; bx < bxCount; ++bx) {
        ++m.blocksVisited;
        BlockMesh b = meshBlock(src, wm::BlockPos{bx, by, bz}, opts);
        if (!b.faces.empty()) m.blocks.push_back(std::move(b));
      }
  return m;
}

}  // namespace df3d::mesher
