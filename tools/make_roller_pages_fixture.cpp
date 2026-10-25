#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=2)return 2;
 SyntheticFort fort(32,32,1);const auto stone=fort.material("GRANITE");
 fort.fillBox(TilePos(0,0,0),TilePos(31,31,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
 auto put=[&](int cell,int id,int phase) {
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Rollers;b.material=stone;
  b.x1=b.x2=2+cell%20;b.y1=b.y2=2+cell/20;
  b.rollerDirection=cell%4;b.rollerMachinePosition=(cell+phase)%256-128;
  fort.placeBuilding(id,b);
 };
 int step=0;auto snap=[&] {fort.snapshot(10+step,1000+step*1000);++step;};
 for(int i=0;i<300;++i){put(i,1000+i,0);}snap();
 for(int i=0;i<300;++i){put(i,1000+i,1);}snap();
 for(int i=0;i<300;i+=2){fort.removeBuilding(1000+i);}snap();
 for(int i=0;i<300;i+=2){put(i,2000+i,2);}snap();
 for(int i=0;i<300;++i){fort.removeBuilding((i%2?1000:2000)+i);}snap();
 for(int i=0;i<300;++i){put(i,3000+i,3);}snap();
 for(int i=0;i<300;++i){put(i,3000+i,4);}snap();
 const auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[1],bytes,error)?0:1;
}
