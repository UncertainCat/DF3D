// Small deterministic movement history for cutout elevation regression.
#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;

int main(int argc,char** argv) {
    if(argc!=2)return 2;
    SyntheticFort fort(16,16,5);
    const auto granite=fort.material("GRANITE");
    fort.fillBox(TilePos(0,0,0),TilePos(15,15,4),
        TileState(TileShape::Floor,MaterialKind::Stone,granite,0,LiquidKind::None,TileFlags::NONE, df3d::mirror::DesignationKind::None));
    fort.addUnit(201,"CAT",2,2,1);
    fort.addUnit(202,"CAT",4,2,2);
    fort.addUnit(203,"CAT",6,2,4);
    fort.addUnit(204,"CAT",2,4,1);
    fort.addUnit(205,"CAT",8,2,1);
    SyntheticFort::ItemSpec item;
    item.kind=ItemKind::Bar;item.material=granite;item.stack=2;
    item.x=2;item.y=2;item.z=2;
    fort.placeItem(301,item);
    fort.snapshot(10);
    fort.moveUnit(201,2,2,2);
    fort.moveUnit(202,4,2,1);
    fort.moveUnit(203,6,2,1);
    fort.moveUnit(204,14,4,4);
    fort.moveUnit(205,9,2,1);
    fort.snapshot(11);
    const auto bytes=fort.serialize();
    FixtureStream stream;
    std::string error;
    if(!parseFixture(bytes,stream,error))return 1;
    if(auto invalid=validateStream(stream)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
    if(!writeFixtureFile(argv[1],bytes,error))return 1;
    std::printf("wrote vertical motion fixture: %zu bytes\n",bytes.size());
}
