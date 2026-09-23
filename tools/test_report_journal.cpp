#include "doctest.h"
#include "../bridge/plugin/report_journal.h"
using namespace df3d_events;
namespace {
ReportObservation report(int id,uint64_t tick=100) {
    ReportObservation e;e.reportId=id;e.tick=tick;e.type="COMBAT_PARRY";return e;
}
}

TEST_CASE("report journal observes each native report once within bounded capacity") {
    ReportJournal j;j.reset(40);
    CHECK_MESSAGE(!j.observe(report(39),false),"attach baseline suppresses historical reports");
    CHECK_MESSAGE(j.observe(report(41),false),"new report is observed");
    CHECK_MESSAGE(!j.observe(report(41),false),"repeat poll cannot replay a report");
    CHECK_MESSAGE(!j.observe(report(42),true),"wrapped continuation does not trigger again");
    auto repeated=report(43);repeated.repeatCount=9;j.observe(repeated,false);
    REQUIRE_MESSAGE((j.records.size()==2 && j.records.back().id==2),"ignored lines do not allocate event IDs");
    CHECK_MESSAGE(j.records.back().repeatCount==9,"native repeat count survives without multiplying events");
    for(int i=44;i<600;++i) j.observe(report(i),false);
    CHECK_MESSAGE((j.records.size()==512 && j.dropped==46),"journal capacity reports evictions");
    j.expire(701);CHECK_MESSAGE(j.records.empty(),"age retirement is bounded");
    CHECK_MESSAGE(j.dropped==46,"normal expiry does not count as overflow");
    j.reset(99);CHECK_MESSAGE((j.records.empty() && j.nextId==1 && j.dropped==0),"new session clears journal and counters");
    REQUIRE_MESSAGE(j.observe(report(100,1),false),"new session observes again");
    CHECK_MESSAGE(j.records.front().id==1,"new session restarts identities");
}
