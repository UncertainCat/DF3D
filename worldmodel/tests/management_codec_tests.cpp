#include <doctest.h>

#include <algorithm>
#include <iostream>

#include "management_codecs.h"
#include "management_util.h"

namespace codec = wm::detail::management;
namespace wire = df3d::mirror;

TEST_CASE("work detail request boundaries and absent optional edits") {
  auto check=[](const wm::ManagementRequest& r,const std::string& expected) {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,1,7);
    auto error=wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer()));
    CHECK(error.value_or("")==expected);
  };
  wm::ManagementRequest r;r.action=wm::ManagementAction::WorkDetailCreate;r.citizen.expectedRevision=INT64_MAX;
  check(r,"");r.citizen.name="";r.citizen.labors={};check(r,"");
  r.citizen.unitId=-2;check(r,"invalid citizen request");r.citizen.unitId=-1;
  r.citizen.detailIndex=-2;check(r,"invalid citizen request");r.citizen.detailIndex=-1;
  r.citizen.member=0;check(r,"unexpected citizen edit fields");r.citizen.member=-1;
  r.citizen.mode=0;check(r,"unexpected citizen edit fields");r.citizen.mode=-1;
  r.citizen.edit=1;check(r,"unexpected work detail edit");r.citizen.edit=0;
  r.citizen.onlyAssigned=0;check(r,"unexpected citizen work scope");r.citizen.onlyAssigned=-1;
  r.citizen.expectedRevision=uint64_t(INT64_MAX)+1;check(r,"invalid citizen request");r.citizen.expectedRevision=INT64_MAX;
  r.citizen.name="x";check(r,"unexpected work detail name");r.citizen.name="";
  r.citizen.unitId=0;check(r,"unexpected new work detail identity");r.citizen.unitId=-1;
  r.citizen.expectedRevision=0;check(r,"citizen receipt required");r.citizen.expectedRevision=1;
  for(auto action:{wm::ManagementAction::WorkDetailCreate,wm::ManagementAction::WorkDetailDelete,wm::ManagementAction::WorkDetailEdit,wm::ManagementAction::CitizenWorkScope}) {
    auto search=r;search.action=action;
    if(action==wm::ManagementAction::WorkDetailDelete || action==wm::ManagementAction::WorkDetailEdit)search.citizen.detailIndex=0;
    if(action==wm::ManagementAction::WorkDetailEdit)search.citizen.edit=1;
    if(action==wm::ManagementAction::CitizenWorkScope){search.citizen.unitId=0;search.citizen.onlyAssigned=0;}
    check(search,"");search.citizen.cursor=1;check(search,"unexpected citizen search");search.citizen.cursor=0;
    search.citizen.query="x";check(search,"unexpected citizen search");search.citizen.query="";check(search,"");
    search.citizen.expectedRevision=0;check(search,"citizen receipt required");
  }
  for(auto action:{wm::ManagementAction::WorkDetailDelete,wm::ManagementAction::WorkDetailEdit}) {
    r.action=action;r.citizen.edit=action==wm::ManagementAction::WorkDetailEdit?1:0;
    check(r,"work detail index required");r.citizen.detailIndex=0;check(r,"");
    r.citizen.detailIndex=127;check(r,"");r.citizen.detailIndex=128;check(r,"invalid citizen request");
    r.citizen.detailIndex=-1;
  }
  r.citizen.detailIndex=0;r.citizen.edit=1;
  r.citizen.name=std::string(160,'x');check(r,"");r.citizen.name+='x';check(r,"work detail name too long");
  r.citizen.name="";check(r,"");r.citizen.edit=0;check(r,"invalid work detail edit");
  r.citizen.edit=4;check(r,"invalid work detail edit");r.citizen.edit=2;
  for(int i=0;i<94;++i)r.citizen.labors.push_back(i);
  check(r,"");
  r.citizen.labors.push_back(94);check(r,"too many work detail labors");
  for(auto values:{std::vector<int16_t>{-1},std::vector<int16_t>{94},std::vector<int16_t>{0,0}}) {
    r.citizen.labors=values;check(r,"invalid work detail labor");
  }
  r.citizen.labors={};check(r,"");r.citizen.edit=3;check(r,"");
  r.citizen.name="x";check(r,"unexpected work detail name");r.citizen.name="";
  r.citizen.labors={1};check(r,"unexpected work detail labors");r.citizen.labors={};
  r.action=wm::ManagementAction::CitizenWorkScope;r.citizen.edit=0;r.citizen.detailIndex=-1;
  check(r,"invalid citizen work scope");r.citizen.unitId=0;
  for(int value:{0,1}) {r.citizen.onlyAssigned=value;check(r,"");}
  for(int value:{-1,2}) {r.citizen.onlyAssigned=value;check(r,"invalid citizen work scope");}
  r={};r.action=wm::ManagementAction::WorkDetailList;check(r,"");r.citizen.cursor=1;
  check(r,"work detail list revision required");r.citizen.expectedListRevision=INT64_MAX;check(r,"");
  r.citizen.expectedListRevision=uint64_t(INT64_MAX)+1;check(r,"invalid work detail list revision");
  r.citizen.expectedListRevision=1;r.action=wm::ManagementAction::CitizenList;check(r,"unexpected work detail list revision");
}

TEST_CASE("citizen codec preserves every appended state field and defaults") {
  for(bool populated:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    auto skill=b.CreateString(populated?"Legendary Miner":"");
    auto error=b.CreateString(populated?"Row exceeds name cap":"");
    wire::TilePos origin(0,0,0);
    wire::CitizenInfoBuilder person(b);person.add_id(0);person.add_origin(&origin);
    if(populated) {
      person.add_revision(INT64_MAX);person.add_detail_member(1);person.add_detail_skill(1);
      person.add_detail_skill_rating(15);person.add_detail_skill_name(skill);person.add_portrait_state(3);person.add_row_error(error);
    }
    auto u=person.Finish();
    wire::WorkDetailInfoBuilder detail(b);detail.add_index(0);
    if(populated){detail.add_icon(18);detail.add_row_error(error);}
    auto d=detail.Finish();auto people=b.CreateVector(std::vector{u});auto details=b.CreateVector(std::vector{d});
    auto recalc=b.CreateString(populated?"Native recalculation failed; labors may be stale":"");
    wire::CitizenStateBuilder state(b);state.add_citizens(people);state.add_details(details);
    if(populated){state.add_recalc_done(1);state.add_recalc_total(5000);state.add_recalc_error(recalc);state.add_detail_list_revision(INT64_MAX);}
    b.Finish(state.Finish());auto decoded=codec::decodeCitizen(flatbuffers::GetRoot<wire::CitizenState>(b.GetBufferPointer()));
    REQUIRE(decoded.citizens.size()==1);REQUIRE(decoded.details.size()==1);
    const auto& row=decoded.citizens[0];CHECK(row.revision==(populated?INT64_MAX:0));
    CHECK(row.detailMember==(populated?1:-1));CHECK(row.detailSkill==(populated?1:-1));
    CHECK(row.detailSkillRating==(populated?15:-1));CHECK(row.detailSkillName==(populated?"Legendary Miner":""));
    CHECK(row.portraitState==(populated?3:0));CHECK(row.rowError==(populated?"Row exceeds name cap":""));
    CHECK(decoded.details[0].icon==(populated?18:-2));CHECK(decoded.details[0].rowError==row.rowError);
    CHECK(decoded.recalcDone==(populated?1:0));CHECK(decoded.recalcTotal==(populated?5000:0));
    CHECK(decoded.detailListRevision==(populated?INT64_MAX:0));CHECK(decoded.recalcError==(populated?"Native recalculation failed; labors may be stale":""));
  }
}

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

