#pragma once
#include "room_plan.h"
#include <cstdint>
#include <vector>

namespace df3d_area {
using NativeRoomSeed=RoomSeed;
// Reads furniture identity and native room-use relations, without construction-
// stage filtering. Caller holds the safe point; no native UI or mutation.
NativeRoomSeed observeNativeRoomSeed(int32_t buildingId);
struct NativeRoomObservation {
  int32_t x=0,y=0,z=0;
  uint32_t width=0,height=0;
  std::vector<RoomCell> cells;
  RoomTraversal traversal;
};
// Caller must hold the DFHack safe point. No native mutations or UI dependencies.
NativeRoomObservation observeNativeRoom(int32_t seedX,int32_t seedY,int32_t seedZ);
// Read-only selection plan. Caller holds one safe point for the entire snapshot.
RoomPlan observeNativeRoomPlan(RoomFurniture kind,const Bounds& selection,int32_t z);
struct NativeRoomCollisions {
  bool valid=false;
  std::vector<uint8_t> rooms;
  std::vector<int32_t> existingZones;
};
// Same safe point as planning/preparation. No collision flags are written here.
NativeRoomCollisions observeNativeRoomCollisions(const RoomPlan& plan);
}
