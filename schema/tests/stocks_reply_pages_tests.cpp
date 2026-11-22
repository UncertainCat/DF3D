#include "doctest.h"
#include "stocks_reply_pages.h"
#include "management_util.h"
using namespace df3d::stocks_pages;

TEST_CASE("reply families share a budget but cannot read each other's captures") {
    Store store;const Identity stock{3,7,11},production{3,8,12};
    REQUIRE(store.capture(stock,{1,2,3}));
    REQUIRE(store.capture(production,{4,5},Family::Production));
    CHECK(store.retained()==5);
    CHECK_FALSE(store.read(stock,0,Family::Production));
    CHECK_FALSE(store.read(production,0));
    REQUIRE(store.read(production,0,Family::Production));
    CHECK_FALSE(store.capture(production,{9},Family::Stocks));
    REQUIRE(store.capture({3,9,1},std::vector<uint8_t>(retainedBytes,42),Family::Production));
    CHECK_FALSE(store.read(stock,0));CHECK_FALSE(store.read(production,0,Family::Production));
    CHECK(store.retained()==retainedBytes);
}

TEST_CASE("Stocks reply pages preserve one immutable capture") {
    Store store;Assembly assembly;const Identity id{3,7,11};
    std::vector<uint8_t> source(pageBytes*2+17);
    for(size_t i=0;i<source.size();++i)source[i]=uint8_t(i%251);
    REQUIRE(store.capture(id,source));assembly.begin(id);
    for(unsigned offset=0;offset<source.size();) {
        const auto page=store.read(id,offset);REQUIRE(page);REQUIRE(valid(*page));
        CHECK_FALSE(assembly.take().has_value());REQUIRE(assembly.append(*page));
        offset=assembly.nextOffset();
    }
    REQUIRE(assembly.complete());REQUIRE(assembly.take()==source);
    CHECK_FALSE(assembly.complete());CHECK_FALSE(assembly.take());
    CHECK_FALSE(store.read(id,1));CHECK_FALSE(store.read(id,uint32_t(source.size())));
}

TEST_CASE("Stocks pages reject mixed captures and incomplete transfers") {
    Store store;const Identity id{3,7,11};REQUIRE(store.capture(id,std::vector<uint8_t>(pageBytes+1,42)));
    for(int fault=0;fault<7;++fault) {
        Assembly assembly;assembly.begin(id);auto first=*store.read(id,0);
        if(fault==0)first.identity.epoch++;
        if(fault==1)first.identity.client++;
        if(fault==2)first.identity.request++;
        if(fault==3)first.offset=pageBytes;
        if(fault==4)first.bytes.pop_back();
        if(fault==5)first.total=retainedBytes+1;
        if(fault<6){CHECK_FALSE(assembly.append(first));CHECK_FALSE(assembly.take());continue;}
        REQUIRE(assembly.append(first));auto last=*store.read(id,pageBytes);last.total++;
        CHECK_FALSE(assembly.append(last));CHECK_FALSE(assembly.take());
    }
    Assembly assembly;assembly.begin(id);auto first=*store.read(id,0);
    REQUIRE(assembly.append(first));CHECK_FALSE(assembly.append(first));CHECK_FALSE(assembly.take());
}

TEST_CASE("Stocks captures retire on replacement world changes and budget pressure") {
    Store store;const Identity first{3,7,11},second{3,7,12},other{3,8,1};
    REQUIRE(store.capture(first,{1,2,3}));REQUIRE(store.capture(second,{4}));
    CHECK_FALSE(store.capture(second,{9}));CHECK_FALSE(store.capture(first,{9}));
    REQUIRE(store.read(second,0));CHECK(store.read(second,0)->bytes==std::vector<uint8_t>{4});
    CHECK_FALSE(store.read(first,0));REQUIRE(store.read(second,0));CHECK(store.retained()==1);
    REQUIRE(store.capture(other,std::vector<uint8_t>(retainedBytes,42)));
    CHECK_FALSE(store.read(second,0));CHECK(store.retained()==retainedBytes);
    store.world(4);CHECK(store.retained()==0);CHECK_FALSE(store.read(other,0));
    CHECK_FALSE(store.capture({0,8,2},{1}));CHECK_FALSE(store.capture({4,8,2},{}));
    REQUIRE(store.capture({4,8,2},{1}));store.retire(8);CHECK(store.retained()==0);
}

TEST_CASE("Display continuations carry receipt identity and cannot mutate") {
    namespace m=df3d::mirror;
    for(int fault=0;fault<8;++fault) {
        flatbuffers::FlatBufferBuilder b;
        const auto page=m::CreateDisplayReplyRequest(b,fault==1?0:fault==2?9:7,
            fault==3?0:fault==4?1:fault==5?retainedBytes:pageBytes);
        m::ConstructionRequestBuilder request(b);request.add_client_id(2);request.add_seq(9);request.add_world_epoch(3);
        request.add_action(fault==6?m::ManagementAction::DisplayCommit:m::ManagementAction::DisplayRead);
        request.add_display_reply(page);if(fault==0)request.add_schema_version(m::kManagementVersion);
        if(fault==7)request.add_schema_version(m::kManagementVersion-1);
        b.Finish(request.Finish());
        const auto error=m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer()));
        CHECK(bool(error)==(fault!=0));
    }
}

TEST_CASE("Display pages validate byte bounds and isolate reply families") {
    namespace m=df3d::mirror;
    Store store;const Identity id{3,2,7};REQUIRE(store.capture(id,{1,2},Family::Display));
    CHECK_FALSE(store.read(id,0,Family::Stocks));CHECK_FALSE(store.read(id,0,Family::Production));
    REQUIRE(store.read(id,0,Family::Display));
    for(int fault=0;fault<8;++fault) {
        flatbuffers::FlatBufferBuilder b;
        const auto bytes=b.CreateVector(std::vector<uint8_t>(fault==1?pageBytes-1:pageBytes,42));
        const auto page=m::CreateDisplayReplyPage(b,fault==2?8:7,pageBytes+1,fault==3?1:0,bytes);
        const auto other=fault==4?m::CreateProductionReplyPage(b,7,pageBytes+1,0,bytes):flatbuffers::Offset<m::ProductionReplyPage>{};
        m::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(fault==5?0:3);
        state.add_client_id(2);state.add_request_seq(7);state.add_display_page(page);state.add_production_page(other);
        state.add_action(fault==6?m::ManagementAction::StocksMenuRead:m::ManagementAction::DisplayCommit);
        state.add_status(fault==7?m::ManagementStatus::Ok:m::ManagementStatus::Pending);
        b.Finish(state.Finish());
        const auto error=m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()));
        CHECK(bool(error)==(fault!=0));
    }
}