TEST_CASE("empty work-order traits do not turn moves or details into another edit") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::WorkOrderUpdate;
  auto& w=r.workOrder;w.id=0;w.expectedRevision=1;w.move=1;
  w.expectedNeighbor=1;w.expectedListRevision=1;w.traits.emplace();
  REQUIRE_FALSE(encoded.invalid(r));CHECK(encoded.get()->work_order()->traits()==nullptr);
  w.traits->push_back("f1:0");CHECK(encoded.invalid(r));
  w.traits->clear();w.move=0;w.expectedNeighbor=-1;w.expectedListRevision=0;
  w.inputIndex=0;w.matType=0;w.matIndex=0;
  REQUIRE_FALSE(encoded.invalid(r));CHECK(encoded.get()->work_order()->traits()==nullptr);
  w.traits->push_back("f1:0");CHECK(encoded.invalid(r));
  // Condition edits retain an explicit empty replacement, distinct from absence.
  w={};w.id=0;w.expectedRevision=1;w.compare=0;w.threshold=0;w.traits.emplace();
  r.action=wm::ManagementAction::WorkOrderCondition;
  REQUIRE_FALSE(encoded.invalid(r));REQUIRE(encoded.get()->work_order()->traits());
  CHECK(encoded.get()->work_order()->traits()->size()==0);
  w={};r.action=wm::ManagementAction::WorkOrderCatalog;
  w.query=std::string(64,'q');REQUIRE_FALSE(encoded.invalid(r));
  w.query.push_back('q');CHECK(encoded.invalid(r));
}

TEST_CASE("maximal producer order page fits the management channel") {
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<mm::WorkOrderInfo>> orders;
  for(int id=0;id<16;++id) {
    std::vector<flatbuffers::Offset<mm::WorkOrderCondition>> conditions;
    std::vector<flatbuffers::Offset<mm::WorkOrderInput>> inputs;
    for(int index=0;index<8;++index) {
      std::vector<std::string> traits;
      for(int t=0;t<16;++t)traits.push_back("rc:"+std::string(59,'x')+char('a'+t)+char('a'+index));
      conditions.push_back(mm::CreateWorkOrderCondition(b,0,index,b.CreateString(std::string(256,'c')),
        true,0,1,-1,-1,-1,false,-1,-1,-1,b.CreateVectorOfStrings(traits),1,true,-1));
      // The producer currently emits empty input descriptions.
      inputs.push_back(mm::CreateWorkOrderInput(b,index,b.CreateString(""),-1,-1,true));
    }
    std::vector<int32_t> jobs;for(int j=0;j<128;++j)jobs.push_back(id*128+j);
    auto name=b.CreateString(std::string(512,'n')),reason=b.CreateString(std::string(1024,'r'));
    auto cs=b.CreateVector(conditions);auto ins=b.CreateVector(inputs);auto js=b.CreateVector(jobs);
    mm::WorkOrderInfoBuilder o(b);o.add_id(id);o.add_revision(1);o.add_name(name);o.add_reason(reason);
    o.add_total(10);o.add_remaining(10);o.add_conditions(cs);o.add_inputs(ins);o.add_generated_jobs(js);
    orders.push_back(o.Finish());
  }
  auto os=b.CreateVector(orders);
  mm::WorkOrderStateBuilder w(b);w.add_orders(os);w.add_list_revision(INT64_MAX);auto ws=w.Finish();
  auto citizen=mm::CreateCitizenState(b,
    b.CreateVector(std::vector<flatbuffers::Offset<mm::CitizenInfo>>{}),
    b.CreateVector(std::vector<flatbuffers::Offset<mm::WorkDetailInfo>>{}));
  mm::ManagementStateBuilder s(b);s.add_schema_version(mm::kManagementVersion);s.add_revision(1);
  s.add_action(mm::ManagementAction::WorkOrderList);s.add_status(mm::ManagementStatus::Ok);s.add_work_order(ws);s.add_citizen(citizen);
  b.Finish(s.Finish());
  CHECK(b.GetSize()<mm::kManagementCapacity);
  CHECK_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
}

TEST_CASE("non-citizen replies reject populated citizen tables") {
  for(bool detail : {false,true}) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<mm::CitizenInfo>> people;
    std::vector<flatbuffers::Offset<mm::WorkDetailInfo>> details;
    if(detail) details.push_back(mm::CreateWorkDetailInfo(b));
    else people.push_back(mm::CreateCitizenInfo(b));
    auto citizens=mm::CreateCitizenState(b,b.CreateVector(people),b.CreateVector(details));
    mm::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(mm::ManagementAction::WorkOrderList);state.add_citizen(citizens);
    b.Finish(state.Finish());
    auto error=mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer()));
    REQUIRE(error);CHECK(*error=="unexpected citizen state");
  }
}

