#pragma once
#include "standing_orders_native.h"
#include "df/item.h"
#include "df/items_other_id.h"
#include "df/material.h"
#include "df/labor_kitchen_interface_food_key.h"
#include "df/labor_kitchen_interface_food_value.h"
#include <cstddef>
#include <unordered_map>
#include <vector>

namespace df3d_kitchen {
inline uint8_t* supportedBase() {
    auto* base=df3d_standing::supportedBase();
    if(!base)return nullptr;
    static const bool valid=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x42af10,0x3d3,UINT64_C(0xe342cfb2854b06d3)},
            {0x4308da,0x160,UINT64_C(0x649be87310c97ecc)},
            {0xc8b600,0x3b5,UINT64_C(0x203cf49bf5ce17fb)},
            {0x6b8af0,0x96,UINT64_C(0x8f67f7a1b9d42698)},
            {0x466210,0xb9,UINT64_C(0x5812acac3977a744)},
            {0x14add70,0x12f,UINT64_C(0x01f897b15772d540)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    return valid?base:nullptr;
}
using Key=df::labor_kitchen_interface_food_key;
using Value=df::labor_kitchen_interface_food_value;
struct NativeHash {
    size_t operator()(const Key& key) const noexcept {
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        return reinterpret_cast<size_t(*)(void*,const Key*)>(base+0x466210)(nullptr,&key);
    }
};
using Map=std::unordered_map<Key,Value,NativeHash>;
// Only the map is accessed by42af10. No widget, callbacks, menu or vtable are
// constructed. Native allocation and our Release MSVC STL share the process CRT.
struct Context {std::array<std::byte,0x180> prefix{};Map known;};
static_assert(sizeof(Key)==12 && sizeof(Value)==40 && sizeof(Map)==64);
static_assert(offsetof(Context,known)==0x180);
struct Row {int16_t type,subtype,material;int32_t materialIndex,count;uint8_t capabilities;std::string name;};
inline std::optional<std::vector<Row>> read() {
    auto* base=supportedBase();
    if(!base || !df::global::world || !df::global::plotinfo)return std::nullopt;
    const auto& items=df::global::world->items.other[df::items_other_id::ANY_COOKABLE];
    if(reinterpret_cast<const uint8_t*>(&items)!=base+0x23e5c60 || items.size()>2000000)return std::nullopt;
    Context owned;
    const std::string drink="DRINK_MAT";
    for(auto* item:items) {
        if(!item)return std::nullopt;
        // Native430900..430a0d: native cookability or native drink-product
        // membership, followed by the exact inline screen eligibility mask.
        bool eligible=reinterpret_cast<bool(*)(df::item*,bool,bool,bool)>(base+0xc8b600)(item,false,false,false);
        const auto type=item->getType();
        if(!eligible && (type==df::item_type::PLANT || type==df::item_type::PLANT_GROWTH)) {
            auto* material=reinterpret_cast<df::material*(*)(df::world*,int16_t,int32_t)>(base+0x14add70)(df::global::world,item->getActualMaterial(),item->getActualMaterialIndex());
            if(material) {
                if(reinterpret_cast<uint8_t*>(&material->reaction_product.id)!=reinterpret_cast<uint8_t*>(material)+0x350)return std::nullopt;
                eligible=reinterpret_cast<bool(*)(const std::vector<std::string*>*,const std::string*)>(base+0x6b8af0)(&material->reaction_product.id,&drink);
            }
        }
        if(!eligible || (item->flags.whole&0xe98f30u) || (item->flags2.whole&8u))continue;
        reinterpret_cast<void(*)(Context*,df::item*)>(base+0x42af10)(&owned,item);
        if(owned.known.size()>65536)return std::nullopt;
    }
    std::vector<Row> result;result.reserve(owned.known.size());
    for(const auto& [key,value]:owned.known) {
        if(value.num<0 || value.canrest<1 || value.canrest>3 || value.name.empty() || value.name.size()>4096)return std::nullopt;
        result.push_back({int16_t(key.type),key.subtype,key.mat,key.matg,value.num,uint8_t(value.canrest),value.name});
    }
    return result;
}
} // namespace df3d_kitchen
