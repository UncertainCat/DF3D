// Real Windows mappings, isolated from the user's live bridge by unique names.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <doctest.h>
#include "shm_layout.h"
#include "client_mailbox.h"
#include "command_util.h"
#include "publication_clock.h"
#include "synthetic_builder.h"
#include "wm/mirror_client.h"
namespace m = df3d::mirror;
namespace shm = df3d::shm;
namespace {
struct Mapping {
  HANDLE handle = nullptr;
  void* view = nullptr;
  Mapping(const std::string& name, size_t size) {
    handle = CreateFileMappingA(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                                static_cast<DWORD>(size), name.c_str());
    REQUIRE(handle != nullptr);
    REQUIRE(GetLastError() != ERROR_ALREADY_EXISTS);
    view = MapViewOfFile(handle, FILE_MAP_ALL_ACCESS, 0, 0, size);
    REQUIRE(view != nullptr);
  }
  ~Mapping() { if (view) UnmapViewOfFile(view); if (handle) CloseHandle(handle); }
};
uint64_t unique() { static uint64_t n = 0; return (uint64_t(GetCurrentProcessId()) << 32) | (++n + 0xDF300000); }
struct Publisher {
  uint64_t epoch = unique();
  std::string name = "Local\\df3d_recovery_test_" + std::to_string(epoch);
  Mapping ring;
  shm::RegionHeader* h = static_cast<shm::RegionHeader*>(ring.view);
  std::unique_ptr<Mapping> grid;
  shm::TerrainHeader* terrain = nullptr;
  Publisher(int sizeX = 16, uint32_t journalBytes = 0)
      : ring(name,shm::regionSize(65536,4096,journalBytes)) {
    shm::initRegion(h,static_cast<uint32_t>(m::SchemaVersion::Current),65536,4096,journalBytes);
    newGrid(sizeX);
  }
  void newGrid(int sizeX = 16) {
    epoch = unique();
    char name[64]; shm::terrainRegionName(epoch, name, sizeof(name));
    grid = std::make_unique<Mapping>(name, shm::terrainRegionSize(sizeX / 16, 4096));
    terrain = static_cast<shm::TerrainHeader*>(grid->view);
    shm::initTerrain(terrain, static_cast<uint32_t>(m::SchemaVersion::Current), sizeX, 16, 1, epoch, 4096);
    shm::terrainAppendMaterial(terrain, "GRANITE", 7);
    fill(100, 1);
    shm::atomicStoreRelease(&h->terrainEpoch, epoch);
  }
  void fill(uint64_t tick, uint8_t shape) {
    shm::TerrainTile tiles[256]{};
    for (auto& t : tiles) { t.shape = shape; t.material_kind = 1; t.material = 0; }
    shm::terrainBeginWrite(terrain);
    for (uint32_t block=0; block<terrain->blockCount; ++block) shm::terrainWriteBlock(terrain, block, tiles);
    shm::terrainEndWrite(terrain, tick);
  }
  void publish(m::SyntheticFort& fort, uint64_t tick, uint64_t timestampMicros = 0) {
    fort.snapshot(tick);
    auto bytes = fort.serialize();
    size_t off = 8, last = off;
    while (off < bytes.size()) { last = off; off += 4 + flatbuffers::ReadScalar<uint32_t>(bytes.data() + off); }
    REQUIRE(shm::publishSnapshot(h,bytes.data()+last,bytes.size()-last,tick,timestampMicros));
  }
  std::unique_ptr<wm::MirrorClient> open() {
    std::string error;
    auto c = wm::MirrorClient::open(error, name);
    REQUIRE_MESSAGE(c != nullptr, error);
    return c;
  }
};
m::SyntheticFort fortWithEntities() {
  m::SyntheticFort f(16,16,1);
  auto wood = f.material("OAK"); // index 0 differs from the grid's GRANITE
  m::SyntheticFort::BuildingSpec b; b.kind=m::BuildingKind::Bed; b.material=wood;
  f.placeBuilding(8,b);
  m::SyntheticFort::ItemSpec i; i.kind=m::ItemKind::Wood; i.material=wood;
  f.placeItem(9,i);
  f.addUnit(7,"DWARF",1,1,0);
  return f;
}
}
TEST_CASE("live mapping: terrain gap retries a torn grid at the same tick and preserves entity materials") {
  Publisher pub;
  auto f = fortWithEntities();
  auto c = pub.open(); wm::WorldModel model;
  pub.publish(f,100); REQUIRE(c->poll(model,0));
  REQUIRE(model.tileAt({0,0,0}));
  CHECK(model.tileAt({0,0,0})->shape == wm::TileShape::Wall);
  REQUIRE(model.item(9)); REQUIRE(model.building(8));
  CHECK(model.materialName(model.item(9)->material) == "OAK");
  CHECK(model.materialName(model.building(8)->material) == "OAK");
  CHECK(model.materialName(model.tileAt({0,0,0})->material) == "GRANITE");
  pub.fill(120,2); // lost Delta outside eight-frame resend window
  shm::terrainBeginWrite(pub.terrain); // writer unavailable throughout poll
  pub.publish(f,120); REQUIRE(c->poll(model,1));
  CHECK_FALSE(c->terrainSynced());
  CHECK(model.tileAt({0,0,0})->shape == wm::TileShape::Wall);
  shm::terrainEndWrite(pub.terrain,120);
  REQUIRE(c->poll(model,2)); // no new ring snapshot, but grid must recover
  CHECK(c->terrainSynced());
  CHECK(model.tileAt({0,0,0})->shape == wm::TileShape::Floor);
  CHECK(model.materialName(model.item(9)->material) == "OAK");
  // Lost entity removal and missed Full response: keep requesting until a Full arrives.
  f.removeItem(9); pub.publish(f,121); // removal never polled
  pub.publish(f,140); REQUIRE(c->poll(model,3));
  auto requests = c->entityFullRequests();
  pub.publish(f,142); REQUIRE(c->poll(model,4));
  CHECK(c->entityFullRequests() > requests);
  REQUIRE(model.item(9));
  f.requestFullItems(); f.requestFullBuildings(); pub.publish(f,143);
  REQUIRE(c->poll(model,5)); CHECK(model.item(9) == nullptr);
}
TEST_CASE("live mapping: equal-tick epoch replacement and unload invalidate all models") {
  for (bool ingestTerrain : {true, false}) {
    Publisher pub; auto f = fortWithEntities(); auto c = pub.open();
    wm::WorldModelConfig cfg; cfg.ingestTerrain = ingestTerrain; wm::WorldModel model(cfg);
    pub.publish(f,500); REQUIRE(c->poll(model,0));
    REQUIRE(model.item(9)); CHECK(model.materialName(model.item(9)->material) == "OAK");
    auto generation = model.sessionGeneration();
    auto next = fortWithEntities(); next.moveUnit(7,9,9,0); next.removeItem(9);
    // Producer unload contract: invalidate old ring before new grid epoch.
    shm::atomicStoreRelease(&pub.h->bridgeTick,0);
    pub.newGrid();
    REQUIRE(c->poll(model,0.5)); CHECK_FALSE(model.hasData());
    pub.publish(next,500);
    REQUIRE(c->poll(model,1)); CHECK(model.sessionGeneration() == generation + 1);
    CHECK(model.evaluate(7,model.renderTickAt(1)).pos.x == 9);
    CHECK(model.item(9) == nullptr);
    // Entire epoch transition can also happen between two polls at equal tick.
    next.moveUnit(7,8,8,0); pub.newGrid(); pub.publish(next,500);
    REQUIRE(c->poll(model,1.5));
    CHECK(model.sessionGeneration() == generation + 2);
    CHECK(model.evaluate(7,model.renderTickAt(1.5)).pos.x == 8);
    shm::atomicStoreRelease(&pub.h->bridgeTick,0);
    shm::atomicStoreRelease(&pub.h->terrainEpoch,0);
    REQUIRE(c->poll(model,2)); CHECK_FALSE(model.hasData()); CHECK(model.unitIds().empty());
    CHECK_FALSE(c->poll(model,3)); // old snapshot still exists, must stay unloaded
    pub.newGrid(); next.moveUnit(7,4,4,0); pub.publish(next,3);
    REQUIRE(c->poll(model,4)); CHECK(model.renderTickAt(4) == 3);
    CHECK(model.evaluate(7,3).pos.x == 4);
  }
}
TEST_CASE("live mapping: missing terrain mapping appears while ring tick remains unchanged") {
  Publisher pub; auto f = fortWithEntities(); auto c = pub.open(); wm::WorldModel model;
  char name[64]; const auto epoch = unique(); shm::terrainRegionName(epoch,name,sizeof(name));
  shm::atomicStoreRelease(&pub.h->terrainEpoch,epoch);
  pub.publish(f,100); REQUIRE(c->poll(model,0)); CHECK_FALSE(model.hasTerrain());
  Mapping grid(name,shm::terrainRegionSize(1,4096));
  auto* h = static_cast<shm::TerrainHeader*>(grid.view);
  shm::initTerrain(h,static_cast<uint32_t>(m::SchemaVersion::Current),16,16,1,epoch,4096);
  shm::TerrainTile tiles[256]{};
  shm::terrainBeginWrite(h); shm::terrainWriteBlock(h,0,tiles); shm::terrainEndWrite(h,100);
  REQUIRE(c->poll(model,1)); CHECK(model.hasTerrain()); CHECK(c->lastError().empty());
}

