#pragma once
#include "tile_selection_native.h"
#include "work_order_art_native.h"
#include "work_order_art_draft_native.h"
#include "df/location_detailst.h"

namespace df3d_selection {
struct EngravingArtSource {
    df::location_detailst detail;
    bool exists=false;
    uint64_t revision=0;
};
inline uint64_t engravingArtRevision(const EngravingArtSource& source) {
    const auto& detail=source.detail;
    uint64_t revision=UINT64_C(14695981039346656037);
    for(auto value:{int(detail.pos.x),int(detail.pos.y),int(detail.pos.z),int(source.exists),int(detail.art_specifier),detail.art_spec_id1,detail.art_spec_id2})
        for(unsigned shift=0;shift<32;shift+=8){revision^=(uint32_t(value)>>shift)&255;revision*=UINT64_C(1099511628211);}
    revision&=INT64_MAX;return revision?revision:1;
}
// Planned engraving inputs come from the semantic per-tile specification.
// The actual native opener also allocates an empty specification when absent;
// collecting candidates needs only an owned default in that case.
inline std::optional<EngravingArtSource> engravingArtSource(int x,int y,int z) {
    const auto selection=collect(x,y,z);
    if(!selection || !df::global::plotinfo)return std::nullopt;
    const auto planned=df::view_sheet_type::ENGRAVING_PLANNED;
    bool eligible=selection->active.kind==planned;
    for(const auto& tab:selection->tabs)eligible|=tab.kind==planned;
    if(!eligible)return std::nullopt;
    EngravingArtSource source;auto& detail=source.detail;
    detail.pos=df::coord(uint16_t(x),uint16_t(y),uint16_t(z));
    for(const auto* value:df::global::plotinfo->waypoints.location_detail)
        if(value && value->pos==detail.pos){detail=*value;source.exists=true;break;}
    source.revision=engravingArtRevision(source);
    return source;
}
inline std::optional<df3d_production::WorkOrderArtSubjects> engravingArtSubjects(const EngravingArtSource& source,int kind,const std::string& query={}) {
    auto detail=source.detail;
    df::image_creation_specifierst inputs;inputs.location_detail=&detail;
    inputs.image_ent=df::global::plotinfo->main.fortress_entity;
    return df3d_production::nativeArtSubjects(inputs,source.revision,kind,query,df::image_creator_context_type::DESIGNATION_ENGRAVING);
}
inline std::optional<df3d_production::WorkOrderArtSubjects> engravingArtSubjects(int x,int y,int z,int kind) {
    auto source=engravingArtSource(x,y,z);if(!source)return std::nullopt;
    return engravingArtSubjects(*source,kind);
}
inline bool engravingArtReady() {
    static const bool ready=[] {
        if(!df3d_production::workOrderArtSubjectsReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1615560,0x20,UINT64_C(0xa7b5f000f8ee46d4)}, // engraving heading
            {0x20a2a5,0x35,UINT64_C(0x0f9ef4e343f520bf)}, // figure assignment
            {0x20a5db,0x35,UINT64_C(0x706c2ebe76cc9431)}, // site assignment
            {0x20a902,0x31,UINT64_C(0x2b3ae105972c46c4)}, // group assignment
            {0x20aca8,0x5c,UINT64_C(0x4a7ae069fa05399a)}, // existing image assignment
            {0x20f239,0x2e,UINT64_C(0xac5480f8d229fd6b)}, // artist choice
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();return ready;
}
struct EngravingArtPage {
    uint64_t revision=0;
    df3d_production::WorkOrderArtPage page;
};
inline std::optional<EngravingArtPage> engravingArtPage(int x,int y,int z,int16_t page,const std::string& query={},uint32_t cursor=0,uint64_t listRevision=0,int32_t hovered=-1,uint16_t columns=0) {
    if(!engravingArtReady() || query.size()>128)return std::nullopt;
    auto source=engravingArtSource(x,y,z);if(!source)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    auto result=df3d_production::nativeArtPage(reinterpret_cast<const char*>(base+0x1615560),page,query,cursor,listRevision,hovered,columns,
        [&](int kind,const std::string& filter){return engravingArtSubjects(*source,kind,filter);},
        [&](const std::string& filter){return df3d_production::nativeArtImages(source->revision,filter);});
    if(!result)return std::nullopt;
    return EngravingArtPage{source->revision,std::move(*result)};
}
enum class EngravingArtOutcome {Rejected,Stale,Applied};
// Mixed native input handlers have no standalone assignment leaf. Project only
// their pinned semantic stores after validating current native choices. Figure,
// site and group assignment deliberately preserve the old image sub-ID.
inline EngravingArtOutcome applyEngravingArtSubject(int x,int y,int z,uint64_t revision,int kind,int32_t id,uint64_t listRevision,const std::string& query={},uint64_t* resultingRevision=nullptr) {
    if(!engravingArtReady() || !revision || revision>INT64_MAX || listRevision>INT64_MAX || query.size()>128 || kind<0 || (kind>3 && kind!=5))return EngravingArtOutcome::Rejected;
    auto source=engravingArtSource(x,y,z);
    if(!source || source->revision!=revision)return EngravingArtOutcome::Stale;
    auto detail=source->detail;int type=kind-1,subid=detail.art_spec_id2;
    if(kind==0) {
        if(id!=-1 || listRevision || !query.empty())return EngravingArtOutcome::Rejected;
        subid=-1;
    } else if(kind==5) {
        const auto images=df3d_production::nativeArtImages(source->revision,query);
        if(!images)return EngravingArtOutcome::Rejected;
        if(!listRevision || images->listRevision!=listRevision)return EngravingArtOutcome::Stale;
        if(id<0 || size_t(id)>=images->rows.size())return EngravingArtOutcome::Rejected;
        type=3;subid=images->rows[size_t(id)]->subid;id=images->rows[size_t(id)]->id;
    } else {
        const auto subjects=engravingArtSubjects(*source,kind,query);
        if(!subjects)return EngravingArtOutcome::Rejected;
        if(!listRevision || subjects->listRevision!=listRevision)return EngravingArtOutcome::Stale;
        if(std::find(subjects->ids.begin(),subjects->ids.end(),id)==subjects->ids.end())return EngravingArtOutcome::Rejected;
    }
    detail.art_specifier=df::job_art_specifier_type(type);detail.art_spec_id1=id;detail.art_spec_id2=subid;
    source->detail=detail;source->exists=true;const auto nextRevision=engravingArtRevision(*source);
    auto& specifications=df::global::plotinfo->waypoints.location_detail;
    for(auto* value:specifications)if(value && value->pos==detail.pos){*value=detail;if(resultingRevision)*resultingRevision=nextRevision;return EngravingArtOutcome::Applied;}
    // Allocation and vector growth precede publication. A read never inserts a
    // semantic record; a validated edit installs the native default plus stores.
    auto value=std::make_unique<df::location_detailst>(detail);
    specifications.push_back(value.get());value.release();
    if(resultingRevision)*resultingRevision=nextRevision;
    return EngravingArtOutcome::Applied;
}
inline std::optional<EngravingArtPage> engravingArtDraftPage(int x,int y,int z,int16_t page,
    df3d_production::WorkOrderArtDraftValue value,uint8_t action,
    const std::optional<df3d_production::WorkOrderArtDraftElementValue>& element,
    const std::optional<df3d_production::WorkOrderArtDraftRelationshipValue>& relationship,int32_t deleteIndex,
    const std::string& query,uint32_t cursor,uint64_t listRevision,uint16_t columns,
    const df3d_production::WorkOrderArtNameQuery* nameQuery=nullptr,const df3d_production::WorkOrderArtNameEdit* nameEdit=nullptr) {
    auto root=engravingArtPage(x,y,z,-1);if(!root)return std::nullopt;
    auto result=df3d_production::nativeArtDraftPage(std::move(root->page),root->revision,page,std::move(value),action,
        element,relationship,deleteIndex,query,cursor,listRevision,columns,nameQuery,nameEdit,
        df::image_creator_context_type::DESIGNATION_ENGRAVING);
    if(!result)return std::nullopt;
    root->page=std::move(*result);return root;
}
enum class EngravingArtDraftOutcome {Rejected,Stale,Applied,Unknown};
inline EngravingArtDraftOutcome commitEngravingArtDraft(int x,int y,int z,uint64_t revision,
    const df3d_production::WorkOrderArtDraftValue& value,uint64_t* resultingRevision=nullptr) {
    if(!engravingArtReady() || !df3d_production::workOrderArtDraftReady() || !revision || revision>INT64_MAX ||
       !value.name || value.elements.empty() || value.elements.size()>256 || value.relationships.size()>256)return EngravingArtDraftOutcome::Rejected;
    static const bool pinned=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x33;++i){hash^=base[0x20b3bc+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x82371e48b0a3f235);
    }();if(!pinned)return EngravingArtDraftOutcome::Rejected;
    auto source=engravingArtSource(x,y,z);
    if(!source || source->revision!=revision)return EngravingArtDraftOutcome::Stale;
    auto draft=df3d_production::WorkOrderArtDraft::create(df::image_creator_context_type::DESIGNATION_ENGRAVING);
    if(!draft || !draft->setName(*value.name))return EngravingArtDraftOutcome::Rejected;
    for(const auto& e:value.elements)if(!draft->addElement(e.kind,e.id,e.secondary,e.quantity))return EngravingArtDraftOutcome::Rejected;
    for(const auto& r:value.relationships)if(!draft->addRelationship(r.verb,r.transitive,r.actor,r.target))return EngravingArtDraftOutcome::Rejected;
    if(!draft->canInstall())return EngravingArtDraftOutcome::Rejected;
    auto& specifications=df::global::plotinfo->waypoints.location_detail;df::location_detailst* destination=nullptr;
    for(auto* row:specifications)if(row && row->pos==source->detail.pos){destination=row;break;}
    std::unique_ptr<df::location_detailst> pending;
    if(!destination){pending=std::make_unique<df::location_detailst>(source->detail);destination=pending.get();specifications.reserve(specifications.size()+1);}
    // Native20b02b..20b2a5 registration is shared with jobs/orders. From this
    // point, a partial world/entity write must never be reported as rejection.
    try {
        auto* image=draft->install();if(!image)return EngravingArtDraftOutcome::Unknown;
        // Native20b3bc..20b3ef changes only the tile specification afterward.
        destination->art_specifier=df::job_art_specifier_type(3);destination->art_spec_id1=image->id;destination->art_spec_id2=image->subid;
        if(pending){specifications.push_back(destination);pending.release();}
        source->detail=*destination;source->exists=true;
        if(resultingRevision)*resultingRevision=engravingArtRevision(*source);
        return EngravingArtDraftOutcome::Applied;
    } catch(...) {return EngravingArtDraftOutcome::Unknown;}
}
}
