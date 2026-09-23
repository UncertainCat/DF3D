// Small deterministic ceiling-occupancy lifecycle, no licensed art required.
#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    SyntheticFort fort(16,16,3);
    const auto stone=fort.material("GRANITE"), other=fort.material("GABBRO");
    const auto tile=[&](TileShape shape, uint16_t material, int water=0, TileFlags flags=TileFlags::NONE) {
        return TileState(shape,MaterialKind::Stone,material,water,water?LiquidKind::Water:LiquidKind::None,flags,DesignationKind::None);
    };
    fort.fillBox(TilePos(0,0,0),TilePos(15,15,2),tile(TileShape::Empty,stone));
    fort.fillBox(TilePos(0,0,0),TilePos(15,15,0),tile(TileShape::Floor,stone));
    int frame=0;
    const auto snap=[&](){fort.snapshot(100+frame,1000+10000*frame);++frame;};
    snap();
    fort.setTile(2,2,1,tile(TileShape::Empty,other,1));snap();
    fort.setTile(2,2,2,tile(TileShape::Floor,stone));snap();
    fort.setTile(2,2,2,tile(TileShape::Floor,other,3));snap();
    fort.setTile(2,2,1,tile(TileShape::Floor,stone));snap();
    fort.setTile(2,2,2,tile(TileShape::Wall,other));snap();
    fort.setTile(2,2,1,tile(TileShape::Empty,stone));
    fort.setTile(2,2,2,tile(TileShape::Empty,stone));snap();
    fort.setTile(2,2,1,tile(TileShape::Empty,stone,0,TileFlags::Hidden));snap();
    fort.setTile(2,2,1,tile(TileShape::Empty,stone));snap();
    fort.setTile(15,15,2,tile(TileShape::Wall,stone));snap();
    // Door evidence lifecycle: a solid hidden neighbor contributes no jamb.
    fort.setTile(2,2,2,tile(TileShape::Wall,stone));snap();
    fort.setTile(2,2,2,tile(TileShape::Wall,stone,0,TileFlags::Hidden));snap();
    fort.setTile(2,2,2,tile(TileShape::Wall,stone));snap();
    fort.setTile(2,2,2,tile(TileShape::Floor,stone));snap();
    const auto bytes=fort.serialize();
    FixtureStream parsed;std::string error;
    if(!parseFixture(bytes,parsed,error))return 1;
    if(auto invalid=validateStream(parsed)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
    if(!writeFixtureFile(argv[1],bytes,error))return 1;
    std::printf("wrote render-cache fixture: %zu bytes\n",bytes.size());
}
