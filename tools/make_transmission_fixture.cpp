#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=2)return 2;
 SyntheticFort fort(24,16,1);auto stone=fort.material("GRANITE"),wood=fort.material("PLANT:OAK:WOOD"),iron=fort.material("INORGANIC:IRON");
 fort.fillBox(TilePos(0,0,0),TilePos(23,15,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
 SyntheticFort::BuildingSpec original;
 for(int i=0;i<6;++i) {
  SyntheticFort::BuildingSpec b;b.kind=i<4?BuildingKind::AxleHorizontal:i==4?BuildingKind::AxleVertical:BuildingKind::GearAssembly;b.material=stone;
  b.x1=2+i*3;b.y1=6;b.x2=b.x1+(i==0?2:0);b.y2=b.y1+(i==1?2:0);
  b.horizontalAxleVertical=i<4?i%2:-1;b.gearAxleMachinePosition=0;fort.placeBuilding(100+i,b);if(i==0)original=b;
 }
 int step=0;auto snap=[&](){fort.snapshot(10+step,1000+1000*step);++step;};
 auto position=[&](int value){for(int id=100;id<106;++id){auto b=fort.building(id);b.gearAxleMachinePosition=value;fort.placeBuilding(id,b);}};
 snap();for(int p:{1,2,-129,-128,-3,-1,127}){position(p);snap();}
 for(int id=100;id<106;++id)fort.setBuildingStage(id,BuildingStage::Planned);snap();position(0);snap();
 for(int id=100;id<106;++id){auto b=fort.building(id);b.stage=BuildingStage::Complete;b.constructionItemIsLog=id==105?0:1;b.constructionItemMaterial=wood;fort.placeBuilding(id,b);}snap();
 position(1);snap();
 for(int id=100;id<106;++id){auto b=fort.building(id);b.constructionItemMaterial=iron;fort.placeBuilding(id,b);}snap();
 for(int id=100;id<106;++id){auto b=fort.building(id);b.constructionItemIsLog=-1;b.constructionItemMaterial=kNoMaterial;fort.placeBuilding(id,b);}snap();
 fort.removeBuilding(100);snap();fort.placeBuilding(100,original);snap();
 auto b=fort.building(101);b.gearAxleMachinePosition=0;fort.placeBuilding(101,b);snap();
 b=fort.building(102);b.horizontalAxleVertical=1;fort.placeBuilding(102,b);snap();
 auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[1],bytes,error)?0:1;
}
