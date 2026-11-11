#pragma once
#include "nobles_native.h"
#include "location_staff_mutation_native.h"
#include "df/squad_position.h"
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
// Preparation restores read-only scratch before returning. In particular these
// guards must not surround a subsequent simulation commit.
inline bool prepareDraft(Context& owned,const std::vector<DraftChoice>& choices) {
    if(!ready() || choices.size()>65536)return false;
    auto* base=owned.base;
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x674;++i){hash^=base[0x424b3f+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x81c7b0d7fa7e30e8);
    }();
    if(!pinned || df::global::world->units.active.size()>1048576)return false;
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::LaborEligibilityCacheRestore caches;
    for(auto* unit:df::global::world->units.active)if(!caches.capture(unit,-1))return false;
    reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421f30)(&owned.value);
    for(const auto& choice:choices) {
        size_t target=owned.value.noblelist.size();
        for(size_t i=0;i<owned.value.noblelist.size();++i) {
            const auto* row=owned.value.noblelist[i];if(!row || !row->ep)return false;
            if(row->enid==choice.entityId && row->ep->id==choice.positionId &&
               (row->epp?row->epp->id:-1)==choice.assignmentId && (row->un?row->un->id:-1)==choice.expectedUnitId) {
                if(target!=owned.value.noblelist.size())return false;
                target=i;
            }
        }
        if(!stageAppointment(owned,target,choice.unitId))return false;
    }
    return true;
}

// No pointers survive the preview and no native menu state is consulted.
inline std::optional<std::vector<DraftRow>> draftPreview(const std::vector<DraftChoice>& choices) {
    if(!ready())return std::nullopt;
    Context owned(reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr)));
    if(!prepareDraft(owned,choices))return std::nullopt;
    std::vector<DraftRow> rows;
    for(size_t i=0;i<owned.value.noblelist.size();++i) {
        const auto* row=owned.value.noblelist[i];if(!row || !row->ep)return std::nullopt;
        rows.push_back({row->enid,row->ep->id,row->epp?row->epp->id:-1,row->un?row->un->id:-1,
            row->nem?row->nem->id:-1,owned.value.spec_hfid[i]});
    }
    return rows;
}

inline bool draftCommitReady() {
    if(!ready() || !df3d_area::religiousStaffAssignmentFunctions())return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<const void*>(&df::global::world->squads.all)!=base+0x24e37c0 ||
       reinterpret_cast<const void*>(&df::global::world->nemesis.civilized_actor)!=base+0x23e51a8 ||
       reinterpret_cast<const void*>(&df::global::plotinfo->equipment.update)!=base+0x2399858)return false;
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x42a5a0,0x4f0,UINT64_C(0xfaf37eb5c5a1e2fe)},
            {0xdde080,0xb0,UINT64_C(0x12ff168f6ee921e3)},
            {0x109420,0x7f,UINT64_C(0x1d8b95d06d3bd24a)},
            {0xbb9b0,0x74,UINT64_C(0x7532991bab65be09)}};
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    return pinned;
}
enum class DraftCommitOutcome {Unavailable,Rejected,Applied,Unknown};
// Runs at a bridge safe point. The future request owner must bind this operation
// to its session/revision and deduplicate it; Unknown must never be replayed.
// The diagnostic route below is not a public asynchronous command contract.
inline DraftCommitOutcome commitDraft(const std::vector<DraftChoice>& choices) {
    if(!draftCommitReady())return DraftCommitOutcome::Unavailable;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    Context owned(base);
    struct Expected {df::historical_entity* entity;int32_t assignment,holder,previous;bool created;};
    std::vector<Expected> effects;
    try {
        if(choices.empty() || !prepareDraft(owned,choices))return DraftCommitOutcome::Rejected;
        using FindNemesis=df::nemesis_record*(*)(std::vector<df::nemesis_record*>*,int32_t);
        const auto findNemesis=reinterpret_cast<FindNemesis>(base+0xdde080);
        for(const auto* row:owned.value.noblelist) {
            if(!row || !row->ep)return DraftCommitOutcome::Rejected;
            auto* entity=df::historical_entity::find(row->enid);
            if(!entity || entity->positions.assignments.size()>65536 || entity->positions.own.size()>65536 ||
               std::find(entity->positions.own.begin(),entity->positions.own.end(),row->ep)==entity->positions.own.end())return DraftCommitOutcome::Rejected;
            if(row->epp && std::find(entity->positions.assignments.begin(),entity->positions.assignments.end(),row->epp)==entity->positions.assignments.end())return DraftCommitOutcome::Rejected;
            auto* previous=row->epp && row->epp->histfig!=-1?findNemesis(&df::global::world->nemesis.all,row->epp->histfig):nullptr;
            if(previous==row->nem)continue;
            // The native wrapper dereferences units for job/military cleanup.
            // Reject incomplete records before any native effect begins.
            for(auto* nemesis:{previous,row->nem})if(nemesis && (!nemesis->figure || !nemesis->unit ||
                df::unit::find(nemesis->unit->id)!=nemesis->unit || nemesis->unit->hist_figure_id!=nemesis->figure->id))return DraftCommitOutcome::Rejected;
            if(row->epp && row->epp->squad_id>=0)if(auto* squad=df::squad::find(row->epp->squad_id)) {
                if(squad->positions.size()>65536)return DraftCommitOutcome::Rejected;
                for(auto* slot:squad->positions)if(!slot)return DraftCommitOutcome::Rejected;
            }
            int32_t assignment=row->epp?row->epp->id:entity->positions.next_assignment_id;
            if(!row->epp) {
                if(assignment<0 || assignment>INT32_MAX-int32_t(owned.value.noblelist.size()))return DraftCommitOutcome::Rejected;
                for(const auto& prior:effects)if(prior.entity==entity && prior.created)++assignment;
                for(const auto* existing:entity->positions.assignments)
                    if(!existing || existing->id>=entity->positions.next_assignment_id)return DraftCommitOutcome::Rejected;
            }
            effects.push_back({entity,assignment,row->nem?row->nem->figure->id:-1,
                row->nem?row->nem->figure->id:row->epp->histfig2,!row->epp});
        }
    } catch(const std::exception&) {return DraftCommitOutcome::Rejected;}
    try {
        // Entire audited apply/cleanup routine with our own rows and containers.
        // Its globals are simulation entities, figures, units, squads and
        // equipment state. No menu, input, camera or rendering globals are read.
        reinterpret_cast<void(*)(df::administrators_interfacest*,bool)>(base+0x42a5a0)(&owned.value,true);
        for(const auto& effect:effects) {
            const df::entity_position_assignment* found=nullptr;
            for(auto* assignment:effect.entity->positions.assignments)if(assignment && assignment->id==effect.assignment) {
                if(found)return DraftCommitOutcome::Unknown;
                found=assignment;
            }
            if(!found || found->histfig!=effect.holder || found->histfig2!=effect.previous)return DraftCommitOutcome::Unknown;
        }
        return DraftCommitOutcome::Applied;
    } catch(const std::exception&) {return DraftCommitOutcome::Unknown;}
}
}
