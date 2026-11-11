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
struct SymbolChoice {int32_t itemId=-1;bool selected=false;};
inline uint64_t symbolRevision(const std::vector<SymbolRow>& rows) {
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto number=[&](uint32_t v){for(unsigned i=0;i<4;++i){hash^=uint8_t(v>>(i*8));hash*=UINT64_C(1099511628211);}};
    const auto office=[&](const std::optional<OfficeKey>& key) {
        number(key?1:0);if(key){number(key->entityId);number(key->positionId);number(key->assignmentId);number(key->draftSlot);}
    };
    number(uint32_t(rows.size()));
    for(const auto& row:rows){number(row.itemId);number(row.value);office(row.currentOffice);office(row.selectedOffice);}
    hash&=INT64_MAX;return hash?hash:1;
}
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
            {0x424794,0x47,UINT64_C(0xa1447d0600f41dc2)},
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
// Native424794..4247db toggles to the selected office, then restores the prior
// office (or unassigns if it was already this office). The presentation sends
// final checkbox states, not menu indices. This only stages the supplied owned
// context; a later apply must validate all edits before crossing into effects.
inline bool stageSymbols(Context& owned,const OfficeKey& key,uint64_t expectedRevision,
        const std::vector<SymbolChoice>& choices) {
    if(!expectedRevision || expectedRevision>INT64_MAX || choices.size()>4096)return false;
    const auto rows=projectSymbols(owned,key);if(!rows)return false;
    if(symbolRevision(*rows)!=expectedRevision){owned.stale=true;return false;}
    auto& value=owned.value;
    int32_t target=-1;
    for(size_t i=0;i<value.noblelist.size();++i) {
        const auto* row=value.noblelist[i];
        if(row->enid==key.entityId && row->ep->id==key.positionId &&
           (row->epp?row->epp->id:-1)==key.assignmentId && owned.slot(row)==key.draftSlot)target=int32_t(i);
    }
    if(target<0)return false;
    std::unordered_map<int32_t,size_t> indices;
    for(size_t i=0;i<rows->size();++i)if(!indices.emplace((*rows)[i].itemId,i).second)return false;
    std::unordered_map<int32_t,bool> edits;
    for(const auto& choice:choices)if(!indices.count(choice.itemId) || !edits.emplace(choice.itemId,choice.selected).second)return false;
    for(const auto& choice:choices) {
        const auto i=indices.at(choice.itemId);
        const auto previous=value.cand_symbol_is_symbol_of_ind[i];
        value.cand_symbol_new_ind[i]=choice.selected?target:(previous==target?-1:previous);
    }
    return true;
}
// Continuations carry the untouched tail in its original order. Rebuilding the
// native list can reorder newly elevated artifacts, so filter/reorder only our
// private vectors after revalidating the fresh list. The command owner must
// authenticate this tail against its outstanding step, not arbitrary UI order.
inline bool stageSymbolContinuation(Context& owned,const OfficeKey& key,uint64_t expectedRevision,
        const std::vector<SymbolChoice>& remaining) {
    if(remaining.empty() || !stageSymbols(owned,key,expectedRevision,remaining))return false;
    auto& value=owned.value;
    std::unordered_map<int32_t,size_t> indices;
    for(size_t i=0;i<value.cand_symbol.size();++i)indices.emplace(value.cand_symbol[i]->id,i);
    std::vector<df::item*> items;std::vector<int32_t> selected,previous,amounts;
    items.reserve(remaining.size());selected.reserve(remaining.size());previous.reserve(remaining.size());amounts.reserve(remaining.size());
    for(const auto& edit:remaining) {
        const auto i=indices.at(edit.itemId);
        // A prior effect arriving here twice must not be silently accepted.
        if(value.cand_symbol_new_ind[i]==value.cand_symbol_is_symbol_of_ind[i])return false;
        items.push_back(value.cand_symbol[i]);selected.push_back(value.cand_symbol_new_ind[i]);
        previous.push_back(value.cand_symbol_is_symbol_of_ind[i]);amounts.push_back(value.cand_symbol_value[i]);
    }
    value.cand_symbol=std::move(items);value.cand_symbol_new_ind=std::move(selected);
    value.cand_symbol_is_symbol_of_ind=std::move(previous);value.cand_symbol_value=std::move(amounts);
    return true;
}
}
