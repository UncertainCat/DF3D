#pragma once
#include "residents_order_native.h"
#include "df/item.h"
#include "df/items_other_id.h"

namespace df3d_residents {
// Semantic tagged references, owned by this call. Native predicates read world
// state but never a native widget/menu. Items are small creatures, not units.
struct CreatureReference {
    union {df::unit* unit;df::item* item;};
    uint8_t kind=0;
    uint8_t padding[7]{};
};
static_assert(sizeof(CreatureReference)==16);
struct CreatureIdentity {int32_t kind,id;};
inline bool creatureListsSupported() {
    static const bool ready=[] {
        if(!orderingSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x3d5cc0,0x10a,UINT64_C(0x7aae555640ea0f4e)},
            {0x3d5860,0xb5,UINT64_C(0xdc4ac09e0dc50da0)},
            {0x3d55e0,0x1b,UINT64_C(0x1ae8d4d3571c6cf8)},
            {0x3ccc30,0x1cc,UINT64_C(0x13614ddde97c9919)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
// Initial-list diagnostic: search, activity sorting and animal actions have
// separate ownership requirements and are not supplied by this entry point.
inline std::optional<std::vector<CreatureIdentity>> orderedCreatures(int tab,int sort,bool descending) {
    if(tab<0 || tab>3 || sort<0 || sort>2 || !df::global::world || !creatureListsSupported())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Predicate=bool (*)(void*,const CreatureReference*);
    using Compare=bool (*)(void*,const CreatureReference*,const CreatureReference*);
    constexpr size_t filters[]={0x3d5df0,0x3d5cc0,0x3d5860,0x3d55e0};
    constexpr size_t comparators[]={0x1431370,0x1435a10,0x14358c0};
    const auto excluded=reinterpret_cast<Predicate>(const_cast<uint8_t*>(base+filters[tab]));
    const auto compare=reinterpret_cast<Compare>(const_cast<uint8_t*>(base+comparators[sort]));
    std::vector<CreatureReference> entries;
    for(auto* unit:df::global::world->units.active) {
        if(!unit)continue;
        CreatureReference entry{};entry.unit=unit;
        if(!excluded(nullptr,&entry))entries.push_back(entry);
    }
    for(auto* item:df::global::world->items.other[df::items_other_id::ANY_CRITTER]) {
        if(!item)continue;
        CreatureReference entry{};entry.item=item;entry.kind=1;
        if(!excluded(nullptr,&entry))entries.push_back(entry);
    }
    std::stable_sort(entries.begin(),entries.end(),[&](const auto& a,const auto& b) {
        return descending?compare(nullptr,&b,&a):compare(nullptr,&a,&b);
    });
    std::vector<CreatureIdentity> result;result.reserve(entries.size());
    for(const auto& entry:entries)result.push_back({entry.kind,entry.kind==0?entry.unit->id:entry.item->id});
    return result;
}
}
