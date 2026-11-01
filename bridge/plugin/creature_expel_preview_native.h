#pragma once
#include "creature_expel_native.h"
#include "location_staff_order_native.h"
#include "zone_native.h"

namespace df3d_creature {
struct ExpelUnitRow {int32_t id=-1;std::string name;df3d_area::ZoneOwnerNameColor color;};
struct ExpelDestinationRow {int32_t id=-1;std::string name;};
struct ExpelPreview {
    int32_t unitId=-1,reason=-1;bool eligible=false;
    std::vector<ExpelUnitRow> units;
    std::vector<ExpelDestinationRow> destinations;
};
// Owned CP437 text; fitting, fixed captions and navigation belong to the viewer.
// Native15ed73..15edae uses the existing owner color flags and name(false).
// Native15e046..15e05f formats the site's language_name in English(true,false).
inline std::optional<ExpelPreview> expelPreview(df::unit* unit) {
    const auto eligible=expelEligible(unit);if(!eligible)return std::nullopt;
    ExpelPreview result;result.unitId=unit?unit->id:-1;result.eligible=*eligible;
    if(!*eligible)return result;
    const auto group=expelGroup(unit);if(!group)return std::nullopt;
    result.reason=group->reason;
    const auto& text=df3d_area::staffOrderingFunctions();if(!text)return std::nullopt;
    if(group->units.size()>4096)return std::nullopt;
    for(auto id:group->units) {
        auto* member=df::unit::find(id);if(!member)return std::nullopt;
        const auto color=df3d_area::nativeZoneOwnerNameColor(*member);if(!color)return std::nullopt;
        ExpelUnitRow row;row.id=id;row.color=*color;text.name(member,&row.name,false);
        if(row.name.size()>512)return std::nullopt;
        result.units.push_back(std::move(row));
    }
    if(group->reason!=-1)return result;
    const auto destinations=expelDestinations();if(!destinations)return std::nullopt;
    if(destinations->size()>4096)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[&] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x7c2;++i){hash^=base[0xa946e0+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xdbc3db5f052419ee);
    }();
    if(!supported)return std::nullopt;
    for(auto id:*destinations) {
        ExpelDestinationRow row;row.id=id;
        if(id!=-1) {
            auto* site=df::world_site::find(id);if(!site)return std::nullopt;
            reinterpret_cast<void (*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&site->name,&row.name,true,false);
            if(row.name.size()>512)return std::nullopt;
        }
        result.destinations.push_back(std::move(row));
    }
    return result;
}
}
