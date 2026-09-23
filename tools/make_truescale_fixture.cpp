#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
#include "unit_status.h"
#include <cstdio>
using namespace df3d::mirror;
int main(int argc,char** argv) {
    if(argc!=2)return 2;
    SyntheticFort fort(32,16,4);
    const auto stone=fort.material("GRANITE");
    fort.fillBox(TilePos(0,0,0),TilePos(31,15,0),TileState(TileShape::Floor,MaterialKind::Stone,stone,0,LiquidKind::None,TileFlags::NONE,DesignationKind::None));
    // Same species/art, different physical volumes. No visual policy in the fixture.
    for(uint64_t id=1;id<=3;++id)fort.addUnit(id,"COLOSSUS_BRONZE",int(id)*6,7,0);
    fort.setBodyVolume(1,3000);fort.setBodyVolume(2,60000);fort.setBodyVolume(3,20000000);
    fort.addUnit(4,"DWARF",8,10,0); fort.setBodyVolume(4,3000);
    fort.addUnit(5,"DWARF",16,10,0); fort.setBodyVolume(5,90000);
    fort.addUnit(6,"DWARF",24,10,0); fort.setBodyVolume(6,3000);
    fort.setUnitStatusFlags(6,df3d::unit_status::Baby);
    // Explicit shared specimen art isolates classification from missing dwarf layers.
    for(uint64_t id=4;id<=6;++id)fort.setAppearance(id,{{"CREATURES_MEGABEAST",0,0,3,2}});
    fort.snapshot(1000);
    const auto bytes=fort.serialize();FixtureStream stream;std::string error;
    if(!parseFixture(bytes,stream,error)||validateStream(stream)||!writeFixtureFile(argv[1],bytes,error))return 1;
    std::puts("TRUESCALE_FIXTURE_PASS");
}
