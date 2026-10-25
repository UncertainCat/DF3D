#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=2)return 2;
 SyntheticFort fort(16,16,1);auto stone=fort.material("GRANITE"),wood=fort.material("PLANT:OAK:WOOD");
 fort.fillBox(TilePos(0,0,0),TilePos(15,15,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
 SyntheticFort::BuildingSpec original;
 for(int d=0;d<4;++d) {
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Rollers;b.material=stone;
  b.x1=2+d*3;b.y1=6;b.x2=b.x1+(d%2?2:0);b.y2=b.y1+(d%2?0:2);
  b.rollerDirection=d;b.rollerMachinePosition=0;fort.placeBuilding(100+d,b);
  int cell=0;for(int y=b.y1;y<=b.y2;++y)for(int x=b.x1;x<=b.x2;++x)fort.setCompletedTrack(x,y,0,cell++==1?5:3);
  if(d==0)original=b;
 }
 int step=0;auto snap=[&](){fort.snapshot(10+step,1000+1000*step);++step;};
 auto position=[&](int value){for(int d=0;d<4;++d){auto b=fort.building(100+d);b.rollerMachinePosition=value;fort.placeBuilding(100+d,b);}};
 snap();for(int p:{1,2,-129,-128,127}){position(p);snap();}
 fort.setCompletedTrack(2,7,0,10);snap();
 fort.setCompletedTrack(0,0,0,3);snap();
 for(int d=0;d<4;++d)fort.setBuildingStage(100+d,BuildingStage::Planned);snap();
 position(0);snap();
 for(int d=0;d<4;++d)fort.setBuildingStage(100+d,BuildingStage::Complete);snap();
 fort.removeBuilding(100);snap();fort.placeBuilding(100,original);snap();
 auto b=fort.building(101);b.rollerMachinePosition=1;fort.placeBuilding(101,b);snap();
 for(int log:{1,0,-1}) {
  for(int d=0;d<4;++d){auto b=fort.building(100+d);b.constructionItemIsLog=log;b.constructionItemMaterial=log==-1?kNoMaterial:wood;fort.placeBuilding(100+d,b);}snap();
 }
 auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[1],bytes,error)?0:1;
}