TEST_CASE("live mapping: paused late attach ingests requested entity Full without advancing DF") {
  for (uint64_t tick : {uint64_t(0), uint64_t(120)}) {
  Publisher pub; auto f = fortWithEntities();
  pub.fill(tick,1);
  f.addUnit(17,"DWARF",2,1,0); // explicitly empty stack must also bootstrap
  f.setAppearance(7, {{"TEST_BODY",1,2,1,1,"",-1,-1,0,0},
                      {"TEST_CLOTHING",3,4,1,1,"",-1,-1,0,0}});
  f.requestFullAppearances();
  pub.publish(f,tick); // initial Full happened before this viewer existed
  pub.publish(f,tick); // latest-only buffer now contains no initial Full
  auto c = pub.open(); wm::WorldModel model;
  REQUIRE(c->poll(model,0));
  CHECK(model.item(9) == nullptr);
  CHECK(model.building(8) == nullptr);
  CHECK(model.unitAppearance(7) == nullptr);
  auto requests = c->entityFullRequests();
  REQUIRE(c->poll(model,0.1)); // same tick must keep requesting bootstrap
  CHECK(c->entityFullRequests() > requests);
  f.requestFullItems(); f.requestFullBuildings(); f.requestFullAppearances();
  pub.publish(f,tick); // bridge services Full at the unchanged paused tick
  REQUIRE(c->poll(model,0.2));
  REQUIRE(model.item(9)); REQUIRE(model.building(8));
  CHECK(model.latestTick() == tick);
  CHECK(model.materialName(model.item(9)->material) == "OAK");
  REQUIRE(model.unitAppearance(7));
  CHECK(model.unitAppearance(7)->layers.size() == 2);
  const auto appearanceVersion = model.unitAppearance(7)->version;
  REQUIRE(model.unitAppearance(17));
  CHECK(model.unitAppearance(17)->layers.empty());
  CHECK_FALSE(c->poll(model,0.3)); // synchronized same-tick polls remain cheap

  pub.publish(f,tick); // ordinary unchanged publication omits appearances
  REQUIRE(c->poll(model,0.4));
  REQUIRE(model.unitAppearance(7));
  CHECK(model.unitAppearance(7)->version == appearanceVersion);
  CHECK(model.unitAppearance(7)->layers.size() == 2);

  // Reopen the transport against the same model and same paused producer.
  // The same viewer recovers its complete appearance at the unchanged tick.
  c.reset(); c = pub.open();
  REQUIRE(c->poll(model,0.5));
  f.requestFullItems(); f.requestFullBuildings(); f.requestFullAppearances();
  pub.publish(f,tick);
  REQUIRE(c->poll(model,0.6));
  REQUIRE(model.unitAppearance(7));
  CHECK(model.unitAppearance(7)->layers.size() == 2);
  // A later Full must replace a previously nonempty stack with an empty one.
  f.setAppearance(7, {});
  f.requestFullItems(); f.requestFullBuildings(); f.requestFullAppearances();
  pub.publish(f,tick);
  REQUIRE(c->poll(model,0.7));
  REQUIRE(model.unitAppearance(7));
  CHECK(model.unitAppearance(7)->layers.empty());
  CHECK(model.latestTick() == tick);
  CHECK_FALSE(c->poll(model,0.8));
  }
}

