#pragma once
#include <memory>
#include <optional>
#include <limits>
#include <vector>
#include "df/creature_raw.h"
#include "df/caste_raw.h"
#include "df/creature_raw_graphics.h"

namespace df3d_residents {
// A selected layered fallback is reported explicitly until its owned evaluator
// is qualified. It must never be confused with an original page tile.
constexpr int32_t speciesLayeredFallback=std::numeric_limits<int32_t>::max();
inline std::optional<int32_t> speciesSelectorOriginalTile(int32_t race) {
    auto* raw=df::creature_raw::find(race);
    if(!raw || raw->caste.size()>32767)return std::nullopt;
    for(const auto* caste:raw->caste)if(!caste)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x1661;++i){hash^=base[0x6d6560+i];hash*=UINT64_C(1099511628211);}
        constexpr uint32_t cases[]={0x6d6c8f,0x6d6c84,0x6d6c72,0x6d6c60,0x6d6c4e,0x6d6c3c,0x6d6c2a};
        for(size_t i=0;i<7;++i)if(*reinterpret_cast<const uint32_t*>(base+0x6d7bc4+i*4)!=cases[i])return false;
        return hash==UINT64_C(0x5ddf9622e1746db9);
    }();
    if(!pinned)return std::nullopt;
    std::vector<std::unique_ptr<df::creature_raw_graphics>> graphics;
    const auto clone=[&](const df::creature_raw_graphics* original)->df::creature_raw_graphics* {
        if(!original)return nullptr;
        auto copy=std::make_unique<df::creature_raw_graphics>();
        *copy=*original;
        // Native6d7775 reads these owned vectors before considering71a410.
        // A nonzero sentinel avoids template expansion and cache composition.
        // Layer-set pointers are inspected only for selection, never invoked.
        for(auto& column:copy->layer_unitless_texpos[102])
            for(auto& cell:column)cell.assign(1,0);
        copy->layer_unitless_texpos[102][0][0][0]=speciesLayeredFallback;
        auto* result=copy.get();graphics.push_back(std::move(copy));return result;
    };
    auto owned=std::make_unique<df::creature_raw>();
    owned->flags=raw->flags;owned->graphics=clone(raw->graphics);
    std::vector<std::unique_ptr<df::caste_raw>> castes;
    for(const auto* source:raw->caste) {
        auto caste=std::make_unique<df::caste_raw>();caste->caste_graphics=clone(source->caste_graphics);
        owned->caste.push_back(caste.get());castes.push_back(std::move(caste));
    }
    std::string position;
    using Selector=int32_t(*)(df::creature_raw*,int16_t,std::string*,int16_t,int16_t,int16_t,
        uint32_t,df::unit*,df::item_body_component*,bool*);
    // Widget1423420 requests400, not800: multi-cell flat sprites return their
    // native selected original cell without generating a sheet-icon texture.
    return reinterpret_cast<Selector>(const_cast<uint8_t*>(base+0x6d6560))(
        owned.get(),-1,&position,-1,-1,102,0x400,nullptr,nullptr,nullptr);
}
}