TEST_CASE("work-order request fields and exclusive intents survive encoding") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::WorkOrderCondition;
  auto& w=r.workOrder;w.id=0;w.expectedRevision=1;w.compare=0;w.threshold=0;
  w.itemSubtype=2;w.matType=419;w.matIndex=7;w.traits=std::vector<std::string>{"f1:0","rc:X"};
  REQUIRE_FALSE(encoded.invalid(r));auto* q=encoded.get()->work_order();
  CHECK(q->item_subtype()==2);CHECK(q->mat_type()==419);CHECK(q->mat_index()==7);
  REQUIRE(q->traits());CHECK(q->traits()->Get(1)->str()=="rc:X");
  w.traits=std::vector<std::string>(256,std::string(64,'t'));CHECK_FALSE(encoded.invalid(r));
  w.traits->push_back("x");CHECK(encoded.invalid(r));w.traits->pop_back();
  w.traits->front().push_back('x');CHECK(encoded.invalid(r));
  w={};r.action=wm::ManagementAction::WorkOrderCatalog;
  w.groupType=0;w.groupSubtype=2;w.groupCustom=3;w.expectedListRevision=INT64_MAX;
  REQUIRE_FALSE(encoded.invalid(r));q=encoded.get()->work_order();
  CHECK(q->group_type()==0);CHECK(q->group_subtype()==2);CHECK(q->group_custom()==3);
  CHECK(q->expected_list_revision()==INT64_MAX);
  w={};r.action=wm::ManagementAction::WorkOrderUpdate;w.id=0;w.expectedRevision=1;
  w.move=1;w.expectedNeighbor=2;w.expectedListRevision=INT64_MAX;
  REQUIRE_FALSE(encoded.invalid(r));q=encoded.get()->work_order();
  CHECK(q->move()==1);CHECK(q->expected_neighbor()==2);CHECK(q->expected_list_revision()==INT64_MAX);
  w.move=-1;CHECK_FALSE(encoded.invalid(r));w.move=2;CHECK(encoded.invalid(r));
  w.move=-2;CHECK(encoded.invalid(r));w.move=1;
  const auto move=r;
  for(int missing=0;missing<5;++missing) {
    r=move;
    if(missing==0)r.action=wm::ManagementAction::WorkOrderDelete;
    if(missing==1)w.id=-1;
    if(missing==2)w.expectedRevision=0;
    if(missing==3)w.expectedNeighbor=-1;
    if(missing==4)w.expectedListRevision=0;
    CHECK(encoded.invalid(r));
  }
  r=move;w.move=0;w.expectedNeighbor=-1;w.expectedListRevision=0;
  w.inputIndex=0;w.matType=0;w.matIndex=0;w.encrustFlags=1092;
  REQUIRE_FALSE(encoded.invalid(r));q=encoded.get()->work_order();
  CHECK(q->input_index()==0);CHECK(q->mat_type()==0);CHECK(q->mat_index()==0);CHECK(q->encrust_flags()==1092);
  const auto input=r;
  for(int missing=0;missing<7;++missing) {
    r=input;
    if(missing==0)r.action=wm::ManagementAction::WorkOrderDelete;
    if(missing==1)w.id=-1;
    if(missing==2)w.expectedRevision=0;
    if(missing==3)w.expectedNeighbor=0;
    if(missing==4)w.expectedListRevision=1;
    if(missing==5)w.move=1;
    if(missing==6){w.matType=-1;w.matIndex=-1;w.encrustFlags=-1;}
    CHECK(encoded.invalid(r));
  }
  // New scalar identities retain -1 and zero, and refuse values below -1.
  for(int field=0;field<9;++field) for(int value:{-1,0,-2}) {
    r={};r.action=wm::ManagementAction::WorkOrderCatalog;
    switch(field) {
      case 0:w.expectedNeighbor=value;break;case 1:w.itemSubtype=value;break;
      case 2:w.matType=value;break;case 3:w.matIndex=value;break;
      case 4:w.groupType=value;break;case 5:w.groupSubtype=value;break;
      case 6:w.groupCustom=value;break;case 7:w.encrustFlags=value;break;
      case 8:w.inputIndex=value;if(value==0)r=input;break;
    }
    CHECK(encoded.invalid(r)==(value==-2));
  }
  r=move;w.expectedListRevision=-1;CHECK(encoded.invalid(r));
  // Every unrelated field must leave its default only in a separate intent.
  for(const auto& base:{move,input}) for(int field=0;field<25;++field) {
    r=base;
    switch(field) {
      case 0:w.remaining=0;break;case 1:w.frequency=0;break;
      case 2:w.workshopId=-1;break;case 3:w.maxWorkshops=0;break;
      case 4:w.recipe="x";break;case 5:w.query="x";break;case 6:w.cursor=1;break;
      case 7:w.conditionKind=1;break;case 8:w.conditionIndex=0;break;
      case 9:w.removeCondition=true;break;case 10:w.compare=0;break;
      case 11:w.threshold=0;break;case 12:w.itemType=0;break;
      case 13:w.targetOrder=1;break;case 14:w.dependency=0;break;
      case 15:w.candidateKind=1;break;case 16:w.itemSubtype=0;break;
      case 17:w.traits=std::vector<std::string>{"f1:0"};break;
      case 18:w.groupType=0;break;case 19:w.groupSubtype=0;break;case 20:w.groupCustom=0;break;
      case 21:if(base.workOrder.move)w.inputIndex=0;else w.inputIndex=-1;break;
      case 22:if(base.workOrder.move)w.matType=0;else w.move=1;break;
      case 23:if(base.workOrder.move)w.matIndex=0;else w.expectedNeighbor=0;break;
      case 24:if(base.workOrder.move)w.encrustFlags=0;else w.expectedListRevision=1;break;
    }
    CAPTURE(field);CHECK(encoded.invalid(r));
  }
}

TEST_CASE("work-order response fields decode with owned strings and absent defaults") {
  for(bool present:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    auto ts=b.CreateVectorOfStrings(std::vector<std::string>{"f5:31","rp:X"});
    mm::WorkOrderConditionBuilder c(b);
    if(present){c.add_item_subtype(3);c.add_mat_type(419);c.add_mat_index(7);c.add_traits(ts);
      c.add_satisfaction(2);c.add_estimated(true);c.add_estimate_count(42);}
    auto cs=b.CreateVector(std::vector{c.Finish()});
    auto in=mm::CreateWorkOrderInput(b,2,b.CreateString("input"),0,5,true);
    auto ins=b.CreateVector(std::vector{in});
    mm::WorkOrderInfoBuilder o(b);o.add_id(0);o.add_revision(1);o.add_conditions(cs);
    if(present){o.add_position(12);o.add_detail_kind(6);o.add_size_raw(17);o.add_encrust_flags(1092);
      o.add_mat_type(19);o.add_mat_index(8);o.add_material_category(4096);o.add_inputs(ins);}
    auto os=b.CreateVector(std::vector{o.Finish()});
    auto mat=mm::CreateWorkOrderMaterial(b,0,4,b.CreateString("material"));
    auto mats=b.CreateVector(std::vector{mat});
    auto trait=mm::CreateWorkOrderTrait(b,b.CreateString("rc:X"),b.CreateString("trait"));
    auto traits=b.CreateVector(std::vector{trait});
    auto type=mm::CreateWorkOrderItemType(b,3,2,b.CreateString("type"));
    auto types=b.CreateVector(std::vector{type});
    auto group=mm::CreateWorkOrderGroup(b,0,2,7,b.CreateString("group"),9);
    auto groups=b.CreateVector(std::vector{group});
    auto task=mm::CreateWorkOrderTask(b,b.CreateString("key"),b.CreateString("task"),11,b.CreateString("reaction"),3,2,419,7);
    auto tasks=b.CreateVector(std::vector{task});
    mm::WorkOrderStateBuilder state(b);state.add_orders(os);
    if(present){state.add_materials(mats);state.add_traits(traits);state.add_types(types);state.add_groups(groups);state.add_tasks(tasks);
      state.add_total(128);state.add_list_revision(INT64_MAX);state.add_build_phase(3);state.add_build_done(17);state.add_build_total(128);}
    b.Finish(state.Finish());auto decoded=codec::decodeWorkOrder(flatbuffers::GetRoot<mm::WorkOrderState>(b.GetBufferPointer()));
    std::fill_n(b.GetBufferPointer(),b.GetSize(),uint8_t(0));
    REQUIRE(decoded.orders.size()==1);const auto& order=decoded.orders[0];REQUIRE(order.conditions.size()==1);const auto& cond=order.conditions[0];
    CHECK(order.position==(present?12:-1));CHECK(order.detailKind==(present?6:0));CHECK(order.sizeRaw==(present?17:-1));
    CHECK(order.encrustFlags==(present?1092:0));CHECK(order.matType==(present?19:-1));CHECK(order.matIndex==(present?8:-1));CHECK(order.materialCategory==(present?4096:0));
    CHECK(cond.itemSubtype==(present?3:-1));CHECK(cond.matType==(present?419:-1));CHECK(cond.matIndex==(present?7:-1));
    CHECK(cond.satisfaction==(present?2:0));CHECK(cond.estimated==present);CHECK(cond.estimateCount==(present?42:-1));
    CHECK(decoded.total==(present?128:0));CHECK(decoded.listRevision==(present?INT64_MAX:0));
    CHECK(decoded.buildPhase==(present?3:0));CHECK(decoded.buildDone==(present?17:0));CHECK(decoded.buildTotal==(present?128:0));
    if(present) {
      CHECK(cond.traits==std::vector<std::string>{"f5:31","rp:X"});
      REQUIRE(order.inputs.size()==1);const auto& i=order.inputs[0];CHECK(i.index==2);CHECK(i.description=="input");CHECK(i.matType==0);CHECK(i.matIndex==5);CHECK(i.editable);
      REQUIRE(decoded.materials.size()==1);CHECK(decoded.materials[0].matType==0);CHECK(decoded.materials[0].matIndex==4);CHECK(decoded.materials[0].name=="material");
      REQUIRE(decoded.traits.size()==1);CHECK(decoded.traits[0].key=="rc:X");CHECK(decoded.traits[0].name=="trait");
      REQUIRE(decoded.types.size()==1);CHECK(decoded.types[0].itemType==3);CHECK(decoded.types[0].itemSubtype==2);CHECK(decoded.types[0].name=="type");
      REQUIRE(decoded.groups.size()==1);const auto& g=decoded.groups[0];CHECK(g.type==0);CHECK(g.subtype==2);CHECK(g.custom==7);CHECK(g.name=="group");CHECK(g.count==9);
      REQUIRE(decoded.tasks.size()==1);const auto& t=decoded.tasks[0];CHECK(t.key=="key");CHECK(t.name=="task");CHECK(t.jobType==11);CHECK(t.reaction=="reaction");CHECK(t.itemType==3);CHECK(t.itemSubtype==2);CHECK(t.matType==419);CHECK(t.matIndex==7);
    } else {
      CHECK(cond.traits.empty());CHECK(order.inputs.empty());CHECK(decoded.materials.empty());CHECK(decoded.traits.empty());CHECK(decoded.types.empty());CHECK(decoded.groups.empty());CHECK(decoded.tasks.empty());
    }
  }
}

