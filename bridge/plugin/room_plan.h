#pragma once
#include "room_discovery.h"

namespace df3d_area {
enum class RoomFurniture : uint8_t { None, Bed, Chair, Table, Coffin };
struct RoomSeed {
  int32_t id=-1,x=0,y=0,z=0;
  RoomFurniture furniture=RoomFurniture::None;
  bool valid=false,inUse=false;
};
struct RoomDiscovery {
  RoomTraversalStatus status=RoomTraversalStatus::Invalid;
  RoomFootprint footprint;
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
enum class RoomCollision : uint8_t { None, Overlap, Unknown };
// Collision needs a shared enabled Open cell, not merely intersecting bounds.
// Boundary cells remain in room extents but do not penalize shared walls/doors.
template<class ContainsOther,class Observe>
RoomCollision roomCollision(const RoomFootprint& room,const Bounds& other,int32_t otherZ,
                            ContainsOther containsOther,Observe observe) {
  if(room.z!=otherZ)return RoomCollision::None;
  if(!room.valid || room.bounds.width<=0 || room.bounds.height<=0 || other.width<=0 || other.height<=0 ||
     room.extents.size()!=size_t(room.bounds.width)*room.bounds.height)return RoomCollision::Unknown;
  const int64_t left=std::max<int64_t>(room.bounds.x,other.x),top=std::max<int64_t>(room.bounds.y,other.y);
  const int64_t right=std::min(int64_t(room.bounds.x)+room.bounds.width,int64_t(other.x)+other.width);
  const int64_t bottom=std::min(int64_t(room.bounds.y)+room.bounds.height,int64_t(other.y)+other.height);
  bool unknown=false;
  for(int64_t y=top;y<bottom;++y)for(int64_t x=left;x<right;++x) {
    if(!room.contains(int32_t(x),int32_t(y),room.z) || !containsOther(int32_t(x),int32_t(y)))continue;
    const auto cell=observe(int32_t(x),int32_t(y),room.z);
    if(cell==RoomCell::Open)return RoomCollision::Overlap;
    unknown=unknown || cell==RoomCell::Unobserved;
  }
  return unknown?RoomCollision::Unknown:RoomCollision::None;
}
// Seeds preserve native building-vector order, including furniture outside the
// selection: native Bedroom discovery counts all beds in the discovered room.
// This prepares semantic geometry only; it neither mutates nor reserves IDs.
template<class Discover>
RoomPlan planRooms(const std::vector<RoomSeed>& seeds,RoomFurniture kind,
                   const Bounds& selection,int32_t z,Discover discover) {
  RoomPlan out;
  if(kind<RoomFurniture::Bed || kind>RoomFurniture::Coffin || z<0 || z>32767 ||
     selection.x<0 || selection.y<0 || selection.width<=0 || selection.height<=0 ||
     int64_t(selection.x)+selection.width>32768 ||
     int64_t(selection.y)+selection.height>32768)return out;
  out.status=RoomPlanStatus::Complete;
  for(const auto& seed:seeds) {
    if(seed.furniture!=kind || seed.z!=z || seed.x<selection.x || seed.y<selection.y ||
       int64_t(seed.x)>=int64_t(selection.x)+selection.width ||
       int64_t(seed.y)>=int64_t(selection.y)+selection.height)continue;
    if(!seed.valid || seed.id<0)return RoomPlan{};
    if(seed.inUse){++out.rejectedInUse;continue;}
    bool grouped=false;
    for(const auto& room:out.rooms)if(room.footprint.contains(seed.x,seed.y,z)) {
      grouped=true;break;
    }
    if(grouped)continue;
    auto discovery=discover(seed);
    if(discovery.status==RoomTraversalStatus::Unenclosed){++out.rejectedUnenclosed;continue;}
    if(discovery.status!=RoomTraversalStatus::Complete) {
      RoomPlan failed;
      failed.status=discovery.status==RoomTraversalStatus::Incomplete?
        RoomPlanStatus::Incomplete:RoomPlanStatus::Invalid;
      return failed;
    }
    if(!discovery.footprint.valid || !discovery.footprint.contains(seed.x,seed.y,z))return RoomPlan{};
    bool dormitory=false;
    if(kind==RoomFurniture::Bed) {
      size_t beds=0;
      for(const auto& other:seeds)if(other.furniture==kind &&
          discovery.footprint.contains(other.x,other.y,other.z)) {
        if(!other.valid || other.id<0)return RoomPlan{};
        ++beds;
      }
      dormitory=beds>1;
    }
    out.rooms.push_back({seed.id,dormitory,std::move(discovery.footprint)});
  }
  return out;
}
} // namespace df3d_area
