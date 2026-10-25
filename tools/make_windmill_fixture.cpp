#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=2)return 2;
 SyntheticFort fort(16,16,1);auto stone=fort.material("GRANITE"),wood=fort.material("PLANT:OAK:WOOD");
 fort.fillBox(TilePos(0,0,0),TilePos(15,15,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
 SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Windmill;b.material=stone;b.x1=6;b.y1=6;b.x2=8;b.y2=8;
 int step=0;auto snap=[&](){fort.placeBuilding(100,b);fort.snapshot(10+step,1000+1000*step);++step;};
 snap();
 for(auto stage:{BuildingStage::Complete,BuildingStage::Planned}) {
  b.stage=stage;
  for(int x=-1;x<=1;++x)for(int y=-1;y<=1;++y)for(int rotation:{0,1,-128,127}) {
   b.windmillOrientX=x;b.windmillOrientY=y;b.windmillRotation=rotation;snap();
  }
 }
 b.stage=BuildingStage::Complete;b.constructionItemIsLog=1;b.constructionItemMaterial=wood;snap();
 b.windmillRotation=0;snap();
 b.constructionItemIsLog=-1;b.constructionItemMaterial=kNoMaterial;snap();
 fort.removeBuilding(100);fort.snapshot(10+step,1000+1000*step);++step;snap();
 auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[1],bytes,error)?0:1;
}
