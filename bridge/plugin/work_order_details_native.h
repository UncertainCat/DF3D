#pragma once
#include "work_order_rows_native.h"
#include "df/job_details_interfacest.h"
#include "df/job_reqst.h"
#include "df/job_item.h"

namespace df3d_production {
struct WorkOrderDetailOption {int32_t kind=-1,index=-1;};
struct WorkOrderDetailMaterial {int16_t type=-1;int32_t index=-1,count=0;};
struct WorkOrderDetailsObservation {
    std::vector<WorkOrderDetailOption> options;
    std::vector<WorkOrderDetailMaterial> materials;
};
inline bool workOrderDetailsReady() {
    static const bool ready=[] {
        if(!workOrderRowsSupported() || !workshopInventoryReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x213552,0x4a6,UINT64_C(0x63bcd0e76a4e5af2)}, // inline option enumeration
            {0x213ea8,0xca,UINT64_C(0x20d1f62774cb088a)}, // native job-family dispatch data
            {0x21d190,0x42c0,UINT64_C(0x4e81bb00d071f6f9)}, // selected-option choices
            {0x21d050,0x13f,UINT64_C(0xa1141eef0dbe8cf1)}, // material amount
            {0x2230f0,0x8ec,UINT64_C(0xf7ba06a257bfe54c)}, // material sorting/filter
            {0x2239e0,0x706,UINT64_C(0x0cbc46c3d2089dc0)}, // plant sorting/filter
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}

// The opener213420 changes global screen state and is never called. Compose its
// pinned semantic option enumeration over initialized simulation requirements.
// Choice population21d190 receives an independently owned context/order/inputs.
// Only MATERIAL and PLANT are admitted: IMAGE opens a separate global picker.
// Other option families are reported but their choices are not implemented here.
inline std::optional<WorkOrderDetailsObservation> nativeWorkOrderDetails(df::manager_order& source,int32_t selected=-1) {
    if(!workOrderDetailsReady() || !df::global::world || !df::global::plotinfo ||
       !df::global::plotinfo->main.fortress_entity)return std::nullopt;
    const auto observation=nativeWorkOrderRow(source,-1,true);
    if(!observation || !observation->detailsAvailable || !source.items || source.items->elements.size()>64)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    WorkOrderDetailsObservation result;
    for(size_t i=0;i<source.items->elements.size();++i) {
        const auto* item=source.items->elements[i];if(!item)return std::nullopt;
        if(item->job_details_flags.bits.have_set_job_details ||
           (item->mat_type==0 && item->mat_index==-1) ||
           ((int(item->item_type)==5 || int(item->item_type)==55) && item->mat_type==-1) ||
           (item->flags1.whole&0x1000000) || (item->flags2.whole&0x8536c000) || (item->flags3.whole&0x120000))
            result.options.push_back({0,int32_t(i)});
    }
    const int family=int(source.job_type)-79;
    if(family>=0 && family<=165) {
        const uint8_t slot=base[0x213ecc+family];
        uint32_t target=0;std::memcpy(&target,base+0x213ea8+slot*4,sizeof(target));
        switch(target) {
            case 0x21365d:result.options.push_back({2,-1});break;
            case 0x2137ff:result.options.push_back({1,-1});break;
            case 0x213828:result.options.push_back({6,int(source.job_type)});break;
            case 0x21387f:result.options.push_back({3,-1});break;
            case 0x2138a8:result.options.push_back({4,190});break;
            case 0x2138fc:result.options.push_back({4,191});break;
            case 0x213950:result.options.push_back({4,244});break;
            case 0x2139a4:result.options.push_back({5,-1});break;
            case 0x213e26:break;
            default:return std::nullopt;
        }
    }
    if(selected==-1)return result;
    if(selected<0 || size_t(selected)>=result.options.size())return std::nullopt;
    const auto option=result.options[size_t(selected)];
    if(option.kind!=0 && option.kind!=6)return std::nullopt;
    std::vector<df::job_item> inputs;inputs.reserve(source.items->elements.size());
    for(const auto* item:source.items->elements)inputs.push_back(*item);
    df::job_reqst requirements;for(auto& item:inputs)requirements.elements.push_back(&item);
    df::manager_order order=source;order.items=&requirements;
    df::job_details_interfacest context;
    static_assert(offsetof(df::job_details_interfacest,current_option)==0x18);
    static_assert(offsetof(df::job_details_interfacest,plant_mat)==0x450);
    context.wq=&order;context.jb=nullptr;context.bld=nullptr;
    context.context=df::job_details_context_type::MANAGER_WORK_ORDER;
    context.search.x=context.search.y=context.search.z=-30000;
    context.current_option=df::job_details_option_type(option.kind);context.current_option_index=option.index;
    {
        df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
        using Populate=void (*)(df::job_details_interfacest*);
        reinterpret_cast<Populate>(base+0x21d190)(&context);
    }
    const auto& types=option.kind==0?context.material:context.plant_mat;
    const auto& indices=option.kind==0?context.matgloss:context.plant_matgloss;
    const auto& counts=option.kind==0?context.material_count:context.plant_count;
    if(types.size()>16384 || types.size()!=indices.size() || types.size()!=counts.size())return std::nullopt;
    for(size_t i=0;i<types.size();++i)result.materials.push_back({types[i],indices[i],counts[i]});
    return result;
}
}
