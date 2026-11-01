#pragma once
#include "creature_thoughts_native.h"
#include "creature_overview_native.h"
#include <array>
namespace df3d_creature {
// Native47f74b..4800ad composes Needs inline among sheet writes. Only the
// focus calculator and historical-name formatter are invoked; paragraph order,
// colors and clauses follow that pinned inline composition using owned text.
inline std::optional<std::string> personalityNeeds(const df::unit* source) {
    if(!source || !df::global::world || !thoughtDescriptionReady())return std::nullopt;
    static_assert(offsetof(df::unit,counters.soldier_mood)==0x814);
    static_assert(offsetof(df::unit,mood)==0x360);
    const auto* soul=source->status.current_soul;
    if(!soul || soul->personality.needs.empty() || int(source->counters.soldier_mood)!=-1 || (int(source->mood)>=5 && int(source->mood)<=9))return std::string{};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x47f74b,0x967,UINT64_C(0x582eaa098fc33217)},
            {0x481e14,0x78,UINT64_C(0xacbafdb50a8ce0ff)},
            {0x15e85b4,0x2,UINT64_C(0x07da2c07b4a05dc3)},
            {0x15e873c,0x2,UINT64_C(0x07c5c807b48f0acd)},
            {0x15ed5b4,0x5,UINT64_C(0x56a7d5c347508a2a)},
            {0x15f71e4,0x5,UINT64_C(0xf302b01c91704c3b)},
            {0x16023c0,0xa,UINT64_C(0xb89c4f7cc79be315)},
            {0x16023d0,0xa,UINT64_C(0x2551a5e146efa1c2)},
            {0x1602430,0xa,UINT64_C(0xd4bd098ef4c1f7c2)},
            {0x1602440,0xa,UINT64_C(0xc9fa9a8eee11c5c9)},
            {0x1602558,0xa,UINT64_C(0x1a8f36e1403f6fc9)},
            {0x1602568,0xa,UINT64_C(0x881bd122423de397)},
            {0x1640390,0xa,UINT64_C(0xf0acbb8ff43beb5d)},
            {0x16403a0,0xf,UINT64_C(0x2353a41866a10d37)},
            {0x16403b0,0xb,UINT64_C(0x4e624740ef5479bd)},
            {0x16403c0,0xd,UINT64_C(0x3446e6c4aae724b9)},
            {0x16403d0,0x1d,UINT64_C(0x594fc9a286ea60d1)},
            {0x16403f0,0x20,UINT64_C(0xfb99bcce4b15a471)},
            {0x1640410,0x11,UINT64_C(0x5ab00c0e73d8a08a)},
            {0x1640428,0xb,UINT64_C(0x1efcbd6946dcc862)},
            {0x1640438,0x20,UINT64_C(0x3b933861950b56cf)},
            {0x1640458,0x26,UINT64_C(0x07897c0ed83b17f9)},
            {0x1640480,0x23,UINT64_C(0x4ba951754db92e7f)},
            {0x16404a8,0x22,UINT64_C(0x755f699b2f1b5537)},
            {0x16404d0,0xb,UINT64_C(0x58979f4bbab69843)},
            {0x16404e0,0x1a,UINT64_C(0x54a020ab75afdb56)},
            {0x1640500,0x19,UINT64_C(0x2851e1c831ed22f6)},
            {0x1640520,0x1a,UINT64_C(0xf04479e6c28b2f77)},
            {0x1640580,0xa,UINT64_C(0x2bfce3e145dca052)},
            {0x1640590,0xa,UINT64_C(0xc35ebe7cce4c150e)},
            {0x1640650,0x19,UINT64_C(0x3b13a30005e202f0)},
            {0x1640670,0x21,UINT64_C(0x69d9341d0433184b)},
            {0x1640698,0x13,UINT64_C(0xbad07cf7cd648e91)},
            {0x16406b0,0x1e,UINT64_C(0xbd2e6c43babe5935)},
            {0x16406d0,0x19,UINT64_C(0x7c8064ce050040a5)},
            {0x16406f0,0x2d,UINT64_C(0x1de0b5a6b1c93f9d)},
            {0x1640720,0x1f,UINT64_C(0x1f07de6b6c641c2f)},
            {0x1640740,0x27,UINT64_C(0x864faa25ac3099ca)},
            {0x1640768,0x1e,UINT64_C(0xdfd1e42f71c5b034)},
            {0x1640788,0x1e,UINT64_C(0x3914210b7645066b)},
            {0x16407a8,0x19,UINT64_C(0xc616ce228990c12d)},
            {0x16407c8,0x1d,UINT64_C(0x407026d30f3ab268)},
            {0x16407e8,0x17,UINT64_C(0xb98ce59b20edc79f)},
            {0x1640800,0x21,UINT64_C(0xb0f3c06f5854fb4f)},
            {0x1640828,0x1a,UINT64_C(0x7528d8b7363a513f)},
            {0x1640848,0x2b,UINT64_C(0xc0795045c0d01119)},
            {0x1640878,0x1f,UINT64_C(0xa3958faa570d0e05)},
            {0x1640898,0x1d,UINT64_C(0xaa26d12f536c86d8)},
            {0x16408b8,0x1f,UINT64_C(0xaa474fa3c72d2d61)},
            {0x16408d8,0x21,UINT64_C(0x7bcae5d3295a5e27)},
            {0x1640900,0x18,UINT64_C(0x4e8dda597b9d395a)},
            {0x1640918,0x1c,UINT64_C(0x7c7516ae1ab27a20)},
            {0x1640938,0x19,UINT64_C(0x21bd44bd03d77d27)},
            {0x1640958,0x21,UINT64_C(0x445d6c3c24b50a9a)},
            {0x1640980,0x11,UINT64_C(0x8d1e7f7e00c6d27d)},
            {0x1640998,0x16,UINT64_C(0xc239e0a04a0ffe20)},
            {0x16409b0,0x1e,UINT64_C(0x400fa8423331d248)},
            {0x16409d0,0xf,UINT64_C(0xc82a8bb03fc715e3)},
            {0x16409e0,0x13,UINT64_C(0x5965bf20a8ddc041)},
            {0x16409f8,0x17,UINT64_C(0x4b371bc0589efa4f)},
            {0x1640a10,0x17,UINT64_C(0x97def2266e1a8c3e)},
            {0x1640a28,0x1b,UINT64_C(0x9b1b6d50559a64f6)},
            {0x1640a68,0x22,UINT64_C(0x7a5a0f00c4c07136)},
            {0x1640a90,0x1a,UINT64_C(0x7d757453a11a4d48)},
            {0x1640ab0,0x23,UINT64_C(0xd41843f0726ceafd)},
            {0x1640b18,0x18,UINT64_C(0x64090f76df5c3a71)},
            {0x1640b30,0x1c,UINT64_C(0xf9045d171c643d48)},
            {0x1640b50,0xe,UINT64_C(0xaace2c680001a19c)},
            {0x1640b60,0x1f,UINT64_C(0xb93d009124e3e405)},
            {0x1640b80,0x17,UINT64_C(0xb18216c3f555ea8c)},
            {0x1640b98,0x1d,UINT64_C(0x6f5e877a72cb41d5)},
            {0x1640bb8,0x10,UINT64_C(0x6997eeec442922be)},
            {0x1640bc8,0x25,UINT64_C(0x549eb076b78f8506)},
            {0x1640bf0,0x19,UINT64_C(0xbe68f639fb642cc2)},
            {0x1640c10,0x28,UINT64_C(0xa3d5e05fd97079ba)},
            {0x1640c38,0x1a,UINT64_C(0xb4529cb7fbfc3226)},
            {0x1640c58,0x23,UINT64_C(0xcd61aa053ea1d0c1)},
            {0x1640c80,0x16,UINT64_C(0x23208358b69872b6)},
            {0x1640c98,0x1c,UINT64_C(0x2392c93101bc2fac)},
            {0x1640cb8,0xf,UINT64_C(0xfbbd7c4a95f29f57)},
            {0x1640cc8,0x1d,UINT64_C(0x85e9ec32b6e2e93f)},
            {0x1640ce8,0x15,UINT64_C(0x100585f6cafedf7d)},
            {0x1640d00,0x23,UINT64_C(0x821dc989e3d7f8ec)},
            {0x1640d28,0x15,UINT64_C(0x4c47a4939bff60d6)},
            {0x1640d40,0x27,UINT64_C(0x0f40027e61028b0b)},
            {0x1640d68,0x1b,UINT64_C(0xd8f6e98cf3e4c319)},
            {0x1640d88,0x1e,UINT64_C(0x6202e1f0ba9a2b73)},
            {0x1640da8,0x15,UINT64_C(0xcf5753217baee861)},
            {0x1640dc0,0x23,UINT64_C(0xce4f1efad34d1b6f)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();if(!ready)return std::nullopt;
    int32_t current=0,undistracted=0;
    const auto percent=focusPercent(soul->personality,&current,&undistracted);
    if(!percent)return std::nullopt;
    const auto literal=[&](size_t rva){return reinterpret_cast<const char*>(base+rva);};
    const auto pronoun=[&](bool capitalized){std::string value;using Fn=void(*)(int8_t,std::string*,bool);reinterpret_cast<Fn>(base+0xaa4730)(source->sex,&value,capitalized);return value;};
    size_t color=0x1602440;
    if(current!=undistracted && undistracted>0)color=*percent>=140?0x16023c0:*percent>=120?0x1640590:current>undistracted?0x1602430:*percent<=60?0x1602568:*percent<=80?0x1602558:0x16023d0;
    std::string text=literal(color);text+=literal(0x1640580);text+=pronoun(false);text+=literal(0x15f71e4);
    text+=literal(*percent>=140?0x16404a8:*percent>=120?0x1640480:current>undistracted?0x1640458:*percent<=60?0x1640438:*percent<=80?0x1640520:current!=undistracted && undistracted>0?0x1640500:0x16404e0);
    text+=literal(0x15e85b4);
    // Native73b50 omits individual need rows for baby/child professions.
    static_assert(offsetof(df::unit,profession)==0xa0);
    if(int(source->profession)==103 || int(source->profession)==104)return text;
    constexpr size_t colors[]={0x1602568,0x1602558,0x16023d0,0x1602440,0x1602430,0x1640590,0x16023c0};
    constexpr size_t states[]={0x1640410,0x1640428,0x1640390,0x16403a0,0x16403b0,0x16403c0,0x16404d0};
    constexpr size_t clauses[][2]={
        {0x16403f0,0x16403d0},
        {0x16409d0,0x16409b0},
        {0x1640998,0x1640a28},
        {0x1640a10,0x16409f8},
        {0x16408b8,0x1640898},
        {0x1640878,0x1640958},
        {0x1640938,0x1640918},
        {0x1640900,0x16407c8},
        {0x16407a8,0x1640788},
        {0x1640768,0x1640848},
        {0x1640828,0x1640800},
        {0x16407e8,0x16406b0},
        {0x1640698,0x1640670},
        {0x1640650,0x1640740},
        {0x1640720,0x16406f0},
        {0x16406d0,0x1640d40},
        {0x1640d28,0x1640d00},
        {0x1640ce8,0x1640dc0},
        {0x1640da8,0x1640d88},
        {0x1640d68,0x1640c58},
        {0x1640c38,0x1640c10},
        {0x1640bf0,0x1640cc8},
        {0x1640cb8,0x1640c98},
        {0x1640c80,0x1640b60},
        {0x1640b50,0x1640b30},
        {0x1640b18,0x1640bc8},
        {0x1640bb8,0x1640b98},
        {0x1640b80,0x1640ab0},
        {0x1640a90,0x1640a68},
        {0x16409e0,0x16408d8},
    };
    InventoryRandomRestore random(base);
    KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    for(const auto* live:soul->personality.needs){
        if(!live)return std::nullopt;
        const auto need=*live;
        const auto focus=need.focus_level;
        const int tier=focus>=300?3:focus>=200?2:focus>=100?1:focus<=-100000?-3:focus<=-10000?-2:focus<=-1000?-1:0;
        text+="[B]";text+=literal(colors[tier+3]);text+=pronoun(true);text+=literal(0x15f71e4);text+=literal(states[tier+3]);text+=literal(0x15e873c);
        const int id=int(need.id);
        if(id>=0 && id<30){
            if(id==2 && tier>0 && need.deity_id==-1)text+=literal(0x1640980);
            else text+=literal(clauses[id][tier>0?0:1]);
            if(id==2 && need.deity_id!=-1){
                if(tier<=0)text+=literal(0x15ed5b4);
                // Native72080 initializes an owned history-format context
                // (0xc8 bytes). Its optional source pointers start null. No UI
                // context or borrowed mutable lookup index is passed downstream.
                alignas(8) std::array<uint8_t,0xc8> context{};
                reinterpret_cast<void(*)(void*)>(base+0x72080)(context.data());
                using Name=void(*)(void*,std::string*,int32_t,void*,int16_t,int16_t);
                reinterpret_cast<Name>(base+0xb92f10)(base+0x24f9cb8,&text,need.deity_id,context.data(),1,1);
            }
        }
        text+=literal(0x15e85b4);
        if(text.size()>65536)return std::nullopt;
    }
    return text;
}
}
