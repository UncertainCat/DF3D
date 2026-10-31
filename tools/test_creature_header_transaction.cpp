#include "doctest.h"
#include "../bridge/plugin/creature_header_transaction.h"

TEST_CASE("creature header writes require fresh authority and verified effects") {
    using namespace df3d_creature;
    for(bool profession:{false,true})for(bool figure:{false,true})for(int fault=0;fault<15;++fault) {
        CAPTURE(profession);CAPTURE(figure);CAPTURE(fault);
        HeaderEditSnapshot before;before.unitId=86;before.histFigureId=figure?102:-1;
        before.hasFigure=figure;before.nickname="old";before.profession="miner";
        before.figureNickname=figure?"historical":"";before.revision=headerEditRevision(before);
        auto expected=before.revision;std::string requested="new";
        if(fault==1)++expected;
        if(fault==2)expected=0;
        if(fault==3)requested=std::string(31,'X');
        if(fault==4)requested=std::string("x\0y",3);
        int applies=0,reads=0;
        auto result=finishHeaderNameEdit(before,expected,profession,requested,[&](const std::string& bytes) {
            ++applies;CHECK(bytes=="new");
            if(fault==5)throw 5;
            return fault!=6;
        },[&]()->std::optional<HeaderEditSnapshot> {
            ++reads;
            if(fault==7)throw 7;
            if(fault==8)return {};
            auto after=before;
            (profession?after.profession:after.nickname)=requested;
            if(!profession && figure)after.figureNickname=requested;
            if(fault==9)++after.unitId;
            if(fault==10)++after.histFigureId;
            if(fault==11)(profession?after.nickname:after.profession)="unexpected";
            if(fault==12)(profession?after.profession:after.nickname)="wrong";
            if(fault==13)after.figureNickname="unexpected";
            after.revision=headerEditRevision(after);
            if(fault==14)++after.revision;
            return after;
        });
        CHECK(applies==(fault>=1 && fault<=4?0:1));
        CHECK(reads==(fault==0 || fault>=7?1:0));
        CHECK(result.receipt.has_value()==(fault==0));
        CHECK(result.mutated==!(fault>=1 && fault<=4 || fault==6));
        CHECK(result.outcome==(fault==0?HeaderEditOutcome::Completed:fault==1?HeaderEditOutcome::Stale:
            fault>=2 && fault<=4 || fault==6?HeaderEditOutcome::Rejected:HeaderEditOutcome::Unknown));
    }
}

TEST_CASE("creature unchanged header intents preserve divergent historical nickname") {
    using namespace df3d_creature;
    HeaderEditSnapshot before;before.unitId=86;before.histFigureId=102;before.hasFigure=true;
    before.nickname="same";before.figureNickname="different";before.revision=headerEditRevision(before);
    int calls=0;
    auto result=finishHeaderNameEdit(before,before.revision,false,"same",[&](auto&){++calls;return true;},
        [&]()->std::optional<HeaderEditSnapshot>{++calls;return {};});
    CHECK(calls==0);CHECK_FALSE(result.mutated);REQUIRE(result.receipt);
    CHECK(result.receipt->figureNickname=="different");CHECK(result.outcome==HeaderEditOutcome::Completed);
    auto changed=before;changed.figureNickname="external edit";
    CHECK(headerEditRevision(changed)!=before.revision);
}
