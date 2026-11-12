#pragma once
#include "creature_thoughts_native.h"
#include "df/unit_soul.h"
#include "df/personality_moodst.h"

namespace df3d_creature {
// Native1a6c44..1a7065 selects the quote inline among sheet writes. Invoke
// only its semantic text routines, with independently owned unit/soul storage.
inline std::optional<std::string> overviewQuote(df::unit* source) {
    if(!source || !df::global::world || !thoughtDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x73760,0x4c,UINT64_C(0xd6e159fb1367c80e)},
            {0x73710,0x4c,UINT64_C(0xe700e2d52b0deb31)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
            {0x72850,0x8b,UINT64_C(0xf9b1c2f8d7f55288)},
            {0x1a6c44,0x422,UINT64_C(0xca0175cdaab0efc6)},
            {0x1a8138,0xbd,UINT64_C(0x2f0dd035e0173a99)},
            {0x666470,0x1ae0,UINT64_C(0xddff0b0898548295)},
            {0x667f50,0x250,UINT64_C(0x13dde744aa20ec06)},
            {0x6681a0,0x1040,UINT64_C(0x9cfe0c3869b26e49)},
            {0x6691e0,0xd60,UINT64_C(0x12bf1765a3fb5087)},
            {0x669f40,0xd60,UINT64_C(0x07546cc4093430b1)},
            {0x66aca0,0xd60,UINT64_C(0x89b347a6d201992d)},
            {0x66fe50,0x3d68,UINT64_C(0xd0a9b0dc7f06d582)},
            {0x66ba00,0x4448,UINT64_C(0xdbd9987252f098af)},
            {0x67b6c0,0x58d,UINT64_C(0x2476b32b284faba9)},
            {0xe185a0,0xb3,UINT64_C(0x3a013d7331df5d39)},
            {0xe11b00,0xab,UINT64_C(0x0f13c45194db8eb9)},
            {0x664be0,0x1890,UINT64_C(0xe9e3ecb8166b9baa)},
            {0x756500,0x188,UINT64_C(0x531dbaf4cb505231)},
            {0x737b0,0x2e,UINT64_C(0x44e51f229ada57d2)},
            {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
            {0x15e9718,0x2,UINT64_C(0x07cc9407b494d11f)},
            {0x15fcfe8,0x2,UINT64_C(0x07c5a807b48ed46d)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();
    if(!ready)return std::nullopt;
    using Predicate=bool(*)(df::unit*);
    if(!reinterpret_cast<Predicate>(base+0x73760)(source) ||
       !reinterpret_cast<Predicate>(base+0x73710)(source) ||
       !reinterpret_cast<Predicate>(base+0x138ed20)(source) ||
       !source->status.current_soul)return std::string{};
    const int mood=int(source->mood);
    if(mood==5 || mood==6 || mood==7 || mood==9 ||
       int(source->counters.soldier_mood)!=-1 || source->counters.unconscious>0)return std::string{};
    static_assert(offsetof(df::unit,counters.unconscious)==0x800);
    static_assert(offsetof(df::unit,counters.soldier_mood)==0x814);
    auto soul=*source->status.current_soul;
    struct OwnedUnit final:df::unit {OwnedUnit():df::unit(){}} unit;
    unit.race=source->race;unit.caste=source->caste;unit.sex=source->sex;
    unit.profession=source->profession;unit.mood=source->mood;
    unit.hist_figure_id=source->hist_figure_id;unit.enemy.histfig_vector_idx=-1;
    unit.status.current_soul=&soul;unit.status.misc_traits=source->status.misc_traits;
    // Personality values, temporary trait changes and misc traits are read-only.
    // Name lookups may update the copied histfig index. The context formatter's
    // second unit is null, excluding relationship/knowledge cache refreshes.
    InventoryRandomRestore random(base);
    KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    const df::personality_moodst* selected=nullptr;
    int best=-1;
    if(mood!=8)for(const auto* emotion:soul.personality.emotions) {
        if(!emotion || int(emotion->thought)==-1)continue;
        if(int(emotion->thought)==6 && reinterpret_cast<int32_t(*)(int32_t)>(base+0x71f30)(10)!=0)continue;
        const int type=int(emotion->type);
        if(type==-1 || type==165 || type==166 || (emotion->flags.whole&0x70) ||
           (emotion->strength<=0 && emotion->relative_strength<=0))continue;
        int weight=std::min(emotion->relative_strength,100);
        if(weight==100 && emotion->relative_strength==100 && (emotion->flags.whole&1))weight=100000;
        if(type>=0 && type<=168) {
            const auto index=base[0x1a814c+type];
            const auto target=*reinterpret_cast<const uint32_t*>(base+0x1a8138+index*4);
            switch(target) {
                case 0x1a6e88:weight*=8;break;
                case 0x1a6e91:weight*=4;break;
                case 0x1a6e9a:weight*=2;break;
                case 0x1a6e9e:weight*=16;break;
                default:break;
            }
        }
        if(weight>best){selected=emotion;best=weight;}
    }
    std::string text;
    if(selected) {
        using Context=void(*)(df::unit*,df::unit*,std::string*,int32_t,int32_t,int32_t);
        reinterpret_cast<Context>(base+0x66fe50)(&unit,nullptr,&text,int(selected->thought),selected->subthought,selected->severity);
        if(!text.empty())text+=reinterpret_cast<const char*>(base+0x15fcfe8);
        int strength=std::min(selected->relative_strength,100);
        if(selected->relative_strength==100 && (selected->flags.whole&1))strength=101;
        const size_t formatter=strength==101?0x667f50:strength==100?0x6681a0:strength>10?0x6691e0:strength>0?0x669f40:0x66aca0;
        reinterpret_cast<void(*)(int32_t,std::string*)>(base+formatter)(int(selected->type),&text);
    } else {
        reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x666470)(&unit,&text,false);
        if(reinterpret_cast<bool(*)(void*,int16_t,int16_t,int32_t)>(base+0x72850)(base+0x24eca48,unit.race,unit.caste,0x77))
            reinterpret_cast<void(*)(std::string*)>(base+0x67b6c0)(&text);
    }
    if(text.size()>65536)return std::nullopt;
    const auto* quote=reinterpret_cast<const char*>(base+0x15e9718);
    return std::string(quote)+text+quote;
}
}
