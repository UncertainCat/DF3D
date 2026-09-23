// Command path (schema v6). Tier 0: every command builder
// round-trips through parseCommand and validateCommand; the validators
// reject inverted / negative / out-of-map rectangles, bad enums, bad
// priorities and zero ids; command results validate in snapshots (status,
// unique seq); the tile flag bits.
#include <doctest.h>

#include <string>

#include "command_util.h"
#include "management_util.h"
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "validate.h"

using namespace df3d::mirror;

namespace {

const Command* parse(const std::vector<uint8_t>& bytes) {
  const Command* c = parseCommand(bytes.data(), bytes.size());
  REQUIRE(c != nullptr);
  return c;
}

const TilePos kMap(48, 48, 10);

}  // namespace

TEST_CASE("every command builder round-trips and validates") {
  const TileRect rect(3, 4, 5, 6, 2);
  // FlatBuffer views borrow their bytes; keep each buffer alive through its checks.
  {
    const auto bytes = buildSetPauseCommand(1, true);
    const Command* c = parse(bytes);
    CHECK(c->seq() == 1);
    CHECK(c->payload_type() == CommandPayload::SetPause);
    CHECK(c->payload_as_SetPause()->paused());
    CHECK(!validateCommand(*c, &kMap));
  }
  {
    const auto bytes = buildDesignateDigCommand(2, rect, DigKind::Channel, 6);
    const Command* c = parse(bytes);
    REQUIRE(c->payload_type() == CommandPayload::DesignateDig);
    const DesignateDig* d = c->payload_as_DesignateDig();
    CHECK(d->rect()->x1() == 3);
    CHECK(d->rect()->y2() == 6);
    CHECK(d->rect()->z() == 2);
    CHECK(d->kind() == DigKind::Channel);
    CHECK(d->priority() == 6);
    CHECK(!validateCommand(*c, &kMap));
    CHECK(!validateCommand(*c, nullptr));
  }
  {
    const auto bytes = buildDesignateDigCommand(3, rect, DigKind::Dig);
    const Command* c = parse(bytes);
    CHECK(c->payload_as_DesignateDig()->priority() == kDefaultDigPriority);
  }
  {
    const auto bytes = buildDesignateSmoothCommand(4, rect, SmoothKind::Engrave);
    const Command* c = parse(bytes);
    REQUIRE(c->payload_type() == CommandPayload::DesignateSmooth);
    CHECK(c->payload_as_DesignateSmooth()->kind() == SmoothKind::Engrave);
    CHECK(!validateCommand(*c, &kMap));
  }
  {
    const auto bytes = buildDesignateChopCommand(5, rect, false);
    const Command* c = parse(bytes);
    REQUIRE(c->payload_type() == CommandPayload::DesignateChop);
    CHECK(!c->payload_as_DesignateChop()->enable());
    CHECK(!validateCommand(*c, &kMap));
  }
  {
    const auto bytes = buildDesignateGatherCommand(6, rect, true);
    const Command* c = parse(bytes);
    REQUIRE(c->payload_type() == CommandPayload::DesignateGather);
    CHECK(c->payload_as_DesignateGather()->enable());
    CHECK(!validateCommand(*c, &kMap));
  }
  {
    const auto bytes = buildSetItemFlagsCommand(7, 1234, OptionalBool::Set,
                                                      OptionalBool::Unchanged, OptionalBool::Clear);
    const Command* c = parse(bytes);
    REQUIRE(c->payload_type() == CommandPayload::SetItemFlags);
    const SetItemFlags* f = c->payload_as_SetItemFlags();
    CHECK(f->item() == 1234);
    CHECK(f->forbidden() == OptionalBool::Set);
    CHECK(f->dump() == OptionalBool::Unchanged);
    CHECK(f->melt() == OptionalBool::Clear);
    CHECK(!validateCommand(*c, &kMap));
  }
  {
    const auto bytes = buildSetBuildingFlagsCommand(8, 77, OptionalBool::Clear);
    const Command* c = parse(bytes);
    REQUIRE(c->payload_type() == CommandPayload::SetBuildingFlags);
    CHECK(c->payload_as_SetBuildingFlags()->building() == 77);
    CHECK(c->payload_as_SetBuildingFlags()->forbidden() == OptionalBool::Clear);
    CHECK(!validateCommand(*c, &kMap));
  }
}

