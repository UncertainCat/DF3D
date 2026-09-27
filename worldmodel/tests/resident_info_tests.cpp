#include "doctest.h"
#include "wm/resident_info.h"
#include "wm/creature_info.h"

namespace {
struct FakeResidentTransport final : wm::ResidentInfoTransport {
  wm::ManagementState value;
  std::string problem;
  std::vector<wm::ManagementRequest> requests;
  uint64_t sequence=0;
  FakeResidentTransport() { value.worldEpoch=42; }
  void poll() override {}
  uint64_t send(const wm::ManagementRequest& r) override {
    requests.push_back(r); return ++sequence;
  }
  const wm::ManagementState& state() const override { return value; }
  const std::string& error() const override { return problem; }
  void reply(wm::ManagementStatus status=wm::ManagementStatus::Ok) {
    value={}; value.worldEpoch=42; value.requestSeq=sequence;
    value.action=requests.back().action; value.status=status;
    value.citizen.detailListRevision=7;
  }
};
struct Fixture {
  FakeResidentTransport* fake;
  wm::ResidentInfoService service;
  Fixture():Fixture(std::make_unique<FakeResidentTransport>()){}
  explicit Fixture(std::unique_ptr<FakeResidentTransport> t):fake(t.get()),service(std::move(t)){}
  void start(wm::ResidentInfoDemand d=wm::ResidentInfoDemand::Residents) {
    service.setDemand(d); service.update(0,42);
    REQUIRE(fake->requests.back().action==wm::ManagementAction::Catalog);
    fake->reply(); service.update(1,42);
  }
  void citizen(int id, uint32_t cursor=0) {
    fake->reply(); wm::CitizenInfo row; row.id=id;
    fake->value.citizen.citizens.push_back(row); fake->value.citizen.nextCursor=cursor;
  }
  void finishDetails(uint64_t now) {
    REQUIRE(fake->requests.back().action==wm::ManagementAction::WorkDetailList);
    fake->reply(); service.update(now,42);
  }
};
}
TEST_CASE("resident collection publishes atomically and deduplicates pages") {
  Fixture f; f.start();
  f.citizen(2,10); f.service.update(2,42);
  CHECK_FALSE(f.service.snapshot());
  CHECK(f.fake->requests.back().citizen.cursor==10);
  f.citizen(2); wm::CitizenInfo row; row.id=11; f.fake->value.citizen.citizens.push_back(row);
  f.service.update(3,42);
  CHECK_FALSE(f.service.snapshot()); f.finishDetails(3);
  auto first=f.service.snapshot(); REQUIRE(first); CHECK(first->citizens.size()==2);
  CHECK(first->captureStartedMs==0); CHECK(first->captureCompletedMs==3);
  f.service.refresh(); f.service.update(4,42);
  CHECK(f.service.snapshot()==first); CHECK(f.service.status().loading);
  f.citizen(12); f.service.update(5,42); f.finishDetails(5);
  CHECK(f.service.snapshot()!=first); CHECK(first->citizens.size()==2);
}
TEST_CASE("resident collection ignores unrelated responses and times out") {
  Fixture f; f.start(); f.citizen(2);
  f.fake->value.action=wm::ManagementAction::WorkOrderList;
  f.service.update(2,42); CHECK_FALSE(f.service.snapshot()); CHECK(f.fake->requests.size()==2);
  f.fake->value.action=wm::ManagementAction::CitizenList; --f.fake->value.requestSeq;
  f.service.update(3,42); CHECK_FALSE(f.service.snapshot()); CHECK(f.fake->requests.size()==2);
  f.service.update(15002,42); CHECK_FALSE(f.service.status().loading);
  CHECK_FALSE(f.service.status().error.empty());
}
TEST_CASE("resident collection retains stale success after rejection or cursor failure") {
  Fixture f; f.start(); f.citizen(2); f.service.update(2,42); f.finishDetails(2);
  auto first=f.service.snapshot(); f.service.refresh(); f.service.update(3,42);
  f.citizen(3,10); f.service.update(4,42);
  f.citizen(4,10); f.service.update(5,42);
  CHECK(f.service.snapshot()==first); CHECK(f.service.status().stale);
  CHECK(f.service.status().error.find("cursor")!=std::string::npos);
  f.service.refresh(); f.service.update(6,42); f.fake->reply(); f.service.update(7,42);
  f.fake->reply(wm::ManagementStatus::Rejected); f.fake->value.message="unavailable";
  f.service.update(8,42); CHECK(f.service.snapshot()==first); CHECK(f.service.status().error=="unavailable");
}
TEST_CASE("resident demand cache survives navigation and discards in-flight old demand") {
  Fixture f; f.start(); f.citizen(2); f.service.update(2,42); f.finishDetails(2);
  auto residents=f.service.snapshot();
  f.service.refresh(); f.service.update(3,42);
  f.service.setDemand(wm::ResidentInfoDemand::WorkOrders); CHECK_FALSE(f.service.snapshot());
  f.citizen(3); f.service.update(4,42); CHECK_FALSE(f.service.snapshot());
  CHECK(f.fake->requests.back().action==wm::ManagementAction::Catalog);
  f.fake->reply(); f.service.update(5,42);
  CHECK(f.fake->requests.back().action==wm::ManagementAction::WorkOrderList);
  f.fake->reply(); wm::WorkOrderInfo order; order.id=8; f.fake->value.workOrder.orders.push_back(order);
  f.service.update(6,42); REQUIRE(f.service.snapshot()); CHECK(f.service.snapshot()->orders.size()==1);
  f.service.setDemand(wm::ResidentInfoDemand::Residents);
  CHECK(f.service.snapshot()==residents); CHECK(f.service.status().stale);
  f.service.setDemand(wm::ResidentInfoDemand::None);
  CHECK(f.service.cached(wm::ResidentInfoDemand::Residents)==residents);
  CHECK_FALSE(f.service.cached(static_cast<wm::ResidentInfoDemand>(99)));
  f.service.update(7,0);
  CHECK_FALSE(f.service.cached(wm::ResidentInfoDemand::Residents));
  f.service.setDemand(wm::ResidentInfoDemand::Residents); CHECK_FALSE(f.service.snapshot());
}
TEST_CASE("resident epoch change clears idle caches and refuses wrong-world replies") {
  Fixture f; f.start(); f.citizen(2); f.service.update(2,42); f.finishDetails(2);
  f.fake->value.worldEpoch=43; f.service.update(3,42); CHECK_FALSE(f.service.snapshot());
  f.service.setDemand(wm::ResidentInfoDemand::None); f.service.update(4,43);
  f.service.setDemand(wm::ResidentInfoDemand::Residents); CHECK_FALSE(f.service.snapshot());
}
TEST_CASE("work details collect roster and one revision of definitions together") {
  Fixture f; f.start(wm::ResidentInfoDemand::WorkDetails);
  CHECK(f.fake->requests.back().action==wm::ManagementAction::CitizenList);
  f.citizen(2); f.service.update(2,42); CHECK_FALSE(f.service.snapshot());
  CHECK(f.fake->requests.back().action==wm::ManagementAction::WorkDetailList);
  f.fake->reply(); wm::WorkDetailInfo detail; detail.index=0; detail.revision=7;
  f.fake->value.citizen.details.push_back(detail); f.fake->value.citizen.nextCursor=1;
  f.service.update(3,42); CHECK_FALSE(f.service.snapshot());
  f.fake->reply(); f.fake->value.citizen.detailListRevision=8; detail.index=1; detail.revision=8; f.fake->value.citizen.details.push_back(detail);
  f.service.update(4,42); CHECK_FALSE(f.service.snapshot()); CHECK_FALSE(f.service.status().error.empty());
  f.service.refresh(); f.service.update(5,42); f.fake->reply(); f.service.update(6,42);
  f.citizen(2); f.service.update(7,42); f.fake->reply();
  f.fake->value.citizen.details.push_back(detail); f.service.update(8,42);
  REQUIRE(f.service.snapshot()); CHECK(f.service.snapshot()->citizens.size()==1); CHECK(f.service.snapshot()->details.size()==1);
}
TEST_CASE("resident periodic refresh sleeps when no demand and sends once per update") {
  Fixture f; f.start(); f.citizen(2); f.service.update(2,42); f.finishDetails(2);
  f.service.update(5001,42); CHECK(f.fake->requests.size()==3);
  f.service.update(5002,42); CHECK(f.fake->requests.size()==4);
  f.citizen(3); f.service.update(5003,42); f.finishDetails(5003);
  f.service.setDemand(wm::ResidentInfoDemand::None); f.service.update(15000,42);
  CHECK(f.fake->requests.size()==5);
}
TEST_CASE("work details reject empty continuation after definitions shrink") {
  Fixture f; f.start(wm::ResidentInfoDemand::WorkDetails);
  f.citizen(2); f.service.update(2,42);
  f.fake->reply(); wm::WorkDetailInfo detail; detail.index=0; detail.revision=7;
  f.fake->value.citizen.details.push_back(detail); f.service.update(3,42);
  auto first=f.service.snapshot(); REQUIRE(first);
  f.service.refresh(); f.service.update(4,42);
  f.citizen(2); f.service.update(5,42);
  f.fake->reply(); f.fake->value.citizen.details.push_back(detail);
  f.fake->value.citizen.nextCursor=1; f.service.update(6,42);
  CHECK(f.service.snapshot()==first);
  f.fake->reply(); f.fake->value.citizen.detailListRevision=8; f.service.update(7,42);
  CHECK(f.service.snapshot()==first); CHECK(f.service.status().stale);
  CHECK_FALSE(f.service.status().loading);
  CHECK(f.service.status().error.find("changed during collection")!=std::string::npos);
}
TEST_CASE("resident badges join definitions by list revision, not row revision") {
  for(auto demand : {wm::ResidentInfoDemand::Residents,wm::ResidentInfoDemand::WorkDetails}) {
    Fixture f; f.start(demand); f.citizen(2);
    f.fake->value.citizen.citizens[0].assignedDetails.push_back({1,9,""});
    f.service.update(2,42); CHECK_FALSE(f.service.snapshot());
    f.fake->reply(); wm::WorkDetailInfo detail; detail.index=0; detail.revision=11; detail.name="Miners";
    f.fake->value.citizen.details.push_back(detail); f.fake->value.citizen.nextCursor=1;
    f.service.update(3,42); CHECK_FALSE(f.service.snapshot());
    CHECK(f.fake->requests.back().citizen.expectedListRevision==7);
    f.fake->reply(); detail.index=1; detail.revision=12; detail.name="Custom"; detail.assignedUnits={2};
    f.fake->value.citizen.details.push_back(detail); f.service.update(4,42);
    auto first=f.service.snapshot(); REQUIRE(first);
    CHECK(first->detailListRevision==7); CHECK(first->details.size()==2);
    CHECK(first->citizens[0].assignedDetails[0].name.empty()); CHECK(first->details[1].name=="Custom");
    f.service.refresh(); f.service.update(5,42); f.citizen(2); f.service.update(6,42);
    f.fake->reply(); f.fake->value.citizen.detailListRevision=8; f.service.update(7,42);
    CHECK(f.service.snapshot()==first); CHECK(f.service.status().stale);
    CHECK(f.service.status().error=="Work details changed during collection; refresh required");
  }
}
TEST_CASE("resident roster pages reject changed or absent definition revisions") {
  for(uint64_t revision : {uint64_t(0),uint64_t(8)}) {
    Fixture f; f.start(); f.citizen(2,1); f.service.update(2,42);
    f.citizen(3); f.fake->value.citizen.detailListRevision=revision; f.service.update(3,42);
    CHECK_FALSE(f.service.snapshot());
    CHECK(f.service.status().error=="Work details changed during collection; refresh required");
  }
}
TEST_CASE("creature facts publish by identity and retain stale per-ID snapshots") {
 auto transport=std::make_unique<FakeResidentTransport>();auto* fake=transport.get();
 wm::CreatureInfoService service(std::move(transport));service.demand(86);service.update(0,42);
 REQUIRE(fake->requests.back().action==wm::ManagementAction::Catalog);
 fake->reply();service.update(1,42);REQUIRE(fake->requests.back().action==wm::ManagementAction::CreatureInspect);
 CHECK(fake->requests.back().creatureUnitId==86);
 fake->reply();fake->value.creature.unitId=86;fake->value.creature.name="Citizen";service.update(2,42);
 auto first=service.snapshot(86);REQUIRE(first);CHECK(first->detail.name=="Citizen");
 service.update(5002,42);fake->reply(wm::ManagementStatus::Rejected);fake->value.message="Unavailable";service.update(5003,42);
 CHECK(service.snapshot(86)==first);CHECK(service.status(86).stale);CHECK(service.status(86).error=="Unavailable");
 service.demand(310);service.update(5004,42);fake->reply();service.update(5005,42);
 fake->reply();fake->value.creature.unitId=310;service.update(5006,42);
 REQUIRE(service.snapshot(310));CHECK(service.snapshot(86)==first);
 service.demand(-1);service.update(5007,0);CHECK_FALSE(service.snapshot(86));CHECK_FALSE(service.snapshot(310));
}
TEST_CASE("creature service rejects wrong identity and ignores obsolete replies") {
 auto transport=std::make_unique<FakeResidentTransport>();auto* fake=transport.get();
 wm::CreatureInfoService service(std::move(transport));service.demand(86);service.update(0,42);
 fake->reply();service.update(1,42);fake->reply();fake->value.creature.unitId=87;
 service.update(2,42);CHECK_FALSE(service.snapshot(86));CHECK_FALSE(service.status(86).error.empty());
 service.demand(310);service.update(3,42);fake->reply();service.update(4,42);
 service.demand(86);fake->reply();fake->value.creature.unitId=310;service.update(5,42);
 CHECK_FALSE(service.snapshot(310));CHECK(fake->requests.back().action==wm::ManagementAction::Catalog);
 fake->reply();--fake->value.requestSeq;service.update(6,42);CHECK(fake->requests.size()==5);
 service.update(15006,42);CHECK_FALSE(service.status(86).loading);CHECK_FALSE(service.status(86).error.empty());
}
TEST_CASE("creature service bounds failed identity state and clears on changed world") {
 auto transport=std::make_unique<FakeResidentTransport>();auto* fake=transport.get();
 wm::CreatureInfoService service(std::move(transport));
 for(int i=0;i<80;++i){service.demand(i);service.update(i*2,42);fake->reply(wm::ManagementStatus::Rejected);fake->value.message="Unavailable";service.update(i*2+1,42);}
 CHECK(service.status(0).error.empty());CHECK(service.status(79).error=="Unavailable");
 service.update(200,0);CHECK(service.status(79).error.empty());CHECK(service.status(79).worldEpoch==0);
}
