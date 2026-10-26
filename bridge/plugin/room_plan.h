#pragma once
#include "room_discovery.h"

namespace df3d_area {
enum class RoomFurniture : uint8_t { None, Bed, Chair, Table, Coffin };
struct RoomSeed {
  int32_t id=-1,x=0,y=0,z=0;
  RoomFurniture furniture=RoomFurniture::None;
  bool valid=false,inUse=false;
};
struct PlannedRoom {
  int32_t seedId=-1;
  bool dormitory=false;
  RoomFootprint footprint;
};
enum class RoomPlanStatus : uint8_t { Complete, Incomplete, Invalid };
struct RoomPlan {
  RoomPlanStatus status=RoomPlanStatus::Invalid;
  uint32_t rejectedInUse=0,rejectedUnenclosed=0;
  std::vector<PlannedRoom> rooms;
};
} // namespace df3d_area
