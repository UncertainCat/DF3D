#include "room_discovery_native.h"
#include "TileTypes.h"
#include "modules/Maps.h"
#include "modules/Buildings.h"
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
RoomShape roomShape(df::tiletype_shape shape) {
  using namespace df::enums::tiletype_shape;
  switch(shape) {
    case NONE:return RoomShape::None;
    case EMPTY:return RoomShape::Empty;
    case FLOOR:return RoomShape::Floor;
    case BOULDER:return RoomShape::Boulder;
    case PEBBLES:return RoomShape::Pebbles;
    case WALL:return RoomShape::Wall;
    case FORTIFICATION:return RoomShape::Fortification;
    case STAIR_UP:return RoomShape::StairUp;
    case STAIR_DOWN:return RoomShape::StairDown;
    case STAIR_UPDOWN:return RoomShape::StairUpDown;
    case RAMP:return RoomShape::Ramp;
    case RAMP_TOP:return RoomShape::RampTop;
    case BROOK_BED:return RoomShape::BrookBed;
    case BROOK_TOP:return RoomShape::BrookTop;
    case BRANCH:return RoomShape::Branch;
    case TRUNK_BRANCH:return RoomShape::TrunkBranch;
    case TWIG:return RoomShape::Twig;
    case SAPLING:return RoomShape::Sapling;
    case SHRUB:return RoomShape::Shrub;
    case ENDLESS_PIT:return RoomShape::EndlessPit;
    default:return RoomShape::Unknown;
  }
}
RoomOccupancy roomOccupancy(df::tile_building_occ occupancy) {
  using namespace df::enums::tile_building_occ;
  switch(occupancy) {
    case None:return RoomOccupancy::None;
    case Planned:return RoomOccupancy::Planned;
    case Passable:return RoomOccupancy::Passable;
    case Obstacle:return RoomOccupancy::Obstacle;
    case Well:return RoomOccupancy::Well;
    case Floored:return RoomOccupancy::Floored;
    case Impassable:return RoomOccupancy::Impassable;
    case Dynamic:return RoomOccupancy::Dynamic;
    default:return static_cast<RoomOccupancy>(255);
  }
}
RoomCell observeCell(int32_t x,int32_t y,int32_t z) {
  if(!DFHack::Maps::isValidTilePos(x,y,z))return RoomCell::Unobserved;
  const auto* block=DFHack::Maps::getTileBlock(x,y,z);
  if(!block)return RoomCell::Unobserved;
  const auto designation=block->designation[x&15][y&15];
  if(designation.bits.hidden)return RoomCell::Unobserved;
  const auto occupancy=block->occupancy[x&15][y&15].bits.building;
  auto* building=DFHack::Buildings::findAtTile(df::coord(x,y,z));
  const bool door=building && building->getType()==df::building_type::Door;
  if(occupancy==df::tile_building_occ::Dynamic && building && !door)return RoomCell::Unobserved;
  const auto depth=uint8_t(designation.bits.flow_size);
  const auto liquid=!depth?RoomLiquid::None:
    (designation.bits.liquid_type==df::tile_liquid::Magma?RoomLiquid::Magma:RoomLiquid::Water);
  return classifyRoomCell(roomShape(DFHack::tileShape(block->tiletype[x&15][y&15])),
    roomOccupancy(occupancy),liquid,depth,door);
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
  if(!DFHack::Maps::isValidTilePos(seedX,seedY,seedZ))return out;
  // Twenty open steps plus one reached boundary layer, in each direction.
  constexpr uint32_t side=43;
  out.x=seedX-21;out.y=seedY-21;out.z=seedZ;out.width=side;out.height=side;
  out.cells.assign(side*side,RoomCell::Unobserved);
  for(uint32_t y=0;y<side;++y)for(uint32_t x=0;x<side;++x) {
    const int32_t tx=out.x+int32_t(x),ty=out.y+int32_t(y);
    out.cells[size_t(y)*side+x]=observeCell(tx,ty,seedZ);
  }
  out.traversal=traverseRoom(out.cells,side,side,21,21);
  return out;
}
RoomPlan observeNativeRoomPlan(RoomFurniture kind,const Bounds& selection,int32_t z) {
  if(!df::global::world || !DFHack::Maps::isValidTilePos(selection.x,selection.y,z) ||
     selection.width<=0 || selection.height<=0 ||
     int64_t(selection.x)+selection.width>32768 || int64_t(selection.y)+selection.height>32768 ||
     !DFHack::Maps::isValidTilePos(selection.x+selection.width-1,selection.y+selection.height-1,z))return {};
  std::vector<RoomSeed> seeds;
  for(auto* building:df::global::world->buildings.all) {
    if(!building || building->z!=z)continue;
    auto seed=observeNativeRoomSeed(building->id);
    if(seed.furniture==kind)seeds.push_back(seed);
  }
  return planRooms(seeds,kind,selection,z,[](const RoomSeed& seed) {
    const auto observed=observeNativeRoom(seed.x,seed.y,seed.z);
    return RoomDiscovery{observed.traversal.status,
      compactRoom(observed.x,observed.y,observed.z,observed.width,observed.height,observed.traversal)};
  });
}
NativeRoomCollisions observeNativeRoomCollisions(const RoomPlan& plan) {
  NativeRoomCollisions out;
  if(plan.status!=RoomPlanStatus::Complete || !df::global::world)return out;
  out.rooms.assign(plan.rooms.size(),0);
  for(auto* zone:df::global::world->buildings.other.ANY_ZONE) {
    if(!zone)return out;
    if(!roomUseType(zone->type))continue;
    bool affected=false;
    const Bounds bounds{zone->x1,zone->y1,zone->x2-zone->x1+1,zone->y2-zone->y1+1};
    for(size_t i=0;i<plan.rooms.size();++i) {
      const auto collision=roomCollision(plan.rooms[i].footprint,bounds,zone->z,
        [&](int32_t x,int32_t y){return DFHack::Buildings::containsTile(zone,df::coord2d(x,y));},observeCell);
      if(collision==RoomCollision::Unknown)return out;
      if(collision==RoomCollision::Overlap){out.rooms[i]=1;affected=true;}
    }
    if(affected)out.existingZones.push_back(zone->id);
  }
  for(size_t i=0;i<plan.rooms.size();++i)for(size_t j=0;j<i;++j) {
    const auto& other=plan.rooms[j].footprint;
    const auto collision=roomCollision(plan.rooms[i].footprint,other.bounds,other.z,
      [&](int32_t x,int32_t y){return other.contains(x,y,other.z);},observeCell);
    if(collision==RoomCollision::Unknown)return out;
    if(collision==RoomCollision::Overlap)out.rooms[i]=out.rooms[j]=1;
  }
  out.valid=true;return out;
}
}
