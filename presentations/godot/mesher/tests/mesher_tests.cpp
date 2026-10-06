// Tier 0: shape and culling rules on hand-built maps (no fixtures, no
// model). Tier 1: the demo fixture through the world model into block mesh
// manifests (counts, mined-out tiles, z-slice).
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
#include "df3d_mesher/terrain_support.h"

#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <tuple>

#include "df3d_mesher/block_mesher.h"
#include "df3d_mesher/piece_policy.h"
#include "wm/world_model.h"

using namespace df3d::mesher;
using wm::LiquidKind;
using wm::MaterialKind;
using wm::TileShape;
using wm::TileState;

namespace {

// A block source over a sparse map; blocks exist once any tile in them is
// set (unset tiles in a known block are Empty).
class MapSource final : public BlockSource {
 public:
  MapSource(int32_t x, int32_t y, int32_t z) : size_{x, y, z} {}
  wm::TilePos mapSize() const override { return size_; }
  std::optional<wm::BlockView> block(wm::BlockPos b) const override {
    auto it = blocks_.find({b.bx, b.by, b.bz});
    if (it == blocks_.end()) return std::nullopt;
    return wm::BlockView{b, 1, it->second.data()};
  }
  void set(int32_t x, int32_t y, int32_t z, TileState t) {
    const wm::BlockPos b = wm::blockOf(wm::TilePos{x, y, z});
    auto& tiles = blocks_[{b.bx, b.by, b.bz}];
    tiles[wm::tileIndexInBlock(x % 16, y % 16)] = t;
  }
  void fill(wm::TilePos lo, wm::TilePos hi, TileState t) {
    for (int32_t z = lo.z; z <= hi.z; ++z)
      for (int32_t y = lo.y; y <= hi.y; ++y)
        for (int32_t x = lo.x; x <= hi.x; ++x) set(x, y, z, t);
  }

