#pragma once
#include "hunter_ammunition_native.h"
#include "knowledge_detail_native.h"

namespace df3d_hunter_ammunition {
inline uint8_t* captionBase() {
    auto* base=df3d_standing::supportedBase();if(!base)return nullptr;
    static const bool valid=[base] {
        for(const auto& pin:std::array<std::array<uint64_t,3>,6>{{
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x52d650,0x2b4,UINT64_C(0x9e8023d09def7af9)},
            {0xc65450,0xaba,UINT64_C(0x47fa672b7bbcd332)},
            {0x454bb9,0x18e,UINT64_C(0x7dd74b5d1d04de37)},
            {0x4592f4,0x74,UINT64_C(0x4af5155fe4e44536)},
            {0x4544ba,0x8c,UINT64_C(0x0eeb0a9ff993cf22)}}}){
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin[1];++i){hash^=base[pin[0]+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin[2])return false;
        }
        return true;
    }();
    return valid?base:nullptr;
}
// Inputs originate in validated native candidates or the current simulation.
// Raw type formatting and capitalization write independently owned strings.
inline std::optional<std::string> caption(int16_t type,int16_t subtype,Material material,bool type_choice=false,bool foreign=false) {
    auto* base=captionBase();if(!base || !df::global::world)return std::nullopt;
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::string text;
    if(!type_choice && material.type==-1 && material.category!=-1){
        // Prefix addresses follow native454c0d's category switch, including its
        // fallback. Literal bytes stay in the supported installation.
        constexpr std::array<size_t,29> prefixes={0x16156d0,0x16158a4,0x16156d8,0x163e594,
            0x16156b8,0x163e594,0x163e594,0x163e594,0x163e594,0x163e594,0x163e594,0x163e594,
            0x163e594,0x163e59c,0x163e594,0x163e59c,0x16158fc,0x16158c4,0x16158bc,0x16158dc,
            0x16158cc,0x16158e4,0x163e594,0x163e594,0x163e594,0x163e594,0x163e5a8,0x16158ac,0x16158b4};
        const size_t rva=material.category>=1 && material.category<=29?prefixes[size_t(material.category-1)]:0x163e594;
        text=reinterpret_cast<const char*>(base+rva);text+=reinterpret_cast<const char*>(base+0x15e873c);
    }
    using Item=void(*)(std::string*,int16_t,int16_t,int16_t,int32_t,int32_t,int32_t,bool,void*,int32_t,int32_t,bool,int32_t,int32_t);
    reinterpret_cast<Item>(base+0xa82c10)(&text,type,subtype,material.type,material.index,type_choice?0:-1,0,!type_choice,nullptr,-1,-1,true,0,0);
    if(type_choice && foreign)text+=reinterpret_cast<const char*>(base+0x163e650);
    reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&text);
    return text;
}
inline std::optional<std::string> stackCaption(df::item* item) {
    auto* base=captionBase();if(!base || !item)return std::nullopt;
    std::string text;
    reinterpret_cast<void(*)(df::item*,std::string*,bool,int32_t)>(base+0xc65450)(item,&text,false,-1);
    return text;
}
}
