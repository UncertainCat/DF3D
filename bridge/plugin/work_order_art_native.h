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
            {0x201320,0x79,UINT64_C(0x9eedf99c8af9aefb)}, // figure caption composition
            {0x201976,0x60,UINT64_C(0xd99b90c0338c328e)}, // site caption composition
            {0x201fb6,0x62,UINT64_C(0xef66198fb280beac)}, // entity caption composition
            {0xa94030,0x6a1,UINT64_C(0xd81db68b3c9b33d2)}, // simple native name
            {0xc0f630,0x2c,UINT64_C(0x2f03e40b0a07e0bf)}, // historical identity
            {0x20a1df,0x94,UINT64_C(0xda14704e2a7596a2)}, // figure selection
            {0x20a515,0x94,UINT64_C(0x887e8ee07510f16a)}, // site selection
            {0x20a844,0x90,UINT64_C(0x21fb16abe2986637)}, // entity selection
            {0x20f179,0x91,UINT64_C(0xd457c7675c96d8cb)}, // artist choice
            {0x1ffced,0x216,UINT64_C(0xbccd02d40a931fd0)}, // order artwork heading composition
            {0x1fff6d,0x14,UINT64_C(0xd97688af8b65493a)}, // heading limit
            {0x1615350,0xc8,UINT64_C(0x227f3ddd70cde8fd)}, // root option literals
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
inline std::optional<std::string> nativeWorkOrderArtSubjectCaption(int32_t kind,int32_t id) {
    if(!workOrderArtSubjectsReady() || !df::global::world)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    df::language_name* name=nullptr;
    if(kind==1) {
        auto* figure=df::historical_figure::find(id);if(!figure)return std::nullopt;
        name=&figure->name;
        auto* identity=reinterpret_cast<df::identity*(*)(df::historical_figure*)>(base+0xc0f630)(figure);
        if(identity)name=reinterpret_cast<df::language_name*(*)(df::identity*)>(base+0xc3a4f0)(identity);
    } else if(kind==2) {
        auto* site=df::world_site::find(id);if(!site)return std::nullopt;name=&site->name;
    } else if(kind==3) {
        auto* entity=df::historical_entity::find(id);if(!entity)return std::nullopt;name=&entity->name;
    }
    if(!name)return std::nullopt;
    df::language_name owned=*name;
    std::string caption,translated;
    reinterpret_cast<void(*)(df::language_name*,std::string*)>(base+0xa94030)(&owned,&caption);
    reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&translated,true,false);
    caption+=reinterpret_cast<const char*>(base+0x1602dbc);
    caption+=translated;caption+=reinterpret_cast<const char*>(base+0x15e9718);
    return caption;
}

inline WorkOrderDetailEditResult setWorkOrderArtSubject(df::manager_order& order,uint64_t revision,int32_t option,int32_t kind,int32_t id,uint64_t listRevision,const std::string& query={}) {
    WorkOrderDetailEditResult result;
    if(!workOrderArtSubjectsReady() || kind<0 || kind>3)return result;
    const auto before=nativeWorkOrderDetails(order);
    if(!before || option<0 || size_t(option)>=before->options.size())return result;
    if(!revision || revision!=before->revision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    const auto optionKind=before->options[size_t(option)].kind;
    if(optionKind!=1 && optionKind!=3)return result;
    // The improvement Image entry applies its own type edit before opening art.
    if(optionKind==3 && int(order.specdata.improvement)!=0)return result;
    if(kind==0) {
        if(id!=-1 || listRevision || !query.empty())return result;
    } else {
        const auto choices=nativeWorkOrderArtSubjects(order,kind,query);
        if(!choices)return result;
        if(!listRevision || choices->listRevision!=listRevision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
        if(std::find(choices->ids.begin(),choices->ids.end(),id)==choices->ids.end())return result;
    }
    result.outcome=WorkshopOrdersOutcome::Unknown;
    order.art_spec.type=df::job_art_specifier_type(kind-1);order.art_spec.id=id;
    // Native related-subject actions leave subid intact; artist choice clears it.
    if(kind==0)order.art_spec.subid=-1;
    if(order.items)rebuildWorkOrderDetailRequirements(order);
    result.observation=nativeWorkOrderDetails(order);
    if(result.observation)result.outcome=WorkshopOrdersOutcome::Applied;
    return result;
}
struct WorkOrderArtPage {
    int16_t page=-1;std::string caption;
    std::vector<std::pair<int32_t,std::string>> rows;
    uint64_t listRevision=0;uint32_t total=0,nextCursor=0;
};
inline std::optional<WorkOrderArtPage> nativeWorkOrderArtPage(df::manager_order& order,int16_t page,const std::string& query,uint32_t cursor,uint64_t listRevision) {
    if(!workOrderArtSubjectsReady())return std::nullopt;
    const auto row=nativeWorkOrderRow(order,-1,true);if(!row)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    WorkOrderArtPage result;result.page=page;
    result.caption=reinterpret_cast<const char*>(base+0x1615548);result.caption+=row->caption;
    if(order.amount_total>0)result.caption+=" ("+std::to_string(order.amount_total)+")";
    if(result.caption.size()>78)result.caption.resize(78);
    if(page==-1) {
        if(!query.empty() || cursor || listRevision)return std::nullopt;
        constexpr std::pair<int32_t,size_t> options[]={{1,0x1615360},{2,0x16153c8},{3,0x16153a0},{5,0x16153f0},{6,0x16153d8},{0,0x1615400}};
        for(const auto& [id,rva]:options)result.rows.emplace_back(id,reinterpret_cast<const char*>(base+rva));
        result.total=uint32_t(result.rows.size());return result;
    }
    const auto subjects=nativeWorkOrderArtSubjects(order,page,query);
    if(!subjects || cursor>subjects->ids.size() || (listRevision && listRevision!=subjects->listRevision))return std::nullopt;
    result.listRevision=subjects->listRevision;result.total=uint32_t(subjects->ids.size());
    const auto end=std::min(size_t(cursor)+128,subjects->ids.size());
    for(size_t i=cursor;i<end;++i) {
        auto caption=nativeWorkOrderArtSubjectCaption(page,subjects->ids[i]);
        if(!caption || caption->size()>1024)return std::nullopt;
        result.rows.emplace_back(subjects->ids[i],std::move(*caption));
    }
    result.nextCursor=end<subjects->ids.size()?uint32_t(end):0;return result;
}
inline WorkOrderDetailEditResult beginWorkOrderArt(df::manager_order& order,uint64_t revision,int32_t option) {
    WorkOrderDetailEditResult result;
    if(!workOrderArtSubjectsReady())return result;
    const auto before=nativeWorkOrderDetails(order);
    if(!before || option<0 || size_t(option)>=before->options.size())return result;
    if(!revision || revision!=before->revision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    const auto kind=before->options[size_t(option)].kind;if(kind!=1 && kind!=3)return result;
    // Native21931f writes Image before entering the editor, without rebuilding
    // requirements or clearing the existing art specifier. Back retains this.
    result.outcome=WorkshopOrdersOutcome::Unknown;
    if(kind==3)order.specdata.improvement=df::improvement_type(0);
    result.observation=nativeWorkOrderDetails(order);
    if(result.observation)result.outcome=WorkshopOrdersOutcome::Applied;
    return result;
}
}
