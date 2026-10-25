// Semantic clock/activity history; no captured DF artwork or renderer scratch.
#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
    if(argc!=2)return 2;
    SyntheticFort fort(16,16,1);
    const auto granite=fort.material("GRANITE");
    fort.fillBox(TilePos(0,0,0),TilePos(15,15,0),
        TileState(TileShape::Floor,MaterialKind::Stone,granite,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
    for(int d=0;d<4;++d) {
        SyntheticFort::BuildingSpec b;
        b.kind=BuildingKind::ScrewPump;b.material=granite;
        b.x1=3+d*3;b.y1=6+d%2;b.x2=b.x1+(d%2);b.y2=b.y1+((d+1)%2);
        b.pumpDirection=d;b.pumpRunning=1;
        fort.placeBuilding(100+d,b);
    }
    fort.snapshot(10,1000,0);
    fort.snapshot(11,2000,10);
    for(int d=0;d<4;++d) {auto b=fort.building(100+d);b.pumpRunning=0;fort.placeBuilding(100+d,b);}
    fort.snapshot(12,3000,10);
    for(int d=0;d<4;++d) {auto b=fort.building(100+d);b.pumpRunning=1;fort.placeBuilding(100+d,b);}
    fort.snapshot(13,4000,-1);
    fort.snapshot(14,5000,0);
    for(int d=0;d<4;++d) {auto b=fort.building(100+d);b.pumpRunning=-1;fort.placeBuilding(100+d,b);}
    fort.snapshot(15,6000,10);
    for(int d=0;d<4;++d) {auto b=fort.building(100+d);b.pumpRunning=1;fort.placeBuilding(100+d,b);}
    fort.snapshot(16,7000,0);
    int sample=0;
    for(const char* material:{"INORGANIC:GRANITE","INORGANIC:IRON","GLASS_GREEN","PLANT:OAK:WOOD"})for(bool complete:{false,true}) {
        for(int d=0;d<4;++d) {auto b=fort.building(100+d);b.material=fort.material(material);b.stage=complete?BuildingStage::Complete:BuildingStage::Planned;b.pumpRunning=0;fort.placeBuilding(100+d,b);}
        fort.snapshot(17+sample,8000+1000*sample,0);++sample;
    }
    const auto bytes=fort.serialize();
    FixtureStream stream;std::string error;
    if(!parseFixture(bytes,stream,error))return 1;
    if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
    return writeFixtureFile(argv[1],bytes,error)?0:1;
}
