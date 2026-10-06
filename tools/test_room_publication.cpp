#include "doctest.h"
#include "../bridge/plugin/room_publication.h"
#include <array>
#include <memory>
#include <stdexcept>

namespace {
struct Zone {int slot;int32_t id=-1;};
struct PublicationFixture {
  struct Delete {
    PublicationFixture* fixture;
    void operator()(Zone* zone) const {
      ++fixture->unpublished[zone->slot];fixture->destroy(zone);
    }
  };
  using Owner=std::unique_ptr<Zone,Delete>;
  std::array<Zone*,4> alive{};
  std::array<int,4> destroyed{},unpublished{};
  std::vector<int> published,removed;
  std::vector<Owner> prepared;
  std::vector<int32_t> ids;
  int failAt=-1,removeFailsAt=-1,missingAt=-1;
  bool throwPublish=false,throwRemove=false,assignBeforeFailure=true,throwFind=false,successWithoutId=false;
  explicit PublicationFixture(int count=4) {
    prepared.reserve(count);ids.reserve(count);
    for(int i=0;i<count;++i) {
      alive[i]=new Zone{i};prepared.emplace_back(alive[i],Delete{this});
    }
  }
  void destroy(Zone* zone) {
    const auto slot=zone->slot;REQUIRE(alive[slot]==zone);
    alive[slot]=nullptr;++destroyed[slot];delete zone;
  }
  void finish() {
    prepared.clear();
    for(auto* zone:alive)if(zone)destroy(zone);
  }
  ~PublicationFixture(){finish();}
  df3d_area::RoomCreationStatus run() {
    return df3d_area::publishRooms(prepared,ids,
      [&](Zone* zone,size_t) {
        published.push_back(zone->slot);
        if(zone->slot!=failAt || assignBeforeFailure)zone->id=100+zone->slot;
        if(zone->slot==failAt) {
          if(successWithoutId)return true;
          if(throwPublish)throw std::runtime_error("injected publication fault");
          return false;
        }
        return true;
      },[](const Zone* zone) noexcept {return zone->id;},
      [&](int32_t id)->Zone* {
        if(id-100==missingAt) {
          if(throwFind)throw std::runtime_error("injected identity lookup fault");
          return nullptr;
        }
        return alive.at(size_t(id-100));
      },[&](Zone* zone) {
        const auto slot=zone->slot;removed.push_back(slot);
        destroy(zone); // even a failing cleanup can already have destroyed it
        if(slot==removeFailsAt) {
          if(throwRemove)throw std::runtime_error("injected cleanup fault");
          return false;
        }
        return true;
      });
  }
};
}

TEST_CASE("room publication transfers a complete set and retains no native pointer owners") {
  PublicationFixture fixture;
  CHECK(fixture.run()==df3d_area::RoomCreationStatus::Committed);
  CHECK(fixture.ids==std::vector<int32_t>{100,101,102,103});
  CHECK(fixture.removed.empty());
  for(const auto& owner:fixture.prepared)CHECK_FALSE(owner);
  fixture.finish();
  CHECK(fixture.unpublished==std::array<int,4>{0,0,0,0});
  CHECK(fixture.destroyed==std::array<int,4>{1,1,1,1});
}
TEST_CASE("room publication rollback cleans current then earlier IDs exactly once") {
  for(bool throws:{false,true})for(bool assigned:{false,true})for(int index=0;index<4;++index) {
    PublicationFixture f;f.failAt=index;f.throwPublish=throws;f.assignBeforeFailure=assigned;
    REQUIRE(f.run()==df3d_area::RoomCreationStatus::RolledBack);
    CHECK(f.ids.empty());REQUIRE(f.published.size()==size_t(index+1));
    REQUIRE(f.removed.size()==size_t(index+1));
    for(int i=0;i<=index;++i)CHECK(f.removed[i]==index-i);
    for(int i=index+1;i<4;++i)REQUIRE(f.prepared[i]);
    f.finish();
    for(int i=0;i<4;++i) {
      CHECK(f.destroyed[i]==1);CHECK(f.unpublished[i]==(i>index?1:0));
    }
  }
}
TEST_CASE("room cleanup failure remains unknown after deletion and continues other cleanup") {
  for(bool throws:{false,true})for(int failingCleanup=0;failingCleanup<3;++failingCleanup) {
    PublicationFixture f;f.failAt=2;f.removeFailsAt=failingCleanup;f.throwRemove=throws;
    CHECK(f.run()==df3d_area::RoomCreationStatus::Unknown);
    CHECK(f.ids==std::vector<int32_t>{100,101,102});
    CHECK(f.removed==std::vector<int>{2,1,0});
    CHECK(f.published==std::vector<int>{0,1,2});
    REQUIRE(f.prepared[3]);f.finish();
    CHECK(f.destroyed==std::array<int,4>{1,1,1,1});
    CHECK(f.unpublished==std::array<int,4>{0,0,0,1});
  }
  for(bool throws:{false,true}) {
    PublicationFixture f;f.failAt=2;f.missingAt=1;f.throwFind=throws;
    CHECK(f.run()==df3d_area::RoomCreationStatus::Unknown);
    CHECK(f.ids==std::vector<int32_t>{100,101,102});
    CHECK(f.removed==std::vector<int>{2,0});
    f.finish();CHECK(f.destroyed==std::array<int,4>{1,1,1,1});
  }
  PublicationFixture noId;noId.failAt=2;noId.assignBeforeFailure=false;noId.removeFailsAt=0;
  CHECK(noId.run()==df3d_area::RoomCreationStatus::Unknown);
  CHECK(noId.ids==std::vector<int32_t>{100,101});
  CHECK(noId.removed==std::vector<int>{2,1,0});
  PublicationFixture invalidSuccess;invalidSuccess.failAt=1;
  invalidSuccess.assignBeforeFailure=false;invalidSuccess.successWithoutId=true;
  CHECK(invalidSuccess.run()==df3d_area::RoomCreationStatus::RolledBack);
  CHECK(invalidSuccess.ids.empty());CHECK(invalidSuccess.published==std::vector<int>{0,1});
}
TEST_CASE("room publication refuses incomplete preparation before ownership transfer") {
  PublicationFixture f;
  f.ids=std::vector<int32_t>{};
  CHECK(f.run()==df3d_area::RoomCreationStatus::NotStarted);
  CHECK(f.published.empty());CHECK(f.removed.empty());
  f.ids.reserve(4);f.prepared[1].reset();
  CHECK(f.run()==df3d_area::RoomCreationStatus::NotStarted);
  CHECK(f.published.empty());f.finish();
  CHECK(f.destroyed==std::array<int,4>{1,1,1,1});
  CHECK(f.unpublished==std::array<int,4>{1,1,1,1});
  PublicationFixture staleIds;staleIds.ids.push_back(999);
  CHECK(staleIds.run()==df3d_area::RoomCreationStatus::NotStarted);
  CHECK(staleIds.published.empty());CHECK(staleIds.ids==std::vector<int32_t>{999});
  PublicationFixture empty(0);
  CHECK(empty.run()==df3d_area::RoomCreationStatus::Committed);
}
