#pragma once
#include "work_detail_query_native.h"
#include "skills_caption_native.h"
#include "df/unit_soul.h"
#include "df/unit_skill.h"

namespace df3d_production {
struct WorkDetailSkillText {int16_t skill;int32_t rating;std::string caption;};
// Native1429ef0 builds widgets, so its small eligibility loop is pinned and
// copied here. The actual skill sorter and both caption functions are called
// with owned vectors/strings. No widget or native rendering scratch is used.
inline bool workDetailSkillTextSupported() {
    static const bool ready=[] {
        if(!work_detail_query::supported() || !df3d_creature::skillsCaptionReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x1429ef0,0x408,UINT64_C(0xb77385c5e0f54a56)},
            {0x1430240,0x236,UINT64_C(0x3c97e92f188a2201)},
            {0x1432920,0x290,UINT64_C(0x453b29da1f3241bb)},
            {0x1434180,0x10b,UINT64_C(0x4fe9f1eafe5df91b)},
            {0x1434d90,0xa4,UINT64_C(0xbee050d41219fed6)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();return ready;
}
inline std::optional<std::vector<WorkDetailSkillText>> workDetailSkillText(int32_t index,df::unit* unit) {
    if(!unit || !df::global::plotinfo || !workDetailSkillTextSupported())return std::nullopt;
    const auto& all=df::global::plotinfo->labor_info.work_details;
    if(index<0 || size_t(index)>=all.size() || all.size()>128 || !all[size_t(index)])return std::nullopt;
    auto weights=workDetailSkillWeights(*all[size_t(index)]);
    std::vector<df::unit_skill*> skills;
    if(const auto* soul=unit->status.current_soul) {
        if(soul->skills.size()>4096)return std::nullopt;
        for(auto* skill:soul->skills) {
            if(!skill || int(skill->id)<0 || size_t(skill->id)>=weights.size())return std::nullopt;
            if(weights[size_t(skill->id)]>0 && int32_t(skill->rating)>0)skills.push_back(skill);
        }
    }
    if(!skills.empty()) {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        using Sort=void(*)(df::unit_skill**,df::unit_skill**,ptrdiff_t,int32_t*);
        reinterpret_cast<Sort>(base+0x1430240)(skills.data(),skills.data()+skills.size(),ptrdiff_t(skills.size()),weights.data());
    }
    std::vector<WorkDetailSkillText> result;result.reserve(skills.size());
    for(const auto* skill:skills)result.push_back({int16_t(skill->id),int32_t(skill->rating),
        df3d_creature::nativeSkillCaption(int16_t(skill->id),int32_t(skill->rating),unit->race,unit->caste)});
    return result;
}
}
