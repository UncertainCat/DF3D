#pragma once
#include "creature_lists_native.h"
#include "df/plotinfost.h"
#include "df/historical_entity.h"
#include "df/entity_animal_training_knowledgest.h"
#include "df/creature_raw.h"

namespace df3d_residents {
struct TrainingKnowledgeRow {int32_t race,level;std::string name,caption;int32_t foreground;bool bright;};
inline std::optional<std::vector<TrainingKnowledgeRow>> trainingKnowledge() {
    if(!df::global::world || !df::global::plotinfo || !orderingSupported())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xa9c7d0,0x9e,UINT64_C(0xee8610186c05335c)},
            {0x36cf90,0xbd0,UINT64_C(0x473701873857c2c9)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!pinned || reinterpret_cast<const uint8_t*>(&df::global::plotinfo->main.fortress_entity)!=base+0x239a1e8)return std::nullopt;
    static_assert(offsetof(df::historical_entity,training_knowledge)==0x1248);
    const auto* entity=df::global::plotinfo->main.fortress_entity;
    if(!entity || !entity->training_knowledge)return std::nullopt;
    const auto& levels=entity->training_knowledge->level;
    const auto& raws=df::global::world->raws.creatures.all;
    if(levels.size()>raws.size() || levels.size()>32767)return std::nullopt;
    // This projects already-calculated fortress knowledge, not training rules.
    // Native36d060 admits nonzero entries; comparatora9c7d0 orders singular
    // names even though36d575 displays plural names. Never use native's static
    // scratch vector or call the menu-opening routine36cf90.
    std::vector<int32_t> races;
    for(size_t i=0;i<levels.size();++i) {
        if(!raws[i])return std::nullopt;
        if(int(levels[i])!=0)races.push_back(int32_t(i));
    }
    using Compare=int (*)(const void*,const void*);
    const auto compare=reinterpret_cast<Compare>(const_cast<uint8_t*>(base+0xa9c7d0));
    // Use the same imported qsort as36d0e0, including its equal-name handling.
    using Sort=void (*)(void*,size_t,size_t,Compare);
    const auto sort=*reinterpret_cast<const Sort*>(base+0x15e5d60);
    if(!races.empty())sort(races.data(),races.size(),sizeof(int32_t),compare);
    constexpr size_t captions[]={0,0x1629f68,0x1629e00,0x1629df0,0x1629e28,0x1629e18};
    constexpr int colors[]={7,4,6,7,3,2};
    std::vector<TrainingKnowledgeRow> result;result.reserve(races.size());
    for(auto race:races) {
        const int level=int(levels[race]);
        TrainingKnowledgeRow row{race,level,raws[race]->name[1],{},7,false};
        if(level>=1 && level<=5) {
            const char* literal=reinterpret_cast<const char*>(base+captions[level]);
            size_t length=0;while(length<64 && literal[length])++length;
            if(length==64)return std::nullopt;
            row.caption.assign(literal,length);row.foreground=colors[level];row.bright=true;
        }
        result.push_back(std::move(row));
    }
    return result;
}
}
