// Command results (schema v6). Tier 0: drainCommandResults through
// WorldModel::ingest with hand-built SnapshotData — delivered once per
// seq in arrival order, the bridge's repeats dropped, an old seq that
// reappears after the window is not re-delivered within it, messages and
// ticks carried. Tier 1: the fixture path (SyntheticFort ->
// loadFixtureBytes).
#include <doctest.h>

#include <string>

#include "synthetic_builder.h"
#include "wm/world_model.h"

using namespace wm;
namespace m = df3d::mirror;

namespace {

SnapshotData base(Tick tick) {
  SnapshotData d;
  d.tick = tick;
  d.mapSize = TilePos{48, 48, 6};
  return d;
}

CommandResultObservation res(uint64_t seq, CommandStatus status, std::string_view msg = {}) {
  CommandResultObservation r;
  r.seq = seq;
  r.status = status;
  r.message = msg;
  return r;
}

}  // namespace

TEST_CASE("command results: delivered once per seq, in order, with message and tick") {
  WorldModel model;
  CHECK(model.drainCommandResults().empty());
  CHECK(model.commandResultsReceived() == 0);

  SnapshotData d = base(10);
  d.commandResults = {res(1, CommandStatus::Ok, "9 of 9 tiles"),
                      res(2, CommandStatus::Rejected, "rect outside map")};
  model.ingest(d, 0.0);
  // The bridge repeats both for a few frames and adds a third.
  SnapshotData d2 = base(11);
  d2.commandResults = {res(1, CommandStatus::Ok, "9 of 9 tiles"),
                       res(2, CommandStatus::Rejected, "rect outside map"),
                       res(3, CommandStatus::Unknown)};
  model.ingest(d2, 0.01);

  auto out = model.drainCommandResults();
  REQUIRE(out.size() == 3);
  CHECK(out[0].seq == 1);
  CHECK(out[0].status == CommandStatus::Ok);
  CHECK(out[0].message == "9 of 9 tiles");
  CHECK(out[0].tick == 10);
  CHECK(out[1].seq == 2);
  CHECK(out[1].status == CommandStatus::Rejected);
  CHECK(out[1].message == "rect outside map");
  CHECK(out[1].tick == 10);
  CHECK(out[2].seq == 3);
  CHECK(out[2].status == CommandStatus::Unknown);
  CHECK(out[2].message.empty());
  CHECK(out[2].tick == 11);
  CHECK(model.commandResultsReceived() == 3);

  // Drained: nothing pending; later repeats stay dropped.
  CHECK(model.drainCommandResults().empty());
  SnapshotData d3 = base(12);
  d3.commandResults = {res(2, CommandStatus::Rejected, "rect outside map"), res(3, CommandStatus::Unknown)};
  model.ingest(d3, 0.02);
  CHECK(model.drainCommandResults().empty());
  CHECK(model.commandResultsReceived() == 3);
}

TEST_CASE("command results: a snapshot without results leaves the drain empty; large seqs fine") {
  WorldModel model;
  model.ingest(base(1), 0.0);
  CHECK(model.drainCommandResults().empty());
  SnapshotData d = base(2);
  d.commandResults = {res(0xFFFFFFFFFFFFFFF0ull, CommandStatus::Ok)};
  model.ingest(d, 0.01);
  auto out = model.drainCommandResults();
  REQUIRE(out.size() == 1);
  CHECK(out[0].seq == 0xFFFFFFFFFFFFFFF0ull);
}

TEST_CASE("command results: repeat suppression window is bounded, oldest seqs forgotten") {
  WorldModel model;
  // 4096 distinct seqs fill the window; seq 1 then falls out once more
  // arrive, so a (pathological) re-send of seq 1 after the window is
  // delivered again — the window bounds memory, the bridge's repeat span
  // (8 frames) is far inside it.
  for (uint64_t s = 1; s <= 4096; ++s) {
    SnapshotData d = base(s);
    d.commandResults = {res(s, CommandStatus::Ok)};
    model.ingest(d, static_cast<double>(s));
  }
  CHECK(model.drainCommandResults().size() == 4096);
  SnapshotData again = base(5000);
  again.commandResults = {res(4096, CommandStatus::Ok), res(1, CommandStatus::Ok)};
  model.ingest(again, 5000.0);
  CHECK(model.drainCommandResults().empty());  // both still remembered
  SnapshotData more = base(5001);
  more.commandResults = {res(5001, CommandStatus::Ok)};  // evicts seq 1
  model.ingest(more, 5001.0);
  SnapshotData d = base(5002);
  d.commandResults = {res(1, CommandStatus::Ok), res(4096, CommandStatus::Ok)};
  model.ingest(d, 5002.0);
  auto out = model.drainCommandResults();
  REQUIRE(out.size() == 2);
  CHECK(out[0].seq == 5001);
  CHECK(out[1].seq == 1);
}

TEST_CASE("command results through the fixture path") {
  m::SyntheticFort fort(16, 16, 2);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.snapshot(100);
  fort.commandResult(7, m::CommandStatus::Ok, "3 of 9 tiles");
  fort.snapshot(101);
  fort.commandResult(8, m::CommandStatus::Rejected, "no such item");
  fort.snapshot(102);
  WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(loadFixtureBytes(model, fort.serialize(), err), err);
  auto out = model.drainCommandResults();
  REQUIRE(out.size() == 2);
  CHECK(out[0].seq == 7);
  CHECK(out[0].status == CommandStatus::Ok);
  CHECK(out[0].message == "3 of 9 tiles");
  CHECK(out[0].tick == 101);
  CHECK(out[1].seq == 8);
  CHECK(out[1].status == CommandStatus::Rejected);
  CHECK(out[1].tick == 102);
}

TEST_CASE("command vocabulary: rect equality and priority constants") {
  TileRect a{1, 2, 3, 4, 5}, b{1, 2, 3, 4, 5};
  CHECK(a == b);
  b.z = 6;
  CHECK(!(a == b));
  CHECK(kMinDigPriority == 1);
  CHECK(kMaxDigPriority == 7);
  CHECK(kDefaultDigPriority == 4);
}
