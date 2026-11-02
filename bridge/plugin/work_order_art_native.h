#pragma once
#include "work_order_details_native.h"
#include "df/image_creator_interfacest.h"
#include "df/historical_figure.h"
#include "df/historical_entity.h"
#include "df/world_site.h"

namespace df3d_production {
struct WorkOrderArtSubjects {
    uint64_t orderRevision=0,listRevision=0;
    int32_t kind=-1;
    std::vector<int32_t> ids;
};
inline bool workOrderArtSubjectsReady() {
    static const bool ready=[] {
        if(!workOrderDetailsReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x20f300,0x3a2,UINT64_C(0x7a58222f99e2a853)}, // historical figures
            {0x20f6b0,0x3dc,UINT64_C(0x9aec29c4191db1c7)}, // sites
            {0x20fa90,0x37c,UINT64_C(0x8972bb117b3367d0)}, // entities
            {0x1fc0c0,0x8c,UINT64_C(0xd79cbc6ebdc2073a)}, // native name comparator
            {0x1fb1c0,0x345,UINT64_C(0x2cdbd88b294d4dae)}, // owned master-row cleanup
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}

// These leaves build/sort/filter subjects on an owned context. Neither the
// whole opener1ffae0 nor the mixed navigation/action dispatcher20ed00 is called.
inline std::optional<WorkOrderArtSubjects> nativeWorkOrderArtSubjects(df::manager_order& source,int32_t kind,const std::string& query={}) {
    if(kind<1 || kind>3 || query.size()>128 || !workOrderArtSubjectsReady())return std::nullopt;
    const auto details=nativeWorkOrderDetails(source);if(!details)return std::nullopt;
    bool supported=false;
    for(const auto& option:details->options)if(option.kind==1 || option.kind==3)supported=true;
    if(!supported)return std::nullopt;
    df::manager_order order=source;
    df::image_creator_interfacest context;
    context.context=df::image_creator_context_type::JOB_DETAILS_MAIN;
    context.current_option=df::image_creator_option_type(kind);
    context.ics.wq=&order;context.ics.jb=nullptr;
    context.ics.image_ent=df::global::plotinfo->main.fortress_entity;
    context.filter=query;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    struct Cleanup {
        df::image_creator_interfacest& context;
        const uint8_t* base;
        ~Cleanup(){reinterpret_cast<void(*)(df::image_creator_interfacest*)>(base+0x1fb1c0)(&context);}
    } cleanup{context,base};
    WorkOrderArtSubjects result;result.kind=kind;result.orderRevision=details->revision;
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    const auto collect=[&](auto& rows,size_t rva) {
        using Rows=std::remove_reference_t<decltype(rows)>;
        reinterpret_cast<void(*)(df::image_creator_interfacest*,Rows*)>(base+rva)(&context,&rows);
        if(rows.size()>262144)return false;
        result.ids.reserve(rows.size());
        for(const auto* row:rows) {if(!row || row->id<0)return false;result.ids.push_back(row->id);}
        return true;
    };
    if(!(kind==1?collect(context.hf,0x20f300):kind==2?collect(context.st,0x20f6b0):collect(context.ent,0x20fa90)))return std::nullopt;
    uint64_t hash=details->revision;
    const auto add=[&](uint64_t value){for(unsigned shift=0;shift<64;shift+=8){hash^=(value>>shift)&255;hash*=UINT64_C(1099511628211);}};
    add(kind);add(result.ids.size());for(auto id:result.ids)add(id);
    result.listRevision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    return result;
}
}
