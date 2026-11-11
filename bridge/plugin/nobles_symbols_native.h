#pragma once
#include "nobles_draft_native.h"
#include "unit_room_native.h"
#include "df/artifact_record.h"
#include "df/artifact_claim.h"

namespace df3d_nobles {
struct SymbolRow {
    int32_t itemId=-1,value=0;
    std::optional<OfficeKey> currentOffice,selectedOffice;
};
// 422d10 writes only the supplied candidate vectors and local sorting arrays.
// Position/reference getters can refresh semantic reference caches; valuation
// has the same semantic lazy artwork initialization as Stocks. No native menu,
// temporary item scores or camera/search scratch participates in this call.
inline bool symbolsReady() {
    if(!ready() || !df3d_room::valuationReady())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto at=[base](const void* address,size_t rva){return address==base+rva;};
    const auto& world=*df::global::world;
    if(!at(&world,0x23d14f0) || !at(&world.items.other.IN_PLAY,0x23e5468) ||
       !at(&world.items.other.ANY_ARTIFACT,0x23e5480) || !at(&world.artifacts.all,0x23e6180) ||
       !at(&world.map.block_index,0x24e80a8) || !at(&world.map.x_count,0x24e80dc) ||
       !at(&world.map.y_count,0x24e80e0) || !at(&world.map.z_count,0x24e80e4) ||
       !at(&df::global::plotinfo->civ_id,0x2393670))return false;
    static_assert(offsetof(df::administrators_interfacest,cand_symbol)==0xc0);
    static_assert(offsetof(df::administrators_interfacest,cand_symbol_new_ind)==0xd8);
    static_assert(offsetof(df::administrators_interfacest,cand_symbol_is_symbol_of_ind)==0xf0);
    static_assert(offsetof(df::administrators_interfacest,cand_symbol_value)==0x108);
    static_assert(offsetof(df::historical_entity,artifact_claims)==0x1318);
    static_assert(offsetof(df::artifact_record,item)==0x90);
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x422d10,0x10d8,UINT64_C(0x9b8c1fea577b3390)},
            {0xb9dc0,0xa7,UINT64_C(0x4d8961b901732215)},
            {0x1367430,0xc6,UINT64_C(0xc0292be8a6dacf2c)},
            {0xc8baa0,0x11a,UINT64_C(0x2c62fce4a0555c66)},
            {0xedfa60,0xbd,UINT64_C(0x2f89116df6b958cc)},
            {0xedfb20,0x13,UINT64_C(0xa222e60f2f8301e4)},
            {0x14db50,0xb1,UINT64_C(0x4b9c987ca0656b35)},
            {0x14dc10,0x5a,UINT64_C(0xfb6e6c7bccbf765b)},
            {0x67270,6,UINT64_C(0x7dce27ae257f083d)},
            {0x7a840,6,UINT64_C(0xeff4222c8d49c252)},
            {0x7dc40,0x86,UINT64_C(0x396b58fb95c29f02)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    return pinned;
}
// The caller prepares its appointment draft first. Native indices remain local
// to that context; only stable office identities leave the provider.
inline std::optional<std::vector<SymbolRow>> projectSymbols(Context& owned,const OfficeKey& key) {
    if(!symbolsReady())return std::nullopt;
    auto& value=owned.value;
    df::noblelistst* target=nullptr;
    for(auto* row:value.noblelist) {
        if(!row || !row->ep)return std::nullopt;
        if(row->enid==key.entityId && row->ep->id==key.positionId &&
           (row->epp?row->epp->id:-1)==key.assignmentId && owned.slot(row)==key.draftSlot) {
            if(target)return std::nullopt;target=row;
        }
    }
    if(!target || !target->epp)return std::nullopt;
    const auto& world=*df::global::world;
    if(world.items.other.IN_PLAY.size()>1048576 || world.items.other.ANY_ARTIFACT.size()>1048576 ||
       world.artifacts.all.size()>1048576)return std::nullopt;
    df3d_creature::InventoryRandomRestore random(owned.base);
    reinterpret_cast<void(*)(df::administrators_interfacest*,df::noblelistst*)>(owned.base+0x422d10)(&value,target);
    const auto count=value.cand_symbol.size();
    if(count>1048576 || value.cand_symbol_new_ind.size()!=count ||
       value.cand_symbol_is_symbol_of_ind.size()!=count || value.cand_symbol_value.size()!=count)return std::nullopt;
    const auto office=[&](int32_t index,std::optional<OfficeKey>& result) {
        if(index==-1){result.reset();return true;}
        if(index<0 || size_t(index)>=value.noblelist.size())return false;
        const auto* row=value.noblelist[index];
        result=OfficeKey{row->enid,row->ep->id,row->epp?row->epp->id:-1,owned.slot(row)};return true;
    };
    std::vector<SymbolRow> result;result.reserve(count);
    for(size_t i=0;i<count;++i) {
        auto* item=value.cand_symbol[i];if(!item)return std::nullopt;
        SymbolRow row;row.itemId=item->id;row.value=value.cand_symbol_value[i];
        if(!office(value.cand_symbol_new_ind[i],row.selectedOffice) ||
           !office(value.cand_symbol_is_symbol_of_ind[i],row.currentOffice))return std::nullopt;
        result.push_back(std::move(row));
    }
    return result;
}
}
