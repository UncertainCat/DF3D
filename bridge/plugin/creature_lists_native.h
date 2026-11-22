#pragma once
#include "residents_query_native.h"
#include "df/item.h"
#include "df/items_other_id.h"
#include <functional>

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
            {0x3d61d0,0x1a6,UINT64_C(0x9eee6bd498307371)},
            {0x142fba0,0x179,UINT64_C(0x5f2345a9a3831db1)},
            {0x1430780,0x10a,UINT64_C(0x6d84bb0b27132b35)},
            {0x1430890,0x10c,UINT64_C(0x33c2a3c859a97d4e)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
// The native item-row builder does not populate the activity map. Keep item
// keys absent, rather than inventing an activity string for search or sorting.
inline std::optional<std::vector<CreatureIdentity>> orderedCreatures(int tab,int sort,bool descending,std::string query={}) {
    if(tab<0 || tab>3 || sort<0 || sort>5 || sort==3 || (sort==5 && tab!=1) || !df::global::world || !creatureListsSupported() || !querySupported())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Predicate=bool (*)(void*,const CreatureReference*);
    using Compare=bool (*)(void*,const CreatureReference*,const CreatureReference*);
    constexpr size_t filters[]={0x3d5df0,0x3d5cc0,0x3d5860,0x3d55e0};
    constexpr size_t comparators[]={0x1431370,0x1435a10,0x14358c0,0,0x1434030,0x3d61d0};
    const auto excluded=reinterpret_cast<Predicate>(const_cast<uint8_t*>(base+filters[tab]));
    const auto compare=reinterpret_cast<Compare>(const_cast<uint8_t*>(base+comparators[sort]));
    const auto filtered=reinterpret_cast<Predicate>(const_cast<uint8_t*>(base+0x1424c30));
    detail::QueryContext context;
    context.query=std::move(query);df3d_area::staffOrderingFunctions().normalize(&context.query);
    auto* contextPointer=&context;
    const bool needsActivity=sort==4 || !context.query.empty();
    std::vector<CreatureReference> entries;
    for(auto* unit:df::global::world->units.active) {
        if(!unit)continue;
        CreatureReference entry{};entry.unit=unit;
        if(excluded(nullptr,&entry))continue;
        if(needsActivity) {
            const auto activity=activityText(unit);if(!activity)return std::nullopt;
            context.activities.emplace(detail::Entry{unit},activity->key);
        }
        if(!filtered(&contextPointer,&entry))entries.push_back(entry);
    }
    for(auto* item:df::global::world->items.other[df::items_other_id::ANY_CRITTER]) {
        if(!item)continue;
        CreatureReference entry{};entry.item=item;entry.kind=1;
        if(!excluded(nullptr,&entry) && !filtered(&contextPointer,&entry))entries.push_back(entry);
    }
    if(sort==5 && !entries.empty()) {
        // Native142c4b0 selects these forward/reverse sorting implementations.
        // Slaughterability is not a strict ordering: never give its comparator
        // to a C++ standard algorithm with stricter preconditions.
        using Function=std::function<bool(const CreatureReference&,const CreatureReference&)>;
        static_assert(sizeof(Function)==64);
        Function predicate=[&](const auto& a,const auto& b){return compare(nullptr,&a,&b);};
        auto* first=entries.data();auto* last=first+entries.size();
        if(descending) {
            // Native wrapper takes ownership of its by-value function copy.
            using Reverse=void (*)(CreatureReference*,CreatureReference*,Function);
            reinterpret_cast<Reverse>(const_cast<uint8_t*>(base+0x142fba0))(last,first,predicate);
        } else if(entries.size()<=32) {
            using Insertion=void (*)(CreatureReference*,CreatureReference*,Function*);
            reinterpret_cast<Insertion>(const_cast<uint8_t*>(base+0x1430780))(first,last,&predicate);
        } else {
            std::vector<CreatureReference> scratch((entries.size()+1)/2);
            using Merge=void (*)(CreatureReference*,CreatureReference*,int64_t,CreatureReference*,int64_t,Function*);
            reinterpret_cast<Merge>(const_cast<uint8_t*>(base+0x1430890))(first,last,int64_t(entries.size()),scratch.data(),int64_t(scratch.size()),&predicate);
        }
    } else std::stable_sort(entries.begin(),entries.end(),[&](const auto& a,const auto& b) {
        return descending?compare(&contextPointer,&b,&a):compare(&contextPointer,&a,&b);
    });
    std::vector<CreatureIdentity> result;result.reserve(entries.size());
    for(const auto& entry:entries)result.push_back({entry.kind,entry.kind==0?entry.unit->id:entry.item->id});
    return result;
}
}
