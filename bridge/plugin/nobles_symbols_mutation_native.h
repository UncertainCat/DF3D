#pragma once
#include "nobles_symbols_native.h"
#include "df/history_event_artifact_createdst.h"

namespace df3d_nobles {
inline bool symbolApplyReady() {
    if(!symbolsReady())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto at=[base](const void* address,size_t rva){return address==base+rva;};
    const auto& world=*df::global::world;
    if(!at(df::global::artifact_next_id,0x2131b1c) || !at(df::global::hist_event_next_id,0x2131b18) ||
       !at(df::global::cur_year,0x23746f4) || !at(df::global::cur_year_tick,0x2387fc4) ||
       !at(&df::global::plotinfo->group_id,0x2393678) || !at(&df::global::plotinfo->site_id,0x2393674) ||
       !at(&world.history.events,0x24f9cb8) || !at(&world.history.active_event_collections,0x24fa2f0) ||
       !at(&world.history.active_mission,0x24fa318) ||
       !at(&world.worldgen.worldgen_parms.reveal_all_history,0x24f9c70))return false;
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x4227b0,0x538,UINT64_C(0xcf6b6a1aea062677)},
            {0x9dce20,0x212,UINT64_C(0x2c381a4fcc10d0f5)},
            {0x13cc4d0,0x139,UINT64_C(0xf660081358097d16)},
            {0x727b0,0x23,UINT64_C(0x81ce1c3a8cbc6068)},
            {0xc98970,0x123,UINT64_C(0x79d289392dbe9794)},
            {0x7d170,0x115,UINT64_C(0x7fc84cc158795b9d)},
            {0x2a6a90,0x109,UINT64_C(0x59fcac324129a4b2)},
            {0xfe7e0,0xdd,UINT64_C(0x7f4746b34927cc08)},
            {0xfe570,0xab,UINT64_C(0x9db774b89d9f7f44)},
            {0x72660,0x7d,UINT64_C(0x2414953f9e9e9670)},
            {0xedf070,0x9e4,UINT64_C(0x3a7d957c1bb23db0)},
            {0x8b8474,0x91,UINT64_C(0xb50030f61b94c4ee)},
            {0x931860,0x2f9,UINT64_C(0x3f40974d82863764)},
            {0xa92860,0x17cb,UINT64_C(0x627504395969e689)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    return pinned;
}
struct SymbolStep {
    DraftCommitOutcome outcome=DraftCommitOutcome::Rejected;
    int32_t namingArtifactId=-1;
    // Native order is preserved for the next step, after the name editor closes.
    std::vector<SymbolChoice> remaining;
};
// Safe-point only: the context must have been freshly prepared and staged in
// this call. No pointers survive the call. A future asynchronous owner must
// retain the returned IDs/order and deduplicate effects, never replay Unknown.
inline SymbolStep applySymbolStep(Context& owned,const OfficeKey& key) {
    SymbolStep result;
    if(!symbolApplyReady()){result.outcome=DraftCommitOutcome::Unavailable;return result;}
    auto& value=owned.value;
    const size_t count=value.cand_symbol.size();
    if(count>1048576 || value.cand_symbol_new_ind.size()!=count ||
       value.cand_symbol_is_symbol_of_ind.size()!=count || value.cand_symbol_value.size()!=count)return result;
    auto* fortress=df::global::plotinfo->main.fortress_entity;
    if(!fortress || fortress->id!=df::global::plotinfo->group_id)return result;
    int32_t target=-1;
    for(size_t i=0;i<value.noblelist.size();++i) {
        const auto* row=value.noblelist[i];if(!row || !row->ep)return result;
        if(row->enid==key.entityId && row->ep->id==key.positionId && row->epp &&
           row->epp->id==key.assignmentId && owned.slot(row)==key.draftSlot){if(target!=-1)return result;target=int32_t(i);}
    }
    if(target<0)return result;
    const auto artifactOf=[](df::item* item)->df::artifact_record* {
        for(auto* ref:item->general_refs)if(ref && ref->getType()==df::general_ref_type::IS_ARTIFACT)return ref->getArtifact();
        return nullptr;
    };
    for(size_t i=0;i<count;++i) {
        auto* item=value.cand_symbol[i];
        if(!item || df::item::find(item->id)!=item)return result;
        if(item->flags.bits.artifact) {
            auto* artifact=artifactOf(item);if(!artifact || artifact->item!=item || df::artifact_record::find(artifact->id)!=artifact)return result;
        }
        for(auto index:{value.cand_symbol_new_ind[i],value.cand_symbol_is_symbol_of_ind[i]}) {
            if(index==-1)continue;
            if(index<0 || size_t(index)>=value.noblelist.size())return result;
            auto* row=value.noblelist[index];auto* entity=df::historical_entity::find(row->enid);
            if(!entity || !row->epp || std::find(entity->positions.assignments.begin(),entity->positions.assignments.end(),row->epp)==entity->positions.assignments.end())return result;
        }
    }
    try {
        // All scratch guards have ended before crossing this effects boundary.
        result.outcome=DraftCommitOutcome::Unknown;
        const auto apply=reinterpret_cast<void(*)(df::administrators_interfacest*)>(owned.base+0x4227b0);
        value.handling_symbol_closure_ind=0;apply(&value);
        if(value.handling_symbol_closure_ind!=-1) {
            const auto index=value.handling_symbol_closure_ind;
            if(index<0 || size_t(index)>=count)return result;
            auto* item=value.cand_symbol[index];
            if(item->flags.bits.artifact || value.cand_symbol_new_ind[index]!=target)return result;
            // Inline update8b8474..8b8505: semantic item categorization,
            // artifact/reference allocation, history event and native name.
            // The global name-editor opener and native input are not called.
            item->uncategorize();
            auto* artifact=reinterpret_cast<df::artifact_record*(*)()>(owned.base+0x727b0)();
            if(!artifact)return result;
            artifact->item=item;
            reinterpret_cast<void(*)(df::item*,int32_t,int32_t)>(owned.base+0x72660)(item,1,artifact->id);
            item->flags.bits.artifact=true;item->categorize(true);
            auto* event=reinterpret_cast<df::history_event_artifact_createdst*(*)()>(owned.base+0x7d170)();
            if(!event)return result;
            event->year=*df::global::cur_year;event->seconds=*df::global::cur_year_tick;
            event->artifact_id=artifact->id;event->entity=df::global::plotinfo->group_id;
            event->site=df::global::plotinfo->site_id;event->flags2.bits.name_only=true;event->add_to_classes();
            reinterpret_cast<void(*)(df::historical_entity*,df::language_name*,int16_t)>(owned.base+0x931860)(fortress,&artifact->name,1);
            result.namingArtifactId=artifact->id;
            apply(&value);
        }
        auto next=value.handling_symbol_closure_ind;
        if(next< -1 || (next!=-1 && size_t(next)>=count))return result;
        const auto completed=next==-1?count:size_t(next);
        for(size_t i=0;i<completed;++i) {
            const auto selected=value.cand_symbol_new_ind[i];
            if(selected==value.cand_symbol_is_symbol_of_ind[i])continue;
            auto* artifact=artifactOf(value.cand_symbol[i]);if(!artifact)return result;
            if(selected!=-1) {
                const auto* row=value.noblelist[selected];const auto* entity=df::historical_entity::find(row->enid);
                bool found=false;
                for(const auto* claim:entity->artifact_claims)if(claim && claim->artifact_id==artifact->id &&
                    int(claim->claim_type)==0 && claim->symbol_claim_id==row->epp->id && claim->renounce_event==-1)found=true;
                if(!found)return result;
            }else {
                for(const auto* entity:{df::historical_entity::find(df::global::plotinfo->civ_id),fortress})if(entity)
                    for(const auto* claim:entity->artifact_claims)if(claim && claim->artifact_id==artifact->id && claim->renounce_event==-1)return result;
            }
        }
        if(next!=-1) {
            for(size_t i=size_t(next);i<count;++i)if(value.cand_symbol_new_ind[i]!=value.cand_symbol_is_symbol_of_ind[i])
                result.remaining.push_back({value.cand_symbol[i]->id,value.cand_symbol_new_ind[i]==target});
        }
        result.outcome=DraftCommitOutcome::Applied;
    }catch(const std::exception&){result.outcome=DraftCommitOutcome::Unknown;}
    return result;
}
}