TEST_CASE("live mapping: empty paused entity and appearance Full completes bootstrap") {
  Publisher pub; m::SyntheticFort f(16,16,1); pub.fill(0,1);
  auto c = pub.open(); wm::WorldModel model;
  f.requestFullItems(); f.requestFullBuildings(); f.requestFullAppearances();
  pub.publish(f,0);
  REQUIRE(c->poll(model,0));
  CHECK(c->itemsSynced()); CHECK(c->buildingsSynced());
  CHECK(model.unitIds().empty()); CHECK(model.latestTick() == 0);
  CHECK(c->lastError().empty()); CHECK_FALSE(c->poll(model,0.1));
}

TEST_CASE("live mapping: tick-zero fort is valid but old zero-tick slots cannot cross epochs") {
  Publisher pub; auto f = fortWithEntities(); auto c = pub.open(); wm::WorldModel model;
  pub.fill(0,1);
  CHECK_FALSE(c->poll(model,0)); // grid exists, no snapshot published
  pub.publish(f,0);
  REQUIRE(c->poll(model,0.1));
  CHECK(model.hasData()); CHECK(model.latestTick() == 0);
  CHECK(model.hasTerrain()); REQUIRE(model.item(9));
  CHECK_FALSE(c->poll(model,0.2));
  // Same producer reloads a different fort, also paused at zero.
  shm::atomicStoreRelease(&pub.h->terrainEpoch,0);
  shm::invalidateSnapshots(pub.h);
  pub.newGrid(); pub.fill(0,2);
  REQUIRE(c->poll(model,0.3)); CHECK_FALSE(model.hasData());
  CHECK(model.item(9) == nullptr);
  auto next = fortWithEntities(); next.removeItem(9); next.moveUnit(7,8,8,0);
  pub.publish(next,0);
  REQUIRE(c->poll(model,0.4)); CHECK(model.hasData());
  CHECK(model.latestTick() == 0); CHECK(model.item(9) == nullptr);
  CHECK(model.evaluate(7,0).pos.x == 8);
  CHECK(model.tileAt({0,0,0})->shape == wm::TileShape::Floor);
}

TEST_CASE("live mapping: paused edits ingest distinct publications at one simulation tick") {
  for(uint64_t tick : {uint64_t(0),uint64_t(100)}) {
    Publisher pub;auto f=fortWithEntities();auto c=pub.open();wm::WorldModel model;
    f.setTile(0,0,0,m::TileState(m::TileShape::Wall,m::MaterialKind::Stone,0,0,m::LiquidKind::None,m::TileFlags::NONE, df3d::mirror::DesignationKind::None));
    pub.fill(tick,1);pub.publish(f,tick);REQUIRE(c->poll(model,0));
    REQUIRE(c->buildingsSynced());REQUIRE(c->itemsSynced());REQUIRE(c->terrainSynced());
    CHECK_FALSE(c->poll(model,0.1));
    m::SyntheticFort::BuildingSpec b;b.kind=m::BuildingKind::Stockpile;b.material=0;
    f.placeBuilding(31,b);f.removeItem(9);f.requestFullBuildings();f.requestFullItems();
    f.setTile(0,0,0,m::TileState(m::TileShape::Floor,m::MaterialKind::Stone,0,0,m::LiquidKind::None,m::TileFlags::NONE, df3d::mirror::DesignationKind::None));
    pub.fill(tick,2);pub.publish(f,tick);
    REQUIRE(c->poll(model,0.2));REQUIRE(model.building(31));CHECK(model.item(9)==nullptr);
    CHECK(model.tileAt({0,0,0})->shape==wm::TileShape::Floor);
    CHECK(model.latestTick()==tick);CHECK_FALSE(c->poll(model,0.3));
    // Skip two publications: the active slot is unchanged but its sequence isn't.
    f.removeBuilding(31);f.requestFullBuildings();f.requestFullItems();pub.publish(f,tick);
    f.requestFullBuildings();f.requestFullItems();pub.publish(f,tick);
    REQUIRE(c->poll(model,0.4));CHECK(model.building(31)==nullptr);
    CHECK(model.latestTick()==tick);CHECK_FALSE(c->poll(model,0.5));
  }
}

TEST_CASE("command sender cannot retarget its displayed world after epoch replacement") {
  Publisher pub;auto f=fortWithEntities();auto client=pub.open();wm::WorldModel model;
  pub.fill(100,1);pub.publish(f,100);REQUIRE(client->poll(model,0));
  const auto epoch=shm::atomicLoadAcquire(&pub.h->terrainEpoch);
  REQUIRE(client->sendSetPause(true)>0);
  uint8_t bytes[1024];const auto size=shm::popCommand(pub.h,bytes,sizeof(bytes));REQUIRE(size>0);
  const auto* command=m::parseCommand(bytes,size);REQUIRE(command);
  CHECK(command->world_epoch()==epoch);
  shm::atomicStoreRelease(&pub.h->terrainEpoch,epoch+1);
  CHECK(client->sendSetPause(false)==0);
  CHECK(client->sendSetItemFlags(9,wm::OptionalBool::Set,wm::OptionalBool::Unchanged,wm::OptionalBool::Unchanged)==0);
  CHECK_FALSE(m::commandEpochMatches(*command,epoch+1));
  CHECK(shm::popCommand(pub.h,bytes,sizeof(bytes))==0);
}