TEST_CASE("validateCommand rejects malformed rectangles") {
  auto err = validateCommand(*parse(buildDesignateDigCommand(1, TileRect(5, 4, 3, 6, 2), DigKind::Dig)), &kMap);
  REQUIRE(err);
  CHECK(err->find("inverted") != std::string::npos);
  err = validateCommand(*parse(buildDesignateSmoothCommand(2, TileRect(3, -1, 5, 6, 2), SmoothKind::Smooth)), nullptr);
  REQUIRE(err);
  CHECK(err->find("negative") != std::string::npos);
  err = validateCommand(*parse(buildDesignateChopCommand(3, TileRect(3, 4, 48, 6, 2), true)), &kMap);
  REQUIRE(err);
  CHECK(err->find("outside map") != std::string::npos);
  // Without a map size the same rectangle is accepted (the bridge has the map).
  CHECK(!validateCommand(*parse(buildDesignateChopCommand(3, TileRect(3, 4, 48, 6, 2), true)), nullptr));
  err = validateCommand(*parse(buildDesignateGatherCommand(4, TileRect(3, 4, 5, 6, 10), true)), &kMap);
  REQUIRE(err);
  CHECK(err->find("outside map") != std::string::npos);
  CHECK(err->find("command seq 4") != std::string::npos);
}

TEST_CASE("validateCommand rejects bad enums, priorities and zero ids") {
  const TileRect rect(3, 4, 5, 6, 2);
  auto err = validateCommand(*parse(buildDesignateDigCommand(1, rect, static_cast<DigKind>(255))), &kMap);
  REQUIRE(err);
  CHECK(err->find("dig kind") != std::string::npos);
  err = validateCommand(*parse(buildDesignateDigCommand(2, rect, DigKind::Dig, 0)), &kMap);
  REQUIRE(err);
  CHECK(err->find("priority 0") != std::string::npos);
  err = validateCommand(*parse(buildDesignateDigCommand(3, rect, DigKind::Dig, 8)), &kMap);
  REQUIRE(err);
  CHECK(err->find("priority 8") != std::string::npos);
  err = validateCommand(*parse(buildDesignateSmoothCommand(4, rect, static_cast<SmoothKind>(255))), &kMap);
  REQUIRE(err);
  CHECK(err->find("smooth kind") != std::string::npos);
  err = validateCommand(*parse(buildSetItemFlagsCommand(5, 0, OptionalBool::Set, OptionalBool::Unchanged,
                                                        OptionalBool::Unchanged)), &kMap);
  REQUIRE(err);
  CHECK(err->find("item id 0") != std::string::npos);
  err = validateCommand(*parse(buildSetItemFlagsCommand(6, 9, static_cast<OptionalBool>(3),
                                                        OptionalBool::Unchanged, OptionalBool::Unchanged)), &kMap);
  REQUIRE(err);
  CHECK(err->find("forbidden") != std::string::npos);
  err = validateCommand(*parse(buildSetBuildingFlagsCommand(7, 0, OptionalBool::Set)), &kMap);
  REQUIRE(err);
  CHECK(err->find("building id 0") != std::string::npos);
  err = validateCommand(*parse(buildSetBuildingFlagsCommand(8, 5, static_cast<OptionalBool>(7))), &kMap);
  REQUIRE(err);
  CHECK(err->find("forbidden") != std::string::npos);
}

TEST_CASE("validateCommand rejects an empty / unknown payload") {
  flatbuffers::FlatBufferBuilder fbb;
  fbb.Finish(CreateCommand(fbb, 9, CommandPayload::NONE, 0));
  std::vector<uint8_t> bytes(fbb.GetBufferPointer(), fbb.GetBufferPointer() + fbb.GetSize());
  CHECK(parseCommand(bytes.data(),bytes.size())==nullptr);
  auto err = validateCommand(*flatbuffers::GetRoot<Command>(bytes.data()), &kMap);
  REQUIRE(err);
  CHECK(err->find("missing command payload") != std::string::npos);
}

