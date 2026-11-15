#pragma once
#include "farm_native.h"
#include "df/building_trapst.h"
#include "df/item.h"
#include "df/item_trappartsst.h"
#include "df/buildingitemst.h"
#include "df/item_type.h"
#include "modules/Maps.h"

namespace df3d_production {
// Source authority is independent of the native selected sheet and of the
// initial mechanism search. Targeting retains the initially chosen item IDs.
inline std::optional<BuildingHeaderObservation> observeLever(df::building* source) {
    auto* lever=virtual_cast<df::building_trapst>(source);
    if(!lever || int(lever->trap_type)!=0 || lever->isHidden() || lever->jobs.size()>=32767 ||
       lever->getBuildStage()!=lever->getMaxBuildStage())return std::nullopt;
    auto* tile=DFHack::Maps::getTileDesignation(lever->centerx,lever->centery,lever->z);
    if(!tile || tile->bits.hidden)return std::nullopt;
    const auto value=observeBuildingHeader(lever,true);
    if(!value || value->removing)return std::nullopt;
    return value;
}
// The initial Link selector is inline in DF's sheet input. Preserve its
// TRAPPARTS order/flag mask here; call DF for availability, effective position,
// walkability component and stock exclusion. Output IDs are independently owned.
inline std::optional<std::array<int32_t,2>> leverInitialMechanisms(df::building* building) {
    auto* lever=virtual_cast<df::building_trapst>(building);
    if(!farmFunctions() || !df::global::world || !lever || int(lever->trap_type)!=0 ||
       lever->getBuildStage()!=lever->getMaxBuildStage())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t expected;};
        constexpr Pin pins[]={
            {0x1ad883,0x2b1,UINT64_C(0x6e32f372e3f3cf02)},
            {0xc93380,0x98,UINT64_C(0x9455ba082ba604c4)},
            {0xc93160,0x213,UINT64_C(0x07d957dea30ed105)},
            {0xc8baa0,0x11a,UINT64_C(0x2c62fce4a0555c66)},
            {0x10afe0,0xb9,UINT64_C(0xdd7dd1f9769e2f8a)}};
        for(const auto& pin:pins) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=pin.expected)return false;
        }return true;
    }();
    auto& world=*df::global::world;
    auto& items=world.items.other.TRAPPARTS;
    if(!ready || reinterpret_cast<uint8_t*>(&world)!=base+0x23d14f0 ||
       reinterpret_cast<uint8_t*>(&items)!=base+0x23e5b88 || items.size()>1000000)return std::nullopt;
    using Check=bool (*)(df::item*);
    using Position=void (*)(df::item*,int16_t*,int16_t*,int16_t*);
    using Walk=int32_t (*)(df::world*,int16_t,int16_t,int16_t);
    auto walk=reinterpret_cast<Walk>(base+0x10afe0);
    std::array<int32_t,2> result{{-1,-1}};size_t count=0;
    for(auto* item:items) {
        if(!item || !reinterpret_cast<Check>(base+0xc93380)(item) ||
           (item->flags.whole & UINT64_C(0x800e90cb2)))continue;
        int16_t x=-30000,y=-30000,z=-30000;
        reinterpret_cast<Position>(base+0xc8baa0)(item,&x,&y,&z);
        if(!walk(&world,x,y,z))continue;
        const auto component=walk(&world,lever->centerx,lever->centery,lever->z);
        if(walk(&world,x,y,z)!=component || reinterpret_cast<Check>(base+0xc93160)(item))continue;
        result[count++]=item->id;if(count==2)break;
    }
    return result;
}
// Native1adb58..1adb8f: semantic job creation/attachment, with no menu input.
// fd580/d020c0 register the job and allocate its ID immediately. Call only at
// a safe point after validating the complete intent; never use as a preview.
inline bool leverPullNativeReady() {
    static const bool ready=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
        };
        return hash(0xfd580,0x23)==UINT64_C(0x1f9646cb809a07ae) &&
            hash(0xd020c0,0x1f9)==UINT64_C(0xe6506fad7c779085) &&
            hash(0x54bcf0,0xce)==UINT64_C(0x7ceaff76902a0dea) &&
            hash(0xd09b70,0x130)==UINT64_C(0x1046a66c3f604a04) &&
            hash(0x1adb58,0x3c)==UINT64_C(0x63603996d93f2ca9);
    }();return ready;
}
inline bool leverLinkNativeReady() {
    static const bool ready=[] {
        if(!leverPullNativeReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t expected;};
        constexpr Pin pins[]={
            {0x1aa380,0x315,UINT64_C(0xed2f0dc4efaf2a25)},
            {0x1b9780,0x31,UINT64_C(0x59972c0f9f455e8c)},
            {0xc93380,0x98,UINT64_C(0x9455ba082ba604c4)},
            {0x5726f0,0x162,UINT64_C(0x93ed129be23f5e93)},
            {0x57b770,0x113,UINT64_C(0x3fc5ac46eee9f334)},
            {0xd09750,0x7c,UINT64_C(0xcbfd54f134a3afeb)},
            {0xd028e0,0x5b4,UINT64_C(0x052e6647c39a35f9)}};
        for(const auto& pin:pins) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=pin.expected)return false;
        }return true;
    }();return ready;
}
// Native first visible footprint wins, then the native type dispatch and
// duplicate/pending-link predicate decide admission. Ordinary fortress
// visibility uses !isHidden, excluding native hide/unhide-menu overrides.
inline std::optional<int32_t> leverLinkTargetAt(df::building* source,df::coord pos) {
    auto* lever=virtual_cast<df::building_trapst>(source);
    if(!leverLinkNativeReady() || !df::global::world || !lever || int(lever->trap_type)!=0 ||
       lever->getBuildStage()!=lever->getMaxBuildStage() || lever->jobs.size()>32767 ||
       !DFHack::Maps::isValidTilePos(pos))return std::nullopt;
    for(const auto* job:lever->jobs)if(!job || job->job_type==df::job_type::DestroyBuilding)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto& buildings=df::global::world->buildings.other.IN_PLAY;
    if(reinterpret_cast<uint8_t*>(&buildings)!=base+0x23edf28 || buildings.size()>1000000)return std::nullopt;
    df::building* target=nullptr;
    using Contains=bool (*)(df::building*,int16_t,int16_t,int16_t,bool);
    for(auto* candidate:buildings) {
        if(!candidate || candidate->isHidden())continue;
        const auto kind=candidate->getType();
        if(kind==df::building_type::Stockpile || kind==df::building_type::Civzone)continue;
        if(reinterpret_cast<Contains>(base+0x57b770)(candidate,pos.x,pos.y,pos.z,false)){target=candidate;break;}
    }
    if(!target)return -1;
    switch(int(target->getType())) {
    case 8:case 9:case 19:case 25:case 27:case 28:case 31:
    case 35:case 36:case 37:case 38:case 39:case 40:break;
    case 23:if(target->getSubtype()!=5)return -1;break;
    default:return -1;
    }
    auto* actual=virtual_cast<df::building_actual>(target);
    if(!actual || actual->construction_stage!=target->getMaxBuildStage() ||
       target->isForbidden() || target->isInvisibleToPlayer())return -1;
    if(actual->contained_items.size()>32767)return std::nullopt;
    for(const auto* held:actual->contained_items)
        if(!held || !held->item || held->item->general_refs.size()>32767)return std::nullopt;
    using Linked=bool (*)(df::building*,df::building*);
    if(reinterpret_cast<Linked>(base+0x5726f0)(target,source))return -1;
    return target->id;
}
inline df::job* linkLeverNative(df::building* source,df::coord pos,int32_t sourceItem,int32_t targetItem) {
    const auto selected=leverLinkTargetAt(source,pos);
    if(!selected || *selected<0 || sourceItem<0 || targetItem<0 || sourceItem==targetItem)return nullptr;
    auto* first=df::item::find(sourceItem);auto* second=df::item::find(targetItem);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    using Check=bool (*)(df::item*);
    for(auto* item:{first,second})if(!item || item->getType()!=df::item_type::TRAPPARTS || !reinterpret_cast<Check>(base+0xc93380)(item) ||
        (item->flags.whole&UINT64_C(0x800e90cb2)))return nullptr;
    using Create=df::job* (*)();
    using Reference=void (*)(df::job*,int32_t,int32_t);
    using Item=bool (*)(df::job*,df::item*,int32_t,int32_t,int32_t);
    using Attach=void (*)(df::building*,df::job*,bool);
    using Requirements=void (*)(df::job*);
    auto* job=reinterpret_cast<Create>(base+0xfd580)();
    job->job_type=df::job_type::LinkBuildingToTrigger;
    reinterpret_cast<Reference>(base+0xd09750)(job,33,*selected);
    reinterpret_cast<Item>(base+0xd028e0)(job,first,3,-1,-1);
    reinterpret_cast<Item>(base+0xd028e0)(job,second,4,-1,-1);
    reinterpret_cast<Attach>(base+0x54bcf0)(source,job,false);
    reinterpret_cast<Requirements>(base+0xd09b70)(job);
    return job;
}
inline df::job* pullLeverNative(df::building* building) {
    auto* lever=virtual_cast<df::building_trapst>(building);
    if(!leverPullNativeReady() || !df::global::world || !lever || int(lever->trap_type)!=0 ||
       lever->getBuildStage()!=lever->getMaxBuildStage() || lever->jobs.size()>=32767)return nullptr;
    auto* tile=DFHack::Maps::getTileDesignation(lever->centerx,lever->centery,lever->z);
    if(!tile || tile->bits.hidden)return nullptr;
    for(const auto* job:lever->jobs)if(!job || job->job_type==df::job_type::DestroyBuilding)return nullptr;
    static_assert(sizeof(df::job)==0x148 && offsetof(df::job,job_type)==0x14);
    using Create=df::job* (*)();
    using Attach=void (*)(df::building*,df::job*,bool);
    using Requirements=void (*)(df::job*);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* job=reinterpret_cast<Create>(base+0xfd580)();
    job->job_type=df::job_type::PullLever;
    job->pos=df::coord(lever->centerx,lever->centery,lever->z);
    reinterpret_cast<Attach>(base+0x54bcf0)(lever,job,false);
    reinterpret_cast<Requirements>(base+0xd09b70)(job);
    return job;
}
}
