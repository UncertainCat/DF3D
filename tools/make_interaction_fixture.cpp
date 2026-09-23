// Asset-free fixture for current-slice interaction/query regression tests.
// Output is regenerable test data, normally build/interaction.df3dfix.
#include <cstdio>
#include <string>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"
using namespace df3d::mirror;
int main(int argc, char** argv) {
    if (argc != 2) return 2;
    SyntheticFort fort(16, 16, 3);
    const auto granite = fort.material("GRANITE");
    const auto tile = [&](TileFlags flags) {
        const auto bits=uint8_t(flags);
        const auto operation=(bits&uint8_t(TileFlags::EngraveDesignated))?DesignationKind::Engrave:
            (bits&uint8_t(TileFlags::SmoothDesignated))?DesignationKind::Smooth:
            (bits&uint8_t(TileFlags::DigDesignated))?DesignationKind::Dig:DesignationKind::None;
        return TileState(TileShape::Floor, MaterialKind::Stone, granite, 0, LiquidKind::None, flags, operation);
    };
    fort.fillBox(TilePos(0, 0, 0), TilePos(15, 15, 2), tile(TileFlags::NONE));
    fort.setTile(2, 2, 1, tile(TileFlags::DigDesignated));
    fort.setTile(3, 2, 1, tile(TileFlags::SmoothDesignated));
    fort.setTile(4, 2, 1, tile(TileFlags::EngraveDesignated));
    fort.setTile(5, 2, 1, tile(TileFlags::Hidden | TileFlags::DigDesignated));
    fort.setTile(6, 2, 2, tile(TileFlags::SmoothDesignated));
    SyntheticFort::ItemSpec item;
    item.kind = ItemKind::Bar;
    item.material = granite;
    item.x = 2; item.y = 3; item.z = 1;
    item.stack = 5;
    fort.placeItem(9, item);
    item.stack = 1;
    item.flags = ItemFlags::Forbidden;
    fort.placeItem(7, item);
    item.x = 5; item.y = 2; item.z = 1; // item exists but is hidden
    fort.placeItem(11, item);
    item.x = 2; item.y = 3; item.z = 2; // above the selected slice
    fort.placeItem(12, item);
    // Visual pile caps never remove semantic items. Left: quantity
    // pile; middle: hierarchy on installed furniture; right: compressed pile.
    item.flags = ItemFlags::NONE; item.z = 1; item.y = 8; item.x = 5;
    item.stack = 100;
    fort.placeItem(20, item);
    fort.placeItem(21, item);
    fort.placeItem(22, item);
    // Separate same-kind singles must each draw, without sharing a type cap.
    item.x=2; item.stack=1;
    fort.placeItem(23, item);
    fort.placeItem(24, item);
    fort.placeItem(25, item);
    SyntheticFort::BuildingSpec building;
    building.kind = BuildingKind::Table; building.material = granite;
    building.x1=building.x2=8; building.y1=building.y2=8; building.z=1;
    fort.placeBuilding(100, building);
    uint32_t id=30;
    item.x=8; item.stack=1;
    for(auto kind : {ItemKind::Chair,ItemKind::Barrel,ItemKind::Bar,ItemKind::Cloth,ItemKind::Shield,ItemKind::Goblet}) {
        item.kind=kind; fort.placeItem(id++,item);
    }
    item.x=11; item.stack=500;
    for(auto kind : {ItemKind::Chair,ItemKind::Barrel,ItemKind::Bar,ItemKind::Cloth,ItemKind::Shield,ItemKind::Goblet}) {
        item.kind=kind; fort.placeItem(id++,item);
    }
    // Co-positioned units on a real pile, an edge-neighbour and
    // overlapping furniture artwork (the forbidden-door mark is another layer).
    fort.addUnit(101,"CAT",5,8,1);
    fort.addUnit(102,"CAT",5,8,1);
    fort.addUnit(103,"CAT",6,8,1);
    fort.addUnit(104,"CAT",8,8,1);
    fort.addUnit(105,"CAT",5,8,1);
    fort.addUnit(106,"CAT",5,8,1); // departed in latest frame
    fort.addUnit(107,"CAT",5,8,1); // above slice in latest frame
    fort.addUnit(108,"CAT",5,8,0); // below a one-floor window
    building.kind=BuildingKind::Door;building.flags=BuildingFlags::Forbidden;
    building.x1=building.x2=8;building.y1=building.y2=11;
    fort.placeBuilding(101,building);
    building.flags=BuildingFlags::NONE;building.x1=building.x2=9;
    fort.placeBuilding(102,building);
    building.kind=BuildingKind::Table;building.x1=building.x2=2;
    fort.placeBuilding(103,building);
    building.x1=building.x2=3;
    fort.placeBuilding(104,building);
    building.kind=BuildingKind::Chair;building.x1=building.x2=2;
    building.stage=BuildingStage::Planned;
    fort.placeBuilding(105,building);
    building.kind=BuildingKind::Hatch;building.stage=BuildingStage::Complete;
    building.x1=building.x2=12;
    fort.placeBuilding(106,building);
    fort.snapshot(10);
    // Move through the quantity pile and its neighbouring unit. Display stack
    // heights must never become interpolated creature movement/support.
    fort.moveUnit(101,6,8,1);
    fort.snapshot(11);
    fort.moveUnit(101,7,8,1);
    fort.addUnit(109,"CAT",8,8,1); // latest arrival precedes animation visibility
    fort.removeUnit(106);
    fort.moveUnit(107,5,8,2);
    fort.snapshot(12);
    const auto bytes = fort.serialize();
    FixtureStream stream;
    std::string error;
    if (!parseFixture(bytes, stream, error)) return 1;
    if (auto invalid = validateStream(stream)) {
        std::fprintf(stderr, "%s\n", invalid->c_str());
        return 1;
    }
    if (!writeFixtureFile(argv[1], bytes, error)) return 1;
    std::printf("wrote interaction fixture: %zu bytes\n", bytes.size());
}
