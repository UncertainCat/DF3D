#pragma once
#include <cstddef>
#include <unordered_map>
#include "residents_activity_native.h"

namespace df3d_residents {
inline bool querySupported() {
    static const bool ready=[] {
        if(!activitySupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x3c9c30,0xe7,UINT64_C(0x3eae3e81c7aa002f)},
            {0x1434030,0x147,UINT64_C(0x565cf7a95087765f)},
            {0x1424c30,0x218,UINT64_C(0x14952fd1a693777f)},
            {0xb9d50,0x69,UINT64_C(0x979704ba6b6743e5)},
            {0xe1990,0xc7,UINT64_C(0x1c45e5635f4ffde2)},
            {0x1432700,0xdb,UINT64_C(0x57f864182614b0c0)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}

namespace detail {
using Entry=df3d_area::StaffUnitReference;
struct EntryHash {
    size_t operator()(const Entry& entry) const noexcept {
        using Hash=size_t (*)(void*,const Entry*);
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        return reinterpret_cast<Hash>(const_cast<uint8_t*>(base+0x3c9c30))(nullptr,&entry);
    }
};
struct EntryEqual {
    bool operator()(const Entry& a,const Entry& b) const noexcept {return a.kind==b.kind && a.unit==b.unit;}
};
using ActivityMap=std::unordered_map<Entry,std::string,EntryHash,EntryEqual>;
// Only these two fields are consumed by 1434030/1424c30. This is independently
// constructed storage, not a widget: it has no vtable, callbacks or menu state.
// MSVC's empty hash/equality objects preserve the native map ABI. Keys are
// 16-byte tagged references; the generated XML's pointer-only key is incorrect.
struct QueryContext {
    std::array<std::byte,0x330> prefix{};
    ActivityMap activities;
    std::array<std::byte,0x680-0x330-sizeof(ActivityMap)> middle{};
    std::string query;
};
static_assert(sizeof(ActivityMap)==0x40);
static_assert(offsetof(QueryContext,activities)==0x330);
static_assert(offsetof(QueryContext,query)==0x680);
}

// Sorts 0..3 retain the ordering provider's identifiers; 4 is Activity.
// query contains native textbox bytes (UTF-8 from window text events, without
// CP437 conversion). Callback1432700 normalizes those bytes before storing
// filter_str; use that same native normalizer, including its accent behavior.
inline std::optional<std::vector<int32_t>> queryResidents(int sort,bool descending,std::string query) {
    if(sort<0 || sort>4 || !df::global::world || !querySupported())return std::nullopt;
    if(sort<4 && query.empty())return orderedResidents(sort,descending);
    using Entry=detail::Entry;
    using Predicate=bool (*)(void*,const Entry*);
    using Compare=bool (*)(void*,const Entry*,const Entry*);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto excluded=reinterpret_cast<Predicate>(const_cast<uint8_t*>(base+0x3d5df0));
    const auto filtered=reinterpret_cast<Predicate>(const_cast<uint8_t*>(base+0x1424c30));
    constexpr size_t comparators[]={0x1431370,0x1435a10,0x14358c0,0x1435ed0,0x1434030};
    const auto compare=reinterpret_cast<Compare>(const_cast<uint8_t*>(base+comparators[sort]));
    detail::QueryContext context;
    context.query=std::move(query);df3d_area::staffOrderingFunctions().normalize(&context.query);
    auto* contextPointer=&context;
    std::vector<Entry> entries;
    for(auto* unit:df::global::world->units.active) {
        if(!unit)continue;
        Entry entry{unit};if(excluded(nullptr,&entry))continue;
        const auto activity=activityText(unit);if(!activity)return std::nullopt;
        context.activities.emplace(entry,activity->key);
        if(!filtered(&contextPointer,&entry))entries.push_back(entry);
    }
    std::stable_sort(entries.begin(),entries.end(),[&](const Entry& a,const Entry& b) {
        return descending?compare(&contextPointer,&b,&a):compare(&contextPointer,&a,&b);
    });
    std::vector<int32_t> ids;ids.reserve(entries.size());
    for(const auto& entry:entries)ids.push_back(entry.unit->id);
    return ids;
}
}