TEST_CASE("live mapping: paused dig receipt and designation survive idle polling and reconnect") {
  for (uint64_t tick : {uint64_t(0), uint64_t(100)}) {
    Publisher pub; auto f = fortWithEntities(); auto c = pub.open(); wm::WorldModel model;
    pub.fill(tick,1); pub.publish(f,tick); REQUIRE(c->poll(model,0));
    CHECK_FALSE(c->poll(model,0.1));
    const auto seq = c->sendDesignateDig({2,3,2,3,0},wm::DigKind::Dig,4);
    REQUIRE(seq != 0);
    // Synthetic producer executes the command at the same paused tick.
    shm::TerrainTile tiles[256]{};
    for (auto& tile : tiles) { tile.shape=1; tile.material_kind=1; tile.material=0; }
    tiles[3*16+2].flags=wm::kTileDigDesignated;
    shm::terrainBeginWrite(pub.terrain);
    shm::terrainWriteBlock(pub.terrain,0,tiles);
    shm::terrainEndWrite(pub.terrain,tick);
    f.setTile(2,3,0,m::TileState(m::TileShape::Wall,m::MaterialKind::Stone,0,0,
        m::LiquidKind::None,m::TileFlags::DigDesignated, df3d::mirror::DesignationKind::None));
    f.commandResult(seq,m::CommandStatus::Ok,"1 of 1 tiles");
    pub.publish(f,tick); REQUIRE(c->poll(model,0.2));
    CHECK(model.latestTick()==tick);
    REQUIRE(model.tileAt({2,3,0}));
    CHECK((model.tileAt({2,3,0})->flags & wm::kTileDigDesignated)!=0);
    auto results=model.drainCommandResults(); REQUIRE(results.size()==1);
    CHECK(results[0].seq==seq); CHECK(results[0].status==wm::CommandStatus::Ok);
    CHECK_FALSE(c->poll(model,0.3));
    CHECK((model.tileAt({2,3,0})->flags & wm::kTileDigDesignated)!=0);
    f.commandResult(seq,m::CommandStatus::Ok,"1 of 1 tiles");
    pub.publish(f,tick); REQUIRE(c->poll(model,0.4));
    CHECK(model.drainCommandResults().empty()); // repeated receipts retire once
    c.reset(); c=pub.open(); wm::WorldModel reconnected;
    REQUIRE(c->poll(reconnected,0.5));
    REQUIRE(reconnected.tileAt({2,3,0}));
    CHECK((reconnected.tileAt({2,3,0})->flags & wm::kTileDigDesignated)!=0);
    CHECK(reconnected.latestTick()==tick);
  }
}

TEST_CASE("live mapping: paused command spills recover all grid blocks after earlier running attachment") {
  Publisher pub(32); m::SyntheticFort f(32,16,1);
  f.material("GRANITE"); auto c=pub.open(); wm::WorldModel model;
  f.requestFullItems(); f.requestFullBuildings();
  pub.fill(100,1); pub.publish(f,100); REQUIRE(c->poll(model,0));
  REQUIRE(c->terrainSynced()); REQUIRE(c->itemsSynced()); REQUIRE(c->buildingsSynced());
  CHECK(c->terrainGridTick()==100);
  pub.publish(f,101); REQUIRE(c->poll(model,0.1)); // viewer reaches a later pause
  // One command affects two blocks in the grid, but only one fits its Delta.
  shm::TerrainTile tiles[256]{};
  for (auto& tile:tiles) { tile.shape=1;tile.material_kind=1;tile.material=0; }
  tiles[0].flags=wm::kTileDigDesignated;
  shm::terrainBeginWrite(pub.terrain);
  shm::terrainWriteBlock(pub.terrain,0,tiles);
  shm::terrainWriteBlock(pub.terrain,1,tiles);
  shm::terrainEndWrite(pub.terrain,101);
  f.setTile(0,0,0,m::TileState(m::TileShape::Wall,m::MaterialKind::Stone,0,0,
      m::LiquidKind::None,m::TileFlags::DigDesignated, df3d::mirror::DesignationKind::None));
  f.commandResult(41,m::CommandStatus::Ok,"2 of 2 tiles");
  pub.publish(f,101); REQUIRE(c->poll(model,0.2));
  CHECK(c->terrainGridTick()==101);
  REQUIRE(model.tileAt({0,0,0})); REQUIRE(model.tileAt({16,0,0}));
  CHECK((model.tileAt({0,0,0})->flags & wm::kTileDigDesignated)!=0);
  CHECK((model.tileAt({16,0,0})->flags & wm::kTileDigDesignated)!=0);
  CHECK(model.drainCommandResults().size()==1);
  CHECK_FALSE(c->poll(model,0.3)); // no idle republish needed to recover spill
}

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <thread>
#include "wm/buffered_world_client.h"
namespace {
template<class Predicate> bool awaitBuffered(Predicate predicate) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
  while (!predicate()) {
    if (std::chrono::steady_clock::now() >= deadline) return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return true;
}
}
TEST_CASE("buffered live mapping owns ingestion thread and sends commands before delayed display") {
  Publisher pub;
  auto fort = fortWithEntities(); pub.publish(fort, 100);
  std::atomic<double> now{0};
  std::atomic<bool> onWorker{false};
  std::atomic<int> timingEvents{0};
  const auto mainThread = std::this_thread::get_id();
  wm::BufferedWorldConfig cfg;
  SUBCASE("diagnostic timings disabled") { cfg.collectTimings = false; }
  SUBCASE("diagnostic timings enabled") { cfg.collectTimings = true; }
  cfg.timingObserver = [&](const char*, double start, double duration) {
    if (start > 0 && duration >= 0 && std::this_thread::get_id() != mainThread) ++timingEvents;
  };
  cfg.clock = [&] {
    if (std::this_thread::get_id() != mainThread) onWorker = true;
    return now.load();
  };
  std::string error;
  auto client = wm::BufferedWorldClient::open(cfg, error, pub.name);
  REQUIRE_MESSAGE(client, error);
  REQUIRE(awaitBuffered([&] { return client->stats().published >= 1; }));
  CHECK(client->stats().sourcePublications.accepted >= 1);
  CHECK(client->stats().sourcePublications.missed == 0);
  CHECK(onWorker.load());
  CHECK_FALSE(client->takeReady(0.099));
  CHECK(client->sendSetPause(true) == 0); // no presented model yet
  CHECK(client->sendSetPause(false) == 0);
  auto frame = client->takeReady(0.1);
  REQUIRE(frame); REQUIRE(frame->model->item(9));
  REQUIRE(client->sendSetPause(true)>0);
  uint8_t commandBytes[1024];
  auto commandSize=shm::popCommand(pub.h,commandBytes,sizeof(commandBytes));
  REQUIRE(commandSize>0);
  auto* sent=df3d::mirror::parseCommand(commandBytes,commandSize);
  REQUIRE(sent); CHECK(sent->world_epoch()==frame->sourceEpoch);
  CHECK(frame->model->latestTick() == 100);
  CHECK(frame->releaseAt == doctest::Approx(0.1));
  // An unload invalidates pending/displayed generations without waiting out
  // the delay, even at the same injected timestamp.
  shm::atomicStoreRelease(&pub.h->terrainEpoch, 0);
  REQUIRE(awaitBuffered([&] { return client->stats().generation > frame->generation; }));
  REQUIRE(awaitBuffered([&] { return client->stats().published >= 2; }));
  auto unloaded = client->takeReady(0);
  REQUIRE(unloaded); CHECK_FALSE(unloaded->model->hasData());
  CHECK(unloaded->generation > frame->generation);
  client->stop();
  client->stop();
  const auto timing = client->stats();
  if (cfg.collectTimings) {
    CHECK(timing.pollMilliseconds > 0.0);
    CHECK(timing.publicationMilliseconds > 0.0);
    CHECK(timingEvents.load() >= 2);
  } else {
    CHECK(timing.pollMilliseconds == 0.0);
    CHECK(timing.publicationMilliseconds == 0.0);
    CHECK(timingEvents.load() == 0);
  }
}

