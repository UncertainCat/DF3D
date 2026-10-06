#pragma once
#include <cstdint>
#include <cstddef>
#include <vector>

namespace df3d_area {
enum class RoomCreationStatus : uint8_t { NotStarted, Committed, RolledBack, Unknown };

// Owns the publication boundary, shared by native code and injected-failure tests.
// All owners and ID storage must be prepared before entry. Publish may partially
// expose an object or throw, but must not destroy it. Reading its ID must not throw.
// Remove may destroy its input even when returning false or throwing; never read
// that pointer afterward. Find returns a current pointer for a published ID;
// missing/throwing lookups leave the cleanup outcome Unknown.
template<class Owner,class Publish,class Id,class Find,class Remove>
RoomCreationStatus publishRooms(std::vector<Owner>& prepared,std::vector<int32_t>& ids,
                               Publish publish,Id idOf,Find find,Remove remove) {
  static_assert(noexcept(idOf(prepared.front().get())),"Published identity reads must not throw");
  if(!ids.empty() || ids.capacity()<prepared.size())return RoomCreationStatus::NotStarted;
  for(const auto& owner:prepared)if(!owner)return RoomCreationStatus::NotStarted;
  for(size_t i=0;i<prepared.size();++i) {
    auto* current=prepared[i].release();
    bool published=false;
    try {published=publish(current,i);} catch(...) {}
    const int32_t id=idOf(current);
    if(published && id>=0){ids.push_back(id);continue;}
    bool restored=true;
    try {restored=remove(current);} catch(...) {restored=false;}
    for(auto it=ids.rbegin();it!=ids.rend();++it) {
      try {
        auto* previous=find(*it);
        if(!previous || !remove(previous))restored=false;
      } catch(...) {restored=false;}
    }
    if(restored){ids.clear();return RoomCreationStatus::RolledBack;}
    if(id>=0)ids.push_back(id);
    return RoomCreationStatus::Unknown;
  }
  return RoomCreationStatus::Committed;
}
}
