#pragma once
#include "standing_orders_native.h"
#include "df/item.h"
#include "df/items_other_id.h"
#include "df/material.h"
#include "modules/Materials.h"
#include "df/labor_kitchen_interface_food_key.h"
#include "df/labor_kitchen_interface_food_value.h"
#include <cstddef>
#include <functional>
#include <tuple>
#include <unordered_map>
#include <vector>

namespace df3d_kitchen {
inline uint8_t* supportedBase() {
    auto* base=df3d_standing::supportedBase();
    if(!base)return nullptr;
    static const bool valid=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x74f430,0x1d3,UINT64_C(0x79707f49e13c9401)},
            {0x52c2b0,0xd8,UINT64_C(0x38b6489e35387929)},
            {0xac8410,0x77,UINT64_C(0x167ebc614e92ed22)},
            {0xac8280,0x18d,UINT64_C(0x4ce7454087c59262)},
            {0xac7d10,0x570,UINT64_C(0xa95d2149d15941b7)},
            {0x46ce00,0xb,UINT64_C(0xba3c8c9dddb60ecc)},
            {0x46c820,0xb,UINT64_C(0x42dd9776fe0477d1)},
            {0x46c7e0,0x1c,UINT64_C(0x3c461622eb61e886)},
            {0x46c730,0x85,UINT64_C(0x5a62d9f04fdd4896)},
            {0x46c680,0x89,UINT64_C(0x0cbda71fe11edd37)},
            {0xac7c30,0xd6,UINT64_C(0xebcb8225555d9695)},
            {0x465970,0x17f,UINT64_C(0x608660a3f97cf2aa)},
            {0x465af0,0x17f,UINT64_C(0x6f3db96bf1940708)},
            {0x430d50,0x1d8,UINT64_C(0x10096dbd8f590e8c)},
            {0x46c850,0x5d,UINT64_C(0x8bb528f17939950b)},
            {0x52cee0,0x19e,UINT64_C(0xc25c2d8a6eb9fcac)},
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
struct Filter {int8_t type=-1;uint8_t capabilities=0;std::string query;};
enum class Column:uint8_t {Type,Name,Number,Cook,Brew};
struct Sort {Column column=Column::Type;bool reverse=false;};
struct FilterContext {
    std::array<std::byte,0x230> prefix{};
    std::string query;
    int8_t type=-1;
    uint8_t capabilities=0;
};
struct FilterCallable {void* unused=nullptr;FilterContext* context;};
struct Entry {Key key;Value value;};
static_assert(offsetof(FilterContext,query)==0x230 && offsetof(FilterContext,type)==0x250);
static_assert(offsetof(Entry,value)==0x10 && sizeof(Entry)==0x38);
inline std::optional<std::vector<Row>> read(const Filter& filter={},const std::vector<Sort>& sorts={{}}) {
    auto* base=supportedBase();
    if(!base || !df::global::world || !df::global::plotinfo)return std::nullopt;
    if(filter.type<-1 || filter.type>3 || filter.capabilities>3 || filter.query.size()>4096)return std::nullopt;
    if(sorts.empty() || sorts.size()>65536)return std::nullopt;
    uint8_t used=0,reversed=0;
    for(const auto& sort:sorts){const auto id=static_cast<uint8_t>(sort.column);if(id>4)return std::nullopt;
        const auto bit=1u<<id;if((used&bit) && bool(reversed&bit)!=sort.reverse)return std::nullopt;
        used|=bit;if(sort.reverse)reversed|=bit;}
    const auto& exclusions=df::global::plotinfo->kitchen;
    const auto size=exclusions.item_types.size();
    if(size>65536 || exclusions.item_subtypes.size()!=size || exclusions.mat_types.size()!=size || exclusions.mat_indices.size()!=size || exclusions.exc_types.size()!=size)return std::nullopt;
    FilterContext selection;selection.query=filter.query;selection.type=filter.type;selection.capabilities=filter.capabilities;
    reinterpret_cast<void(*)(std::string*)>(base+0x52cee0)(&selection.query);
    FilterCallable callable{nullptr,&selection};
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
    std::vector<Entry> entries;entries.reserve(owned.known.size());
    for(const auto& [key,value]:owned.known) {
        if(value.num<0 || value.canrest<1 || value.canrest>3 || value.name.empty() || value.name.size()>4096)return std::nullopt;
        // The wrapper moves the copied string into the by-value predicate,
        // which destroys that copy. The original map entry remains owned here.
        Entry copy{key,value};
        if(reinterpret_cast<bool(*)(FilterCallable*,Entry*)>(base+0x46c850)(&callable,&copy))continue;
        entries.push_back({key,value});
    }
    // Native431ea0 applies priorities from last to first. Both sort entry
    // points operate only on owned entries and consume the copied callable.
    using Comparator=std::function<bool(const Entry&,const Entry&)>;
    static_assert(sizeof(Comparator)==64);
    constexpr size_t comparators[]={0x46c820,0x46c7e0,0x46ce00,0x46c730,0x46c680};
    if(entries.size()>1)for(auto it=sorts.rbegin();it!=sorts.rend();++it){
        const auto compare=reinterpret_cast<bool(*)(void*,const Entry*,const Entry*)>(base+comparators[static_cast<uint8_t>(it->column)]);
        Comparator callable=[compare](const Entry& a,const Entry& b){return compare(nullptr,&a,&b);};
        auto* first=entries.data();auto* last=first+entries.size();
        const auto sort=reinterpret_cast<void(*)(Entry*,Entry*,Comparator*)>(base+(it->reverse?0x465970:0x465af0));
        sort(it->reverse?last:first,it->reverse?first:last,&callable);
    }
    std::vector<Row> result;result.reserve(entries.size());
    for(const auto& entry:entries){const auto& key=entry.key;const auto& value=entry.value;
        result.push_back({int16_t(key.type),key.subtype,key.mat,key.matg,value.num,uint8_t(value.canrest),value.name});}
    return result;
}
struct Exclusion {
    int16_t type,subtype,material;int32_t materialIndex;uint8_t flags;
    bool operator==(const Exclusion& b)const{return std::tie(type,subtype,material,materialIndex,flags)==std::tie(b.type,b.subtype,b.material,b.materialIndex,b.flags);}
};
struct Display {std::string countCaption;bool estimated=false;uint8_t excluded=0;std::string materialToken;};
inline std::optional<std::vector<Display>> display(const std::vector<Row>& rows) {
    auto* base=supportedBase();if(!base || !df::global::plotinfo || rows.size()>65536)return std::nullopt;
    const auto& precision=df::global::plotinfo->nobles.bookkeeper_precision;
    if(reinterpret_cast<const uint8_t*>(&precision)!=base+0x23912ac || base[0x1614d50]!='?')return std::nullopt;
    const auto& k=df::global::plotinfo->kitchen;const auto n=k.item_types.size();
    if(n>65536 || k.item_subtypes.size()!=n || k.mat_types.size()!=n || k.mat_indices.size()!=n || k.exc_types.size()!=n)return std::nullopt;
    std::vector<Display> result;result.reserve(rows.size());
    for(const auto& row:rows){
        if(row.count<0)return std::nullopt;
        Display value;
        DFHack::MaterialInfo material(row.material,row.materialIndex);
        if(!material.isValid())return std::nullopt;
        value.materialToken=material.getToken();
        if(value.materialToken.empty() || value.materialToken.size()>256)return std::nullopt;
        reinterpret_cast<int32_t(*)(int32_t,int32_t,int32_t,bool*)>(base+0x74f430)(row.count,precision,0,&value.estimated);
        // Kitchen431545..431571 deliberately formats the original count,
        // unlike material pickers that format the returned rounded estimate.
        reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c2b0)(row.count,&value.countCaption);
        if(value.estimated)value.countCaption.append(reinterpret_cast<const char*>(base+0x1614d50),1);
        value.excluded=reinterpret_cast<uint8_t(*)(void*,int16_t,int16_t,int16_t,int32_t)>(base+0xac7c30)(nullptr,row.type,row.subtype,row.material,row.materialIndex);
        if(value.excluded>3 || value.countCaption.empty() || value.countCaption.size()>64)return std::nullopt;
        result.push_back(std::move(value));
    }
    return result;
}
inline std::optional<std::vector<Exclusion>> exclusions() {
    auto* base=supportedBase();if(!base || !df::global::plotinfo)return std::nullopt;
    const auto& k=df::global::plotinfo->kitchen;const auto n=k.item_types.size();
    if(reinterpret_cast<const uint8_t*>(&k.item_types)!=base+0x23935d8 || n>65536 ||
       k.item_subtypes.size()!=n || k.mat_types.size()!=n || k.mat_indices.size()!=n || k.exc_types.size()!=n)return std::nullopt;
    std::vector<Exclusion> result;result.reserve(n);
    for(size_t i=0;i<n;++i){if(k.exc_types[i].whole<0 || k.exc_types[i].whole>3)return std::nullopt;
        result.push_back({int16_t(k.item_types[i]),k.item_subtypes[i],k.mat_types[i],k.mat_indices[i],uint8_t(k.exc_types[i].whole)});}
    return result;
}
enum class Outcome {Rejected=0,Applied=1,Stale=2};
// A click toggles one native permission. Revalidate the complete exclusion
// receipt and target availability before the first write. Never replay Unknown.
inline Outcome apply(const Row& target,uint8_t flag,const std::vector<Exclusion>& expected,bool* writeStarted=nullptr) {
    if(flag!=1 && flag!=2)return Outcome::Rejected;
    const auto before=exclusions();if(!before)return Outcome::Rejected;
    if(*before!=expected)return Outcome::Stale;
    const auto rows=read();if(!rows)return Outcome::Rejected;
    const Row* current=nullptr;
    for(const auto& row:*rows)if(std::tie(row.type,row.subtype,row.material,row.materialIndex)==std::tie(target.type,target.subtype,target.material,target.materialIndex)){current=&row;break;}
    if(!current || current->count!=target.count || current->capabilities!=target.capabilities)return Outcome::Stale;
    if(!(current->capabilities&flag))return Outcome::Rejected;
    auto* base=supportedBase();
    if(writeStarted)*writeStarted=true;
    // The first parameter is unused by the native toggle/remove/add chain.
    // Native add performs job/reagent handling; direct vector edits omit it.
    reinterpret_cast<void(*)(void*,int16_t,int16_t,int16_t,int32_t,uint8_t)>(base+0xac8410)(nullptr,target.type,target.subtype,target.material,target.materialIndex,flag);
    return Outcome::Applied;
}
} // namespace df3d_kitchen
