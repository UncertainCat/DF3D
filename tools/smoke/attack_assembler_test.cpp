#include "doctest.h"
#include "../../bridge/plugin/attack_assembler.h"
#include "../../external/dfhack/library/modules/CombatResultScope.h"
struct Item {int id=-1;};
using Assembler=df3d_contact::AttackAssembler<Item>;
static Assembler::Record record(uint64_t id,uint64_t tick=1){Assembler::Record r;r.id=id;r.tick=tick;r.action=77;return r;}
TEST_CASE("native occurrences sharing an action stay distinct and finish in sorted order") {
    Assembler a;
    REQUIRE(a.begin(record(1)));REQUIRE(a.begin(record(2)));
    a.contact(1,{3},{4});a.contact(1,{3},{4});a.contact(1,{3},{5});
    REQUIRE(a.end(2,true));REQUIRE(a.end(1,true));
    REQUIRE(a.records().size()==2);CHECK(a.records()[0].id==1);CHECK(a.records()[1].id==2);
    CHECK(a.records()[0].contacts.size()==2);CHECK(a.records()[1].contacts.empty());
    CHECK(a.records()[0].action==a.records()[1].action);CHECK(a.records()[1].complete);
    CHECK(a.pending()==0);
}
TEST_CASE("partial and over-budget contact collections cannot be marked complete") {
    Assembler a;REQUIRE(a.begin(record(1)));
    for(int i=0;i<101;++i)a.contact(1,{1},{i+2});
    REQUIRE(a.end(1,true));CHECK(a.records()[0].contacts.size()==100);CHECK_FALSE(a.records()[0].complete);
    REQUIRE(a.begin(record(2)));a.contact(2,{-1},{3});REQUIRE(a.end(2,true));CHECK_FALSE(a.records()[1].complete);
    REQUIRE(a.begin(record(3)));REQUIRE(a.end(3,false));CHECK_FALSE(a.records()[2].complete);
}
TEST_CASE("item zero is an identity and outcome coverage is preserved") {
    Assembler a;auto r=record(1);r.weapon_context_complete=true;REQUIRE(a.begin(r));
    a.contact(1,{0},{1});REQUIRE(a.end(1,true,1,false,2,true));
    const auto& row=a.records().front();CHECK(row.complete);CHECK(row.contacts.size()==1);
    CHECK(row.weapon_context_complete);CHECK(row.outcome==2);CHECK(row.outcome_complete);
}
TEST_CASE("journal and pending work have independent bounded loss accounting") {
    Assembler a;
    for(uint64_t id=1;id<=513;++id){REQUIRE(a.begin(record(id)));REQUIRE(a.end(id,true));}
    CHECK(a.records().size()==512);CHECK(a.records().front().id==2);CHECK(a.dropped()==1);
    for(uint64_t id=1000;id<1032;++id)CHECK(a.begin(record(id)));
    CHECK_FALSE(a.begin(record(1032)));CHECK(a.dropped()==2);
    a.cancelPending();CHECK(a.pending()==0);CHECK(a.dropped()==34);
    CHECK(a.begin(record(2000,10)));CHECK(a.end(2000,true));
    a.prune(602);CHECK(a.records().size()==1);CHECK(a.records()[0].id==2000);
    a.reset();CHECK(a.records().empty());CHECK(a.dropped()==0);
}
TEST_CASE("wound ID intervals exclude nested executions without scanning old wounds") {
    DFHack::Combat::WoundInterval interval;
    interval.begin=1000;interval.end=1005;interval.exclude(1001,1004);
    CHECK(interval.bounded(128));CHECK(interval.own(1000));CHECK(interval.own(1004));
    CHECK_FALSE(interval.own(999));CHECK_FALSE(interval.own(1001));CHECK_FALSE(interval.own(1003));CHECK_FALSE(interval.own(1005));
    interval.exclude(1002,1003);CHECK_FALSE(interval.own(1002));
    interval.end=1200;CHECK_FALSE(interval.bounded(128));
    interval.exclude(10,9);CHECK_FALSE(interval.complete);
}
TEST_CASE("wounds preserve positive observations while anatomy payload truncates independently") {
    Assembler a;auto r=record(1);r.defender=9;REQUIRE(a.begin(r));
    Assembler::Wound first;first.id=0;first.victim=9;first.severed=true;first.parts.resize(100);
    Assembler::Wound second;second.id=1;second.victim=9;second.parts.resize(100);
    a.wound(1,first);a.wound(1,first);a.wound(1,second);
    REQUIRE(a.end(1,true,0,true));const auto& out=a.records()[0];
    CHECK(out.wounds_complete);REQUIRE(out.wounds.size()==2);CHECK(out.wounds[0].severed);
    CHECK(out.wounds[0].parts.size()==100);CHECK(out.wounds[0].parts_complete);
    CHECK(out.wounds[1].parts.size()==28);CHECK_FALSE(out.wounds[1].parts_complete);
}
