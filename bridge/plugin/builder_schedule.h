#pragma once
#include <algorithm>
#include <cstddef>
#include <cstdint>

namespace df3d_builder {
// Registry at task 03-B dispatch: highest kind 17 plus one.
constexpr size_t kBuilderKindCount=18;
// Explicit synchronous writes do not borrow a read budget. Keep their work
// metrics separately; wide counts must never narrow before this decision.
constexpr uint32_t readCharge(uint32_t remaining,uint64_t measured,bool synchronousWrite) {
    return synchronousWrite ? 0 : uint32_t(std::min(uint64_t(remaining),measured));
}
// Select only enabled domains owned by the request's helper.
template<class Table,class Owns>
uint32_t requestMask(const Table& table,Owns owns) {
    uint32_t mask=0;
    for(const auto& entry:table)
        if(entry.enabled && owns(entry.action))mask|=entry.domainMask;
    return mask;
}
// Entries visited once per update; completion rolls its unused share forward.
// Re-read active bits after each callback, since one Lua owns several kinds.
template<class Table,class Step>
uint32_t advance(const Table& table,uint32_t& active,uint32_t& start,uint32_t budget,Step step) {
    const auto first=start;bool rotated=false;
    const auto initial=budget;
    for(size_t offset=0;offset<table.size() && budget;++offset) {
        const auto kind=(first+offset)%table.size();
        if(!table[kind].enabled || !(active & (1u<<kind)))continue;
        if(!rotated){start=(kind+1)%table.size();rotated=true;}
        uint32_t count=0;
        for(size_t next=offset;next<table.size();++next) {
            const auto k=(first+next)%table.size();
            if(table[k].enabled && (active & (1u<<k)))++count;
        }
        const auto share=(budget+count-1)/count;
        budget-=std::min(share,step(kind,share));
    }
    return initial-budget;
}
} // namespace df3d_builder
