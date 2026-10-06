#include "doctest.h"
#include "../bridge/plugin/location_catalog_page.h"
namespace area=df3d_area;

TEST_CASE("Location pages reject mixed snapshots after native metadata changes") {
  area::LocationCatalogSnapshot<area::ReligiousPractice> snapshot;
  std::vector<area::ReligiousPractice> rows;
  for(int32_t id=0;id<260;++id)rows.push_back({area::ReligiousPracticeKind::Deity,id,1});
  snapshot.observe(8,rows);
  const auto first=snapshot.page(8,0);
  REQUIRE(first.status==area::LocationPageStatus::Ready);
  REQUIRE(first.rows.size()==128);CHECK(first.total==260);CHECK(first.nextCursor==128);
  snapshot.observe(8,rows);
  const auto middle=snapshot.page(8,128,first.revision);
  REQUIRE(middle.status==area::LocationPageStatus::Ready);
  CHECK(middle.rows.front().id==128);CHECK(middle.nextCursor==256);
  const auto last=snapshot.page(8,256,first.revision);
  REQUIRE(last.rows.size()==4);CHECK(last.nextCursor==0);
  // A change outside the requested page still invalidates the whole receipt.
  rows.back().deities.push_back({259,"Native fixture deity",{3,7}});
  snapshot.observe(8,rows);
  const auto stale=snapshot.page(8,128,first.revision);
  CHECK(stale.status==area::LocationPageStatus::Stale);CHECK(stale.rows.empty());CHECK(stale.revision==0);
  const auto fresh=snapshot.page(8,0);
  CHECK(fresh.revision!=first.revision);
  rows[0].worshippers=2;snapshot.observe(8,rows);
  CHECK(snapshot.page(8,128,fresh.revision).status==area::LocationPageStatus::Stale);
  // Earlier pages own their contents even after a refresh.
  CHECK(first.rows[0].worshippers==1);
}

TEST_CASE("Location receipt cannot survive epoch changes or unavailable observations") {
  area::LocationCatalogSnapshot<area::GuildWorkers> snapshot;
  std::vector<area::GuildWorkers> rows{{41,29,true,1316,24,"Synthetic guild"}};
  snapshot.observe(4,rows);const auto original=snapshot.page(4,0);
  REQUIRE(original.status==area::LocationPageStatus::Ready);
  snapshot.observe(5,rows);
  CHECK(snapshot.page(4,0).status==area::LocationPageStatus::Unavailable);
  CHECK(snapshot.page(5,0,original.revision).status==area::LocationPageStatus::Stale);
  const auto next=snapshot.page(5,0);
  snapshot.observe(5,std::nullopt);
  CHECK(snapshot.page(5,0).status==area::LocationPageStatus::Unavailable);
  snapshot.observe(5,rows);
  CHECK(snapshot.page(5,0,next.revision).status==area::LocationPageStatus::Stale);
  const auto restored=snapshot.page(5,0);
  rows[0].guildId=42;rows[0].guildName="Other synthetic guild";rows[0].members=0;
  snapshot.observe(5,rows);
  CHECK(snapshot.page(5,0,restored.revision).status==area::LocationPageStatus::Stale);
  snapshot.observe(0,rows);
  CHECK(snapshot.page(0,0).status==area::LocationPageStatus::Unavailable);
}

TEST_CASE("Location pagination requires issued page boundaries and revision") {
  area::LocationCatalogSnapshot<area::GuildWorkers> snapshot;
  snapshot.observe(1,std::vector<area::GuildWorkers>{});
  const auto empty=snapshot.page(1,0);
  CHECK(empty.status==area::LocationPageStatus::Ready);CHECK(empty.total==0);CHECK(empty.nextCursor==0);
  std::vector<area::GuildWorkers> rows(129);
  snapshot.observe(1,rows);const auto first=snapshot.page(1,0);
  CHECK(snapshot.page(1,128).status==area::LocationPageStatus::Stale);
  CHECK(snapshot.page(1,1,first.revision).status==area::LocationPageStatus::InvalidCursor);
  CHECK(snapshot.page(1,256,first.revision).status==area::LocationPageStatus::InvalidCursor);
  CHECK(snapshot.page(1,128,first.revision).rows.size()==1);
}
