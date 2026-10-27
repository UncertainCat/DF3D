#pragma once
#include "location_staff_order_native.h"
#include "df/historical_figure.h"
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
struct ReligiousStaffMutationFunctions {
  using Remove=void (*)(df::historical_figure*,int32_t,int32_t,bool,bool);
  using Military=void (*)(df::unit*);
  using CancelJob=void (*)(df::unit*,bool,int32_t,bool,void*);
  Remove remove=nullptr;Military military=nullptr;CancelJob cancelJob=nullptr;
  explicit operator bool() const {return remove && military && cancelJob;}
};
inline const ReligiousStaffMutationFunctions& religiousStaffMutationFunctions() {
  static const auto functions=[]()->ReligiousStaffMutationFunctions {
    if(!staffOrderingFunctions())return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t length) {
      uint64_t value=UINT64_C(14695981039346656037);
      for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
      return value;
    };
    // Complete pinned bodies, with no PE base relocations. b95d60 owns the
    // position/history effect; the other helpers own military/job retirement.
    if(hash(0xb96300,0xce)!=UINT64_C(0x718bdbff364f1818) ||
       hash(0xb95d60,0x35d)!=UINT64_C(0xc2edfae1a6417dc5) ||
       hash(0x13cbf10,0x173)!=UINT64_C(0x0992efa035b017f8) ||
       hash(0x1325080,0x33c3)!=UINT64_C(0xf84d63b3115de7d1))return {};
    return {reinterpret_cast<ReligiousStaffMutationFunctions::Remove>(base+0xb96300),
      reinterpret_cast<ReligiousStaffMutationFunctions::Military>(base+0x13cbf10),
      reinterpret_cast<ReligiousStaffMutationFunctions::CancelJob>(base+0x1325080)};
  }();
  return functions;
}

}
