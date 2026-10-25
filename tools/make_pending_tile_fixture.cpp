#include <cstdio>
#include <fstream>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=3)return 2;
 std::ifstream input(argv[1]);if(!input)return 2;
 SyntheticFort fort(12,12,1);const auto stone=fort.material("INORGANIC:GRANITE");
 fort.fillBox(TilePos(0,0,0),TilePos(11,11,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
 const char* materials[]={"INORGANIC:GRANITE","INORGANIC:IRON","GLASS_GREEN","PLANT:OAK:WOOD"};
 int subtype,material,step=0;
 while(input>>subtype>>material) {
  if(subtype<0 || subtype>37 || material<0 || material>3)return 2;
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Construction;b.subtype=uint16_t(subtype);
  b.x1=b.y1=b.x2=b.y2=4;b.material=fort.material(materials[material]);
  b.constructionStage=0;b.stage=BuildingStage::Planned;
  fort.placeBuilding(100,b);fort.snapshot(10+step,1000+1000*step);++step;
 }
 if(!input.eof() || !step)return 2;
 auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[2],bytes,error)?0:1;
}