TEST_CASE("live mapping: exact missed publications independent of simulation tick gaps") {
  Publisher pub; auto f=fortWithEntities();
  pub.publish(f,100); pub.publish(f,101); // Before attachment is not loss.
  auto c=pub.open(); wm::WorldModel model;
  REQUIRE(c->poll(model,0));
  CHECK(c->publicationStats().lastIndex==2);
  CHECK(c->publicationStats().missed==0);
  pub.publish(f,102); pub.publish(f,103); pub.publish(f,104);
  REQUIRE(c->poll(model,1));
  CHECK(c->publicationStats().missed==2);
  CHECK(c->publicationStats().gapEvents==1);
  CHECK(c->publicationStats().largestGap==2);
  pub.publish(f,500); // Big tick jump, but no publication was missed.
  REQUIRE(c->poll(model,2));
  CHECK(c->publicationStats().missed==2);
  pub.publish(f,500); pub.publish(f,500); // Paused edits are publications too.
  REQUIRE(c->poll(model,3));
  CHECK(c->publicationStats().missed==3);
  const auto accepted=c->publicationStats().accepted;
  c->poll(model,4);
  CHECK(c->publicationStats().accepted==accepted);
  shm::invalidateSnapshots(pub.h); pub.newGrid();
  pub.publish(f,501);pub.publish(f,502);
  REQUIRE(c->poll(model,5));
  CHECK(c->publicationStats().missed==3); // New epoch establishes baseline.
}

