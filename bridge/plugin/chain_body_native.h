#pragma once
#include "chain_native.h"
#include "cage_body.h"
#include "building_room_native.h"

namespace df3d_production {
inline bool chainBodyReady() {
    if(!chainCandidatesReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto pin=[base](size_t at,size_t count,uint64_t expected) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){hash^=base[at+i];hash*=UINT64_C(1099511628211);}
            return hash==expected;
        };
        // Renderer bytes establish row order and room/status branches only.
        // Never execute the renderer or read its native selection storage.
        return pin(0x190341,0x1d1a,UINT64_C(0xc1c3f9d2a5e59a42)) &&
            pin(0x1330c30,0x688,UINT64_C(0x0e165ee31decf426)) &&
            std::strcmp(reinterpret_cast<const char*>(base+0x16018e8),"Assigned and chained")==0 &&
            std::strcmp(reinterpret_cast<const char*>(base+0x16014b0),"Assigned")==0 &&
            std::strcmp(reinterpret_cast<const char*>(base+0x1601bf8),"Chained")==0;
    }();return ready;
}
// Chains share the room/justice portion of the restraint body; cage-only
// glass/aquarium facts remain false. Chain flags are edit authority, not UI flags.
inline std::optional<CageBody> chainBody(df::building* building) {
    if(!building || building->getType()!=df::building_type::Chain || !chainBodyReady())return {};
    const auto room=cageRoomBody(*building);if(!room)return {};
    CageBody result;result.justiceRestraint=building->isJusticeRestraint();result.room=*room;
    return result;
}
}
