// Local item payload/compaction regression, with explicit replay arrival gaps.
#include <cstdio>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc,char** argv) {
    if(argc!=2)return 2;
    SyntheticFort fort(48,16,3);
    const auto stone=fort.material("GRANITE");
    fort.fillBox(TilePos(0,0,0),TilePos(47,15,2),
        TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
    const auto place=[&](uint32_t id,ItemKind kind,int x,int z,uint32_t stack) {
        SyntheticFort::ItemSpec item;item.kind=kind;item.material=stone;
        item.x=x;item.y=1;item.z=z;item.stack=stack;fort.placeItem(id,item);
    };
    place(100,ItemKind::Bar,1,1,1);place(200,ItemKind::Wood,2,1,2);
    place(300,ItemKind::Chair,18,1,1);place(400,ItemKind::Bar,33,1,2);place(500,ItemKind::Wood,34,2,1);
    fort.requestFullGlyphs();
    int frame=0;
    const auto snap=[&](){fort.snapshot(100+frame,1000+10000*frame);++frame;};
    snap();
    fort.moveItem(100,2,1,1);snap();
    fort.removeItem(100);snap();
    place(100,ItemKind::Chair,34,2,2);snap();
    fort.setItemFlags(300,ItemFlags::Dump);snap();
    fort.moveItem(400,34,1,1);snap();
    fort.materialGlyph("INORGANIC:UNRELATED", {});snap();
    // Terrain changes beside a pile must not refresh unrelated item records.
    fort.setTile(3,1,1,TileState(TileShape::Floor,MaterialKind::Stone,stone,3,LiquidKind::Water,TileFlags::NONE,DesignationKind::None));snap();
    fort.setTile(2,1,1,TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::Hidden,DesignationKind::None));snap();
    fort.setTile(2,1,1,TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));snap();
    const auto bytes=fort.serialize();FixtureStream parsed;std::string error;
    if(!parseFixture(bytes,parsed,error))return 1;
    if(auto invalid=validateStream(parsed)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
    if(!writeFixtureFile(argv[1],bytes,error))return 1;
    std::printf("wrote item updates fixture: %zu bytes\n",bytes.size());
}
