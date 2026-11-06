#pragma once
#include "workshop_catalog_native.h"
#include "df/job_details_interfacest.h"
#include "df/descriptor_color.h"
#include "df/job_item.h"
#include "df/job_reqst.h"
#include "df/manager_order.h"
#include <array>

namespace df3d_production {
struct WorkOrderDyeChoice {int32_t color=-1,first=-1,second=-1,available=0;bool tint=false;};
struct WorkOrderDyeCatalog {int32_t kind=-1,target=-1;std::vector<WorkOrderDyeChoice> rows;};
inline bool workOrderDyeReady() {
    static const bool ready=[] {
        if(!workshopInventoryReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x21d190,0x42c0,UINT64_C(0x4e81bb00d071f6f9)},
            {0x7dc570,0x555,UINT64_C(0x93c147122b21ca4a)},
            {0x7dc060,0x509,UINT64_C(0xff551b5b2d3478e1)},
            {0x7db680,0x19c,UINT64_C(0x9ed5e993cee0b99f)},
            {0x7db820,0x2cb,UINT64_C(0x3e74337c4e69a9da)},
            {0x7dbaf0,0x2cb,UINT64_C(0xcd7de336623f6f65)},
            {0x7dbdc0,0x29f,UINT64_C(0xc05d32975818ca9e)},
            {0x21a402,0x587,UINT64_C(0x6cd7442784092983)}, // inline tint ingredient enumeration
            {0x21b48f,0x3f3,UINT64_C(0xd06d746fdfbc786b)}, // inline mix ingredient enumeration
            {0x221490,0xffc,UINT64_C(0xf6a57bb554baff89)},
            {0x222490,0xc5b,UINT64_C(0x1767332d6a44234c)},
            {0x2143b0,0x4548,UINT64_C(0x68dcba5b5aa698ef)}, // caption/swatch composition, never invoked
            {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)},
            {0x21aa2a,0x20,UINT64_C(0x030ef09363a6e70b)}, // direct dye effect
            {0x219f3c,0x15,UINT64_C(0xaf82ebf88a6cc620)}, // tint effect
            {0x21af91,0x18,UINT64_C(0x1791e2bdca5ac8be)}, // mix effect
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}

// Native218900 has no separate ingredient-list leaf. Compose its pinned loops
// over owned inventory/search storage, calling DF's color-mixing calculation.
// The inventory RVAs below are simulation vectors selected by that composition;
// no native menu, search, cursor or screen storage is consulted.
inline bool populateWorkOrderDyeReagents(df::job_details_interfacest& context,int32_t target) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto& colors=df::global::world->raws.descriptors.colors;
    const size_t count=colors.size();
    if(target<0 || size_t(target)>=count || count>1024)return false;
    std::vector<int32_t> dyes(count),substrates(count);
    const bool mixing=int(context.current_option)==5;
    const auto collect=[&](bool dye)->bool {
        df::job_item_filter filter;
        reinterpret_cast<void(*)(df::job_item_filter*)>(base+0x1fb050)(&filter);
        static_assert(offsetof(df::job_item_filter,can_steal_haul_items)==0xb2);
        static_assert(offsetof(df::job_item_filter,min_dimension)==0x88);
        size_t source=0x23e5c60;
        filter.can_steal_haul_items=true;filter.flags2.whole=dye?1:2;filter.use_flags2=true;
        if(dye)filter.flags1.whole=0x10;
        else if(context.dye_object_job_type==191){filter.item_type=df::item_type(58);filter.min_dimension=10000;source=0x23e5f90;}
        else if(context.dye_object_job_type==244){filter.item_type=df::item_type(55);source=0x23e5f48;}
        else {filter.item_type=df::item_type(57);filter.flags1.whole=0x40;filter.min_dimension=15000;source=0x23e5f78;}
        const auto& inventory=*reinterpret_cast<const std::vector<df::item*>*>(base+source);
        std::vector<df::item*> owned(inventory.begin(),inventory.end()),found;
        filter.item_vector=&owned;
        reinterpret_cast<void(*)(df::job_item_filter*,std::vector<df::item*>*)>(base+0xa29630)(&filter,&found);
        for(auto* item:found) {
            if(!item)return false;
            const int32_t color=dye?item->isDyeColor():item->getColorWhetherDyedOrNot();
            if(color==-1)continue;
            if(color<0 || size_t(color)>=count)return false;
            auto& value=dye?dyes[size_t(color)]:substrates[size_t(color)];
            const int32_t amount=dye?item->getDyeAmount(color):1;
            if(amount<0 || int64_t(value)+amount>INT32_MAX)return false;
            value+=amount;
        }
        return true;
    };
    if(!collect(true) || (!mixing && !collect(false)))return false;
    auto& first=mixing?context.mix_dye_reagent_color1:context.dye_object_tint_reagent_color1;
    auto& second=mixing?context.mix_dye_reagent_color2:context.dye_object_tint_reagent_color2;
    auto& available=mixing?context.mix_dye_reagent_available:context.dye_object_tint_reagent_available;
    first.clear();second.clear();available.clear();
    for(int pass=0;pass<2;++pass)for(int32_t a=0;size_t(a)<count;++a) {
        if(a==target || (!mixing && pass==0 && substrates[size_t(a)]==0))continue;
        for(int32_t b=mixing?a+1:0;size_t(b)<count;++b) {
            if(b==target || b==a)continue;
            const bool stocked=(mixing?dyes[size_t(a)]:substrates[size_t(a)])>0 && dyes[size_t(b)]>0;
            if((pass==0)!=stocked)continue;
            std::array<int32_t,7> results;results.fill(-1);
            reinterpret_cast<void(*)(std::vector<df::descriptor_color*>*,int32_t,int32_t,int32_t*)>(base+0x7dc570)(&colors,a,b,results.data());
            for(const auto color:results)if(color==target) {
                if(first.size()>=16384)return false;
                first.push_back(a);second.push_back(b);
                available.push_back(pass==0?std::min(mixing?dyes[size_t(a)]:substrates[size_t(a)],dyes[size_t(b)]):0);
                if(mixing)break; // Native tint retains repeated mix results; Mix dye does not.
            }
        }
    }
    if(mixing) {
        context.mix_dye_chosen_target_color=target;
        context.mix_dye_reagent_color1_master=first;context.mix_dye_reagent_color2_master=second;context.mix_dye_reagent_available_master=available;
    } else {
        context.dye_object_tint_color=target;
        context.dye_object_tint_reagent_color1_master=first;context.dye_object_tint_reagent_color2_master=second;context.dye_object_tint_reagent_available_master=available;
    }
    return true;
}

