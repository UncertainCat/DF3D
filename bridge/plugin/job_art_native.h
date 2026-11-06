#pragma once
#include "job_settings_native.h"
#include "work_order_art_native.h"

namespace df3d_production {
inline bool jobArtReady() {
    static const bool ready=[] {
        if(!jobSettingsReady() || !workOrderArtSubjectsReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x72;++i){hash^=base[0x1ffc7b+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x3c3de5c6aca9d751);
    }();return ready;
}
inline bool jobArtEffectsReady() {
    static const bool ready=[] {
        if(!jobArtReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x20a197,0x38,UINT64_C(0xed8b268d7ec77e62)},
            {0x20a4c7,0x3e,UINT64_C(0x7547c52f2fb86340)},
            {0x20a7fb,0x39,UINT64_C(0x0322daa3b927d14d)},
            {0x20ab16,0x66,UINT64_C(0xf04100668d5e2bc6)},
            {0x20f131,0x38,UINT64_C(0xe68ab6e2d4610236)},
            {0x219306,0x2e,UINT64_C(0x9dd76169b37c3dc6)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return true;
    }();return ready;
}
struct JobArtSubjects {
    int32_t jobId=-1,buildingId=-1;
    std::string caption;
    WorkOrderArtSubjects subjects;
};
// Read-only job adapter. The source is a simulation record, never a menu job
// pointer. Native leaves receive a private context and copied job requirements.
inline std::optional<JobArtSubjects> nativeJobArtSubjects(const df::job& source,int32_t kind,const std::string& query={}) {
    if(kind<1 || kind>3 || query.size()>128 || !jobArtReady())return std::nullopt;
    const auto details=nativeJobSettings(source,-1,{},false);if(!details)return std::nullopt;
    bool supported=false;
    for(const auto& option:details->options)if(option.kind==1 || option.kind==3)supported=true;
    if(!supported)return std::nullopt;
    std::vector<df::job_item> requirements;requirements.reserve(source.job_items.elements.size());
    for(const auto* item:source.job_items.elements){if(!item)return std::nullopt;requirements.push_back(*item);}
    df::job job=source;job.job_items.elements.clear();
    for(auto& item:requirements)job.job_items.elements.push_back(&item);
    df::image_creation_specifierst inputs;inputs.jb=&job;inputs.wq=nullptr;
    inputs.image_ent=df::global::plotinfo->main.fortress_entity;
    auto subjects=nativeArtSubjects(inputs,details->revision,kind,query);if(!subjects)return std::nullopt;
    JobArtSubjects result;result.jobId=details->jobId;result.buildingId=details->buildingId;
    result.subjects=std::move(*subjects);
    // Native1ffc7b..1ffced uses the same d03170 job caption, without an order quantity.
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    result.caption=reinterpret_cast<const char*>(base+0x1615548);result.caption+=details->caption;
    if(result.caption.size()>78)result.caption.resize(78);
    return result;
}
struct JobArtPage {
    int32_t jobId=-1,buildingId=-1;
    uint64_t revision=0;
    WorkOrderArtPage page;
};
inline std::optional<JobArtPage> nativeJobArtPage(const df::job& job,int16_t page,const std::string& query={},uint32_t cursor=0,uint64_t listRevision=0,int32_t hovered=-1,uint16_t columns=0) {
    if(!jobArtReady() || query.size()>128)return std::nullopt;
    const auto details=nativeJobSettings(job,-1,{},false);if(!details)return std::nullopt;
    bool supported=false;for(const auto& option:details->options)if(option.kind==1 || option.kind==3)supported=true;
    if(!supported)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    std::string caption=reinterpret_cast<const char*>(base+0x1615548);caption+=details->caption;
    auto observed=nativeArtPage(std::move(caption),page,query,cursor,listRevision,hovered,columns,
        [&](int32_t kind,const std::string& filter)->std::optional<WorkOrderArtSubjects> {
            auto subjects=nativeJobArtSubjects(job,kind,filter);if(!subjects)return std::nullopt;
            return std::move(subjects->subjects);
        },[&](const std::string& filter){return nativeArtImages(details->revision,filter);});
    if(!observed)return std::nullopt;
    return JobArtPage{details->jobId,details->buildingId,details->revision,std::move(*observed)};
}

// Safe-point caller resolves source membership. Validate fresh owned native
// eligibility and receipts before writing; no allocation or native UI calls follow.
inline JobSettingsOutcome applyJobArtSubject(df::job& job,const JobSettingsTarget& target,uint64_t revision,int32_t option,int32_t kind,int32_t id,uint64_t listRevision,const std::string& query={}) {
    if(!jobArtEffectsReady() || !revision || revision>INT64_MAX || listRevision>INT64_MAX || query.size()>128 || kind<0 || (kind>3 && kind!=5))return JobSettingsOutcome::Rejected;
    if(job.id!=target.jobId)return JobSettingsOutcome::Stale;
    const auto root=nativeJobSettings(job,-1,{},false);
    if(!root || root->buildingId!=target.buildingId || root->revision!=revision)return JobSettingsOutcome::Stale;
    if(option<0 || size_t(option)>=root->options.size())return JobSettingsOutcome::Rejected;
    const auto optionKind=root->options[size_t(option)].kind;
    if(optionKind!=1 && optionKind!=3)return JobSettingsOutcome::Rejected;
    if(optionKind==3 && int(job.specdata.improvement)!=0)return JobSettingsOutcome::Rejected;
    int32_t selectedType=kind-1,selectedId=id,selectedSubid=job.art_spec.subid;
    if(kind==0) {
        if(id!=-1 || listRevision || !query.empty())return JobSettingsOutcome::Rejected;
        selectedSubid=-1;
    } else if(kind==5) {
        const auto images=nativeArtImages(root->revision,query);if(!images)return JobSettingsOutcome::Rejected;
        if(!listRevision || images->listRevision!=listRevision)return JobSettingsOutcome::Stale;
        if(id<0 || size_t(id)>=images->rows.size())return JobSettingsOutcome::Rejected;
        selectedType=3;selectedId=images->rows[size_t(id)]->id;selectedSubid=images->rows[size_t(id)]->subid;
    } else {
        const auto subjects=nativeJobArtSubjects(job,kind,query);if(!subjects)return JobSettingsOutcome::Rejected;
        if(!listRevision || subjects->subjects.listRevision!=listRevision)return JobSettingsOutcome::Stale;
        if(std::find(subjects->subjects.ids.begin(),subjects->subjects.ids.end(),id)==subjects->subjects.ids.end())return JobSettingsOutcome::Rejected;
    }
    job.art_spec.type=df::job_art_specifier_type(selectedType);job.art_spec.id=selectedId;job.art_spec.subid=selectedSubid;
    return JobSettingsOutcome::Applied;
}
inline JobSettingsOutcome beginJobArt(df::job& job,const JobSettingsTarget& target,uint64_t revision,int32_t option,uint64_t choicesRevision) {
    if(!jobArtEffectsReady() || !revision || revision>INT64_MAX || !choicesRevision || choicesRevision>INT64_MAX || option<0)return JobSettingsOutcome::Rejected;
    if(job.id!=target.jobId)return JobSettingsOutcome::Stale;
    const auto observed=nativeJobSettings(job,option);
    if(!observed || observed->buildingId!=target.buildingId || observed->revision!=revision || observed->choicesRevision!=choicesRevision)return JobSettingsOutcome::Stale;
    if(size_t(option)>=observed->options.size() || observed->options[size_t(option)].kind!=3)return JobSettingsOutcome::Rejected;
    if(std::none_of(observed->materials.begin(),observed->materials.end(),[](const auto& row){return row.index==0;}))return JobSettingsOutcome::Rejected;
    // Native219306..219334: Image changes only this union before opening art.
    job.specdata.improvement=df::improvement_type(0);return JobSettingsOutcome::Applied;
}

}
