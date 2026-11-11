#pragma once
#include "df/crime.h"
#include "df/world.h"
#include <optional>
#include <string>

namespace df3d_justice {
// Native case-list construction47083f/470c89 calls this plain string builder.
// It reads crime facts, unit names and agreement details; it does not access
// Justice widgets. Both the crime value and output storage belong to this call.
inline std::optional<std::string> caption(const df::crime* crime) {
    if(!crime || !df::global::world)return std::nullopt;
    static_assert(offsetof(df::crime,mode)==4);
    static_assert(offsetof(df::crime,victim)==0x70);
    static_assert(offsetof(df::crime,agreement_id)==0x110);
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        // Includes the full function and its19-way dispatch table.
        for(size_t i=0;i<0x4f8;++i){hash^=base[0x46d660+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xec4ef57098e332dc);
    }();
    if(!pinned)return std::nullopt;
    const auto owned=*crime;
    std::string text;
    using Caption=std::string*(*)(std::string*,const df::crime*);
    reinterpret_cast<Caption>(const_cast<uint8_t*>(base)+0x46d660)(&text,&owned);
    if(text.size()>16384)return std::nullopt;
    return text;
}
}