namespace {
// One boundary changes per case; the valid baseline saturates every page cap.
struct WorkOrderPageBounds {
  int orders=16,conditions=128,traits=2048,jobs=2048,rows=128,keyBytes=64,nameBytes=128;
  int detailKind=6,satisfaction=2,phase=3,done=128,total=128;
  uint64_t revision=INT64_MAX;
  int list=-1; // -1: all catalogs; otherwise select one catalog for its boundary.
};
void workOrderPage(flatbuffers::FlatBufferBuilder& b,const WorkOrderPageBounds& n) {
  std::vector<flatbuffers::Offset<mm::WorkOrderInfo>> orders;
  for(int id=0;id<n.orders;++id) {
    std::vector<flatbuffers::Offset<mm::WorkOrderCondition>> conditions;
    const int count=n.conditions/n.orders+(id<n.conditions%n.orders);
    for(int index=0;index<count;++index) {
      const int ordinal=id*(n.conditions/n.orders)+std::min(id,n.conditions%n.orders)+index;
      const int traitCount=n.traits/n.conditions+(ordinal<n.traits%n.conditions);
      auto traits=b.CreateVectorOfStrings(std::vector<std::string>(traitCount,std::string(n.keyBytes,'t')));
      mm::WorkOrderConditionBuilder c(b);c.add_index(index);c.add_traits(traits);c.add_satisfaction(n.satisfaction);
      conditions.push_back(c.Finish());
    }
    std::vector<int32_t> jobs;
    for(int j=0;j<n.jobs/n.orders+(id<n.jobs%n.orders);++j)jobs.push_back(id*1024+j);
    auto cs=b.CreateVector(conditions);auto js=b.CreateVector(jobs);
    mm::WorkOrderInfoBuilder o(b);o.add_id(id);o.add_revision(1);o.add_detail_kind(n.detailKind);o.add_conditions(cs);o.add_generated_jobs(js);
    orders.push_back(o.Finish());
  }
  std::vector<flatbuffers::Offset<mm::WorkOrderMaterial>> mats;
  std::vector<flatbuffers::Offset<mm::WorkOrderTrait>> traits;
  std::vector<flatbuffers::Offset<mm::WorkOrderItemType>> types;
  std::vector<flatbuffers::Offset<mm::WorkOrderGroup>> groups;
  std::vector<flatbuffers::Offset<mm::WorkOrderTask>> tasks;
  for(int i=0;i<n.rows;++i) {
    if(n.list<0 || n.list==0)mats.push_back(mm::CreateWorkOrderMaterial(b,0,i,b.CreateString(std::string(n.nameBytes,'m'))));
    if(n.list<0 || n.list==1)traits.push_back(mm::CreateWorkOrderTrait(b,b.CreateString(std::string(n.keyBytes,'t')),b.CreateString(std::string(n.nameBytes,'t'))));
    if(n.list<0 || n.list==2)types.push_back(mm::CreateWorkOrderItemType(b,0,i,b.CreateString(std::string(n.nameBytes,'y'))));
    if(n.list<0 || n.list==3)groups.push_back(mm::CreateWorkOrderGroup(b,0,0,i,b.CreateString(std::string(n.nameBytes,'g')),1));
    if(n.list<0 || n.list==4)tasks.push_back(mm::CreateWorkOrderTask(b,b.CreateString(std::string(n.keyBytes,'k')),b.CreateString(std::string(n.nameBytes,'n')),0,b.CreateString(std::string(64,'r')),0,0,0,i));
  }
  auto os=b.CreateVector(orders);auto ms=b.CreateVector(mats);auto ts=b.CreateVector(traits);auto ys=b.CreateVector(types);auto gs=b.CreateVector(groups);auto ks=b.CreateVector(tasks);
  mm::WorkOrderStateBuilder w(b);w.add_orders(os);w.add_materials(ms);w.add_traits(ts);w.add_types(ys);w.add_groups(gs);w.add_tasks(ks);
  w.add_list_revision(n.revision);w.add_build_phase(n.phase);w.add_build_done(n.done);w.add_build_total(n.total);auto ws=w.Finish();
  mm::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(mm::ManagementAction::WorkOrderList);state.add_status(mm::ManagementStatus::Ok);state.add_work_order(ws);b.Finish(state.Finish());
}
}
TEST_CASE("maximal management page and individual state validator boundaries") {
  auto valid=[](const WorkOrderPageBounds& n) {
    flatbuffers::FlatBufferBuilder b;workOrderPage(b,n);
    flatbuffers::Verifier v(b.GetBufferPointer(),b.GetSize());REQUIRE(v.VerifyBuffer<mm::ManagementState>(nullptr));
    CHECK(b.GetSize()<mm::kManagementCapacity);
    return !mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value();
  };
  CHECK(valid({}));
  for(int boundary=0;boundary<10;++boundary) {
    WorkOrderPageBounds n;CAPTURE(boundary);
    switch(boundary) {
      case 0:n.orders=17;break;case 1:n.conditions=129;break;case 2:n.traits=2049;break;
      case 3:n.jobs=2049;break;case 4:n.detailKind=7;break;case 5:n.satisfaction=3;break;
      case 6:n.phase=4;break;case 7:n.done=129;break;case 8:n.revision=uint64_t(INT64_MAX)+1;break;
      case 9:n.keyBytes=65;n.rows=0;break;
    }
    CHECK_FALSE(valid(n));
  }
  for(int list=0;list<5;++list) {
    WorkOrderPageBounds n;n.list=list;CHECK(valid(n));n.rows=129;CHECK_FALSE(valid(n));
    n.rows=128;n.nameBytes=129;CHECK_FALSE(valid(n));
    if(list==1 || list==4){n.nameBytes=128;n.traits=0;n.keyBytes=65;CHECK_FALSE(valid(n));}
  }
}

