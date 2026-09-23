// Tier 0/1 for the shared-memory transport: layout invariants, snapshot
// double-buffer publish/read, and the command ring — exercised on plain
// heap memory (the layout functions are agnostic to how the region is
// mapped; OS mapping is exercised by the live smoke lane).
#include <doctest.h>

#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "command_util.h"
#include "shm_layout.h"

using namespace df3d;

namespace {

struct Region {
  std::unique_ptr<uint8_t[]> mem;
  shm::RegionHeader* h;
};

Region makeRegion(uint32_t snapCap = 4096, uint32_t cmdCap = 256, uint32_t journalBytes = 0) {
  Region r;
  const size_t size = shm::regionSize(snapCap, cmdCap,journalBytes);
  r.mem = std::make_unique<uint8_t[]>(size);
  r.h = reinterpret_cast<shm::RegionHeader*>(r.mem.get());
  shm::initRegion(r.h, 1, snapCap, cmdCap,journalBytes);
  return r;
}

}  // namespace

TEST_CASE("region init and check round-trip; corruption detected") {
  auto r = makeRegion();
  CHECK(shm::checkRegion(r.h, 1) == nullptr);
  CHECK(shm::checkRegion(r.h, 2) != nullptr);  // schema mismatch
  r.h->magic[0] = 'X';
  CHECK(shm::checkRegion(r.h, 1) != nullptr);
}

TEST_CASE("snapshot publish/read: latest wins, slots alternate") {
  auto r = makeRegion();
  std::vector<uint8_t> out(4096);

  CHECK(shm::readLatestSnapshot(r.h, out.data(), out.size()) == 0);  // nothing yet

  const char* a = "snapshot-A";
  const char* b = "snapshot-B-longer";
  REQUIRE(shm::publishSnapshot(r.h, reinterpret_cast<const uint8_t*>(a), 10, 100));
  size_t n = shm::readLatestSnapshot(r.h, out.data(), out.size());
  CHECK(n == 10);
  CHECK(std::memcmp(out.data(), a, 10) == 0);
  CHECK(r.h->bridgeTick == 100);

  REQUIRE(shm::publishSnapshot(r.h, reinterpret_cast<const uint8_t*>(b), 17, 101));
  n = shm::readLatestSnapshot(r.h, out.data(), out.size());
  CHECK(n == 17);
  CHECK(std::memcmp(out.data(), b, 17) == 0);
  // First publish lands in slot 1 (slot 0 is the initial "active"); the
  // second alternates back to slot 0.
  CHECK((r.h->activeSlot & 1u) == 0u);
  CHECK(r.h->slotSeq[0] == 2);
  CHECK(r.h->slotSeq[1] == 2);
}

TEST_CASE("oversized snapshot is refused, not truncated") {
  auto r = makeRegion(64, 256);
  std::vector<uint8_t> big(65, 0xAB);
  CHECK(!shm::publishSnapshot(r.h, big.data(), big.size(), 1));
}

TEST_CASE("command ring: fifo push/pop") {
  auto r = makeRegion();
  std::vector<uint8_t> buf(256);
  for (uint32_t i = 1; i <= 5; ++i) {
    std::vector<uint8_t> msg(i * 3, static_cast<uint8_t>(i));
    REQUIRE(shm::pushCommand(r.h, msg.data(), static_cast<uint32_t>(msg.size())));
  }
  for (uint32_t i = 1; i <= 5; ++i) {
    const size_t n = shm::popCommand(r.h, buf.data(), buf.size());
    REQUIRE(n == i * 3);
    CHECK(buf[0] == i);
  }
  CHECK(shm::popCommand(r.h, buf.data(), buf.size()) == 0);  // empty
}

TEST_CASE("command ring: wraps across the boundary and survives many laps") {
  auto r = makeRegion(64, 64);  // tiny ring forces frequent wraps
  std::vector<uint8_t> buf(64);
  for (uint32_t lap = 0; lap < 100; ++lap) {
    std::vector<uint8_t> msg(21, static_cast<uint8_t>(lap));  // unaligned length
    REQUIRE(shm::pushCommand(r.h, msg.data(), static_cast<uint32_t>(msg.size())));
    const size_t n = shm::popCommand(r.h, buf.data(), buf.size());
    REQUIRE(n == 21);
    CHECK(buf[0] == static_cast<uint8_t>(lap));
  }
}

