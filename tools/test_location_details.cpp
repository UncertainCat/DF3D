#include "doctest.h"
#include "../bridge/plugin/location_details_native.h"

TEST_CASE("Location access follows native display precedence for every flag combination") {
  using namespace df3d_area;
  // Native160005 observed all eight masks on all six baseline locations.
  // Bit0 visitors, bit1 long-term residents, bit2 members. Some combinations
  // are noncanonical but must still display the observed native mode.
  const LocationAccess nativeModes[]={LocationAccess::Citizens,LocationAccess::Visitors,
      LocationAccess::Residents,LocationAccess::Visitors,LocationAccess::Members,
      LocationAccess::Members,LocationAccess::Members,LocationAccess::Members};
  for(unsigned mask=0;mask<8;++mask) {
    CAPTURE(mask);
    CHECK(locationAccess({bool(mask&1),bool(mask&2),bool(mask&4)})==nativeModes[mask]);
  }
}

TEST_CASE("Native access selections normalize flags and reject unavailable modes") {
  using namespace df3d_area;
  for(uint8_t kind=1;kind<=5;++kind) {
    for(unsigned mode=0;mode<4;++mode) {
      CAPTURE(kind);CAPTURE(mode);
      const auto result=locationAccessSelection(kind,static_cast<LocationAccess>(mode));
      const bool available=mode!=3 || kind==2 || kind==4;
      REQUIRE(bool(result)==available);
      if(!result)continue;
      // Native160005 canonical target masks, independently captured for every
      // initial mask. Visitors also enables long-term residents.
      const unsigned nativeMasks[]={3,2,0,4};
      CHECK((unsigned(result->visitors)+2*unsigned(result->residents)+4*unsigned(result->members))==nativeMasks[mode]);
    }
    CHECK_FALSE(locationAccessSelection(kind,static_cast<LocationAccess>(4)));
    CHECK_FALSE(locationAccessSelection(kind,static_cast<LocationAccess>(255)));
  }
  for(uint8_t kind:{0,6,255})CHECK_FALSE(locationAccessSelection(kind,LocationAccess::Citizens));
}

TEST_CASE("Location details receipt changes with every observed field") {
  using namespace df3d_area;
  LocationDetailsCore base;base.siteId=651;base.id=0;base.kind=5;base.name="Fixture";base.zoneIds={23};
  const auto revision=locationDetailsRevision(base);
  CHECK(revision>0);CHECK(revision<=uint64_t(INT64_MAX));CHECK(locationDetailsRevision(base)==revision);
  for(int field=0;field<47;++field) {
    auto next=base;
    if(field==0)++next.siteId;if(field==1)++next.id;if(field==2)++next.kind;if(field==3)next.name+="x";
    if(field==4)next.accessFlags.visitors=true;if(field==5)next.accessFlags.residents=true;if(field==6)next.accessFlags.members=true;
    if(field==7)next.access=LocationAccess::Members;if(field==8)++next.profession;if(field==9)++next.tier;
    if(field==10)++next.value;if(field==11)++next.desiredCopies;if(field==12)next.recognized=true;
    if(field==13)next.zoneIds.push_back(914);if(field==14)next.zoneIds[0]=24;
    if(field==35)++next.appraisal;
    if(field==44)++next.writtenObjects;
    if(field==45)++next.danceFloorX;if(field==46)++next.danceFloorY;
    if(field>=15 && field<35){auto& supply=next.supplies[size_t(field-15)/2];if(field%2)++supply.stored;else ++supply.desired;}
    if(field==36)++next.facilities.chests;if(field==37)++next.facilities.beds;if(field==38)++next.facilities.tables;if(field==39)++next.facilities.tractionBenches;if(field==40)++next.facilities.bookcases;if(field==41)++next.facilities.chairs;if(field==42)++next.facilities.rooms;if(field==43)++next.facilities.rentedRooms;
    CAPTURE(field);CHECK(locationDetailsRevision(next)!=revision);
  }
}

TEST_CASE("Staff receipts distinguish absence, all row fields, duplicates and order") {
  using namespace df3d_area;
  LocationDetailsCore base;
  const auto absent=locationDetailsRevision(base);
  base.staff.emplace();CHECK(locationDetailsRevision(base)!=absent);
  base.staff->rows.push_back({});
  const auto receipt=locationDetailsRevision(base);
  for(int field=0;field<11;++field) {
    auto next=base;auto& r=next.staff->rows[0];
    if(field==0)r.source=LocationStaffSource::ReligiousPosition;
    int32_t* values[]={&r.occupationId,&r.role,&r.histfigId,&r.unitId,&r.locationId,&r.siteId,&r.groupId,&r.entityId,&r.positionId,&r.assignmentId};
    if(field>0)++*values[field-1];
    CAPTURE(field);CHECK(locationDetailsRevision(next)!=receipt);
  }
  auto duplicate=base;duplicate.staff->rows.push_back(duplicate.staff->rows[0]);
  CHECK(locationDetailsRevision(duplicate)!=receipt);
  duplicate.staff->rows[1].occupationId=17;
  auto swapped=duplicate;std::swap(swapped.staff->rows[0],swapped.staff->rows[1]);
  CHECK(locationDetailsRevision(swapped)!=locationDetailsRevision(duplicate));
  auto missing=base;missing.staff->missingRoles={7,8};
  CHECK(locationDetailsRevision(missing)!=receipt);
  auto changed=missing;changed.staff->missingRoles[1]=9;
  CHECK(locationDetailsRevision(changed)!=locationDetailsRevision(missing));
  auto shorter=missing;shorter.staff.value().missingRoles.resize(1);
  CHECK(locationDetailsRevision(shorter)!=locationDetailsRevision(missing));
}

TEST_CASE("Staff name presence and every resolved identity and text invalidate Details receipts") {
  using namespace df3d_area;
  LocationDetailsCore base;base.staff.emplace();base.staff->rows.push_back({});
  auto next=base;next.staff->rows[0].names.emplace();
  CHECK(locationDetailsRevision(next)!=locationDetailsRevision(base));base=next;
  for(int field=0;field<4;++field) {
    next=base;auto& n=*next.staff->rows[0].names;
    if(field==0)n.positionName="Fixture";if(field==1)n.holderName="Fixture";
    if(field==2)n.holderKind=1;if(field==3)n.holderId=17;
    CHECK(locationDetailsRevision(next)!=locationDetailsRevision(base));
  }
}

TEST_CASE("Location affiliation facts invalidate Details receipts") {
  df3d_area::LocationDetailsCore base;
  auto next=base;next.affiliation.emplace();
  CHECK(df3d_area::locationDetailsRevision(next)!=df3d_area::locationDetailsRevision(base));
  base=next;
  for(int field=0;field<5;++field) {
    next=base;
    if(field==0)next.affiliation->kind=3;
    if(field==1)next.affiliation->id=383;
    if(field==2)next.affiliation->name="Synthetic religion";
    if(field==3)next.affiliation->count=53;
    if(field==4)next.affiliation->workers=12;
    CHECK(df3d_area::locationDetailsRevision(next)!=df3d_area::locationDetailsRevision(base));
  }
}