inline std::optional<WorkOrderDyeCatalog> nativeWorkOrderDyeCatalog(df::manager_order& source,int32_t target=-1,const std::string& query={},bool filterApplied=false) {
    const int job=int(source.job_type),kind=job==243?5:4;
    if((job!=190 && job!=191 && job!=243 && job!=244) || !workOrderDyeReady() || !df::global::world ||
       !source.items || source.items->elements.size()>64 || query.size()>128 || target< -1)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::vector<df::job_item> inputs;inputs.reserve(source.items->elements.size());
    for(const auto* input:source.items->elements){if(!input)return std::nullopt;inputs.push_back(*input);}
    df::job_reqst requirements;for(auto& input:inputs)requirements.elements.push_back(&input);
    df::manager_order order=source;order.items=&requirements;
    df::job_details_interfacest context;context.wq=&order;context.jb=nullptr;context.bld=nullptr;
    context.context=df::job_details_context_type::MANAGER_WORK_ORDER;
    context.search.x=context.search.y=context.search.z=-30000;
    context.current_option=df::job_details_option_type(kind);context.current_option_index=kind==4?job:-1;
    reinterpret_cast<void(*)(df::job_details_interfacest*)>(base+0x21d190)(&context);
    const auto& targets=kind==4?context.dye_object_target_color:context.mix_dye_target_color;
    if(target>=0) {
        bool found=false;
        for(size_t i=0;i<targets.size();++i)if(targets[i]==target && (kind==5 || (i<context.dye_object_target_color_is_tint.size() && context.dye_object_target_color_is_tint[i])))found=true;
        if(!found || !populateWorkOrderDyeReagents(context,target))return std::nullopt;
    }
    if(filterApplied || !query.empty()) {
        if(kind==4)context.dye_object_filter=query;else context.mix_dye_filter=query;
        reinterpret_cast<void(*)(df::job_details_interfacest*)>(base+(kind==4?0x221490:0x222490))(&context);
    }
    WorkOrderDyeCatalog result;result.kind=kind;result.target=target;
    if(target<0) {
        const auto& available=kind==4?context.dye_object_target_color_available:context.mix_dye_target_color_available;
        if(targets.size()>16384 || targets.size()!=available.size() || (kind==4 && targets.size()!=context.dye_object_target_color_is_tint.size()))return std::nullopt;
        for(size_t i=0;i<targets.size();++i)result.rows.push_back({targets[i],-1,-1,available[i],kind==5 || context.dye_object_target_color_is_tint[i]});
    } else {
        const auto& first=kind==4?context.dye_object_tint_reagent_color1:context.mix_dye_reagent_color1;
        const auto& second=kind==4?context.dye_object_tint_reagent_color2:context.mix_dye_reagent_color2;
        const auto& available=kind==4?context.dye_object_tint_reagent_available:context.mix_dye_reagent_available;
        if(first.size()>16384 || first.size()!=second.size() || first.size()!=available.size())return std::nullopt;
        for(size_t i=0;i<first.size();++i)result.rows.push_back({target,first[i],second[i],available[i],false});
    }
    return result;
}
}
