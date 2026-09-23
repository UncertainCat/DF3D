#include "doctest.h"
#include "../presentations/godot/extension/src/layout_causal_probe.h"

TEST_CASE("layout causal probe attributes tile changes and bounds its journal") {
    df3d_godot::LayoutCausalProbe probe;
    probe.begin(false,1,1,false,false);
    probe.item({1,2,3});probe.arrival({1,2,3});probe.applied({1,2,3},100,1,100);probe.finish();
    CHECK((probe.rows.empty() && probe.causes.empty()));
    probe.begin(true,10,2,false,false);
    probe.arrival({1,2,3});probe.item({1,2,3});
    probe.applied({1,2,3},1400,1,1400);probe.finish();
    REQUIRE(probe.rows.size()==1);
    CHECK((probe.rows[0].changedItems==1400 && probe.rows[0].tiles[0].causes.unitArrivals==1));
    CHECK(probe.rows[0].tiles[0].causes.itemUpdates==1);
    probe.begin(true,20,3,false,false);
    probe.departure({1,2,3});probe.applied({1,2,3},1400,0,1400);probe.finish();
    REQUIRE(probe.rows.size()==2);
    CHECK((probe.rows[1].tiles[0].causes.unitArrivals==0 && probe.rows[1].tiles[0].causes.unitDepartures==1));
    for(int frame=0;frame<40;++frame) {
        probe.begin(true,30+frame,4+frame,false,true);
        for(int tile=0;tile<20;++tile)probe.applied({1,tile,0},100,0,tile);
        probe.finish();
    }
    CHECK(probe.rows.size()==probe.Limit);
    for(const auto& row:probe.rows)CHECK(row.tiles.size()<=probe.TileLimit);
    CHECK(probe.rows[0].changedItems==1400);
}
