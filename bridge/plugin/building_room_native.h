#pragma once
#include "zone_native.h"
#include "cage_body.h"
#include <cstring>
#include "df/building.h"
#include "df/building_civzonest.h"
#include "df/world_site.h"
#include "df/abstract_building.h"
#include "df/abstract_building_contents.h"
#include <windows.h>
#include <optional>
#include <vector>

namespace df3d_production {
inline bool buildingRoomLocationReady() {
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto pin=[base](size_t at,size_t count,uint64_t expected) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){h^=base[at+i];h*=UINT64_C(1099511628211);}
            return h==expected;
        };
        return pin(0x67e80,0x10,UINT64_C(0x7580a2b541177a3a)) &&
            pin(0x18f0fb,0x67,UINT64_C(0x15de853aa66bfcfe)) &&
            pin(0x18f418,0x34b,UINT64_C(0x1dc7ba3fbd571f38));
    }();return ready;
}
// Shared native predicate, used by cage, chain and coffin renderers. No widget
// storage or renderer execution: only live semantic building relations.
inline std::optional<std::vector<df::building_civzonest*>> relevantBuildingRooms(const df::building& building) {
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x47;++i){hash^=base[0x54bb10+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x94acd2997276546c);
    }();
    if(!ready || building.relations.size()>10000)return {};
    using Relevant=bool(*)(int32_t);
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    std::vector<df::building_civzonest*> result;
    for(auto* zone:building.relations) {
        if(!zone)return {};
        if(reinterpret_cast<Relevant>(base+0x54bb10)(int32_t(zone->type)))result.push_back(zone);
    }
    return result;
}
inline std::optional<BuildingRoomBody> cageRoomBody(df::building& building) {
    if(building.getType()!=df::building_type::Cage)return {};
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base] {
        // Cage renderer's owned relation filter. Calling it would borrow UI;
        // the pinned native predicate above is the independent callable.
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0xc7;++i){hash^=base[0x18edc1+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xd001b21a77934a33) &&
            std::strcmp(reinterpret_cast<const char*>(base+0x1601800),"This furniture is a part of")==0 &&
            std::strcmp(reinterpret_cast<const char*>(base+0x1601820),"This furniture is a part of multiple rooms.")==0 &&
            std::strcmp(reinterpret_cast<const char*>(base+0x1601890),"You must designate a dungeon")==0 &&
            std::strcmp(reinterpret_cast<const char*>(base+0x1601870),"before this restraint will")==0 &&
            std::strcmp(reinterpret_cast<const char*>(base+0x1601850),"be used for imprisonment.")==0;
    }();
    if(!ready || !buildingRoomLocationReady())return {};
    const auto rooms=relevantBuildingRooms(building);if(!rooms)return {};
    BuildingRoomBody result;result.buildingId=building.id;
    for(const auto* room:*rooms)result.relevantZones.push_back(room->id);
    if(rooms->empty()) {
        for(const size_t rva:{0x1601890,0x1601870,0x1601850})result.notices.emplace_back(reinterpret_cast<const char*>(base+rva));
    } else if(rooms->size()>1)result.notices.emplace_back(reinterpret_cast<const char*>(base+0x1601820));
    else {
        const auto& room=*rooms->front();const auto name=df3d_area::nativeZoneName(room);
        if(!name || name->size()>1536)return {};
        result.roomId=room.id;result.roomType=int32_t(room.type);result.name=*name;
        result.siteId=room.site_id;result.locationId=room.location_id;
        if(room.location_id!=-1)if(auto* site=df::world_site::find(room.site_id)) {
            using Find=df::abstract_building* (*)(df::world_site*,int32_t);
            if(auto* location=reinterpret_cast<Find>(base+0x67e80)(site,room.location_id)) {
                result.locationType=int32_t(location->getType());
                if(auto* contents=location->getContents()) {
                    result.locationHasContents=true;result.locationTier=contents->location_tier;
                }
            }
        }
        result.introduction=reinterpret_cast<const char*>(base+0x1601800);
    }
    return result;
}
}
