#pragma once
#include "machinery_body.h"
#include <cstdint>
#include <optional>
#include <string>
#include <vector>
#include <utility>

namespace df3d_production {
// Owned semantic observation. Names remain native CP437 until transport encoding.
struct BuildingHeaderObservation {
    int32_t id=-1,type=-1,stage=-1,maxStage=-1;
    std::string customName,nativeName,headerName;
    bool removing=false,suspended=false,hasWorker=false,forbidden=false;
    struct Job {int32_t id,type;uint32_t flags;};
    std::vector<Job> jobs;
    uint64_t revision=0;
    std::optional<MachineryBody> machinery;
    std::optional<uint8_t> wellStatus;
};
inline uint64_t buildingHeaderRevision(const BuildingHeaderObservation& value) {
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto byte=[&](uint8_t b){hash^=b;hash*=UINT64_C(1099511628211);};
    const auto number=[&](uint64_t n){for(int i=0;i<8;++i){byte(uint8_t(n));n>>=8;}};
    number(value.id);number(value.type);number(value.stage);number(value.maxStage);
    for(const auto* text:{&value.customName,&value.nativeName,&value.headerName}) {
        number(text->size());for(unsigned char c:*text)byte(c);
    }
    byte(value.removing);byte(value.suspended);byte(value.hasWorker);byte(value.forbidden);
    number(value.jobs.size());for(const auto& job:value.jobs){number(job.id);number(job.type);number(job.flags);}
    // Preserve revisions for existing non-machinery observations.
    if(value.machinery){const auto& v=*value.machinery;
        number(v.machineId);number(v.produced);number(v.required);byte(uint8_t(v.status));
        byte(v.stableFoundation);byte(v.disengaged);byte(v.pumpManual);byte(v.pumpDirection);}
    if(value.wellStatus)byte(*value.wellStatus);
    return (hash&INT64_MAX)?(hash&INT64_MAX):1;
}
inline bool validBuildingHeader(const BuildingHeaderObservation& value) {
    return value.id>=0 && value.type>=0 && value.stage>=0 && value.maxStage>=value.stage &&
        value.customName.size()<=512 && !value.nativeName.empty() && value.nativeName.size()<=512 &&
        !value.headerName.empty() && value.headerName.size()<=512 &&
        (value.removing || (!value.suspended && !value.hasWorker)) &&
        (value.type==18)==value.wellStatus.has_value() && (!value.wellStatus || *value.wellStatus<=3) &&
        machineryType(value.type)==bool(value.machinery) &&
        (!value.machinery || validMachineryBody(*value.machinery,value.type)) && value.revision==buildingHeaderRevision(value);
}
enum class BuildingHeaderOperation : uint8_t { Rename, Remove, CancelRemoval, PumpManual };
enum class BuildingHeaderOutcome : uint8_t { Rejected, Completed, Stale, Unknown };
struct BuildingHeaderEdit {
    BuildingHeaderOutcome outcome=BuildingHeaderOutcome::Rejected;
    bool mutated=false;
    std::optional<BuildingHeaderObservation> receipt;
};
// Apply=false guarantees no effects began. Throws or unverifiable postconditions
// after entry return Unknown without authority. Callers validate epoch/visibility
// and lossless CP437 conversion at the same safe point; nothing is replayed.
template<class Apply,class Observe>
BuildingHeaderEdit finishBuildingHeaderEdit(const BuildingHeaderObservation& before,
        uint64_t expected,BuildingHeaderOperation operation,const std::string& name,
        Apply apply,Observe observe,int pumpValue=-1) {
    BuildingHeaderEdit result;
    if(!expected || !validBuildingHeader(before) || before.stage!=before.maxStage)return result;
    if(operation!=BuildingHeaderOperation::Rename && operation!=BuildingHeaderOperation::Remove &&
       operation!=BuildingHeaderOperation::CancelRemoval && operation!=BuildingHeaderOperation::PumpManual)return result;
    const bool pump=operation==BuildingHeaderOperation::PumpManual;
    if(pump ? (before.type!=33 || pumpValue<0 || pumpValue>1) : pumpValue!=-1)return result;
    const bool rename=operation==BuildingHeaderOperation::Rename;
    if((rename && (name.size()>30 || name.find('\0')!=std::string::npos)) || (!rename && !name.empty()))return result;
    if(expected!=before.revision){result.outcome=BuildingHeaderOutcome::Stale;return result;}
    if((rename || pump) ? before.removing : before.removing==(operation==BuildingHeaderOperation::Remove))return result;
    if(pump && before.machinery->pumpManual==pumpValue){result.receipt=before;result.outcome=BuildingHeaderOutcome::Completed;return result;}
    if(rename && name==before.customName){result.receipt=before;result.outcome=BuildingHeaderOutcome::Completed;return result;}
    result.mutated=true;result.outcome=BuildingHeaderOutcome::Unknown;
    try {
        if(!apply()){result.mutated=false;result.outcome=BuildingHeaderOutcome::Rejected;return result;}
        auto after=observe();
        if(!after || !validBuildingHeader(*after))return result;
        auto unchanged=*after;
        if(pump) {
            if(!after->machinery || after->machinery->pumpManual!=pumpValue)return result;
            unchanged.machinery->pumpManual=before.machinery->pumpManual;
        } else if(rename) {
            if(after->customName!=name)return result;
            unchanged.customName=before.customName;unchanged.nativeName=before.nativeName;unchanged.headerName=before.headerName;
        } else {
            if(after->removing!=(operation==BuildingHeaderOperation::Remove))return result;
            if(operation==BuildingHeaderOperation::CancelRemoval && !after->jobs.empty())return result;
            unchanged.removing=before.removing;unchanged.suspended=before.suspended;unchanged.hasWorker=before.hasWorker;unchanged.jobs=before.jobs;
        }
        if(buildingHeaderRevision(unchanged)!=before.revision)return result;
        result.receipt=std::move(after);result.outcome=BuildingHeaderOutcome::Completed;
    } catch(...) {result.receipt.reset();}
    return result;
}
}
