#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc, char** argv) {
    if (argc!=2) return 2;
    SyntheticFort fort(16,16,3);
    const auto stone=fort.material("GRANITE");
    fort.fillBox(TilePos(0,0,0),TilePos(15,15,2),
        TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
    fort.addUnit(1,"DWARF",2,2,1);
    for (int i=0;i<80;++i) {
        SyntheticFort::Layer layer; layer.page="DWARF_BODY";
        layer.tileX=1; layer.tileY=0; layer.offsetX=int8_t(i);
        fort.setAppearance(1,{layer});
        fort.snapshot(100+i,1000+i*1000);
    }
    const auto bytes=fort.serialize(); FixtureStream stream; std::string error;
    if (!parseFixture(bytes,stream,error) || validateStream(stream) || !writeFixtureFile(argv[1],bytes,error)) return 1;
    std::printf("RESOURCE_LIFETIME_FIXTURE_PASS %zu bytes\n",bytes.size());
}
