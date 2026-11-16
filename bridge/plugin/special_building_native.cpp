#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "special_building_native.h"
#include "farm_native.h"
#include "unit_description_native.h"
#include "building_item_native.h"
#include "df/building_nest_boxst.h"
#include "df/building_animaltrapst.h"
#include "df/building_hivest.h"
#include "df/buildings_other_id.h"
#include "df/item_critter.h"
#include <cstring>

namespace df3d_production {
namespace {
bool ready() {
    if(!farmFunctions() || !df::global::world)return false;
    static_assert(offsetof(df::building_nest_boxst,claimed_by)==0x148);
    static_assert(offsetof(df::building_animaltrapst,bait_type)==0x148);
    static_assert(offsetof(df::building_hivest,hive_flags)==0x148);
    static_assert(offsetof(df::item_critter,race)==0xb8);
    static const bool pinned=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t at,length;uint64_t hash;};
        // Renderer ranges are static evidence for semantic branches only. They
        // are never executed and no widget, drawing or selection state is read.
        constexpr Pin pins[]={
            {0x196637,0x1e5,UINT64_C(0x2d9024af9aff7e00)},
            {0x19836c,0x8ce,UINT64_C(0xbe461fd3fa5ca647)},
            {0x18b841,0xea1,UINT64_C(0x82a7f8fc147226ff)},
            {0x1330c30,0x688,UINT64_C(0x0e165ee31decf426)},
            {0x560f10,0x293,UINT64_C(0xc30f8d5969d48a48)}};
        for(const auto& p:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){hash^=base[p.at+i];hash*=UINT64_C(1099511628211);}
            if(hash!=p.hash)return false;
        }
        struct Text {size_t at;const char* value;};
        constexpr Text texts[]={{0x1601c18,"Nest box claimed by"},{0x1601c00,"Nest box unclaimed"},
            {0x1601da0,"Desired bait: "},{0x1601d98,"Nothing"},{0x1601d8c,"Meat"},
            {0x1601d84,"Fish"},{0x1601d78,"Large gem"},
            {0x1600d10,"Trap Occupied:"},{0x1601fe0,"Trap Baited:"}};
        for(const auto& t:texts)if(std::strcmp(reinterpret_cast<const char*>(base+t.at),t.value))return false;
        return true;
    }();return pinned;
}
std::string text(size_t at) {
    return reinterpret_cast<const char*>(reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr))+at);
}
bool target(df::building* building,df::building_type type) {
    return ready() && building && building->getType()==type &&
        building->getBuildStage()==building->getMaxBuildStage();
}
}
std::optional<NestBoxBody> nestBoxBody(df::building* building) {
    if(!target(building,df::building_type::NestBox))return {};
    const auto& nest=*static_cast<df::building_nest_boxst*>(building);
    NestBoxBody result;
    auto* unit=df::unit::find(nest.claimed_by);
    result.status=text(unit?0x1601c18:0x1601c00);
    if(!unit)return result;
    if(unit->inventory.size()>10000 || !unit->body.body_plan)return {};
    for(auto* held:unit->inventory)if(!held || !held->item)return {};
    result.nameColor=df3d_area::nativeZoneOwnerNameColor(*unit);
    if(!result.nameColor)return {};
    df3d_creature::InventoryDescriptionContext owned(*unit);
    using Name=void(*)(df::unit*,std::string*,bool);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    reinterpret_cast<Name>(base+0x1330c30)(owned.unit(),&result.name,false);
    if(result.name.size()>2048)return {};
    result.claimantId=unit->id;return result;
}
std::optional<AnimalTrapBody> animalTrapBody(df::building* building) {
    if(!target(building,df::building_type::AnimalTrap))return {};
    const auto& trap=*static_cast<df::building_animaltrapst*>(building);
    AnimalTrapBody result;result.baitType=trap.bait_type;
    if(trap.contained_items.size()>10000)return {};
    if(trap.contained_items.empty())return result;
    if(trap.contained_items.size()==1) {
        result.state=AnimalTrapBody::State::Empty;result.status=text(0x1601da0);
        switch(trap.bait_type) {
        case -1:result.status+=text(0x1601d98);break;
        case 48:result.status+=text(0x1601d8c);break;
        case 49:result.status+=text(0x1601d84);break;
        case 44:result.status+=text(0x1601d78);break;
        default:break; // Native leaves the suffix empty for other values.
        }
        return result;
    }
    const auto* entry=trap.contained_items[1];if(!entry || !entry->item)return {};
    auto* item=entry->item;const bool occupied=item->getType()==df::item_type::VERMIN;
    result.state=occupied?AnimalTrapBody::State::Occupied:AnimalTrapBody::State::Baited;
    result.status=text(occupied?0x1600d10:0x1601fe0);result.itemId=item->id;
    const auto caption=buildingItemCaption(item);if(!caption || caption->size()>2048)return {};
    result.name=*caption;return result;
}
std::optional<HiveBody> hiveBody(df::building* building) {
    if(!target(building,df::building_type::Hive))return {};
    auto& hive=*static_cast<df::building_hivest*>(building);
    HiveBody result;result.flags=hive.hive_flags.whole;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto& hives=df::global::world->buildings.other.HIVE;
    if(reinterpret_cast<const void*>(&hives)!=base+0x23eeb40 || hives.size()>100000 || hive.contained_items.size()>10000)return {};
    // Standalone native map/tile query, with no UI or scratch inputs.
    result.outdoorAccess=reinterpret_cast<bool(*)(df::building*)>(base+0x560f10)(&hive);
    for(const auto* entry:hive.contained_items) {
        if(!entry || !entry->item)return {};
        auto* item=entry->item;
        if(!item->flags.bits.in_building || item->getType()!=df::item_type::VERMIN)continue;
        result.colonyRace=static_cast<df::item_critter*>(item)->race;
        // Native18c49f calls virtual slot9 (getRace). One matching colony per
        // hive, including this hive; the first installed colony sets the race.
        for(const auto* other:hives) {
            if(!other || other->contained_items.size()>10000)return {};
            for(const auto* contained:other->contained_items) {
                if(!contained || !contained->item)return {};
                auto* candidate=contained->item;
                if(candidate->flags.bits.in_building && candidate->getType()==df::item_type::VERMIN && candidate->getRace()==result.colonyRace) {
                    ++result.matchingColonies;break;
                }
            }
        }
        result.crowding=result.matchingColonies>=60?2:result.matchingColonies>40?1:0;
        break;
    }
    return result;
}
std::optional<SpecialBuildingControls> specialBuildingControls(df::building* building) {
    if(!building)return {};
    SpecialBuildingControls result;result.id=building->id;result.type=int32_t(building->getType());
    df::building_actual* actual=nullptr;
    if(result.type==24) {
        result.trap=animalTrapBody(building);if(!result.trap)return {};
        actual=static_cast<df::building_animaltrapst*>(building);
    } else if(result.type==49) {
        result.hive=hiveBody(building);if(!result.hive)return {};
        actual=static_cast<df::building_hivest*>(building);
    } else return {};
    if(building->jobs.size()>10000 || actual->contained_items.size()>10000)return {};
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto number=[&](uint64_t n){for(int i=0;i<8;++i){hash^=uint8_t(n);hash*=UINT64_C(1099511628211);n>>=8;}};
    number(result.id);number(result.type);number(building->getBuildStage());number(building->getMaxBuildStage());number(building->flags.whole);
    if(result.trap){number(result.trap->baitType);number(uint8_t(result.trap->state));number(result.trap->itemId);}
    if(result.hive){number(result.hive->flags);number(result.hive->outdoorAccess);number(result.hive->colonyRace);number(result.hive->matchingColonies);}
    number(actual->contained_items.size());
    for(const auto* entry:actual->contained_items) {
        if(!entry || !entry->item)return {};
        number(entry->item->id);number(entry->use_mode);number(entry->item->flags.whole);
    }
    number(building->jobs.size());
    for(const auto* job:building->jobs) {
        if(!job)return {};
        result.jobs.push_back({job->id,int32_t(job->job_type),int32_t(job->item_type),job->flags.whole});
        number(job->id);number(int32_t(job->job_type));number(int32_t(job->item_type));number(job->flags.whole);
        result.removing|=job->job_type==df::job_type::DestroyBuilding;
    }
    result.revision=(hash&INT64_MAX)?hash&INT64_MAX:1;return result;
}
namespace {
bool editsReady() {
    if(!ready())return false;
    static const bool pinned=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto pin=[&](size_t at,size_t count,uint64_t expected) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){hash^=base[at+i];hash*=UINT64_C(1099511628211);}
            return hash==expected;
        };
        return pin(0x1afad4,0xf5,UINT64_C(0x81dbccbc33c93a1a)) &&
            pin(0x1adfee,0x275,UINT64_C(0x93cbe65241c0f8b8));
    }();return pinned;
}
bool sameJobs(const std::vector<SpecialBuildingControls::Job>& a,const std::vector<SpecialBuildingControls::Job>& b) {
    if(a.size()!=b.size())return false;
    for(size_t i=0;i<a.size();++i)if(a[i].id!=b[i].id || a[i].type!=b[i].type || a[i].itemType!=b[i].itemType || a[i].flags!=b[i].flags)return false;
    return true;
}
}
SpecialBuildingEdit setAnimalTrapBait(df::building* building,uint64_t expected,int16_t bait) {
    SpecialBuildingEdit result;
    try {
        if(!expected || expected>INT64_MAX || (bait!=-1 && bait!=44 && bait!=48 && bait!=49) || !editsReady())return result;
        const auto before=specialBuildingControls(building);if(!before || !before->trap)return result;
        if(before->revision!=expected){result.outcome=SpecialBuildingOutcome::Stale;return result;}
        if(before->removing || before->trap->state!=AnimalTrapBody::State::Empty)return result;
        auto& trap=*static_cast<df::building_animaltrapst*>(building);
        std::vector<SpecialBuildingControls::Job> retained;
        for(const auto& job:before->jobs)if(job.type!=int32_t(df::job_type::BaitTrap) || job.itemType==bait)retained.push_back(job);
        // Even clicking the already selected bait cancels mismatched fill jobs.
        result.effectsStarted=true;result.outcome=SpecialBuildingOutcome::Unknown;
        trap.bait_type=bait;
        using Cancel=void(*)(df::building*,int32_t);
        const auto cancel=reinterpret_cast<Cancel>(farmFunctions().cancelJob);
        for(size_t i=trap.jobs.size();i-->0;) {
            const auto* job=trap.jobs[i];
            if(job->job_type==df::job_type::BaitTrap && int32_t(job->item_type)!=bait)cancel(&trap,int32_t(i));
        }
        auto after=specialBuildingControls(building);
        if(!after || !after->trap || after->trap->baitType!=bait || !sameJobs(retained,after->jobs))return result;
        result.receipt=std::move(after);result.outcome=SpecialBuildingOutcome::Completed;
    }catch(...){}
    return result;
}
SpecialBuildingEdit setHiveSetting(df::building* building,uint64_t expected,uint32_t mask,bool enabled) {
    SpecialBuildingEdit result;
    try {
        if(!expected || expected>INT64_MAX || (mask!=1 && mask!=2) || !editsReady())return result;
        const auto before=specialBuildingControls(building);if(!before || !before->hive)return result;
        if(before->revision!=expected){result.outcome=SpecialBuildingOutcome::Stale;return result;}
        if(before->removing)return result;
        const auto flags=(before->hive->flags&~mask)|(enabled?mask:0U);
        if(flags==before->hive->flags){result.outcome=SpecialBuildingOutcome::Completed;result.receipt=before;return result;}
        result.effectsStarted=true;result.outcome=SpecialBuildingOutcome::Unknown;
        static_cast<df::building_hivest*>(building)->hive_flags.whole=flags;
        auto after=specialBuildingControls(building);
        if(!after || !after->hive || after->hive->flags!=flags || !sameJobs(before->jobs,after->jobs))return result;
        result.receipt=std::move(after);result.outcome=SpecialBuildingOutcome::Completed;
    }catch(...){}
    return result;
}
}
