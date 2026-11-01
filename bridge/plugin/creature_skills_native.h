#pragma once
#include "unit_description_native.h"
#include "df/unit_soul.h"
#include "df/unit_skill.h"
#include <cstddef>
namespace df3d_creature {
struct SkillsPage {
    std::vector<int16_t> skills;
    std::vector<int32_t> values,rustValues,knowledgeTypes,knowledgeIds;
    std::vector<uint32_t> knowledgeBits;
};
// Native47e270 owns category dispatch, stable rating insertion and Knowledge
// enumeration. Supply independent vectors and a copied historical-figure cache;
// no view_sheets storage or staged native selection is read.
inline std::optional<SkillsPage> skillsPageProbe(df::unit* source,int page) {
    if(!source || page<0 || page>4 || !inventoryDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    constexpr Pin pins[]={
        {0x47e270,0x11cd,UINT64_C(0x9fba784968992fc8)},
        {0x70e20,0x117,UINT64_C(0x09aba69f846f6c10)},
        {0x71040,0x112,UINT64_C(0x5f2ee621244a5576)},
        {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
    };
    for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return std::nullopt;}
    struct Context {
        std::array<uint8_t,0x1b30> prefix{};
        std::vector<int16_t> skills;
        std::vector<int32_t> values,rustValues,knowledgeTypes,knowledgeIds;
        std::vector<uint32_t> knowledgeBits;
    } context;
    static_assert(offsetof(Context,skills)==0x1b30 && offsetof(Context,knowledgeBits)==0x1ba8);
    static_assert(offsetof(df::unit,status)+offsetof(df::unit::T_status,current_soul)==0xa98);
    static_assert(offsetof(df::unit_soul,skills)==0x218);
    std::memcpy(context.prefix.data()+0x1b28,&page,sizeof(page));
    InventoryDescriptionContext unit(*source);
    struct OwnedSoul final:df::unit_soul {OwnedSoul():df::unit_soul(){}} soul;
    std::vector<df::unit_skill> skills;
    if(source->status.current_soul){
        const auto& original=source->status.current_soul->skills;
        if(original.size()>4096)return std::nullopt;
        skills.reserve(original.size());
        for(const auto* skill:original){if(!skill)return std::nullopt;skills.push_back(*skill);}
        for(auto& skill:skills)soul.skills.push_back(&skill);
        unit.unit()->status.current_soul=&soul;
    }
    reinterpret_cast<void(*)(void*,df::unit*)>(base+0x47e270)(&context,unit.unit());
    if(context.skills.size()>4096 || context.knowledgeTypes.size()>4096 ||
       context.skills.size()!=context.values.size() || context.skills.size()!=context.rustValues.size() ||
       context.knowledgeTypes.size()!=context.knowledgeIds.size() || context.knowledgeTypes.size()!=context.knowledgeBits.size())return std::nullopt;
    return SkillsPage{std::move(context.skills),std::move(context.values),std::move(context.rustValues),
        std::move(context.knowledgeTypes),std::move(context.knowledgeIds),std::move(context.knowledgeBits)};
}
}