TEST_CASE("work-order default catalog identities and per-condition trait boundaries") {
  for(int size:{256,257}) {
    flatbuffers::FlatBufferBuilder b;
    auto ts=b.CreateVectorOfStrings(std::vector<std::string>(size,"f1:0"));
    mm::WorkOrderConditionBuilder c(b);c.add_traits(ts);auto cs=b.CreateVector(std::vector{c.Finish()});
    mm::WorkOrderInfoBuilder o(b);o.add_revision(1);o.add_conditions(cs);auto os=b.CreateVector(std::vector{o.Finish()});
    auto mat=mm::CreateWorkOrderMaterial(b);auto mats=b.CreateVector(std::vector{mat});
    auto type=mm::CreateWorkOrderItemType(b);auto types=b.CreateVector(std::vector{type});
    auto group=mm::CreateWorkOrderGroup(b);auto groups=b.CreateVector(std::vector{group});
    auto task=mm::CreateWorkOrderTask(b);auto tasks=b.CreateVector(std::vector{task});
    mm::WorkOrderStateBuilder w(b);w.add_orders(os);w.add_materials(mats);w.add_types(types);w.add_groups(groups);w.add_tasks(tasks);auto ws=w.Finish();
    mm::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(mm::ManagementAction::WorkOrderList);state.add_status(mm::ManagementStatus::Ok);state.add_work_order(ws);b.Finish(state.Finish());
    const auto* wire=flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer());
    CHECK(mm::validateManagementState(*wire).has_value()==(size==257));
    const auto decoded=codec::decodeWorkOrder(wire->work_order());
    CHECK(decoded.materials[0].matType==-1);CHECK(decoded.materials[0].matIndex==-1);
    CHECK(decoded.types[0].itemType==-1);CHECK(decoded.types[0].itemSubtype==-1);
    CHECK(decoded.groups[0].type==-1);CHECK(decoded.groups[0].subtype==-1);CHECK(decoded.groups[0].custom==-1);CHECK(decoded.groups[0].count==0);
    const auto& t=decoded.tasks[0];CHECK(t.jobType==-1);CHECK(t.itemType==-1);CHECK(t.itemSubtype==-1);CHECK(t.matType==-1);CHECK(t.matIndex==-1);
  }
}

TEST_CASE("construction selection revisions are optional signed int64 values per entry") {
  wm::ManagementRequest request;
  request.action=wm::ManagementAction::Place;request.definition="Chair";
  request.selections={{0,-1,-1,-1,-1,1},{1,-1,-1,-1,-1,1,42}};
  for (int64_t revision : {int64_t(-2),int64_t(-1),int64_t(0),int64_t(1),int64_t(INT64_MAX)}) {
    request.selections[0].expectedListRevision=revision;
    flatbuffers::FlatBufferBuilder builder;
    codec::encodeRequest(builder,request,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(builder.GetBufferPointer());
    CHECK(encoded->expected_list_revision()==0);
    CHECK(encoded->selections()->Get(0)->expected_list_revision()==revision);
    CHECK(encoded->selections()->Get(1)->expected_list_revision()==42);
    auto error=wire::validateConstructionRequest(*encoded);
    if(revision < -1) { REQUIRE(error);CHECK(*error=="invalid construction selection list revision"); }
    else CHECK_FALSE(error);
  }
  // The appended field is absent in an older selection buffer.
  flatbuffers::FlatBufferBuilder builder;
  builder.Finish(wire::CreateConstructionSelection(builder,0,-1,-1,-1,-1,1));
  CHECK(flatbuffers::GetRoot<wire::ConstructionSelection>(builder.GetBufferPointer())->expected_list_revision()==-1);
  request.selections.clear();
  builder.Clear();codec::encodeRequest(builder,request,1,2,3);
  CHECK_FALSE(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(builder.GetBufferPointer())));
}

TEST_CASE("construction native decisions survive request codecs and validation") {
  auto error=[](const wm::ManagementRequest& r) {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* v=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(v->direction()==r.direction);CHECK(v->depth()==r.depth);
    CHECK(v->origin()->x()==r.x);CHECK(v->origin()->y()==r.y);CHECK(v->origin()->z()==r.z);
    if(!r.selections.empty())CHECK(v->selections()->Get(0)->count()==r.selections[0].count);
    return wire::validateConstructionRequest(*v);
  };
  wm::ManagementRequest r;r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  REQUIRE(error(r));CHECK(*error(r)=="Must span multiple elevations");
  r.depth=2;CHECK_FALSE(error(r));r.depth=1;r.definition="SiegeEngine:Ballista";
  for(uint8_t d=0;d<8;++d){r.direction=d;CHECK_FALSE(error(r));}
  r.direction=8;REQUIRE(error(r));CHECK(*error(r)=="invalid dimensions or orientation");r.direction=0;
  r.action=wm::ManagementAction::Place;
  for(const char* key:{"Weapon","Trap:WeaponTrap"}) {
    r.definition=key;r.selections={{int16_t(r.definition=="Weapon" ? 0 : 1)}};
    CHECK(r.selections[0].count==1);CHECK_FALSE(error(r));
    r.selections[0].count=10;CHECK_FALSE(error(r));
    r.selections[0].count=11;REQUIRE(error(r));CHECK(*error(r)=="Weapon count must be between 1 and 10");
    r.selections[0].count=0;REQUIRE(error(r));CHECK(*error(r)=="invalid or duplicate construction selection");
    r.selections.clear();REQUIRE(error(r));CHECK(*error(r)=="Weapon count must be between 1 and 10");
  }
  r.action=wm::ManagementAction::ConstructionMaterials;r.definition="Chair";r.filter=0;
  r.x=10;r.y=20;r.z=3;CHECK_FALSE(error(r));
}

