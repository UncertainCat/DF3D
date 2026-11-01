#pragma once
#include "knowledge_detail_native.h"
#include "df/dance_form.h"
#include "df/dance_form_section.h"
#include "df/dance_form_move.h"
#include "df/history_event_agreement_formedst.h"
#include "df/agreement.h"
#include "df/agreement_details.h"
#include "df/agreement_details_data_join_party.h"
#include "df/identity.h"
#include "df/history_event_masterpiece_lostst.h"
#include "df/history_event_performancest.h"
#include "df/historical_entity.h"
#include "df/entity_occasion_info.h"
#include "df/entity_occasion.h"
#include "df/entity_occasion_schedule.h"
#include "df/history_event_artifact_createdst.h"
#include "df/artifact_record.h"
#include "df/item_coinst.h"
#include "df/coin_batch.h"
#include <unordered_set>
namespace df3d_creature {
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
// Both audited recursive phrase classes have at most one event successor.
// Walk iteratively so validation itself cannot overflow on a cyclic graph.
inline bool knowledgeEventInputsValid(int32_t event_id) {
    std::unordered_set<int32_t> visited;
    while(event_id>=0) {
        auto* event=df::history_event::find(event_id);if(!event)return true;
        if(!visited.insert(event_id).second)return false;
        if(!directAgreementIdentityInputsValid(event_id))return false;
        if(event->getType()==df::history_event_type::ARTIFACT_CREATED) {
            const auto* artifact=df::artifact_record::find(static_cast<df::history_event_artifact_createdst*>(event)->artifact_id);
            if(artifact && !artifact->name.has_name && artifact->item && artifact->item->getType()==df::item_type::COIN) {
                const auto index=static_cast<df::item_coinst*>(artifact->item)->coin_batch;
                if(index!=-1) {
                    const auto& batches=df::global::world->coin_batches.all;
                    if(index<0 || size_t(index)>=batches.size() || !batches[size_t(index)])return false;
                    const auto issuer_id=batches[size_t(index)]->entity;
                    if(issuer_id!=-1) {
                        const auto* issuer=df::historical_entity::find(issuer_id);
                        if(!issuer || !issuer->entity_raw)return false;
                    }
                }
            }
        }
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
