#pragma once
#include <cstdint>

namespace df3d_area {
// Native lookup requires sorted unique pointers. The semantic contract also
// excludes self-links. Validate before reading, copying or publishing endpoints.
template<class Rows> bool validStockpileLinkVector(const Rows& rows,int32_t ownerId) {
  if(rows.size()>1024)return false;
  int32_t last=-1;
  for(const auto* row:rows) {
    if(!row || row->id<=last || row->id==ownerId)return false;
    last=row->id;
  }
  return true;
}
}
