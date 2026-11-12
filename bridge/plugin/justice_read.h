#pragma once
#include "justice_native.h"
#include "justice_witness_native.h"
#include "justice_action_native.h"
#include "justice_presentation_native.h"
#include "management_util.h"
#include "MiscUtils.h"
#include <stdexcept>
namespace df3d_justice {
namespace m=df3d::mirror;
static_assert(uint8_t(CaseResolution::Unsolved)==uint8_t(m::JusticeCaseResolution::Unsolved) && uint8_t(CaseResolution::Convicted)==uint8_t(m::JusticeCaseResolution::Convicted) && uint8_t(CaseResolution::UnknownConvict)==uint8_t(m::JusticeCaseResolution::UnknownConvict));
struct CaseRow {int32_t id=-1;std::string caption;};
struct Detail {
    int32_t id=-1;uint64_t revision=0;std::string caption;CaseSummary summary;
    uint32_t total=0,offset=0;std::vector<WitnessText> witnesses;
};
struct ReadResult {
    m::JusticeOutcome outcome=m::JusticeOutcome::Rejected;uint8_t tab=0;
    uint64_t revision=0;uint32_t total=0,offset=0;std::vector<CaseRow> rows;std::optional<Detail> detail;
    struct Candidate {CandidateFact fact;CandidatePresentation display;};
    struct Candidates {int32_t crimeId=-1;uint64_t revision=0;uint32_t total=0,offset=0;std::vector<Candidate> rows;};
    std::optional<Candidates> candidates;
};
struct ReadHash {
    uint64_t value=UINT64_C(14695981039346656037);
    void number(uint64_t n){for(unsigned i=0;i<8;++i){value^=uint8_t(n>>(8*i));value*=UINT64_C(1099511628211);}}
    void text(const std::string& s){number(s.size());for(unsigned char c:s){value^=c;value*=UINT64_C(1099511628211);}}
    uint64_t finish()const {return (value&INT64_MAX)?value&INT64_MAX:1;}
};
inline std::string readText(const std::string& text){auto utf=DF2UTF(text);if(utf.size()>16384)throw std::runtime_error("Justice caption exceeds bound");return utf;}
// Caller admits world epoch/save state at a safe point. The complete semantic
// list/detail is hashed before slicing; no native widget or cursor is consulted.
inline ReadResult read(const m::JusticeRequest& q,bool selected) {
    ReadResult refused;refused.tab=q.tab();
    try {
        const auto lists=cases();if(!lists || q.tab()>2)return refused;
        const auto& ids=(*lists)[q.tab()];if(ids.size()>1048576)return refused;
        std::vector<CaseRow> rows;ReadHash hash;hash.number(q.tab());hash.number(ids.size());
        for(auto id:ids){auto text=caption(df::crime::find(id));if(!text)return refused;
            rows.push_back({id,readText(*text)});hash.number(uint32_t(id));hash.text(rows.back().caption);}
        const auto revision=hash.finish();
        if((q.expected_list_revision() && q.expected_list_revision()!=revision) ||
            (selected && std::find(ids.begin(),ids.end(),q.crime_id())==ids.end())){refused.outcome=m::JusticeOutcome::Stale;return refused;}
        ReadResult result;result.tab=q.tab();result.revision=revision;result.outcome=m::JusticeOutcome::None;
        if(!selected){
            if(q.offset()>rows.size()){refused.outcome=m::JusticeOutcome::Stale;return refused;}
            result.total=uint32_t(rows.size());result.offset=q.offset();size_t bytes=0;
            for(size_t i=q.offset();i<rows.size() && result.rows.size()<q.limit();++i){
                auto size=32+rows[i].caption.size();if(bytes+size>384*1024)break;bytes+=size;result.rows.push_back(std::move(rows[i]));}
        }else{
            auto* crime=df::crime::find(q.crime_id());auto summary=caseSummary(crime);auto reports=witnessText(crime);
            if(!summary || !reports)return refused;
            Detail d;d.id=q.crime_id();d.caption=rows[size_t(std::find(ids.begin(),ids.end(),d.id)-ids.begin())].caption;
            d.summary.resolution=summary->resolution;d.summary.status=readText(summary->status);if(summary->injuredParty)d.summary.injuredParty=readText(*summary->injuredParty);
            ReadHash facts;facts.number(uint32_t(d.id));facts.text(d.caption);facts.text(d.summary.status);facts.number(uint8_t(d.summary.resolution));
            facts.number(bool(d.summary.injuredParty));if(d.summary.injuredParty)facts.text(*d.summary.injuredParty);
            facts.number(reports->size());
            for(auto& w:*reports)for(auto* text:{&w.witness,&w.description,&w.date,&w.reported}){*text=readText(*text);facts.text(*text);}
            d.revision=facts.finish();
            if((q.expected_case_revision() && q.expected_case_revision()!=d.revision) || q.offset()>reports->size()){
                refused.outcome=m::JusticeOutcome::Stale;return refused;}
            d.total=uint32_t(reports->size());d.offset=q.offset();
            size_t bytes=d.caption.size()+d.summary.status.size()+(d.summary.injuredParty?d.summary.injuredParty->size():0);
            for(size_t i=q.offset();i<reports->size() && d.witnesses.size()<q.limit();++i){const auto& w=(*reports)[i];
                auto size=64+w.witness.size()+w.description.size()+w.date.size()+w.reported.size();
                if(bytes+size>384*1024)break;bytes+=size;d.witnesses.push_back(std::move((*reports)[i]));}
            if(d.offset<d.total && d.witnesses.empty())return refused;
            result.detail=std::move(d);
        }
        return result;
    }catch(...){return refused;}
}
// Open/Cold rows install486ac0->472ac0 (actions); Closed rows install486e50
// (summary only), in the pinned case-list builder used by cases(). Never use
// native tab/selection state to admit a candidate request or mutation.
inline ReadResult candidateRequest(const m::JusticeRequest& q,bool apply) {
    ReadResult refused;refused.tab=q.tab();
    try {
        if(q.tab()==1)return refused;
        flatbuffers::FlatBufferBuilder scope;
        scope.Finish(m::CreateJusticeRequest(scope,q.tab(),0,1,q.expected_list_revision(),q.crime_id(),q.expected_case_revision()));
        const auto observed=read(*flatbuffers::GetRoot<m::JusticeRequest>(scope.GetBufferPointer()),true);
        if(observed.outcome!=m::JusticeOutcome::None){refused.outcome=observed.outcome;return refused;}
        auto* crime=df::crime::find(q.crime_id());if(!crime || !observed.detail)return refused;
        const auto query=q.query()?q.query()->str():std::string{};
        const auto nativeQuery=UTF2DF(query);
        if(DF2UTF(nativeQuery)!=query)return refused;
        const auto facts=convictionCandidates(crime,nativeQuery);if(!facts || facts->size()>1048576)return refused;
        ReadHash hash;hash.number(observed.revision);hash.number(observed.detail->revision);hash.text(query);
        // Include effect-relevant crime values absent from the displayed summary.
        for(auto value:{int32_t(crime->mode),crime->criminal,crime->accused,crime->victim,crime->incident_id,
                       crime->site,crime->entity,crime->punishment.hammerstrikes,crime->punishment.prison_time})hash.number(uint32_t(value));
        hash.number(crime->flags.whole);hash.number(crime->punishment.flags.whole);hash.number(facts->size());
        for(const auto& row:*facts){hash.number(uint32_t(row.unitId));hash.number(uint32_t(row.rank));hash.number(row.flags);}
        const auto revision=hash.finish();
        if((q.expected_candidate_revision() && q.expected_candidate_revision()!=revision) || q.offset()>facts->size()){
            refused.outcome=m::JusticeOutcome::Stale;return refused;
        }
        if(apply){
            if(std::none_of(facts->begin(),facts->end(),[&](const CandidateFact& row){return row.unitId==q.unit_id();})){
                refused.outcome=m::JusticeOutcome::Stale;return refused;
            }
            const auto outcome=convict(crime,df::unit::find(q.unit_id()),crime->accused);
            refused.outcome=outcome==ActionOutcome::Applied?m::JusticeOutcome::Applied:
                outcome==ActionOutcome::Unknown?m::JusticeOutcome::Unknown:m::JusticeOutcome::Rejected;
            return refused;
        }
        ReadResult result;result.tab=q.tab();result.revision=observed.revision;result.outcome=m::JusticeOutcome::None;
        auto& page=result.candidates.emplace();page.crimeId=crime->id;page.revision=revision;page.total=uint32_t(facts->size());page.offset=q.offset();
        size_t bytes=0;
        for(size_t i=q.offset();i<facts->size() && page.rows.size()<q.limit();++i){
            // The accepted1200x800 reference uses the native28-column minimum.
            auto display=candidatePresentation(crime,df::unit::find((*facts)[i].unitId),28);if(!display)return refused;
            for(auto* text:{&display->name,&display->witnessLabel,&display->deceased}){*text=readText(*text);bytes+=text->size();}
            bytes+=64;if(bytes>384*1024)return refused;
            page.rows.push_back({(*facts)[i],std::move(*display)});
        }
        return result;
    }catch(...){return refused;}
}
inline flatbuffers::Offset<m::JusticeState> encode(flatbuffers::FlatBufferBuilder& b,const ReadResult& r){
    std::vector<flatbuffers::Offset<m::JusticeCaseRow>> rows;
    for(const auto& row:r.rows)rows.push_back(m::CreateJusticeCaseRow(b,row.id,b.CreateString(row.caption)));
    flatbuffers::Offset<m::JusticeCaseDetail> detail;
    if(r.detail){const auto& d=*r.detail;std::vector<flatbuffers::Offset<m::JusticeWitnessRow>> witnesses;
        for(const auto& w:d.witnesses)witnesses.push_back(m::CreateJusticeWitnessRow(b,b.CreateString(w.witness),b.CreateString(w.description),b.CreateString(w.date),b.CreateString(w.reported)));
        detail=m::CreateJusticeCaseDetail(b,d.id,d.revision,b.CreateString(d.caption),d.summary.injuredParty?b.CreateString(*d.summary.injuredParty):0,
            b.CreateString(d.summary.status),d.total,d.offset,b.CreateVector(witnesses),m::JusticeCaseResolution(d.summary.resolution));}
    flatbuffers::Offset<m::JusticeCandidatePage> candidates;
    if(r.candidates){const auto& page=*r.candidates;std::vector<flatbuffers::Offset<m::JusticeCandidateRow>> entries;
        for(const auto& row:page.rows){const auto& d=row.display;const auto& c=d.nameColor;const auto& f=row.fact;
            auto color=m::CreateAreaNameColor(b,c.color[0],c.color[1],c.color[2],c.alternate[0],c.alternate[1],c.alternate[2],c.effect);
            auto display=m::CreateJusticeCandidateDisplay(b,28,b.CreateString(d.name),color,d.witnessCount,
                b.CreateString(d.witnessLabel),d.witnessColor,b.CreateString(d.deceased));
            entries.push_back(m::CreateJusticeCandidateRow(b,f.unitId,f.rank,bool(f.flags&1),bool(f.flags&2),display));}
        candidates=m::CreateJusticeCandidatePage(b,page.crimeId,page.revision,page.total,page.offset,b.CreateVector(entries));}
    return m::CreateJusticeState(b,r.outcome,r.tab,r.revision,r.total,r.offset,b.CreateVector(rows),detail,candidates);
}
}
