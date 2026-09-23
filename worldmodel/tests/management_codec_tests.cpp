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
