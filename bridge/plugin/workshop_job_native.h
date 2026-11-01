#pragma once
#include "farm_native.h"
#include "knowledge_detail_native.h"

namespace df3d_production {
// Native button text8c2310 supplies these scalar fields to d032b0. The first
// argument is unused; the optional live-job argument is null in the picker.
// Copy the reaction string and own the output, without allocating any widgets.
inline std::optional<std::string> workshopJobCaption(const df::job& job) {
    static const bool ready=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0xd032b0,0x5024)==UINT64_C(0xba755d2dfd15322d) &&
            hash(0x1360ec0,0x189)==UINT64_C(0xbbaa204ea4c15268) &&
            hash(0x14d1920,0x459)==UINT64_C(0xf48e28715360ed9a) &&
            hash(0x14add70,0x12f)==UINT64_C(0x01f897b15772d540) &&
            hash(0x145bee0,0x5e)==UINT64_C(0x6abc4e374e372eef) &&
            hash(0x144d90,0xba)==UINT64_C(0x97aed5d23117e68f) &&
            hash(0xaa3bd0,0x1c3)==UINT64_C(0x0f9cd818efc6bad8) &&
            hash(0xa94030,0x6a1)==UINT64_C(0xd81db68b3c9b33d2);
    }();
    if(!ready || !df::global::world)return std::nullopt;
    using Format=void (*)(void*,std::string*,int16_t,int16_t,int16_t,int16_t,int32_t,
        const std::string*,uint32_t,int32_t,uint32_t,const df::job*,int32_t,int32_t,int32_t);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    std::string result,reaction=job.reaction_name;
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    reinterpret_cast<Format>(base+0xd032b0)(nullptr,&result,int16_t(job.job_type),int16_t(job.item_type),
        job.item_subtype,job.mat_type,job.mat_index,&reaction,job.specflag.whole,
        job.specdata.hist_figure_id,job.material_category.whole,nullptr,
        int32_t(job.art_spec.type),job.art_spec.id,job.art_spec.subid);
    return result;
}
// The workshop button's action8c2460 delegates input construction through
// d09b70 to d09ca0. Call that semantic leaf with an unlinked, independently
// owned job. It reads raws, the use-dyed-cloth standing order and needsMagma;
// it writes only the supplied requirements. No button or menu is constructed.
inline bool workshopRequirements(df::job& owned, df::building* building) {
    static const bool ready=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0xd09ca0,0x2f52)==UINT64_C(0x2e65a5a8b4f5a1c5) &&
            hash(0xa676c0,0xa0)==UINT64_C(0xcf5d67f71c5b901e) &&
            hash(0xcc0110,0xa0)==UINT64_C(0xdb71755904d0cf88);
    }();
    if(!ready || !df::global::world || !building || owned.list_link || owned.id!=-1 ||
       !owned.job_items.elements.empty())return false;
    static_assert(offsetof(df::job,job_items)==0xc8);
    static_assert(sizeof(df::job_spec_flags)==4 && sizeof(df::job_material_category)==4);
    using Fill=void (*)(df::job_reqst*,int16_t,int16_t,int16_t,int16_t,int32_t,
        const std::string*,uint32_t,uint32_t,int32_t,df::building*,int32_t,int32_t,int32_t);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    reinterpret_cast<Fill>(base+0xd09ca0)(&owned.job_items,int16_t(owned.job_type),
        int16_t(owned.item_type),owned.item_subtype,owned.mat_type,owned.mat_index,
        &owned.reaction_name,owned.material_category.whole,owned.specflag.whole,
        owned.specdata.hist_figure_id,building,int32_t(owned.art_spec.type),
        owned.art_spec.id,owned.art_spec.subid);
    return true;
}
}
