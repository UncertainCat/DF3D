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
 const char* colors[]={"CLEAR","GRAY","DARK_GREEN","AUBURN"};
 int stage,maximum,count,state,weapons,material,buildingMaterial,step=0;std::string raw;
 while(input>>stage>>maximum>>count>>state>>weapons>>material>>buildingMaterial>>raw) {
  if(material < -1 || material>3 || buildingMaterial<0 || buildingMaterial>3)return 2;
  SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Weapon;
  b.x1=b.y1=b.x2=b.y2=4;b.material=fort.material(materials[buildingMaterial]);
  b.constructionStage=stage;b.stage=stage==maximum?BuildingStage::Complete:stage==0?BuildingStage::Planned:BuildingStage::InProgress;
  b.containedItemCount=count;b.weaponRetracted=state;b.weaponCount=weapons;
  if(raw!="NONE")b.constructionWeaponRaw=raw;
  if(material>=0){b.constructionItemIsLog=0;b.constructionItemId=1000;b.constructionItemMaterial=fort.material(materials[material]);b.constructionItemSolidColor=colors[material];}
  fort.placeBuilding(100,b);fort.snapshot(10+step,1000+1000*step);++step;
 }
 if(!input.eof() || !step)return 2;
 auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 return writeFixtureFile(argv[2],bytes,error)?0:1;
}
