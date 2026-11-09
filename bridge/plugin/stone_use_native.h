#pragma once
#include "standing_orders_native.h"
#include "df/plotinfost.h"
#include <cstddef>

namespace df3d_stone_use {
inline uint8_t* supportedBase() {
    auto* base=df3d_standing::supportedBase();
    if(!base)return nullptr;
    static const bool valid=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x434b8a,0x2a,UINT64_C(0x5f0bf376df3ff178)},
            {0x432450,0xaff,UINT64_C(0x051b891c44236820)},
            {0xd97510,0x790,UINT64_C(0xe3752bf787a64fef)},
            {0xbb9b0,0x74,UINT64_C(0x7532991bab65be09)},
            {0x14add70,0x12f,UINT64_C(0x01f897b15772d540)},
            {0x14d1920,0x459,UINT64_C(0xf48e28715360ed9a)},
            {0x52d650,0x273,UINT64_C(0x76b7340f0d7d3264)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    return valid?base:nullptr;
}
// Native432450 accesses only these data vectors. No widget, vtable, native
// menu, input or graphics cache is supplied. The restriction pointers refer
// to authoritative settings and are validated before dereference, never kept.
struct Context {
    std::array<std::byte,0x150> prefix{};
    int32_t category=0,alignment=0;
    std::array<std::vector<int32_t>,2> indices;
    std::array<std::vector<char*>,2> restrictions;
    std::vector<std::string*> descriptions;
    uint8_t* base;
    explicit Context(uint8_t* value):base(value){}
    ~Context(){reinterpret_cast<void(*)(void*)>(base+0xbb9b0)(&descriptions);}
    Context(const Context&)=delete;
    Context& operator=(const Context&)=delete;
};
static_assert(offsetof(Context,indices)==0x158 && offsetof(Context,restrictions)==0x188);
static_assert(offsetof(Context,descriptions)==0x1b8);
struct Row {int32_t category,index;bool restricted;std::string name,uses;};
inline std::optional<std::vector<Row>> read() {
    auto* base=supportedBase();
    if(!base || !df::global::world || !df::global::plotinfo)return std::nullopt;
    const auto& flags=df::global::plotinfo->economic_stone;
    if(flags.size()>65536)return std::nullopt;
    Context owned(base);
    reinterpret_cast<void(*)(void*)>(base+0x432450)(&owned);
    if(owned.descriptions.size()!=owned.indices[0].size())return std::nullopt;
    std::vector<Row> result;
    for(int32_t category=0;category<2;++category){
        if(owned.indices[category].size()!=owned.restrictions[category].size() || owned.indices[category].size()>flags.size())return std::nullopt;
        for(size_t i=0;i<owned.indices[category].size();++i){
            const int32_t index=owned.indices[category][i];
            if(index<0 || size_t(index)>=flags.size() || owned.restrictions[category][i]!=&flags[index] || (flags[index]!=0 && flags[index]!=1))return std::nullopt;
            auto* material=reinterpret_cast<uint8_t*(*)(void*,int16_t,int32_t)>(base+0x14add70)(df::global::world,0,index);
            if(!material)return std::nullopt;
            // Native43899c prefers the material's stone caption at60, then
            // calls the general native formatter for the inorganic identity.
            std::string name=*reinterpret_cast<const std::string*>(material+0x60);
            if(name.empty())reinterpret_cast<void(*)(void*,std::string*,int16_t,int32_t,int32_t,bool,int16_t)>(base+0x14d1920)(df::global::world,&name,0,index,0,false,0);
            reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&name);
            if(name.empty() || name.size()>16384)return std::nullopt;
            std::string uses;
            if(category==0){if(!owned.descriptions[i] || owned.descriptions[i]->size()>65536)return std::nullopt;uses=*owned.descriptions[i];}
            result.push_back({category,index,flags[index]!=0,std::move(name),std::move(uses)});
        }
    }
    return result;
}
enum class Outcome {Rejected,Applied,Stale};
inline Outcome apply(int32_t category,int32_t index,const std::vector<char>& expected,bool* writeStarted=nullptr) {
    if(writeStarted)*writeStarted=false;
    if(category<0 || category>1 || index<0 || expected.size()>65536 ||
       std::any_of(expected.begin(),expected.end(),[](char value){return value!=0 && value!=1;}))return Outcome::Rejected;
    const auto rows=read();
    if(!rows || !df::global::plotinfo)return Outcome::Rejected;
    auto& flags=df::global::plotinfo->economic_stone;
    if(flags!=expected)return Outcome::Stale;
    if(size_t(index)>=flags.size() || std::none_of(rows->begin(),rows->end(),[=](const Row& row){return row.category==category && row.index==index;}))return Outcome::Rejected;
    // Native434b8a..434bb4 has no semantic callee: its complete simulation
    // effect is this byte flip. Do not invoke its mouse/widget dispatcher.
    // All fallible reads/allocations finish before the first authoritative write.
    if(writeStarted)*writeStarted=true;
    flags[index]=static_cast<char>(1-flags[index]);
    return Outcome::Applied;
}
}
