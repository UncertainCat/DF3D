#include "doctest.h"
#include "../bridge/plugin/fortress_population.h"
#include <numeric>
#include <vector>

TEST_CASE("fortress population census is complete or absent") {
    auto identity=[](int category) { return category; };
    auto empty=df3d_session::fortressPopulation(std::vector<int>{},identity);
    CHECK_MESSAGE((empty && empty->population==0 && empty->stress==std::array<uint32_t,7>{}),
          "empty fortress is available, with zero totals");
    auto census=df3d_session::fortressPopulation(std::vector<int>{6,0,3,6,2,1,5,4},identity);
    CHECK_MESSAGE((census && census->population==8 && census->stress==std::array<uint32_t,7>{1,1,1,1,1,1,2}),
          "every person contributes once, semantic stress order preserved");
    CHECK_MESSAGE((!df3d_session::fortressPopulation(std::vector<int>{0,1,-1,6},identity)),
          "negative category invalidates partial census");
    CHECK_MESSAGE((!df3d_session::fortressPopulation(std::vector<int>{6,7},identity)),
          "unknown category invalidates partial census");
    // Recorded living citizen+resident categories, paused frame 0,
    // gameplay-e92320f2d24d. No names or game graphics are fixture inputs.
    const std::array<uint32_t,7> recorded{6,8,21,39,27,18,58};
    std::vector<int> people;
    for (int category=0; category<7; ++category)
        people.insert(people.end(),recorded[category],category);
    auto full=df3d_session::fortressPopulation(people,identity);
    REQUIRE_MESSAGE((full && full->population==177 && full->stress==recorded),
          "recorded resident-inclusive semantic census");
    CHECK_MESSAGE(std::accumulate(full->stress.begin(),full->stress.end(),uint32_t(0))==uint32_t(full->population),
          "stress and population share one denominator");
}
