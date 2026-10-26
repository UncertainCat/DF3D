#include "doctest.h"
#include "../bridge/plugin/room_publication.h"
#include <memory>
#include <stdexcept>

namespace {
struct Zone {int32_t id;};
struct PublicationFixture {
  std::vector<std::unique_ptr<Zone>> world;
  std::vector<int32_t> ids;
  int allocations=0,completions=0,finishes=0;
  int allocationFailure=-1,completionFailure=-1;
  bool throws=false,invalidId=false,finishFailure=false;
  PublicationFixture(){ids.reserve(4);}
  df3d_area::RoomCreationStatus run(size_t count=4) {
    return df3d_area::publishRooms(count,ids,[&]()->Zone* {
      const int index=allocations++;
      // The native factory may publish before failing to return a pointer.
      world.push_back(std::make_unique<Zone>(Zone{100+index}));
      if(index==allocationFailure) {
        if(throws)throw std::runtime_error("factory failure after publication");
        if(invalidId){world.back()->id=-1;return world.back().get();}
        return nullptr;
      }
      return world.back().get();
    },[&](Zone*,size_t index) {
      ++completions;
      if(int(index)==completionFailure) {
        if(throws)throw std::runtime_error("partial completion");
        return false;
      }
      return true;
    },[](const Zone* zone) noexcept {return zone->id;},[&] {
      ++finishes;
      if(finishFailure && throws)throw std::runtime_error("partial finalization");
      return !finishFailure;
    });
  }
};
}
TEST_CASE("native publication completes a batch with DF retaining every object") {
  PublicationFixture f;
  CHECK(f.run()==df3d_area::RoomCreationStatus::Committed);
  CHECK(f.ids==std::vector<int32_t>{100,101,102,103});
  CHECK(f.world.size()==4);CHECK(f.completions==4);CHECK(f.finishes==1);
}
TEST_CASE("factory failure after publication retains world objects without replay authority") {
  for(int index=0;index<4;++index)for(int fault=0;fault<3;++fault) {
    PublicationFixture f;f.allocationFailure=index;f.throws=fault==1;f.invalidId=fault==2;
    CHECK(f.run()==df3d_area::RoomCreationStatus::Unknown);
    CHECK(f.allocations==index+1);CHECK(f.world.size()==size_t(index+1));
    REQUIRE(f.ids.size()==size_t(index));
    for(int i=0;i<index;++i)CHECK(f.ids[i]==100+i);
    CHECK(f.completions==index);CHECK(f.finishes==0);
  }
}
TEST_CASE("completion failure records the current identity but never deletes a partial batch") {
  for(int index=0;index<4;++index)for(bool throws:{false,true}) {
    PublicationFixture f;f.completionFailure=index;f.throws=throws;
    CHECK(f.run()==df3d_area::RoomCreationStatus::Unknown);
    CHECK(f.allocations==index+1);CHECK(f.world.size()==size_t(index+1));
    REQUIRE(f.ids.size()==size_t(index+1));
    for(int i=0;i<=index;++i)CHECK(f.ids[i]==100+i);
    CHECK(f.completions==index+1);CHECK(f.finishes==0);
  }
}
TEST_CASE("batch finalization failure retains all observation identities as unknown") {
  for(bool throws:{false,true}) {
    PublicationFixture f;f.finishFailure=true;f.throws=throws;
    CHECK(f.run()==df3d_area::RoomCreationStatus::Unknown);
    CHECK(f.ids==std::vector<int32_t>{100,101,102,103});
    CHECK(f.world.size()==4);CHECK(f.finishes==1);
  }
}
TEST_CASE("publication preflight rejects missing capacity and existing identities before factory entry") {
  PublicationFixture f;std::vector<int32_t>().swap(f.ids);
  CHECK(f.run()==df3d_area::RoomCreationStatus::NotStarted);
  CHECK(f.allocations==0);CHECK(f.finishes==0);
  f.ids.reserve(4);f.ids.push_back(999);
  CHECK(f.run()==df3d_area::RoomCreationStatus::NotStarted);
  CHECK(f.allocations==0);CHECK(f.ids==std::vector<int32_t>{999});
  f.ids.clear();CHECK(f.run(0)==df3d_area::RoomCreationStatus::Committed);
  CHECK(f.allocations==0);CHECK(f.finishes==0);
}
