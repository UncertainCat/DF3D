// Bridge policies remain testable without DF or an engine.
#include <doctest.h>
#include <initializer_list>
#include "../../bridge/plugin/item_visibility_policy.h"

using namespace df3d_bridge;

TEST_CASE("new workshop output is map-visible without the on-ground flag") {
    MapItemPlacement bed;
    bed.positionValid = true;
    CHECK_FALSE(mapItemEligible(bed));
    bed.storage = TemporaryStorage::WorkshopVisible;
    CHECK_FALSE(mapItemEligible(bed)); // A holder reference alone is insufficient.
    bed.holderPositionValid = true;
    CHECK(mapItemEligible(bed));

    for (auto storage : {TemporaryStorage::None, TemporaryStorage::WorkshopHidden,
                         TemporaryStorage::Permanent, TemporaryStorage::OtherBuilding}) {
        bed.storage = storage;
        CHECK_FALSE(mapItemEligible(bed));
    }
}

TEST_CASE("map output disappears when carried or consumed into a building") {
    for (bool ground : {false, true}) {
        MapItemPlacement item;
        item.onGround = ground;
        item.positionValid = true;
        item.storage = TemporaryStorage::WorkshopVisible;
        item.holderPositionValid = true;
        REQUIRE(mapItemEligible(item));
        for (auto flag : {&MapItemPlacement::inInventory, &MapItemPlacement::inBuilding,
                          &MapItemPlacement::removed, &MapItemPlacement::garbageCollect}) {
            auto unavailable = item;
            unavailable.*flag = true;
            CHECK_FALSE(mapItemEligible(unavailable));
        }
        item.positionValid = false;
        CHECK_FALSE(mapItemEligible(item));
    }
}

TEST_CASE("ordinary ground items do not require a workshop holder") {
    MapItemPlacement item;
    item.onGround = true;
    item.positionValid = true;
    CHECK(mapItemEligible(item));
    item.onGround = false;
    CHECK_FALSE(mapItemEligible(item));
}

TEST_CASE("pausing flushes new output discovery once without advancing ticks") {
    PauseTransitionTracker pause;
    CHECK_FALSE(pause.observe(false, false));
    CHECK_FALSE(pause.observe(true, true)); // Initial attach already gets a Full.
    CHECK_FALSE(pause.observe(true, true));
    CHECK_FALSE(pause.observe(true, false));
    CHECK_FALSE(pause.observe(true, false));
    CHECK(pause.observe(true, true)); // Native pause and DF3D pause share this path.
    for (int update = 0; update < 100; ++update)
        CHECK_FALSE(pause.observe(true, true));
    CHECK_FALSE(pause.observe(true, false));
    CHECK(pause.observe(true, true));
    CHECK_FALSE(pause.observe(false, false));
    CHECK_FALSE(pause.observe(true, true)); // Prior world's pause history is gone.
}
