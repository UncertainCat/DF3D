#include <doctest.h>

#include <algorithm>

#include "management_codecs.h"

namespace codec = wm::detail::management;
namespace wire = df3d::mirror;

TEST_CASE("management encoding isolates domain payloads while preserving envelope identity") {
  wm::ManagementRequest request;
  request.area.id = 0;
  request.area.ownerId = -2;
  request.workOrder.id = 37;
  request.workOrder.expectedRevision = (uint64_t(1) << 54) + 1;
  request.workOrder.query = "steel";
  for (auto action : {wm::ManagementAction::Catalog, wm::ManagementAction::AreaInspect,
                      wm::ManagementAction::WorkOrderInspect}) {
    request.action = action;
    flatbuffers::FlatBufferBuilder builder;
    codec::encodeRequest(builder, request, 123, (uint64_t(1) << 55) + 7, 456);
    flatbuffers::Verifier verifier(builder.GetBufferPointer(), builder.GetSize());
    REQUIRE(verifier.VerifyBuffer<wire::ConstructionRequest>(nullptr));
    const auto* encoded =
        flatbuffers::GetRoot<wire::ConstructionRequest>(builder.GetBufferPointer());
    CHECK(encoded->client_id() == 123);
    CHECK(encoded->seq() == (uint64_t(1) << 55) + 7);
    CHECK(encoded->world_epoch() == 456);
    CHECK(bool(encoded->area()) == (action == wm::ManagementAction::AreaInspect));
    CHECK(bool(encoded->work_order()) == (action == wm::ManagementAction::WorkOrderInspect));
    CHECK_FALSE(encoded->production());
    CHECK_FALSE(encoded->citizen());
    if (encoded->area()) {
      CHECK(encoded->area()->id() == 0);
      CHECK(encoded->area()->owner_id() == -2);
      CHECK(encoded->area()->active() == -1);
    }
    if (encoded->work_order()) {
      CHECK(encoded->work_order()->expected_revision() == request.workOrder.expectedRevision);
      CHECK(encoded->work_order()->query()->str() == "steel");
      CHECK(encoded->work_order()->remaining() == -1);
    }
  }
}

TEST_CASE("management domain decoding owns nested data independently of the wire buffer") {
  flatbuffers::FlatBufferBuilder builder;
  auto fact = wire::CreateCreatureFact(builder, builder.CreateString("age"),
                                       builder.CreateString("Twenty years"), 20, true);
  auto record = wire::CreateCreatureRecord(builder, 17, -1, builder.CreateString("Identity"),
                                           builder.CreateVector(std::vector{fact}));
  auto section = wire::CreateCreatureSection(builder, wire::CreatureSectionKind::Identity, true,
                                             false, {}, builder.CreateVector(std::vector{record}));
  const auto sections = builder.CreateVector(std::vector{section});
  const auto name = builder.CreateString("Cerol");
  wire::CreatureStateBuilder creature(builder);
  creature.add_unit_id(42);
  creature.add_name(name);
  creature.add_sections(sections);
  builder.Finish(creature.Finish());
  auto decoded =
      codec::decodeCreature(flatbuffers::GetRoot<wire::CreatureState>(builder.GetBufferPointer()));
  // The collector reuses this storage as soon as decode returns.
  std::fill_n(builder.GetBufferPointer(), builder.GetSize(), uint8_t(0));
  CHECK(decoded.unitId == 42);
  CHECK(decoded.name == "Cerol");
  CHECK(decoded.species.empty());
  REQUIRE(decoded.sections.size() == 1);
  REQUIRE(decoded.sections[0].records.size() == 1);
  const auto& row = decoded.sections[0].records[0];
  CHECK(row.relatedId == -1);
  REQUIRE(row.facts.size() == 1);
  CHECK(row.facts[0].text == "Twenty years");
  CHECK(row.facts[0].hasNumber);
  CHECK(row.facts[0].number == 20);
  decoded = codec::decodeCreature(nullptr);
  CHECK(decoded.unitId == -1);
  CHECK(decoded.sections.empty());
}

