#pragma once
#include "knowledge_detail_native.h"
#include "df/dance_form.h"
#include "df/dance_form_section.h"
#include "df/dance_form_move.h"
#include "df/history_event_agreement_formedst.h"
#include "df/history_event_agreement_concludedst.h"
#include "df/agreement.h"
#include "df/agreement_details.h"
#include "df/agreement_details_data_join_party.h"
#include "df/agreement_details_data_plot_steal_artifact.h"
#include "df/agreement_details_data_retrieve_artifact.h"
#include "df/identity.h"
#include "df/history_event_masterpiece_lostst.h"
#include "df/history_event_performancest.h"
#include "df/historical_entity.h"
#include "df/entity_occasion_info.h"
#include "df/entity_occasion.h"
#include "df/entity_occasion_schedule.h"
#include "df/history_event_artifact_createdst.h"
#include "df/history_event_artifact_claim_formedst.h"
#include "df/history_event_artifact_copiedst.h"
#include "df/history_event_artifact_destroyedst.h"
#include "df/history_event_artifact_droppedst.h"
#include "df/history_event_artifact_foundst.h"
#include "df/history_event_artifact_givenst.h"
#include "df/history_event_artifact_hiddenst.h"
#include "df/history_event_artifact_lostst.h"
#include "df/history_event_artifact_possessedst.h"
#include "df/history_event_artifact_recoveredst.h"
#include "df/history_event_artifact_storedst.h"
#include "df/history_event_artifact_transformedst.h"
#include "df/history_event_hf_act_on_artifactst.h"
#include "df/history_event_hf_learns_secretst.h"
#include "df/history_event_entity_dissolvedst.h"
#include "df/history_event_hf_gains_secret_goalst.h"
#include "df/history_event_item_stolenst.h"
#include "df/history_event_hist_figure_diedst.h"
#include "df/general_ref.h"
#include "df/artifact_record.h"
#include "df/item_coinst.h"
#include "df/coin_batch.h"
#include <unordered_set>
#include <cstring>
namespace df3d_creature {
// Called only after description readiness has pinned the native name helper.
// This closes coin dependencies, not arbitrary item-caption graphs.
inline bool knowledgeArtifactInputsValid(int32_t artifact_id) {
    auto* artifact=df::artifact_record::find(artifact_id);
    if(!artifact)return true; // Native missing-artifact wording.
    if(!artifact->item)return false;
    if(artifact->item->getType()!=df::item_type::COIN)return true;
    auto name=artifact->name;
    std::string translated;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&name,&translated,true,false);
    if(!translated.empty())return true;
    const auto index=static_cast<df::item_coinst*>(artifact->item)->coin_batch;
    if(index==-1)return true;
    if(!df::global::world)return false;
    const auto& batches=df::global::world->coin_batches.all;
    if(index<0 || size_t(index)>=batches.size() || !batches[size_t(index)])return false;
    const auto issuer_id=batches[size_t(index)]->entity;
    if(issuer_id==-1)return true;
    const auto* issuer=df::historical_entity::find(issuer_id);
    return issuer && issuer->entity_raw;
}
inline bool knowledgeItemArtifactInputsValid(int32_t item_id) {
    auto* item=df::item::find(item_id);
    if(!item || !item->flags.bits.artifact)return true;
    for(auto* ref:item->general_refs) {
        if(!ref)return false;
        if(ref->getType()!=df::general_ref_type::IS_ARTIFACT)continue;
        // Native edfc20 is a read-only artifact lookup. Stop at the first
        // matching reference even when its target is missing, as DF does.
        const auto* artifact=ref->getArtifact();
        return !artifact || knowledgeArtifactInputsValid(artifact->id);
    }
    return true;
}
// The generated circumstance union has no artifact-named member. Native
// b5a6c0 passes its raw int32 payload to b94400 for exactly these two thoughts.
template<class Circumstance>
inline bool knowledgeCircumstanceArtifactInputsValid(const Circumstance& circumstance) {
    if(circumstance.type!=df::unit_thought_type::AcquireArtifact &&
       circumstance.type!=df::unit_thought_type::GaveArtifact)return true;
    int32_t artifact_id;
    static_assert(sizeof(circumstance.data)==sizeof(artifact_id));
    std::memcpy(&artifact_id,&circumstance.data,sizeof(artifact_id));
    return knowledgeArtifactInputsValid(artifact_id);
}
inline bool eventCircumstanceArtifactInputsValid(df::history_event* event) {
    // CHANGE_HF_MOOD and CHANGE_HF_STATE also call b5a6c0, but pass constant
    // -1 for the circumstance rather than forwarding a stored dependency.
    switch(event->getType()) {
    case df::history_event_type::ARTIFACT_CLAIM_FORMED:
        return knowledgeCircumstanceArtifactInputsValid(static_cast<df::history_event_artifact_claim_formedst*>(event)->circumstance);
    case df::history_event_type::ARTIFACT_GIVEN:
        return knowledgeCircumstanceArtifactInputsValid(static_cast<df::history_event_artifact_givenst*>(event)->circumstance);
    case df::history_event_type::ARTIFACT_POSSESSED:
        return knowledgeCircumstanceArtifactInputsValid(static_cast<df::history_event_artifact_possessedst*>(event)->circumstance);
    case df::history_event_type::ENTITY_DISSOLVED:
        return knowledgeCircumstanceArtifactInputsValid(static_cast<df::history_event_entity_dissolvedst*>(event)->circumstance);
    case df::history_event_type::HF_GAINS_SECRET_GOAL:
        return knowledgeCircumstanceArtifactInputsValid(static_cast<df::history_event_hf_gains_secret_goalst*>(event)->circumstance);
    case df::history_event_type::ITEM_STOLEN:
        return knowledgeCircumstanceArtifactInputsValid(static_cast<df::history_event_item_stolenst*>(event)->circumstance);
    default:return true;
    }
}
// Artifact dependencies verified against b94400 call arguments. Agreement
// payloads are handled separately below.
inline bool directEventArtifactInputsValid(df::history_event* event) {
    switch(event->getType()) {
    case df::history_event_type::ARTIFACT_CREATED:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_createdst*>(event)->artifact_id);
    case df::history_event_type::ARTIFACT_CLAIM_FORMED:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_claim_formedst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_COPIED:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_copiedst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_DESTROYED:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_destroyedst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_DROPPED:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_droppedst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_FOUND:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_foundst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_GIVEN:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_givenst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_HIDDEN:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_hiddenst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_LOST:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_lostst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_POSSESSED:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_possessedst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_RECOVERED:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_recoveredst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_STORED:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_artifact_storedst*>(event)->artifact);
    case df::history_event_type::ARTIFACT_TRANSFORMED: {
        const auto* value=static_cast<df::history_event_artifact_transformedst*>(event);
        if(!knowledgeArtifactInputsValid(value->new_artifact))return false;
        for(const auto id:value->old_artifact)if(!knowledgeArtifactInputsValid(id))return false;
        return true;
    }
    case df::history_event_type::HF_ACT_ON_ARTIFACT:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_hf_act_on_artifactst*>(event)->artifact);
    case df::history_event_type::HF_LEARNS_SECRET:
        return knowledgeArtifactInputsValid(static_cast<df::history_event_hf_learns_secretst*>(event)->artifact);
    case df::history_event_type::ITEM_STOLEN:
        return knowledgeItemArtifactInputsValid(static_cast<df::history_event_item_stolenst*>(event)->item);
    case df::history_event_type::HIST_FIGURE_DIED: {
        const auto& weapon=static_cast<df::history_event_hist_figure_diedst*>(event)->weapon;
        return knowledgeItemArtifactInputsValid(weapon.item) && knowledgeItemArtifactInputsValid(weapon.shooter_item);
    }
    default:return true;
    }
}
// A targeted diagnostic guard, not general event-graph validation. JoinParty
// reasons2/24 reach c3a590(false), whose profession formatter treats narrowed
// comparison race -2 as a request to read native UI state.
inline bool directAgreementIdentityInputsValid(int32_t event_id) {
    auto* event=df::history_event::find(event_id);
    if(!event || event->getType()!=df::history_event_type::AGREEMENT_FORMED)return true;
    const auto* agreement=df::agreement::find(static_cast<const df::history_event_agreement_formedst*>(event)->agreement_id);
    if(!agreement || agreement->parties.empty() || agreement->details.empty())return true;
    const auto* detail=agreement->details.front();if(!detail)return false;
    if(detail->type!=df::agreement_details_type::JoinParty)return true;
    const auto* data=detail->data.JoinParty;if(!data)return false;
    if((int32_t(data->reason)!=2 && int32_t(data->reason)!=24) || data->figure!=-1)return true;
    const auto* identity=df::identity::find(data->entity);
    if(!identity || identity->impersonated_hf!=-1)return true;
    const auto profession=uint16_t(identity->profession);
    return profession==UINT16_C(0xffff) || profession==102 || uint16_t(identity->race)!=UINT16_C(0xfffe);
}
inline bool agreementArtifactInputsValid(df::history_event* event) {
    const auto type=event->getType();
    const bool formed=type==df::history_event_type::AGREEMENT_FORMED;
    if(!formed && type!=df::history_event_type::AGREEMENT_CONCLUDED)return true;
    const auto id=formed ? static_cast<df::history_event_agreement_formedst*>(event)->agreement_id
                        : static_cast<df::history_event_agreement_concludedst*>(event)->agreement_id;
    const auto* agreement=df::agreement::find(id);
    // Both native phrases use only the first detail. Only FORMED requires
    // nonempty parties before dispatching that detail.
    if(!agreement || agreement->details.empty() || (formed && agreement->parties.empty()))return true;
    const auto* detail=agreement->details.front();if(!detail)return false;
    if(detail->type==df::agreement_details_type::RetrieveArtifact) {
        const auto* data=detail->data.RetrieveArtifact;
        return data && knowledgeArtifactInputsValid(data->artifact);
    }
    if(formed && detail->type==df::agreement_details_type::PlotStealArtifact) {
        const auto* data=detail->data.PlotStealArtifact;
        return data && knowledgeArtifactInputsValid(data->artifact_id);
    }
    return true;
}
// Both audited recursive phrase classes have at most one event successor.
// Walk iteratively so validation itself cannot overflow on a cyclic graph.
inline bool knowledgeEventInputsValid(int32_t event_id) {
    std::unordered_set<int32_t> visited;
    while(event_id>=0) {
        auto* event=df::history_event::find(event_id);if(!event)return true;
        if(!visited.insert(event_id).second)return false;
        if(!directAgreementIdentityInputsValid(event_id))return false;
        if(!agreementArtifactInputsValid(event))return false;
        if(!directEventArtifactInputsValid(event))return false;
        if(!eventCircumstanceArtifactInputsValid(event))return false;
        if(event->getType()==df::history_event_type::MASTERPIECE_LOST) {
            event_id=static_cast<df::history_event_masterpiece_lostst*>(event)->creation_event;
            continue;
        }
        if(event->getType()!=df::history_event_type::PERFORMANCE)return true;
        const auto* performance=static_cast<df::history_event_performancest*>(event);
        const auto* entity=df::historical_entity::find(performance->entity);
        if(!entity || !entity->occasion_info)return true;
        const df::entity_occasion* occasion=nullptr;
        for(const auto* candidate:entity->occasion_info->occasions) {
            if(!candidate)return false;
            if(candidate->id==performance->occasion){occasion=candidate;break;}
        }
        if(!occasion || performance->schedule<0 || size_t(performance->schedule)>=occasion->schedule.size())return true;
        const auto* schedule=occasion->schedule[size_t(performance->schedule)];
        if(!schedule || int32_t(schedule->type)!=3)return true;
        event_id=schedule->reference;
    }
    return true;
}
// Diagnostic formatter, not yet a production provider. Event-type acceptance
// is tracked separately from the independently owned dance data graph.
inline std::optional<std::string> danceDetailProbe(df::dance_form* source) {
    if(!source || !knowledgeDescriptionReady() || source->sections.size()>4096 || source->moves.size()>4096)return std::nullopt;
    if(!df::global::world)return std::nullopt;
    if(!knowledgeEventInputsValid(source->event))return std::nullopt;
    for(const auto* section:source->sections)
        if(!section || !knowledgeEventInputsValid(section->acts_out_event))return std::nullopt;
    KnowledgeMaterialCacheRestore cache_restore(df::global::world->raws.creatures.hist_fig_to_creature_map);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    constexpr Pin pins[]={
        {0xca0d00,0x55,UINT64_C(0x6891982ef52f2367)},
        {0x5be970,0x536,UINT64_C(0xd785ec19f3aa4618)},
        {0x52c2b0,0xd8,UINT64_C(0x38b6489e35387929)},
        {0xc3a590,0xcbf,UINT64_C(0x09a894440651f51f)},
        {0x132e0c0,0x368,UINT64_C(0x5020a6b8e463a24d)},
        {0x4ea820,0x42e8,UINT64_C(0x9cb7bc42be4693f7)},
        {0x4e99f0,0xe24,UINT64_C(0xbe3650a1c5ba887e)},
        {0x7da30,0xb3,UINT64_C(0xa91f2722090923d0)},
        {0xb89e90,0x12f,UINT64_C(0xedf91acba90c5067)},
        {0xb65030,0x1b8,UINT64_C(0x6557e947120f0a0b)},
        {0xb8c2b0,0x6db,UINT64_C(0x393d1fb27e6e1a4b)},
        {0xb69bb0,0x17e,UINT64_C(0x770b7c3e1cfbf0a6)},
        {0xb69d30,0x1c9,UINT64_C(0x8f89c4f250e5b86b)},
        {0xb77430,0x2e7,UINT64_C(0x68e110a467cb9073)},
        {0xb80420,0x6b4,UINT64_C(0xde44fccbc2765650)},
        {0xb93930,0x15a,UINT64_C(0x1ab3438f9be56fa2)},
        {0xb94090,0x368,UINT64_C(0xb4728c2a90d0f54e)},
        {0xb94940,0xf6,UINT64_C(0x9212620ec0e20427)},
        {0xb94a40,0x157,UINT64_C(0x47255515af7da23e)},
        {0xb92640,0x2b4,UINT64_C(0xed9f612ded76daea)},
        {0xb5a6c0,0x13f1,UINT64_C(0x4e95e628626945c4)},
        {0x1ba140,0xa8,UINT64_C(0xdb6eb9072d509b29)},
        {0x6ff00,0xa8,UINT64_C(0x95c810961f82c229)},
        {0x7db20,0xb6,UINT64_C(0x4ee4244d4f7af0ae)},
        {0xbad30,0x118,UINT64_C(0xea445ea01cfc50c1)},
        {0x66b70,0x5c,UINT64_C(0xb65a09fabb030b21)},
        {0xb9980,0x1e,UINT64_C(0xfaa5c1133f00b330)},
    };
    for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return std::nullopt;}
    struct OwnedForm final:df::dance_form {OwnedForm():df::dance_form(){}} form;
    struct OwnedSection final:df::dance_form_section {OwnedSection():df::dance_form_section(){}};
    struct OwnedMove final:df::dance_form_move {OwnedMove():df::dance_form_move(){}};
    static_cast<df::dance_form&>(form)=*source;
    form.sections.clear();form.moves.clear();
    std::vector<std::unique_ptr<OwnedSection>> sections;
    std::vector<std::unique_ptr<OwnedMove>> moves;
    for(const auto* original:source->sections){
        if(!original)return std::nullopt;
        auto value=std::make_unique<OwnedSection>();static_cast<df::dance_form_section&>(*value)=*original;
        form.sections.push_back(value.get());sections.push_back(std::move(value));
    }
    for(const auto* original:source->moves){
        if(!original)return std::nullopt;
        auto value=std::make_unique<OwnedMove>();static_cast<df::dance_form_move&>(*value)=*original;
        form.moves.push_back(value.get());moves.push_back(std::move(value));
    }
    std::string result(reinterpret_cast<const char*>(base+0x1602430));
    reinterpret_cast<void(*)(df::dance_form*,std::string*)>(base+0x4ea820)(&form,&result);
    if(result.size()>65536)return std::nullopt;
    return result;
}
}
