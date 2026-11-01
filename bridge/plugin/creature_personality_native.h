#pragma once
#include "creature_thoughts_native.h"
#include "df/unit_soul.h"
#include "df/unit_personality.h"
namespace df3d_creature {
inline std::optional<std::string> personalityValues(const df::unit* source) {
    if(!source || !df::global::world || !thoughtDescriptionReady())return std::nullopt;
    if(!source->status.current_soul)return std::string{};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xe248a0,0x2400,UINT64_C(0xaa9ae807069b6006)},
            {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)},
            {0x52c2b0,0xd8,UINT64_C(0x38b6489e35387929)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();if(!ready)return std::nullopt;
    const auto& soul=*source->status.current_soul;
    auto personality=soul.personality;
    struct OwnedUnit final:df::unit {OwnedUnit():df::unit(){}} unit;
    unit.race=source->race;unit.sex=source->sex;
    InventoryRandomRestore random(base);
    KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::string text;
    // Native4815a4..4815d6: cultural/personal values, memory causes and dreams.
    // The personality vectors and output are owned; pointed-to value/memory
    // records and cultural world records are read-only. The unit is used only
    // by the native circumstance formatter (race/sex); no sheet state is used.
    using Describe=void(*)(df::unit_personality*,df::unit*,int32_t,int8_t,std::string*,bool,int32_t);
    reinterpret_cast<Describe>(base+0xe248a0)(&personality,&unit,soul.race,soul.sex,&text,true,3);
    if(text.size()>65536)return std::nullopt;
    return text;
}
}