namespace {
namespace mm = df3d::mirror;
struct EncodedRequest {
  flatbuffers::FlatBufferBuilder b;
  bool invalid(const wm::ManagementRequest& r) {
    b.Clear();
    codec::encodeRequest(b, r, 1, 1, 7);
    return mm::validateConstructionRequest(*get()).has_value();
  }
  const mm::ConstructionRequest* get() const {
    return flatbuffers::GetRoot<mm::ConstructionRequest>(b.GetBufferPointer());
  }
};
}
TEST_CASE("trade exchange wire guards native receipts and whole-good selections") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::TradeExchangeSelect;r.trade.depotId=17;r.trade.itemId=55;r.trade.side=1;r.trade.selected=1;
  CHECK(encoded.invalid(r));
  r.trade.receipt=123;REQUIRE_FALSE(encoded.invalid(r));auto* q=encoded.get();REQUIRE(q->trade());CHECK(q->trade()->receipt()==123);CHECK(q->trade()->item_id()==55);CHECK(q->trade()->side()==1);CHECK(q->trade()->selected()==1);
  r.action=wm::ManagementAction::TradeExchangeSubmit;CHECK(encoded.invalid(r));
  r.trade.itemId=-1;r.trade.selected=-1;REQUIRE_FALSE(encoded.invalid(r));q=encoded.get();CHECK(q->trade()->receipt()==123);
  r.action=wm::ManagementAction::TradeExchangeClose;r.trade.receipt=0;REQUIRE_FALSE(encoded.invalid(r));q=encoded.get();CHECK(q->trade()->receipt()==0);
}
TEST_CASE("Stocks requests keep membership receipts separate from trade") {
  EncodedRequest encoded;
  wm::ManagementRequest r; r.action=wm::ManagementAction::StocksList; r.stocks.category=39;
  CHECK(encoded.invalid(r));
  r.stocks.receipt=12; r.stocks.cursor=512; r.stocks.query="iron";
  REQUIRE_FALSE(encoded.invalid(r)); auto* q=encoded.get();
  REQUIRE(q->stocks()); CHECK(q->trade()==nullptr); CHECK(q->stocks()->receipt()==12);
  CHECK(q->stocks()->category()==39); CHECK(q->stocks()->cursor()==512); CHECK(q->stocks()->query()->str()=="iron");
  r.action=wm::ManagementAction::StocksInspect; CHECK(encoded.invalid(r));
  r.stocks.itemId=0; REQUIRE_FALSE(encoded.invalid(r)); CHECK(encoded.get()->stocks()->item_id()==0);
}
TEST_CASE("Appointments require role identity and consumed-context receipts") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::AppointmentsAssign;r.appointments.unitId=5173;
  CHECK(encoded.invalid(r));
  r.appointments.entityId=483;r.appointments.positionId=10;r.appointments.assignmentId=6;r.appointments.receipt=25;
  REQUIRE_FALSE(encoded.invalid(r)); auto* q=encoded.get(); REQUIRE(q->appointments()); CHECK(q->stocks()==nullptr);CHECK(q->appointments()->receipt()==25);CHECK(q->appointments()->unit_id()==5173);CHECK(q->appointments()->assignment_id()==6);
  r.appointments.unitId=-1; REQUIRE_FALSE(encoded.invalid(r));CHECK(encoded.get()->appointments()->unit_id()==-1);
}
TEST_CASE("Kitchen requests carry exact ingredient tuples and reject malformed edits") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::KitchenSetPermission;
  r.kitchen.itemType=1;r.kitchen.matType=419;r.kitchen.matIndex=20;r.kitchen.permission=2;r.kitchen.allowed=0;
  CHECK(encoded.invalid(r));r.kitchen.receipt=7;r.kitchen.query="berries";
  REQUIRE_FALSE(encoded.invalid(r));auto* q=encoded.get();REQUIRE(q->kitchen());CHECK(q->appointments()==nullptr);
  CHECK(q->kitchen()->item_type()==1);CHECK(q->kitchen()->item_subtype()==-1);CHECK(q->kitchen()->mat_type()==419);CHECK(q->kitchen()->mat_index()==20);CHECK(q->kitchen()->permission()==2);CHECK(q->kitchen()->allowed()==0);CHECK(q->kitchen()->receipt()==7);CHECK(q->kitchen()->query()->str()=="berries");
  for(auto flag:{0,3}){r.kitchen.permission=uint8_t(flag);CHECK(encoded.invalid(r));}
  r.kitchen.permission=1;r.kitchen.allowed=-1;CHECK(encoded.invalid(r));
  r.kitchen.allowed=1;r.kitchen.matIndex=-2;CHECK(encoded.invalid(r));
  r.kitchen.matIndex=20;r.action=wm::ManagementAction::KitchenList;CHECK(encoded.invalid(r));
  r.kitchen={};r.kitchen.receipt=7;r.kitchen.cursor=4097;CHECK(encoded.invalid(r));
  r.kitchen.cursor=0;r.kitchen.query=std::string(129,'x');CHECK(encoded.invalid(r));
}
TEST_CASE("selection transport request payloads preserve ownership") {
  EncodedRequest encoded;
  wm::ManagementRequest request;request.action=wm::ManagementAction::Selection;
  request.selection.x=88;request.selection.y=71;request.selection.z=143;
  REQUIRE_FALSE(encoded.invalid(request));
  const auto* command=encoded.get();REQUIRE(command->selection());
  CHECK(command->selection()->tile()->x()==88);CHECK(command->selection()->tile()->z()==143);
  CHECK(command->selection()->receipt()==0);
  request.selection.receipt=77;REQUIRE_FALSE(encoded.invalid(request));
  CHECK(encoded.get()->selection()->receipt()==77); // replacement click carries ownership
}