TEST_CASE("command results validate in snapshots: status and unique seq") {
  SyntheticFort fort(8, 8, 2);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.snapshot(1);
  fort.commandResult(3, CommandStatus::Ok, "9 of 9 tiles");
  fort.commandResult(4, CommandStatus::Rejected, "rect outside map");
  fort.snapshot(2);
  fort.snapshot(3);  // results are not repeated by the builder
  FixtureStream fs;
  std::string err;
  REQUIRE_MESSAGE(parseFixture(fort.serialize(), fs, err), err);
  CHECK(!validateStream(fs));
  REQUIRE(fs.snapshots.size() == 3);
  CHECK(fs.snapshots[0]->command_results() == nullptr);
  REQUIRE(fs.snapshots[1]->command_results() != nullptr);
  REQUIRE(fs.snapshots[1]->command_results()->size() == 2);
  CHECK(fs.snapshots[1]->command_results()->Get(0)->seq() == 3);
  CHECK(fs.snapshots[1]->command_results()->Get(0)->status() == CommandStatus::Ok);
  CHECK(std::string(fs.snapshots[1]->command_results()->Get(0)->message()->c_str()) == "9 of 9 tiles");
  CHECK(fs.snapshots[1]->command_results()->Get(1)->status() == CommandStatus::Rejected);
  CHECK(fs.snapshots[2]->command_results() == nullptr);

  SyntheticFort dup(8, 8, 2);
  dup.commandResult(5, CommandStatus::Ok);
  dup.commandResult(5, CommandStatus::Rejected);
  dup.snapshot(1);
  REQUIRE(parseFixture(dup.serialize(), fs, err));
  auto verr = validateStream(fs);
  REQUIRE(verr);
  CHECK(verr->find("duplicate seq") != std::string::npos);

  SyntheticFort bad(8, 8, 2);
  bad.commandResult(6, static_cast<CommandStatus>(9));
  bad.snapshot(1);
  REQUIRE(parseFixture(bad.serialize(), fs, err));
  verr = validateStream(fs);
  REQUIRE(verr);
  CHECK(verr->find("invalid status") != std::string::npos);
}

TEST_CASE("v6 tile flag bits validate: pending smooth / engrave designations") {
  SyntheticFort fort(16, 16, 1);
  fort.setTile(2, 2, 0, TileState(TileShape::Floor, MaterialKind::Stone, fort.material("INORGANIC:GRANITE"),
                                  0, LiquidKind::None, TileFlags::SmoothDesignated, df3d::mirror::DesignationKind::None));
  fort.setTile(3, 2, 0, TileState(TileShape::Wall, MaterialKind::Stone, fort.material("INORGANIC:GRANITE"),
                                  0, LiquidKind::None, TileFlags::Smooth | TileFlags::EngraveDesignated, df3d::mirror::DesignationKind::None));
  fort.snapshot(1);
  FixtureStream fs;
  std::string err;
  REQUIRE(parseFixture(fort.serialize(), fs, err));
  CHECK(!validateStream(fs));
  CHECK(static_cast<uint8_t>(TileFlags::SmoothDesignated) == 0x20);
  CHECK(static_cast<uint8_t>(TileFlags::EngraveDesignated) == 0x40);
}