TEST_CASE("construction codec preserves eight facings and per-tile totals") {
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> footprints;
  for(uint8_t d=0;d<8;++d)footprints.push_back(wire::CreateConstructionFootprint(b,d,1,1,0,0));
  const auto fps=b.CreateVector(footprints);const auto key=b.CreateString("SiegeEngine:Ballista");
  wire::BuildingDefinitionBuilder def(b);def.add_key(key);def.add_width(1);def.add_height(1);
  def.add_orientations(255);def.add_footprints(fps);const auto definition=def.Finish();
  const auto catalog=b.CreateVector(std::vector{definition});
  const auto filter=wire::CreateConstructionFilter(b,0,-1,-1,0,0,1024);
  const auto filters=b.CreateVector(std::vector{filter});
  wire::ConstructionStateBuilder c(b);c.add_filters(filters);c.add_placed(1024);const auto construction=c.Finish();
  wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_catalog(catalog);
  state.add_required(1024);state.add_construction(construction);b.Finish(state.Finish());
  const auto* encoded=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateManagementState(*encoded));
  wm::ManagementState decoded;codec::decodeConstruction(encoded,decoded);
  REQUIRE(decoded.catalog.size()==1);CHECK(decoded.catalog[0].orientations==255);
  REQUIRE(decoded.catalog[0].footprints.size()==8);CHECK(decoded.catalog[0].footprints[7].direction==7);
  CHECK(decoded.required==1024);CHECK(decoded.construction.placed==1024);
  CHECK(decoded.construction.filters[0].quantity==1024);
}

TEST_CASE("material lists require a placement origin and eight footprints is the limit") {
  for(int missing=0;missing<3;++missing) {
    flatbuffers::FlatBufferBuilder b;
    const auto key=b.CreateString(missing==0 ? "" : "Chair");const wire::TilePos origin(0,0,0);
    wire::ConstructionRequestBuilder request(b);request.add_client_id(1);request.add_seq(1);request.add_world_epoch(1);
    request.add_action(wire::ManagementAction::ConstructionMaterials);request.add_definition(key);
    request.add_filter(missing==1 ? -1 : 0);if(missing!=2)request.add_origin(&origin);b.Finish(request.Finish());
    const auto error=wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer()));
    REQUIRE(error);CHECK(*error=="definition, filter and origin required");
  }
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> rows;
  for(uint8_t d=0;d<9;++d)rows.push_back(wire::CreateConstructionFootprint(b,d%8,1,1,0,0));
  const auto fps=b.CreateVector(rows);const auto key=b.CreateString("SiegeEngine:Ballista");
  wire::BuildingDefinitionBuilder definition(b);definition.add_key(key);definition.add_width(1);definition.add_height(1);
  definition.add_footprints(fps);const auto def=definition.Finish();const auto catalog=b.CreateVector(std::vector{def});
  wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_catalog(catalog);b.Finish(state.Finish());
  const auto error=wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer()));
  REQUIRE(error);CHECK(*error=="too many construction footprints");
}


// These maximal wire fixtures exercise schema bounds, not recorded native labels.
// Producer fields: construction.lua definitions/filter_row/materials/placement.
namespace {
struct ConstructionWire {
  flatbuffers::FlatBufferBuilder b;
  const wire::ManagementState* state=nullptr;
  ConstructionWire(const std::string& field="", int64_t n=0, int page=0) {
    auto value=[&](const char* key,int64_t normal){return field==key?n:normal;};
    auto text=[&](const char* key,size_t normal){return b.CreateString(std::string(size_t(value(key,normal)),'x'));};
    std::vector<flatbuffers::Offset<wire::ConstructionFilter>> filters;
    for(int i=0;i<value("filters",8);++i)
      filters.push_back(wire::CreateConstructionFilter(b,int16_t(value("filter_index",i)),
        int16_t(value("filter_type",-1)),int16_t(value("filter_subtype",-1)),
        text("filter_caption",64),text("requirement",64),int32_t(value("quantity",-1))));
    auto fs=b.CreateVector(filters);
    std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> footprints;
    for(int i=0;i<value("footprints",5);++i)
      footprints.push_back(wire::CreateConstructionFootprint(b,uint8_t(value("direction",i)),
        uint16_t(value("fp_width",31)),uint16_t(value("fp_height",31)),
        int16_t(value("center_x",field=="fp_width"?0:30)),int16_t(value("center_y",-1))));

    std::vector<flatbuffers::Offset<wire::BuildingDefinition>> catalog;
    if(page==0)for(int i=0;i<value("catalog",128);++i) {
      std::string key=std::to_string(i);key.resize(size_t(value("key",64)),'k');
      const auto k=b.CreateString(key),name=text("name",128),reason=text("reason",128),native=text("native_name",128),
        family=text("family",64),subtype=text("subtype_key",64),custom=text("custom_code",64);
      // No shared child vectors: model the producer's independently encoded rows.
      std::vector<flatbuffers::Offset<wire::ConstructionFilter>> ownFilters;
      for(int f=0;f<value("filters",8);++f)
        ownFilters.push_back(wire::CreateConstructionFilter(b,int16_t(value("filter_index",f)),
          int16_t(value("filter_type",-1)),int16_t(value("filter_subtype",-1)),
          text("filter_caption",64),text("requirement",64),int32_t(value("quantity",-1))));
      const auto ownFs=b.CreateVector(ownFilters);
      std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> ownFootprints;
      for(int f=0;f<value("footprints",5);++f)
        ownFootprints.push_back(wire::CreateConstructionFootprint(b,uint8_t(value("direction",f)),
          uint16_t(value("fp_width",31)),uint16_t(value("fp_height",31)),
          int16_t(value("center_x",field=="fp_width"?0:30)),int16_t(value("center_y",-1))));
      const auto ownFps=b.CreateVector(ownFootprints);
      wire::BuildingDefinitionBuilder d(b);d.add_key(k);d.add_name(name);d.add_reason(reason);
      d.add_native_name(native);d.add_family(family);d.add_subtype_key(subtype);d.add_custom_code(custom);
      d.add_width(uint16_t(value("width",31)));d.add_height(uint16_t(value("height",31)));
      d.add_area_mode(uint8_t(value("area_mode",4)));d.add_orientations(31);
      d.add_max_width(uint16_t(value("max_width",31)));d.add_max_height(uint16_t(value("max_height",31)));
      d.add_max_depth(uint16_t(value("max_depth",256)));d.add_filters(ownFs);d.add_footprints(ownFps);
      catalog.push_back(d.Finish());
    }
    const auto cats=b.CreateVector(catalog);
    std::vector<flatbuffers::Offset<wire::ConstructionMaterial>> materials;
    if(page==1)for(int i=0;i<value("materials",field=="mat_index"?1:128);++i)
      materials.push_back(wire::CreateConstructionMaterial(b,int16_t(value("item_type",-1)),
        int16_t(value("item_subtype",-1)),int16_t(value("mat_type",-1)),int32_t(value("mat_index",i)),
        text("material_name",128),text("material_caption",64),uint32_t(value("count",1))));
    auto mats=b.CreateVector(materials);
    auto mask=b.CreateVector(std::vector<uint8_t>(size_t(value("mask_size",page==2?1024:0)),uint8_t(value("mask",1))));
    auto pieces=b.CreateVector(std::vector<uint8_t>(size_t(value("pieces_size",page==2?1024:0)),uint8_t(value("piece",3))));
    auto key=text("building_key",64);
    wire::ConstructionStateBuilder c(b);c.add_building_key(key);c.add_filter(int16_t(value("filter",7)));
    c.add_filters(fs);c.add_materials(mats);c.add_total(128);c.add_list_revision(uint64_t(value("list_revision",INT64_MAX)));
    c.add_estimated(true);c.add_build_phase(uint8_t(value("build_phase",2)));
    c.add_build_done(uint32_t(value("build_done",128)));c.add_build_total(128);
    c.add_placed(uint32_t(value("placed",1024)));c.add_skipped(uint32_t(value("skipped",0)));
    c.add_first_building(int32_t(value("first_building",-1)));c.add_valid_mask(mask);c.add_pieces(pieces);
    if(!footprints.empty())c.add_footprint(footprints[0]);
    const auto construction=c.Finish();
    wire::ManagementStateBuilder s(b);s.add_revision(1);s.add_schema_version(uint32_t(value("version",wire::kManagementVersion)));
    s.add_catalog(cats);s.add_construction(construction);b.Finish(s.Finish());
    state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  }
  std::optional<std::string> error() const {return wire::validateManagementState(*state);}
};
}

