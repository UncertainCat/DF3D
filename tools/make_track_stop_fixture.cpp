// Terrain-only track changes must refresh an unchanged Track Stop.
#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
 if(argc!=2)return 2;
 SyntheticFort fort(16,16,1);const auto stone=fort.material("GRANITE");
 const TileState floor(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None);
 fort.fillBox(TilePos(0,0,0),TilePos(15,15,0),floor);
 SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Trap;b.subtype=5;b.material=stone;
 b.x1=b.x2=8;b.y1=b.y2=8;fort.placeBuilding(100,b);
 for(int mask=0;mask<16;++mask){fort.setCompletedTrack(8,8,0,uint8_t(mask));fort.snapshot(10+mask,1000+mask*1000);}
 fort.setCompletedTrack(2,2,0,3);fort.snapshot(26,17000);
 fort.setBuildingStage(100,BuildingStage::Planned);fort.snapshot(27,18000);
 fort.setCompletedTrack(8,8,0,0);fort.setBuildingStage(100,BuildingStage::Complete);fort.snapshot(28,19000);
 const auto wood=fort.material("PLANT:OAK:WOOD");
 b=fort.building(100);b.constructionItemIsLog=1;b.constructionItemMaterial=wood;
 fort.placeBuilding(100,b);fort.snapshot(29,20000);
 b.constructionItemIsLog=0;fort.placeBuilding(100,b);fort.snapshot(30,21000);
 b.constructionItemMaterial=stone;fort.placeBuilding(100,b);fort.snapshot(31,22000);
 b.constructionItemIsLog=-1;b.constructionItemMaterial=kNoMaterial;
 fort.placeBuilding(100,b);fort.snapshot(32,23000);
 const auto bytes=fort.serialize();FixtureStream stream;std::string error;
 if(!parseFixture(bytes,stream,error))return 1;
 if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
 // Assert that connectivity updates carry no building updates.
 for(int i=1;i<=16;++i) {
  const auto* snapshot=stream.snapshots[i];
  if(snapshot->building_scope()!=ChangeScope::Delta ||
     (snapshot->buildings() && snapshot->buildings()->size()) ||
     (snapshot->removed_buildings() && snapshot->removed_buildings()->size()))return 1;
 }
 return writeFixtureFile(argv[1],bytes,error)?0:1;
}
