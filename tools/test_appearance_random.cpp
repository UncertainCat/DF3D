#include "doctest.h"
#include "../bridge/plugin/appearance_random.h"

TEST_CASE("Native unit appearance seeds select the observed HEAD layers") {
    // Protected225411 native cached sprites, independent four-way pixel survey.
    // Corpus/provenance: fixtures/areas/native_location_staff_variants.json.
    const struct { uint32_t seed; int32_t head; } samples[] = {
        {2326521738u,2},{2896660398u,3},{2761052u,2},{2187532448u,1},
        {2922069844u,2},{68403368u,2},{2051436528u,1},{1918080274u,3},
        {2452092014u,3},{3883667634u,4}};
    for (auto sample : samples)
        CHECK(df3d_appearance::nativeRandomPart(sample.seed,"HEAD",4)==sample.head);
}
