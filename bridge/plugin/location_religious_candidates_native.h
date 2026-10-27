#pragma once
#include "location_staff_order_native.h"
#include "df/historical_figure.h"
#include "df/entity_position.h"
#include "df/historical_entity.h"

namespace df3d_area {
// Semantic predicates called by the supported occupation selector. Native
// entity/assignment lookup caches may be refreshed; no picker state is used.
struct ReligiousCandidateFunctions {
  using Unit=bool (*)(df::unit*);
  using Caste=bool (*)(int16_t,int16_t);
  using Excluded=bool (*)(df::unit*,int32_t);
  using Membership=int16_t (*)(df::historical_figure*,int16_t,int32_t);
  using Eligible=bool (*)(df::historical_figure*,df::entity_position*,df::historical_entity*,void*,bool);
  Unit unit=nullptr;Caste caste=nullptr;Excluded excluded=nullptr;
  Membership membership=nullptr;Eligible eligible=nullptr;
  const uint8_t* profession=nullptr;
  explicit operator bool() const {return unit && caste && excluded && membership && eligible && profession;}
};
inline const ReligiousCandidateFunctions& religiousCandidateFunctions() {
  static const auto functions=[]()->ReligiousCandidateFunctions {
    if(!staffOrderingFunctions())return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t length) {
      uint64_t value=UINT64_C(14695981039346656037);
      for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
      return value;
    };
    // The shared gate covers full unit/caste predicates. Pin the religious
    // predicates, lookup-cache writers and immutable profession switch table.
    if(hash(0x13b99b0,0x24d)!=UINT64_C(0x1ea3e3ea386f418b) ||
       hash(0xb96d80,0x53e)!=UINT64_C(0x5249c96a7883418a) ||
       hash(0xb973c0,0x79)!=UINT64_C(0xe30c0166fa2e4d2a) ||
       hash(0xb972c0,0xf8)!=UINT64_C(0x462a923de0759a7a) ||
       hash(0xbbef0,0x9a)!=UINT64_C(0xb674b3f5153bea03) ||
       hash(0xbbd90,0xa8)!=UINT64_C(0xe0b2ddde58f5e3fc) ||
       hash(0xbbe40,0xad)!=UINT64_C(0x062a266340f9bf38) ||
       hash(0xb530b0,0xac)!=UINT64_C(0x7c6f66602bdab157) ||
       hash(0x93ce30,0xb7)!=UINT64_C(0xd664ff2de27cabfb) ||
       hash(0x3a405c,0x87)!=UINT64_C(0xc754a376f70f6c70))return {};
    return {reinterpret_cast<ReligiousCandidateFunctions::Unit>(base+0x138ed20),
      reinterpret_cast<ReligiousCandidateFunctions::Caste>(base+0x1376500),
      reinterpret_cast<ReligiousCandidateFunctions::Excluded>(base+0x13b99b0),
      reinterpret_cast<ReligiousCandidateFunctions::Membership>(base+0xb973c0),
      reinterpret_cast<ReligiousCandidateFunctions::Eligible>(base+0xb96d80),base+0x3a405c};
  }();
  return functions;
}
}