TEST_CASE("construction maximal pages and complete owned field decoding") {
  for(int page=0;page<3;++page) {
    ConstructionWire fixture("",0,page);
    REQUIRE_FALSE(fixture.error());CHECK(fixture.b.GetSize()<wire::kManagementCapacity);
    std::cout<<"CONSTRUCTION_MAX_PAGE "<<page<<" "<<fixture.b.GetSize()<<" bytes\n";
    wm::ManagementState s;codec::decodeConstruction(fixture.state,s);
    const auto& c=s.construction;
    CHECK(c.buildingKey==std::string(64,'x'));CHECK(c.filter==7);CHECK(c.filters.size()==8);
    CHECK(c.total==128);CHECK(c.listRevision==INT64_MAX);CHECK(c.estimated);CHECK(c.buildPhase==2);
    CHECK(c.buildDone==128);CHECK(c.buildTotal==128);CHECK(c.placed==1024);CHECK(c.skipped==0);CHECK(c.firstBuilding==-1);
    REQUIRE(c.footprint);CHECK(c.footprint->direction==0);CHECK(c.footprint->width==31);CHECK(c.footprint->height==31);
    CHECK(c.footprint->centerX==30);CHECK(c.footprint->centerY==-1);
    for(int i=0;i<8;++i) {const auto& f=c.filters[i];CHECK(f.index==i);CHECK(f.itemType==-1);CHECK(f.itemSubtype==-1);
      CHECK(f.caption==std::string(64,'x'));CHECK(f.requirement==std::string(64,'x'));CHECK(f.quantity==-1);}
    if(page==0) {
      REQUIRE(s.catalog.size()==128);const auto& d=s.catalog[0];CHECK(d.key.size()==64);CHECK(d.name.size()==128);
      CHECK(d.reason.size()==128);CHECK(d.nativeName.size()==128);CHECK(d.family.size()==64);
      CHECK(d.subtypeKey.size()==64);CHECK(d.customCode.size()==64);CHECK(d.areaMode==4);CHECK(d.orientations==31);
      CHECK(d.maxWidth==31);CHECK(d.maxHeight==31);CHECK(d.maxDepth==256);CHECK(d.filters.size()==8);CHECK(d.footprints.size()==5);
    } else if(page==1) {
      REQUIRE(c.materials.size()==128);for(int i=0;i<128;++i) {const auto& m=c.materials[i];
        CHECK(m.itemType==-1);CHECK(m.itemSubtype==-1);CHECK(m.matType==-1);CHECK(m.matIndex==i);
        CHECK(m.name.size()==128);CHECK(m.caption.size()==64);CHECK(m.count==1);}
    } else {CHECK(c.validMask==std::vector<uint8_t>(1024,1));CHECK(c.pieces==std::vector<uint8_t>(1024,3));}
    std::fill_n(fixture.b.GetBufferPointer(),fixture.b.GetSize(),uint8_t(0));
    CHECK(c.buildingKey==std::string(64,'x'));CHECK(c.filters[0].requirement==std::string(64,'x'));
  }
  flatbuffers::FlatBufferBuilder b;b.Finish(wire::CreateManagementState(b));
  wm::ManagementState defaults;codec::decodeConstruction(flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer()),defaults);
  CHECK(defaults.construction.filter==-1);CHECK(defaults.construction.firstBuilding==-1);CHECK(defaults.construction.listRevision==0);
  CHECK(defaults.construction.filters.empty());CHECK(defaults.construction.materials.empty());CHECK_FALSE(defaults.construction.footprint);
}

