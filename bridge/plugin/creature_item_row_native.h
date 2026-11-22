#pragma once
#include "building_item_native.h"
#include "df/item_petst.h"
#include "df/creature_raw.h"
#include "df/caste_raw.h"
#include "df/caste_raw_flags.h"

namespace df3d_residents {
struct ItemPetRow {std::string caption;std::array<int16_t,3> color;df::coord position;std::string activity;std::array<int16_t,3> activityColor{2,0,1};};
inline std::optional<ItemPetRow> itemPetRow(df::item* item) {
    auto* pet=virtual_cast<df::item_petst>(item);
    if(!pet || !df::global::world)return std::nullopt;
    static const bool supported=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,size;uint64_t hash;};
        constexpr Pin pins[]={
            {0xc7b200,0x1f,UINT64_C(0x5c74bfc3e8d4ddf4)},
            {0x7022c0,0xe5,UINT64_C(0xb01a72d65e66e9a3)},
            {0x142b746,0x73,UINT64_C(0x66d559baafa821e)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.size;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return std::nullopt;
    const auto caption=df3d_production::buildingItemCaption(item);
    if(!caption)return std::nullopt;
    // Native142b45a..142b4c5 captures raw item.pos, including contained pets.
    // Do not substitute the holder-resolving position used by item-sheet Follow.
    static_assert(offsetof(df::item,pos)==8);
    ItemPetRow result{*caption,{4,4,1},item->pos};
    // PET branch142b751..142b7af supplies this exact native activity caption.
    const auto* base=reinterpret_cast<const char*>(GetModuleHandleW(nullptr));
    result.activity.assign(base+0x1787218,12);
    // Native item-name renderer1423fe0 requests setDisplayColor(0). The PET
    // implementation only exposes a drawing-global writer (c7b200/7022c0),
    // so project its pinned raw-color branches without invoking that writer.
    static_assert(offsetof(df::item_critter,race)==0xb8 && offsetof(df::item_critter,caste)==0xba);
    static_assert(offsetof(df::creature_raw,color)==0x138 && offsetof(df::caste_raw,caste_color)==0x46e);
    const auto& raws=df::global::world->raws.creatures.all;
    if(pet->race>=0 && size_t(pet->race)<raws.size() && raws[pet->race]) {
        const auto* raw=raws[pet->race];result.color=raw->color;
        if(pet->caste>=0 && size_t(pet->caste)<raw->caste.size() && raw->caste[pet->caste] &&
           raw->caste[pet->caste]->flags.is_set(df::caste_raw_flags::HAS_COLOR))result.color=raw->caste[pet->caste]->caste_color;
        if(result.color[0]==result.color[1])result.color[2]=1;
    }
    return result;
}
}