TEST_CASE("designation options are complete per-command values") {
  const TileRect r(3,4,5,6,2);
  auto a=buildDesignateDigCommand(500,r,DigKind::Dig,1,true,3);
  auto b=buildDesignateDigCommand(501,r,DigKind::Dig);
  const auto *first=parse(a)->payload_as_DesignateDig(), *second=parse(b)->payload_as_DesignateDig();
  CHECK(first->marker()); CHECK(first->mining_mode()==3); CHECK(first->priority()==1);
  CHECK_FALSE(second->marker()); CHECK(second->mining_mode()==0); CHECK(second->priority()==4);
  CHECK_FALSE(validateCommand(*parse(a), &kMap));
  for(auto bytes:{buildDesignateSmoothCommand(502,r,SmoothKind::Fortify,7,true),
                  buildDesignateChopCommand(503,r,true,2,true),buildDesignateGatherCommand(504,r,true,3,true)})
    CHECK_FALSE(validateCommand(*parse(bytes), &kMap));
  auto track=buildDesignateSmoothCommand(505,r,SmoothKind::Track,5,true,true,false);
  CHECK(parse(track)->payload_as_DesignateSmooth()->from_east());
  CHECK_FALSE(parse(track)->payload_as_DesignateSmooth()->from_south());
  auto stairs=buildDesignateDigCommand(506,r,DigKind::StairsSpan,4,false,0,5);
  CHECK_FALSE(validateCommand(*parse(stairs), &kMap));
  CHECK(parse(stairs)->payload_as_DesignateDig()->max_z()==5);
  for(auto bytes:{buildDesignateDigCommand(507,r,DigKind::StairsSpan,4,false,0,1),
                  buildDesignateDigCommand(508,r,DigKind::StairsSpan,4,false,0,10),
                  buildDesignateDigCommand(509,r,DigKind::Channel,4,false,1),
                  buildDesignateDigCommand(510,r,DigKind::Dig,4,false,4),
                  buildDesignateSmoothCommand(511,r,SmoothKind::Smooth,0),
                  buildDesignateChopCommand(512,r,true,8),buildDesignateGatherCommand(513,r,true,0)})
    CHECK(validateCommand(*parse(bytes), &kMap).has_value());
}

TEST_CASE("designation volumes preserve bounds and reject invalid spans before execution") {
  const TileRect r(3,4,5,6,2);
  auto dig=buildDesignateDigCommand(600,r,DigKind::Dig,4,true,0,5);
  auto smooth=buildDesignateSmoothCommand(601,r,SmoothKind::Smooth,4,true,false,false,5);
  auto chop=buildDesignateChopCommand(602,r,true,4,true,5);
  auto gather=buildDesignateGatherCommand(603,r,true,4,true,5);
  CHECK(parse(dig)->payload_as_DesignateDig()->max_z()==5);
  CHECK(parse(smooth)->payload_as_DesignateSmooth()->max_z()==5);
  CHECK(parse(chop)->payload_as_DesignateChop()->max_z()==5);
  CHECK(parse(gather)->payload_as_DesignateGather()->max_z()==5);
  for(const auto& bytes:{dig,smooth,chop,gather}) CHECK_FALSE(validateCommand(*parse(bytes),&kMap));
  for(auto bytes:{buildDesignateDigCommand(604,r,DigKind::Dig,4,false,0,1),
                  buildDesignateSmoothCommand(605,r,SmoothKind::Smooth,4,false,false,false,10),
                  buildDesignateChopCommand(606,r,true,4,false,-2),
                  buildDesignateGatherCommand(607,r,true,4,false,1),
                  buildDesignateSmoothCommand(608,r,SmoothKind::Track,4,false,false,false,5)})
    CHECK(validateCommand(*parse(bytes),&kMap).has_value());
}

TEST_CASE("track destination elevation preserves direction independently of volume bounds") {
  const TileRect r(3,4,5,6,2);
  for(int endZ:{0,2,5}) {
    auto bytes=buildDesignateSmoothCommand(700,r,SmoothKind::Track,4,false,true,false,-1,endZ);
    CHECK(parse(bytes)->payload_as_DesignateSmooth()->track_end_z()==endZ);
    CHECK_FALSE(validateCommand(*parse(bytes),&kMap));
  }
  for(auto bytes:{buildDesignateSmoothCommand(701,r,SmoothKind::Track,4,false,false,false,-1,-2),
                  buildDesignateSmoothCommand(702,r,SmoothKind::Track,4,false,false,false,-1,10),
                  buildDesignateSmoothCommand(703,r,SmoothKind::Smooth,4,false,false,false,-1,3)})
    CHECK(validateCommand(*parse(bytes),&kMap).has_value());
}