TEST_CASE("construction state rejects each over-limit field with exact messages") {
  struct Case {const char* field;int64_t accept,reject;const char* error;int page=0;};
  for(const auto& c:std::initializer_list<Case>{
      {"catalog",128,129,"catalog too large"},{"key",64,65,"invalid definition"},
      {"name",128,129,"invalid definition"},{"reason",128,129,"invalid definition"},
      {"native_name",128,129,"invalid definition"},{"family",64,65,"invalid definition"},
      {"subtype_key",64,65,"invalid definition"},{"custom_code",64,65,"invalid definition"},
      {"width",31,32,"invalid definition"},{"height",31,32,"invalid definition"},
      {"max_width",31,32,"invalid definition"},{"max_height",31,32,"invalid definition"},
      {"max_depth",256,257,"invalid definition"},{"area_mode",4,5,"invalid definition"},
      {"filter",7,8,"invalid construction result"},{"filter",-1,-2,"invalid construction result"},
      {"first_building",-1,-2,"invalid construction result"},{"build_phase",3,4,"invalid construction result"},
      {"build_done",128,129,"invalid construction result"},{"placed",1024,1025,"invalid construction result"},
      {"skipped",0,1,"invalid construction result"},{"list_revision",INT64_MAX,INT64_MIN,"invalid construction result"},
      {"building_key",64,65,"invalid construction result"},{"filters",8,9,"invalid construction result"},
      {"filter_caption",64,65,"invalid construction result"},{"requirement",64,65,"invalid construction result"},
      {"filter_type",-1,-2,"invalid construction result"},{"filter_subtype",-1,-2,"invalid construction result"},
      {"quantity",-1,-2,"invalid construction result"},{"fp_width",31,32,"invalid construction result"},
      {"fp_height",31,32,"invalid construction result"},{"center_x",30,31,"invalid construction result"},
      {"center_y",-1,-2,"invalid construction result"},{"footprints",8,9,"too many construction footprints"},
      {"mask_size",1024,1025,"construction mask too large",2},{"mask",1,2,"invalid construction mask",2},
      {"pieces_size",1024,1025,"construction pieces too large",2},{"piece",3,4,"invalid construction piece",2},
      {"materials",128,129,"construction materials page too large",1},{"count",1,0,"invalid construction material",1},
      {"item_type",-1,-2,"invalid construction material",1},{"item_subtype",-1,-2,"invalid construction material",1},
      {"mat_type",-1,-2,"invalid construction material",1},
      {"mat_index",-1,-2,"invalid construction material",1},
      {"width",1,0,"invalid definition"},{"height",1,0,"invalid definition"},
      {"fp_width",1,0,"invalid construction result"},{"fp_height",1,0,"invalid construction result"},
      {"center_x",-1,-2,"invalid construction result"},{"center_y",30,31,"invalid construction result"},
      {"material_name",128,129,"invalid construction material",1},{"material_caption",64,65,"invalid construction material",1},
      {"version",wire::kManagementVersion,wire::kManagementVersion-1,"invalid management version/revision"}}) {
    CAPTURE(c.field);ConstructionWire accepted(c.field,c.accept,c.page);CHECK_FALSE(accepted.error());
    ConstructionWire rejected(c.field,c.reject,c.page);REQUIRE(rejected.error());CHECK(*rejected.error()==c.error);
  }
  for(const char* key:{"name","reason","native_name","family","subtype_key","custom_code","filter_caption","requirement","building_key"})
    CHECK_FALSE(ConstructionWire(key,0).error());
  for(const char* key:{"catalog","filters","footprints","mask_size","pieces_size","materials"})
    CHECK_FALSE(ConstructionWire(key,0).error());
  for(const char* key:{"filter","first_building","build_phase","build_done","placed","list_revision","quantity","area_mode","max_width","max_height","max_depth"})
    CHECK_FALSE(ConstructionWire(key,0).error());
  for(const char* key:{"mask","piece"})CHECK_FALSE(ConstructionWire(key,0,2).error());
  CHECK_FALSE(ConstructionWire("mat_index",0,1).error());
  CHECK_FALSE(ConstructionWire("count",UINT32_MAX,1).error());
  CHECK_FALSE(ConstructionWire("first_building",INT32_MAX).error());
  ConstructionWire badDirection("direction",8);REQUIRE(badDirection.error());CHECK(*badDirection.error()=="invalid construction result");
  for(const char* key:{"filter_index","direction"}) {
    ConstructionWire duplicate(key,0);REQUIRE(duplicate.error());
    CHECK(*duplicate.error()==(std::string(key)=="direction"?"invalid or duplicate construction footprint":"invalid construction result"));
  }
}

TEST_CASE("construction request boundary and absent-field matrix") {
  auto check=[](const wm::ManagementRequest& r,const std::string& expected="") {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(q->depth()==r.depth);CHECK(q->filter()==r.filter);CHECK(q->retracting()==r.retracting);
    CHECK(q->expected_list_revision()==uint64_t(r.expectedListRevision));
    CHECK(wire::validateConstructionRequest(*q).value_or("")==expected);
  };
  wm::ManagementRequest r;r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  r.width=4;r.depth=256;check(r);r.depth=257;check(r,"invalid construction depth or volume");
  r.depth=256;r.width=5;check(r,"invalid construction depth or volume");
  r.definition="Chair";r.width=1;r.depth=0;check(r,"invalid construction depth or volume");r.depth=1;check(r);
  r.retracting=true;check(r);r.direction=1;check(r,"invalid retracting orientation");r.direction=0;r.retracting=false;
  r.action=wm::ManagementAction::Catalog;r.depth=2;check(r,"unexpected construction placement fields");r.depth=1;
  r.retracting=true;check(r,"unexpected construction placement fields");r.retracting=false;
  for(auto rev:{int64_t(0),int64_t(INT64_MAX)}){r.expectedListRevision=rev;check(r);}
  r.expectedListRevision=INT64_MIN;check(r,"invalid construction list revision");r.expectedListRevision=0;
  for(auto f:{int16_t(-2),int16_t(-1),int16_t(0),int16_t(7),int16_t(8)}) {
    r.action=wm::ManagementAction::ConstructionMaterials;r.filter=f;
    check(r,f < -1 || f>7?"invalid construction filter":f==-1?"definition, filter and origin required":"");
  }
  r.filter=0;r.definition="";check(r,"definition, filter and origin required");r.definition="Chair";
  r.action=wm::ManagementAction::Catalog;check(r,"unexpected construction filter");r.filter=-1;
  r.action=wm::ManagementAction::Preview;r.expectedListRevision=1;check(r,"unexpected construction list revision");r.expectedListRevision=0;
  r.action=wm::ManagementAction::Place;
  for(int i=0;i<16;++i)r.selections.push_back({int16_t(i%8),-1,-1,-1,i,1,INT64_MAX});
  check(r);
  r.selections.push_back({0,-1,-1,-1,16,1,INT64_MAX});check(r,"too many construction selections");r.selections.pop_back();
  r.selections[1]=r.selections[0];check(r,"invalid or duplicate construction selection");r.selections.resize(1);
  for(auto f:{int16_t(-1),int16_t(0),int16_t(7),int16_t(8)}){r.selections[0].filter=f;check(r,f<0||f>7?"invalid or duplicate construction selection":"");}
  r.selections[0].filter=0;
  for(auto member:{&wm::ConstructionSelection::itemType,&wm::ConstructionSelection::itemSubtype,&wm::ConstructionSelection::matType}) {
    r.selections[0].*member=-1;check(r);r.selections[0].*member=0;check(r);
    r.selections[0].*member=-2;check(r,"invalid or duplicate construction selection");r.selections[0].*member=-1;
  }
  r.selections[0].matIndex=-2;check(r,"invalid or duplicate construction selection");r.selections[0].matIndex=-1;check(r);
  r.selections[0].count=0;check(r,"invalid or duplicate construction selection");r.selections[0].count=1;
  r.selections[0].count=UINT32_MAX;check(r);r.selections[0].count=1;
  r.action=wm::ManagementAction::Preview;check(r,"unexpected construction selections");r.selections.clear();check(r);
  r.action=wm::ManagementAction::Catalog;r.definition="";check(r);
}

#include "../../bridge/plugin/construction_effects.h"
TEST_CASE("construction committed chunks mark mutations and every intersecting block") {
  wire::TilePos origin(15,31,7);bool mutated=false;
  std::vector<std::tuple<int,int,int>> hints;
  auto hint=[&](int x,int y,int z){hints.emplace_back(x,y,z);};
  df3d_management::constructionEffects(0,&origin,2,2,2,mutated,hint);
  CHECK_FALSE(mutated);CHECK(hints.empty());
  // The helper receives committed count even when the Lua reply is Rejected.
  df3d_management::constructionEffects(1,&origin,2,2,2,mutated,hint);
  CHECK(mutated);
  const std::vector<std::tuple<int,int,int>> expected{
    {0,16,7},{16,16,7},{0,32,7},{16,32,7},
    {0,16,8},{16,16,8},{0,32,8},{16,32,8}};
  CHECK(hints==expected);
  df3d_management::constructionEffects(0,&origin,2,2,2,mutated,hint);
  CHECK(mutated);CHECK(hints==expected);
}