TEST_CASE("buffered capture keeps receiving ordered publications while model copying is stalled") {
  Publisher pub(16,4*1024*1024);
  auto fort = fortWithEntities();
  pub.publish(fort,100);
  std::atomic<double> now{0};
  std::mutex gateMutex;
  std::condition_variable gateWake;
  bool stalled=false, released=false;
  wm::BufferedWorldConfig cfg;
  cfg.collectTimings=true;
  cfg.publishIntervalSeconds=0.001;
  bool overflow=false, replaceEpoch=false, burst=false;
  SUBCASE("backlog fits") {}
  SUBCASE("bounded backlog overruns and requests authoritative recovery") {
    cfg.maxPendingSnapshots=2;
    overflow=true;
  }
  SUBCASE("session replacement while old model copy is stalled") {
    replaceEpoch=true;
  }
  SUBCASE("journal burst drains without one poll delay per publication") {
    burst=true;
    cfg.pollIntervalSeconds=0.1;
  }
  cfg.clock=[&] { return now.load(); };
  cfg.timingObserver=[&](const char* stage,double,double) {
    if (std::strcmp(stage,"worker.snapshot_copy")!=0) return;
    std::unique_lock<std::mutex> lock(gateMutex);
    if (released) return;
    stalled=true;
    gateWake.notify_all();
    gateWake.wait(lock,[&] { return released; });
  };
  std::string error;
  auto client=wm::BufferedWorldClient::open(cfg,error,pub.name);
  REQUIRE_MESSAGE(client,error);
  // Release before destroying the client even if an assertion aborts the test.
  struct ReleaseGate {
    std::mutex& mutex; std::condition_variable& wake; bool& released;
    ~ReleaseGate() {
      { std::lock_guard<std::mutex> lock(mutex); released=true; }
      wake.notify_all();
    }
  } release{gateMutex,gateWake,released};
  {
    std::unique_lock<std::mutex> lock(gateMutex);
    REQUIRE(gateWake.wait_for(lock,std::chrono::seconds(2),[&] { return stalled; }));
  }
  const auto processed=client->stats().sourcePublications.accepted;
  if (replaceEpoch) {
    shm::invalidateSnapshots(pub.h);
    pub.newGrid();
    auto replacement=fortWithEntities();
    replacement.removeItem(9);
    replacement.moveUnit(7,12,1,0);
    now=0.02;
    pub.publish(replacement,100); // Same simulation tick, different session.
    REQUIRE(awaitBuffered([&] { return client->stats().capturedPublications.lastIndex==2; }));
    CHECK(client->stats().pendingSnapshots==1);
    {
      std::lock_guard<std::mutex> lock(gateMutex);
      released=true;
    }
    gateWake.notify_all();
    std::unique_ptr<wm::BufferedWorldFrame> replacementFrame;
    REQUIRE(awaitBuffered([&] {
      if (auto ready=client->takeReady(1)) {
        // Even the completed old copy must not escape after capture observes
        // the replacement epoch, before processing has caught up with it.
        CHECK(ready->sourceEpoch==pub.epoch);
        replacementFrame=std::move(ready);
      }
      return replacementFrame && replacementFrame->model->hasData();
    }));
    CHECK(replacementFrame->generation>0);
    CHECK(replacementFrame->model->item(9)==nullptr);
    CHECK(replacementFrame->model->evaluate(7,100).pos.x==12);
    CHECK(client->stats().captureQueueDrops==0);
    return;
  }
  const uint64_t count=burst?40:6;
  for (uint64_t i=1;i<=count;++i) {
    now=double(i)*0.01;
    fort.moveUnit(7,int(i%12)+1,1,0);
    fort.commandResult(i,m::CommandStatus::Ok,"received in order");
    pub.publish(fort,100+i);
    if (!burst) REQUIRE(awaitBuffered([&] { return client->stats().capturedPublications.lastIndex==i+1; }));
  }
  REQUIRE(awaitBuffered([&] { return client->stats().capturedPublications.lastIndex==count+1; }));
  const auto blocked=client->stats();
  CHECK(blocked.sourcePublications.accepted==processed);
  CHECK(blocked.capturedPublications.accepted==count+1);
  CHECK(blocked.capturedPublications.missed==0);
  CHECK(blocked.pendingSnapshots==(overflow?2:count));
  CHECK(blocked.pendingBytes>0);
  CHECK(blocked.captureQueueDrops==(overflow?4:0));
  {
    std::lock_guard<std::mutex> lock(gateMutex);
    released=true;
  }
  gateWake.notify_all();
  REQUIRE(awaitBuffered([&] { return client->stats().sourcePublications.lastIndex==count+1; }));
  const auto caughtUp=client->stats();
  CHECK(caughtUp.sourcePublications.accepted==(overflow?3:count+1));
  CHECK(caughtUp.sourcePublications.missed==(overflow?4:0));
  CHECK(caughtUp.pendingSnapshots==0);
  // Ordered ingestion can catch up before its rate-limited model copy. Advance
  // the injected publication clock without changing source capture timestamps.
  now=double(count)*0.01+0.005;
  REQUIRE(awaitBuffered([&] { return client->stats().published>caughtUp.published; }));
  if (overflow) {
    CHECK(caughtUp.entityFullRequests>blocked.entityFullRequests);
    fort.removeItem(9);
    fort.requestFullItems(); fort.requestFullBuildings();
    now=0.07;
    pub.publish(fort,107);
    REQUIRE(awaitBuffered([&] { return client->stats().sourcePublications.lastIndex==8; }));
    CHECK(client->stats().itemsSynced);
    now=0.08;
    std::unique_ptr<wm::BufferedWorldFrame> recovered;
    REQUIRE(awaitBuffered([&] {
      if (auto ready=client->takeReady(1)) recovered=std::move(ready);
      return recovered && recovered->model->latestTick()==107;
    }));
    CHECK(recovered->model->latestTick()==107);
    CHECK(recovered->model->item(9)==nullptr);
    return;
  }
  auto frame=client->takeReady(1);
  REQUIRE(frame);
  CHECK(frame->model->latestTick()==100+count);
  CHECK(frame->capturedAt==doctest::Approx(double(count)*0.01));
  CHECK(frame->releaseAt==doctest::Approx(double(count)*0.01+0.1));
  const auto results=frame->model->drainCommandResults();
  REQUIRE(results.size()==count);
  for (size_t i=0;i<results.size();++i) CHECK(results[i].seq==i+1);
}

TEST_CASE("captured snapshots own bytes after ring reuse and ingest in capture order") {
  Publisher pub;
  auto fort=fortWithEntities();
  auto collector=pub.open();
  auto processor=pub.open();
  wm::WorldModel model;
  std::vector<wm::MirrorClient::CapturedSnapshot> pending;
  for (uint64_t i=0;i<4;++i) {
    fort.moveUnit(7,int(i)+2,1,0);
    pub.publish(fort,100+i);
    wm::MirrorClient::CapturedSnapshot snapshot;
    REQUIRE(collector->capture(snapshot,double(i)*0.1));
    CHECK(snapshot.index==i+1);
    REQUIRE_FALSE(snapshot.bytes.empty());
    pending.push_back(std::move(snapshot));
  }
  // Both shared slots have been overwritten before any semantic ingestion.
  for (size_t i=0;i<pending.size();++i) {
    REQUIRE(processor->ingestCaptured(model,pending[i]));
    CHECK(model.latestTick()==100+i);
    CHECK(model.evaluate(7,double(100+i)).pos.x==doctest::Approx(double(i)+2));
  }
  CHECK(collector->captureStats().accepted==4);
  CHECK(processor->publicationStats().accepted==4);
  CHECK(processor->publicationStats().missed==0);
}

TEST_CASE("captured publications from an unloaded epoch cannot restore its entities") {
  Publisher pub;
  auto fort=fortWithEntities();
  auto collector=pub.open();
  auto processor=pub.open();
  wm::WorldModel model;
  pub.publish(fort,100);
  wm::MirrorClient::CapturedSnapshot first,stale,unload;
  REQUIRE(collector->capture(first,0));
  REQUIRE(processor->ingestCaptured(model,first));
  REQUIRE(model.item(9));
  pub.publish(fort,101);
  REQUIRE(collector->capture(stale,0.1));
  shm::atomicStoreRelease(&pub.h->terrainEpoch,0);
  shm::invalidateSnapshots(pub.h);
  REQUIRE(collector->capture(unload,0.2));
  REQUIRE(processor->ingestCaptured(model,unload));
  CHECK_FALSE(model.hasData());
  processor->ingestCaptured(model,stale);
  CHECK_FALSE(model.hasData());
  CHECK(model.unitIds().empty());
  CHECK(model.item(9)==nullptr);
}

