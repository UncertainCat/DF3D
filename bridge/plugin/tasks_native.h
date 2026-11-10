#pragma once
#include "residents_activity_native.h"
#include "labor_eligibility_cache.h"
#include "knowledge_detail_native.h"
#include "df/jobs_interfacest.h"
#include "df/cri_unitst.h"
#include "df/job_list_link.h"
#include "df/general_ref.h"
#include <unordered_set>

namespace df3d_tasks {
struct Row {
    int32_t jobId=-1,unitId=-1,itemId=-1;
    uint32_t flags=0;
    std::string professionKey,jobKey,caption,workerName;
};
// Native323a68 opens Tasks by passing its jobs context to374630. That builder
// reads the simulation job chain, filters workers/flags, and stably inserts by
// job type. Its only output is the supplied context; no native menu is input.
inline std::optional<std::vector<Row>> rows() {
    if(!df::global::world || !df3d_residents::activitySupported())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<const void*>(&df::global::world->jobs.list.next)!=base+0x23e61c8)return std::nullopt;
    static const bool pinned=[base] {
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x374630,0x3cc,UINT64_C(0xffafc144accbb830)},
            {0x310e70,0x82,UINT64_C(0x69713ac3fdf3ff0a)},
            {0x70bd0,0x15c,UINT64_C(0x4f81ccfaa39439f5)},
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
        result.push_back(std::move(row));
    }
    return result;
}
}
