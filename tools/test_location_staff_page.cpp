#include "doctest.h"
#include "../bridge/plugin/location_staff_page.h"
namespace staff=df3d_area;
namespace {
staff::LocationStaffCandidates candidates(int count=260) {
  staff::LocationStaffCandidates result;result.role=7;
  for(int32_t i=0;i<count;++i) {
    staff::LocationStaffCandidate row;row.unitId=i;row.histfigId=i+1000;
    row.name="Synthetic fixture worker";row.baseName="Synthetic";row.professionName="fixture worker";row.professionColor=7;row.score=5;row.skills={{58,1,20,5}};
    result.rows.push_back(row);
  }
  return result;
}
}
TEST_CASE("Staff page receipts bind every target component even with identical rows") {
  const staff::LocationStaffTarget original{651,2,87};
  for(auto changed:{staff::LocationStaffTarget{652,2,87},{651,3,87},{651,2,88}}) {
    staff::LocationStaffCandidateSnapshot snapshot;auto rows=candidates();
    snapshot.observe(9,original,rows);const auto first=snapshot.page(9,original,0);
    REQUIRE(first.status==staff::LocationPageStatus::Ready);CHECK(first.rows.size()==128);
    snapshot.observe(9,changed,rows);
    CHECK(snapshot.page(9,original,128,first.revision).status==staff::LocationPageStatus::Stale);
    CHECK(snapshot.page(9,changed,128,first.revision).status==staff::LocationPageStatus::Stale);
    const auto next=snapshot.page(9,changed,0);REQUIRE(next.status==staff::LocationPageStatus::Ready);
    CHECK(next.target==changed);CHECK(next.role==7);CHECK(next.revision!=first.revision);
    snapshot.observe(9,original,rows);
    CHECK(snapshot.page(9,original,0,first.revision).status==staff::LocationPageStatus::Stale);
    // Earlier pages own their data and target after a different selector opens.
    CHECK(first.target==original);CHECK(first.rows.front().unitId==0);
  }
}
TEST_CASE("Staff receipts invalidate for role and off-page candidate metadata changes") {
  const staff::LocationStaffTarget target{651,2,87};
  for(int change=0;change<19;++change) {
    staff::LocationStaffCandidateSnapshot snapshot;auto rows=candidates();
    snapshot.observe(9,target,rows);const auto first=snapshot.page(9,target,0);
    auto& row=rows.rows.back();
    if(change==0)rows.role=8;
    if(change==1)++row.unitId;
    if(change==2)++row.histfigId;
    if(change==3)++row.score;
    if(change==4)row.name+=" changed";
    if(change==5)++row.skills[0].id;
    if(change==6)++row.skills[0].rating;
    if(change==7)++row.skills[0].experience;
    if(change==8)++row.skills[0].weight;
    if(change==9)std::swap(rows.rows[258],rows.rows[259]);
    if(change==10)row.baseName+=" changed";
    if(change==11)row.professionName+=" changed";
    if(change==12)++row.professionColor;
    if(change==13)row.legendary=true;
    if(change==14)++row.sourceIndex;
    if(change==15)++row.professionOrder;
    if(change==16)++row.statusOrder;
    if(change==17)row.nameSortKey.push_back(255);
    if(change==18)row.professionSortKey.push_back(0);
    snapshot.observe(9,target,rows);CAPTURE(change);
    CHECK(snapshot.page(9,target,128,first.revision).status==staff::LocationPageStatus::Stale);
  }
}
TEST_CASE("Staff pages handle complete traversal empty results loss and epoch change") {
  const staff::LocationStaffTarget target{651,2,87};staff::LocationStaffCandidateSnapshot snapshot;
  auto rows=candidates();snapshot.observe(3,target,rows);const auto first=snapshot.page(3,target,0);
  snapshot.observe(3,target,rows);const auto second=snapshot.page(3,target,128,first.revision);
  REQUIRE(second.status==staff::LocationPageStatus::Ready);CHECK(second.rows.front().unitId==128);
  CHECK(second.nextCursor==256);const auto last=snapshot.page(3,target,256,first.revision);
  REQUIRE(last.rows.size()==4);CHECK(last.rows.back().unitId==259);CHECK(last.nextCursor==0);
  CHECK(snapshot.page(3,target,128).status==staff::LocationPageStatus::Stale);
  CHECK(snapshot.page(3,target,1,first.revision).status==staff::LocationPageStatus::InvalidCursor);
  snapshot.observe(4,target,rows);
  CHECK(snapshot.page(3,target,0).status==staff::LocationPageStatus::Unavailable);
  CHECK(snapshot.page(4,target,0,first.revision).status==staff::LocationPageStatus::Stale);
  snapshot.observe(4,target,std::nullopt);CHECK(snapshot.page(4,target,0).status==staff::LocationPageStatus::Unavailable);
  snapshot.observe(4,target,rows);CHECK(snapshot.page(4,target,0,first.revision).status==staff::LocationPageStatus::Stale);
  snapshot.observe(4,target,candidates(0));const auto empty=snapshot.page(4,target,0);
  CHECK(empty.status==staff::LocationPageStatus::Ready);CHECK(empty.total==0);CHECK(empty.rows.empty());
  rows.role=3;snapshot.observe(4,target,rows);CHECK(snapshot.page(4,target,0).status==staff::LocationPageStatus::Unavailable);
  snapshot.observe(4,{-1,2,87},candidates());CHECK(snapshot.page(4,target,0).status==staff::LocationPageStatus::Unavailable);
}

TEST_CASE("Staff receipts invalidate on cross-location assignment dependencies without display changes") {
  const staff::LocationStaffTarget target{651,1,88};
  const staff::LocationStaffAssignmentBinding held{259,105,2,1259,259,4,651,-1};
  for(int change=0;change<10;++change) {
    auto rows=candidates();rows.assignmentBindings={held};
    staff::LocationStaffCandidateSnapshot snapshot;snapshot.observe(9,target,rows);
    const auto first=snapshot.page(9,target,0);REQUIRE(first.status==staff::LocationPageStatus::Ready);
    snapshot.observe(9,target,rows);CHECK(snapshot.page(9,target,128,first.revision).status==staff::LocationPageStatus::Ready);
    auto& binding=rows.assignmentBindings.front();
    if(change==0)++binding.ownerUnitId;
    if(change==1)++binding.occupationId;
    if(change==2)++binding.role;
    if(change==3)++binding.histfigId;
    if(change==4)++binding.unitId;
    if(change==5)++binding.locationId;
    if(change==6)++binding.siteId;
    if(change==7)++binding.groupId;
    if(change==8)rows.assignmentBindings.clear();
    if(change==9)rows.assignmentBindings.push_back({259,106,5,1259,259,4,651,-1});
    snapshot.observe(9,target,rows);CAPTURE(change);
    CHECK(snapshot.page(9,target,128,first.revision).status==staff::LocationPageStatus::Stale);
    CHECK(first.rows.front().name==rows.rows.front().name);
    // A restored assignment does not revive an earlier receipt (ABA).
    rows.assignmentBindings={held};snapshot.observe(9,target,rows);
    CHECK(snapshot.page(9,target,0,first.revision).status==staff::LocationPageStatus::Stale);
  }
}