TEST_CASE("buffered capture rejects empty queue budgets") {
  Publisher pub;
  wm::BufferedWorldConfig cfg;
  cfg.clock=[] { return 0.0; };
  SUBCASE("zero snapshot count") { cfg.maxPendingSnapshots=0; }
  SUBCASE("zero byte budget") { cfg.maxPendingBytes=0; }
  std::string error;
  auto client=wm::BufferedWorldClient::open(cfg,error,pub.name);
  CHECK_FALSE(client);
  CHECK_FALSE(error.empty());
}

TEST_CASE("queued older terrain deltas do not repeatedly resynthesize a newer grid Full") {
  Publisher pub;
  auto fort=fortWithEntities();
  auto collector=pub.open();
  auto processor=pub.open();
  wm::WorldModel model;
  wm::MirrorClient::CapturedSnapshot first,queued;
  pub.publish(fort,100);
  REQUIRE(collector->capture(first,0));
  fort.setTile(0,0,0,m::TileState(m::TileShape::Floor,m::MaterialKind::Stone,0,0,
      m::LiquidKind::None,m::TileFlags::NONE,m::DesignationKind::None));
  pub.publish(fort,101);
  REQUIRE(collector->capture(queued,0.1));
  pub.fill(110,2);
  REQUIRE(processor->ingestCaptured(model,first));
  REQUIRE(processor->terrainGridTick()==110);
  REQUIRE(model.tileAt({0,0,0}));
  CHECK(model.tileAt({0,0,0})->shape==wm::TileShape::Floor);
  // The queued Delta is already represented in the Full. New grid activity
  // must not turn replay of that old Delta into another whole-grid scan.
  pub.fill(120,1);
  REQUIRE(processor->ingestCaptured(model,queued));
  CHECK(processor->terrainGridTick()==110);
  CHECK(model.tileAt({0,0,0})->shape==wm::TileShape::Floor);
  CHECK(model.latestTick()==101);
}

TEST_CASE("buffered capture reports a publication larger than its byte budget") {
  Publisher pub;
  auto fort=fortWithEntities();
  pub.publish(fort,100);
  wm::BufferedWorldConfig cfg;
  cfg.maxPendingBytes=1;
  cfg.clock=[] { return 0.0; };
  std::string error;
  auto client=wm::BufferedWorldClient::open(cfg,error,pub.name);
  REQUIRE_MESSAGE(client,error);
  REQUIRE(awaitBuffered([&] { return !client->stats().error.empty(); }));
  client->stop();
  const auto stopped=client->stats();
  CHECK(stopped.error.find("maxPendingBytes")!=std::string::npos);
  CHECK(stopped.captureQueueDrops==1);
  CHECK(stopped.sourcePublications.accepted==0);
  CHECK(stopped.pendingBytes==0);
  CHECK_FALSE(client->takeReady(1));
}

TEST_CASE("rejected publication cannot restamp a pending valid model") {
  Publisher pub;
  auto fort=fortWithEntities();
  pub.publish(fort,100);
  std::atomic<double> now{0};
  wm::BufferedWorldConfig cfg;
  cfg.publishIntervalSeconds=1;
  cfg.clock=[&] { return now.load(); };
  std::string error;
  auto client=wm::BufferedWorldClient::open(cfg,error,pub.name);
  REQUIRE_MESSAGE(client,error);
  REQUIRE(awaitBuffered([&] { return client->stats().published==1; }));
  now=0.01;
  fort.moveUnit(7,3,1,0);
  pub.publish(fort,101);
  REQUIRE(awaitBuffered([&] { return client->stats().sourcePublications.lastIndex==2; }));
  CHECK(client->stats().published==1); // Valid model is waiting for its copy slot.
  now=0.02;
  fort.forgeSchemaVersion(0); // Structurally valid FlatBuffer, invalid semantics.
  pub.publish(fort,102);
  REQUIRE(awaitBuffered([&] { return client->stats().capturedPublications.lastIndex==3; }));
  REQUIRE(awaitBuffered([&] { return client->stats().sourcePublications.rejected>0; }));
  CHECK(client->stats().sourcePublications.lastIndex==2);
  now=2;
  REQUIRE(awaitBuffered([&] { return client->stats().published==2; }));
  auto frame=client->takeReady(3);
  REQUIRE(frame);
  CHECK(frame->model->latestTick()==101);
  CHECK(frame->capturedAt==doctest::Approx(0.01));
  CHECK(frame->releaseAt==doctest::Approx(0.11));
  CHECK(frame->sourceEpoch==pub.epoch);
}

TEST_CASE("journal capture drains distinct same-tick edits in publication order") {
  Publisher pub(16,4*1024*1024);
  auto fort=fortWithEntities(); auto client=pub.open(); wm::WorldModel model;
  pub.publish(fort,100);
  REQUIRE(client->poll(model,0)); // Establish reader baseline before burst.
  for (uint64_t i=1;i<=40;++i) {
    fort.commandResult(i,m::CommandStatus::Ok,"paused edit");
    pub.publish(fort,100);
  }
  for (uint64_t i=1;i<=40;++i) {
    REQUIRE(client->poll(model,0.1));
    CHECK(client->publicationStats().lastIndex==i+1);
    CHECK(model.latestTick()==100);
  }
  CHECK_FALSE(client->poll(model,0.1));
  CHECK(client->captureStats().missed==0);
  const auto results=model.drainCommandResults();
  REQUIRE(results.size()==40);
  for (size_t i=0;i<results.size();++i) CHECK(results[i].seq==i+1);
}

TEST_CASE("journal attachment accepts a protected record behind the live heartbeat") {
  Publisher pub(16,4*1024*1024);
  auto fort=fortWithEntities(); auto collector=pub.open();
  pub.publish(fort,100);
  // Reproduce a heartbeat advancing while the copied record is verified.
  shm::atomicStoreRelease(&pub.h->bridgeTick,uint64_t(101));
  wm::MirrorClient::CapturedSnapshot captured;
  REQUIRE(collector->capture(captured,1));
  CHECK(captured.tick==100);
  CHECK(captured.index==1);
  CHECK(collector->captureStats().rejected==0);
}

