#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=2)return 2;
 SyntheticFort fort(16,16,1);auto stone=fort.material("GRANITE"),wood=fort.material("PLANT:OAK:WOOD");
 fort.fillBox(TilePos(0,0,0),TilePos(15,15,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
 for(int axis=0;axis<2;++axis) {
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::WaterWheel;b.material=stone;
  b.x1=4+axis*5;b.y1=6;b.x2=b.x1+(axis?0:2);b.y2=b.y1+(axis?2:0);
  b.waterwheelMachinePosition=0;fort.placeBuilding(100+axis,b);
 }
 int step=0;auto snap=[&](){fort.snapshot(10+step,1000+1000*step);++step;};
 auto position=[&](int value){for(int id=100;id<102;++id){auto b=fort.building(id);b.waterwheelMachinePosition=value;fort.placeBuilding(id,b);}};
 snap();for(int p:{1,2,-129,-128,-3,-2,-1,127}){position(p);snap();}
 for(int id=100;id<102;++id)fort.setBuildingStage(id,BuildingStage::Planned);snap();
 position(0);snap();
 for(int id=100;id<102;++id){auto b=fort.building(id);b.stage=BuildingStage::Complete;b.constructionItemIsLog=1;b.constructionItemMaterial=wood;fort.placeBuilding(id,b);}snap();
 position(1);snap();
 for(int id=100;id<102;++id){auto b=fort.building(id);b.constructionItemIsLog=-1;b.constructionItemMaterial=kNoMaterial;fort.placeBuilding(id,b);}snap();
 auto original=fort.building(100);fort.removeBuilding(100);snap();fort.placeBuilding(100,original);snap();
 auto b=fort.building(101);b.waterwheelMachinePosition=0;fort.placeBuilding(101,b);snap();
 auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[1],bytes,error)?0:1;
}
