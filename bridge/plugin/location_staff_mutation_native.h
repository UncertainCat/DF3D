#pragma once
#include "location_staff_order_native.h"
namespace df3d_area {
// Unit/world semantics only. These are not viewscreen/widget callbacks.
struct StaffMutationFunctions {
  using Profession=void (*)(df::unit*,bool);
  using Labors=void (*)(df::unit*);
  Profession profession=nullptr;
  Labors labors=nullptr;
  explicit operator bool() const {return profession && labors;}
};
inline const StaffMutationFunctions& staffMutationFunctions() {
  static const auto functions=[]()->StaffMutationFunctions {
    // Reuse the pinned PE identity/readers gate, then verify both full mutation
    // routines and profession tables. Neither range has PE base relocations.
    if(!staffOrderingFunctions())return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t length) {
      uint64_t value=UINT64_C(14695981039346656037);
      for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
      return value;
    };
    if(hash(0x133bcf0,0x2636)!=UINT64_C(0xbf332d0f67ce1d24) ||
       hash(0x4390d0,0x457)!=UINT64_C(0x000a02588e270c20))return {};
    return {reinterpret_cast<StaffMutationFunctions::Profession>(base+0x133bcf0),
      reinterpret_cast<StaffMutationFunctions::Labors>(base+0x4390d0)};
  }();
  return functions;
}
}
