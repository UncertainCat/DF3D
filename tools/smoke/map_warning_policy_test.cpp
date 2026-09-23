#include <doctest.h>
#include "../../bridge/plugin/map_warning_policy.h"
using df3d_map_indicators::miningWarning;
TEST_CASE("native mining hazard footprint includes diagonals and above but not below") {
 for(int x=-2;x<=2;++x) for(int y=-2;y<=2;++y) for(int z=-1;z<=1;++z) {
  auto source=[&](int dx,int dy,int dz){return x==dx && y==dy && z==dz;};
  bool expected=(z==0&&x>=-1&&x<=1&&y>=-1&&y<=1)||(z==1&&x==0&&y==0);
  CHECK(miningWarning(10074,source)==(expected?1:0));
 }
}
TEST_CASE("warm threshold is inclusive and takes precedence over damp") {
 int reads=0; auto source=[&](int,int,int){++reads;return true;};
 CHECK(miningWarning(10074,source)==1);
 reads=0; CHECK(miningWarning(10075,source)==2); CHECK(reads==0);
 CHECK(miningWarning(60000,source)==2);
}

TEST_CASE("building occupancy exception requires native impassable or closed dynamic gate") {
 for(uint8_t occupancy=0;occupancy<8;++occupancy) {
  CHECK(df3d_map_indicators::buildingBlocksMiningWarning(occupancy,false)==(occupancy==6));
  CHECK(df3d_map_indicators::buildingBlocksMiningWarning(occupancy,true)==(occupancy==6||occupancy==7));
 }
}
