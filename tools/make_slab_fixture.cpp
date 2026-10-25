#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=2)return 2;
 SyntheticFort fort(24,16,1);auto stone=fort.material("INORGANIC:GRANITE"),iron=fort.material("INORGANIC:IRON");
 fort.fillBox(TilePos(0,0,0),TilePos(23,15,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
 for(int i=0;i<28;++i) {
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Slab;b.material=stone;b.slabEngraving=i-1;b.constructionItemIsLog=0;b.constructionItemMaterial=stone;
  b.x1=b.x2=2+(i%7)*3;b.y1=b.y2=2+(i/7)*3;fort.placeBuilding(100+i,b);
 }
 int step=0;auto snap=[&](){fort.snapshot(10+step,1000+1000*step);++step;};snap();
 for(int i=100;i<128;++i){auto b=fort.building(i);b.constructionItemMaterial=iron;fort.placeBuilding(i,b);}snap();
 for(int i=100;i<128;++i)fort.setBuildingStage(i,BuildingStage::Planned);snap();
 for(int i=100;i<128;++i){auto b=fort.building(i);b.stage=BuildingStage::Complete;b.slabEngraving=-2;b.constructionItemIsLog=-1;b.constructionItemMaterial=kNoMaterial;fort.placeBuilding(i,b);}snap();
 auto b=fort.building(100);fort.removeBuilding(100);snap();b.slabEngraving=0;b.constructionItemIsLog=0;b.constructionItemMaterial=iron;fort.placeBuilding(100,b);snap();
 auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[1],bytes,error)?0:1;
}
