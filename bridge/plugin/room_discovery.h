#pragma once
#include "area_geometry.h"

namespace df3d_area {
// Semantic observations only: the caller classifies native tiles/buildings.
// A boundary cell is included when reached but never expands the search.
enum class RoomCell : uint8_t { Unobserved, Open, Boundary };
// Semantic source facts; these are not wire values or renderer shapes.
enum class RoomShape : uint8_t {
  None, Empty, Floor, Boulder, Pebbles, Wall, Fortification, StairUp,
  StairDown, StairUpDown, Ramp, RampTop, BrookBed, BrookTop, Branch,
  TrunkBranch, Twig, Sapling, Shrub, EndlessPit, Unknown
};
enum class RoomOccupancy : uint8_t {
  None, Planned, Passable, Obstacle, Well, Floored, Impassable, Dynamic
};
enum class RoomLiquid : uint8_t { None, Water, Magma };

// Native shape/occupancy/liquid partition probes004402. In particular, native
// Multi traverses Twig but not TrunkBranch: generic walkability is insufficient.
// door is an observed building lookup, not the door's open/closed animation flag.
inline RoomCell classifyRoomCell(RoomShape shape,RoomOccupancy occupancy,
                                 RoomLiquid liquid,uint8_t depth,bool door,
                                 bool observed=true) {
  if(!observed || shape>=RoomShape::Unknown || occupancy>RoomOccupancy::Dynamic ||
     liquid>RoomLiquid::Magma || depth>7 ||
     ((liquid==RoomLiquid::None)!=(depth==0)))return RoomCell::Unobserved;
  if(door || occupancy==RoomOccupancy::Obstacle || occupancy==RoomOccupancy::Well ||
     occupancy==RoomOccupancy::Impassable || liquid==RoomLiquid::Magma || depth==7)
    return RoomCell::Boundary;
  // Native paired probes050121: a building-supplied floor connects rooms even
  // over open space, walls or tree interiors; liquid/door guards still apply.
  if(occupancy==RoomOccupancy::Floored)return RoomCell::Open;
  switch(shape) {
    case RoomShape::Floor:case RoomShape::Boulder:case RoomShape::Pebbles:
    case RoomShape::StairUp:case RoomShape::StairDown:case RoomShape::StairUpDown:
    case RoomShape::Ramp:case RoomShape::BrookTop:case RoomShape::Branch:
    case RoomShape::Twig:case RoomShape::Sapling:case RoomShape::Shrub:
      return RoomCell::Open;
    default:return RoomCell::Boundary;
  }
}
enum class RoomTraversalStatus { Complete, Unenclosed, Incomplete, Invalid };
struct RoomTraversal {
  RoomTraversalStatus status=RoomTraversalStatus::Invalid;
  std::vector<uint8_t> reached;
};

// DF53.16 native Multi probes establish a maximum shortest-path depth of20
// through open cells, including diagonal steps. Reached walls/doors at depth21
// remain part of the footprint. This is a native behavior limit, not a CPU budget.
// Furniture eligibility, shape classification and transactional creation are
// separate responsibilities; this result alone cannot authorize a mutation.
// The supplied window is an observation boundary, not an enclosure limit.
inline RoomTraversal traverseRoom(const std::vector<RoomCell>& cells,
                                  uint32_t width,uint32_t height,
                                  uint32_t seedX,uint32_t seedY) {
  RoomTraversal out;
  // Existing area allocation/geometry limits; not native rejection semantics.
  if(!width || !height || width>kMaxSide || height>kMaxSide ||
     uint64_t(width)*height>kMaxCells || cells.size()!=size_t(width)*height ||
     seedX>=width || seedY>=height ||
     cells[size_t(seedY)*width+seedX]!=RoomCell::Open)return out;
  out.status=RoomTraversalStatus::Complete;
  out.reached.assign(cells.size(),0);
  std::vector<uint8_t> depth(cells.size(),0);
  std::vector<size_t> pending;
  pending.reserve(cells.size());
  const size_t seed=size_t(seedY)*width+seedX;
  out.reached[seed]=1;pending.push_back(seed);
  for(size_t cursor=0;cursor<pending.size();++cursor) {
    const auto index=pending[cursor];
    if(cells[index]==RoomCell::Boundary)continue;
    const int32_t x=int32_t(index%width),y=int32_t(index/width);
    for(int32_t dy=-1;dy<=1;++dy)for(int32_t dx=-1;dx<=1;++dx) {
      if(!dx && !dy)continue;
      const int32_t nx=x+dx,ny=y+dy;
      if(nx<0 || ny<0 || nx>=int32_t(width) || ny>=int32_t(height)) {
        out.status=RoomTraversalStatus::Incomplete;continue;
      }
      const size_t next=size_t(ny)*width+nx;
      if(cells[next]==RoomCell::Unobserved) {
        out.status=RoomTraversalStatus::Incomplete;continue;
      }
      if(out.reached[next])continue;
      const auto nextDepth=uint8_t(depth[index]+1);
      if(cells[next]==RoomCell::Open && nextDepth>20) {
        out.status=RoomTraversalStatus::Unenclosed;return out;
      }
      depth[next]=nextDepth;
      out.reached[next]=1;pending.push_back(next);
    }
  }
  return out;
}

struct RoomFootprint {
  Bounds bounds;
  int32_t z=-1;
  std::vector<uint8_t> extents;
  bool valid=false;
  bool contains(int32_t x,int32_t y,int32_t level) const {
    if(!valid || level!=z || x<bounds.x || y<bounds.y ||
       int64_t(x)>=int64_t(bounds.x)+bounds.width ||
       int64_t(y)>=int64_t(bounds.y)+bounds.height)return false;
    return extents[size_t(y-bounds.y)*bounds.width+x-bounds.x]!=0;
  }
};
// Convert the observation window to a native footprint without filling holes.
// Refused/incomplete traversals never become publishable plans.
inline RoomFootprint compactRoom(int32_t x,int32_t y,int32_t z,uint32_t width,uint32_t height,
                                  const RoomTraversal& traversal) {
  RoomFootprint out;
  if(traversal.status!=RoomTraversalStatus::Complete || z<0 || z>32767 || !width || !height ||
     width>kMaxSide || height>kMaxSide || uint64_t(width)*height>kMaxCells ||
     traversal.reached.size()!=size_t(width)*height)return out;
  uint32_t left=width,top=height,right=0,bottom=0;
  for(uint32_t row=0;row<height;++row)for(uint32_t col=0;col<width;++col) {
    const auto value=traversal.reached[size_t(row)*width+col];
    if(value>1)return out;
    if(!value)continue;
    left=std::min(left,col);right=std::max(right,col);
    top=std::min(top,row);bottom=std::max(bottom,row);
  }
  if(left==width || int64_t(x)+left<0 || int64_t(y)+top<0 ||
     int64_t(x)+right>32767 || int64_t(y)+bottom>32767)return out;
  out.bounds={int32_t(int64_t(x)+left),int32_t(int64_t(y)+top),
              int32_t(right-left+1),int32_t(bottom-top+1)};
  out.extents.reserve(size_t(out.bounds.width)*out.bounds.height);
  for(uint32_t row=top;row<=bottom;++row)
    out.extents.insert(out.extents.end(),traversal.reached.begin()+size_t(row)*width+left,
                       traversal.reached.begin()+size_t(row)*width+right+1);
  out.z=z;out.valid=true;return out;
}
inline bool sameRoom(const RoomFootprint& a,const RoomFootprint& b) {
  return a.valid && b.valid && a.z==b.z && a.bounds.x==b.bounds.x && a.bounds.y==b.bounds.y &&
    a.bounds.width==b.bounds.width && a.bounds.height==b.bounds.height && a.extents==b.extents;
}
} // namespace df3d_area
