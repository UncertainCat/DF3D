#pragma once
#include "room_plan.h"
#include <unordered_map>

namespace df3d_area {
// DF's inline Multi flood uses ordered seeds and twenty alternating frontiers.
// A lower seed label can replace a higher label. Read a parent's current label
// for every neighbor, including changes made earlier in the same frontier.
// All labels, queues and tile observations here are independently owned.
template<class Observe>
RoomPlan planRoomSet(const std::vector<RoomSeed>& seeds,RoomFurniture kind,
                     const Bounds& selection,int32_t z,int32_t mapWidth,int32_t mapHeight,Observe observe) {
  RoomPlan out;
  if(kind<RoomFurniture::Bed || kind>RoomFurniture::Coffin || z<0 || z>32767 ||
     mapWidth<1 || mapHeight<1 || mapWidth>32768 || mapHeight>32768 ||
     selection.x<0 || selection.y<0 || selection.width<1 || selection.height<1 ||
     int64_t(selection.x)+selection.width>mapWidth || int64_t(selection.y)+selection.height>mapHeight)return out;
  out.status=RoomPlanStatus::Complete;
  std::vector<const RoomSeed*> selected;
  for(const auto& seed:seeds) {
    if(seed.furniture!=kind || seed.z!=z || seed.x<selection.x || seed.y<selection.y ||
       int64_t(seed.x)>=int64_t(selection.x)+selection.width || int64_t(seed.y)>=int64_t(selection.y)+selection.height)continue;
    if(!seed.valid || seed.id<0)return {};
    if(seed.inUse){++out.rejectedInUse;continue;}
    selected.push_back(&seed);
  }
  if(selected.empty())return out;
  constexpr size_t frontierCapacity=120000; // native 0x1d4c0 entries
  if(selected.size()>frontierCapacity){out.status=RoomPlanStatus::Incomplete;return out;}
  const auto key=[](int32_t x,int32_t y){return (uint64_t(uint32_t(x))<<32)|uint32_t(y);};
  const auto xOf=[](uint64_t cell){return int32_t(cell>>32);};
  const auto yOf=[](uint64_t cell){return int32_t(uint32_t(cell));};
  std::unordered_map<uint64_t,size_t> owners;
  std::unordered_map<uint64_t,RoomCell> observations;
  bool incomplete=false;
  const auto cellKind=[&](uint64_t cell) {
    auto [it,inserted]=observations.try_emplace(cell,RoomCell::Unobserved);
    if(inserted)it->second=observe(xOf(cell),yOf(cell),z);
    if(it->second==RoomCell::Unobserved)incomplete=true;
    return it->second;
  };
  std::vector<uint64_t> current,next;
  for(size_t i=0;i<selected.size();++i){const auto cell=key(selected[i]->x,selected[i]->y);owners[cell]=i;current.push_back(cell);}
  for(int round=0;round<20 && !current.empty();++round) {
    next.clear();
    for(auto parent:current) {
      if(next.size()>=frontierCapacity)continue;
      const auto px=xOf(parent),py=yOf(parent);
      for(int32_t x=px-1;x<=px+1;++x)for(int32_t y=py-1;y<=py+1;++y) {
        if((x==px && y==py) || x<0 || y<0 || x>=mapWidth || y>=mapHeight)continue;
        const auto cell=key(x,y);const auto owner=owners.at(parent);
        auto it=owners.find(cell);
        if(it!=owners.end() && it->second<=owner)continue;
        owners[cell]=owner;
        if(cellKind(cell)==RoomCell::Open && next.size()<frontierCapacity)next.push_back(cell);
      }
    }
    current.swap(next);
  }
  if(incomplete){out.status=RoomPlanStatus::Incomplete;return out;}
  std::vector<std::vector<uint64_t>> groups(selected.size());
  for(const auto& [cell,owner]:owners)groups[owner].push_back(cell);
  for(size_t i=0;i<groups.size();++i) {
    auto cells=std::move(groups[i]);if(cells.empty())continue;
    bool unenclosed=false;
    const auto initial=cells.size();
    for(size_t c=0;c<initial;++c) {
      const auto cell=cells[c];if(cellKind(cell)!=RoomCell::Open)continue;
      const auto px=xOf(cell),py=yOf(cell);
      if(px==0 || py==0 || px==mapWidth-1 || py==mapHeight-1){unenclosed=true;continue;}
      for(int32_t x=px-1;x<=px+1;++x)for(int32_t y=py-1;y<=py+1;++y) {
        if(x==px && y==py)continue;
        const auto neighbor=key(x,y);const auto found=owners.find(neighbor);
        if(found!=owners.end() && found->second==i)continue;
        if(cellKind(neighbor)==RoomCell::Open)unenclosed=true;
        else cells.push_back(neighbor);
      }
    }
    if(incomplete){out.rooms.clear();out.status=RoomPlanStatus::Incomplete;return out;}
    if(unenclosed){++out.rejectedUnenclosed;continue;}
    int32_t left=mapWidth,top=mapHeight,right=0,bottom=0;
    for(auto cell:cells){left=std::min(left,xOf(cell));right=std::max(right,xOf(cell));top=std::min(top,yOf(cell));bottom=std::max(bottom,yOf(cell));}
    RoomFootprint footprint;footprint.bounds={left,top,right-left+1,bottom-top+1};footprint.z=z;
    if(!validBounds(footprint.bounds)){out.rooms.clear();out.status=RoomPlanStatus::Incomplete;return out;}
    footprint.extents.assign(size_t(footprint.bounds.width)*footprint.bounds.height,0);
    for(auto cell:cells)footprint.extents[size_t(yOf(cell)-top)*footprint.bounds.width+xOf(cell)-left]=1;
    footprint.valid=true;
    size_t beds=0;
    if(kind==RoomFurniture::Bed)for(const auto& seed:seeds)
      if(seed.furniture==kind && footprint.contains(seed.x,seed.y,seed.z))++beds;
    out.rooms.push_back({selected[i]->id,beds>=2,std::move(footprint)});
  }
  return out;
}
}