 private:
  wm::TilePos size_;
  std::map<std::tuple<int32_t, int32_t, int32_t>, std::array<TileState, 256>> blocks_;
};

TileState tile(TileShape s, MaterialKind k = MaterialKind::Stone, uint8_t flags = 0,
               wm::MaterialId mat = 0) {
  TileState t;
  t.shape = s;
  t.materialKind = k;
  t.material = mat;
  t.flags = flags;
  return t;
}

TileState liquid(TileState base, LiquidKind kind, uint8_t level) {
  base.liquidKind = kind;
  base.liquidLevel = level;
  return base;
}

const TileState kWall = tile(TileShape::Wall);
const TileState kFloor = tile(TileShape::Floor);
const TileState kEmpty = tile(TileShape::Empty, MaterialKind::None);

int countDir(const BlockMesh& m, FaceDir d) {
  return static_cast<int>(std::count_if(m.faces.begin(), m.faces.end(),
                                        [d](const Face& f) { return f.tag.dir == d; }));
}

int countPart(const BlockMesh& m, FacePart p) {
  return static_cast<int>(std::count_if(m.faces.begin(), m.faces.end(),
                                        [p](const Face& f) { return f.tag.part == p; }));
}

int countDirPart(const BlockMesh& m, FaceDir d, FacePart p) {
  return static_cast<int>(std::count_if(m.faces.begin(), m.faces.end(), [&](const Face& f) {
    return f.tag.dir == d && f.tag.part == p;
  }));
}

int countTile(const BlockMesh& m, int lx, int ly) {
  return static_cast<int>(std::count_if(m.faces.begin(), m.faces.end(), [&](const Face& f) {
    return f.tag.lx == lx && f.tag.ly == ly;
  }));
}

const Face* find(const BlockMesh& m, int lx, int ly, FaceDir d,
                 FacePart part = FacePart::Terrain) {
  for (const Face& f : m.faces)
    if (f.tag.lx == lx && f.tag.ly == ly && f.tag.dir == d && f.tag.part == part) return &f;
  return nullptr;
}

Vec3 sub(Vec3 a, Vec3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
Vec3 cross(Vec3 a, Vec3 b) {
  return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
float dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

// Winding is CCW seen from the normal side: the geometric normal from the
// vertex order must agree with the tagged normal, for both triangles.
void checkWinding(const BlockMesh& m) {
  for (const Face& f : m.faces) {
    const Vec3 n1 = cross(sub(f.v[1], f.v[0]), sub(f.v[2], f.v[0]));
    const Vec3 n2 = cross(sub(f.v[2], f.v[0]), sub(f.v[3], f.v[0]));
    CHECK(dot(n1, f.normal) > 0);
    CHECK(dot(n2, f.normal) > 0);
    CHECK(std::abs(dot(f.normal, f.normal) - 1.0f) < 1e-4f);
  }
}

float minZ(const Face& f) {
  return std::min({f.v[0].z, f.v[1].z, f.v[2].z, f.v[3].z});
}
float maxZ(const Face& f) {
  return std::max({f.v[0].z, f.v[1].z, f.v[2].z, f.v[3].z});
}

}  // namespace

TEST_CASE("a lone wall is a full cube with six tagged faces") {
  MapSource map(16, 16, 4);
  map.set(3, 4, 1, tile(TileShape::Wall, MaterialKind::Stone, wm::kTileSmooth, 7));
  const BlockMesh m = meshBlock(map, {0, 0, 1});
  CHECK(m.version == 1);
  REQUIRE(m.faces.size() == 6);
  checkWinding(m);
  for (FaceDir d : {FaceDir::PosX, FaceDir::NegX, FaceDir::PosY, FaceDir::NegY, FaceDir::PosZ,
                    FaceDir::NegZ}) {
    CHECK(countDir(m, d) == 1);
  }
  for (const Face& f : m.faces) {
    CHECK(f.tag.shape == TileShape::Wall);
    CHECK(f.tag.materialKind == MaterialKind::Stone);
    CHECK(f.tag.material == 7);
    CHECK((f.tag.flags & wm::kTileSmooth) != 0);
    CHECK(f.tag.part == FacePart::Terrain);
    CHECK(f.tag.lx == 3);
    CHECK(f.tag.ly == 4);
    for (const Vec3& v : f.v) {
      CHECK(v.x >= 3.0f);
      CHECK(v.x <= 4.0f);
      CHECK(v.y >= 4.0f);
      CHECK(v.y <= 5.0f);
      CHECK(v.z >= 1.0f);
      CHECK(v.z <= 2.0f);
    }
  }
  CHECK(find(m, 3, 4, FaceDir::PosZ)->v[0].z == 2.0f);
  CHECK(find(m, 3, 4, FaceDir::NegZ)->v[0].z == 1.0f);
}

TEST_CASE("faces between two solid tiles are culled, including across block and z boundaries") {
  MapSource map(32, 16, 4);
  map.set(15, 0, 1, kWall);
  map.set(16, 0, 1, kWall);  // next block in x
  map.set(15, 0, 2, kWall);  // above
  const BlockMesh a = meshBlock(map, {0, 0, 1});
  const BlockMesh b = meshBlock(map, {1, 0, 1});
  const BlockMesh c = meshBlock(map, {0, 0, 2});
  CHECK(a.faces.size() == 4);  // no +x (wall), no top (wall above)
  CHECK(find(a, 15, 0, FaceDir::PosX) == nullptr);
  CHECK(find(a, 15, 0, FaceDir::PosZ) == nullptr);
  CHECK(b.faces.size() == 5);
  CHECK(find(b, 0, 0, FaceDir::NegX) == nullptr);
  CHECK(c.faces.size() == 5);
  CHECK(find(c, 15, 0, FaceDir::NegZ) == nullptr);
}

TEST_CASE("Empty and RampTop produce nothing; unknown blocks yield version 0") {
  MapSource map(16, 16, 2);
  map.set(1, 1, 0, kEmpty);
  map.set(2, 2, 0, tile(TileShape::RampTop, MaterialKind::None));
  CHECK(meshBlock(map, {0, 0, 0}).faces.empty());
  CHECK(meshBlock(map, {0, 0, 0}).version == 1);
  CHECK(meshBlock(map, {0, 0, 1}).version == 0);
  CHECK(meshBlock(map, {0, 0, 1}).faces.empty());
  CHECK(producesGeometry(kEmpty, false) == false);
  CHECK(producesGeometry(kWall, false) == true);
  CHECK(producesGeometry(liquid(kEmpty, LiquidKind::Water, 3), false) == true);
}

TEST_CASE("hidden tiles emit only Hidden caps toward open space and occlude like rock; reveal draws them; designations show") {
  MapSource map(16, 16, 2);
  map.set(5, 5, 0, tile(TileShape::Wall, MaterialKind::Stone, wm::kTileHidden));
  map.set(6, 5, 0, kWall);  // visible wall beside hidden rock
  BlockMesh m = meshBlock(map, {0, 0, 0});
  // The hidden tile is an opaque black body: five caps (the sixth,
  // toward the wall, is culled), no material, no shape, flagged hidden.
  CHECK(countTile(m, 5, 5) == 5);
  CHECK(countPart(m, FacePart::Hidden) == 5);
  CHECK(find(m, 5, 5, FaceDir::PosX, FacePart::Hidden) == nullptr);
  const Face* cap = find(m, 5, 5, FaceDir::PosZ, FacePart::Hidden);
  REQUIRE(cap);
  CHECK(cap->tag.material == wm::kNoMaterial);
  CHECK(cap->tag.materialKind == MaterialKind::None);
  CHECK(cap->tag.shape == TileShape::Unknown);
  CHECK((cap->tag.flags & wm::kTileHidden) != 0);
  checkWinding(m);
  CHECK(countTile(m, 6, 5) == 5);  // face toward the hidden rock is culled
  CHECK(find(m, 6, 5, FaceDir::NegX) == nullptr);
  CHECK(producesGeometry(tile(TileShape::Wall, MaterialKind::Stone, wm::kTileHidden), false) ==
        false);

  MeshOptions reveal;
  reveal.revealHidden = true;
  m = meshBlock(map, {0, 0, 0}, reveal);
  CHECK(countTile(m, 5, 5) == 5);
  CHECK(countTile(m, 6, 5) == 5);
  CHECK(find(m, 5, 5, FaceDir::PosX) == nullptr);

  // A hidden tile that is designated for digging is meshed, flag carried.
  map.set(8, 8, 0, tile(TileShape::Wall, MaterialKind::Soil,
                        wm::kTileHidden | wm::kTileDigDesignated));
  m = meshBlock(map, {0, 0, 0});
  CHECK(countTile(m, 8, 8) == 6);
  CHECK((find(m, 8, 8, FaceDir::PosZ)->tag.flags & wm::kTileDigDesignated) != 0);
  CHECK(countPart(m, FacePart::Hidden) == 5);  // the designated tile is not a cap
}

TEST_CASE("Hidden caps merge: a buried hidden block is six quads, a slab above culls its top") {
  MapSource map(16, 16, 2);
  map.fill({0, 0, 0}, {15, 15, 0}, tile(TileShape::Wall, MaterialKind::Stone, wm::kTileHidden));
  BlockMesh m = meshBlock(map, {0, 0, 0});
  // Nothing observed around it: one rectangle per side, 16 x 16 tops and
  // bottoms, 16-long runs on the sides, all Hidden.
  CHECK(m.faces.size() == 6);
  CHECK(countPart(m, FacePart::Hidden) == 6);
  for (FaceDir d : {FaceDir::PosX, FaceDir::NegX, FaceDir::PosY, FaceDir::NegY, FaceDir::PosZ,
                    FaceDir::NegZ}) {
    CHECK(countDir(m, d) == 1);
  }
  const Face* top = find(m, 0, 0, FaceDir::PosZ, FacePart::Hidden);
  REQUIRE(top);
  float maxX = 0, maxY = 0;
  for (const Vec3& v : top->v) {
    maxX = std::max(maxX, v.x);
    maxY = std::max(maxY, v.y);
  }
  CHECK(maxX == doctest::Approx(16.0f));
  CHECK(maxY == doctest::Approx(16.0f));
  checkWinding(m);
  // A floor over half of it: those tops are culled by the slab, the rest
  // merge into one rectangle; the slab's own bottom is culled by the rock.
  map.fill({0, 0, 1}, {15, 7, 1}, kFloor);
  m = meshBlock(map, {0, 0, 0});
  CHECK(countDirPart(m, FaceDir::PosZ, FacePart::Hidden) == 1);
  const Face* half = find(m, 0, 8, FaceDir::PosZ, FacePart::Hidden);
  REQUIRE(half);
  const BlockMesh above = meshBlock(map, {0, 0, 1});
  CHECK(countDir(above, FaceDir::NegZ) == 0);
  // A hole in the middle: four runs of one around it plus the split tops.
  map.set(5, 5, 0, kEmpty);
  m = meshBlock(map, {0, 0, 0});
  CHECK(countDirPart(m, FaceDir::PosX, FacePart::Hidden) == 2);  // the outer run and the hole's west wall
  CHECK(find(m, 4, 5, FaceDir::PosX, FacePart::Hidden) != nullptr);
  CHECK(find(m, 6, 5, FaceDir::NegX, FacePart::Hidden) != nullptr);
  CHECK(find(m, 5, 4, FaceDir::PosY, FacePart::Hidden) != nullptr);
  CHECK(find(m, 5, 6, FaceDir::NegY, FacePart::Hidden) != nullptr);
  CHECK(countTile(m, 5, 5) == 0);
  CHECK(producesGeometry(tile(TileShape::Wall, MaterialKind::Soil,
                              wm::kTileHidden | wm::kTileDigDesignated),
                         false) == true);
}

TEST_CASE("a floor is a thin slab; its bottom and edges cull against rock and other floors") {
  MapSource map(16, 16, 3);
  map.set(4, 4, 1, kFloor);
  BlockMesh m = meshBlock(map, {0, 0, 1});
  CHECK(m.faces.size() == 6);  // floating slab: all six faces
  checkWinding(m);
  const Face* top = find(m, 4, 4, FaceDir::PosZ);
  REQUIRE(top);
  CHECK(top->v[0].z == doctest::Approx(1.0f + kFloorHeight));
  const Face* side = find(m, 4, 4, FaceDir::PosX);
  REQUIRE(side);
  CHECK(maxZ(*side) == doctest::Approx(1.0f + kFloorHeight));
  CHECK(minZ(*side) == doctest::Approx(1.0f));

  map.set(4, 4, 0, kWall);   // rock below
  map.set(5, 4, 1, kFloor);  // floor beside
  map.set(3, 4, 1, kWall);   // wall beside
  m = meshBlock(map, {0, 0, 1});
  CHECK(countTile(m, 4, 4) == 3);  // top, +y, -y
  CHECK(find(m, 4, 4, FaceDir::NegZ) == nullptr);
  CHECK(find(m, 4, 4, FaceDir::PosX) == nullptr);
  CHECK(find(m, 4, 4, FaceDir::NegX) == nullptr);
  // The wall's face toward the floor is drawn (the slab covers only a strip).
  CHECK(find(m, 3, 4, FaceDir::PosX) != nullptr);
}

TEST_CASE("z-slice: tiles at top_z show their tops, blocks above are not meshed") {
  MapSource map(16, 16, 4);
  map.fill({0, 0, 0}, {15, 15, 3}, kWall);
  MeshOptions cut;
  cut.topZ = 2;
  const BlockMesh m2 = meshBlock(map, {0, 0, 2}, cut);
  CHECK(countDir(m2, FaceDir::PosZ) == 256);
  CHECK(countDir(m2, FaceDir::NegZ) == 0);
  CHECK(meshBlock(map, {0, 0, 3}, cut).faces.empty());
  // Without the cut the interior layer shows no tops.
  CHECK(countDir(meshBlock(map, {0, 0, 2}), FaceDir::PosZ) == 0);

  const TerrainManifest man = buildTerrainManifest(map, 2, 0);
  CHECK(man.topZ == 2);
  CHECK(man.bottomZ == 0);
  CHECK(man.blocksVisited == 3);
  REQUIRE(man.blocks.size() == 3);
  CHECK(man.blocks.back().pos.bz == 2);
  // Only blocks with geometry are listed: a solid interior slab with the
  // map edge exposed still has its side faces; an all-empty block does not.
  MapSource sky(16, 16, 2);
  sky.fill({0, 0, 0}, {15, 15, 1}, kEmpty);
  CHECK(buildTerrainManifest(sky, 1, 0).blocks.empty());
  CHECK(buildTerrainManifest(sky, 1, 0).blocksVisited == 2);
}

TEST_CASE("map edges and unobserved blocks count as open") {
  MapSource map(20, 16, 1);  // partial block in x
  map.fill({0, 0, 0}, {19, 15, 0}, kWall);
  const BlockMesh a = meshBlock(map, {0, 0, 0});
  const BlockMesh b = meshBlock(map, {1, 0, 0});
  CHECK(find(a, 0, 0, FaceDir::NegX) != nullptr);  // map edge
  CHECK(find(a, 15, 0, FaceDir::PosX) == nullptr);  // continues into block 1
  CHECK(find(b, 3, 0, FaceDir::PosX) != nullptr);   // map edge at x = 19
  CHECK(countTile(b, 4, 0) == 0);                   // padding beyond the map: nothing
  MapSource sparse(32, 16, 1);
  sparse.set(15, 0, 0, kWall);  // block (1,0,0) never observed
  CHECK(find(meshBlock(sparse, {0, 0, 0}), 15, 0, FaceDir::PosX) != nullptr);
}

TEST_CASE("a ramp is a wedge rising toward the wall it leans on; lone ramps are half blocks") {
  MapSource map(16, 16, 2);
  map.set(5, 5, 0, tile(TileShape::Ramp));
  map.set(6, 5, 0, kWall);  // high side +x
  BlockMesh m = meshBlock(map, {0, 0, 0});
  checkWinding(m);
  const Face* slope = find(m, 5, 5, FaceDir::Slope);
  REQUIRE(slope);
  CHECK(slope->normal.x < 0);  // faces away from the wall, upward
  CHECK(slope->normal.z > 0);
  CHECK(slope->tag.slopeHigh == FaceDir::PosX);  // tagged with the high side
  for (const Face& f : m.faces)
    if (f.tag.lx == 5 && f.tag.ly == 5) CHECK(f.tag.slopeHigh == FaceDir::PosX);
  CHECK(find(m, 6, 5, FaceDir::PosZ)->tag.slopeHigh == FaceDir::PosZ);  // the wall itself: none
  for (const Vec3& v : slope->v) {
    if (v.x > 5.5f) CHECK(v.z == doctest::Approx(1.0f));
    else CHECK(v.z == doctest::Approx(kFloorHeight));
  }
  CHECK(find(m, 5, 5, FaceDir::PosX) == nullptr);  // against the wall
  const Face* low = find(m, 5, 5, FaceDir::NegX);
  REQUIRE(low);
  CHECK(maxZ(*low) == doctest::Approx(kFloorHeight));
  CHECK(find(m, 5, 5, FaceDir::PosY) != nullptr);  // trapezoid sides
  CHECK(find(m, 5, 5, FaceDir::NegY) != nullptr);
  CHECK(countTile(m, 5, 5) == 5);  // bottom, slope, low, two sides
  // The wall's face toward the ramp is culled by the wedge's high side.
  CHECK(find(m, 6, 5, FaceDir::NegX) == nullptr);

  MapSource lone(16, 16, 1);
  lone.set(2, 2, 0, tile(TileShape::Ramp));
  m = meshBlock(lone, {0, 0, 0});
  CHECK(countTile(m, 2, 2) == 6);
  CHECK(find(m, 2, 2, FaceDir::Slope) == nullptr);
  CHECK(find(m, 2, 2, FaceDir::PosZ)->v[0].z == doctest::Approx(kLoneRampHeight));
  CHECK(find(m, 2, 2, FaceDir::PosZ)->tag.slopeHigh == FaceDir::PosZ);  // lone: no high side

  // The high side follows the mesher's N, E, S, W preference; each
  // direction is tagged with the matching FaceDir.
  struct Case { int dx, dy; FaceDir want; };
  for (const Case c : {Case{0, -1, FaceDir::NegY}, Case{1, 0, FaceDir::PosX},
                       Case{0, 1, FaceDir::PosY}, Case{-1, 0, FaceDir::NegX}}) {
    MapSource one(16, 16, 1);
    one.set(8, 8, 0, tile(TileShape::Ramp));
    one.set(8 + c.dx, 8 + c.dy, 0, kWall);
    const BlockMesh r = meshBlock(one, {0, 0, 0});
    const Face* s = find(r, 8, 8, FaceDir::Slope);
    REQUIRE(s);
    CHECK(s->tag.slopeHigh == c.want);
  }
}

TEST_CASE("object ramp support agrees with terrain wedge vertices including block borders") {
  for(int side=0;side<5;++side) {
    MapSource map(32,32,1);
    map.set(15,15,0,tile(TileShape::Ramp));
    const int dx[]={0,1,0,-1},dy[]={-1,0,1,0};
    if(side<4)map.set(15+dx[side],15+dy[side],0,kWall);
    const auto read=[&](wm::TilePos p)->std::optional<TileState> {
      if(p.x<0 || p.y<0 || p.x>=32 || p.y>=32)return {};
      const auto b=map.block(wm::blockOf(p));
      return b?std::optional<TileState>(b->tiles[wm::tileIndexInBlock(p.x%16,p.y%16)]):std::nullopt;
    };
    const int code=rampSupportCode({15,15,0},read,false);
    CHECK(code==side+1);
    const auto mesh=meshBlock(map,{0,0,0});
    const auto* face=find(mesh,15,15,side<4?FaceDir::Slope:FaceDir::PosZ);
    REQUIRE(face);
    for(const auto& vertex:face->v) {
      const auto ground=rampSupport(code,vertex.x-15,vertex.y-15);
      CHECK(kFloorHeight+ground.lift==doctest::Approx(vertex.z));
    }
    CHECK(rampSupport(code,.5f,.5f).lift==doctest::Approx(side<4?.45f:.4f));
  }
}

TEST_CASE("ramp support invalidation ignores material and liquid; tracks shape and disclosure") {
  TerrainSupportDependencies deps;
  std::array<TileState,wm::kTilesPerBlock> tiles{};
  CHECK(deps.observe({0,0,0},tiles.data(),false).all());
  CHECK(deps.observe({0,0,0},tiles.data(),false).none());
  tiles[1]=tile(TileShape::Floor,MaterialKind::Stone);
  CHECK(deps.observe({0,0,0},tiles.data(),false).none());
  tiles[1]=tile(TileShape::Ramp);
  CHECK(deps.observe({0,0,0},tiles.data(),false).count()==1);
  tiles[1].materialKind=MaterialKind::Soil;
  tiles[1].liquidKind=LiquidKind::Water;tiles[1].liquidLevel=7;
  CHECK(deps.observe({0,0,0},tiles.data(),false).none());
  tiles[16]=tile(TileShape::Wall);
  CHECK(deps.observe({0,0,0},tiles.data(),false).count()==1);
  tiles[16]=tile(TileShape::TreeTrunk);
  CHECK(deps.observe({0,0,0},tiles.data(),false).none());
  tiles[1].flags=wm::kTileHidden;
  CHECK(deps.observe({0,0,0},tiles.data(),false).count()==1);
  CHECK(deps.observe({0,0,0},tiles.data(),true).count()==1);
  CHECK(deps.observe({0,0,0},nullptr,true).count()==2);
}

TEST_CASE("every face carries the tile's cube-neighbour mask (walls); hidden rock counts, other z does not") {
  MapSource map(32, 32, 3);
  // A 3-long wall run along x at y = 5 with a diagonal cube at (9, 4).
  for (int x = 5; x <= 7; ++x) map.set(x, 5, 1, kWall);
  map.set(8, 4, 1, kWall);
  map.set(6, 6, 1, kFloor);                                              // not a cube
  map.set(5, 4, 1, tile(TileShape::Wall, MaterialKind::Stone, wm::kTileHidden));  // phantom
  map.set(7, 5, 2, kWall);                                               // above: ignored
  map.set(6, 5, 0, kWall);                                               // below: ignored
  const BlockMesh m = meshBlock(map, {0, 0, 1});
  auto maskAt = [&](int lx, int ly) {
    for (const Face& f : m.faces)
      if (f.tag.lx == lx && f.tag.ly == ly) return f.tag.walls;
    return uint8_t{0};
  };
  // (5,5): E neighbour (6,5) is a wall; N (5,4) is hidden rock (phantom, counts).
  CHECK(maskAt(5, 5) == (kWallE | kWallN));
  // (6,5): W and E walls; NW (5,4) phantom; S (6,6) is a floor (open).
  CHECK(maskAt(6, 5) == (kWallW | kWallE | kWallNW));
  // (7,5): W wall; NE (8,4) wall; the cube above at z 2 is not counted.
  CHECK(maskAt(7, 5) == (kWallW | kWallNE));
  // (8,4): only the diagonal SW (7,5).
  CHECK(maskAt(8, 4) == kWallSW);
  // The floor at (6,6) carries its mask too (N wall, NW and NE walls).
  CHECK(maskAt(6, 6) == (kWallN | kWallNW | kWallNE));
  // Every face of a tile agrees.
  for (const Face& f : m.faces)
    if (f.tag.lx == 6 && f.tag.ly == 5) CHECK(f.tag.walls == (kWallW | kWallE | kWallNW));

  // Map edge and an unobserved block count as open: a wall at the corner
  // of the map with nothing around it has an empty mask.
  MapSource corner(16, 16, 1);
  corner.set(0, 0, 0, kWall);
  CHECK(meshBlock(corner, {0, 0, 0}).faces.front().tag.walls == 0);
  // Across a block boundary the neighbour is seen.
  MapSource across(32, 16, 1);
  across.set(15, 3, 0, kWall);
  across.set(16, 3, 0, kWall);
  const BlockMesh left = meshBlock(across, {0, 0, 0});
  for (const Face& f : left.faces) CHECK(f.tag.walls == kWallE);
  // With reveal on, hidden rock is an ordinary cube (still counted).
  MeshOptions reveal;
  reveal.revealHidden = true;
  const BlockMesh r = meshBlock(map, {0, 0, 1}, reveal);
  for (const Face& f : r.faces)
    if (f.tag.lx == 5 && f.tag.ly == 5) CHECK(f.tag.walls == (kWallE | kWallN));
}

TEST_CASE("stairs preserve full tile artwork above the slab on every level") {
  MapSource map(16, 16, 3);
  map.set(1, 1, 0, tile(TileShape::StairUp));
  map.set(1, 1, 1, tile(TileShape::StairUpDown));
  map.set(1, 1, 2, tile(TileShape::StairDown));
  for(int z=0;z<3;++z) {
    const BlockMesh mesh=meshBlock(map,{0,0,z});
    checkWinding(mesh);
    CHECK(countPart(mesh,FacePart::Terrain)==6);
    CHECK(countPart(mesh,FacePart::Feature)==1);
    const Face* art=find(mesh,1,1,FaceDir::PosZ,FacePart::Feature);
    REQUIRE(art);
    float minX=2,maxX=1,minY=2,maxY=1;
    for(const auto& v:art->v) {
      minX=std::min(minX,v.x);maxX=std::max(maxX,v.x);
      minY=std::min(minY,v.y);maxY=std::max(maxY,v.y);
      CHECK(v.z==doctest::Approx(z+kFloorHeight+.001f));
      CHECK(v.z<z+kFloorHeight+.002f); // below installation decals
    }
    CHECK(minX==1);CHECK(maxX==2);CHECK(minY==1);CHECK(maxY==2);
  }
}

TEST_CASE("boulders, pebbles, trunks, branches, shrubs, saplings, fortifications") {
  MapSource map(16, 16, 2);
  map.set(0, 0, 0, tile(TileShape::Boulder));
  map.set(2, 0, 0, tile(TileShape::Pebbles));
  map.set(4, 0, 0, tile(TileShape::TreeTrunk, MaterialKind::Wood));
  map.set(4, 0, 1, tile(TileShape::TreeBranch, MaterialKind::Wood));
  map.set(6, 0, 0, tile(TileShape::Shrub, MaterialKind::Plant));
  map.set(8, 0, 0, tile(TileShape::Sapling, MaterialKind::Wood));
  map.set(10, 0, 0, tile(TileShape::Fortification));
  map.set(12, 0, 0, tile(TileShape::Unknown, MaterialKind::Unknown));
  const BlockMesh m = meshBlock(map, {0, 0, 0});
  checkWinding(m);
  CHECK(countTile(m, 0, 0) == 6 + 5);   // slab + box without bottom
  CHECK(countTile(m, 2, 0) == 6 + 5);
  CHECK(countTile(m, 4, 0) == 6);
  CHECK(countTile(m, 6, 0) == 6 + 1);   // slab + one flat decal
  CHECK(countTile(m, 8, 0) == 6 + 1);
  for (int lx : {6, 8}) {
    const Face* d = find(m, lx, 0, FaceDir::PosZ, FacePart::Feature);
    REQUIRE(d);
    CHECK(d->normal.z > 0);
    for (const Vec3& v : d->v) CHECK(v.z == doctest::Approx(kFloorHeight + kDecalLift));
    CHECK(find(m, lx, 0, FaceDir::Cross, FacePart::Feature) == nullptr);
  }
  // The decal is inside the tile, so a wall above (z-slice cut away) or
  // beside it never culls it, and it never occludes anything.
  map.set(6, 0, 1, kWall);
  map.set(7, 0, 0, kWall);
  const BlockMesh again = meshBlock(map, {0, 0, 0});
  CHECK(find(again, 6, 0, FaceDir::PosZ, FacePart::Feature) != nullptr);
  CHECK(find(again, 7, 0, FaceDir::NegX) != nullptr);
  CHECK(countTile(m, 10, 0) == 6);
  CHECK(countTile(m, 12, 0) == 6);
  CHECK(find(m, 10, 0, FaceDir::PosZ)->tag.shape == TileShape::Fortification);
  const BlockMesh up = meshBlock(map, {0, 0, 1});
  CHECK(countTile(up, 4, 0) == 6);
  CHECK(countDir(up, FaceDir::Cross) == 0);
  checkWinding(up);
  CHECK(find(up, 4, 0, FaceDir::PosZ, FacePart::Feature) != nullptr);
}

TEST_CASE("liquids: translucent top at level/7 above the floor, sides toward lower neighbours") {
  MapSource map(16, 16, 2);
  map.fill({0, 0, 0}, {15, 15, 0}, kFloor);
  map.set(5, 5, 0, liquid(kFloor, LiquidKind::Water, 7));
  map.set(6, 5, 0, liquid(kFloor, LiquidKind::Water, 3));
  map.set(4, 5, 0, kWall);
  map.set(5, 6, 0, kEmpty);  // a pit beside the water
  const BlockMesh m = meshBlock(map, {0, 0, 0});
  checkWinding(m);
  auto liquidFaces = [&](int lx, int ly) {
    std::vector<const Face*> out;
    for (const Face& f : m.faces)
      if (f.tag.part == FacePart::Liquid && f.tag.lx == lx && f.tag.ly == ly) out.push_back(&f);
    return out;
  };
  const auto deep = liquidFaces(5, 5);
  // top; +x toward level 3 (partial); +y toward the pit; -x wall culled; -y floor (level 0).
  REQUIRE(deep.size() == 4);
  const Face* top = find(m, 5, 5, FaceDir::PosZ, FacePart::Liquid);
  REQUIRE(top);
  CHECK(top->v[0].z == doctest::Approx(1.0f));
  CHECK(top->tag.liquid == LiquidKind::Water);
  CHECK(top->tag.liquidLevel == 7);
  CHECK(top->tag.shape == TileShape::Floor);  // the bed shows through the tag
  const Face* toShallow = find(m, 5, 5, FaceDir::PosX, FacePart::Liquid);
  REQUIRE(toShallow);
  CHECK(maxZ(*toShallow) == doctest::Approx(1.0f));
  CHECK(minZ(*toShallow) == doctest::Approx(kFloorHeight + (1.0f - kFloorHeight) * 3.0f / 7.0f));
  const Face* toPit = find(m, 5, 5, FaceDir::PosY, FacePart::Liquid);
  REQUIRE(toPit);
  CHECK(minZ(*toPit) == doctest::Approx(kFloorHeight));
  CHECK(find(m, 5, 5, FaceDir::NegX, FacePart::Liquid) == nullptr);
  const Face* toDry = find(m, 5, 5, FaceDir::NegY, FacePart::Liquid);
  REQUIRE(toDry);
  CHECK(minZ(*toDry) == doctest::Approx(kFloorHeight));
  // The shallow tile: top at 3/7, no side back toward the deep tile.
  const Face* shallowTop = find(m, 6, 5, FaceDir::PosZ, FacePart::Liquid);
  REQUIRE(shallowTop);
  CHECK(shallowTop->v[0].z == doctest::Approx(kFloorHeight + (1.0f - kFloorHeight) * 3.0f / 7.0f));
  CHECK(find(m, 6, 5, FaceDir::NegX, FacePart::Liquid) == nullptr);
  // The floor under the water is still meshed (slab top under the surface).
  CHECK(find(m, 5, 5, FaceDir::PosZ, FacePart::Terrain) != nullptr);

  // Magma in open air (no floor) starts at the tile bottom; stacked full
  // columns hide their internal surface.
  MapSource pool(16, 16, 3);
  pool.set(0, 0, 0, liquid(kEmpty, LiquidKind::Magma, 7));
  pool.set(0, 0, 1, liquid(kEmpty, LiquidKind::Magma, 7));
  const BlockMesh p0 = meshBlock(pool, {0, 0, 0});
  CHECK(find(p0, 0, 0, FaceDir::PosZ, FacePart::Liquid) == nullptr);
  CHECK(minZ(*find(p0, 0, 0, FaceDir::PosX, FacePart::Liquid)) == doctest::Approx(0.0f));
  CHECK(find(p0, 0, 0, FaceDir::PosX, FacePart::Liquid)->tag.liquid == LiquidKind::Magma);
  const BlockMesh p1 = meshBlock(pool, {0, 0, 1});
  CHECK(find(p1, 0, 0, FaceDir::PosZ, FacePart::Liquid) != nullptr);

  // A full column under a drawn wall hides its surface; under undisclosed
  // hidden rock (which draws nothing) the surface stays visible.
  MapSource capped(16, 16, 2);
  capped.set(0, 0, 0, liquid(kEmpty, LiquidKind::Water, 7));
  capped.set(0, 0, 1, kWall);
  capped.set(1, 0, 0, liquid(kEmpty, LiquidKind::Water, 7));
  capped.set(1, 0, 1, tile(TileShape::Wall, MaterialKind::Stone, wm::kTileHidden));
  const BlockMesh c0 = meshBlock(capped, {0, 0, 0});
  CHECK(find(c0, 0, 0, FaceDir::PosZ, FacePart::Liquid) == nullptr);
  CHECK(find(c0, 1, 0, FaceDir::PosZ, FacePart::Liquid) != nullptr);
}

namespace {
bool sameFace(const Face& a, const Face& b) {
  const FaceTag& x = a.tag;
  const FaceTag& y = b.tag;
  return a.v == b.v && a.normal == b.normal && x.shape == y.shape &&
         x.materialKind == y.materialKind && x.material == y.material && x.liquid == y.liquid &&
         x.liquidLevel == y.liquidLevel && x.flags == y.flags && x.completedTrack == y.completedTrack && x.dir == y.dir &&
         x.part == y.part && x.slopeHigh == y.slopeHigh && x.walls == y.walls && x.lx == y.lx &&
         x.ly == y.ly;
}
}  // namespace

TEST_CASE("mesher is deterministic across independently built sources") {
  // Two sources with the same content populated in different orders and with
  // different neighbour-block insertion history; the manifests must agree
  // face for face, including every tag field, and must not be trivially empty.
  const auto populate = [](MapSource& map, bool reversed) {
    // One edit per tile so the insertion order carries no last-write-wins meaning.
    std::map<std::tuple<int32_t, int32_t, int32_t>, TileState> content;
    for (int32_t y = 0; y < 16; ++y)
      for (int32_t x = 0; x < 16; ++x) content[{x, y, 0}] = kFloor;
    content[{3, 3, 0}] = kWall;
    content[{4, 4, 0}] = liquid(kFloor, LiquidKind::Water, 2);
    content[{7, 7, 0}] = tile(TileShape::Ramp);
    content[{7, 6, 0}] = kWall;
    content[{16, 3, 0}] = kWall;   // neighbouring block in x
    content[{3, 16, 0}] = kFloor;  // neighbouring block in y
    std::vector<std::pair<std::tuple<int32_t, int32_t, int32_t>, TileState>> edits(content.begin(), content.end());
    if (reversed) std::reverse(edits.begin(), edits.end());
    for (const auto& [pos, t] : edits) map.set(std::get<0>(pos), std::get<1>(pos), std::get<2>(pos), t);
  };
  MapSource first(48, 48, 2);
  populate(first, false);
  const BlockMesh a = meshBlock(first, {0, 0, 0});
  MapSource second(48, 48, 2);
  // An unrelated block (bx=2,by=2: outside the meshed block's 27-block
  // neighbourhood) inserted before the content. An adjacent extra block would
  // be a content change: an observed empty block is not an unobserved one.
  second.set(40, 40, 1, kWall);
  populate(second, true);
  const BlockMesh b = meshBlock(second, {0, 0, 0});
  REQUIRE(a.faces.size() > 16 * 16);
  REQUIRE(a.faces.size() == b.faces.size());
  size_t mismatches = 0;
  for (size_t i = 0; i < a.faces.size(); ++i) mismatches += sameFace(a.faces[i], b.faces[i]) ? 0 : 1;
  CHECK(mismatches == 0);
  // The comparison itself can detect a difference: a changed source diverges.
  second.set(3, 3, 0, kFloor);
  const BlockMesh c = meshBlock(second, {0, 0, 0});
  bool diverged = c.faces.size() != a.faces.size();
  for (size_t i = 0; !diverged && i < c.faces.size(); ++i) diverged = !sameFace(a.faces[i], c.faces[i]);
  CHECK(diverged);
}

namespace {
// Records every block the mesher asks for so edge handling is observable.
class RecordingSource final : public BlockSource {
 public:
  explicit RecordingSource(const MapSource& inner) : inner_(inner) {}
  wm::TilePos mapSize() const override { return inner_.mapSize(); }
  std::optional<wm::BlockView> block(wm::BlockPos b) const override {
    requested.push_back(b);
    return inner_.block(b);
  }
  mutable std::vector<wm::BlockPos> requested;

 private:
  const MapSource& inner_;
};
}  // namespace

TEST_CASE("neighbour gather never requests blocks outside the map grid") {
  // 20x20 tiles: two blocks per axis, the second one partial. Meshing the
  // corner blocks must not ask the source for bx/by == -1 or == 2.
  MapSource map(20, 20, 2);
  map.fill({0, 0, 0}, {19, 19, 0}, kFloor);
  map.set(0, 0, 0, kWall);
  map.set(19, 19, 0, kWall);
  RecordingSource recorder(map);
  for (const wm::BlockPos pos : {wm::BlockPos{0, 0, 0}, wm::BlockPos{1, 1, 0}, wm::BlockPos{1, 0, 1}}) {
    recorder.requested.clear();
    const BlockMesh mesh = meshBlock(recorder, pos);
    CHECK_FALSE(recorder.requested.empty());
    int outside = 0;
    for (const wm::BlockPos& b : recorder.requested)
      if (b.bx < 0 || b.by < 0 || b.bz < 0 || b.bx >= 2 || b.by >= 2 || b.bz >= 2) ++outside;
    CHECK(outside == 0);
    if (pos.bz == 0) CHECK_FALSE(mesh.faces.empty());
  }
  // Map-edge neighbours count as open: the corner wall shows its outward sides.
  const BlockMesh corner = meshBlock(recorder, {0, 0, 0});
  CHECK(find(corner, 0, 0, FaceDir::NegX) != nullptr);
  CHECK(find(corner, 0, 0, FaceDir::NegY) != nullptr);
}

// --- tier 1: the demo fixture --------------------------------------------------

namespace {
const BlockMesh* blockAt(const TerrainManifest& m, wm::BlockPos p) {
  for (const BlockMesh& b : m.blocks)
    if (b.pos == p) return &b;
  return nullptr;
}
}  // namespace

TEST_CASE("demo fort: per-block counts, z-slice, mined-out tiles expose neighbours") {
  // Layout (tools/make_demo_fixture.cpp): 48x48x12; hidden stone z 0..2,
  // hidden soil z 3..4, turf floor at z 5, sky above; trees at
  // (6,40) (40,6) (42,42) with branches at z 6; pond 34..38 x 34..38 on
  // z 5; magma pool 40..43 x 40..43 at z 0; a stair shaft at (20,12);
  // digs at 9..14 x 20..22 on z 4 mined out over ticks 1001..1006.
  std::string err;
  auto replay = wm::FixtureReplay::open(DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix", err);
  REQUIRE_MESSAGE(replay, err);
  wm::WorldModel model;
  REQUIRE(replay->stepTo(model, replay->firstArrivalSeconds()) == 1);  // the Full only
  const WorldModelSource src(model);

  const TerrainManifest all = buildTerrainManifest(src, 11, 0);
  CHECK(all.blocksVisited == 108);
  // Sky levels 7..11 have nothing; z 6 has the three branch blocks.
  for (const BlockMesh& b : all.blocks) CHECK(b.pos.bz <= 6);
  int z6 = 0;
  for (const BlockMesh& b : all.blocks) z6 += b.pos.bz == 6;
  CHECK(z6 == 3);
  // A plain turf block: 256 floor tops, nothing else (edges between floors
  // and bottoms over hidden soil are culled).
  const BlockMesh* turf = blockAt(all, {1, 1, 5});
  REQUIRE(turf);
  CHECK(turf->faces.size() == 256);
  CHECK(countDir(*turf, FaceDir::PosZ) == 256);
  CHECK(turf->faces[0].tag.materialKind == MaterialKind::Grass);
  CHECK(model.materialName(turf->faces[0].tag.material) == "GRASS_TEMPERATE");
  // The pond block carries liquid faces tagged by level.
  const BlockMesh* pond = blockAt(all, {2, 2, 5});
  REQUIRE(pond);
  CHECK(countPart(*pond, FacePart::Liquid) > 0);
  const Face* centre = find(*pond, 36 - 32, 36 - 32, FaceDir::PosZ, FacePart::Liquid);
  REQUIRE(centre);
  CHECK(centre->tag.liquidLevel == 7);
  CHECK(centre->tag.liquid == LiquidKind::Water);
  // Magma at the bottom sits under hidden rock, which draws no tile art,
  // so its surface stays visible (16 tops; sides culled by rock); the pool
  // floors' undersides show too (the map's bottom edge is open), as do the
  // hidden rock's bottom caps around them (merged).
  const BlockMesh* buried = blockAt(all, {2, 2, 0});
  REQUIRE(buried);
  CHECK(countPart(*buried, FacePart::Liquid) == 16);
  CHECK(countDirPart(*buried, FaceDir::NegZ, FacePart::Terrain) == 16);
  CHECK(countDirPart(*buried, FaceDir::NegZ, FacePart::Hidden) > 0);
  CHECK(countDirPart(*buried, FaceDir::NegZ, FacePart::Hidden) < 240);
  // Sliced at z 0 the 4x4 pool shows its surface; sides are culled by rock.
  const TerrainManifest deep = buildTerrainManifest(src, 0, 0);
  const BlockMesh* magma = blockAt(deep, {2, 2, 0});
  REQUIRE(magma);
  CHECK(countPart(*magma, FacePart::Liquid) == 16);
  const Face* lava = find(*magma, 41 - 32, 41 - 32, FaceDir::PosZ, FacePart::Liquid);
  REQUIRE(lava);
  CHECK(lava->tag.liquid == LiquidKind::Magma);
  CHECK(lava->tag.liquidLevel == 7);

  // z-slice at the surface: nothing above z 5 is built and the surface
  // blocks are unchanged (their tops were already open to the sky).
  const TerrainManifest sliced = buildTerrainManifest(src, 5, 0);
  for (const BlockMesh& b : sliced.blocks) CHECK(b.pos.bz <= 5);
  CHECK(blockAt(sliced, {1, 1, 5})->faces.size() == 256);
  // Slicing at z 4 exposes the hidden soil as black caps, and the
  // designated tiles (player-visible) show their tops: 6 x 3 designations.
  const TerrainManifest z4 = buildTerrainManifest(src, 4, 0);
  const BlockMesh* digs = blockAt(z4, {0, 1, 4});
  REQUIRE(digs);
  int designated = 0;
  for (const Face& f : digs->faces) designated += (f.tag.flags & wm::kTileDigDesignated) != 0;
  CHECK(designated == 18);
  CHECK(countDirPart(*digs, FaceDir::PosZ, FacePart::Terrain) == 18);
  CHECK(countPart(*digs, FacePart::Terrain) == 18);
  CHECK(countPart(*digs, FacePart::Hidden) > 0);
  CHECK(countPart(*digs, FacePart::Hidden) + 18 == static_cast<int>(digs->faces.size()));

  // Mine out the first column (tick 1001): three walls become floors. Their
  // tops show; the next column's walls now face the new floors.
  REQUIRE(replay->stepTo(model, replay->firstArrivalSeconds() + 0.01) == 1);
  CHECK(model.blockVersion({0, 1, 4}) == 2);
  const TerrainManifest after = buildTerrainManifest(src, 4, 0);
  const BlockMesh* dug = blockAt(after, {0, 1, 4});
  REQUIRE(dug);
  CHECK(dug->version == 2);
  int floors = 0, exposed = 0, own = 0;
  for (const Face& f : dug->faces) {
    if (f.tag.part == FacePart::Hidden) continue;
    ++own;
    if (f.tag.shape == TileShape::Floor) floors += 1;
    if (f.tag.lx == 10 && f.tag.dir == FaceDir::NegX) exposed += 1;
  }
  CHECK(floors == 3);
  CHECK(exposed == 3);
  CHECK(own == 15 + 3 + 3);

  // The whole stream: the shaft at (14,20) opens on z 2..5, so the gallery
  // floor below it at z 1 and the shaft walls appear; unaffected blocks
  // keep their version-1 meshes.
  replay->stepAll(model);
  const TerrainManifest final = buildTerrainManifest(src, 5, 0);
  CHECK(blockAt(final, {1, 1, 5})->version == 1);
  const BlockMesh* shaftTop = blockAt(final, {0, 1, 5});
  REQUIRE(shaftTop);
  CHECK(countTile(*shaftTop, 14, 4) == 0);  // the opening itself is Empty
  // The shaft's walls at z 3 are hidden soil and the opening is Empty, so
  // that block has only the shaft's four black caps; the dug
  // floors at z 4 around the opening show their edges down into the shaft.
  const BlockMesh* shaft3 = blockAt(final, {0, 1, 3});
  REQUIRE(shaft3);
  CHECK(countPart(*shaft3, FacePart::Hidden) >= 4);
  CHECK(countPart(*shaft3, FacePart::Hidden) == static_cast<int>(shaft3->faces.size()));
  CHECK(find(*shaft3, 13, 4, FaceDir::PosX, FacePart::Hidden) != nullptr);
  CHECK(find(*shaft3, 15, 4, FaceDir::NegX, FacePart::Hidden) != nullptr);
  const BlockMesh* z4b = blockAt(final, {0, 1, 4});
  REQUIRE(z4b);
  CHECK(find(*z4b, 13, 4, FaceDir::PosX) != nullptr);  // floor edge facing the shaft
}

TEST_CASE("demo fort: the reveal option draws the hidden mass") {
  wm::WorldModel model;
  std::string err;
  REQUIRE(wm::loadFixtureFile(model, DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix", err));
  const WorldModelSource src(model);
  MeshOptions reveal;
  reveal.revealHidden = true;
  const TerrainManifest hidden = buildTerrainManifest(src, 1, 0);
  const TerrainManifest shown = buildTerrainManifest(src, 1, 0, reveal);
  size_t hiddenFaces = 0, shownFaces = 0;
  for (const auto& b : hidden.blocks) hiddenFaces += b.faces.size();
  for (const auto& b : shown.blocks) shownFaces += b.faces.size();
  CHECK(shownFaces > hiddenFaces);
  // Revealed and sliced at z 1, every tile shows its top; the vein's tops
  // are tagged Mineral (MAGNETITE) and the rest Stone.
  const BlockMesh* vein = blockAt(shown, {2, 0, 1});
  REQUIRE(vein);
  CHECK(countDir(*vein, FaceDir::PosZ) == 256);
  const Face* ore = find(*vein, 33 - 32, 11, FaceDir::PosZ);
  REQUIRE(ore);
  CHECK(ore->tag.materialKind == MaterialKind::Mineral);
  CHECK(model.materialName(ore->tag.material) == "MAGNETITE");
  CHECK(find(*vein, 5, 5, FaceDir::PosZ)->tag.materialKind == MaterialKind::Stone);
  // Not revealed, the same block is the undisclosed mass: one merged black
  // cap at the cut and its two map-edge sides, nothing else.
  const BlockMesh* mass = blockAt(hidden, {2, 0, 1});
  REQUIRE(mass);
  CHECK(countPart(*mass, FacePart::Hidden) == static_cast<int>(mass->faces.size()));
  CHECK(countDirPart(*mass, FaceDir::PosZ, FacePart::Hidden) == 1);
  CHECK(mass->faces.size() == 3);
}

TEST_CASE("furniture has cutout volume while map installations remain flat") {
  for (auto kind : {wm::BuildingKind::Chair, wm::BuildingKind::Bed, wm::BuildingKind::Table,
       wm::BuildingKind::Coffin, wm::BuildingKind::Box, wm::BuildingKind::Cabinet,
       wm::BuildingKind::Statue, wm::BuildingKind::Well, wm::BuildingKind::Weaponrack,
       wm::BuildingKind::Armorstand, wm::BuildingKind::Bookcase, wm::BuildingKind::Cage,
       wm::BuildingKind::Workshop, wm::BuildingKind::Furnace, wm::BuildingKind::TradeDepot})
    CHECK(isFurniturePiece(kind));
  for (auto kind : {wm::BuildingKind::Stockpile,
       wm::BuildingKind::Civzone, wm::BuildingKind::Door, wm::BuildingKind::Bridge,
       wm::BuildingKind::Unknown}) CHECK_FALSE(isFurniturePiece(kind));
}

TEST_CASE("both crossed foliage planes span the entire sprite horizontally") {
  for (float normal : {-1.f, 1.f}) {
    CHECK(crossPlaneU(normal, 0.5f, 0.f) == 0.f);
    CHECK(crossPlaneU(normal, 0.5f, 1.f) == 1.f);
  }
  CHECK(crossPlaneU(0.f, 0.f, 0.5f) == 0.f);
  CHECK(crossPlaneU(0.f, 1.f, 0.5f) == 1.f);
}

#include "df3d_mesher/cutout.h"
#include "df3d_mesher/item_stack.h"
#include "df3d_mesher/depth_layout.h"
TEST_CASE("cutout stacks are local to their semantic tile") {
 std::vector<DepthFootprint> p={{.5f,.5f,.5f,.5f,0,1},{1.5f,.5f,.5f,.5f,0,1},
                              {.5f,.5f,.35f,.35f,0,2},{.5f,.5f,.35f,.35f,0,2},
                              {2.5f,.5f,10.f,.8f,0,2},{.5f,.5f,.5f,.5f,1,1}};
 auto d=depthLayout(p);
 CHECK(d[2].bottom>d[0].bottom+d[0].thickness);
 CHECK(d[3].bottom>d[2].bottom+d[2].thickness);
 CHECK(d[1].bottom==doctest::Approx(.005f)); // adjacent furniture stays grounded
 CHECK(d[4].bottom==doctest::Approx(.005f)); // wide art never joins distant piles
 for(size_t i=0;i<p.size();++i)for(size_t j=0;j<i;++j)if(depthTile(p[i])==depthTile(p[j]))
  CHECK((d[i].bottom>d[j].bottom+d[j].thickness || d[j].bottom>d[i].bottom+d[i].thickness));
 auto raised=depthLayout(p,.74f,{.6f,0,0,0,0,0});
 CHECK(raised[0].bottom>.6f);
 for(int i:{1,4,5})CHECK(raised[i].bottom==doctest::Approx(.005f));
 // A whole row of edge-touching furniture cannot spread one pile's support.
 p.clear();for(int x=0;x<100;++x)p.push_back({x+.5f,.5f,.5f,.5f,0,1});
 auto row=depthLayout(p,.74f,{.7f});
 for(int i=1;i<100;++i)CHECK(row[i].bottom==doctest::Approx(.005f));
}
TEST_CASE("frame tile contents allocate furniture items and units together") {
 std::vector<DepthFootprint> p;
 for(int category:{1,2,3})for(int i=0;i<70;++i)p.push_back({.5f,.5f,10.f,10.f,127,category});
 p.push_back({1.5f,.5f,.5f,.5f,127,3});
 auto d=depthLayout(p);
 for(size_t i=0;i+1<d.size();++i) {
  CHECK(d[i].thickness>0);CHECK((127.f+kFloorHeight)+d[i].bottom+d[i].thickness<128.f);
  if(i)CHECK((127.f+kFloorHeight)+d[i].bottom>(127.f+kFloorHeight)+d[i-1].bottom+d[i-1].thickness);
 }
 CHECK(d.back().bottom==doctest::Approx(.005f));
 CHECK(d.back().thickness==doctest::Approx(.12f));
 // Moving the owning frame's last unit to a new tile only changes those piles.
 p[209].x=2.5f;auto moved=depthLayout(p);
 CHECK(moved[209].bottom==doctest::Approx(.005f));
 CHECK(moved.back().bottom==d.back().bottom);
 CHECK(moved[208].thickness>d[208].thickness);
}
TEST_CASE("crowded depth allocation preserves finite physical separation") {
 std::vector<DepthFootprint> p;
 for(int i=0;i<200;++i)p.push_back({.5f,.5f,.5f,.5f,0,2});
 const auto d=depthLayout(p);
 for(size_t i=0;i<d.size();++i) {
  CHECK(d[i].thickness>0);CHECK(d[i].bottom+d[i].thickness<kPieceCeiling);
  if(i)CHECK(200.f+d[i].bottom>200.f+d[i-1].bottom+d[i-1].thickness);
 }
 auto reordered=depthLayout(p);for(size_t i=0;i<d.size();++i)CHECK(d[i].bottom==reordered[i].bottom);
}
TEST_CASE("item pile caps each quantity stack and orders heavy to small") {
 wm::MapItem bar, otherBar, chair, bin, sword, axe, coin;
 bar.id=9; bar.kind=wm::ItemKind::Bar; bar.stack=1000000;
 otherBar=bar; otherBar.id=7; otherBar.material=123;
 chair.id=3; chair.kind=wm::ItemKind::Chair;
 bin.id=4; bin.kind=wm::ItemKind::Bin;
 sword.id=5; sword.kind=wm::ItemKind::Weapon; sword.subtypeRaw="SWORD";
 axe=sword; axe.id=6; axe.subtypeRaw="AXE";
 coin.id=10; coin.kind=wm::ItemKind::Coin;
 std::vector<const wm::MapItem*> input={&coin,&bar,&sword,&chair,&otherBar,&axe,&bin};
 auto layers=itemStack(input);
 REQUIRE(layers.size()==9);
 CHECK(layers[0].item==&chair); CHECK(layers[1].item==&bin);
 CHECK(layers[2].item==&otherBar); CHECK(layers[3].item==&otherBar);
 CHECK(layers[4].item==&bar); CHECK(layers[5].item==&bar);
 CHECK(layers[6].item==&axe); CHECK(layers[7].item==&sword); CHECK(layers[8].item==&coin);
 std::reverse(input.begin(),input.end()); auto reordered=itemStack(input);
 for(size_t i=0;i<layers.size();++i){CHECK(reordered[i].item==layers[i].item);CHECK(reordered[i].bottom==layers[i].bottom);}
 input={&bar}; layers=itemStack(input); REQUIRE(layers.size()==2); CHECK(layers[1].item==&bar);
 bar.stack=1; CHECK(itemStack(input).size()==1);
 input.clear(); CHECK(itemStack(input).empty());
}
TEST_CASE("identical separate items never share a quantity cap") {
 std::vector<wm::MapItem> items(3);
 std::vector<const wm::MapItem*> input;
 for(size_t i=0;i<items.size();++i){items[i].id=i;items[i].kind=wm::ItemKind::Bar;items[i].stack=100;input.push_back(&items[i]);}
 auto layers=itemStack(input); REQUIRE(layers.size()==6);
 for(size_t i=0;i<layers.size();++i){CHECK(layers[i].item==&items[i/2]);CHECK(layers[i].thickness==doctest::Approx(.12f));if(i)CHECK(layers[i].bottom>layers[i-1].bottom+layers[i-1].thickness);}
 for(auto& item:items)item.stack=1;
 layers=itemStack(input); REQUIRE(layers.size()==3);
 for(size_t i=0;i<layers.size();++i)CHECK(layers[i].item==&items[i]);
}
TEST_CASE("large mixed piles compress below next tile including furniture support") {
 std::vector<wm::MapItem> items(100);
 std::vector<const wm::MapItem*> input;
 for(size_t i=0;i<items.size();++i){items[i].id=i;items[i].kind=wm::ItemKind::Weapon;items[i].subtype=uint16_t(i);items[i].stack=999999;input.push_back(&items[i]);}
 auto layers=itemStack(input,.134f); REQUIRE(layers.size()==200);
 CHECK(layers[0].bottom>.134f);
 for(size_t i=0;i<layers.size();++i){CHECK(layers[i].thickness>0);CHECK(layers[i].thickness<.12f);CHECK(layers[i].bottom+layers[i].thickness<=1.f);if(i)CHECK(layers[i].bottom>layers[i-1].bottom+layers[i-1].thickness);}
}
TEST_CASE("cutout topology preserves holes disconnected pixels and image north") {
 const std::vector<uint8_t> ring={255,255,255,255,0,255,255,255,255};
 auto m=cutoutMesh(ring,3,3);
 CHECK(m.size()==(4*2+16)*6); // 4 top runs, bottom runs and 16 exposed edges
 for(size_t i=0;i<m.size();++i){auto v=m[i];CHECK(v.x>=-.5f);CHECK(v.x<=.5f);CHECK(v.z>=-.5f);CHECK(v.z<=.5f);CHECK(v.y>=0);CHECK(v.y<=kCutoutThickness);CHECK(v.shade==1);if(i<4*2*6){CHECK(v.u==doctest::Approx(v.x+.5f));CHECK(v.v==doctest::Approx(v.z+.5f));}else{int px=int(v.u*3),py=int(v.v*3);CHECK(ring[py*3+px]==255);CHECK(v.u*3==doctest::Approx(px+.5f));CHECK(v.v*3==doctest::Approx(py+.5f));}}
 auto isolated=cutoutMesh(std::vector<uint8_t>{255,0,255},3,1);
 CHECK(isolated.size()==12*6);
 CHECK(cutoutMesh(std::vector<uint8_t>{0,127},2,1).empty());
 CHECK(cutoutMesh(std::vector<uint8_t>{255},2,1).empty());
 CHECK(kCutoutThickness==doctest::Approx(.12f));
}
TEST_CASE("cutout sides sample their opaque pixel centers without added outline") {
 auto m=cutoutMesh(std::vector<uint8_t>{0,255,0},3,1);
 REQUIRE(m.size()==6*6);
 for(size_t i=12;i<m.size();++i){CHECK(m[i].u==doctest::Approx(.5f));CHECK(m[i].v==doctest::Approx(.5f));CHECK(m[i].shade==1.f);}
}

TEST_CASE("indexed cutouts preserve every triangle attribute across alpha masks and edge covers") {
 // Exhaust all 3x3 masks, including empty images, holes and disconnected
 // islands. Expansion must recover exactly the original draw stream.
 const std::vector<CutoutEdgeCover> covers={{1,0,.03f,.09f},{0,1,0,.06f}};
 for(unsigned mask=0;mask<512;++mask) {
  std::vector<uint8_t> alpha(9);
  for(unsigned pixel=0;pixel<9;++pixel) alpha[pixel]=(mask&(1u<<pixel))?255:0;
  const auto original=cutoutMesh(alpha,3,3,covers);
  const auto indexed=indexCutoutMesh(original);
  REQUIRE(indexed.indices.size()==original.size());
  CHECK(indexed.vertices.size()<=original.size());
  for(size_t i=0;i<original.size();++i) {
   REQUIRE(indexed.indices[i]>=0);
   REQUIRE(size_t(indexed.indices[i])<indexed.vertices.size());
   const auto& a=original[i]; const auto& b=indexed.vertices[indexed.indices[i]];
   CHECK(a.x==b.x);CHECK(a.y==b.y);CHECK(a.z==b.z);
   CHECK(a.u==b.u);CHECK(a.v==b.v);CHECK(a.shade==b.shade);
  }
 }
}

TEST_CASE("cutout indexing retains UV and shade seams and reduces solid sprite vertices") {
 const CutoutVertex base={0,0,0,0,0,1};
 auto uv=base;uv.u=.5f;
 auto shade=base;shade.shade=.5f;
 const auto seams=indexCutoutMesh(std::vector<CutoutVertex>{base,uv,shade,base});
 REQUIRE(seams.vertices.size()==3);
 CHECK(seams.indices==std::vector<int32_t>{0,1,2,0});
 const auto original=cutoutMesh(std::vector<uint8_t>(32*32,255),32,32);
 const auto indexed=indexCutoutMesh(original);
 CHECK(indexed.indices.size()==1152); // unchanged 384 triangles
 CHECK(indexed.vertices.size()<original.size()*2/3);
 CHECK(indexed.vertices.size()*sizeof(CutoutVertex)+indexed.indices.size()*sizeof(int32_t)
       <original.size()*sizeof(CutoutVertex));
}

TEST_CASE("leaf cubes have six complete faces and cannot occlude their neighbours") {
  MapSource map(32, 16, 3);
  const auto leaf = tile(TileShape::TreeBranch, MaterialKind::Wood);
  map.set(15, 5, 1, leaf);
  map.set(16, 5, 1, leaf); // across the block boundary
  map.set(15, 5, 2, leaf); // vertical adjacency
  map.set(14, 5, 1, kWall);
  map.set(15, 5, 0, kWall);
  const BlockMesh m = meshBlock(map, {0, 0, 1});
  checkWinding(m);
  CHECK(countTile(m, 15, 5) == 6);
  CHECK(find(m, 14, 5, FaceDir::PosX) != nullptr);
  CHECK(find(meshBlock(map, {0, 0, 0}), 15, 5, FaceDir::PosZ) != nullptr);
  CHECK(countTile(meshBlock(map, {1, 0, 1}), 0, 5) == 6);
  for (FaceDir d : {FaceDir::PosX, FaceDir::NegX, FaceDir::PosY,
                    FaceDir::NegY, FaceDir::PosZ, FaceDir::NegZ}) {
    const Face* f = find(m, 15, 5, d, FacePart::Feature);
    REQUIRE(f);
    std::vector<std::pair<int, int>> corners;
    for (const auto& v : f->v) {
      const float x = v.x - 15, y = v.y - 5, z = v.z - 1;
      for (float c : {x, y, z}) {
        CHECK(c >= kLeafInset - 0.00001f);
        CHECK(c <= 1 - kLeafInset + 0.00001f);
      }
      const float u = leafTextureCoordinate(d == FaceDir::PosX || d == FaceDir::NegX ? y : x);
      const float w = leafTextureCoordinate(d == FaceDir::PosZ || d == FaceDir::NegZ ? y : z);
      CHECK((std::abs(u) < .00001f || std::abs(u - 1) < .00001f));
      CHECK((std::abs(w) < .00001f || std::abs(w - 1) < .00001f));
      corners.emplace_back(int(std::round(u)), int(std::round(w)));
    }
    std::sort(corners.begin(), corners.end());
    CHECK(std::unique(corners.begin(), corners.end()) == corners.end());
  }
}

TEST_CASE("building art stays fixed under moving and crowded physical stacks") {
 std::vector<DepthFootprint> p={{.5f,.5f,.5f,.5f,143,1},{.5f,.5f,.5f,.5f,143,4}};
 const auto alone=drawDepthLayout(p,{-1,0});
 for(int count:{1,2,220}) {
  auto crowded=p;
  for(int i=0;i<count;++i)crowded.push_back({.5f,.5f,.5f,.5f,143,i==count-1?3:2});
  const auto d=drawDepthLayout(crowded,{-1,0});
  CHECK(d[0].bottom==alone[0].bottom);CHECK(d[0].thickness==alone[0].thickness);
  CHECK(d[1].bottom==d[0].bottom);CHECK(d[1].thickness==d[0].thickness);
  for(size_t i=2;i<d.size();++i) {
   CHECK(d[i].thickness>0);CHECK(d[i].bottom+d[i].thickness<kPieceCeiling);
   if(i>2)CHECK(143.f+d[i].bottom>143.f+d[i-1].bottom+d[i-1].thickness);
   else CHECK(d[i].bottom>d[0].bottom+d[0].thickness+kBuildingSpillBias);
  }
 }
}

TEST_CASE("building spill priority is translation independent bounded and below moving pieces") {
 const auto base=buildingDepth(80,80);
 const auto spill=buildingDepth(80,79), taller=buildingDepth(80,78);
 CHECK(spill.bottom==base.bottom);CHECK(taller.bottom==base.bottom);
 CHECK(taller.thickness>spill.thickness);CHECK(spill.thickness>base.thickness);
 CHECK(buildingDepth(180,179).thickness==spill.thickness);
 CHECK(buildingDepth(1000000,0).thickness<=base.thickness+kBuildingSpillBias);
 CHECK(base.bottom+base.thickness+kBuildingSpillBias<kPieceCeiling);
 const auto decals=buildingDepth(80,79,false);
 CHECK(decals.thickness==0);CHECK(decals.bottom<base.bottom);
 CHECK(installationArtBottom(wm::BuildingKind::Stockpile)<installationArtBottom(wm::BuildingKind::Civzone));
 CHECK(installationArtBottom(wm::BuildingKind::Civzone)<installationArtBottom(wm::BuildingKind::Door));
 CHECK(installationArtBottom(wm::BuildingKind::Door)<base.bottom);
}

TEST_CASE("connected image fragments remove coincident seam walls and retain exposed steps") {
 const std::vector<uint8_t> solid={255};
 const std::vector<CutoutEdgeCover> joined={{1,0,0,kCutoutThickness}};
 const auto closed=cutoutMesh(solid,1,1,joined);
 CHECK(closed.size()==5*6); // top, bottom and three external sides
 for(size_t i=12;i<closed.size();i+=6){
  bool east=true;for(size_t j=i;j<i+6;++j)east=east&&closed[j].x==.5f;
  CHECK_FALSE(east);
 }
 const std::vector<CutoutEdgeCover> partial={{1,0,.03f,.09f}};
 const auto stepped=cutoutMesh(solid,1,1,partial);
 CHECK(stepped.size()==7*6); // uncovered lower + upper span on shared boundary
 int eastFaces=0;
 for(size_t i=12;i<stepped.size();i+=6){
  bool east=true;float lo=1,hi=-1;
  for(size_t j=i;j<i+6;++j){east=east&&stepped[j].x==.5f;lo=std::min(lo,stepped[j].y);hi=std::max(hi,stepped[j].y);}
  if(!east)continue;
  ++eastFaces;
  CHECK((hi<=.03f || lo>=.09f));
 }
 // Exactly the two uncovered spans (below and above the partial cover) remain on the east side.
 CHECK(eastFaces==2);
 const std::vector<CutoutEdgeCover> unionCover={{1,0,0,.06f},{1,0,.06f,.12f}};
 CHECK(cutoutMesh(solid,1,1,unionCover).size()==closed.size());
 // A transparent neighbouring edge does not create a cover entry.
 CHECK(cutoutMesh(solid,1,1).size()==6*6);
}

TEST_CASE("joined thin foreground caps do not leave floating point seam slivers") {
 const std::vector<uint8_t> solid={255};
 std::vector<CutoutEdgeCover> covers;
 // Native z143 workshop caps normalize a 0.015-high interval around 0.267.
 // Cancellation on the allocated bottom/top must not manufacture seam faces.
 const float bottom=.267f, thickness=.015f;
 const float top=((bottom+thickness)-bottom)*(kCutoutThickness/thickness);
 for(int side=0;side<4;++side)covers.push_back({side,0,0,top});
 CHECK(cutoutMesh(solid,1,1,covers).size()==12);
 for(auto& c:covers){c.bottom=0.0000001f;c.top=kCutoutThickness-0.0000001f;}
 CHECK(cutoutMesh(solid,1,1,covers).size()==12);
 // Real exposed geometry remains: this is not broad boundary suppression.
 covers={{1,0,.001f,kCutoutThickness-.001f}};
 CHECK(cutoutMesh(solid,1,1,covers).size()==42);
}

#include "df3d_mesher/minimap.h"
TEST_CASE("minimap hides unknown and hidden terrain before inspecting materials") {
 CHECK(minimapColor(std::nullopt)==-1);
 TileState tile; tile.shape=TileShape::Wall; tile.materialKind=MaterialKind::Stone;
 CHECK(minimapColor(tile)==0x404040);
 tile.flags=wm::kTileHidden; tile.liquidLevel=7; tile.liquidKind=LiquidKind::Magma;
 CHECK(minimapColor(tile)==-1);
 tile.flags=0; tile.shape=TileShape::Unknown;
 CHECK(minimapColor(tile)==-1);
 tile.shape=TileShape::Empty;
 CHECK(minimapColor(tile)==0x801800);
 tile.liquidLevel=0;
 CHECK(minimapColor(tile)==0x64e0ff);
 tile.shape=TileShape::Floor; tile.materialKind=MaterialKind::Grass;
 CHECK(minimapColor(tile)==0x80c000);
}
TEST_CASE("minimap representative sampling is bounded on nonsquare maps") {
 CHECK(minimapSample(0,256,512)==1);
 CHECK(minimapSample(255,256,512)==511);
 CHECK(minimapSample(63,64,128)==127);
 for(int size : {1,3,17,128,256,512,1024}) {
  const int pixels=std::min(size,256);
  int previous=-1;
  for(int p=0;p<pixels;++p) {
   const int sample=minimapSample(p,pixels,size);
   CHECK(sample>=0); CHECK(sample<size); CHECK(sample>previous); previous=sample;
  }
 }
}

namespace {
// Independent ordered-map implementation of the fixed-building policy.
std::vector<DepthInterval> orderedDepthReference(const std::vector<DepthFootprint>& p,
                                                const std::vector<int>& parent,
                                                const std::vector<float>& supports) {
 struct Pile {int count=0,next=0;float support=0;};
 std::map<DepthTile,Pile> piles;
 for(int i=0;i<int(p.size());++i) {
  auto& pile=piles[depthTile(p[i])];
  if(p[i].category==2 || p[i].category==3)++pile.count;
  if(i<int(supports.size()))pile.support=std::max(pile.support,supports[i]);
  if(p[i].category==1)pile.support=std::max(pile.support,kBuildingBottom+kBuildingThickness+kBuildingSpillBias);
  if(p[i].category==0)pile.support=std::max(pile.support,kInstallationBottom);
 }
 std::vector<DepthInterval> result(p.size());
 for(int i=0;i<int(p.size());++i) {
  auto& pile=piles[depthTile(p[i])];
  if(p[i].category==2 || p[i].category==3) {
   const float low=std::clamp(pile.support,0.0f,kPieceCeiling-.01f)+.005f;
   const float step=std::min(.13f,(kPieceCeiling-low)/pile.count);
   result[i]={low+pile.next++*step,step*(.12f/.13f)};
  } else if(p[i].category==4) {
   const int owner=i<int(parent.size())?parent[i]:-1;
   result[i]=owner>=0 && owner<i && depthTile(p[owner])==depthTile(p[i])?result[owner]:buildingDepth(0,0);
  } else result[i]=buildingDepth(0,0,p[i].category==1);
 }
 return result;
}
}

TEST_CASE("depth hash lookups exactly preserve ordered sparse and crowded fortress allocation") {
 for(const bool crowded : {false,true}) {
  std::vector<DepthFootprint> pieces;
  std::vector<int> parents;
  std::vector<float> supports;
  for(int i=0;i<700;++i) {
   pieces.push_back({float(i%70)-3.5f,float(i/70)+.5f,.5f,.5f,127+i%3,1});
   parents.push_back(-1);supports.push_back(.002f+.02f*(i%4)/4);
  }
  for(int category : {2,3})for(int i=0;i<(category==2?(crowded?1600:200):180);++i) {
   auto piece=pieces[(i*37)%700];piece.category=category;
   pieces.push_back(piece);parents.push_back(-1);supports.push_back(0);
  }
  if(crowded)for(int i=0;i<220;++i) {
   auto piece=pieces[0];piece.category=2;
   pieces.push_back(piece);parents.push_back(-1);supports.push_back(i==219?.68f:0);
  }
  for(int i=0;i<700;i+=10) {
   auto piece=pieces[i];piece.category=4;
   pieces.push_back(piece);parents.push_back(i);supports.push_back(0);
  }
  const auto expected=orderedDepthReference(pieces,parents,supports);
  const auto actual=drawDepthLayout(pieces,parents,supports);
  REQUIRE(expected.size()==actual.size());
  for(size_t i=0;i<actual.size();++i) {
   CHECK(actual[i].bottom==expected[i].bottom);
   CHECK(actual[i].thickness==expected[i].thickness);
  }
  // Opt-in timing avoids adding benchmark noise/work to the regular suite.
  // DF3D_DEPTH_BENCH=1 mesher_tests --test-case="depth hash lookups*"
  if(std::getenv("DF3D_DEPTH_BENCH")) {
   std::vector<double> orderedTimes,hashTimes;
   double checksum=0;
   for(int sample=0;sample<81;++sample) {
    for(int phase=0;phase<2;++phase) {
     const bool ordered=(sample+phase)%2==0;
     const auto start=std::chrono::steady_clock::now();
     const auto output=ordered?orderedDepthReference(pieces,parents,supports):drawDepthLayout(pieces,parents,supports);
     const double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
     (ordered?orderedTimes:hashTimes).push_back(ms);
     checksum+=output[(sample*13)%output.size()].bottom;
    }
   }
   std::sort(orderedTimes.begin(),orderedTimes.end());std::sort(hashTimes.begin(),hashTimes.end());
   std::printf("depth_bench pieces=%zu crowded=%d ordered_p50_ms=%.6f hash_p50_ms=%.6f speedup=%.3f checksum=%.6f\n",
    pieces.size(),int(crowded),orderedTimes[40],hashTimes[40],orderedTimes[40]/hashTimes[40],checksum);
  }
 }
}

#include "df3d_mesher/depth_scene.h"
namespace {
wm::WorldModel depthSceneModel(bool hidden = false) {
 wm::WorldModel model;
 wm::SnapshotData snap;
 snap.tick=100; snap.mapSize={16,16,2}; snap.terrainScope=wm::TerrainScope::Full;
 snap.tileStorage.resize(512);
 for(auto& t:snap.tileStorage)t.shape=wm::TileShape::Floor;
 if(hidden)snap.tileStorage[wm::tileIndexInBlock(2,2)].flags=wm::kTileHidden;
 snap.blocks={{ {0,0,0},snap.tileStorage.data() }, { {0,0,1},snap.tileStorage.data()+256 }};
 snap.buildingScope=wm::ChangeScope::Full;
 for(auto [id,kind]:std::vector<std::pair<int,wm::BuildingKind>>{
     {10,wm::BuildingKind::Stockpile},{11,wm::BuildingKind::Civzone},{20,wm::BuildingKind::Workshop}}) {
  wm::BuildingObservation b; b.id=id;b.kind=kind;b.x1=b.x2=b.y1=b.y2=2;b.z=0;
  snap.buildings.push_back(b);
 }
 snap.itemScope=wm::ChangeScope::Full;
 wm::ItemObservation wood;wood.id=20;wood.kind=wm::ItemKind::Wood;wood.pos={2,2,0};
 wm::ItemObservation chair;chair.id=30;chair.kind=wm::ItemKind::Chair;chair.pos={2,2,0};chair.stack=200;
 snap.items={wood,chair};
 snap.units={{8,{2,2,0},wm::JobKind::Idle,"DWARF"},{2,{2,2,0},wm::JobKind::Idle,"DWARF"},
             {11,{2,2,1},wm::JobKind::Idle,"DWARF"}};
 model.ingest(snap,0);
 return model;
}
DepthSceneSources depthSceneSources(const wm::WorldModel& model) {
 DepthSceneSources source;source.generation=model.sessionGeneration();source.top=0;
 for(auto id:{10,11,20})source.buildings[id]={model.building(id)->version,{{0,0}}, {}};
 source.buildings[20].cells={{0,-1},{0,0}};
 source.buildings[20].foreground={{0,-1},{0,0}};
 return source;
}
void sameDepth(const DepthInterval& actual,const DepthInterval& expected) {
 CHECK(actual.bottom==expected.bottom);CHECK(actual.thickness==expected.thickness);
}
}
TEST_CASE("prepared scene reserves physical furniture only and keeps foreground fixed") {
 const auto model=depthSceneModel();const auto source=depthSceneSources(model);
 const auto result=prepareDepthScene(model,source);
 REQUIRE(result.valid);
 CHECK(result.items==std::vector<wm::ItemId>{30,30,20});
 CHECK(result.units==std::vector<wm::UnitId>{2,8});
 REQUIRE(result.itemDepth.size()==3);REQUIRE(result.unitDepth.size()==2);
 // Artwork-only northern cell is not an occupied/supporting building tile.
 CHECK(result.buildings.count({20,2,1})==0);
 CHECK(result.foreground.count({20,2,1})==0);
 std::vector<DepthFootprint> pieces={
  {2.5f,2.5f,.5f,.5f,0,1},
  {2.5f,2.5f,.5f,.5f,0,2},{2.5f,2.5f,.5f,.5f,0,2},{2.5f,2.5f,.5f,.5f,0,2},
  {2.5f,2.5f,.5f,.5f,0,3},{2.5f,2.5f,.5f,.5f,0,3},{2.5f,2.5f,.5f,.5f,0,4}};
 const auto expected=orderedDepthReference(pieces,{-1,-1,-1,-1,-1,-1,0},
     std::vector<float>(pieces.size(),kInstallationBottom));
 sameDepth(result.buildings.at({10,2,2}),{kInstallationBottom,0});
 sameDepth(result.buildings.at({11,2,2}),{kInstallationBottom,0});
 sameDepth(result.buildings.at({20,2,2}),expected[0]);
 for(size_t i=0;i<3;++i)sameDepth(result.itemDepth[i],expected[1+i]);
 for(size_t i=0;i<2;++i)sameDepth(result.unitDepth[i],expected[4+i]);
 sameDepth(result.foreground.at({20,2,2}),expected[0]);
 CHECK(expected[5].bottom+expected[5].thickness<kPieceCeiling);
}
TEST_CASE("prepared scene rejects missing stale and cross session footprint sources") {
 const auto model=depthSceneModel();auto source=depthSceneSources(model);
 source.buildings.erase(20);CHECK_FALSE(prepareDepthScene(model,source).valid);
 source=depthSceneSources(model);++source.buildings[20].version;
 CHECK_FALSE(prepareDepthScene(model,source).valid);
 source=depthSceneSources(model);++source.generation;
 CHECK_FALSE(prepareDepthScene(model,source).valid);
 source=depthSceneSources(model);source.top=-1;
 CHECK_FALSE(prepareDepthScene(model,source).valid);
}
TEST_CASE("prepared scene applies current terrain visibility reveal and z slice") {
 const auto model=depthSceneModel(true);auto source=depthSceneSources(model);
 auto result=prepareDepthScene(model,source);
 REQUIRE(result.valid);CHECK(result.items.empty());
 CHECK(result.buildings.count({20,2,2})==0);CHECK(result.buildings.count({20,2,1})==0);
 CHECK(result.foreground.count({20,2,2})==0);
 source.reveal=true;result=prepareDepthScene(model,source);
 REQUIRE(result.valid);CHECK(result.items.size()==3);CHECK(result.buildings.count({20,2,2})==1);
 source.top=1;source.window=1;result=prepareDepthScene(model,source);
 REQUIRE(result.valid);CHECK(result.buildings.empty());CHECK(result.items.empty());
 CHECK(result.units==std::vector<wm::UnitId>{11});
 source.sliceUnits=false;result=prepareDepthScene(model,source);
 CHECK(result.units==std::vector<wm::UnitId>{2,8,11});
 source.window=2;result=prepareDepthScene(model,source);
 CHECK(result.items.size()==3);CHECK(result.buildings.size()==3);
}

TEST_CASE("one pass visible item stacks exactly match per floor scans across windows and hidden terrain") {
 wm::WorldModel model;
 wm::SnapshotData snapshot;
 snapshot.tick=1;snapshot.mapSize={16,16,5};snapshot.terrainScope=wm::TerrainScope::Full;
 snapshot.tileStorage.resize(512);
 for(auto& tile:snapshot.tileStorage)tile.shape=wm::TileShape::Floor;
 snapshot.tileStorage[wm::tileIndexInBlock(2,3)].flags=wm::kTileHidden;
 snapshot.blocks={{{0,0,0},snapshot.tileStorage.data()},{{0,0,1},snapshot.tileStorage.data()+256}};
 snapshot.itemScope=wm::ChangeScope::Full;
 // Deliberately shuffled IDs and categories, quantity stacks, numeric/raw
 // subtypes, multiple tiles/levels, and items on as-yet unobserved terrain.
 for(int i=399;i>=0;--i) {
  wm::ItemObservation item;
  item.id=1000+i;item.pos={2+i%4,3+(i/4)%4,(i/16)%5};
  item.kind=i%3==0?wm::ItemKind::Chair:i%3==1?wm::ItemKind::Wood:wm::ItemKind::Tool;
  item.subtype=i%7;item.subtypeRaw=i%5==0?"B":i%5==1?"A":"";
  item.stack=i%4==0?200:1;snapshot.items.push_back(item);
 }
 model.ingest(snapshot,0);
 for(bool reveal:{false,true})for(auto [top,window]:std::vector<std::pair<int,int>>{
     {-1,24},{0,1},{1,1},{1,2},{2,0},{4,2},{6,3},{6,24},{100,1}}) {
  std::vector<ItemStackLayer> reference;
  for(int z=top;z>top-window && z>=0;--z) {
   std::map<uint64_t,std::vector<const wm::MapItem*>> tiles;
   std::vector<const wm::MapItem*> scanned;
   model.forEachItem([&](const wm::MapItem& item) { if(item.pos.z==z)scanned.push_back(&item); });
   for(const auto* item:scanned) {
    const auto p=item->pos;const auto tile=model.tileAt(p);
    if(!reveal && tile && (tile->flags&wm::kTileHidden))continue;
    const uint64_t key=(uint64_t(uint32_t(p.z))<<42)|(uint64_t(uint32_t(p.y)&0x1FFFFF)<<21)|(uint32_t(p.x)&0x1FFFFF);
    tiles[key].push_back(item);
   }
   for(const auto& [key,items]:tiles) {
    const auto stack=itemStack(items);
    reference.insert(reference.end(),stack.begin(),stack.end());
   }
  }
  const auto actual=visibleItemStackLayers(model,top,window,reveal);
  REQUIRE(actual.size()==reference.size());
  for(size_t i=0;i<actual.size();++i) {
   CHECK(actual[i].item->id==reference[i].item->id);
   CHECK(actual[i].bottom==reference[i].bottom);
   CHECK(actual[i].thickness==reference[i].thickness);
  }
 }
 CHECK(visibleItemStackLayers(model,4,5,true).size()>visibleItemStackLayers(model,4,5,false).size());
}

TEST_CASE("flat visible stack sort preserves crowded piles raw subtype equivalence and quantities") {
 wm::WorldModel model;
 wm::SnapshotData snapshot;
 snapshot.tick=1;snapshot.mapSize={64,64,4};snapshot.itemScope=wm::ChangeScope::Full;
 const wm::ItemKind kinds[]={wm::ItemKind::Chair,wm::ItemKind::Barrel,wm::ItemKind::Wood,
     wm::ItemKind::Tool,wm::ItemKind::Bar,wm::ItemKind::Boulder,wm::ItemKind::Corpse};
 for(int i=1499;i>=0;--i) {
  wm::ItemObservation item;
  item.id=10000+i;item.pos=i<1200?wm::TilePos{1,1,1}:wm::TilePos{16+(i%2),31,(i%3)};
  item.kind=kinds[i%7];item.subtype=i%11;
  // Equal nonempty raw names ignore differing numeric subtype; empty names
  // retain numeric subtype order. Different ranks/kinds share crowded tiles.
  item.subtypeRaw=i%4==0?"":i%4==1?"RAW_A":"RAW_B";
  item.stack=i%3==0?1:i%3==1?2:999;snapshot.items.push_back(item);
 }
 model.ingest(snapshot,0);
 for(auto [top,window]:std::vector<std::pair<int,int>>{{0,1},{1,1},{2,3},{3,4}}) {
  std::map<std::pair<int64_t,uint64_t>,std::vector<const wm::MapItem*>> tiles;
  model.forEachItem([&](const wm::MapItem& item) {
   const auto p=item.pos;if(p.z>top || p.z<=top-window)return;
   const uint64_t key=(uint64_t(uint32_t(p.z))<<42)|(uint64_t(uint32_t(p.y)&0x1FFFFF)<<21)|(uint32_t(p.x)&0x1FFFFF);
   tiles[{-int64_t(p.z),key}].push_back(&item);
  });
  std::vector<ItemStackLayer> expected;
  for(const auto& [key,items]:tiles) {
   const auto stack=itemStack(items);expected.insert(expected.end(),stack.begin(),stack.end());
  }
  const auto actual=visibleItemStackLayers(model,top,window,true);
  REQUIRE(actual.size()==expected.size());
  for(size_t i=0;i<actual.size();++i) {
   CHECK(actual[i].item==expected[i].item);
   CHECK(actual[i].bottom==expected[i].bottom);
   CHECK(actual[i].thickness==expected[i].thickness);
  }
 }
}


#include "df3d_mesher/unit_presentation.h"
TEST_CASE("unit departure follows delayed clock while arrivals retain immediate bootstrap") {
    wm::WorldModel model;
    wm::SnapshotData snapshot; snapshot.mapSize={16,16,4}; snapshot.tick=100;
    snapshot.units={{7,{1,1,1},wm::JobKind::Idle,"DWARF"}};
    model.ingest(snapshot,0);
    auto arrival=df3d::mesher::presentUnit(model.evaluate(7,100),model.evaluate(7,99));
    CHECK(arrival.state.presence==wm::Presence::Present);
    CHECK(arrival.sliceZ==1);
    snapshot.tick=102; snapshot.units.clear(); model.ingest(snapshot,1);
    auto before=df3d::mesher::presentUnit(model.evaluate(7,102),model.evaluate(7,101.9));
    CHECK(before.state.presence==wm::Presence::Present);
    CHECK(before.state.pos.x==1); CHECK(before.sliceZ==1);
    auto after=df3d::mesher::presentUnit(model.evaluate(7,102),model.evaluate(7,102));
    CHECK(after.state.presence==wm::Presence::Departed);
    CHECK(df3d::mesher::presentUnit(model.evaluate(7,102),model.evaluate(7,99)).state.presence==wm::Presence::NotYetSeen);
    wm::EvalResult current, delayed; current.presence=delayed.presence=wm::Presence::Present;
    current.pos={1,1,3}; delayed.pos={1,1,1};
    auto moving=df3d::mesher::presentUnit(current,delayed);
    CHECK(moving.state.pos.z==1); CHECK(moving.sliceZ==3);
}

TEST_CASE("ground item pose policy excludes living-looking corpses and fluid globs from billboards") {
    using I=wm::ItemKind;
    for (auto kind : {I::Corpse,I::CorpsePiece,I::Remains,I::Glob,I::LiquidMisc})
        CHECK(df3d::mesher::itemLiesOnGround(kind));
    for (auto kind : {I::Unknown,I::Weapon,I::Armor,I::Cage,I::Meat,I::Plant})
        CHECK_FALSE(df3d::mesher::itemLiesOnGround(kind));
}

TEST_CASE("completed Track face direction is independent of pending carve direction") {
  MapSource map(16,16,1);
  auto floor=tile(TileShape::Floor,MaterialKind::Constructed);
  floor.track=5;floor.completedTrack=10;map.set(3,4,0,floor);
  auto mesh=meshBlock(map,{0,0,0});
  const auto* top=find(mesh,3,4,FaceDir::PosZ);REQUIRE(top);
  CHECK(top->tag.completedTrack==10);
  CHECK(countPart(mesh,FacePart::Feature)==1);
  for(const auto& face:mesh.faces) if(face.tag.part==FacePart::Feature) {
    CHECK(face.tag.completedTrack==10);
    CHECK(face.tag.dir==FaceDir::PosZ);
  }
  floor.completedTrack=6;map.set(3,4,0,floor);
  mesh=meshBlock(map,{0,0,0});top=find(mesh,3,4,FaceDir::PosZ);REQUIRE(top);
  CHECK(top->tag.completedTrack==6);
  floor.completedTrack=0;map.set(3,4,0,floor);
  mesh=meshBlock(map,{0,0,0});top=find(mesh,3,4,FaceDir::PosZ);REQUIRE(top);
  CHECK(top->tag.completedTrack==0);
  CHECK(countPart(mesh,FacePart::Feature)==0);
}

TEST_CASE("completed ramp Track overlay follows every slope and lone top") {
  const int dx[]={1,-1,0,0,0}, dy[]={0,0,1,-1,0};
  for(int side=0;side<5;++side) {
    MapSource map(16,16,2);
    auto ramp=tile(TileShape::Ramp);ramp.completedTrack=3;map.set(5,5,0,ramp);
    if(side<4) map.set(5+dx[side],5+dy[side],0,kWall);
    auto mesh=meshBlock(map,{0,0,0});
    const Face* base=nullptr;const Face* overlay=nullptr;
    for(const auto& face:mesh.faces) {
      if(face.tag.lx!=5 || face.tag.ly!=5)continue;
      if(face.tag.part==FacePart::Feature) {CHECK(overlay==nullptr);overlay=&face;}
      if(face.tag.part==FacePart::Terrain && face.tag.dir==(side<4?FaceDir::Slope:FaceDir::PosZ))base=&face;
    }
    REQUIRE(base);REQUIRE(overlay);
    CHECK(overlay->tag.completedTrack==3);
    CHECK(overlay->tag.slopeHigh==base->tag.slopeHigh);
    for(size_t i=0;i<4;++i) {
      CHECK(overlay->v[i].x==doctest::Approx(base->v[i].x));
      CHECK(overlay->v[i].y==doctest::Approx(base->v[i].y));
      CHECK(overlay->v[i].z==doctest::Approx(base->v[i].z+.001f));
    }
    ramp.completedTrack=0;map.set(5,5,0,ramp);
    CHECK(countPart(meshBlock(map,{0,0,0}),FacePart::Feature)==0);
  }
}

TEST_CASE("native minimap material precedence and floor-finish matrix") {
 TileState tile;tile.shape=TileShape::Floor;tile.materialKind=MaterialKind::Stone;
 CHECK(minimapColor(tile)==0x808080);
 tile.flags=wm::kTileSmooth;CHECK(minimapColor(tile)==0x80c000);
 tile.subterranean=true;CHECK(minimapColor(tile)==0xc0c0c0);
 tile.flags=0;CHECK(minimapColor(tile)==0xc0c0c0);
 tile.materialKind=MaterialKind::Ice;CHECK(minimapColor(tile)==0xe0ffff);
 tile.shape=TileShape::Wall;CHECK(minimapColor(tile)==0xe0ffff);
 tile.materialKind=MaterialKind::Stone;tile.liquidLevel=1;tile.liquidKind=LiquidKind::Magma;
 CHECK(minimapColor(tile)==0x801800);
 tile.liquidKind=LiquidKind::Water;CHECK(minimapColor(tile)==0x0018c0);
 tile.buildingOccupancy=2;CHECK(minimapColor(tile)==0xc88c00);
 tile.flags=wm::kTileHidden;CHECK(minimapColor(tile)==-1);
 tile.flags=0;tile.buildingOccupancy=0;tile.liquidLevel=0;tile.liquidKind=LiquidKind::None;
 tile.shape=TileShape::Floor;
 TileState below;below.liquidLevel=7;below.liquidKind=LiquidKind::Water;below.flags=wm::kTileHidden;
 CHECK(minimapColor(tile,below)==0xc0c0c0);
 tile.brookTop=true;CHECK(minimapColor(tile,below)==0x0018c0);
 tile.brookTop=false;tile.shape=TileShape::Empty;CHECK(minimapColor(tile,below)==0x0018c0);
 CHECK(minimapColor(tile)==0x64e0ff);
 tile.shape=TileShape::Floor;tile.materialKind=MaterialKind::Ice;CHECK(minimapColor(tile,below)==0xe0ffff);
}

TEST_CASE("native surface rough ramps and stairs differ from rough ground") {
 TileState t;t.materialKind=MaterialKind::Stone;
 for(auto shape:{TileShape::Ramp,TileShape::StairUp,TileShape::StairDown,TileShape::StairUpDown}) {
  t.shape=shape;CHECK(minimapColor(t)==0x80c000);
 }
 t.materialKind=MaterialKind::Soil;t.shape=TileShape::Ramp;CHECK(minimapColor(t)==0x80c000);
 t.shape=TileShape::Floor;CHECK(minimapColor(t)==0x804000);
}

TEST_CASE("native root columns retain wall color distinct from tree trunks") {
 TileState t;t.shape=TileShape::TreeTrunk;t.materialKind=MaterialKind::Wood;
 CHECK(minimapColor(t)==0x644600);
 t.root=true;CHECK(minimapColor(t)==0x404040);
 t.buildingOccupancy=2;CHECK(minimapColor(t)==0xc88c00);
 t.flags=wm::kTileHidden;CHECK(minimapColor(t)==-1);
}

TEST_CASE("native map boundary lightens exposed walls roots and fortifications after higher priorities") {
 TileState t;t.materialKind=MaterialKind::Stone;
 for(auto shape:{TileShape::Wall,TileShape::Fortification}) {
  t.shape=shape;CHECK(minimapColor(t,std::nullopt,true)==0xc0c0c0);
  CHECK(minimapColor(t)==0x404040);
 }
 t.shape=TileShape::TreeTrunk;t.materialKind=MaterialKind::Wood;t.root=true;
 CHECK(minimapColor(t,std::nullopt,true)==0xc0c0c0);
 t.shape=TileShape::Wall;t.materialKind=MaterialKind::Ice;t.root=false;
 CHECK(minimapColor(t,std::nullopt,true)==0xe0ffff);
 t.materialKind=MaterialKind::Constructed;CHECK(minimapColor(t,std::nullopt,true)==0xc88c00);
 t.materialKind=MaterialKind::Stone;t.liquidLevel=7;t.liquidKind=LiquidKind::Magma;
 CHECK(minimapColor(t,std::nullopt,true)==0x801800);
 t.flags=wm::kTileHidden;CHECK(minimapColor(t,std::nullopt,true)==-1);
}
