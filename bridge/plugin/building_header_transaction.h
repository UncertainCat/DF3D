#pragma once
#include "machinery_body.h"
#include "depot_body.h"
#include "cage_body.h"
#include "siege_body.h"
#include "special_building_native.h"
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
    std::optional<DepotBody> depot;
    std::optional<CageBody> cage;
    std::optional<NestBoxBody> nest;
    std::optional<AnimalTrapBody> trap;
    std::optional<HiveBody> hive;
    std::optional<SiegeBody> siege;
    uint64_t siegeRevision=0;
    uint64_t specialRevision=0;
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
    if(value.depot){const auto& v=*value.depot;number(v.flags);number(v.awaitingItems);byte(v.goods);byte(v.trade);
        number(v.workerId);number(v.brokerId);number(v.brokerJobId);number(v.foreground);number(v.background);byte(v.bright);byte(v.accessible);
        for(const auto* text:{&v.brokerName,&v.activity}){number(text->size());for(unsigned char c:*text)byte(c);}}

    if(value.cage){const auto& v=*value.cage;number(v.flags);number(v.materialType);number(v.materialIndex);byte(v.justiceRestraint);byte(v.glass);
        number(v.room.buildingId);number(v.room.roomId);number(v.room.roomType);number(v.room.relevantZones.size());
        number(v.room.siteId);number(v.room.locationId);number(v.room.locationType);number(v.room.locationTier);byte(v.room.locationHasContents);
        for(auto id:v.room.relevantZones)number(id);
        for(const auto* text:{&v.room.introduction,&v.room.name}){number(text->size());for(unsigned char c:*text)byte(c);}
        number(v.room.notices.size());for(const auto& text:v.room.notices){number(text.size());for(unsigned char c:text)byte(c);}}
    if(value.specialRevision)number(value.specialRevision);
    if(value.siege){const auto& v=*value.siege;number(value.siegeRevision);byte(v.type);byte(v.action);byte(v.resting);byte(v.facing);for(auto count:v.ammunition)number(count);}
    if(value.nest){const auto& v=*value.nest;number(v.claimantId);
        for(const auto* text:{&v.status,&v.name}){number(text->size());for(unsigned char c:*text)byte(c);}
        if(v.nameColor){for(auto c:v.nameColor->color)byte(c);for(auto c:v.nameColor->alternate)byte(c);byte(v.nameColor->effect);}}
    return (hash&INT64_MAX)?(hash&INT64_MAX):1;
}
inline bool validBuildingHeader(const BuildingHeaderObservation& value) {
    return value.id>=0 && value.type>=0 && value.stage>=0 && value.maxStage>=value.stage &&
        value.customName.size()<=512 && !value.nativeName.empty() && value.nativeName.size()<=512 &&
        !value.headerName.empty() && value.headerName.size()<=512 &&
        (value.removing || (!value.suspended && !value.hasWorker)) &&
        (value.type==18)==value.wellStatus.has_value() && (!value.wellStatus || *value.wellStatus<=3) &&
        (value.type==6)==value.depot.has_value() && (!value.depot || validDepotBody(*value.depot)) &&
        (value.type==27 || value.type==28)==bool(value.cage) && (!value.cage || value.cage->room.buildingId==value.id) &&
        (value.type==48)==bool(value.nest) && (value.type==24)==bool(value.trap) && (value.type==49)==bool(value.hive) &&
        ((value.type==24 || value.type==49)==(value.specialRevision>0)) &&
        (value.type==22)==bool(value.siege) && (value.type==22)==(value.siegeRevision>0) && (!value.siege || validSiegeBody(*value.siege)) &&
        machineryType(value.type)==bool(value.machinery) &&
        (!value.machinery || validMachineryBody(*value.machinery,value.type)) && value.revision==buildingHeaderRevision(value);
}
enum class BuildingHeaderOperation : uint8_t { Rename, Remove, CancelRemoval, PumpManual, DepotMode, CageAquarium };
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
       operation!=BuildingHeaderOperation::CancelRemoval && operation!=BuildingHeaderOperation::PumpManual && operation!=BuildingHeaderOperation::DepotMode && operation!=BuildingHeaderOperation::CageAquarium)return result;
    const bool pump=operation==BuildingHeaderOperation::PumpManual;
    const bool depot=operation==BuildingHeaderOperation::DepotMode;
    const bool cage=operation==BuildingHeaderOperation::CageAquarium;
    if(cage && (before.type!=28 || !before.cage || before.cage->justiceRestraint || !before.cage->glass || pumpValue<0 || pumpValue>1))return result;
    const uint16_t cageFlags=cage?uint16_t((before.cage->flags&~2U)|(pumpValue?6U:4U)):0;
    if(pump ? (before.type!=33 || pumpValue<0 || pumpValue>1) : depot ? (before.type!=6 || pumpValue<0 || pumpValue>2) : !cage && pumpValue!=-1)return result;
    const uint32_t depotFlags=depot?(pumpValue==0?(before.depot->flags|1U)&~2U:pumpValue==1?before.depot->flags|3U:before.depot->flags&~1U):0;
    const bool rename=operation==BuildingHeaderOperation::Rename;
    if((rename && (name.size()>30 || name.find('\0')!=std::string::npos)) || (!rename && !name.empty()))return result;
    if(expected!=before.revision){result.outcome=BuildingHeaderOutcome::Stale;return result;}
    if((rename || pump || depot || cage) ? before.removing : before.removing==(operation==BuildingHeaderOperation::Remove))return result;
    if(cage && before.cage->flags==cageFlags){result.receipt=before;result.outcome=BuildingHeaderOutcome::Completed;return result;}
    if(depot && before.depot->flags==depotFlags){result.receipt=before;result.outcome=BuildingHeaderOutcome::Completed;return result;}
    if(pump && before.machinery->pumpManual==pumpValue){result.receipt=before;result.outcome=BuildingHeaderOutcome::Completed;return result;}
    if(rename && name==before.customName){result.receipt=before;result.outcome=BuildingHeaderOutcome::Completed;return result;}
    result.mutated=true;result.outcome=BuildingHeaderOutcome::Unknown;
    try {
        if(!apply()){result.mutated=false;result.outcome=BuildingHeaderOutcome::Rejected;return result;}
        auto after=observe();
        if(!after || !validBuildingHeader(*after))return result;
        auto unchanged=*after;
        if(depot) {
            if(!after->depot || after->depot->flags!=depotFlags)return result;
            unchanged.depot->flags=before.depot->flags;
            const bool adding=!(before.depot->flags&1U) && (depotFlags&1U);
            const bool removing=(before.depot->flags&1U) && !(depotFlags&1U);
            if(adding) {
                if(after->jobs.size()!=before.jobs.size()+1)return result;
                size_t old=0;bool found=false;
                for(const auto& job:after->jobs) {
                    if(old<before.jobs.size() && job.id==before.jobs[old].id) {
                        if(job.type!=before.jobs[old].type || job.flags!=before.jobs[old].flags)return result;++old;
                    } else {
                        if(found || job.id<0 || job.type!=197 || job.flags!=0)return result;
                        for(const auto& prior:before.jobs)if(prior.id==job.id)return result;
                        found=true;
                    }
                }
                if(old!=before.jobs.size() || !found)return result;
                unchanged.jobs=before.jobs;
            } else if(removing) {
                size_t remaining=0;bool brokerJobRemoved=false;
                for(const auto& job:before.jobs) {
                    if(job.type==197){brokerJobRemoved|=job.id==before.depot->brokerJobId;continue;}
                    if(remaining>=after->jobs.size())return result;
                    const auto& kept=after->jobs[remaining++];
                    if(kept.id!=job.id || kept.type!=job.type || kept.flags!=job.flags)return result;
                }
                if(remaining!=after->jobs.size() || after->depot->workerId!=-1)return result;
                unchanged.jobs=before.jobs;unchanged.depot->workerId=before.depot->workerId;
                if(brokerJobRemoved) {
                    if(after->depot->brokerJobId!=-1)return result;
                    unchanged.depot->brokerJobId=before.depot->brokerJobId;
                    unchanged.depot->activity=before.depot->activity;unchanged.depot->foreground=before.depot->foreground;
                    unchanged.depot->background=before.depot->background;unchanged.depot->bright=before.depot->bright;
                }
            }
        } else if(cage) {
            if(!after->cage || after->cage->flags!=cageFlags)return result;
            unchanged.cage->flags=before.cage->flags;
            // Native getName derives Cage/Terrarium/Aquarium from these flags.
            // The custom name remains an independently checked semantic fact.
            unchanged.nativeName=before.nativeName;unchanged.headerName=before.headerName;
        } else if(pump) {
            if(!after->machinery || after->machinery->pumpManual!=pumpValue)return result;
            unchanged.machinery->pumpManual=before.machinery->pumpManual;
        } else if(rename) {
            if(after->customName!=name)return result;
            unchanged.customName=before.customName;unchanged.nativeName=before.nativeName;unchanged.headerName=before.headerName;
        } else {
            if(after->removing!=(operation==BuildingHeaderOperation::Remove))return result;
            if(operation==BuildingHeaderOperation::CancelRemoval && !after->jobs.empty())return result;
            unchanged.specialRevision=before.specialRevision;
            unchanged.siegeRevision=before.siegeRevision;
            unchanged.removing=before.removing;unchanged.suspended=before.suspended;unchanged.hasWorker=before.hasWorker;unchanged.jobs=before.jobs;
        }
        if(buildingHeaderRevision(unchanged)!=before.revision)return result;
        result.receipt=std::move(after);result.outcome=BuildingHeaderOutcome::Completed;
    } catch(...) {result.receipt.reset();}
    return result;
}
}
