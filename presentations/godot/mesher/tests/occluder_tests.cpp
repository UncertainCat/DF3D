#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
#include "df3d_mesher/opaque_occluders.h"
using namespace df3d::mesher;
static Face quad(float x,float y) {
 Face f;f.v={Vec3{x,y,1},Vec3{x+1,y,1},Vec3{x+1,y+1,1},Vec3{x,y+1,1}};return f;
}
TEST_CASE("opaque rectangles merge full coverage without bridging openings") {
 std::vector<Face> faces;
 for(int y=0;y<16;++y)for(int x=0;x<16;++x)faces.push_back(quad(x,y));
 auto out=opaqueOccluders(faces);REQUIRE(out.size()==1);
 CHECK(out[0].u0==0);CHECK(out[0].u1==16);CHECK(out[0].v0==0);CHECK(out[0].v1==16);
 faces.erase(faces.begin()+8*16+8);
 out=opaqueOccluders(faces);
 double area=0;for(const auto& r:out){area+=(r.u1-r.u0)*(r.v1-r.v0);CHECK_FALSE((r.u0<8.5f && r.u1>8.5f && r.v0<8.5f && r.v1>8.5f));}
 CHECK(area==255);
}
TEST_CASE("slopes triangles gaps and distinct planes never become solid rectangles") {
 auto slope=quad(0,0);slope.v[2].z=2;slope.v[3].z=2;
 auto triangle=quad(0,0);triangle.v[3]=triangle.v[2];
 CHECK(opaqueOccluders({slope,triangle}).empty());
 auto offset=quad(0,0);for(auto& p:offset.v)p.z=2;
 CHECK(opaqueOccluders({quad(0,0),quad(2,0),offset}).size()==3);
}
TEST_CASE("every emitted rectangle covers source cells for irregular patterns") {
 for(int pattern=0;pattern<64;++pattern){
  std::vector<Face> faces;
  for(int y=0;y<8;++y)for(int x=0;x<8;++x)if(((x*17+y*23+pattern)%7)>1)faces.push_back(quad(x,y));
  const auto out=opaqueOccluders(faces);
  for(const auto& r:out)for(int y=int(r.v0);y<int(r.v1);++y)for(int x=int(r.u0);x<int(r.u1);++x)CHECK(((x*17+y*23+pattern)%7)>1);
 }
}
