#pragma once
#include "residents_activity_native.h"
#include "labor_eligibility_cache.h"
#include "knowledge_detail_native.h"
#include "df/jobs_interfacest.h"
#include "df/cri_unitst.h"
#include "df/job_list_link.h"
#include "df/general_ref.h"
#include "df/building_trapst.h"
#include "building_item_native.h"
#include "zone_native.h"
#include <unordered_set>

namespace df3d_tasks {
struct Row {
    int32_t jobId=-1,unitId=-1,itemId=-1;
    uint32_t flags=0;
    std::string professionKey,jobKey,caption,workerName;
    int32_t buildingId=-1;
    bool canViewJob=false,canRepeat=false,canRemoveWorker=false,canSuspend=false,canCancel=false;
    bool repeating=false,suspended=false;
    std::string buildingCaption;
    df::coord buildingPosition=df::coord(-30000,-30000,-30000),workerPosition=df::coord(-30000,-30000,-30000);
    std::optional<df3d_area::ZoneOwnerNameColor> workerColor;
    std::optional<df3d_production::ItemAppearanceRecipe> workerAppearance;
};
// Native396ee0/397c90 inline these checks; there is no standalone eligibility
// call for the four edit buttons. Mirror that bounded branch over simulation
// objects only. Never call the whole feed handler or consult its menu rows.
inline bool controls(Row& row,df::job* job,df::unit* worker,uint8_t* base) {
    row.repeating=job->flags.bits.repeat;
    row.suspended=job->flags.bits.suspend;
    row.canViewJob=reinterpret_cast<bool (*)(df::job*)>(base+0xd15ef0)(job);
    df::building* holder=nullptr;
    for(auto* ref:job->general_refs)if(ref->getType()==df::general_ref_type::BUILDING_HOLDER){holder=ref->getBuilding();break;}
    if(!holder)return true;
    row.buildingId=holder->id;
    // Renderer39950c calls this virtual directly; feed3977b6 targets the
    // work location, not the footprint midpoint or the task's position.
    holder->getName(&row.buildingCaption);
    row.buildingPosition=df::coord(holder->centerx,holder->centery,holder->z);
    row.canRemoveWorker=worker && !(job->flags.whole&0x20010);
    // Native scans with a signed16 index. Reject malformed/oversized lists
    // rather than wrap the diagnostic provider's safety bound.
    if(holder->jobs.size()>32767)return false;
    bool removing=false;
    for(auto* other:holder->jobs){if(!other)return false;removing|=other->job_type==df::job_type::DestroyBuilding;}
    const auto first=holder->jobs.empty()?-1:static_cast<int>(holder->jobs.front()->job_type);
    if(holder->getBuildStage()==holder->getMaxBuildStage() && !removing && !(first>=53 && first<=65)) {
        const auto type=holder->getType();
        bool editable=type==df::building_type::Furnace || type==df::building_type::Workshop || static_cast<uint32_t>(type)>54;
        if(type==df::building_type::Trap){
            const auto subtype=static_cast<int>(static_cast<df::building_trapst*>(holder)->trap_type);
            editable=subtype<2 || subtype>5;
        }
        row.canRepeat=editable && !(job->flags.whole&0x200);
        row.canSuspend=row.canCancel=editable;
    } else {
        row.canSuspend=job->job_type==df::job_type::ConstructBuilding;
        row.canCancel=row.canSuspend || job->job_type==df::job_type::DestroyBuilding;
    }
    return true;
}
// Native323a68 opens Tasks by passing its jobs context to374630. That builder
// reads the simulation job chain, filters workers/flags, and stably inserts by
// job type. Its only output is the supplied context; no native menu is input.
inline std::optional<std::vector<Row>> rows(bool includeArtwork=false) {
    if(!df::global::world || !df3d_residents::activitySupported())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<const void*>(&df::global::world->jobs.list.next)!=base+0x23e61c8)return std::nullopt;
    static const bool pinned=[base] {
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x374630,0x3cc,UINT64_C(0xffafc144accbb830)},
            {0x310e70,0x82,UINT64_C(0x69713ac3fdf3ff0a)},
            {0x70bd0,0x15c,UINT64_C(0x4f81ccfaa39439f5)},
            {0xd15ef0,0x1d0,UINT64_C(0x41e934528fc15d5a)},
            {0x3974bd,0x298,UINT64_C(0x723f222c9c8bdbe4)},
            {0x397c18,0x77,UINT64_C(0x8d3868aec27bb264)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();
    if(!pinned)return std::nullopt;
    df3d_creature::LaborEligibilityCacheRestore indices;
    std::unordered_set<const df::job_list_link*> links;
    std::unordered_set<df::unit*> units;
    for(auto* link=df::global::world->jobs.list.next;link;link=link->next) {
        if(links.size()>=1048576 || !links.insert(link).second || !link->item)return std::nullopt;
        const auto* job=link->item;
        if(!df::enum_traits<df::job_type>::is_valid(job->job_type) || job->general_refs.size()>4096)return std::nullopt;
        for(auto* ref:job->general_refs) {
            if(!ref)return std::nullopt;
            if(ref->getType()!=df::general_ref_type::UNIT_WORKER)continue;
            auto* unit=ref->getUnit();
            if(unit && units.insert(unit).second && !indices.capture(unit,-1))return std::nullopt;
        }
    }
    df3d_creature::KnowledgeMaterialCacheRestore materials(df::global::world->raws.creatures.hist_fig_to_creature_map);
    static_assert(sizeof(df::cri_unitst)==0x70);
    static_assert(offsetof(df::jobs_interfacest,scroll_position_cri_job)==0x1c);
    using Build=void (*)(df::jobs_interfacest*);
    struct Owned {
        df::jobs_interfacest value;
        Build clear;
        ~Owned(){clear(&value);} // Native row/string destruction; vector retains its own allocation.
    } owned{{},reinterpret_cast<Build>(base+0x310e70)};
    reinterpret_cast<Build>(base+0x374630)(&owned.value);
    if(owned.value.cri_job.size()>links.size())return std::nullopt;
    std::vector<Row> result;result.reserve(owned.value.cri_job.size());
    for(const auto* entry:owned.value.cri_job) {
        if(!entry || !entry->jb)return std::nullopt;
        Row row{entry->jb->id,entry->un?entry->un->id:-1,entry->it?entry->it->id:-1,
            entry->flag.whole,entry->sort_name,entry->job_sort_name};
        // Tasks renderer3984b6 and3981ce use these original formatters.
        // Retain full CP437 strings; width-dependent clipping is presentation.
        reinterpret_cast<void (*)(df::job*,std::string*)>(base+0xd03170)(entry->jb,&row.caption);
        if(entry->un)df3d_area::staffOrderingFunctions().name(entry->un,&row.workerName,false);
        if(entry->un) {
            auto* unit=entry->un;
            // Tasks3981a8 uses1333bc0(unit,0,true,false), exactly the owner
            // name-color context. Reuse its owned facts, never the gps writer.
            row.workerColor=df3d_area::nativeZoneOwnerNameColor(*unit);
            if(!row.workerColor)return std::nullopt;
            // Tasks398117 uses6d6560 with flag400, the full-body selector
            // context used by widget_unit_portrait1423240. Retain only original
            // installed asset references, never native sheet_icon_texpos.
            if(includeArtwork){
                df3d_appearance::Result recipe;
                if(df3d_appearance::resolveUnitSelector(unit,recipe))
                    row.workerAppearance=df3d_production::ownedItemRecipe(recipe);
            }
            // Native397336..3973bd. Caged workers navigate via their item's
            // effective position; all outputs belong to this row.
            if(!unit->flags1.bits.caged)row.workerPosition=unit->pos;
            else {
                if(unit->general_refs.size()>4096)return std::nullopt;
                for(auto* ref:unit->general_refs){
                    if(!ref)return std::nullopt;
                    if(ref->getType()!=df::general_ref_type::CONTAINED_IN_ITEM)continue;
                    auto* item=ref->getItem();if(!item)continue;
                    const auto position=df3d_production::itemPosition(item);
                    if(!position)return std::nullopt;
                    row.workerPosition=*position;break;
                }
            }
        }
        if(!controls(row,entry->jb,entry->un,base))return std::nullopt;
        result.push_back(std::move(row));
    }
    return result;
}
}
