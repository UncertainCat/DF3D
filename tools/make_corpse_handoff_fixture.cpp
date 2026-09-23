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
    for (int i=0;i<3;++i) {
        SyntheticFort::ItemSpec item; item.kind=i==2?ItemKind::CorpsePiece:ItemKind::Corpse;
        item.material=stone;item.x=2;item.y=2;item.z=1;item.corpseUnitId=i==1?-1:77;
        fort.placeItem(100+i,item);
    }
    fort.snapshot(1,1000);
    const auto bytes=fort.serialize();FixtureStream parsed;std::string error;
    if(!parseFixture(bytes,parsed,error))return 1;
    if(auto invalid=validateStream(parsed)){std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
    if(!writeFixtureFile(argv[1],bytes,error))return 1;
    std::printf("wrote item updates fixture: %zu bytes\n",bytes.size());
}