TEST_CASE("command ring: reports full instead of overwriting") {
  auto r = makeRegion(64, 64);
  std::vector<uint8_t> msg(20, 7);
  int pushed = 0;
  while (shm::pushCommand(r.h, msg.data(), 20)) ++pushed;
  CHECK(pushed >= 1);
  CHECK(pushed <= 3);  // 64-byte ring, 24-byte entries
  // Draining one makes room again.
  std::vector<uint8_t> buf(64);
  REQUIRE(shm::popCommand(r.h, buf.data(), buf.size()) == 20);
  CHECK(shm::pushCommand(r.h, msg.data(), 20));
}

TEST_CASE("end to end: SetPause command through the ring") {
  auto r = makeRegion();
  auto bytes = mirror::buildSetPauseCommand(42, true);
  REQUIRE(shm::pushCommand(r.h, bytes.data(), static_cast<uint32_t>(bytes.size())));

  std::vector<uint8_t> buf(1024);
  const size_t n = shm::popCommand(r.h, buf.data(), buf.size());
  REQUIRE(n == bytes.size());
  const mirror::Command* cmd = mirror::parseCommand(buf.data(), n);
  REQUIRE(cmd != nullptr);
  CHECK(cmd->seq() == 42);
  REQUIRE(cmd->payload_type() == mirror::CommandPayload::SetPause);
  CHECK(cmd->payload_as_SetPause()->paused() == true);
}

TEST_CASE("garbage in the ring is flagged, not consumed") {
  auto r = makeRegion();
  // Simulate corruption: claim a huge entry.
  uint8_t* ring = shm::ringData(r.h);
  const uint32_t bogus = 0x7FFFFFFF;
  std::memcpy(ring, &bogus, 4);
  shm::atomicStoreRelease(&r.h->cmdHead, 8);
  std::vector<uint8_t> buf(64);
  CHECK(shm::popCommand(r.h, buf.data(), buf.size()) == SIZE_MAX);
}

// ---- terrain grid ----

namespace {

struct Grid {
  std::unique_ptr<uint8_t[]> mem;
  shm::TerrainHeader* h;
};

Grid makeGrid(int32_t sx, int32_t sy, int32_t sz, uint64_t epoch = 7, uint32_t matCap = 256) {
  Grid g;
  const size_t size = shm::terrainRegionSize(shm::terrainBlockCount(sx, sy, sz), matCap);
  g.mem = std::make_unique<uint8_t[]>(size);
  g.h = reinterpret_cast<shm::TerrainHeader*>(g.mem.get());
  shm::initTerrain(g.h, 2, sx, sy, sz, epoch, matCap);
  return g;
}

}  // namespace

TEST_CASE("terrain grid: init sizes, check, and region name") {
  auto g = makeGrid(20, 33, 3);
  CHECK(g.h->blocksX == 2);
  CHECK(g.h->blocksY == 3);
  CHECK(g.h->blockCount == 18);
  CHECK(shm::checkTerrain(g.h, 2) == nullptr);
  CHECK(shm::checkTerrain(g.h, 1) != nullptr);
  CHECK(g.h->epoch == 7);
  CHECK(g.h->seq == 0);
  // Every tile starts as "no material", shape Empty.
  const shm::TerrainTile* t = shm::terrainTiles(g.h);
  CHECK(t[0].material == shm::kTerrainNoMaterial);
  CHECK(t[18 * 256 - 1].material == shm::kTerrainNoMaterial);
  CHECK(t[5].shape == 0);
  CHECK(shm::terrainBlockIndex(g.h, 1, 2, 2) == (2 * 3 + 2) * 2 + 1);

  char name[64];
  shm::terrainRegionName(0xABCDu, name, sizeof(name));
  CHECK(std::string(name) == "Local\\df3d_terrain_v1_000000000000abcd");
  g.h->blockCount = 5;
  CHECK(shm::checkTerrain(g.h, 2) != nullptr);
}