TEST_CASE("all absent command union payloads reject without dereference") {
  for(int kind=int(CommandPayload::MIN);kind<=int(CommandPayload::MAX);++kind) {
    flatbuffers::FlatBufferBuilder b;
    b.Finish(CreateCommand(b,1,CommandPayload(kind),0,77));
    CHECK(parseCommand(b.GetBufferPointer(),b.GetSize())==nullptr);
    CHECK(validateCommand(*flatbuffers::GetRoot<Command>(b.GetBufferPointer()),&kMap).has_value());
  }
}
TEST_CASE("ordinary command epochs are explicit and fail closed") {
  auto old=buildSetPauseCommand(1,true,123);
  CHECK(commandEpochMatches(*parse(old),123));
  CHECK_FALSE(commandEpochMatches(*parse(old),124));
  CHECK_FALSE(commandEpochMatches(*parse(old),0));
  CHECK_FALSE(commandEpochMatches(*parse(buildSetPauseCommand(2,true)),123));
}
TEST_CASE("atomic designation volume is bounded before mutation") {
  const TilePos huge(1000000,1000000,1000);
  CHECK_FALSE(validateCommand(*parse(buildDesignateDigCommand(1,TileRect(1,1,256,256,0),DigKind::Dig)),&huge));
  CHECK(validateCommand(*parse(buildDesignateDigCommand(2,TileRect(1,1,256,256,0),DigKind::Dig,4,false,0,1)),&huge).has_value());
  CHECK(validateCommand(*parse(buildDesignateSmoothCommand(3,TileRect(1,1,257,256,0),SmoothKind::Smooth)),&huge).has_value());
  CHECK(validateCommand(*parse(buildDesignateGatherCommand(4,TileRect(0,0,INT32_MAX,INT32_MAX,0),true)),nullptr).has_value());
}

TEST_CASE("request admission shares nonzero world identity with explicit catalog discovery") {
  CHECK(requestEpochMatches(7,7));
  CHECK_FALSE(requestEpochMatches(0,0));
  CHECK_FALSE(requestEpochMatches(7,0));
  CHECK_FALSE(requestEpochMatches(0,7));
  CHECK_FALSE(requestEpochMatches(6,7));
  CHECK(sessionEpochMatches(7,7));
  CHECK_FALSE(sessionEpochMatches(0,0));
  CHECK_FALSE(sessionEpochMatches(6,7));
  for (const auto action : {ManagementAction::Catalog,ManagementAction::Inspect}) {
    CHECK_FALSE(managementRequestAdmitted(action,7,0,false));
    CHECK_FALSE(managementRequestAdmitted(action,7,7,true));
    CHECK(managementRequestAdmitted(action,7,7,false));
  }
  CHECK(managementRequestAdmitted(ManagementAction::Catalog,0,7,false));
  CHECK(managementRequestAdmitted(ManagementAction::Catalog,6,7,false));
  CHECK_FALSE(managementRequestAdmitted(ManagementAction::Inspect,0,7,false));
  CHECK_FALSE(managementRequestAdmitted(ManagementAction::Inspect,6,7,false));
}

TEST_CASE("management runtime rejects retired adapters but retains semantic actions") {
  for (const auto action : {ManagementAction::Catalog,ManagementAction::Preview,
       ManagementAction::Place,ManagementAction::Inspect,ManagementAction::Remove,
       ManagementAction::ReportInspect,ManagementAction::TradeList,ManagementAction::TradeBring,
       ManagementAction::CreatureInspect}) CHECK(runtimeManagementAction(action));
  for (int value=int(ManagementAction::TradeExchangeOpen);value<=int(ManagementAction::Selection);++value)
    CHECK_FALSE(runtimeManagementAction(static_cast<ManagementAction>(value)));
  CHECK_FALSE(runtimeManagementAction(static_cast<ManagementAction>(255)));
}
