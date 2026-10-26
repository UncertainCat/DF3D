#include "room_discovery_native.h"
#include "room_multiseed.h"
#include "zone_native.h"
#include "modules/Maps.h"
#include "df/building_doorst.h"
#include "df/building.h"
#include "df/building_civzonest.h"
#include "df/building_type.h"
#include "df/map_block.h"
#include "df/world.h"

namespace df3d_area {
namespace {
bool roomUseType(df::civzone_type type) {
  switch(type) {
    case df::civzone_type::MeetingHall:case df::civzone_type::Bedroom:
    case df::civzone_type::DiningHall:case df::civzone_type::Office:
    case df::civzone_type::Dormitory:case df::civzone_type::Barracks:
    case df::civzone_type::Dungeon:case df::civzone_type::Tomb:return true;
    default:return false;
  }
}
RoomCell observeCell(int32_t x,int32_t y,int32_t z) {
  if(!DFHack::Maps::isValidTilePos(x,y,z))return RoomCell::Unobserved;
  const auto* block=DFHack::Maps::getTileBlock(x,y,z);
  if(!block)return RoomCell::Unobserved;
  // Native Multi ignores visibility for discovery without revealing tiles.
  if(!nativeZoneTileEligible(int16_t(x),int16_t(y),int16_t(z)))return RoomCell::Boundary;
  // Native355c53..355e23: after the semantic predicate, nonzero occupancy
  // checks the actual door vector for a matching center. Door animation and
  // generic findAtTile heuristics do not decide room expansion.
  if(block->occupancy[x&15][y&15].bits.building!=df::tile_building_occ::None) {
    for(const auto* door:df::global::world->buildings.other.DOOR) {
      if(!door)return RoomCell::Unobserved;
      if(door->centerx==x && door->centery==y && door->z==z)return RoomCell::Boundary;
    }
  }
  return RoomCell::Open;
}
}
NativeRoomSeed observeNativeRoomSeed(int32_t buildingId) {
  NativeRoomSeed out;
  if(buildingId<0)return out;
  auto* building=df::building::find(buildingId);
  if(!building || !DFHack::Maps::isValidTilePos(building->centerx,building->centery,building->z))return out;
  switch(building->getType()) {
    case df::building_type::Bed:out.furniture=RoomFurniture::Bed;break;
    case df::building_type::Chair:out.furniture=RoomFurniture::Chair;break;
    case df::building_type::Table:out.furniture=RoomFurniture::Table;break;
    case df::building_type::Coffin:out.furniture=RoomFurniture::Coffin;break;
    default:return out;
  }
  out.id=building->id;out.x=building->centerx;out.y=building->centery;out.z=building->z;
  // Native Multi evidence: 72 current-zone-type comparisons across four modes.
  // Outdoor/activity zones do not reserve furniture merely by overlapping it.
  // Controlled stage-zero/Planned bed cases are accepted by native Multi too.
  for(const auto* zone:building->relations) {
    if(!zone)return out;
    out.inUse=out.inUse || roomUseType(zone->type);
  }
  out.valid=true;
  return out;
}
NativeRoomObservation observeNativeRoom(int32_t seedX,int32_t seedY,int32_t seedZ) {
  NativeRoomObservation out;
  if(!nativeZoneMultiReady() || !DFHack::Maps::isValidTilePos(seedX,seedY,seedZ))return out;
  // Twenty open steps plus one reached boundary layer, in each direction.
  constexpr uint32_t side=43;
  out.x=seedX-21;out.y=seedY-21;out.z=seedZ;out.width=side;out.height=side;
  out.cells.assign(side*side,RoomCell::Unobserved);
  for(uint32_t y=0;y<side;++y)for(uint32_t x=0;x<side;++x) {
    const int32_t tx=out.x+int32_t(x),ty=out.y+int32_t(y);
    out.cells[size_t(y)*side+x]=observeCell(tx,ty,seedZ);
  }
  // Native3557d3..35591f seeds the furniture before testing any neighbor.
  // A wall/liquid at that center does not suppress the initial expansion.
  out.cells[21*side+21]=RoomCell::Open;
  out.traversal=traverseRoom(out.cells,side,side,21,21);
  return out;
}
RoomPlan observeNativeRoomPlan(RoomFurniture kind,const Bounds& selection,int32_t z) {
  if(!df::global::world || !nativeZoneMultiReady() || !DFHack::Maps::isValidTilePos(selection.x,selection.y,z) ||
     selection.width<=0 || selection.height<=0 ||
     int64_t(selection.x)+selection.width>32768 || int64_t(selection.y)+selection.height>32768 ||
     !DFHack::Maps::isValidTilePos(selection.x+selection.width-1,selection.y+selection.height-1,z))return {};
  std::vector<RoomSeed> seeds;
  for(auto* building:df::global::world->buildings.all) {
    if(!building || building->z!=z)continue;
    auto seed=observeNativeRoomSeed(building->id);
    if(seed.furniture==kind)seeds.push_back(seed);
  }
  return planRoomSet(seeds,kind,selection,z,df::global::world->map.x_count,
    df::global::world->map.y_count,observeCell);
}
}