TEST_CASE("terrain grid: write batch, versions, materials, and a consistent read") {
  auto g = makeGrid(16, 16, 2);
  REQUIRE(g.h->blockCount == 2);
  CHECK(shm::terrainAppendMaterial(g.h, "INORGANIC:GRANITE", 17) == 0);
  CHECK(shm::terrainAppendMaterial(g.h, "PLANT:OAK:WOOD", 14) == 1);
  CHECK(g.h->materialCount == 2);

  shm::TerrainTile block[256] = {};
  for (auto& t : block) {
    t.shape = 1;  // Wall
    t.material_kind = 1;
    t.material = 0;
  }
  shm::terrainBeginWrite(g.h);
  CHECK((g.h->seq & 1u) == 1);
  CHECK(shm::terrainWriteBlock(g.h, 1, block) == 1);
  shm::terrainEndWrite(g.h, 500);
  CHECK((g.h->seq & 1u) == 0);
  CHECK(g.h->gridTick == 500);
  CHECK(g.h->terrainVersion == 1);
  CHECK(shm::terrainVersions(g.h)[0] == 0);
  CHECK(shm::terrainVersions(g.h)[1] == 1);

  std::vector<shm::TerrainTile> tiles(2 * 256);
  std::vector<uint64_t> versions(2);
  std::vector<uint8_t> mats(g.h->materialsCapacity);
  shm::TerrainReadResult rr;
  REQUIRE(shm::readTerrainGrid(g.h, tiles.data(), versions.data(), mats.data(), rr));
  CHECK(rr.gridTick == 500);
  CHECK(rr.materialCount == 2);
  CHECK(versions[1] == 1);
  CHECK(tiles[256].shape == 1);
  CHECK(tiles[0].shape == 0);

  size_t off = 0;
  const char* s = nullptr;
  uint16_t len = 0;
  REQUIRE(shm::terrainMaterialNext(mats.data(), rr.materialBytes, off, &s, &len));
  CHECK(std::string(s, len) == "INORGANIC:GRANITE");
  REQUIRE(shm::terrainMaterialNext(mats.data(), rr.materialBytes, off, &s, &len));
  CHECK(std::string(s, len) == "PLANT:OAK:WOOD");
  CHECK_FALSE(shm::terrainMaterialNext(mats.data(), rr.materialBytes, off, &s, &len));

  // A read during a write batch is refused (seq odd) rather than torn.
  shm::terrainBeginWrite(g.h);
  CHECK_FALSE(shm::readTerrainGrid(g.h, tiles.data(), versions.data(), mats.data(), rr, 3));
  shm::terrainEndWrite(g.h, 501);
  CHECK(shm::readTerrainGrid(g.h, tiles.data(), versions.data(), mats.data(), rr));
  CHECK(rr.gridTick == 501);
}

TEST_CASE("terrain grid: materials table reports full instead of overflowing") {
  auto g = makeGrid(16, 16, 1, 1, 12);
  CHECK(shm::terrainAppendMaterial(g.h, "ABCDEFGH", 8) == 0);  // 2 + 8 = 10 bytes used
  CHECK(shm::terrainAppendMaterial(g.h, "XY", 2) == shm::kTerrainNoMaterial);  // needs 4
  CHECK(g.h->materialCount == 1);
}

TEST_CASE("publication index counts successful writes including paused edits") {
  auto r=makeRegion(64,256); uint8_t data[65]{}; uint8_t out[64]{};
  shm::SnapshotPublication p;
  REQUIRE(shm::publishSnapshot(r.h,data,1,100));
  REQUIRE(shm::readLatestSnapshot(r.h,out,64,16,&p)==1);
  CHECK(p.index==1);
  CHECK_FALSE(shm::publishSnapshot(r.h,data,65,100));
  CHECK(r.h->publicationIndex==1);
  REQUIRE(shm::publishSnapshot(r.h,data,1,100));
  REQUIRE(shm::publishSnapshot(r.h,data,1,100));
  REQUIRE(shm::readLatestSnapshot(r.h,out,64,16,&p)==1);
  CHECK(p.index==3);
  shm::invalidateSnapshots(r.h);
  CHECK(r.h->publicationIndex==3);
  REQUIRE(shm::publishSnapshot(r.h,data,1,0));
  REQUIRE(shm::readLatestSnapshot(r.h,out,64,16,&p)==1);
  CHECK(p.index==4);
}

TEST_CASE("journal retains a burst in order while new readers attach to latest") {
  auto r=makeRegion(64,256,4096);
  uint8_t out[64]{};
  shm::SnapshotPublication p;
  CHECK(shm::readNextSnapshot(r.h,0,out,sizeof(out),16,&p)==0);
  for (uint8_t i=1;i<=40;++i) {
    REQUIRE(shm::publishSnapshot(r.h,&i,1,100,1000+i)); // All at one paused tick.
  }
  REQUIRE(shm::readNextSnapshot(r.h,0,out,sizeof(out),16,&p)==1);
  CHECK(p.index==40); CHECK(out[0]==40);
  CHECK(p.oldestRetainedIndex==1); CHECK(p.latestIndex==40);
  CHECK(p.timestampMicros==1040); CHECK(p.tick==100);
  // A reader already attached to publication 1 can recover every intermediate.
  for (uint64_t index=2;index<=40;++index) {
    REQUIRE(shm::readNextSnapshot(r.h,index-1,out,sizeof(out),16,&p)==1);
    CHECK(p.index==index); CHECK(out[0]==index);
    CHECK(p.timestampMicros==1000+index);
  }
  CHECK(shm::readNextSnapshot(r.h,40,out,sizeof(out),16,&p)==0);
  CHECK(p.latestIndex==40);
  REQUIRE(shm::readLatestSnapshot(r.h,out,sizeof(out),16,&p)==1);
  CHECK(p.index==40); CHECK(p.timestampMicros==1040); CHECK(p.tick==100);
}

