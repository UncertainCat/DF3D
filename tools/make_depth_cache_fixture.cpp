// Asset-free warm-cache lifecycle regression. Large arrival gaps let the
// Godot test advance one batch at a time through the ordinary replay API.
#include <cstdio>
#include <string>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
    if(argc!=2)return 2;
    SyntheticFort fort(16,16,3);
    const auto granite=fort.material("GRANITE");
    fort.fillBox(TilePos(0,0,0),TilePos(15,15,2),TileState(TileShape::Floor,MaterialKind::Stone,granite,0,LiquidKind::None,TileFlags::NONE, df3d::mirror::DesignationKind::None));
    SyntheticFort::BuildingSpec building;
    building.kind=BuildingKind::Table; building.material=granite;
    building.x1=building.x2=4; building.y1=building.y2=5; building.z=1;
    fort.placeBuilding(700,building);
    SyntheticFort::ItemSpec item;
    item.kind=ItemKind::Bar;item.material=granite;item.x=6;item.y=5;item.z=1;item.stack=1;
    fort.placeItem(800,item);
    fort.snapshot(100,1000);
    building.x2=6;
    fort.placeBuilding(700,building);
    fort.snapshot(101,11000);
    fort.removeBuilding(700);
    fort.snapshot(102,21000);
    fort.placeBuilding(700,building);
    fort.snapshot(103,31000);
    // The test ingests these two snapshots in one poll: Changed is coalesced,
    // but the final building's version restarts at 1, matching its cached one.
    fort.removeBuilding(700);
    fort.snapshot(104,41000);
    building.x2=4;
    fort.placeBuilding(700,building);
    fort.snapshot(105,51000);
    const auto bytes=fort.serialize();
    FixtureStream parsed;
    std::string error;
    if(!parseFixture(bytes,parsed,error))return 1;
    if(auto invalid=validateStream(parsed)) {std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
    if(!writeFixtureFile(argv[1],bytes,error))return 1;
    std::printf("wrote depth-cache fixture: %zu bytes\n",bytes.size());
}
