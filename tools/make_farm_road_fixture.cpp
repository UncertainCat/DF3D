#include <cstdio>
#include <fstream>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=3)return 2;
 std::ifstream input(argv[1]);if(!input)return 2;
 SyntheticFort fort(16,16,1);const auto stone=fort.material("INORGANIC:GRANITE");
 fort.fillBox(TilePos(0,0,0),TilePos(15,15,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
 const char* materials[]={"INORGANIC:GRANITE","INORGANIC:IRON","GLASS_GREEN","PLANT:OAK:WOOD"};
 int kind,width,height,stage,material,component,step=0;std::string mask;
 while(input>>kind>>width>>height>>stage>>material>>component>>mask) {
  if(kind<0 || kind>2 || material<0 || material>3 || component < -1 || component>3)return 2;
  SyntheticFort::BuildingSpec b;b.kind=kind==0?BuildingKind::FarmPlot:kind==1?BuildingKind::RoadDirt:BuildingKind::RoadPaved;
  b.x1=b.y1=4;b.x2=3+width;b.y2=3+height;b.material=fort.material(materials[material]);
  b.constructionStage=stage;b.stage=stage==3?BuildingStage::Complete:stage==0?BuildingStage::Planned:BuildingStage::InProgress;
  if(mask!="NONE")for(char c:mask)b.extents.push_back(c=='1');
  // These families do not publish component facts: native artwork ignores
  // them. Retain the native component variations only in the reference rows.
  fort.placeBuilding(100,b);fort.snapshot(10+step,1000+1000*step);++step;
 }
 if(!input.eof() || !step)return 2;
 auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[2],bytes,error)?0:1;
}
