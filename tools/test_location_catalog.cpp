#include "doctest.h"
#include "../bridge/plugin/location_catalog.h"
namespace area=df3d_area;
using K=area::ReligiousPracticeKind;

TEST_CASE("Location religions preserve native first-seen ordering and identity namespaces") {
  // Native090656/091417 establish civ first, then eligible unit deity/member
  // links. Repeated religious links must not duplicate choices or reorder them.
  const auto result=area::locationReligiousPractices({483,482,483},{
    {true,true,{482,282,35},{430}},
    {true,false,{999},{999}},
    {false,true,{998},{998}},
    {true,true,{17,282},{430,282}}
  });
  REQUIRE(result.has_value());
  const std::vector<area::ReligiousPractice> expected{
    {K::None,-1},{K::Deity,483,0},{K::Deity,482,1},{K::Deity,282,2},
    {K::Deity,35,1},{K::Religion,430,2},{K::Deity,17,1},{K::Religion,282,1}};
  CHECK(*result==expected);
}

TEST_CASE("Worshipper counts count an eligible unit once per practice") {
  const auto result=area::locationReligiousPractices({7},{{true,true,{7,7},{7,7}},{true,false,{7},{7}}});
  REQUIRE(result.has_value());
  REQUIRE(result->size()==3);
  CHECK((*result)[0].worshippers==0);
  CHECK((*result)[1].worshippers==1);
  CHECK((*result)[2].worshippers==1);
}

TEST_CASE("Guild ranges preserve native stone and craft profession exceptions") {
  // Controlled native093440:6/7 contribute to Stoneworker5;126/127 do not
  // contribute to Craftsman25. Primary profession only; excluded units inert.
  const auto result=area::locationGuildWorkers({{5,9},{8,8},{25,36}},
    {{true,true,6},{true,true,7},{true,true,8},{true,true,26},
     {true,true,126},{true,true,127},{false,true,8},{true,false,26}});
  REQUIRE(result.has_value());REQUIRE(result->size()==3);
  CHECK((*result)[0].profession==5);CHECK((*result)[0].workers==3);
  CHECK((*result)[1].workers==1);CHECK((*result)[2].workers==1);
  CHECK_FALSE(area::locationGuildWorkers({{5,4}},{}).has_value());
  CHECK_FALSE(area::locationGuildWorkers({{5,9},{5,9}},{}).has_value());
}

TEST_CASE("Location catalog does not manufacture partial choices from invalid observations") {
  const auto empty=area::locationReligiousPractices({},{});
  REQUIRE(empty.has_value());
  CHECK(*empty==std::vector<area::ReligiousPractice>{{K::None,-1}});
  CHECK_FALSE(area::locationReligiousPractices({-1},{}).has_value());
  CHECK_FALSE(area::locationReligiousPractices({1},{{true,true,{2},{-1}}}).has_value());
  // Excluded units do not supply choices and need not have link observations.
  CHECK(area::locationReligiousPractices({},{{false,true,{-1},{}},{true,false,{}, {-1}}}).has_value());
}