TEST_CASE("journal capture reports exact retention loss and resets its epoch baseline") {
  Publisher pub(16,4*1024*1024);
  auto fort=fortWithEntities(); auto collector=pub.open();
  wm::MirrorClient::CapturedSnapshot captured;
  pub.publish(fort,100);
  REQUIRE(collector->capture(captured,0));
  for (int i=0;i<150;++i) pub.publish(fort,100);
  REQUIRE(collector->capture(captured,1));
  CHECK(captured.index==24);
  CHECK(collector->captureStats().missed==22);
  CHECK(collector->captureStats().gapEvents==1);
  for (uint64_t index=25;index<=151;++index) {
    REQUIRE(collector->capture(captured,1));
    CHECK(captured.index==index);
  }
  CHECK_FALSE(collector->capture(captured,1));
  shm::invalidateSnapshots(pub.h);
  pub.newGrid();
  auto replacement=fortWithEntities();
  pub.publish(replacement,100);
  pub.publish(replacement,100);
  REQUIRE(collector->capture(captured,2));
  CHECK(captured.index==153); // New epoch attaches latest, not old retained history.
  CHECK(captured.epoch==pub.epoch);
  CHECK(collector->captureStats().missed==22);
}

TEST_CASE("batched journal arrivals preserve publication intervals for the model clock") {
  Publisher pub(16,4*1024*1024);
  auto fort=fortWithEntities(); auto collector=pub.open(); auto processor=pub.open();
  wm::WorldModelConfig cfg; cfg.renderDelayTicks=0;
  wm::WorldModel model(cfg);
  const uint64_t origin=shm::publicationClockMicros()-500000;
  wm::MirrorClient::CapturedSnapshot captured;
  pub.publish(fort,100,origin);
  REQUIRE(collector->capture(captured,10));
  REQUIRE(captured.timestamped);
  const double firstSource=captured.sourceWallSeconds;
  REQUIRE(processor->ingestCaptured(model,captured));
  for (uint64_t i=1;i<=8;++i) pub.publish(fort,100+i,origin+i*10000);
  for (uint64_t i=1;i<=8;++i) {
    REQUIRE(collector->capture(captured,10)); // Entire backlog arrives at identical wall time.
    CHECK(captured.wallSeconds==10);
    CHECK(captured.sourceWallSeconds-firstSource==doctest::Approx(double(i)*0.01).epsilon(0.00001));
    REQUIRE(processor->ingestCaptured(model,captured));
  }
  CHECK(model.latestTick()==108);
  // 1 tick / 10ms = 100 ticks/sec: extrapolating 5ms advances half a tick.
  CHECK(model.renderTickAt(captured.sourceWallSeconds+0.005)==doctest::Approx(108.5).epsilon(0.000001));
}

TEST_CASE("buffered release delay follows source publication time rather than late receipt") {
  Publisher pub(16,4*1024*1024);
  auto fort=fortWithEntities();
  pub.publish(fort,100,shm::publicationClockMicros()-500000);
  wm::BufferedWorldConfig cfg;
  cfg.clock=[] { return 0.0; };
  std::string error;
  auto client=wm::BufferedWorldClient::open(cfg,error,pub.name);
  REQUIRE_MESSAGE(client,error);
  REQUIRE(awaitBuffered([&] { return client->stats().published==1; }));
  auto frame=client->takeReady(0);
  REQUIRE(frame); // Already older than the 100ms presentation delay.
  CHECK(frame->capturedAt==0);
  CHECK(frame->sourceAt<-0.4);
  CHECK(frame->releaseAt==doctest::Approx(frame->sourceAt+cfg.delaySeconds));
}

TEST_CASE("a held producer mutex yields a distinct busy error and consumes no sequence number") {
  Publisher pub;auto f=fortWithEntities();auto client=pub.open();wm::WorldModel model;
  pub.fill(100,1);pub.publish(f,100);REQUIRE(client->poll(model,0));
  REQUIRE(client->sendSetPause(true)>0);
  const auto seqBefore=shm::atomicLoadAcquire(&pub.h->commandSequence);
  const auto lastSeq=client->lastCommandSeq();
  // Another writer holds the cross-process mutex; a second thread stands in
  // for that process and keeps it until this test says so (doctest asserts
  // stay on the test thread).
  std::mutex m;std::condition_variable cv;bool held=false,release=false,ok=false;
  std::thread holder([&]{
    HANDLE mutex=CreateMutexA(nullptr,FALSE,shm::CommandWriter::mutexName(pub.name).c_str());
    const bool acquired=mutex && WaitForSingleObject(mutex,INFINITE)==WAIT_OBJECT_0;
    {std::lock_guard<std::mutex> lock(m);held=true;ok=acquired;}cv.notify_all();
    {std::unique_lock<std::mutex> lock(m);cv.wait(lock,[&]{return release;});}
    if(acquired)ReleaseMutex(mutex);
    if(mutex)CloseHandle(mutex);
  });
  {std::unique_lock<std::mutex> lock(m);cv.wait(lock,[&]{return held;});}
  REQUIRE(ok);
  CHECK(client->sendSetPause(false)==0);
  CHECK(client->lastError().find("busy")!=std::string::npos);
  CHECK(shm::atomicLoadAcquire(&pub.h->commandSequence)==seqBefore);  // no seq consumed
  CHECK(client->lastCommandSeq()==lastSeq);
  {std::lock_guard<std::mutex> lock(m);release=true;}cv.notify_all();holder.join();
  // Released: the next command takes exactly the next sequence number.
  const auto seq=client->sendSetPause(false);
  CHECK(seq==seqBefore+1);
  CHECK(client->lastError().empty());
  uint8_t bytes[1024];
  REQUIRE(shm::popCommand(pub.h,bytes,sizeof(bytes))>0);  // the first pause
  REQUIRE(shm::popCommand(pub.h,bytes,sizeof(bytes))>0);  // the one sent after release
  CHECK(shm::popCommand(pub.h,bytes,sizeof(bytes))==0);   // the busy attempt wrote nothing
}
