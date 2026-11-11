#pragma once
#include "nobles_native.h"
#include "df/general_ref.h"
#include "df/general_ref_type.h"

namespace df3d_nobles {
// Local draft operations only. The context must be built independently by
// 421f30, never copied from game.main_interface. No simulation assignment is
// modified here. The caller must discard the context if preparation fails.
inline bool stageAppointment(Context& owned,size_t index,int32_t unitId) {
    auto& value=owned.value;
    const auto count=value.noblelist.size();
    if(count>65535 || index>=count || value.spec_prof.size()!=count ||
       value.spec_hfid.size()!=count || value.spec_enid.size()!=count || unitId< -1)return false;
    for(auto* row:value.noblelist)if(!row || !row->ep)return false;
    auto* target=value.noblelist[index];
    const auto allowed=appointmentAvailable(*target,value.noblelist);
    if(!allowed || !*allowed)return false;
    // Native candidate military-conflict checks inspect this draft's rows.
    // General historical-position eligibility still comes from simulation.
    reinterpret_cast<void(*)(df::administrators_interfacest*,df::noblelistst*)>(owned.base+0x423df0)(&value,target);
    if(value.candidate.size()>1048576)return false;
    df::unit* selected=nullptr;bool found=false;
    for(auto* candidate:value.candidate) {
        if(!candidate)return false;
        if((candidate->un?candidate->un->id:-1)==unitId) {
            if(found)return false;
            found=true;selected=candidate->un;
        }
    }
    if(!found)return false;
    df::nemesis_record* nemesis=nullptr;
    if(selected) {
        if(selected->general_refs.size()>65536)return false;
        // Same virtual reference lookup as feed424b8c..424bc7.
        for(auto* ref:selected->general_refs) {
            if(!ref)return false;
            if(ref->getType()==df::general_ref_type::IS_NEMESIS){nemesis=ref->getNemesis();break;}
        }
        if(!nemesis || nemesis->unit!=selected || !nemesis->figure ||
           nemesis->figure->id!=selected->hist_figure_id)return false;
    }
    static_assert(offsetof(df::entity_position,squad_size)==0x278);
    static_assert(offsetof(df::entity_position,number)==0x2d8);
    static_assert(offsetof(df::entity_position,precedence)==0x2d0);
    static_assert(sizeof(df::unitpropertyplacementst)==0x5c);
    const bool unlimitedNew=target->ep->number==-1 && !target->epp;
    const auto allocate=reinterpret_cast<void*(*)(size_t)>(owned.base+0x1539690);
    const auto release=reinterpret_cast<void(*)(void*,size_t)>(owned.base+0x1539680);
    // Reserve all parallel containers before changing membership. New rows and
    // summaries use DF's allocator because native421dc0 owns their cleanup.
    value.noblelist.reserve(count+1);value.spec_prof.reserve(count+1);
    value.spec_hfid.reserve(count+1);value.spec_enid.reserve(count+1);
    if(selected && !target->upplist) {
        target->upplist=static_cast<df::unitpropertyplacementst*>(allocate(sizeof(df::unitpropertyplacementst)));
        if(!target->upplist)return false;
    }
    target->un=selected;target->nem=nemesis;
    value.spec_hfid[index]=selected?selected->hist_figure_id:-1;
    const auto erase=[&](size_t at) {
        auto* row=value.noblelist[at];
        if(row->upplist)release(row->upplist,sizeof(df::unitpropertyplacementst));
        release(row,sizeof(df::noblelistst));
        value.noblelist.erase(value.noblelist.begin()+at);
        value.spec_prof.erase(value.spec_prof.begin()+at);
        value.spec_hfid.erase(value.spec_hfid.begin()+at);
        value.spec_enid.erase(value.spec_enid.begin()+at);
    };
    if(!selected) {
        if(unlimitedNew)erase(index);
        return true;
    }
    reinterpret_cast<void(*)(df::unit*,df::unitpropertyplacementst*,int32_t)>(owned.base+0x136ccc0)(selected,target->upplist,-1);
    // Native424c5a..424e34 resolves military conflicts in reverse list order.
    // Existing assignments remain as vacant drafts; uncommitted unlimited
    // assignments disappear. Placeholder insertion follows the selected row.
    size_t insertion=index+1;
    if(target->ep->squad_size>0) {
        for(size_t i=value.noblelist.size();i-->0;) {
            auto* other=value.noblelist[i];
            if(other==target || other->ep->squad_size==0 || other->un!=selected)continue;
            other->un=nullptr;other->nem=nullptr;value.spec_hfid[i]=-1;
            if(other->ep->number==-1 && !other->epp) {
                erase(i);if(i<insertion)--insertion;
            }
        }
    }
    if(unlimitedNew) {
        auto* blank=static_cast<df::noblelistst*>(allocate(sizeof(df::noblelistst)));
        if(!blank)return false;
        blank->un=nullptr;blank->nem=nullptr;blank->upplist=nullptr;
        blank->ep=target->ep;blank->epp=nullptr;blank->enid=target->enid;blank->value=target->ep->precedence;
        value.noblelist.insert(value.noblelist.begin()+insertion,blank);
        value.spec_prof.insert(value.spec_prof.begin()+insertion,nullptr);
        value.spec_hfid.insert(value.spec_hfid.begin()+insertion,-1);
        value.spec_enid.insert(value.spec_enid.begin()+insertion,blank->enid);
    }
    return true;
}

struct DraftChoice {int32_t entityId,positionId,assignmentId,expectedUnitId,unitId;};
struct DraftRow {int32_t entityId,positionId,assignmentId,unitId,nemesisId,histfigId;};
// Diagnostic and future semantic-draft preparation share the same owned replay.
// No pointers survive this call and no native menu state is consulted.
inline std::optional<std::vector<DraftRow>> draftPreview(const std::vector<DraftChoice>& choices) {
    if(!ready() || choices.size()>65536)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x674;++i){hash^=base[0x424b3f+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x81c7b0d7fa7e30e8);
    }();
    if(!pinned || df::global::world->units.active.size()>1048576)return std::nullopt;
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::LaborEligibilityCacheRestore caches;
    for(auto* unit:df::global::world->units.active)if(!caches.capture(unit,-1))return std::nullopt;
    Context owned(base);
    reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421f30)(&owned.value);
    for(const auto& choice:choices) {
        size_t target=owned.value.noblelist.size();
        for(size_t i=0;i<owned.value.noblelist.size();++i) {
            const auto* row=owned.value.noblelist[i];if(!row || !row->ep)return std::nullopt;
            if(row->enid==choice.entityId && row->ep->id==choice.positionId &&
               (row->epp?row->epp->id:-1)==choice.assignmentId && (row->un?row->un->id:-1)==choice.expectedUnitId) {
                if(target!=owned.value.noblelist.size())return std::nullopt;
                target=i;
            }
        }
        if(!stageAppointment(owned,target,choice.unitId))return std::nullopt;
    }
    std::vector<DraftRow> rows;
    for(size_t i=0;i<owned.value.noblelist.size();++i) {
        const auto* row=owned.value.noblelist[i];if(!row || !row->ep)return std::nullopt;
        rows.push_back({row->enid,row->ep->id,row->epp?row->epp->id:-1,row->un?row->un->id:-1,
            row->nem?row->nem->id:-1,owned.value.spec_hfid[i]});
    }
    return rows;
}
}
