#pragma once
#include "location_staff_native.h"
#include "location_catalog_page.h"

namespace df3d_area {
struct LocationStaffTarget {
  int32_t siteId=-1,locationId=-1,occupationId=-1;
  bool valid() const {return siteId>=0 && locationId>=0 && occupationId>=0;}
  bool operator==(const LocationStaffTarget& other) const {
    return std::tie(siteId,locationId,occupationId)==std::tie(other.siteId,other.locationId,other.occupationId);
  }
};
struct LocationStaffCandidatePage : LocationCatalogPage<LocationStaffCandidate> {
  LocationStaffTarget target;
  int32_t role=-1;
};
// Observe semantic facts at a DF safe point before serving any page. Identical
// candidate lists from different occupations must never share a usable receipt.
class LocationStaffCandidateSnapshot {
public:
  void observe(uint64_t epoch,LocationStaffTarget target,std::optional<LocationStaffCandidates> facts) {
    if(!target.valid() || !facts || !validRole(facts->role)) {
      invalidate();return;
    }
    if(!target_ || !(*target_==target) || role_!=facts->role || assignmentBindings_!=facts->assignmentBindings) rows_.invalidate();
    target_=target;role_=facts->role;assignmentBindings_=std::move(facts->assignmentBindings);
    rows_.observe(epoch,std::move(facts->rows));
  }
  void invalidate() {target_.reset();role_=-1;assignmentBindings_.clear();rows_.invalidate();}
  LocationStaffCandidatePage page(uint64_t epoch,LocationStaffTarget target,uint32_t cursor,
                                  uint64_t revision=0) const {
    LocationStaffCandidatePage result;
    if(!target_ || !target.valid())return result;
    if(!(*target_==target)) {result.status=LocationPageStatus::Stale;return result;}
    static_cast<LocationCatalogPage<LocationStaffCandidate>&>(result)=rows_.page(epoch,cursor,revision);
    if(result.status==LocationPageStatus::Ready) {result.target=target;result.role=role_;}
    return result;
  }
private:
  static bool validRole(int32_t role) {
    switch(role) {case 0:case 1:case 2:case 5:case 7:case 8:case 9:case 10:return true;default:return false;}
  }
  std::optional<LocationStaffTarget> target_;
  int32_t role_=-1;
  std::vector<LocationStaffAssignmentBinding> assignmentBindings_;
  LocationCatalogSnapshot<LocationStaffCandidate> rows_;
};

struct LocationReligiousStaffTarget {
  int32_t siteId=-1,locationId=-1,entityId=-1,assignmentId=-1;
  bool valid() const {return siteId>=0 && locationId>=0 && entityId>=0 && assignmentId>=0;}
  bool operator==(const LocationReligiousStaffTarget& other) const {
    return std::tie(siteId,locationId,entityId,assignmentId)==
      std::tie(other.siteId,other.locationId,other.entityId,other.assignmentId);
  }
};
struct LocationReligiousCandidatePage : LocationCatalogPage<LocationStaffCandidate> {
  LocationReligiousStaffReceipt target;
};
// List ownership is separate from a selected candidate's mutation receipt.
// Refresh both at a safe point; a fresh candidate receipt must never authorize
// an action against a retired list or a changed holder. No native UI is retained.
class LocationReligiousCandidateSnapshot {
public:
  void observe(uint64_t epoch,LocationReligiousStaffTarget target,
               std::optional<LocationReligiousStaffReceipt> receipt,
               std::optional<LocationStaffCandidates> facts) {
    if(!target.valid() || !receipt || !facts || facts->role!=-1 ||
       !receipt->revision || receipt->revision>uint64_t(std::numeric_limits<int64_t>::max()) ||
       receipt->positionId<0 || !(identity(*receipt)==target)) {
      invalidate();return;
    }
    if(!receipt_ || !sameBinding(*receipt_,*receipt))rows_.invalidate();
    receipt_=*receipt;rows_.observe(epoch,std::move(facts->rows));
  }
  void invalidate() {receipt_.reset();rows_.invalidate();}
  LocationReligiousCandidatePage page(uint64_t epoch,LocationReligiousStaffTarget target,
                                      uint32_t cursor,uint64_t revision=0) const {
    LocationReligiousCandidatePage result;
    if(!receipt_ || !target.valid())return result;
    if(!(identity(*receipt_)==target)) {result.status=LocationPageStatus::Stale;return result;}
    static_cast<LocationCatalogPage<LocationStaffCandidate>&>(result)=rows_.page(epoch,cursor,revision);
    if(result.status==LocationPageStatus::Ready)result.target=*receipt_;
    return result;
  }
private:
  static LocationReligiousStaffTarget identity(const LocationReligiousStaffReceipt& r) {
    return {r.siteId,r.locationId,r.entityId,r.assignmentId};
  }
  static bool sameBinding(const LocationReligiousStaffReceipt& a,const LocationReligiousStaffReceipt& b) {
    return identity(a)==identity(b) &&
      std::tie(a.positionId,a.holderId,a.unitId,a.revision,a.removable)==
      std::tie(b.positionId,b.holderId,b.unitId,b.revision,b.removable);
  }
  std::optional<LocationReligiousStaffReceipt> receipt_;
  LocationCatalogSnapshot<LocationStaffCandidate> rows_;
};
}
