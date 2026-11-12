#pragma once
#include "justice_native.h"
#include "justice_guard_native.h"
#include "justice_convicts_native.h"
#include "justice_intelligence_native.h"
#include "residents_row_native.h"
#include "justice_witness_native.h"
#include "justice_action_native.h"
#include "justice_presentation_native.h"
#include "management_util.h"
#include "management_data.h"
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
    struct Candidate {CandidateFact fact;CandidatePresentation display;df3d_management::ResidentAppearanceRecipe icon;};
    struct Candidates {bool interrogate=false;int32_t crimeId=-1;uint64_t revision=0;uint32_t total=0,offset=0;std::vector<Candidate> rows;};
    std::optional<Candidates> candidates;
    struct GuardRow {CandidateFact fact;df3d_residents::RowText text;df3d_management::ResidentAppearanceRecipe icon;df::coord position;};
    struct Guard {std::string caption;uint8_t color=0;std::vector<GuardRow> rows;};
    std::optional<Guard> guard;
    std::optional<std::vector<GuardRow>> convicts;
    struct ConvictPage {ConvictDetail facts;uint64_t revision=0;uint32_t total=0,offset=0;};
    std::optional<ConvictPage> convictDetail;
    struct Intelligence {int32_t index=-1;uint16_t columns=0;std::vector<IntelligenceReport> reports;std::vector<std::string> lines;};
    std::optional<Intelligence> intelligence;
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
        std::vector<CandidateSort> sorts={{CandidateColumn::Crime,false},{CandidateColumn::Name,false}};
        if(q.sorts()){sorts.clear();for(const auto* sort:*q.sorts())sorts.push_back({CandidateColumn(sort->column()),sort->reverse()});}
        const auto facts=q.interrogate()?interrogationCandidates(crime,nativeQuery,sorts):convictionCandidates(crime,nativeQuery,sorts);if(!facts || facts->size()>1048576)return refused;
        ReadHash hash;hash.number(observed.revision);hash.number(observed.detail->revision);hash.text(query);hash.number(q.interrogate());
        hash.number(sorts.size());for(const auto& sort:sorts){hash.number(uint8_t(sort.column));hash.number(sort.reverse);}
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
            const auto outcome=q.interrogate()?toggleInterrogation(crime,df::unit::find(q.unit_id()),q.expected_selected()):convict(crime,df::unit::find(q.unit_id()),crime->accused);
            refused.outcome=outcome==ActionOutcome::Applied?m::JusticeOutcome::Applied:
                outcome==ActionOutcome::Unknown?m::JusticeOutcome::Unknown:m::JusticeOutcome::Rejected;
            return refused;
        }
        ReadResult result;result.tab=q.tab();result.revision=observed.revision;result.outcome=m::JusticeOutcome::None;
        auto& page=result.candidates.emplace();page.interrogate=q.interrogate();page.crimeId=crime->id;page.revision=revision;page.total=uint32_t(facts->size());page.offset=q.offset();
        size_t bytes=0;
        for(size_t i=q.offset();i<facts->size() && page.rows.size()<q.limit();++i){
            // The accepted1200x800 reference uses the native28-column minimum.
            auto display=candidatePresentation(crime,df::unit::find((*facts)[i].unitId),28);if(!display)return refused;
            size_t rowBytes=64;
            for(auto* text:{&display->name,&display->witnessLabel,&display->deceased}){*text=readText(*text);rowBytes+=text->size();}
            df3d_management::ResidentAppearanceRecipe icon;icon.collect(df::unit::find((*facts)[i].unitId),true);
            if(!icon.layers.empty()){
                flatbuffers::FlatBufferBuilder check;check.Finish(icon.build(check));
                if(m::validateOwnerAppearance(*flatbuffers::GetRoot<m::SelectionAppearance>(check.GetBufferPointer()),rowBytes))return refused;
            }
            if(bytes+rowBytes>384*1024)break;bytes+=rowBytes;
            page.rows.push_back({(*facts)[i],std::move(*display),std::move(icon)});
        }
        if(page.offset<page.total && page.rows.empty())return refused;
        return result;
    }catch(...){return refused;}
}
inline ReadResult guardRequest(const m::JusticeRequest& q) {
    ReadResult refused;refused.tab=3;
    try {
        const auto query=q.query()?q.query()->str():std::string{};const auto nativeQuery=UTF2DF(query);
        if(DF2UTF(nativeQuery)!=query)return refused;
        std::vector<CandidateSort> sorts={{CandidateColumn::Category,false}};
        if(q.sorts()){sorts.clear();for(const auto* sort:*q.sorts())sorts.push_back({CandidateColumn(sort->column()),sort->reverse()});}
        auto overview=guardOverview(nativeQuery,sorts);if(!overview || overview->members.size()>1048576)return refused;
        ReadHash hash;hash.text(query);hash.text(overview->caption);hash.number(overview->color);
        for(const auto& sort:sorts){hash.number(uint8_t(sort.column));hash.number(sort.reverse);}
        for(const auto& fact:overview->members){hash.number(uint32_t(fact.unitId));hash.number(uint32_t(fact.rank));}
        const auto revision=hash.finish();
        if((q.expected_list_revision() && q.expected_list_revision()!=revision) || q.offset()>overview->members.size()){refused.outcome=m::JusticeOutcome::Stale;return refused;}
        ReadResult result;result.tab=3;result.outcome=m::JusticeOutcome::None;result.revision=revision;result.offset=q.offset();result.total=uint32_t(overview->members.size());
        auto& page=result.guard.emplace();page.caption=readText(overview->caption);page.color=overview->color;size_t bytes=page.caption.size();
        for(size_t i=q.offset();i<overview->members.size() && page.rows.size()<q.limit();++i){
            const auto fact=overview->members[i];auto* unit=df::unit::find(fact.unitId);if(!unit)return refused;
            auto text=df3d_residents::rowText(unit,30,false,false);if(!text)return refused;
            text->name.firstLine=readText(text->name.firstLine);text->name.secondLine=readText(text->name.secondLine);
            size_t size=64+text->name.firstLine.size()+text->name.secondLine.size();df3d_management::ResidentAppearanceRecipe icon;icon.collect(unit,true);
            if(!icon.layers.empty()){flatbuffers::FlatBufferBuilder check;check.Finish(icon.build(check));if(m::validateOwnerAppearance(*flatbuffers::GetRoot<m::SelectionAppearance>(check.GetBufferPointer()),size))return refused;}
            if(bytes+size>384*1024)break;bytes+=size;
            page.rows.push_back({fact,std::move(*text),std::move(icon),unit->pos});
        }
        if(result.offset<result.total && page.rows.empty())return refused;
        return result;
    }catch(...){return refused;}
}
inline ReadResult convictsRequest(const m::JusticeRequest& q,bool selected) {
    ReadResult refused;refused.tab=4;
    try {
        const auto query=q.query()?q.query()->str():std::string{};const auto nativeQuery=UTF2DF(query);if(DF2UTF(nativeQuery)!=query)return refused;
        std::vector<CandidateSort> sorts={{CandidateColumn::Category,false}};
        if(q.sorts()){sorts.clear();for(const auto* sort:*q.sorts())sorts.push_back({CandidateColumn(sort->column()),sort->reverse()});}
        const auto units=convicts(nativeQuery,sorts);if(!units || units->size()>1048576)return refused;
        ReadHash hash;hash.text(query);for(const auto& sort:sorts){hash.number(uint8_t(sort.column));hash.number(sort.reverse);}
        for(const auto& fact:*units)hash.number(uint32_t(fact.unitId));const auto revision=hash.finish();
        if((q.expected_list_revision() && q.expected_list_revision()!=revision) || (selected && std::none_of(units->begin(),units->end(),[&](const auto& f){return f.unitId==q.unit_id();}))){refused.outcome=m::JusticeOutcome::Stale;return refused;}
        ReadResult result;result.tab=4;result.outcome=m::JusticeOutcome::None;result.revision=revision;
        if(selected){
            auto facts=convictDetail(q.unit_id());if(!facts || facts->crimes.size()>1048576)return refused;
            ReadHash detailHash;detailHash.number(uint32_t(facts->unitId));size_t bytes=64;
            for(auto& line:facts->sentence){line=readText(line);detailHash.text(line);bytes+=line.size();}
            detailHash.number(bool(facts->officer));if(facts->officer){*facts->officer=readText(*facts->officer);detailHash.text(*facts->officer);bytes+=facts->officer->size();}
            for(auto& c:facts->crimes){c.caption=readText(c.caption);detailHash.number(uint32_t(c.id));detailHash.text(c.caption);detailHash.number(bool(c.injuredParty));if(c.injuredParty){*c.injuredParty=readText(*c.injuredParty);detailHash.text(*c.injuredParty);}}
            const auto detailRevision=detailHash.finish();if((q.expected_case_revision() && q.expected_case_revision()!=detailRevision) || q.offset()>facts->crimes.size()){refused.outcome=m::JusticeOutcome::Stale;return refused;}
            auto& page=result.convictDetail.emplace();page.revision=detailRevision;page.total=uint32_t(facts->crimes.size());page.offset=q.offset();
            page.facts.unitId=facts->unitId;page.facts.sentence=std::move(facts->sentence);page.facts.officer=std::move(facts->officer);
            for(size_t i=q.offset();i<facts->crimes.size() && page.facts.crimes.size()<q.limit();++i){const auto& c=facts->crimes[i];const size_t size=32+c.caption.size()+(c.injuredParty?c.injuredParty->size():0);if(bytes+size>384*1024)break;bytes+=size;page.facts.crimes.push_back(c);}
            if(page.offset<page.total && page.facts.crimes.empty())return refused;
        }else{
            if(q.offset()>units->size()){refused.outcome=m::JusticeOutcome::Stale;return refused;}
            result.total=uint32_t(units->size());result.offset=q.offset();auto& rows=result.convicts.emplace();size_t bytes=0;
            for(size_t i=q.offset();i<units->size() && rows.size()<q.limit();++i){const auto fact=(*units)[i];auto* unit=df::unit::find(fact.unitId);if(!unit)return refused;
                auto text=df3d_residents::rowText(unit,30,false,false);if(!text)return refused;text->name.firstLine=readText(text->name.firstLine);text->name.secondLine=readText(text->name.secondLine);
                size_t size=64+text->name.firstLine.size()+text->name.secondLine.size();df3d_management::ResidentAppearanceRecipe icon;icon.collect(unit,true);
                if(!icon.layers.empty()){flatbuffers::FlatBufferBuilder check;check.Finish(icon.build(check));if(m::validateOwnerAppearance(*flatbuffers::GetRoot<m::SelectionAppearance>(check.GetBufferPointer()),size))return refused;}
                if(bytes+size>384*1024)break;bytes+=size;rows.push_back({fact,std::move(*text),std::move(icon),unit->pos});
            }
            if(result.offset<result.total && rows.empty())return refused;
        }
        return result;
    }catch(...){return refused;}
}
inline ReadResult intelligenceRequest(const m::JusticeRequest& q){
    ReadResult refused;refused.tab=5;
    try {
        // Fixed-width owned contents define identity independently of requested layout.
        const auto source=intelligenceReports(112);if(!source)return refused;
        ReadHash hash;hash.number(source->size());for(const auto& r:*source){hash.number(r.index);hash.text(r.title);hash.text(r.officer);hash.number(r.viewed);hash.number(r.paragraphs.size());for(const auto& line:r.paragraphs)hash.text(line);}
        const auto revision=hash.finish();
        if(q.expected_list_revision() && q.expected_list_revision()!=revision){refused.outcome=m::JusticeOutcome::Stale;return refused;}
        ReadResult result;result.tab=5;result.outcome=m::JusticeOutcome::None;result.revision=revision;result.offset=q.offset();auto& page=result.intelligence.emplace();page.index=q.report_index();page.columns=q.text_columns();size_t bytes=0;
        if(page.index<0){
            result.total=uint32_t(source->size());if(q.offset()>result.total){refused.outcome=m::JusticeOutcome::Stale;return refused;}
            for(size_t i=q.offset();i<source->size() && page.reports.size()<q.limit();++i){auto row=(*source)[i];row.title=readText(row.title);row.officer=readText(row.officer);row.lines.clear();row.paragraphs.clear();const auto size=32+row.title.size()+row.officer.size();if(bytes+size>384*1024)break;bytes+=size;page.reports.push_back(std::move(row));}
            if(q.offset()<result.total && page.reports.empty())return refused;
        }else{
            if(size_t(page.index)>=source->size()){refused.outcome=m::JusticeOutcome::Stale;return refused;}
            auto wrapped=intelligenceReports(page.columns);if(!wrapped)return refused;const auto& lines=(*wrapped)[page.index].lines;result.total=uint32_t(lines.size());
            if(q.offset()>result.total){refused.outcome=m::JusticeOutcome::Stale;return refused;}
            for(size_t i=q.offset();i<lines.size() && page.lines.size()<q.limit();++i){auto line=readText(lines[i]);if(bytes+line.size()>384*1024)break;bytes+=line.size();page.lines.push_back(std::move(line));}
            if(q.offset()<result.total && page.lines.empty())return refused;
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
            entries.push_back(m::CreateJusticeCandidateRow(b,f.unitId,f.rank,bool(f.flags&1),bool(f.flags&2),display,row.icon.layers.empty()?0:row.icon.build(b)));}
        candidates=m::CreateJusticeCandidatePage(b,page.crimeId,page.revision,page.total,page.offset,b.CreateVector(entries),page.interrogate);}
    flatbuffers::Offset<m::JusticeGuardPage> guard;
    if(r.guard){std::vector<flatbuffers::Offset<m::JusticeUnitRow>> entries;
        for(const auto& row:r.guard->rows){const auto& c=row.text.nameColor;
            auto color=m::CreateAreaNameColor(b,c.color[0],c.color[1],c.color[2],c.alternate[0],c.alternate[1],c.alternate[2],c.effect);
            m::TilePos position(row.position.x,row.position.y,row.position.z);
            entries.push_back(m::CreateJusticeUnitRow(b,row.fact.unitId,row.fact.rank,b.CreateString(row.text.name.firstLine),b.CreateString(row.text.name.secondLine),color,row.icon.layers.empty()?0:row.icon.build(b),&position));}
        guard=m::CreateJusticeGuardPage(b,b.CreateString(r.guard->caption),r.guard->color,b.CreateVector(entries));}
    flatbuffers::Offset<m::JusticeConvictsPage> convicts;
    if(r.convicts){std::vector<flatbuffers::Offset<m::JusticeUnitRow>> entries;
        for(const auto& row:*r.convicts){const auto& c=row.text.nameColor;auto color=m::CreateAreaNameColor(b,c.color[0],c.color[1],c.color[2],c.alternate[0],c.alternate[1],c.alternate[2],c.effect);m::TilePos position(row.position.x,row.position.y,row.position.z);
            entries.push_back(m::CreateJusticeUnitRow(b,row.fact.unitId,0,b.CreateString(row.text.name.firstLine),b.CreateString(row.text.name.secondLine),color,row.icon.layers.empty()?0:row.icon.build(b),&position));}
        convicts=m::CreateJusticeConvictsPage(b,b.CreateVector(entries));}
    flatbuffers::Offset<m::JusticeConvictDetail> convictDetail;
    if(r.convictDetail){const auto& p=*r.convictDetail;std::vector<flatbuffers::Offset<flatbuffers::String>> sentence;for(const auto& line:p.facts.sentence)sentence.push_back(b.CreateString(line));
        std::vector<flatbuffers::Offset<m::JusticeConvictCrime>> crimes;for(const auto& c:p.facts.crimes)crimes.push_back(m::CreateJusticeConvictCrime(b,c.id,b.CreateString(c.caption),c.injuredParty?b.CreateString(*c.injuredParty):0));
        convictDetail=m::CreateJusticeConvictDetail(b,p.facts.unitId,p.revision,b.CreateVector(sentence),p.facts.officer?b.CreateString(*p.facts.officer):0,p.total,p.offset,b.CreateVector(crimes));}
    flatbuffers::Offset<m::JusticeIntelligencePage> intelligence;
    if(r.intelligence){const auto& p=*r.intelligence;std::vector<flatbuffers::Offset<m::JusticeIntelligenceReport>> reports;std::vector<flatbuffers::Offset<flatbuffers::String>> lines;
        for(const auto& row:p.reports)reports.push_back(m::CreateJusticeIntelligenceReport(b,row.index,b.CreateString(row.title),b.CreateString(row.officer),row.viewed));
        for(const auto& line:p.lines)lines.push_back(b.CreateString(line));intelligence=m::CreateJusticeIntelligencePage(b,p.index,p.columns,b.CreateVector(reports),b.CreateVector(lines));}
    return m::CreateJusticeState(b,r.outcome,r.tab,r.revision,r.total,r.offset,b.CreateVector(rows),detail,candidates,guard,convicts,convictDetail,intelligence);
}
}
