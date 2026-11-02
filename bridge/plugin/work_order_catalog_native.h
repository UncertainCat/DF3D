#pragma once
#include "workshop_job_native.h"
#include "df/manager_order_template.h"
#include <cstdlib>

namespace df3d_production {
inline bool workOrderCatalogSupported() {
    static const bool supported=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xa97150,0x5678,UINT64_C(0x87b9a46d78af72d7)},
            {0x3113b0,0x3a,UINT64_C(0x3a7d19574928cc99)},
            {0x8c03a0,0x17ad,UINT64_C(0xedd2766250590831)},
            {0x14d7f0,0xa0,UINT64_C(0x982df68a02e5f200)},
            {0x376300,0x82,UINT64_C(0x00a15ffdde597218)},
            {0x311580,0x68c,UINT64_C(0x47301c66334c61ee)},
            {0x3769cf,0x4d,UINT64_C(0x7e38a43365dc1161)},
            {0x37683f,0x4a,UINT64_C(0x659f0f1773728921)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return supported;
}

// A97150 builds the fortress-wide catalog in the supplied vector. It reads
// civilization resources, installed raws and acquired reaction permissions;
// no native picker/widget storage is supplied or borrowed. Native376390 uses
// this same builder before formatting, sorting and grouping the picker rows.
// This is the global catalog, not yet the workshop-filtered picker.
inline std::optional<std::vector<df::manager_order_template>> nativeWorkOrderCatalog() {
    if(!workOrderCatalogSupported() || !df::global::world || !df::global::plotinfo ||
       !df::global::plotinfo->main.fortress_entity)return std::nullopt;
    static_assert(sizeof(df::manager_order_template)==0x98);
    static_assert(offsetof(df::manager_order_template,reaction_name)==8);
    static_assert(offsetof(df::manager_order_template,name)==0x50);
    static_assert(offsetof(df::manager_order_template,compare_str)==0x70);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Destroy=void (*)(df::manager_order_template*);
    struct Owned {
        std::vector<df::manager_order_template*> rows;
        Destroy destroy;
        ~Owned(){for(auto* row:rows)if(row)destroy(row);}
    } owned{{},reinterpret_cast<Destroy>(base+0x3113b0)};
    // Material resolution may populate a lookup cache. Restore that scratch
    // while retaining the templates allocated into our independent vector.
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Build=void (*)(std::vector<df::manager_order_template*>*);
    reinterpret_cast<Build>(base+0xa97150)(&owned.rows);
    if(owned.rows.size()>65536)return std::nullopt;
    const auto& text=df3d_area::staffOrderingFunctions();if(!text)return std::nullopt;
    for(auto* row:owned.rows) {
        if(!row || row->reaction_name.size()>128)return std::nullopt;
        df::job job;
        job.job_type=row->job_type;job.reaction_name=row->reaction_name;
        job.item_type=row->item_type;job.item_subtype=row->item_subtype;
        job.mat_type=row->mat_type;job.mat_index=row->mat_index;
        job.specflag=row->specflag;job.specdata=row->specdata;
        job.material_category=row->material_category;
        job.art_spec.type=row->art_specifier;job.art_spec.id=row->art_specifier_id1;job.art_spec.subid=row->art_specifier_id2;
        const auto caption=workshopJobCaption(job);
        if(!caption || caption->size()>8192)return std::nullopt;
        row->name=*caption;row->compare_str=*caption;text.normalize(&row->compare_str);
    }
    using Compare=int (*)(const void*,const void*);
    // Native376640 uses qsort with this pure caption comparator. Its arguments
    // point only into our vector of owned templates.
    if(!owned.rows.empty())std::qsort(owned.rows.data(),owned.rows.size(),sizeof(owned.rows[0]),reinterpret_cast<Compare>(base+0x376300));
    std::vector<df::manager_order_template> result;result.reserve(owned.rows.size());
    for(const auto* row:owned.rows)result.push_back(*row);
    return result;
}

inline std::optional<std::vector<df::manager_order_template>> nativeWorkshopOrderCatalog(df::building* building) {
    if(!building || (building->getType()!=df::building_type::Workshop && building->getType()!=df::building_type::Furnace))return std::nullopt;
    const auto header=observeBuildingHeader(building);
    if(!header || header->removing || header->stage!=header->maxStage)return std::nullopt;
    auto catalog=nativeWorkOrderCatalog();if(!catalog)return std::nullopt;
    const int32_t type=int32_t(building->getType()),subtype=building->getSubtype(),custom=building->getCustomType();
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Classify=void (*)(int16_t,int16_t,int16_t,int32_t,uint32_t,int32_t*,int32_t*);
    const auto classify=reinterpret_cast<Classify>(base+0x311580);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::vector<df::manager_order_template> result;
    for(auto& row:*catalog) {
        bool allowed=false;
        if(row.job_type==df::job_type::CustomReaction) {
            // Native3767aa finds the first exact reaction code, then checks its
            // parallel building restriction vectors. Use simulation raws only.
            const auto& reactions=df::global::world->raws.reactions.reactions;
            const auto found=std::find_if(reactions.begin(),reactions.end(),[&](const auto* r){return r && r->code==row.reaction_name;});
            if(found!=reactions.end()) {
                const auto& match=(*found)->building;
                if(match.type.size()!=match.subtype.size() || match.type.size()!=match.custom.size())return std::nullopt;
                for(size_t i=0;i<match.type.size();++i)
                    if(int32_t(match.type[i])==type && match.subtype[i]==subtype && match.custom[i]==custom){allowed=true;break;}
            }
        } else if(custom==-1) {
            int32_t expectedType=-1,expectedSubtype=-1;
            classify(int16_t(row.job_type),row.item_subtype,row.mat_type,row.mat_index,row.material_category.whole,&expectedType,&expectedSubtype);
            // Native3769cf maps magma forge/furnace variants for builtin jobs.
            int32_t builtinSubtype=subtype;
            if(type==13 && subtype==6)builtinSubtype=5;
            else if(type==5 && subtype>=4 && subtype<=6)builtinSubtype=subtype-3;
            allowed=expectedType==type && expectedSubtype==builtinSubtype;
        }
        if(allowed)result.push_back(std::move(row));
    }
    return result;
}
}
