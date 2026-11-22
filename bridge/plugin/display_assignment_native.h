#pragma once
#include "display_inventory_native.h"
#include "df/job.h"

namespace df3d_production {
inline bool displayAssignmentReady() {
    if(!buildingItemFunctions())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x367618,0xa8,UINT64_C(0xe0c4a1aa26b42fbc)},
            {0x1adf0a,0x37,UINT64_C(0xc152e3a01aab78fd)},
            {0xcb1420,0xe2,UINT64_C(0x5d444e44fe3e3f89)},
            {0x72660,0x7d,UINT64_C(0x2414953f9e9e9670)}};
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
struct DisplayAssignments {
    int32_t id=-1;
    std::vector<int32_t> items;
    bool removing=false;
    uint64_t revision=0;
};
inline std::optional<DisplayAssignments> displayAssignments(df::building* building) {
    auto* display=virtual_cast<df::building_display_furniturest>(building);
    if(!display || !displayAssignmentReady() || display->getBuildStage()!=display->getMaxBuildStage() ||
       display->displayed_items.size()>1048576 || display->jobs.size()>4096)return {};
    DisplayAssignments result;result.id=display->id;result.items=display->displayed_items;
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(int i=0;i<8;++i){hash^=uint8_t(value);hash*=UINT64_C(1099511628211);value>>=8;}};
    add(result.id);add(display->getBuildStage());add(display->centerx);add(display->centery);add(display->z);
    add(result.items.size());
    for(auto id:result.items) {
        add(id);auto* item=df::item::find(id);add(item!=nullptr);
        if(!item)continue;
        if(item->general_refs.size()>4096)return {};
        // Lazy item inspection may calculate weight. Cache validity is not
        // assignment authority and must not invalidate a row by rendering it.
        auto flags=item->flags;flags.bits.weight_computed=false;
        add(flags.whole);add(item->flags2.whole);add(item->pos.x);add(item->pos.y);add(item->pos.z);
        add(item->general_refs.size());
        for(auto* ref:item->general_refs) {
            if(!ref)return {};add(int(ref->getType()));
            auto* holder=ref->getBuilding();add(holder?holder->id:-1);
        }
    }
    add(display->jobs.size());
    for(auto* job:display->jobs) {
        if(!job)return {};add(job->id);add(int(job->job_type));add(job->flags.whole);
        if(job->job_type==df::job_type::DestroyBuilding)result.removing=true;
    }
    result.revision=(hash&INT64_MAX)|1;return result;
}
enum class DisplayOutcome:uint8_t { Rejected, Completed, Stale, Unknown };
struct DisplayEdit {
    DisplayOutcome outcome=DisplayOutcome::Rejected;
    bool effectsStarted=false;
    std::optional<DisplayAssignments> receipt;
};
// Commit a locally owned sorted draft, or remove one parent row. Epoch/session
// and draft ownership belong to the caller. Validate all candidates before any
// effect; partial failure after entry is Unknown and must never be replayed.
inline DisplayEdit editDisplayAssignments(df::building* building,uint64_t expected,
                                         const std::vector<int32_t>& ids,bool assign) {
    DisplayEdit result;
    try {
        const auto before=displayAssignments(building);
        if(!before || !expected || expected>INT64_MAX || ids.empty() || ids.size()>1048576 || (!assign && ids.size()!=1))return result;
        if(before->revision!=expected){result.outcome=DisplayOutcome::Stale;return result;}
        if(before->removing || (assign && before->items.size()+ids.size()>1048576))return result;
        auto& target=*static_cast<df::building_display_furniturest*>(building);
        std::optional<std::vector<int32_t>> eligible;
        if(assign){eligible=displayInventory(building);if(!eligible)return result;}
        int32_t previous=-1;
        for(auto id:ids) {
            if(id<0 || id<=previous)return result;previous=id;
            auto* item=df::item::find(id);if(!item || item->general_refs.size()>4096)return result;
            const auto& available=assign?*eligible:before->items;
            if(std::find(available.begin(),available.end(),id)==available.end())return result;
            for(auto* ref:item->general_refs) {
                if(!ref)return result;
                if(int(ref->getType())==68) {
                    auto* old=ref->getBuilding();
                    if(old && (old->getType()!=df::building_type::DisplayFurniture ||
                        static_cast<df::building_display_furniturest*>(old)->displayed_items.size()>1048576))return result;
                }
            }
        }
        if(assign)target.displayed_items.reserve(target.displayed_items.size()+ids.size());
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        const auto removeRef=reinterpret_cast<bool(*)(df::item*,int32_t,int32_t)>(base+0xcb1420);
        result.effectsStarted=true;result.outcome=DisplayOutcome::Unknown;
        for(auto id:ids) {
            auto* item=df::item::find(id);if(!item)return result;
            item->flags.bits.in_building=false;item->flags2.bits.location_reserved=false;
            if(assign) {
                buildingItemFunctions().forbid(item,3);
                // Native36762c uses the first display reference and removes all
                // occurrences from its prior building before adding the new one.
                for(auto* ref:item->general_refs)if(int(ref->getType())==68) {
                    auto* old=virtual_cast<df::building_display_furniturest>(ref->getBuilding());
                    if(old) {
                        auto& membership=old->displayed_items;
                        membership.erase(std::remove(membership.begin(),membership.end(),id),membership.end());
                        removeRef(item,68,-1);
                    }
                    break;
                }
                target.displayed_items.push_back(id);
                reinterpret_cast<void(*)(df::item*,int32_t,int32_t)>(base+0x72660)(item,68,target.id);
                item->flags2.bits.location_reserved=true;
            } else {
                removeRef(item,68,-1);buildingItemFunctions().forbid(item,3);
                auto at=std::find(target.displayed_items.begin(),target.displayed_items.end(),id);
                if(at==target.displayed_items.end())return result;target.displayed_items.erase(at);
            }
        }
        const auto after=displayAssignments(building);if(!after)return result;
        for(auto id:ids) {
            if((std::find(after->items.begin(),after->items.end(),id)!=after->items.end())!=assign)return result;
            auto* item=df::item::find(id);if(!item || bool(item->flags2.bits.location_reserved)!=assign)return result;
            bool referenced=false;
            for(auto* ref:item->general_refs)if(int(ref->getType())==68 && ref->getBuilding()==building)referenced=true;
            if(referenced!=assign)return result;
        }
        result.receipt=after;result.outcome=DisplayOutcome::Completed;
    }catch(...){}
    return result;
}
}
