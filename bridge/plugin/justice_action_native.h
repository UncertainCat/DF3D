#pragma once
#include "justice_native.h"
#include "df/identity.h"
#include "df/job.h"
#include "df/job_list_link.h"
#include "df/general_ref.h"
#include <memory>

namespace df3d_justice {
enum class ActionOutcome { Unsupported, Rejected, Applied, Unknown };
// Native474550 inlines the report changes around a global Justice-map write.
// There is no callable semantic boundary for that handler. Keep the audited
// effects here, use native identity/job helpers, and never update its menu map.
// Caller owns epoch/save admission and receipt deduplication; expected selection
// rejects repeated/stale toggles. A partial exception is Unknown, never replayed.
inline ActionOutcome toggleInterrogation(df::crime* crime,df::unit* unit,bool expectedSelected) {
    if(!crime || !unit)return ActionOutcome::Rejected;
    const auto candidates=convictionCandidates(crime);if(!candidates)return ActionOutcome::Unsupported;
    const auto current=std::find_if(candidates->begin(),candidates->end(),[unit](const CandidateFact& row){return row.unitId==unit->id;});
    if(current==candidates->end() || bool(current->flags&1)!=expectedSelected || unit->hist_figure_id==-1)
        return ActionOutcome::Rejected;
    auto* world=df::global::world;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<uint8_t*>(&world->jobs.list.next)!=base+0x23e61c8)return ActionOutcome::Unsupported;
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x474550,0x33b,UINT64_C(0xbd8f72f8640b95af)},
            {0x13b3030,0x56,UINT64_C(0xf9404dd6eb50e2af)},
            {0xb9e70,0xf8,UINT64_C(0x7dab880be6ec9cba)},
            {0xbabe0,0xab,UINT64_C(0x1bd318997a061458)},
            {0xa67820,0xcc,UINT64_C(0x506ce8a2c4eefca6)},
        };
        for(const auto& p:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){hash^=base[p.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=p.hash)return false;}
        return true;
    }();
    if(!pinned)return ActionOutcome::Unsupported;
    static_assert(sizeof(df::incident_hfid)==0x28 && offsetof(df::crime,reports)==0xc8);
    static_assert(offsetof(df::unit,hist_figure_id)==0xc30);
    if(crime->reports.size()>1048576)return ActionOutcome::Rejected;
    for(const auto* report:crime->reports)
        if(!report || report->all_witnessed_ident.size()>1048576)return ActionOutcome::Rejected;
    // Validate every job reference before any mutation. Native removal checks
    // the first UNIT_INTERROGATEE reference, regardless of which crime owns it.
    size_t count=0;
    for(auto* link=world->jobs.list.next;link;link=link->next) {
        if(++count>1048576 || !link->item || link->item->general_refs.size()>1048576)return ActionOutcome::Rejected;
        for(const auto* ref:link->item->general_refs)if(!ref)return ActionOutcome::Rejected;
    }
    try {
        df3d_creature::InventoryDescriptionContext owned(*unit);
        const auto* identity=reinterpret_cast<df::identity*(*)(df::unit*)>(base+0x13b3030)(owned.unit());
        const int32_t visual=unit->hist_figure_id,historical=identity?-1:visual,identityId=identity?identity->id:-1;
        if(!expectedSelected) {
            auto report=std::make_unique<df::incident_hfid>();
            report->hfid=-1;report->visual_hfid=visual;report->historical_hfid=historical;
            report->all_witnessed_ident.clear();
            if(identityId!=-1)reinterpret_cast<int32_t(*)(int32_t,std::vector<int32_t>*)>(base+0xb9e70)(identityId,&report->all_witnessed_ident);
            crime->reports.push_back(report.get());report.release();
        } else {
            for(size_t i=crime->reports.size();i>0;--i) {
                auto* report=crime->reports[i-1];
                struct IdentityMatch {int32_t index=-1,value=-1;uint8_t found=0,padding[3]{};} match;
                if(identityId!=-1)reinterpret_cast<IdentityMatch*(*)(IdentityMatch*,const std::vector<int32_t>*,int32_t)>(base+0xbabe0)(&match,&report->all_witnessed_ident,identityId);
                if(report->visual_hfid!=visual && (historical==-1 || report->historical_hfid!=historical) &&
                   (!match.found || match.index==-1))continue;
                for(auto* link=world->jobs.list.next;link;) {
                    auto* job=link->item;link=link->next;
                    if(job->job_type!=df::job_type::InterrogateSubject)continue;
                    for(auto* ref:job->general_refs)if(ref->getType()==df::general_ref_type::UNIT_INTERROGATEE) {
                        if(ref->getUnit()==unit)reinterpret_cast<void(*)(df::job*)>(base+0xa67820)(job);
                        break;
                    }
                }
                delete report;crime->reports.erase(crime->reports.begin()+static_cast<ptrdiff_t>(i-1));
            }
        }
        return ActionOutcome::Applied;
    } catch(...) {return ActionOutcome::Unknown;}
}
}
