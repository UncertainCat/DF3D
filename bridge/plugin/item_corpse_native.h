#pragma once
#include "farm_native.h"
#include "labor_eligibility_cache.h"
#include "knowledge_detail_native.h"
#include "df/item_body_component.h"
#include "df/caste_body_info.h"
#include "df/body_part_raw.h"
#include "df/body_part_layer_raw.h"
#include "df/creature_raw.h"
#include "df/tissue.h"
#include "df/game_mode.h"
#include "df/item_corpsepiecest.h"
#include "df/material.h"

namespace df3d_production {
// c7f0e7 returns original builtin tiles for ordinary parts. The TAN_MAT
// branch instead calls a texture-cache compositor and is deliberately excluded.
// Only an owned minimal item enters the selector; no corpse/UI cache is input.
inline std::optional<int32_t> corpsePieceOriginalTile(df::item* source) {
    if(!source || !farmFunctions() || !df::global::world)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(*reinterpret_cast<const void* const*>(source)!=base+0x167bc50 ||
       reinterpret_cast<void*>(df::global::world)!=base+0x23d14f0)return std::nullopt;
    static const bool pinned=[base] {
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xc7cbc0,0x66b5,UINT64_C(0x98f324784f1accc3)},
            {0xcb1fb0,0x6c,UINT64_C(0x5d211a52b84965f8)},
            {0x6b8af0,0x96,UINT64_C(0x8f67f7a1b9d42698)},
            {0x14add70,0x12f,UINT64_C(0x01f897b15772d540)},
            {0x71f90,0x31,UINT64_C(0x9073e1e4054b7394)},
            {0x2471c0,75,UINT64_C(0xa34702d10f978500)},
            {0x28c660,6,UINT64_C(0xed9d617e577d388e)},
            {0x66e60,6,UINT64_C(0x62d2efd24138f070)},
            {0x4e0e80,8,UINT64_C(0x639f7364c3538714)},
            {0x4e0e90,7,UINT64_C(0x1e41d758869db9c1)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        constexpr std::pair<size_t,size_t> slots[]={{0,0x28c660},{0x10,0x66e60},{0x18,0x66e60},{0x38,0x4e0e80},{0x40,0x4e0e90}};
        for(auto [slot,target]:slots)if(*reinterpret_cast<const void* const*>(base+0x167bc50+slot)!=base+target)return false;
        return *reinterpret_cast<const uint32_t*>(base+0xc83278+46*4)==0xc7f0e7 &&
            std::string(reinterpret_cast<const char*>(base+0x1651c18))=="TAN_MAT";
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::item_body_component,corpse_flags)==0x324);
    static_assert(offsetof(df::item_body_component,largest_tissue.mat_type)==0x374);
    static_assert(offsetof(df::item_body_component,largest_tissue.mat_index)==0x378);
    static_assert(offsetof(df::material,reaction_product.id)==0x350);
    // A C++ subclass installs its own vtable after DFHack's constructor.
    // Instantiate the exact native identity so virtual getters stay native.
    const auto& identity=df::item_corpsepiecest::_identity;
    if(!identity.can_instantiate())return std::nullopt;
    const auto destroy=[&identity](df::item_corpsepiecest* value){identity.destroy(value);};
    std::unique_ptr<df::item_corpsepiecest,decltype(destroy)> owned(
        static_cast<df::item_corpsepiecest*>(identity.instantiate()),destroy);
    if(!owned)return std::nullopt;
    auto& item=*owned;
    if(*reinterpret_cast<const void* const*>(&item)!=base+0x167bc50)return std::nullopt;
    const auto* piece=static_cast<const df::item_corpsepiecest*>(source);
    item.id=piece->id;item.corpse_flags=piece->corpse_flags;item.largest_tissue=piece->largest_tissue;
    df3d_creature::KnowledgeMaterialCacheRestore materials(df::global::world->raws.creatures.hist_fig_to_creature_map);
    if(!item.corpse_flags.bits.unbutchered) {
        auto* material=reinterpret_cast<df::material*(*)(df::world*,int16_t,int32_t)>(base+0x14add70)(
            df::global::world,item.largest_tissue.mat_type,item.largest_tissue.mat_index);
        if(material) {
            if(material->reaction_product.id.size()>4096)return std::nullopt;
            for(const auto* id:material->reaction_product.id)if(!id || id->size()>65536)return std::nullopt;
        }
        std::string tan("TAN_MAT");
        if(reinterpret_cast<bool(*)(df::item*,std::string*)>(base+0xcb1fb0)(&item,&tan))return std::nullopt;
    }
    struct RandomRestore {
        uint64_t& state;uint64_t saved;
        explicit RandomRestore(uint64_t& value):state(value),saved(value){}
        ~RandomRestore(){state=saved;}
    } random(*reinterpret_cast<uint64_t*>(base+0x18adf98));
    return reinterpret_cast<int32_t(*)(df::item*,int32_t)>(base+0xc7cbc0)(&item,0);
}
inline bool corpseItem(df::item* item) {
    return item && (item->getType()==df::item_type::CORPSE || item->getType()==df::item_type::CORPSEPIECE);
}
// ca1aa0 uses body-plan indices directly, including parent walks and tissue
// layer IDs. Validate that graph before calling either native caption path.
inline bool corpseItemDescriptionDispatch(df::item* item) {
    if(!item || !farmFunctions() || !df::global::world)return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto* table=*reinterpret_cast<const uint8_t* const*>(item);
    if(table!=base+0x1648790 && table!=base+0x167bc50)return false;
    if(reinterpret_cast<const void*>(df::global::gamemode)!=base+0x189c298 ||
       *df::global::gamemode!=df::game_mode::DWARF)return false;
    static const bool pinned=[base] {
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xca1aa0,0xc10,UINT64_C(0x35485148557c9a6c)},
            {0xca0d60,0xe4,UINT64_C(0xaf9cbeae35c48dde)},
            {0xcaba20,0x121,UINT64_C(0x6db58b3f87764011)},
            {0xca26b0,0x110,UINT64_C(0x46b107654a2b9158)},
            {0x70be40,0x294,UINT64_C(0x66c878d81c64d1d1)},
            {0x132e430,0x1541,UINT64_C(0x4586d5154a119fe7)},
            {0x132e0c0,0x368,UINT64_C(0x5020a6b8e463a24d)},
            {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
            {0x79eb0,6,UINT64_C(0xb08934581abbd849)},
            {0x28c660,6,UINT64_C(0xed9d617e577d388e)},
            {0x66e60,6,UINT64_C(0x62d2efd24138f070)},
            {0x4e0e80,8,UINT64_C(0x639f7364c3538714)},
            {0x4e0e90,7,UINT64_C(0x1e41d758869db9c1)},
            {0xfc240,8,UINT64_C(0xfa411eb4425a85fb)},
            {0x75f60,9,UINT64_C(0x6aa4478617a62f2e)},
            {0x67040,3,UINT64_C(0xa3703b1a918cfbeb)},
            {0xfc190,7,UINT64_C(0xf985d8151da86506)},
            {0x66e90,3,UINT64_C(0x58389c18233078ff)},
            {0x67050,3,UINT64_C(0x62941518298855c4)},
            {0xfc1c0,8,UINT64_C(0x2d52a42a21f4c0e4)},
            {0xbeb620,0x15f,UINT64_C(0x5c1636cd597dfb58)},
            {0xbeb780,0x114,UINT64_C(0x2bea0cd9ba41c566)},
            {0x9bdfb0,0x148,UINT64_C(0x044d2f90a27b9a05)},
            {0xb973c0,0x79,UINT64_C(0xe30c0166fa2e4d2a)},
            {0xb98d90,0x79,UINT64_C(0x043fd29d5a07e88a)},
            {0x1376500,0xf0,UINT64_C(0x2c5ca25b0abc0a79)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        // Common c75000 getters match SEEDS; corpse material getters differ.
        constexpr std::pair<size_t,size_t> slots[]={
            {0x10,0x66e60},{0x18,0x66e60},{0x38,0x4e0e80},{0x40,0x4e0e90},
            {0x1d8,0xfc240},{0x1e8,0x66e60},{0x1f8,0xcaba20},{0x200,0xca26b0},
            {0x230,0x75f60},{0x448,0x67040},{0x478,0xfc190},{0x508,0x66e90},
            {0x590,0x66e60},{0x5a8,0x67050},{0x5e0,0xfc1c0},{0x5e8,0xca1aa0},
            {0x5f0,0xca0d60},{0x6b0,0x66e60},{0x6c0,0x67050},{0x750,0x66e60}};
        for(size_t v:{size_t(0x1648790),size_t(0x167bc50)}) {
            if(*reinterpret_cast<const void* const*>(base+v)!=base+(v==0x1648790?0x79eb0:0x28c660))return false;
            for(auto [slot,target]:slots)if(*reinterpret_cast<const void* const*>(base+v+slot)!=base+target)return false;
        }
        return true;
    }();
    if(!pinned)return false;
    auto* corpse=static_cast<df::item_body_component*>(item);
    static_assert(offsetof(df::item_body_component,body.components.body_part_status)==0x120);
    static_assert(offsetof(df::item_body_component,body.components.layer_status)==0x168);
    static_assert(offsetof(df::body_part_layer_raw,layer_id)==0x68);
    auto* plan=reinterpret_cast<df::caste_body_info* (*)(df::item*)>(base+0xca26b0)(item);
    if(!plan)return true; // Native explicitly supports an unresolved body plan.
    const auto& parts=plan->body_parts;
    if(parts.size()>32767 || parts.size()!=corpse->body.components.body_part_status.size())return false;
    auto* raw=df::creature_raw::find(corpse->race);
    for(const auto* part:parts) {
        if(!part || part->con_part_id< -1 || (part->con_part_id>=0 && size_t(part->con_part_id)>=parts.size()) ||
           part->name_singular.empty() || !part->name_singular.front() || part->layers.size()>32767)return false;
        for(const auto* layer:part->layers) {
            if(!layer || layer->layer_id<0 || size_t(layer->layer_id)>=corpse->body.components.layer_status.size())return false;
            if(raw && layer->tissue_id>=0 && size_t(layer->tissue_id)<raw->tissue.size()) {
                const auto* tissue=raw->tissue[layer->tissue_id];
                if(!tissue || int(tissue->tissue_mat_state)<0 || int(tissue->tissue_mat_state)>5)return false;
            }
        }
    }
    // Every parent chain must terminate; native follows it without a cycle cap.
    std::vector<uint8_t> visited(parts.size());
    for(size_t i=0;i<parts.size();++i) {
        int32_t at=int32_t(i);
        while(at>=0 && !visited[at]){visited[at]=1;at=parts[at]->con_part_id;}
        if(at>=0 && visited[at]==1)return false;
        at=int32_t(i);
        while(at>=0 && visited[at]==1){visited[at]=2;at=parts[at]->con_part_id;}
    }
    return true;
}
// The corpse caption can select a unit profession and office title. Preserve
// their lookup indices, including spouse-office links, around the whole call.
struct CorpseCaptionScope {
    df3d_creature::LaborEligibilityCacheRestore indices;
    std::unique_ptr<df3d_creature::KnowledgeMaterialCacheRestore> materials;
    bool ready=true;
    explicit CorpseCaptionScope(df::item* item) {
        if(!corpseItem(item))return;
        ready=corpseItemDescriptionDispatch(item);
        if(!ready)return;
        if(auto* unit=df::unit::find(static_cast<df::item_body_component*>(item)->unit_id))ready=indices.capture(unit,-1);
        if(ready)materials=std::make_unique<df3d_creature::KnowledgeMaterialCacheRestore>(df::global::world->raws.creatures.hist_fig_to_creature_map);
    }
};
}
