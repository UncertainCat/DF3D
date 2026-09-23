#include <doctest.h>
#include "wm/world_source.h"
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include "shm_layout.h"
#include "synthetic_builder.h"
#include <chrono>
#include <thread>

namespace {
struct SourceMapping {
  HANDLE handle=nullptr;
  void* view=nullptr;
  SourceMapping(const std::string& name,size_t size) {
    handle=CreateFileMappingA(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,DWORD(size),name.c_str());
    REQUIRE(handle); REQUIRE(GetLastError()!=ERROR_ALREADY_EXISTS);
    view=MapViewOfFile(handle,FILE_MAP_ALL_ACCESS,0,0,size);REQUIRE(view);
  }
  ~SourceMapping(){if(view)UnmapViewOfFile(view);if(handle)CloseHandle(handle);}
};
bool awaitSource(const std::function<bool()>& ready) {
  const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
  while(!ready()) {
    if(std::chrono::steady_clock::now()>=deadline)return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return true;
}
}
TEST_CASE("source live reconnect adoption never reuses a published generation") {
  namespace shm=df3d::shm;
  namespace mirror=df3d::mirror;
  const auto epoch=(uint64_t(GetCurrentProcessId())<<32)|0xDF3F0001;
  const std::string name="Local\\df3d_source_reconnect_"+std::to_string(epoch);
  SourceMapping ring(name,shm::regionSize(65536,4096));
  auto* header=static_cast<shm::RegionHeader*>(ring.view);
  shm::initRegion(header,uint32_t(mirror::SchemaVersion::Current),65536,4096);
  char gridName[64];shm::terrainRegionName(epoch,gridName,sizeof(gridName));
  SourceMapping grid(gridName,shm::terrainRegionSize(1,4096));
  auto* terrain=static_cast<shm::TerrainHeader*>(grid.view);
  shm::initTerrain(terrain,uint32_t(mirror::SchemaVersion::Current),16,16,1,epoch,4096);
  shm::TerrainTile tiles[256]{};
  shm::terrainBeginWrite(terrain);shm::terrainWriteBlock(terrain,0,tiles);shm::terrainEndWrite(terrain,100);
  shm::atomicStoreRelease(&header->terrainEpoch,epoch);
  mirror::SyntheticFort fort(16,16,1);fort.addUnit(7,"DWARF",1,1,0);fort.snapshot(100);
  const auto bytes=fort.serialize();size_t offset=8,last=offset;
  while(offset<bytes.size()){last=offset;offset+=4+flatbuffers::ReadScalar<uint32_t>(bytes.data()+offset);}
  REQUIRE(shm::publishSnapshot(header,bytes.data()+last,bytes.size()-last,100));
  wm::WorldModelConfig modelConfig;modelConfig.collectLifecycleEvents=false;
  wm::WorldSource source(modelConfig);
  uint64_t previous=source.model().sessionGeneration();
  for(int connection=0;connection<3;++connection) {
    wm::BufferedWorldConfig config;config.clock=[]{return 1.0;};config.delaySeconds=0;
    REQUIRE_MESSAGE(source.attach(config,name),source.error());
    // Compare adopted frames directly: a consumer may observe only the last
    // old frame and first new frame, missing the intermediate empty model.
    wm::WorldSource::Update adopted;
    REQUIRE(awaitSource([&]{adopted=source.poll(1.0);return source.model().hasData();}));
    REQUIRE(adopted.available);REQUIRE(adopted.changed);
    REQUIRE(source.model().hasData());
    CHECK(source.model().sessionGeneration()>previous);
    CHECK(source.model().latestTick()==100);
    CHECK_FALSE(source.model().config().collectLifecycleEvents);
    previous=source.model().sessionGeneration();
    source.detachLive();
    CHECK_FALSE(source.live());CHECK_FALSE(source.model().hasData());
    CHECK(source.model().sessionGeneration()>previous);
  }
}
#endif

TEST_CASE("source owner replaces same fixture identity and preserves valid source on open failure") {
  wm::WorldModelConfig config;
  config.collectLifecycleEvents = false;
  wm::WorldSource source(config);
  const std::string path = DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix";
  REQUIRE(source.loadFixture(path, 100));
  CHECK(source.attached());
  CHECK_FALSE(source.live());
  REQUIRE(source.setFixedTick(105));
  const auto update = source.poll(100);
  CHECK(update.available);
  CHECK(update.renderTick == 105);
  CHECK(source.model().hasData());
  CHECK(source.model().drainEvents().empty());
  const auto generation = source.model().sessionGeneration();
  const auto latest = source.model().latestTick();
  CHECK_FALSE(source.loadFixture(DF3D_FIXTURE_DIR "/missing.df3dfix", 200));
  CHECK_FALSE(source.error().empty());
  CHECK(source.attached());
  CHECK(source.model().sessionGeneration() == generation);
  CHECK(source.model().latestTick() == latest);
  CHECK_FALSE(source.attach({}));
  CHECK(source.error() == "a fixture is loaded; attach() is unavailable");
  REQUIRE(source.loadFixture(path, 300));
  CHECK(source.error().empty());
  CHECK(source.model().sessionGeneration() != generation);
  CHECK_FALSE(source.model().config().collectLifecycleEvents);
  CHECK(source.poll(300).renderTick == 105);
  source.detachLive(); // A live detach never destroys a replay.
  CHECK(source.attached());
}

TEST_CASE("source replay clock supports injected elapsed time and fixed tick release") {
  wm::WorldSource source;
  CHECK_FALSE(source.poll(0).available);
  CHECK(source.sendSetPause(true) == 0);
  CHECK(source.error() == "not attached to the live mirror");
  REQUIRE(source.loadFixture(DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix", 100));
  source.setReplayElapsed(0);
  CHECK(source.poll(999).available);
  const auto firstTick = source.model().latestTick();
  source.setReplayElapsed(100000);
  CHECK(source.poll(999).changed);
  CHECK(source.model().latestTick() > firstTick);
  REQUIRE(source.setFixedTick(12.5));
  CHECK(source.poll(999).renderTick == 12.5);
  REQUIRE(source.setFixedTick(-1));
  CHECK(source.poll(999).renderTick != 12.5);
}