TEST_CASE("journal descriptor wrap exposes exact oldest retained publication") {
  auto r=makeRegion(64,256,4096);
  uint8_t out[64]{};
  for (uint64_t i=1;i<=300;++i) {
    const uint8_t data=uint8_t(i);
    REQUIRE(shm::publishSnapshot(r.h,&data,1,i,10000+i));
  }
  shm::SnapshotPublication p;
  REQUIRE(shm::readNextSnapshot(r.h,1,out,sizeof(out),16,&p)==1);
  CHECK(p.index==173); CHECK(p.oldestRetainedIndex==173);
  CHECK(p.index-1-1==171); // Explicit gap since reader's publication 1.
  for (uint64_t index=173;index<=300;++index) {
    REQUIRE(shm::readNextSnapshot(r.h,index-1,out,sizeof(out),16,&p)==1);
    CHECK(p.index==index); CHECK(out[0]==uint8_t(index));
    CHECK(p.tick==index); CHECK(p.timestampMicros==10000+index);
  }
}

TEST_CASE("journal byte eviction preserves wrapped variable length payloads") {
  auto r=makeRegion(64,257,17); // Non-aligned command ring must not misalign entries.
  CHECK(reinterpret_cast<uintptr_t>(shm::journalDescriptors(r.h))%8==0);
  const std::vector<std::vector<uint8_t>> payloads{
    {1,1,1,1,1,1}, {2,2,2,2,2,2}, {3,3,3,3,3,3}, {4,4,4,4,4}, {5,5,5,5,5,5}};
  for (size_t i=0;i<payloads.size();++i)
    REQUIRE(shm::publishSnapshot(r.h,payloads[i].data(),payloads[i].size(),i+1));
  uint8_t out[64]{}; shm::SnapshotPublication p;
  for (uint64_t index=3;index<=5;++index) {
    REQUIRE(shm::readNextSnapshot(r.h,index==3?1:index-1,out,sizeof(out),16,&p)==payloads[index-1].size());
    CHECK(p.index==index); CHECK(p.oldestRetainedIndex==3);
    CHECK(std::memcmp(out,payloads[index-1].data(),payloads[index-1].size())==0);
  }
}

TEST_CASE("journal invalidation clears retained history but preserves publication monotonicity") {
  auto r=makeRegion(64,256,128);
  uint8_t data=1,out[64]{}; shm::SnapshotPublication p;
  REQUIRE(shm::publishSnapshot(r.h,&data,1,100));
  REQUIRE(shm::publishSnapshot(r.h,&data,1,101));
  shm::invalidateSnapshots(r.h);
  CHECK(shm::readNextSnapshot(r.h,0,out,sizeof(out),16,&p)==0);
  CHECK(p.oldestRetainedIndex==3); CHECK(p.latestIndex==2);
  CHECK(shm::readLatestSnapshot(r.h,out,sizeof(out))==0);
  data=3;
  REQUIRE(shm::publishSnapshot(r.h,&data,1,0,777));
  REQUIRE(shm::readNextSnapshot(r.h,0,out,sizeof(out),16,&p)==1);
  CHECK(p.index==3); CHECK(p.oldestRetainedIndex==3);
  CHECK(p.tick==0); CHECK(p.timestampMicros==777); CHECK(out[0]==3);
}

TEST_CASE("tiny journal rejects oversized publication without changing either transport") {
  auto r=makeRegion(64,256,1);
  uint8_t data[2]{4,5},out[64]{}; shm::SnapshotPublication p;
  REQUIRE(shm::publishSnapshot(r.h,data,1,10,99));
  const auto seq=shm::journalDescriptors(r.h)[1].sequence;
  CHECK_FALSE(shm::publishSnapshot(r.h,data,0,20,100));
  CHECK_FALSE(shm::publishSnapshot(r.h,data,2,20,100));
  CHECK(r.h->publicationIndex==1); CHECK(shm::journalDescriptors(r.h)[1].sequence==seq);
  CHECK(r.h->bridgeTick==10);
  REQUIRE(shm::readNextSnapshot(r.h,0,out,sizeof(out),16,&p)==1);
  CHECK(p.index==1); CHECK(p.timestampMicros==99);
  REQUIRE(shm::readLatestSnapshot(r.h,out,sizeof(out),16,&p)==1);
  CHECK(p.index==1); CHECK(p.tick==10);
}

