#pragma once
#include <cstdint>
#include <cstddef>
#include <vector>

namespace df3d_area {
enum class RoomCreationStatus : uint8_t { NotStarted, Committed, Unknown };

// Native factories publish immediately, before returning. Prepared storage and
// ID capacity must exist before entry. No returned pointer is locally owned.
// An allocation can throw after partial native publication; every failure after
// entry is Unknown, never automatic deletion or permission to replay. Retain
// all known IDs as observation hints, not Undo authority. Completion must not
// retire its supplied object. ID reads must not throw.
template<class Allocate,class Complete,class Id,class Finish>
RoomCreationStatus publishRooms(size_t count,std::vector<int32_t>& ids,
                               Allocate allocate,Complete complete,Id idOf,Finish finish) {
  if(!ids.empty() || ids.capacity()<count)return RoomCreationStatus::NotStarted;
  if(!count)return RoomCreationStatus::Committed;
  try {
    for(size_t i=0;i<count;++i) {
      auto* current=allocate();
      static_assert(noexcept(idOf(current)),"Published identity reads must not throw");
      if(!current)return RoomCreationStatus::Unknown;
      const int32_t id=idOf(current);
      if(id<0)return RoomCreationStatus::Unknown;
      ids.push_back(id); // capacity was reserved before the first native call
      if(!complete(current,i))return RoomCreationStatus::Unknown;
    }
    if(!finish())return RoomCreationStatus::Unknown;
  } catch(...) {return RoomCreationStatus::Unknown;}
  return RoomCreationStatus::Committed;
}
}
