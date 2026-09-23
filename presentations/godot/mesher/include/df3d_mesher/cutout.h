#pragma once
#include <vector>
#include <span>
#include <cstdint>
#include <algorithm>
#include <array>
#include <bit>
#include <unordered_map>
namespace df3d::mesher {
inline constexpr float kCutoutThickness = 0.12f;
struct CutoutVertex { float x,y,z,u,v,shade; };
struct IndexedCutoutMesh {
 std::vector<CutoutVertex> vertices;
 std::vector<int32_t> indices;
};
// Share only bit-identical complete vertices. In particular, edge UVs must
// remain separate from front/back UVs even at the same position. Triangle
// order and every vertex-shader input are preserved, including bend anchors.
inline IndexedCutoutMesh indexCutoutMesh(std::span<const CutoutVertex> input) {
 using Key = std::array<uint32_t,6>;
 struct Hash {
  size_t operator()(const Key& key) const {
   size_t hash=0;
   for(auto value:key) hash^=size_t(value)+size_t(0x9e3779b9u)+(hash<<6)+(hash>>2);
   return hash;
  }
 };
 IndexedCutoutMesh out;
 out.vertices.reserve(input.size());
 out.indices.reserve(input.size());
 std::unordered_map<Key,int32_t,Hash> lookup;
 lookup.reserve(input.size());
 for(const auto& v:input) {
  const Key key={std::bit_cast<uint32_t>(v.x),std::bit_cast<uint32_t>(v.y),
   std::bit_cast<uint32_t>(v.z),std::bit_cast<uint32_t>(v.u),
   std::bit_cast<uint32_t>(v.v),std::bit_cast<uint32_t>(v.shade)};
  auto [it,inserted]=lookup.try_emplace(key,static_cast<int32_t>(out.vertices.size()));
  if(inserted) out.vertices.push_back(v);
  out.indices.push_back(it->second);
 }
 return out;
}
// Opaque neighbouring pixels cover a vertical interval on an image boundary.
// side: north/east/south/west; pixel: x for N/S, y for E/W.
struct CutoutEdgeCover { int side, pixel; float bottom, top; };
// Merge horizontal opaque runs for top/bottom; emit only exposed pixel edges.
// Image up is north (-Z), independent of view. Holes remain actual holes.
inline std::vector<CutoutVertex> cutoutMesh(std::span<const uint8_t> alpha, int w, int h,
                                         std::span<const CutoutEdgeCover> covers = {}) {
 std::vector<CutoutVertex> out;
 if(w<=0 || h<=0 || alpha.size()!=size_t(w)*h) return out;
 auto solid=[&](int x,int y){return x>=0&&y>=0&&x<w&&y<h&&alpha[y*w+x]>=128;};
 auto v=[&](float x,float z,float y,float shade){return CutoutVertex{x/w-.5f,y,z/h-.5f,x/w,z/h,shade};};
 auto quad=[&](CutoutVertex a,CutoutVertex b,CutoutVertex c,CutoutVertex d){for(auto q:{a,b,c,a,c,d})out.push_back(q);};
 for(int y=0;y<h;++y) for(int x=0;x<w;){
  if(!solid(x,y)){++x;continue;} int end=x+1;while(end<w&&solid(end,y))++end;
  quad(v(x,y,kCutoutThickness,1),v(end,y,kCutoutThickness,1),v(end,y+1,kCutoutThickness,1),v(x,y+1,kCutoutThickness,1));
  quad(v(x,y,0,1),v(x,y+1,0,1),v(end,y+1,0,1),v(end,y,0,1)); x=end;
 }
 for(int y=0;y<h;++y)for(int x=0;x<w;++x)if(solid(x,y)){
  // Sample the owning opaque pixel, never the alpha boundary. Boundary UVs
  // can select a transparent neighbour's RGB and produce vertical streaks.
  // Keep the source colour without adding a dark outline to the extrusion.
  auto side=[&](float px,float pz,float height){auto q=v(px,pz,height,1);q.u=(x+.5f)/w;q.v=(y+.5f)/h;return q;};
  auto edge=[&](float ax,float az,float bx,float bz,int direction,bool boundary,int pixel){
   if(!boundary || covers.empty()) {quad(side(ax,az,0),side(bx,bz,0),side(bx,bz,kCutoutThickness),side(ax,az,kCutoutThickness));return;}
   std::vector<std::pair<float,float>> exposed={{0,kCutoutThickness}};
   if(boundary)for(const auto& cover:covers)if(cover.side==direction&&cover.pixel==pixel){
    std::vector<std::pair<float,float>> next;
    for(auto [lo,hi]:exposed){
     if(cover.top<=lo||cover.bottom>=hi){next.push_back({lo,hi});continue;}
     if(cover.bottom>lo)next.push_back({lo,std::min(hi,cover.bottom)});
     if(cover.top<hi)next.push_back({std::max(lo,cover.top),hi});
    }exposed=std::move(next);
   }
   // Converting neighbours' allocated heights back to normalized cutout
   // coordinates can leave sub-micro slivers at otherwise joined boundaries.
   // Those collapse into duplicate zero-area triangles at world-space z143.
   for(auto [lo,hi]:exposed)if(hi-lo>kCutoutThickness*0.00001f)
    quad(side(ax,az,lo),side(bx,bz,lo),side(bx,bz,hi),side(ax,az,hi));
  };
  if(!solid(x,y-1))edge(x,y,x+1,y,0,y==0,x);
  if(!solid(x+1,y))edge(x+1,y,x+1,y+1,1,x==w-1,y);
  if(!solid(x,y+1))edge(x+1,y+1,x,y+1,2,y==h-1,x);
  if(!solid(x-1,y))edge(x,y+1,x,y,3,x==0,y);
 }
 return out;
}
}
