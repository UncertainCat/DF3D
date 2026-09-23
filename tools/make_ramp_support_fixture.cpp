#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
#include <cstdio>
using namespace df3d::mirror;
int main(int argc,char** argv) {
    if(argc!=2)return 2;
    SyntheticFort fort(32,16,3);
    const auto stone=fort.material("GRANITE");
    const auto tile=[&](TileShape shape,int water=0) {return TileState(shape,MaterialKind::Stone,stone,water,water?LiquidKind::Water:LiquidKind::None,TileFlags::NONE,DesignationKind::None);};
    fort.fillBox(TilePos(0,0,0),TilePos(31,15,0),tile(TileShape::Floor));
    const int dx[]={0,1,0,-1,0},dy[]={-1,0,1,0,0};
    for(int side=0;side<5;++side) {
        const int x=side==1?15:3+side*5,y=side==1?5:10;
        fort.setTile(x,y,0,tile(TileShape::Ramp));
        if(side<4)fort.setTile(x+dx[side],y+dy[side],0,tile(TileShape::Wall));
        fort.addUnit(side+1,"DWARF",x,y,0);
        SyntheticFort::Layer body;body.page="DWARF_BODY";body.tileX=3;body.tileY=4;
        body.palette="data/vanilla/vanilla_creatures_graphics/graphics/images/dwarf/dwarf_body_palettes.png";
        body.paletteRow=2;body.paletteKeyRow=0;
        fort.setAppearance(side+1,{body});
        SyntheticFort::ItemSpec item;item.kind=ItemKind::Bar;item.material=stone;item.x=x;item.y=y;
        fort.placeItem(100+side,item);
        SyntheticFort::BuildingSpec b;b.kind=BuildingKind::Table;b.material=stone;b.x1=b.x2=x;b.y1=b.y2=y;b.z=0;
        fort.placeBuilding(200+side,b);
    }
    fort.snapshot(100,1000);
    fort.setTile(15,5,0,tile(TileShape::Ramp,1));fort.snapshot(101,11000);
    fort.setTile(16,5,0,tile(TileShape::Floor));fort.snapshot(102,21000);
    const auto bytes=fort.serialize();FixtureStream stream;std::string error;
    if(!parseFixture(bytes,stream,error)||validateStream(stream)||!writeFixtureFile(argv[1],bytes,error))return 1;
    std::puts("RAMP_SUPPORT_FIXTURE_PASS");
}
