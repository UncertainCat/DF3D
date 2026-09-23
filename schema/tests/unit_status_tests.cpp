#include "doctest.h"
#include "unit_status_rules.h"
using namespace df3d::unit_status;
TEST_CASE("fortress status needs use native overhead thresholds") {
    CHECK(needs(49999,24999,57599)==0);
    CHECK(needs(50000,24999,57599)==Hungry);
    CHECK(needs(49999,25000,57599)==Thirsty);
    CHECK(needs(49999,24999,57600)==Drowsy);
    CHECK(needs(75000,50000,150000)==(Hungry|Thirsty|Drowsy));
}
TEST_CASE("fortress distraction handles zero denominator and wide multiplication") {
    CHECK(focus(9999,81,100)==0);
    CHECK(focus(10000,81,100)==Stressed);
    CHECK(focus(0,80,100)==Distracted);
    CHECK(focus(0,-1,0)==0);
    CHECK(focus(0,2000000000,2000000000)==0);
    CHECK(focus(0,-100,100)==Distracted);
}
TEST_CASE("native injury severity separates major impairment from minor damage") {
    CHECK(injury(2,2,2,2,false,1000,1000,false)==0);
    CHECK(injury(1,2,2,2,false,1000,1000,false)==MinorInjury);
    CHECK(injury(0,2,2,2,false,1000,1000,false)==MajorInjury);
    CHECK(injury(2,2,2,2,false,500,1000,false)==0);
    CHECK(injury(2,2,2,2,false,499,1000,false)==MinorInjury);
    CHECK(injury(2,2,2,2,false,250,1000,false)==MinorInjury);
    CHECK(injury(2,2,2,2,false,249,1000,false)==MajorInjury);
    CHECK(injury(2,2,1,2,false,1000,1000,false)==MajorInjury);
    CHECK(injury(2,2,1,2,true,1000,1000,false)==0);
    CHECK(injury(0,0,0,0,false,0,0,false)==0);
    CHECK(injury(2,2,2,2,false,1000,1000,true)==MajorInjury);
}
