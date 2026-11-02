#pragma once
#include "farm_native.h"
#include "df/historical_entity.h"
#include "df/manager_order.h"
#include "df/plotinfost.h"
#include "df/workshop_profile.h"

namespace df3d_production {
// These offsets identify semantic records used by the supported native sheet.
// No viewscreen, retained menu list, or numeric-entry buffer is consulted.
static_assert(offsetof(df::plotinfost,main)+offsetof(df::plotinfost::T_main,fortress_entity)==0x8fb8);
static_assert(offsetof(df::historical_entity,assignments_by_type)==0x1798);
static_assert(int(df::entity_position_responsibility::MANAGE_PRODUCTION)==4);
static_assert(offsetof(df::workshop_profile,max_general_orders)==0x80);
static_assert(offsetof(df::manager_order,workshop_id)==0x64);

inline bool workshopOrdersSupported() {
    static const bool supported=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1882a2,0x25,UINT64_C(0x9393a64364b20dc7)}, // manager assignment list
            {0x1aca10,0x32,UINT64_C(0x902eac70d5324069)}, // workshop order membership
            {0x1acb79,0x21,UINT64_C(0x2c2ba9cf7b6977b7)}, // increment, capped at99
            {0x1acbc7,0x14,UINT64_C(0xf50c0075ec5c3a97)}, // decrement, floored at0
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    return supported;
}

struct WorkshopOrdersProfile {
    int32_t buildingId=-1;
    uint64_t revision=0;
    bool managerAvailable=false;
    int32_t generalOrderLimit=0;
    std::vector<int32_t> orderIds;
};

// Safe-point only. Returned data is owned; order IDs retain native world order.
inline std::optional<WorkshopOrdersProfile> workshopOrdersProfile(df::building* building) {
    if(!workshopOrdersSupported() || !building || !df::global::world || !df::global::plotinfo ||
       (building->getType()!=df::building_type::Workshop && building->getType()!=df::building_type::Furnace))return std::nullopt;
    auto* profile=building->getWorkshopProfile();
    const auto header=observeBuildingHeader(building);
    if(!profile || !header || header->removing || header->stage!=header->maxStage)return std::nullopt;
    const auto* entity=df::global::plotinfo->main.fortress_entity;
    if(!entity)return std::nullopt;
    WorkshopOrdersProfile result;result.buildingId=building->id;
    result.managerAvailable=!entity->assignments_by_type[df::entity_position_responsibility::MANAGE_PRODUCTION].empty();
    result.generalOrderLimit=profile->max_general_orders;
    for(const auto* order:df::global::world->manager_orders.all)
        if(order && order->workshop_id==building->id) {
            if(order->id<0 || result.orderIds.size()>=16384)return std::nullopt;
            result.orderIds.push_back(order->id);
        }
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value) {
        for(unsigned shift=0;shift<64;shift+=8){hash^=(value>>shift)&255;hash*=UINT64_C(1099511628211);}
    };
    add(header->revision);add(building->getSubtype());add(building->getCustomType());
    add(result.managerAvailable);add(uint32_t(result.generalOrderLimit));add(result.orderIds.size());
    for(const auto id:result.orderIds)add(uint32_t(id));
    result.revision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    return result;
}

enum class WorkshopOrdersOutcome { Rejected, Stale, Applied, Unavailable, Unknown };
struct WorkshopOrdersResult {
    WorkshopOrdersOutcome outcome=WorkshopOrdersOutcome::Rejected;
    std::optional<WorkshopOrdersProfile> profile;
};
inline WorkshopOrdersResult stepWorkshopGeneralOrders(int32_t buildingId,uint64_t revision,int32_t delta) {
    WorkshopOrdersResult result;
    if(!workshopOrdersSupported()){result.outcome=WorkshopOrdersOutcome::Unavailable;return result;}
    if(delta!=-1 && delta!=1)return result;
    auto* building=df::building::find(buildingId);
    const auto before=workshopOrdersProfile(building);if(!before)return result;
    if(!revision || revision!=before->revision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    if(before->generalOrderLimit<0 || before->generalOrderLimit>99)return result;
    const int32_t desired=std::clamp(before->generalOrderLimit+delta,0,99);
    // Native keeps this effect inline in the input handler. Compose only that
    // semantic write; the handler itself owns forbidden menu/input state.
    building->getWorkshopProfile()->max_general_orders=desired;
    result.outcome=WorkshopOrdersOutcome::Unknown;
    try {
        auto after=workshopOrdersProfile(building);
        if(after && after->generalOrderLimit==desired) {
            result.profile=std::move(after);result.outcome=WorkshopOrdersOutcome::Applied;
        }
    }catch(...) {} // Never replay an effect whose observation failed.
    return result;
}
}
