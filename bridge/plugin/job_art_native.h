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

}
