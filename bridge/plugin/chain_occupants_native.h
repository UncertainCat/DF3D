#pragma once
#include "chain_body_native.h"
#include "cage_occupants_native.h"
namespace df3d_production {
inline std::optional<CageOccupants> observeChainOccupants(df::building* building) {
    if(!chainBodyReady())return {};
    const auto authority=observeChain(building);if(!authority)return {};
    auto& chain=*static_cast<df::building_chainst*>(building);
    CageOccupants result;result.buildingId=chain.id;result.removing=authority->removing;
    result.justiceRestraint=authority->justiceRestraint;
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    for(auto* unit:{chain.assigned,chain.chained}) {
        if(!unit || (!result.rows.empty() && result.rows.front().id==unit->id))continue;
        const auto name=restraintUnitName(*unit,false);if(!name)return {};
        CageOccupant row;row.id=unit->id;row.entity=1;row.resolved=true;row.name=*name;
        row.assigned=unit==chain.assigned;row.contained=unit==chain.chained;
        row.status=reinterpret_cast<const char*>(base+(row.assigned?(row.contained?0x16018e8:0x16014b0):0x1601bf8));
        result.rows.push_back(std::move(row));
    }
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(int i=0;i<8;++i){hash^=uint8_t(value);hash*=UINT64_C(1099511628211);value>>=8;}};
    add(authority->revision);add(result.rows.size());
    for(const auto& row:result.rows)for(const auto* text:{&row.name,&row.status}) {
        add(text->size());for(unsigned char value:*text){hash^=value;hash*=UINT64_C(1099511628211);}
    }
    result.revision=(hash&INT64_MAX)|1;return result;
}
}
