#include "doctest.h"
#include <vector>
#include "../../external/dfhack/library/modules/CombatContactProfile.h"
using namespace DFHack::Combat;
TEST_CASE("native contact guard rejects unsupported identity and every changed entry byte") {
    for(auto bytes:{std::vector<unsigned char>(Profile::attack.begin(),Profile::attack.end()),std::vector<unsigned char>(Profile::copy.begin(),Profile::copy.end())}) {
        auto expected=bytes;
        CHECK(Profile::matches(Profile::timestamp,Profile::image_size,bytes.data(),expected.data(),bytes.size()));
        CHECK_FALSE(Profile::matches(Profile::timestamp+1,Profile::image_size,bytes.data(),expected.data(),bytes.size()));
        CHECK_FALSE(Profile::matches(Profile::timestamp,Profile::image_size+1,bytes.data(),expected.data(),bytes.size()));
        for(size_t i=0;i<bytes.size();++i) {
            bytes[i]^=1;
            CHECK_FALSE(Profile::matches(Profile::timestamp,Profile::image_size,bytes.data(),expected.data(),bytes.size()));
            bytes[i]^=1;
        }
    }
    CHECK_FALSE(Profile::matches(Profile::timestamp,Profile::image_size,nullptr,Profile::attack.data(),Profile::attack.size()));
}
