#pragma once
#include "building_item_native.h"
#include "knowledge_detail_native.h"
#include "unit_room_native.h"
#include "df/world.h"
#include "df/plotinfost.h"
#include "df/specific_ref.h"
#include "df/stocks_interfacest.h"
#include <array>
#include <cstddef>

namespace df3d_stocks {
// Native Stocks initializer377fe0 enumerates IN_PLAY and excludes c93160.
// Use only its semantic predicate: never call that menu initializer or touch
// item.temporary_32/base_uniform_score. Returned IDs retain simulation order;
// native Stocks sorting/grouping is a separate operation.
inline std::optional<std::vector<int32_t>> inventory() {
    static const auto predicate=[]()->bool (*)(df::item*) {
        if(!df3d_production::farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xc93160,0x213,UINT64_C(0x07d957dea30ed105)},
            {0xc93060,0xf2,UINT64_C(0xaa1dff2bbdba178e)},
            {0x137bd50,0x2d0,UINT64_C(0xdee22d5bacd12bc9)},
            {0x1367430,0xc6,UINT64_C(0xc0292be8a6dacf2c)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
            {0xc8be10,0x14c,UINT64_C(0x1ba19b485a3fa56b)},
            {0xc8baa0,0x11a,UINT64_C(0x2c62fce4a0555c66)},
            {0xedfa60,0xbd,UINT64_C(0x2f89116df6b958cc)},
            {0xedfb20,0x13,UINT64_C(0xa222e60f2f8301e4)},
            {0x14db50,0xb1,UINT64_C(0x4b9c987ca0656b35)},
            {0x14dc10,0x5a,UINT64_C(0xfb6e6c7bccbf765b)},
            {0x67270,6,UINT64_C(0x7dce27ae257f083d)},
            {0x7a840,6,UINT64_C(0xeff4222c8d49c252)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return nullptr;}
        return reinterpret_cast<bool (*)(df::item*)>(base+0xc93160);
    }();
    if(!predicate || !df::global::world)return std::nullopt;
    const auto& items=df::global::world->items.other.IN_PLAY;
    if(items.size()>1048576)return std::nullopt; // Bound owned diagnostic output.
    std::vector<int32_t> ids;ids.reserve(items.size());
    for(auto* item:items){if(!item)return std::nullopt;if(!predicate(item))ids.push_back(item->id);}
    return ids;
}
struct Totals {std::array<int32_t,113> stored{},unavailable{};};
inline std::optional<Totals> totals() {
    const auto ids=inventory();if(!ids)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    // This native initializer block has inline flag/count orchestration, no
    // standalone total provider. Pin it and call its semantic dependencies;
    // omit its temporary_32 writes and all unrelated menu initialization.
    static const bool supported=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0xbe;++i){hash^=base[0x378251+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xe285ee0a05b6aafe);
    }();
    if(!supported)return std::nullopt;
    Totals result;
    for(auto id:*ids) {
        auto* item=df::item::find(id);if(!item)return std::nullopt;
        bool available=(item->flags.whole&0xe88f10)==0;
        if(available && (item->flags.whole&8)) {
            df::specific_ref holder;holder.type=df::specific_ref_type(-1);
            reinterpret_cast<void (*)(df::item*,df::specific_ref*,bool)>(base+0xc8be10)(item,&holder,true);
            if(int32_t(holder.type)==1) {
                if(!holder.data.unit)return std::nullopt;
                available=reinterpret_cast<bool (*)(df::unit*)>(base+0x138ed20)(holder.data.unit);
            }
        }
        const auto type=int32_t(item->getType());
        if(type<0 || type>=int32_t(result.stored.size()))return std::nullopt;
        auto& value=(available && !(item->flags.whole&0x20)?result.stored:result.unavailable)[type];
        // DF's native ADD is a 32-bit operation.
        value=int32_t(uint32_t(value)+uint32_t(item->getStackSize()));
    }
    return result;
}
// Native introsort swaps only the supplied pointer array. Its comparator reads
// type/subtype/material and native item value with null unit/trade contexts.
// The accepted valuation graph may lazily initialize semantic furnishing art;
// no item temporary_32 or native Stocks storage participates in sorting.
inline std::optional<std::vector<int32_t>> orderedInventory() {
    const auto ids=inventory();if(!ids || !df3d_room::valuationReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x379b80,0x268,UINT64_C(0x50f0c651b3f19742)},
            {0x3ccfa0,0x22b,UINT64_C(0x90b54633c75db908)},
            {0x3d30c0,0x1e9,UINT64_C(0x4e56d0b547514068)},
            {0x3d3e50,0xfb,UINT64_C(0xf37cd84fb13f0ba2)},
            {0x3d3f50,0x236,UINT64_C(0x1d6fece73315218a)},
            {0xaca720,0x7a,UINT64_C(0x12b032d63e998c99)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!supported)return std::nullopt;
    std::vector<df::item*> owned;owned.reserve(ids->size());
    for(auto id:*ids){auto* item=df::item::find(id);if(!item)return std::nullopt;owned.push_back(item);}
    if(owned.size()>1)reinterpret_cast<void(*)(df::item**,df::item**,ptrdiff_t,uint8_t)>(base+0x3ccfa0)(owned.data(),owned.data()+owned.size(),ptrdiff_t(owned.size()),0);
    std::vector<int32_t> result;result.reserve(owned.size());
    for(const auto* item:owned)result.push_back(item->id);
    return result;
}
struct CategoryDisplay {int16_t type;std::string caption,stored,unavailable;};
// Native renderer3a1a5a..3a1d48 supplies the formatting arguments. Return
// type-indexed facts here; category filtering/order is a separate operation.
inline std::optional<std::vector<CategoryDisplay>> categoryDisplay() {
    const auto counts=totals();if(!counts || !df::global::plotinfo)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x3a1a5a,0x2ee,UINT64_C(0x3ec1254499b763ef)},
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x52d650,0x2b4,UINT64_C(0x9e8023d09def7af9)},
            {0x74f430,0x1d3,UINT64_C(0x79707f49e13c9401)},
            {0x52c2b0,0xd8,UINT64_C(0x38b6489e35387929)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    const auto& precision=df::global::plotinfo->nobles.bookkeeper_precision;
    if(!supported || reinterpret_cast<const uint8_t*>(&precision)!=base+0x23912ac)return std::nullopt;
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Describe=void(*)(std::string*,int16_t,int16_t,int16_t,int32_t,int32_t,int32_t,bool,void*,int32_t,int32_t,bool,int32_t,int32_t);
    const auto countCaption=[&](int32_t value,bool available) {
        if(!value)return std::string(available?"None":""); // Native3a1c13 literal; absent second row for zero.
        bool estimated=false;
        const auto rounded=reinterpret_cast<int32_t(*)(int32_t,int32_t,int32_t,bool*)>(base+0x74f430)(value,precision,0,&estimated);
        std::string text;reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c2b0)(rounded,&text);
        if(estimated)text.insert(text.begin(),'~'); // Native3a1b6f/3a1cf3.
        return text;
    };
    std::vector<CategoryDisplay> result;result.reserve(93);
    for(int16_t type=0;type<93;++type) {
        CategoryDisplay row;row.type=type;
        reinterpret_cast<Describe>(base+0xa82c10)(&row.caption,type,-1,-1,-1,-1,0,false,nullptr,-1,-1,true,0,0);
        reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&row.caption);
        row.stored=countCaption(counts->stored[type],true);row.unavailable=countCaption(counts->unavailable[type],false);
        result.push_back(std::move(row));
    }
    return result;
}
struct Group {int16_t type,subtype,subcat1,subcat2;int32_t amount;bool expanded;};
// Native ac9c30 owns no globals: abstract-list insertion/matching uses the
// supplied vectors and authoritative item properties/history. Keep all storage
// here, including MSVC's packed expanded bits; no stocks_interfacest is borrowed.
inline std::optional<std::vector<Group>> groups() {
    const auto ids=inventory();if(!ids)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xac9c30,0x50a,UINT64_C(0x7fbce42d6c033414)},
            {0xac9890,0x173,UINT64_C(0xc19090f1c488ecc4)},
            {0xac9710,0x17a,UINT64_C(0xcdf19b8b33e636a4)},
            {0xaca720,0x7a,UINT64_C(0x12b032d63e998c99)},
            {0x13bfd0,0xe8,UINT64_C(0xd4a98ca43e7cadb7)},
            {0x13c270,0x229,UINT64_C(0x09e5c9aa6e43d09c)},
            {0x13d4f0,0xed,UINT64_C(0xe857e2f78065b8b9)},
            {0x70e20,0x117,UINT64_C(0x09aba69f846f6c10)},
            {0x71040,0x112,UINT64_C(0x5f2ee621244a5576)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!supported)return std::nullopt;
    struct Context {
        std::vector<int16_t> type,subtype,subcat1,subcat2;
        std::vector<int32_t> amount;
        std::vector<bool> expanded;
    } owned;
    static_assert(offsetof(Context,amount)==0x60 && offsetof(Context,expanded)==0x78 && sizeof(Context)==0x98);
    const auto add=reinterpret_cast<void (*)(Context*,df::item*)>(base+0xac9c30);
    for(auto id:*ids){auto* item=df::item::find(id);if(!item)return std::nullopt;add(&owned,item);}
    const auto count=owned.type.size();
    if(owned.subtype.size()!=count || owned.subcat1.size()!=count || owned.subcat2.size()!=count ||
       owned.amount.size()!=count || owned.expanded.size()!=count)return std::nullopt;
    std::vector<Group> result;result.reserve(count);
    for(size_t i=0;i<count;++i)result.push_back({owned.type[i],owned.subtype[i],owned.subcat1[i],owned.subcat2[i],owned.amount[i],owned.expanded[i]});
    return result;
}
struct SelectedGroup {Group group;bool matches;uint32_t flags;std::vector<int32_t> ids;uint64_t revision=0;};
struct Selection {std::vector<int32_t> ids;std::vector<SelectedGroup> groups;};
inline std::optional<Selection> selection(int16_t type,std::string query) {
    if(type<0 || type>=93 || !df3d_production::buildingItemFunctions())return std::nullopt;
    const auto master=groups();const auto ordered=orderedInventory();
    if(!master || !ordered)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x37a3f0,0x244,UINT64_C(0xef3f1132a15cc649)},
            {0x37d350,0x3f7,UINT64_C(0x18775745ecd1c0e1)},
            {0x37dbc0,0x664,UINT64_C(0xa49043145cd7af75)},
            {0xa82c10,0x56ec,UINT64_C(0x66347214dfd39a0b)},
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
            {0xe1990,0xc7,UINT64_C(0x1c45e5635f4ffde2)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!supported)return std::nullopt;
    // Own every vector/string. Copy the initializer's type projection, then
    // call only filtering/flag aggregation, never its window-height tail.
    df::stocks_interfacest owned;owned.current_type=df::item_type(type);owned.item_filter=std::move(query);
    static_assert(offsetof(df::stocks_interfacest,current_type)==0x38);
    static_assert(offsetof(df::stocks_interfacest,item_filter)==0x48);
    static_assert(offsetof(df::stocks_interfacest,current_type_i_list)==0x158);
    static_assert(offsetof(df::stocks_interfacest,current_type_a_subtype)==0x170);
    static_assert(offsetof(df::stocks_interfacest,current_type_a_on)==0x1f0);
    static_assert(offsetof(df::stocks_interfacest,current_type_a_flag)==0x210);
    Selection result;
    for(const auto& group:*master)if(group.type==type) {
        owned.current_type_a_subtype.push_back(group.subtype);
        owned.current_type_a_subcat1.push_back(group.subcat1);
        owned.current_type_a_subcat2.push_back(group.subcat2);
        owned.current_type_a_amount.push_back(group.amount);
        owned.current_type_a_expanded.push_back(group.expanded);
        result.groups.push_back({group,false,0});
        owned.master_a_list.type.push_back(group.type);
        owned.master_a_list.subtype.push_back(group.subtype);
        owned.master_a_list.subcat1.push_back(group.subcat1);
        owned.master_a_list.subcat2.push_back(group.subcat2);
    }
    owned.current_type_a_on.resize(result.groups.size());
    owned.current_type_a_flag.resize(result.groups.size());
    for(auto id:*ordered){auto* item=df::item::find(id);if(!item)return std::nullopt;
        if(int16_t(item->getType())==type){
            owned.current_type_i_list.push_back(item);result.ids.push_back(id);
            // ac9890 is the already pinned native abstract-group matcher.
            // Keep the native individual order within each owned group.
            const auto index=reinterpret_cast<int32_t(*)(df::abstractitemlistst*,df::item*)>(base+0xac9890)(&owned.master_a_list,item);
            if(index<0 || size_t(index)>=result.groups.size())return std::nullopt;
            result.groups[index].ids.push_back(id);
        }}
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    reinterpret_cast<void(*)(df::stocks_interfacest*)>(base+0x37d350)(&owned);
    const auto& actions=df3d_production::buildingItemFunctions();
    for(size_t i=0;i<result.groups.size();++i){auto& row=result.groups[i];row.matches=owned.current_type_a_on[i];row.flags=owned.current_type_a_flag[i].whole;
        uint64_t hash=UINT64_C(14695981039346656037);
        const auto add=[&](uint64_t value){for(unsigned byte=0;byte<8;++byte){hash^=uint8_t(value>>(byte*8));hash*=UINT64_C(1099511628211);}};
        add(type);add(row.group.subtype);add(row.group.subcat1);add(row.group.subcat2);add(row.group.amount);
        for(auto id:row.ids){auto* item=df::item::find(id);if(!item)return std::nullopt;
            add(id);add(item->flags.whole);add(item->getStackSize());add(actions.canDump(item));add(actions.canMelt(item));
            add(item->stockpile_countdown);add(item->stockpile_delay);}
        row.revision=(hash&INT64_MAX);if(!row.revision)row.revision=1;
    }
    return result;
}
enum class EditOutcome {Rejected,Applied,Stale,Unknown};
// changed counts successful explicit native helper calls, not affected items:
// native forbid can propagate to related members before their loop iteration.
struct GroupEdit {EditOutcome outcome=EditOutcome::Rejected;uint32_t changed=0;std::optional<Selection> receipt;};
// Call at a safe point with session/epoch authority. Expected revision covers
// identity, complete membership, flags and native eligibility. Never replay an
// Unknown result: native helpers may have already applied part of the intent.
inline GroupEdit editGroup(const Group& key,uint64_t expected,df3d_production::BuildingItemAction action,bool desired) {
    using namespace df3d_production;
    GroupEdit result;bool entered=false;
    if(!expected || int(action)<0 || int(action)>3)return result;
    try {
        auto before=selection(key.type,"");if(!before)return result;
        const auto found=std::find_if(before->groups.begin(),before->groups.end(),[&](const SelectedGroup& row){
            return row.group.subtype==key.subtype && row.group.subcat1==key.subcat1 && row.group.subcat2==key.subcat2;});
        if(found==before->groups.end() || found->revision!=expected){result.outcome=EditOutcome::Stale;result.receipt=std::move(before);return result;}
        const auto& native=buildingItemFunctions();std::vector<df::item*> targets;
        for(auto id:found->ids){auto* item=df::item::find(id);if(!item)return result;
            if(action==BuildingItemAction::Dump && !native.canDump(item))continue;
            if(action==BuildingItemAction::Melt && !native.canMelt(item))continue;
            targets.push_back(item);}
        if(targets.empty()){result.receipt=std::move(before);return result;}
        for(auto* item:targets)if(buildingItemValue(item,action)!=desired){
            entered=true;result.outcome=EditOutcome::Unknown;
            if(!setBuildingItemFlag(item,action,desired))return result;
            ++result.changed;
        }
        result.receipt=selection(key.type,"");if(!result.receipt){if(entered)result.outcome=EditOutcome::Unknown;return result;}
        for(auto* item:targets)if(buildingItemValue(item,action)!=desired){result.outcome=EditOutcome::Unknown;return result;}
        result.outcome=EditOutcome::Applied;return result;
    }catch(...){result.outcome=entered?EditOutcome::Unknown:EditOutcome::Rejected;return result;}
}
// Category insertion is inline in the unsafe menu initializer. Preserve its
// seed permutation and lower-bound insertion (equal captions reverse seed
// order). Search37c070 delegates group naming, normalization and substring
// matching to native routines; omit its native-window scroll clamp entirely.
inline std::optional<std::vector<int16_t>> categories(std::string query) {
    auto display=categoryDisplay();if(!display)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x378360,0x15e2,UINT64_C(0x6dc10b2964dfb42d)},
            {0x37c070,0x315,UINT64_C(0x8c19eeb7c24eb770)},
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
            {0xe1990,0xc7,UINT64_C(0x1c45e5635f4ffde2)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!supported)return std::nullopt;
    const auto normalize=reinterpret_cast<void(*)(std::string*)>(base+0x52cee0);
    for(auto& row:*display)normalize(&row.caption);
    constexpr int16_t seed[]={48,49,50,88,54,72,71,70,69,56,73,75,53,24,39,25,60,28,29,26,27,61,62,45,33,34,35,6,7,8,9,20,21,22,87,55,58,57,90,5,4,3,0,1,44,74,2,52,51,77,78,79,80,81,15,19,10,16,30,31,32,17,18,67,68,11,12,14,86,13,36,37,38,40,41,42,43,63,64,92,65,66,59,23,46,47,76,82,83,84,85,89,91};
    std::vector<int16_t> ordered;ordered.reserve(93);
    for(auto type:seed){auto at=ordered.begin();
        while(at!=ordered.end() && (*display)[*at].caption.compare((*display)[type].caption)<0)++at;
        ordered.insert(at,type);}
    if(query.empty())return ordered;
    const auto grouped=groups();if(!grouped)return std::nullopt;
    normalize(&query);std::array<bool,93> matches{};
    df3d_creature::KnowledgeMaterialCacheRestore restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Describe=void(*)(std::string*,int16_t,int16_t,int16_t,int32_t,int32_t,int32_t,bool,void*,int32_t,int32_t,bool,int32_t,int32_t);
    using Find=size_t(*)(const char*,size_t,size_t,const char*,size_t);
    for(const auto& group:*grouped) {
        if(group.type<0 || group.type>=93)return std::nullopt;
        std::string caption;
        reinterpret_cast<Describe>(base+0xa82c10)(&caption,group.type,group.subtype,group.subcat1,group.subcat2,group.amount,0,false,nullptr,-1,-1,true,0,0);
        normalize(&caption);
        if(reinterpret_cast<Find>(base+0xe1990)(caption.data(),caption.size(),0,query.data(),query.size())!=size_t(-1))matches[group.type]=true;
    }
    ordered.erase(std::remove_if(ordered.begin(),ordered.end(),[&](int16_t type){return !matches[type];}),ordered.end());
    return ordered;
}
}
