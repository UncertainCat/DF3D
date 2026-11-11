#pragma once
#include "nobles_symbols_mutation_native.h"
#include "location_details_native.h"

namespace df3d_nobles {
struct SymbolName {
    int32_t artifactId=-1,itemId=-1;
    df3d_area::LocationNameValue value;
    std::string nativeHeader,englishHeader;
    uint64_t revision=0;
};
inline df::artifact_record* namedSymbol(const OfficeKey& key,int32_t artifactId) {
    if(!symbolApplyReady() || artifactId<0 || key.draftSlot || key.assignmentId<0)return nullptr;
    auto* entity=df::historical_entity::find(key.entityId);
    auto* artifact=df::artifact_record::find(artifactId);
    if(!entity || !artifact || !artifact->item || !artifact->item->flags.bits.artifact)return nullptr;
    bool assigned=false;
    for(const auto* row:entity->positions.assignments)if(row && row->id==key.assignmentId && row->position_id==key.positionId)assigned=true;
    if(!assigned)return nullptr;
    for(const auto* claim:entity->artifact_claims)if(claim && claim->artifact_id==artifactId && int(claim->claim_type)==0 &&
        claim->symbol_claim_id==key.assignmentId && claim->renounce_event==-1)return artifact;
    return nullptr;
}
inline std::optional<SymbolName> observeSymbolName(const OfficeKey& key,int32_t artifactId) {
    const auto* artifact=namedSymbol(key,artifactId);if(!artifact)return std::nullopt;
    const auto& name=artifact->name;
    SymbolName result;result.artifactId=artifactId;result.itemId=artifact->item->id;
    auto& value=result.value;value.firstNameCp437=name.first_name;value.nicknameCp437=name.nickname;value.words=name.words;
    for(size_t i=0;i<7;++i)value.parts[i]=int16_t(name.parts_of_speech[i]);
    value.language=name.language;value.type=int16_t(name.type);value.hasName=name.has_name;
    const auto text=df3d_area::formatNativeLocationName(value);if(!text)return std::nullopt;
    result.nativeHeader=text->native;result.englishHeader=text->english;
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto number=[&](uint64_t v){for(unsigned i=0;i<8;++i){hash^=uint8_t(v>>(i*8));hash*=UINT64_C(1099511628211);}};
    for(auto v:{key.entityId,key.positionId,key.assignmentId,artifactId,result.itemId})number(uint32_t(v));
    for(const auto* s:{&value.firstNameCp437,&value.nicknameCp437}){number(s->size());for(unsigned char c:*s){hash^=c;hash*=UINT64_C(1099511628211);}}
    for(auto v:value.words)number(uint32_t(v));for(auto v:value.parts)number(uint16_t(v));
    number(uint32_t(value.language));number(uint16_t(value.type));number(value.hasName);
    hash&=INT64_MAX;result.revision=hash?hash:1;return result;
}
// Same shared native component editor1fe5c0 as locations/artwork. This adapter
// checks the artifact's live symbol claim and name receipt; no native editor
// context is read. The command owner must also bind the outstanding naming step.
inline DraftCommitOutcome editSymbolName(const OfficeKey& key,int32_t artifactId,uint64_t expectedRevision,
        df3d_area::LocationNameEdit edit,int32_t target,int32_t displayed,int32_t word,int32_t part,const std::string& query) {
    if(!expectedRevision || expectedRevision>INT64_MAX || uint8_t(edit)>3 || query.size()>4096)return DraftCommitOutcome::Rejected;
    const bool whole=edit==df3d_area::LocationNameEdit::RandomWhole;
    if(whole?(target!=-1 || displayed!=-1 || word!=-1 || part!=-1 || !query.empty()):(target<0 || target>6 || displayed<0 || displayed>6))return DraftCommitOutcome::Rejected;
    const auto before=observeSymbolName(key,artifactId);if(!before)return DraftCommitOutcome::Rejected;
    if(before->revision!=expectedRevision)return DraftCommitOutcome::Stale;
    auto* artifact=namedSymbol(key,artifactId);if(!artifact)return DraftCommitOutcome::Rejected;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base]{uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x1382;++i){hash^=base[0x1fe5c0+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x3326cd7614642632);}();
    if(!pinned)return DraftCommitOutcome::Unavailable;
    if(edit==df3d_area::LocationNameEdit::SelectWord) {
        if(target!=displayed)return DraftCommitOutcome::Rejected;
        const auto choices=df3d_area::observeNativeLocationNameWords(uint8_t(displayed),query,artifact->name.language);
        if(!choices || std::none_of(choices->begin(),choices->end(),[&](const auto& row){return row.word==word && row.partOfSpeech==part;}))return DraftCommitOutcome::Rejected;
    }
    try {
        if(whole) {
            auto* namer=df::global::plotinfo->main.fortress_entity;
            if(!namer || !namer->entity_raw)return DraftCommitOutcome::Rejected;
            auto name=artifact->name;
            reinterpret_cast<void(*)(df::historical_entity*,df::language_name*,int16_t)>(base+0x931860)(namer,&name,1);
            artifact->name=std::move(name);
        }else {
            if(edit==df3d_area::LocationNameEdit::RandomComponent) {
                const auto choice=df3d_area::chooseNativeLocationNameWord(uint8_t(displayed),query);
                if(!choice)return DraftCommitOutcome::Rejected;
                word=choice->word;part=choice->partOfSpeech;
            }else if(edit==df3d_area::LocationNameEdit::Clear){word=-1;part=0;}
            artifact->name.words[size_t(target)]=word;artifact->name.parts_of_speech[size_t(target)]=df::part_of_speech(part);
        }
        return DraftCommitOutcome::Applied;
    }catch(const std::exception&){return DraftCommitOutcome::Unknown;}
}
}
