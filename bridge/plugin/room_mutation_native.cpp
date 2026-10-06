#include "room_mutation_native.h"
#include "modules/Buildings.h"
#include "df/building.h"
#include "df/building_civzonest.h"
#include "df/building_squad_infost.h"
#include "df/building_type.h"
#include "df/world.h"
#include <climits>
#include <memory>

namespace df3d_area {
namespace {
struct UnpublishedZoneDeleter {
  void operator()(df::building* building) const {
    if(!building)return;
    delete[] building->room.extents;
    building->room.extents=nullptr;
    delete building;
  }
};
using UnpublishedZone=std::unique_ptr<df::building,UnpublishedZoneDeleter>;
df::civzone_type zoneType(RoomFurniture furniture,bool dormitory) {
  switch(furniture) {
    case RoomFurniture::Bed:return dormitory?df::civzone_type::Dormitory:df::civzone_type::Bedroom;
    case RoomFurniture::Chair:return df::civzone_type::Office;
    case RoomFurniture::Table:return df::civzone_type::DiningHall;
    case RoomFurniture::Coffin:return df::civzone_type::Tomb;
    default:return df::civzone_type::NONE;
  }
}
bool exactFootprint(const df::building* building,const RoomFootprint& footprint) {
  const auto& bounds=footprint.bounds;
  if(!building || building->x1!=bounds.x || building->y1!=bounds.y || building->z!=footprint.z ||
     building->x2!=bounds.x+bounds.width-1 || building->y2!=bounds.y+bounds.height-1 ||
     building->room.x!=bounds.x || building->room.y!=bounds.y ||
     building->room.width!=bounds.width || building->room.height!=bounds.height ||
     !building->room.extents)return false;
  for(size_t i=0;i<footprint.extents.size();++i)
    if((building->room.extents[i]!=df::building_extents_type::None)!=(footprint.extents[i]!=0))return false;
  return true;
}
}
uint64_t observeNativeRoomRevision(int32_t id) {
  auto* base=id>=0?df::building::find(id):nullptr;
  if(!base || base->getType()!=df::building_type::Civzone || base->flags.bits.almost_deleted)return 0;
  auto* zone=static_cast<df::building_civzonest*>(base);
  switch(zone->type) {
    case df::civzone_type::Bedroom:case df::civzone_type::Dormitory:
    case df::civzone_type::Office:case df::civzone_type::DiningHall:case df::civzone_type::Tomb:break;
    default:return 0;
  }
  const int64_t width=int64_t(zone->x2)-zone->x1+1,height=int64_t(zone->y2)-zone->y1+1;
  if(zone->x1<0 || zone->y1<0 || zone->z<0 || zone->x2>32767 || zone->y2>32767 || zone->z>32767 ||
     width<1 || height<1 || width>kMaxSide || height>kMaxSide || width*height>kMaxCells ||
     !zone->room.extents || zone->room.x!=zone->x1 || zone->room.y!=zone->y1 ||
     zone->room.width!=width || zone->room.height!=height)return 0;
  Revision hash;
  hash.add(zone->id);hash.add(zone->type);hash.add(zone->spec_sub_flag.bits.active);
  hash.add(zone->x1);hash.add(zone->x2);hash.add(zone->y1);hash.add(zone->y2);hash.add(zone->z);
  hash.add(zone->site_id);hash.add(zone->location_id);hash.add(zone->race);hash.add(zone->assigned_unit_id);
  hash.add(zone->name.size());for(unsigned char value:zone->name)hash.add(value);
  for(size_t i=0;i<size_t(width*height);++i)hash.add(zone->room.extents[i]);
  if(zone->type==df::civzone_type::Tomb) {
    hash.add(zone->zone_settings.tomb.flags.bits.no_pets);
    hash.add(zone->zone_settings.tomb.flags.bits.no_citizens);
  }
  hash.add(zone->assigned_units.size());for(auto value:zone->assigned_units)hash.add(value);
  hash.add(zone->assigned_items.size());for(auto value:zone->assigned_items)hash.add(value);
  hash.add(zone->contained_buildings.size());for(const auto* value:zone->contained_buildings) {
    if(!value)return 0;hash.add(value->id);
  }
  hash.add(zone->squad_room_info.size());for(const auto* value:zone->squad_room_info) {
    if(!value)return 0;hash.add(value->squad_id);hash.add(value->mode.whole);
  }
  return hash.finish();
}
RoomUndoResult undoNativeRooms(RoomUndoReceipt& receipt,RoomUndoScope scope,uint64_t token,RoomEffectObserver effects) {
  return receipt.undo(scope,token,[&](int32_t id) {
    const auto revision=observeNativeRoomRevision(id);
    if(revision && effects) {
      const auto* zone=df::building::find(id);
      effects({zone->x1,zone->y1,zone->x2-zone->x1+1,zone->y2-zone->y1+1},zone->z);
    }
    return revision;
  },[](int32_t id) {
    auto* zone=df::building::find(id);
    return zone && zone->getType()==df::building_type::Civzone && DFHack::Buildings::deconstruct(zone);
  });
}
NativeRoomCreation createNativeRooms(RoomFurniture kind,const Bounds& selection,int32_t z,RoomEffectObserver effects) {
  NativeRoomCreation out;
  std::vector<UnpublishedZone> prepared;
  std::vector<df::building*> existingCollisions;
  try {
    out.plan=observeNativeRoomPlan(kind,selection,z);
    if(out.plan.status!=RoomPlanStatus::Complete || !df::global::world ||
       !df::global::plotinfo || !df::global::building_next_id) {
      out.error=RoomCreationError::InvalidPlan;return out;
    }
    const auto count=out.plan.rooms.size();
    if(!count){out.status=RoomCreationStatus::Committed;return out;}
    int32_t maxZone=0;
    for(const auto* zone:df::global::world->buildings.other.ANY_ZONE) {
      if(!zone){out.error=RoomCreationError::Preparation;return out;}
      maxZone=std::max(maxZone,zone->zone_num);
    }
    if(*df::global::building_next_id<0 || count>size_t(INT32_MAX-*df::global::building_next_id) ||
       count>size_t(INT32_MAX-maxZone)) {
      out.error=RoomCreationError::IdsExhausted;return out;
    }
    const auto collisions=observeNativeRoomCollisions(out.plan);
    if(!collisions.valid){out.error=RoomCreationError::Preparation;return out;}
    existingCollisions.reserve(collisions.existingZones.size());
    for(auto id:collisions.existingZones) {
      auto* zone=df::building::find(id);
      if(!zone || zone->getType()!=df::building_type::Civzone){out.error=RoomCreationError::Preparation;return out;}
      existingCollisions.push_back(zone);
    }
    prepared.reserve(count);out.createdIds.reserve(count);out.undoTargets.reserve(count);
    for(size_t index=0;index<count;++index) {
      const auto& room=out.plan.rooms[index];
      const auto& f=room.footprint;const auto& bounds=f.bounds;
      const auto type=zoneType(kind,room.dormitory);
      UnpublishedZone owned(DFHack::Buildings::allocInstance(df::coord(bounds.x,bounds.y,f.z),
        df::building_type::Civzone,type));
      if(!owned || owned->getType()!=df::building_type::Civzone) {
        out.error=RoomCreationError::Preparation;return out;
      }
      auto* zone=static_cast<df::building_civzonest*>(owned.get());
      NativeExtents<df::building_extents_type> extents;
      extents.resize(f.extents.size(),0);
      for(size_t i=0;i<f.extents.size();++i)extents[i]=static_cast<df::building_extents_type>(f.extents[i]);
      zone->room.x=bounds.x;zone->room.y=bounds.y;
      zone->room.width=bounds.width;zone->room.height=bounds.height;
      zone->room.extents=extents.release();
      zone->type=type;zone->spec_sub_flag.bits.active=true;
      zone->flags.bits.room_collision=collisions.rooms[index]!=0;
      if(type==df::civzone_type::Tomb)zone->zone_settings.tomb.flags.bits.no_pets=true;
      if(!DFHack::Buildings::setSize(zone,df::coord2d(bounds.width,bounds.height)) || !exactFootprint(zone,f)) {
        out.error=RoomCreationError::Preparation;return out;
      }
      prepared.push_back(std::move(owned));
    }
    if(effects)for(const auto& room:out.plan.rooms)effects(room.footprint.bounds,room.footprint.z);
  } catch(...) {
    out.error=RoomCreationError::Preparation;return out;
  }
  out.status=publishRooms(prepared,out.createdIds,
    [&](df::building* zone,size_t index) {
      return DFHack::Buildings::constructAbstract(zone) &&
        exactFootprint(zone,out.plan.rooms[index].footprint);
    },
    [](const df::building* zone) noexcept {return zone->id;},
    [](int32_t id){return df::building::find(id);},
    [](df::building* zone){return DFHack::Buildings::deconstruct(zone);});
  if(out.status!=RoomCreationStatus::Committed) {
    out.error=out.status==RoomCreationStatus::NotStarted?RoomCreationError::Preparation:RoomCreationError::Publication;
    return out;
  }
  // Native creation marks both sides; native Undo does not clear old flags.
  // Apply existing-zone flags only after the whole new set publishes, so failed
  // preparation/rolled-back publication cannot alter preexisting flags.
  for(auto* zone:existingCollisions)zone->flags.bits.room_collision=true;
  for(auto id:out.createdIds) {
    const auto revision=observeNativeRoomRevision(id);
    if(!revision) {
      out.undoTargets.clear();out.status=RoomCreationStatus::Unknown;
      out.error=RoomCreationError::Observation;return out;
    }
    out.undoTargets.push_back({id,revision});
  }
  out.status=RoomCreationStatus::Committed;
  return out;
}
}
