#pragma once
#include "location_staff_native.h"
#include "location_catalog_page.h"
#include "workshop_workers_native.h"

namespace df3d_production {
struct WorkshopWorkerPage : df3d_area::LocationCatalogPage<df3d_area::LocationStaffCandidate> {
    std::optional<WorkshopWorkerProfile> profile;
};
// Shared staff paging keeps one complete semantic observation behind bounded
// wire pages. Profile and list receipts are separate: changing a restriction
// invalidates the list even when candidate names and skills are unchanged.
class WorkshopWorkerSnapshot {
public:
    void observe(uint64_t epoch,int32_t buildingId) {
        auto profile=workshopWorkerProfile(df::building::find(buildingId));
        if(!profile){invalidate();return;}
        auto rows=df3d_area::observeNativeWorkshopWorkerRows(buildingId);
        if(!rows){invalidate();return;}
        std::stable_sort(rows->begin(),rows->end(),[](const auto& a,const auto& b){return a.score>b.score;});
        if(!profile_ || profile_->buildingId!=buildingId || profile_->revision!=profile->revision)rows_.invalidate();
        profile_=std::move(profile);rows_.observe(epoch,std::move(rows));
    }
    void invalidate() {profile_.reset();rows_.invalidate();}
    WorkshopWorkerPage page(uint64_t epoch,int32_t buildingId,uint32_t cursor,uint64_t revision=0) const {
        WorkshopWorkerPage result;
        if(!profile_)return result;
        if(profile_->buildingId!=buildingId){result.status=df3d_area::LocationPageStatus::Stale;return result;}
        static_cast<df3d_area::LocationCatalogPage<df3d_area::LocationStaffCandidate>&>(result)=rows_.page(epoch,cursor,revision);
        if(result.status==df3d_area::LocationPageStatus::Ready)result.profile=profile_;
        return result;
    }
private:
    std::optional<WorkshopWorkerProfile> profile_;
    df3d_area::LocationCatalogSnapshot<df3d_area::LocationStaffCandidate> rows_;
};
}
