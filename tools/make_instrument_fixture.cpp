#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=2)return 2;
 SyntheticFort fort(16,16,1);const auto stone=fort.material("INORGANIC:GRANITE");
 const auto wood=fort.material("PLANT:OAK:WOOD"),iron=fort.material("INORGANIC:IRON");
 const TileState floor(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None);
 fort.fillBox(TilePos(0,0,0),TilePos(15,15,0),floor);
 SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Instrument;b.material=stone;
 b.x1=b.x2=8;b.y1=b.y2=8;
 int step=0;
 auto capture=[&] {fort.placeBuilding(100,b);fort.snapshot(10+step,1000+step*1000);++step;};
 capture();
 for(int family=0;family<4;++family)for(int placed=0;placed<2;++placed)
 for(auto stage:{BuildingStage::Planned,BuildingStage::Complete}) {
  b.instrumentFamily=int8_t(family);b.instrumentPlaced=int8_t(placed);b.stage=stage;
  b.constructionItemIsLog=0;b.constructionItemMaterial=family%2?iron:wood;capture();
 }
 b.instrumentFamily=-1;b.instrumentPlaced=-1;b.constructionItemIsLog=-1;b.constructionItemMaterial=kNoMaterial;capture();
 fort.removeBuilding(100);fort.snapshot(10+step,1000+step*1000);++step;
 capture(); // reused ID must not inherit the old definition or palette
 const auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[1],bytes,error)?0:1;
}
