#pragma once
#include "work_order_conditions_native.h"
#include "df/plant_raw.h"
#include "df/job_details_interfacest.h"
#include "df/job_reqst.h"
#include "df/job_item.h"

namespace df3d_production {
struct WorkOrderDetailOption {int32_t kind=-1,index=-1;std::string caption;};
struct WorkOrderDetailMaterial {int16_t type=-1;int32_t index=-1,count=0;std::string caption;};
struct WorkOrderDetailsObservation {
    uint64_t revision=0,choicesRevision=0;
    std::string caption;
    std::vector<WorkOrderDetailOption> options;
    std::vector<WorkOrderDetailMaterial> materials;
};
inline bool workOrderDetailsReady() {
    static const bool ready=[] {
        if(!workOrderRowsSupported() || !workshopInventoryReady() || !workOrderSuggestionsSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x214ba4,0x18d,UINT64_C(0x102c5cc07df1d881)}, // input caption selection
            {0x215863,0x25e,UINT64_C(0x41f6aef5115dd21c)}, // material captions
            {0x218565,0xc4,UINT64_C(0x0f7660fb69bc1fe8)}, // plant captions
            {0x2198fe,0x6b,UINT64_C(0xf5db908387417145)}, // material requirement effect
            {0x219967,0x73,UINT64_C(0x7e8585ffa494649a)}, // first input effect
            {0x21afd4,0x41,UINT64_C(0xaf2f8581b53f027d)}, // rebuild requirements
            {0x21c23d,0xf8,UINT64_C(0x282e828b7cc40106)}, // plant effect
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

// Native214ba4 classifies the original requirement, including saved originals
// after a prior selection. Captions use the installed native literals.
inline std::string nativeDetailInputCaption(const df::job_item& item) {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const bool saved=item.job_details_flags.bits.have_set_job_details;
    const auto type=saved?item.job_details_mat_type:item.mat_type;
    const auto index=saved?item.job_details_mat_index:item.mat_index;
    const auto flags=saved?item.job_details_item_flags2.whole:item.flags2.whole;
    size_t literal=0x16158f0;
    if(type==0 && index==-1)literal=0x16156b8;
    else if(type==-1 && int(item.item_type)==5)literal=0x16156d8;
    else if(type==-1 && int(item.item_type)==55)literal=0x16156d0;
    else if(type==-1 && int(item.item_type)==58)literal=0x16158a4;
    else if(type==-1 && int(item.item_type)==57)literal=0x161589c;
    else {
        constexpr unsigned bits[]={14,31,15,17,18,24,26,20,21};
        constexpr size_t words[]={0x1614d54,0x16158b4,0x16158ac,0x16158c4,0x16158bc,0x16158d4,0x16158cc,0x16158e4,0x16158dc};
        bool found=false;
        for(size_t i=0;i<std::size(bits);++i)if(flags&(uint32_t(1)<<bits[i])){literal=words[i];found=true;break;}
        if(!found) {
            if(item.flags1.whole&0x1000000)literal=0x1601078;
            else if(item.flags3.whole&0x100000)literal=0x16158fc;
            else if(item.flags3.whole&0x20000)literal=0x16156b8;
        }
    }
    return std::string(reinterpret_cast<const char*>(base+0x16156c0))+reinterpret_cast<const char*>(base+literal);
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
    result.caption=observation->caption+" ("+std::to_string(source.amount_total)+")";
    uint64_t hash=observation->revision;
    const auto add=[&](uint64_t value){for(unsigned shift=0;shift<64;shift+=8){hash^=(value>>shift)&255;hash*=UINT64_C(1099511628211);}};
    add(source.items->elements.size());
    for(const auto* item:source.items->elements) {
        if(!item)return std::nullopt;
        add(int(item->item_type));add(item->item_subtype);add(item->mat_type);add(item->mat_index);
        add(item->flags1.whole);add(item->flags2.whole);add(item->flags3.whole);add(item->flags4);add(item->flags5);
        add(item->job_details_flags.whole);add(item->job_details_mat_type);add(item->job_details_mat_index);add(item->job_details_item_flags2.whole);
    }
    result.revision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
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
    constexpr size_t optionNames[]={0,0x15fe1e8,0x1615910,0x1615690,0x1615900,0x1615900,0x1615930};
    for(auto& option:result.options)option.caption=option.kind==0?nativeDetailInputCaption(*source.items->elements[size_t(option.index)]):reinterpret_cast<const char*>(base+optionNames[option.kind]);
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
    hash=result.revision;add(option.kind);add(option.index);add(types.size());
    for(size_t i=0;i<types.size();++i) {
        std::string caption;
        if(option.kind==0) {
            WorkOrderFilterChoice material;material.materialType=types[i];material.materialIndex=indices[i];material.materialState=0;
            const auto named=nativeWorkOrderFilterCaption(material,1);if(!named)return std::nullopt;caption=*named;
        } else {
            const auto& plants=df::global::world->raws.plants.all;
            if(indices[i]<0 || size_t(indices[i])>=plants.size() || !plants[size_t(indices[i])])return std::nullopt;
            caption=plants[size_t(indices[i])]->name;
            reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&caption);
        }
        if(caption.size()>512)return std::nullopt;
        add(types[i]);add(indices[i]);
        result.materials.push_back({types[i],indices[i],counts[i],std::move(caption)});
    }
    result.choicesRevision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    return result;
}

struct WorkOrderDetailEditResult {
    WorkshopOrdersOutcome outcome=WorkshopOrdersOutcome::Rejected;
    std::optional<WorkOrderDetailsObservation> observation;
};
inline WorkOrderDetailEditResult setWorkOrderDetailMaterial(df::manager_order& order,uint64_t revision,int32_t option,uint64_t choicesRevision,int32_t choice) {
    WorkOrderDetailEditResult result;
    const auto before=nativeWorkOrderDetails(order,option);
    if(!before)return result;
    if(!revision || revision!=before->revision || !choicesRevision || choicesRevision!=before->choicesRevision){result.outcome=WorkshopOrdersOutcome::Stale;return result;}
    if(choice<0 || size_t(choice)>=before->materials.size())return result;
    const auto selected=before->options[size_t(option)];
    const auto material=before->materials[size_t(choice)];
    const size_t index=selected.kind==6?0:size_t(selected.index);
    if(!order.items || index>=order.items->elements.size() || !order.items->elements[index])return result;
    auto& item=*order.items->elements[index];
    result.outcome=WorkshopOrdersOutcome::Unknown;
    if(!item.job_details_flags.bits.have_set_job_details) {
        item.job_details_flags.bits.have_set_job_details=true;
        item.job_details_mat_type=item.mat_type;item.job_details_mat_index=item.mat_index;
        if(selected.kind==0)item.job_details_item_flags2=item.flags2;
    }
    item.mat_type=material.type;item.mat_index=material.index;
    if(index==0) {
        order.mat_type=material.type;order.mat_index=material.index;
        using Fill=void (*)(df::job_reqst*,int16_t,int16_t,int16_t,int16_t,int32_t,const std::string*,uint32_t,uint32_t,int32_t,df::building*,int32_t,int32_t,int32_t);
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
        reinterpret_cast<Fill>(base+0xd09ca0)(order.items,int16_t(order.job_type),int16_t(order.item_type),order.item_subtype,order.mat_type,order.mat_index,&order.reaction_name,order.material_category.whole,order.specflag.whole,order.specdata.hist_figure_id,nullptr,int32_t(order.art_spec.type),order.art_spec.id,order.art_spec.subid);
    }
    result.observation=nativeWorkOrderDetails(order);
    if(result.observation)result.outcome=WorkshopOrdersOutcome::Applied;
    return result;
}
}