TEST_CASE("journal retries a writer in progress and reports insufficient destination") {
  auto r=makeRegion(64,256,128);
  uint8_t data[8]{},out[64]{}; shm::SnapshotPublication p;
  REQUIRE(shm::publishSnapshot(r.h,data,sizeof(data),10));
  CHECK(shm::readNextSnapshot(r.h,0,out,7,16,&p)==0);
  CHECK(p.index==1);
  auto& entry=shm::journalDescriptors(r.h)[1];
  const auto seq=entry.sequence;
  shm::atomicStoreRelease(&entry.sequence,seq+1);
  CHECK(shm::readNextSnapshot(r.h,0,out,sizeof(out),3,&p)==0);
  CHECK(p.index==0);
  shm::atomicStoreRelease(&entry.sequence,seq);
  REQUIRE(shm::readNextSnapshot(r.h,0,out,sizeof(out),16,&p)==sizeof(data));
}

TEST_CASE("journal retained reads are independent of an unrelated descriptor write") {
  auto r=makeRegion(64,256,256);
  for (uint8_t i=1;i<=3;++i) REQUIRE(shm::publishSnapshot(r.h,&i,1,i));
  auto* entries=shm::journalDescriptors(r.h);
  const auto pendingSequence=entries[3].sequence;
  shm::atomicStoreRelease(&entries[3].sequence,pendingSequence+1);
  uint8_t out[64]{}; shm::SnapshotPublication p;
  REQUIRE(shm::readNextSnapshot(r.h,1,out,sizeof(out),1,&p)==1);
  CHECK(p.index==2); CHECK(out[0]==2);
  CHECK(shm::readNextSnapshot(r.h,2,out,sizeof(out),1,&p)==0);
  shm::atomicStoreRelease(&entries[3].sequence,pendingSequence);
  // Eviction publishes index zero before arena overwrite. Even stale observed
  // bounds must not make that descriptor look like a valid retained payload.
  shm::invalidateJournalEntry(entries[2]);
  CHECK(shm::readNextSnapshot(r.h,1,out,sizeof(out),1,&p)==0);
  shm::atomicStoreRelease(&r.h->journalOldestIndex,3);
  REQUIRE(shm::readNextSnapshot(r.h,1,out,sizeof(out),1,&p)==1);
  CHECK(p.index==3); CHECK(out[0]==3);
}

TEST_CASE("journal byte eviction invalidates displaced entries before their arena is reused") {
  auto r=makeRegion(64,256,12);
  uint8_t first[8]{1,1,1,1,1,1,1,1},second[8]{2,2,2,2,2,2,2,2};
  REQUIRE(shm::publishSnapshot(r.h,first,sizeof(first),1));
  auto& displaced=shm::journalDescriptors(r.h)[1];
  const auto oldSequence=displaced.sequence;
  REQUIRE(shm::publishSnapshot(r.h,second,sizeof(second),2));
  CHECK(displaced.index==0);
  CHECK(displaced.sequence>oldSequence);
  CHECK((displaced.sequence&1u)==0);
  uint8_t out[64]{}; shm::SnapshotPublication p;
  REQUIRE(shm::readNextSnapshot(r.h,1,out,sizeof(out),1,&p)==sizeof(second));
  CHECK(p.index==2); CHECK(std::memcmp(out,second,sizeof(second))==0);
  const auto retainedSequence=shm::journalDescriptors(r.h)[2].sequence;
  shm::invalidateSnapshots(r.h);
  CHECK(shm::journalDescriptors(r.h)[2].index==0);
  CHECK(shm::journalDescriptors(r.h)[2].sequence>retainedSequence);
}

TEST_CASE("disabled journal falls back to latest without redelivering an accepted publication") {
  auto r=makeRegion(64,256);
  CHECK(r.h->journalCapacity==0);
  uint8_t data=1,out[64]{}; shm::SnapshotPublication p;
  REQUIRE(shm::publishSnapshot(r.h,&data,1,10,123));
  REQUIRE(shm::readNextSnapshot(r.h,0,out,sizeof(out),16,&p)==1);
  CHECK(p.timestampMicros==123);
  CHECK(shm::readNextSnapshot(r.h,1,out,sizeof(out),16,&p)==0);
  REQUIRE(shm::publishSnapshot(r.h,&data,1,11));
  REQUIRE(shm::publishSnapshot(r.h,&data,1,12));
  REQUIRE(shm::readNextSnapshot(r.h,1,out,sizeof(out),16,&p)==1);
  CHECK(p.index==3);
}
